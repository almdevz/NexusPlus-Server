#!/usr/bin/env bash
source /opt/nexusplus/lib/common.sh
for m in "$NP_MODULES"/*.sh; do [[ -r "$m" ]] && source "$m"; done

conn_status(){
  local unit=$1
  if systemctl is-active --quiet "$unit" 2>/dev/null; then printf 'ATIVO';
  elif systemctl cat "$unit" >/dev/null 2>&1; then printf 'PARADO';
  else printf 'NÃO INST.'; fi
}

env_value(){
  local file=$1 key=$2 def=${3:--} value=''
  [[ -r "$file" ]] && value=$(awk -F= -v k="$key" '$1==k{print substr($0,index($0,"=")+1);exit}' "$file" 2>/dev/null)
  printf '%s' "${value:-$def}"
}

ssh_port_menu(){ local p; p=$(sshd -T 2>/dev/null | awk '$1=="port"{print $2;exit}'); printf '%s' "${p:-22}"; }
squid_port_menu(){ local p; p=$(awk '/^http_port[[:space:]]/{print $2;exit}' /etc/squid/squid.conf 2>/dev/null); printf '%s' "${p:-3128}"; }
dropbear_port_menu(){ local p; p=$(awk -F= '/^DROPBEAR_PORT=/{print $2;exit}' /etc/default/dropbear 2>/dev/null); printf '%s' "${p:-109}"; }
stunnel_port_menu(){ local mode=$1 def=$2 p; p=$(awk -F= '/^accept[[:space:]]*=/{gsub(/[[:space:]]/,"",$2);print $2;exit}' "/etc/stunnel/nexus-stunnel-${mode}.conf" 2>/dev/null); p=${p##*:}; printf '%s' "${p:-$def}"; }
openvpn_port_menu(){ local p proto; p=$(awk '$1=="port"{print $2;exit}' /etc/openvpn/server/nexus.conf 2>/dev/null); proto=$(awk '$1=="proto"{print $2;exit}' /etc/openvpn/server/nexus.conf 2>/dev/null); printf '%s/%s' "${p:-1194}" "${proto:-udp}"; }
xhttp_port_menu(){ local p; p=$(jq -r '(.listen_port // (.listen // "" | capture(":(?<p>[0-9]+)$").p) // empty)' /etc/nexus-xhttp/server.json 2>/dev/null | head -n1); printf '%s' "${p:-8443}"; }

conn_row(){ printf '[%02d] %-20s Porta: %-10s %s\n' "$1" "$2" "$3" "$4"; }

connection_menu(){
  while true; do
    header 'MODO DE CONEXÃO — PORTAS E STATUS'
    conn_row 1  'OpenSSH'          "$(ssh_port_menu)"                    "$(conn_status ssh)"
    conn_row 2  'Squid Proxy'      "$(squid_port_menu)"                  "$(conn_status squid)"
    conn_row 3  'Dropbear'         "$(dropbear_port_menu)"               "$(conn_status dropbear)"
    conn_row 4  'Proxy SOCKS SSH'  '-'                                     'VIA CLIENTE SSH'
    conn_row 5  'WebSocket SSH'    "$(env_value "$NP_ETC/websocket.env" PORT 80)" "$(conn_status nexus-websocket)"
    conn_row 6  'SSL Tunnel'       "$(stunnel_port_menu tunnel 444)"      "$(conn_status nexus-stunnel-tunnel)"
    conn_row 7  'SSL Proxy'        "$(stunnel_port_menu proxy 443)"       "$(conn_status nexus-stunnel-proxy)"
    conn_row 8  'OpenVPN'          "$(openvpn_port_menu)"                 "$(conn_status openvpn-server@nexus)"
    conn_row 9  'SlowDNS/DNSTT'    "$(env_value "$NP_ETC/dnstt.env" PORT 53)/udp" "$(conn_status nexus-dnstt)"
    conn_row 10 'BadVPN UDPGW'     "$(env_value "$NP_ETC/badvpn.env" PORT 7300)" "$(conn_status nexus-badvpn)"
    conn_row 11 'Chisel'           "$(env_value "$NP_ETC/chisel.env" PORT 8080)" "$(conn_status nexus-chisel)"
    conn_row 12 'Nexus SSH_XHTTP'  "$(xhttp_port_menu)"                   "$(conn_status nexus-xhttp)"
    echo '[00] Voltar'
    read -r -p 'Opção: ' o
    case $o in
      1|01)openssh_manage;;2|02)squid_manage;;3|03)dropbear_manage;;4|04)socks_manage;;5|05)websocket_manage;;6|06)stunnel_manage tunnel;;7|07)stunnel_manage proxy;;8|08)openvpn_manage;;9|09)slowdns_manage;;10)badvpn_manage;;11)chisel_manage;;12)xhttp_menu;;0|00)return;;*)warn 'Inválida';sleep 1;;
    esac
  done
}
