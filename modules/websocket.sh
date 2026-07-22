#!/usr/bin/env bash
websocket_manage(){
 while true; do header 'WEBSOCKET SSH';local cfg=$NP_ETC/websocket.env;p=$(grep '^PORT=' "$cfg" 2>/dev/null|cut -d= -f2);p=${p:-80};t=$(grep '^TARGET=' "$cfg" 2>/dev/null|cut -d= -f2-);t=${t:-127.0.0.1:22};echo "PORTA: $p  DESTINO: $t";echo '1) Instalar/configurar';echo '2) Reiniciar';echo '3) Parar';echo '4) Status/Logs';echo '5) Remover';echo '0) Voltar';read -r -p 'Opção: ' o
 case $o in 1)read -r -p "Porta [$p]: " np;np=${np:-$p};require_free_port "$np" nexus-ws||{ pause;continue;};read -r -p "Destino [$t]: " nt;nt=${nt:-$t};[[ $nt =~ ^[^:]+:[0-9]+$ ]]||{ warn 'Destino inválido';pause;continue;};printf 'PORT=%s\nTARGET=%s\n' "$np" "$nt">"$cfg";cat >/etc/systemd/system/nexus-websocket.service <<UNIT
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
systemctl daemon-reload;systemctl enable --now nexus-websocket;ufw allow "$np/tcp" 2>/dev/null||true;pause;;2)systemctl restart nexus-websocket;pause;;3)systemctl stop nexus-websocket;pause;;4)systemctl status nexus-websocket --no-pager||true;journalctl -u nexus-websocket -n 80 --no-pager;pause;;5)systemctl disable --now nexus-websocket 2>/dev/null||true;rm -f /etc/systemd/system/nexus-websocket.service "$cfg";systemctl daemon-reload;pause;;0)return;;esac;done
}
socks_manage(){ header 'PROXY SOCKS SSH'; warn 'O servidor SSH já oferece encaminhamento dinâmico SOCKS ao cliente. Não é instalado um proxy SOCKS aberto na VPS por segurança.'; echo 'Use no cliente: ssh -D PORTA usuario@servidor'; pause; }
