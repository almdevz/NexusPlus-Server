#!/usr/bin/env bash
# Monitor de conexões por protocolo/porta para o NexusPlus.
# shellcheck source=common.sh
source /opt/nexusplus/lib/common.sh

count_established_on_port() {
    local port=${1:-}
    valid_port "$port" || { echo 0; return; }
    ss -Htn state established 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" {n++} END{print n+0}'
}

remote_ips_on_port() {
    local port=${1:-}
    valid_port "$port" || return 0
    ss -Htn state established 2>/dev/null |
        awk -v p=":${port}" '$4 ~ p"$" {r=$5; sub(/^\[/,"",r); sub(/\]$/,"",r); sub(/:[^:]+$/,"",r); print r}' |
        sort | uniq -c | sort -nr
}

dnstt_port() {
    local cfg=/etc/nexus-dnstt/server.json
    [[ -r "$cfg" ]] || return 1
    jq -r '(.public_udp_port // 53)' "$cfg" 2>/dev/null | head -n1
}

service_state() {
    local unit=$1
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        printf 'ATIVO'
    else
        printf 'INATIVO'
    fi
}

xhttp_port() {
    local cfg=/etc/nexus-xhttp/server.json
    [[ -r "$cfg" ]] || return 1
    jq -r '(.listen_port // (.listen // "" | capture(":(?<p>[0-9]+)$").p) // empty)' "$cfg" 2>/dev/null | head -n1
}

ssh_ports() {
    local ports
    ports=$(sshd -T 2>/dev/null | awk '$1=="port"{print $2}' | sort -nu)
    [[ -n "$ports" ]] || ports=22
    printf '%s\n' "$ports"
}

print_protocol_row() {
    local name=$1 port=$2 state=$3 count=$4
    printf '%-22s %-8s %-10s %-8s\n' "$name" "$port" "$state" "$count"
}

show_protocols() {
    header 'APP ONLINE — PROTOCOLOS E PORTAS'
    printf '%-22s %-8s %-10s %-8s\n' PROTOCOLO PORTA STATUS ONLINE
    printf '%-22s %-8s %-10s %-8s\n' '----------------------' '--------' '----------' '--------'

    local p c st
    while read -r p; do
        [[ -n "$p" ]] || continue
        c=$(count_established_on_port "$p")
        st=$(service_state ssh)
        [[ $st == INATIVO ]] && st=$(service_state sshd)
        print_protocol_row 'SSH DIRETO' "$p" "$st" "$c"
    done < <(ssh_ports)

    if p=$(xhttp_port) && valid_port "$p"; then
        c=$(count_established_on_port "$p")
        logical='-'; if [[ -x /usr/local/bin/nexus-xhttp-health ]]; then logical=$(/usr/local/bin/nexus-xhttp-health 2>/dev/null | jq -r '.active_sessions // "-"' 2>/dev/null || echo '-'); fi
        print_protocol_row "NEXUS XHTTP ${logical}S" "$p" "$(service_state nexus-xhttp)" "$c"
    else
        print_protocol_row 'NEXUS SSH_XHTTP' '-' 'NÃO INST.' '0'
    fi

    if p=$(dnstt_port) && valid_port "$p"; then
        local dhealth='-'
        if [[ -x /usr/local/bin/nexus-dnstt-health ]]; then
            dhealth=$(/usr/local/bin/nexus-dnstt-health 2>/dev/null | jq -r 'if .healthy then "OK" else "FALHA" end' 2>/dev/null || echo 'FALHA')
        fi
        print_protocol_row "NEXUS DNSTT $dhealth" "$p/udp" "$(service_state nexus-dnstt)" '-'
    else
        print_protocol_row 'NEXUS DNSTT' '-' 'NÃO INST.' '-'
    fi

    # Descoberta conservadora de serviços legados conhecidos. Só mostra portas realmente em escuta.
    local spec name pattern
    while IFS='|' read -r name pattern; do
        while read -r p; do
            [[ -n "$p" ]] || continue
            c=$(count_established_on_port "$p")
            print_protocol_row "$name" "$p" 'ATIVO' "$c"
        done < <(ss -Hltnp 2>/dev/null | awk -v pat="$pattern" '$0 ~ pat {a=$4; sub(/^.*:/,"",a); if(a~/^[0-9]+$/) print a}' | sort -nu)
    done <<'SERVICES'
WEBSOCKET|wsproxy|websocket|WebSocket
STUNNEL/SSL|stunnel
DROPBEAR|dropbear
SQUID/HTTP|squid
PROXY PYTHON|proxyd|proxy.py
SERVICES

    echo
    echo 'USUÁRIOS SSH AUTENTICADOS'
    printf '%-20s %-8s %-8s\n' USUÁRIO ATIVAS LIMITE
    local found=0 u uid local_count limit
    while IFS=: read -r u _ uid _; do
        ((uid>=1000 && uid<60000)) || continue
        local_count=$(pgrep -u "$u" sshd 2>/dev/null | wc -l)
        if ((local_count>0)); then
            limit=$(get_kv "$LIMITS" "$u" 1)
            printf '%-20s %-8s %-8s\n' "$u" "$local_count" "$limit"
            found=1
        fi
    done </etc/passwd
    ((found)) || echo 'Nenhum usuário SSH autenticado neste momento.'

    echo
    echo 'ORIGENS CONECTADAS AO NEXUS XHTTP'
    if p=$(xhttp_port) && valid_port "$p"; then
        local origins
        origins=$(remote_ips_on_port "$p")
        [[ -n "$origins" ]] && printf '%s\n' "$origins" || echo 'Nenhuma conexão XHTTP ativa.'
    else
        echo 'Nexus XHTTP não instalado.'
    fi

    echo
    warn 'ONLINE mostra conexões TCP físicas. No rótulo NEXUS XHTTP, o sufixo nS informa sessões lógicas retornadas pelo health check.'
}

app_online_once(){ show_protocols; pause; }

app_online_live(){
    trap 'trap - INT TERM; return' INT TERM
    while true; do
        show_protocols
        echo
        echo 'Atualização automática a cada 2 segundos. Pressione Ctrl+C para voltar.'
        sleep 2
    done
}

app_online_menu(){
    while true; do
        header 'APP ONLINE'
        echo '1) Visualização única'
        echo '2) Monitor em tempo real'
        echo '0) Voltar'
        read -r -p 'Opção: ' o
        case $o in
            1) app_online_once ;;
            2) app_online_live ;;
            0) return ;;
            *) warn 'Opção inválida'; sleep 1 ;;
        esac
    done
}
