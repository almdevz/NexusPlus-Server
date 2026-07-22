#!/usr/bin/env bash
badvpn_manage(){
 while true; do header 'BADVPN UDPGW';local p;p=$(grep '^PORT=' "$NP_ETC/badvpn.env" 2>/dev/null|cut -d= -f2);p=${p:-7300};echo "PORTA UDPGW: $p";echo '1) Compilar/instalar/configurar';echo '2) Reiniciar';echo '3) Parar';echo '4) Status/Logs';echo '5) Remover';echo '0) Voltar';read -r -p 'Opção: ' o
 case $o in 1)read -r -p "Porta [$p]: " np;np=${np:-$p};require_free_port "$np" badvpn||{ pause;continue;};apt-get install -y git cmake build-essential;local src=/usr/local/src/badvpn;rm -rf "$src";git clone --depth 1 https://github.com/ambrop72/badvpn.git "$src";cmake -S "$src" -B "$src/build" -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1;cmake --build "$src/build" -j"$(nproc)";install -m 0755 "$src/build/udpgw/badvpn-udpgw" /usr/local/bin/badvpn-udpgw;printf 'PORT=%s\n' "$np">"$NP_ETC/badvpn.env";cat >/etc/systemd/system/nexus-badvpn.service <<UNIT
[Unit]
Description=NexusPlus BadVPN UDPGW
After=network.target
[Service]
EnvironmentFile=$NP_ETC/badvpn.env
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:\${PORT} --max-clients 256 --max-connections-for-client 8
Restart=on-failure
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload;systemctl enable --now nexus-badvpn;ok 'BadVPN instalado em loopback para uso por túneis SSH.';pause;;2)systemctl restart nexus-badvpn;pause;;3)systemctl stop nexus-badvpn;pause;;4)systemctl status nexus-badvpn --no-pager||true;journalctl -u nexus-badvpn -n 100 --no-pager;pause;;5)systemctl disable --now nexus-badvpn 2>/dev/null||true;rm -f /etc/systemd/system/nexus-badvpn.service /usr/local/bin/badvpn-udpgw "$NP_ETC/badvpn.env";systemctl daemon-reload;pause;;0)return;;esac;done
}
