#!/usr/bin/env bash
slowdns_manage(){
 while true; do header 'SLOWDNS / DNSTT';local cfg=$NP_ETC/dnstt.env;domain=$(grep '^DOMAIN=' "$cfg" 2>/dev/null|cut -d= -f2-);port=$(grep '^PORT=' "$cfg" 2>/dev/null|cut -d= -f2);port=${port:-53};echo "DOMÍNIO: ${domain:-não configurado} PORTA UDP: $port";echo '1) Instalar/configurar';echo '2) Reiniciar';echo '3) Parar';echo '4) Status/Logs';echo '5) Remover';echo '0) Voltar';read -r -p 'Opção: ' o
 case $o in 1)read -r -p 'Domínio delegado (ex: ns1.exemplo.com): ' d;[[ $d =~ ^[A-Za-z0-9.-]+$ ]]||{ warn 'Domínio inválido';pause;continue;};read -r -p "Porta UDP [$port]: " np;np=${np:-$port};require_free_port "$np" dnstt||{ pause;continue;};apt-get install -y git golang-go;local src=/usr/local/src/dnstt;rm -rf "$src";git clone --depth 1 https://www.bamsoftware.com/git/dnstt.git "$src";cd "$src";go build -trimpath -ldflags='-s -w' -o /usr/local/bin/dnstt-server ./dnstt-server;[[ -s /etc/nexusplus/dnstt-server.key ]]||dnstt-server -gen-key -privkey-file /etc/nexusplus/dnstt-server.key -pubkey-file /etc/nexusplus/dnstt-server.pub;printf 'DOMAIN=%s\nPORT=%s\nTARGET=127.0.0.1:22\n' "$d" "$np">"$cfg";cat >/etc/systemd/system/nexus-dnstt.service <<UNIT
[Unit]
Description=NexusPlus DNSTT server
After=network.target
[Service]
EnvironmentFile=$cfg
ExecStart=/usr/local/bin/dnstt-server -udp :\${PORT} -privkey-file /etc/nexusplus/dnstt-server.key \${DOMAIN} \${TARGET}
Restart=on-failure
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload;systemctl enable --now nexus-dnstt;ufw allow "$np/udp" 2>/dev/null||true;ok 'DNSTT instalado. Configure os registros NS/A no DNS.';echo "Chave pública: $(cat /etc/nexusplus/dnstt-server.pub)";pause;;2)systemctl restart nexus-dnstt;pause;;3)systemctl stop nexus-dnstt;pause;;4)systemctl status nexus-dnstt --no-pager||true;journalctl -u nexus-dnstt -n 100 --no-pager;pause;;5)systemctl disable --now nexus-dnstt 2>/dev/null||true;rm -f /etc/systemd/system/nexus-dnstt.service /usr/local/bin/dnstt-server "$cfg" /etc/nexusplus/dnstt-server.key /etc/nexusplus/dnstt-server.pub;systemctl daemon-reload;pause;;0)return;;esac;done
}
