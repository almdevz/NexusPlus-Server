#!/usr/bin/env bash
# APP ONLINE: mostra os usuários SSH criados, conexões ativas e limite.
source /opt/nexusplus/lib/common.sh
source /opt/nexusplus/lib/users.sh

session_count(){
    local user=${1:-}
    [[ -n "$user" ]] || { echo 0; return; }
    ps -eo user=,args= 2>/dev/null |
        awk -v u="$user" '$1==u && ($0 ~ /sshd:/ || $0 ~ /dropbear/){n++} END{print n+0}'
}

managed_users(){
    local emitted=0 u
    if [[ -s "$LIMITS" ]]; then
        while IFS='=' read -r u _; do
            [[ -n "$u" ]] || continue
            id "$u" >/dev/null 2>&1 || continue
            printf '%s\n' "$u"
            emitted=1
        done < "$LIMITS"
    fi
    if ((emitted==0)); then
        while IFS=: read -r u _ uid _; do
            ((uid>=1000 && uid<60000)) || continue
            printf '%s\n' "$u"
        done </etc/passwd
    fi | sort -u
}

show_app_online(){
    header 'NEXUSPLUS — APP ONLINE'
    local u n lim found=0
    while read -r u; do
        [[ -n "$u" ]] || continue
        n=$(session_count "$u")
        lim=$(get_kv "$LIMITS" "$u" 1)
        echo -e "${CYAN}Usuário:${NC} ${YELLOW}${u}${NC}"
        if ((n>0)); then
            echo -e "${CYAN}Conexões:${NC} ${GREEN}${n} CONECTADO${NC}"
        else
            echo -e "${CYAN}Conexões:${NC} ${RED}0 DESCONECTADO${NC}"
        fi
        echo -e "${CYAN}Limite:${NC} ${YELLOW}${lim}${NC}"
        echo -e "${BLUE}──────────────────────────────────────────────${NC}"
        found=1
    done < <(managed_users)
    ((found)) || echo 'Nenhum usuário SSH criado.'
    echo
    echo 'Atualização automática a cada 2 segundos. Pressione Ctrl+C para voltar.'
}

app_online_live(){
    trap 'trap - INT TERM; return' INT TERM
    while true; do
        show_app_online
        sleep 2
    done
}

app_online_once(){ show_app_online; pause; }

# A opção APP Online abre diretamente o monitor, como no SSHPLUS.
app_online_menu(){ app_online_live; }
