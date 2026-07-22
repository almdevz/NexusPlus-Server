#!/usr/bin/env bash
source /opt/nexusplus/lib/common.sh
for m in "$NP_MODULES"/*.sh; do [[ -r "$m" ]] && source "$m"; done
connection_menu(){
 while true; do
  header 'MODO DE CONEXÃO — PORTAS EDITÁVEIS'
  echo '[01] OpenSSH            [07] SSL Proxy'
  echo '[02] Squid Proxy        [08] OpenVPN'
  echo '[03] Dropbear           [09] SlowDNS/DNSTT'
  echo '[04] Proxy SOCKS SSH    [10] BadVPN UDPGW'
  echo '[05] WebSocket SSH      [11] Chisel'
  echo '[06] SSL Tunnel         [12] Nexus SSH_XHTTP'
  echo '[00] Voltar'
  read -r -p 'Opção: ' o
  case $o in 1|01)openssh_manage;;2|02)squid_manage;;3|03)dropbear_manage;;4|04)socks_manage;;5|05)websocket_manage;;6|06)stunnel_manage tunnel;;7|07)stunnel_manage proxy;;8|08)openvpn_manage;;9|09)slowdns_manage;;10)badvpn_manage;;11)chisel_manage;;12)xhttp_menu;;0|00)return;;*)warn 'Inválida';sleep 1;;esac
 done
}
