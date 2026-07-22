#!/usr/bin/env bash
stunnel_manage(){
  local mode=${1:-tunnel}
  local name="nexus-stunnel-$mode"
  local cfg="/etc/stunnel/${name}.conf"
  local def=444
  [[ $mode == proxy ]] && def=443

  while true; do
    header "SSL ${mode^^}"
    local p t
    p=""
    t=""
    if [[ -f "$cfg" ]]; then
      p=$(awk -F= '/^accept/{gsub(/ /,"");print $2;exit}' "$cfg" 2>/dev/null || true)
      t=$(awk -F= '/^connect/{gsub(/ /,"");print $2;exit}' "$cfg" 2>/dev/null || true)
    fi
    p=${p##*:}
    p=${p:-$def}
    t=${t:-127.0.0.1:22}

    echo "PORTA: $p DESTINO: $t"
    echo '1) Instalar/configurar'
    echo '2) Reiniciar'
    echo '3) Parar'
    echo '4) Status/Logs'
    echo '5) Remover'
    echo '0) Voltar'
    read -r -p 'Opção: ' o

    case $o in
      1)
        local np nt
        read -r -p "Porta [$p]: " np
        np=${np:-$p}
        require_free_port "$np" stunnel || { pause; continue; }
        read -r -p "Destino [$t]: " nt
        nt=${nt:-$t}
        [[ $nt =~ ^[^:]+:[0-9]+$ ]] || { warn 'Destino inválido'; pause; continue; }

        apt-get install -y stunnel4
        install -d -m 0755 /etc/stunnel /etc/nexusplus/tls
        if [[ ! -s /etc/nexusplus/tls/fullchain.pem || ! -s /etc/nexusplus/tls/privkey.pem ]]; then
          openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
            -subj '/CN=nexusplus.local' \
            -keyout /etc/nexusplus/tls/privkey.pem \
            -out /etc/nexusplus/tls/fullchain.pem
        fi

        cat >"$cfg" <<ST
foreground = yes
pid =
cert = /etc/nexusplus/tls/fullchain.pem
key = /etc/nexusplus/tls/privkey.pem
[$mode]
accept = 0.0.0.0:$np
connect = $nt
TIMEOUTclose = 0
ST

        cat >/etc/systemd/system/${name}.service <<UNIT
[Unit]
Description=NexusPlus SSL $mode
After=network.target

[Service]
ExecStart=/usr/bin/stunnel4 $cfg
Restart=on-failure
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT
        systemctl daemon-reload
        if systemctl enable --now "$name"; then
          ufw allow "$np/tcp" 2>/dev/null || true
          ok 'SSL configurado'
        else
          warn 'Falha ao iniciar'
          systemctl status "$name" --no-pager || true
        fi
        pause
        ;;
      2)
        systemctl restart "$name" 2>/dev/null || warn 'Serviço ainda não instalado.'
        pause
        ;;
      3)
        systemctl stop "$name" 2>/dev/null || warn 'Serviço ainda não instalado.'
        pause
        ;;
      4)
        systemctl status "$name" --no-pager || true
        journalctl -u "$name" -n 80 --no-pager || true
        pause
        ;;
      5)
        systemctl disable --now "$name" 2>/dev/null || true
        rm -f "/etc/systemd/system/${name}.service" "$cfg"
        systemctl daemon-reload
        pause
        ;;
      0)
        return
        ;;
      *)
        warn 'Opção inválida.'
        sleep 1
        ;;
    esac
  done
}
