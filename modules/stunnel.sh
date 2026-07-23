#!/usr/bin/env bash

stunnel_cfg=/etc/stunnel/stunnel.conf
stunnel_cert=/etc/stunnel/cert.pem
stunnel_key=/etc/stunnel/key.pem
stunnel_pid=/run/stunnel4/stunnel.pid

stunnel_section_value(){
  local section=$1 key=$2
  [[ -r "$stunnel_cfg" ]] || return 0
  awk -v section="[$section]" -v key="$key" '
    $0==section {inside=1; next}
    /^\[/ {inside=0}
    inside && $1==key {gsub(/[[:space:]]/,"",$3); print $3; exit}
  ' "$stunnel_cfg" 2>/dev/null || true
}

stunnel_prepare_runtime(){
  install -d -m 0755 /etc/stunnel /run/stunnel4
  if [[ -f /etc/default/stunnel4 ]]; then
    if grep -q '^ENABLED=' /etc/default/stunnel4; then
      sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
    else
      printf '\nENABLED=1\n' >> /etc/default/stunnel4
    fi
  fi
}

stunnel_prepare_cert(){
  stunnel_prepare_runtime

  if [[ -s /etc/nexusplus/tls/fullchain.pem && -s /etc/nexusplus/tls/privkey.pem ]]; then
    cp -f /etc/nexusplus/tls/fullchain.pem "$stunnel_cert"
    cp -f /etc/nexusplus/tls/privkey.pem "$stunnel_key"
  elif [[ ! -s "$stunnel_cert" || ! -s "$stunnel_key" ]]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
      -subj '/CN=nexusplus.local' \
      -keyout "$stunnel_key" \
      -out "$stunnel_cert"
  fi

  chown root:root "$stunnel_cert" "$stunnel_key"
  chmod 0644 "$stunnel_cert"
  chmod 0600 "$stunnel_key"
}

stunnel_write_config(){
  local direct_port=$1 direct_target=$2 proxy_port=$3 proxy_target=$4
  local tmp backup
  stunnel_prepare_runtime
  tmp=$(mktemp /etc/stunnel/stunnel.conf.XXXXXX)
  backup="${stunnel_cfg}.backup-$(date +%Y%m%d-%H%M%S)"

  [[ -f "$stunnel_cfg" ]] && cp -a "$stunnel_cfg" "$backup"

  cat >"$tmp" <<EOF
cert = $stunnel_cert
key = $stunnel_key
client = no
foreground = no
pid = $stunnel_pid

[ssl_direto]
accept = 0.0.0.0:$direct_port
connect = $direct_target
TIMEOUTclose = 0

[ssl_websocket]
accept = 0.0.0.0:$proxy_port
connect = $proxy_target
TIMEOUTclose = 0
EOF

  if /usr/bin/stunnel4 "$tmp" -version >/dev/null 2>&1; then
    mv -f "$tmp" "$stunnel_cfg"
    return 0
  fi

  rm -f "$tmp"
  [[ -f "$backup" ]] && cp -af "$backup" "$stunnel_cfg"
  return 1
}

stunnel_restart(){
  stunnel_prepare_runtime
  rm -f "$stunnel_pid"
  systemctl daemon-reload
  systemctl enable stunnel4 >/dev/null 2>&1 || true
  systemctl restart stunnel4
}

stunnel_manage(){
  local mode=${1:-tunnel}
  local section def_port def_target label

  if [[ $mode == proxy ]]; then
    section=ssl_websocket
    def_port=443
    def_target=127.0.0.1:80
    label='SSL PROXY → WEBSOCKET'
  else
    section=ssl_direto
    def_port=444
    def_target=127.0.0.1:22
    label='SSL TUNNEL → SSH DIRETO'
  fi

  while true; do
    header "$label"

    local direct_port direct_target proxy_port proxy_target p t state
    direct_port=$(stunnel_section_value ssl_direto accept); direct_port=${direct_port##*:}; direct_port=${direct_port:-444}
    direct_target=$(stunnel_section_value ssl_direto connect); direct_target=${direct_target:-127.0.0.1:22}
    proxy_port=$(stunnel_section_value ssl_websocket accept); proxy_port=${proxy_port##*:}; proxy_port=${proxy_port:-443}
    proxy_target=$(stunnel_section_value ssl_websocket connect); proxy_target=${proxy_target:-127.0.0.1:80}

    if [[ $mode == proxy ]]; then p=$proxy_port; t=$proxy_target; else p=$direct_port; t=$direct_target; fi
    state=$(systemctl is-active stunnel4 2>/dev/null || true); state=${state:-inactive}

    echo "PORTA: $p  DESTINO: $t  STATUS: $state"
    echo '1) Instalar/configurar'
    echo '2) Reiniciar'
    echo '3) Parar'
    echo '4) Status/Logs'
    echo '5) Remover configuração SSL'
    echo '0) Voltar'
    read -r -p 'Opção: ' o

    case $o in
      1)
        local np nt
        read -r -p "Porta [$p]: " np; np=${np:-$p}
        require_free_port "$np" stunnel || { pause; continue; }
        read -r -p "Destino [$t]: " nt; nt=${nt:-$t}
        [[ $nt =~ ^[^:]+:[0-9]+$ ]] || { warn 'Destino inválido'; pause; continue; }

        apt-get install -y stunnel4 openssl
        stunnel_prepare_cert

        if [[ $mode == proxy ]]; then
          proxy_port=$np; proxy_target=$nt
        else
          direct_port=$np; direct_target=$nt
        fi

        if stunnel_write_config "$direct_port" "$direct_target" "$proxy_port" "$proxy_target" && stunnel_restart; then
          ufw allow "$np/tcp" 2>/dev/null || true
          ok "SSL configurado: $np → $nt"
        else
          warn 'Falha na configuração; rollback preservado.'
          systemctl status stunnel4 --no-pager -l || true
        fi
        pause
        ;;
      2)
        stunnel_restart || true
        pause
        ;;
      3)
        systemctl stop stunnel4 2>/dev/null || true
        pause
        ;;
      4)
        systemctl status stunnel4 --no-pager -l || true
        journalctl -u stunnel4 -n 100 --no-pager || true
        echo
        echo 'CONFIGURAÇÃO ATUAL:'
        sed -n '1,120p' "$stunnel_cfg" 2>/dev/null || true
        pause
        ;;
      5)
        systemctl disable --now stunnel4 2>/dev/null || true
        [[ -f "$stunnel_cfg" ]] && cp -a "$stunnel_cfg" "${stunnel_cfg}.backup-$(date +%Y%m%d-%H%M%S)"
        rm -f "$stunnel_cfg" "$stunnel_pid"
        ok 'Configuração SSL removida; certificados foram preservados.'
        pause
        ;;
      0) return ;;
      *) warn 'Opção inválida.'; sleep 1 ;;
    esac
  done
}
