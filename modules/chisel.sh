#!/usr/bin/env bash
chisel_manage(){
 while true; do header 'CHISEL';local cfg=$NP_ETC/chisel.env;p=$(grep '^PORT=' "$cfg" 2>/dev/null|cut -d= -f2);p=${p:-8080};echo "PORTA: $p";echo '1) Instalar/configurar';echo '2) Reiniciar';echo '3) Parar';echo '4) Status/Logs';echo '5) Remover';echo '0) Voltar';read -r -p 'Opção: ' o
 case $o in 1)read -r -p "Porta [$p]: " np;np=${np:-$p};require_free_port "$np" chisel||{ pause;continue;};apt-get install -y golang-go;GOBIN=/usr/local/bin go install github.com/jpillora/chisel@v1.11.5;printf 'PORT=%s\n' "$np">"$cfg";cat >/etc/systemd/system/nexus-chisel.service <<UNIT
[Unit]
Description=NexusPlus Chisel server
After=network.target
[Service]
EnvironmentFile=$cfg
ExecStart=/usr/local/bin/chisel server --port \${PORT} --socks5
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/lib/nexusplus
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload;systemctl enable --now nexus-chisel;ufw allow "$np/tcp" 2>/dev/null||true;pause;;2)systemctl restart nexus-chisel;pause;;3)systemctl stop nexus-chisel;pause;;4)systemctl status nexus-chisel --no-pager||true;journalctl -u nexus-chisel -n 100 --no-pager;pause;;5)systemctl disable --now nexus-chisel 2>/dev/null||true;rm -f /etc/systemd/system/nexus-chisel.service /usr/local/bin/chisel "$cfg";systemctl daemon-reload;pause;;0)return;;esac;done
}
