#!/usr/bin/env bash

websocket_manage() {
  local cfg="$NP_ETC/websocket.env"
  local p t np nt o

  while true; do
    header 'WEBSOCKET SSH'

    p=$(awk -F= '$1=="PORT" {print $2; exit}' "$cfg" 2>/dev/null || true)
    p=${p:-80}
    t=$(awk -F= '$1=="TARGET" {sub(/^[^=]*=/, ""); print; exit}' "$cfg" 2>/dev/null || true)
    t=${t:-127.0.0.1:22}

    echo "PORTA: $p  DESTINO: $t"
    echo '1) Instalar/configurar'
    echo '2) Reiniciar'
    echo '3) Parar'
    echo '4) Status/Logs'
    echo '5) Remover'
    echo '0) Voltar'
    read -r -p 'Opção: ' o

    case "$o" in
      1)
        read -r -p "Porta [$p]: " np
        np=${np:-$p}
        require_free_port "$np" nexus-websocket || { pause; continue; }

        read -r -p "Destino [$t]: " nt
        nt=${nt:-$t}
        [[ $nt =~ ^[^:]+:[0-9]+$ ]] || { warn 'Destino inválido.'; pause; continue; }

        install -d -m 0755 "$NP_ETC"
        printf 'PORT=%s\nTARGET=%s\n' "$np" "$nt" >"$cfg"

        cat >/etc/systemd/system/nexus-websocket.service <<UNIT
[Unit]
Description=NexusPlus WebSocket SSH proxy
After=network.target

[Service]
EnvironmentFile=$cfg
ExecStart=/usr/bin/python3 /opt/nexusplus/services/nexus_ws.py --listen 0.0.0.0:\${PORT} --target \${TARGET}
Restart=on-failure
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT

        systemctl daemon-reload
        if systemctl enable --now nexus-websocket; then
          ufw allow "$np/tcp" 2>/dev/null || true
          ok "WebSocket SSH ativo na porta $np."
        else
          warn 'O serviço não iniciou. Consulte Status/Logs.'
        fi
        pause
        ;;
      2)
        systemctl restart nexus-websocket 2>/dev/null || warn 'WebSocket ainda não está instalado.'
        pause
        ;;
      3)
        systemctl stop nexus-websocket 2>/dev/null || true
        pause
        ;;
      4)
        systemctl status nexus-websocket --no-pager 2>/dev/null || true
        journalctl -u nexus-websocket -n 80 --no-pager 2>/dev/null || true
        pause
        ;;
      5)
        systemctl disable --now nexus-websocket 2>/dev/null || true
        rm -f /etc/systemd/system/nexus-websocket.service "$cfg"
        systemctl daemon-reload
        ok 'WebSocket removido.'
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

socks_manage() {
  header 'PROXY SOCKS SSH'
  warn 'O servidor SSH já oferece encaminhamento dinâmico SOCKS ao cliente.'
  warn 'Não é instalado um proxy SOCKS aberto na VPS por segurança.'
  echo 'Use no cliente: ssh -D PORTA usuario@servidor'
  pause
}
