#!/usr/bin/env bash
squid_manage(){
 while true; do header 'GERENCIAR SQUID'; local p; p=$(awk '/^http_port/{print $2;exit}' /etc/squid/squid.conf 2>/dev/null); p=${p:-3128}; echo "PORTA: $p"; echo '1) Instalar/configurar'; echo '2) Alterar porta'; echo '3) Reiniciar'; echo '4) Parar'; echo '5) Status/Logs'; echo '6) Remover'; echo '0) Voltar'; read -r -p 'Opção: ' o
 case $o in 1|2)read -r -p "Porta [$p]: " np;np=${np:-$p};require_free_port "$np" squid||{ pause;continue;};apt-get install -y squid;local f=/etc/squid/squid.conf bak;bak="$f.bak.$(date +%s)";cp -a "$f" "$bak" 2>/dev/null||true;cat >"$f" <<SQ
http_port $np
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl Safe_ports port 80 443 1024-65535
http_access deny !Safe_ports
http_access allow localnet
http_access deny all
via off
forwarded_for delete
SQ
if squid -k parse && systemctl enable --now squid;then ufw allow "$np/tcp" 2>/dev/null||true;ok 'Squid configurado';else cp -af "$bak" "$f";systemctl restart squid 2>/dev/null||true;warn 'Rollback aplicado';fi;pause;;3)systemctl restart squid;pause;;4)systemctl stop squid;pause;;5)systemctl status squid --no-pager||true;journalctl -u squid -n 80 --no-pager;pause;;6)systemctl disable --now squid 2>/dev/null||true;apt-get purge -y squid;pause;;0)return;;esac;done
}
