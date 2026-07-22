#!/usr/bin/env bash
openvpn_manage(){
 while true; do header 'OPENVPN'; local p proto;p=$(grep -E '^port ' /etc/openvpn/server/nexus.conf 2>/dev/null|awk '{print $2}');p=${p:-1194};proto=$(grep -E '^proto ' /etc/openvpn/server/nexus.conf 2>/dev/null|awk '{print $2}');proto=${proto:-udp};echo "PORTA: $p PROTOCOLO: $proto";echo '1) Instalar/configurar servidor';echo '2) Criar cliente';echo '3) Revogar cliente';echo '4) Reiniciar';echo '5) Parar';echo '6) Status/Logs';echo '7) Remover';echo '0) Voltar';read -r -p 'Opção: ' o
 case $o in
 1)read -r -p "Porta [$p]: " np;np=${np:-$p};require_free_port "$np" openvpn||{ pause;continue;};read -r -p "Protocolo udp/tcp [$proto]: " nproto;nproto=${nproto:-$proto};[[ $nproto == udp || $nproto == tcp ]]||{ warn 'Protocolo inválido';pause;continue;};apt-get install -y openvpn easy-rsa;install -d -m 0700 /etc/openvpn/easy-rsa;cp -a /usr/share/easy-rsa/. /etc/openvpn/easy-rsa/;cd /etc/openvpn/easy-rsa;export EASYRSA_BATCH=1;[[ -d pki ]]||./easyrsa init-pki;[[ -f pki/ca.crt ]]||./easyrsa build-ca nopass;[[ -f pki/issued/server.crt ]]||./easyrsa build-server-full server nopass;[[ -f pki/dh.pem ]]||./easyrsa gen-dh;openvpn --genkey secret pki/ta.key 2>/dev/null||openvpn --genkey --secret pki/ta.key;install -d /etc/openvpn/server;cat >/etc/openvpn/server/nexus.conf <<OV
port $np
proto $nproto
dev tun
user nobody
group nogroup
persist-key
persist-tun
keepalive 10 120
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /var/log/openvpn/ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/server.crt
key /etc/openvpn/easy-rsa/pki/private/server.key
dh /etc/openvpn/easy-rsa/pki/dh.pem
tls-auth /etc/openvpn/easy-rsa/pki/ta.key 0
auth SHA256
cipher AES-256-GCM
ncp-ciphers AES-256-GCM:AES-128-GCM
verb 3
explicit-exit-notify 1
OV
install -d /var/log/openvpn;cat >/etc/sysctl.d/98-nexusplus-openvpn.conf <<SYS
net.ipv4.ip_forward=1
SYS
sysctl --system >/dev/null;cat >/etc/systemd/system/nexus-openvpn-nat.service <<UNIT
[Unit]
Description=NexusPlus OpenVPN NAT
After=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j MASQUERADE'
ExecStop=/bin/sh -c 'iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null || true'
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload;systemctl enable --now openvpn-server@nexus nexus-openvpn-nat;ufw allow "$np/$nproto" 2>/dev/null||true;ok 'OpenVPN instalado';pause;;
 2)read -r -p 'Nome do cliente: ' c;valid_user "$c"||{ warn 'Nome inválido';pause;continue;};cd /etc/openvpn/easy-rsa;EASYRSA_BATCH=1 ./easyrsa build-client-full "$c" nopass;local host;read -r -p 'IP ou domínio público: ' host;local out="/root/${c}.ovpn";cat >"$out" <<CL
client
dev tun
proto $proto
remote $host $p
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
verb 3
<ca>
$(cat pki/ca.crt)
</ca>
<cert>
$(sed -ne '/BEGIN CERTIFICATE/,$p' pki/issued/$c.crt)
</cert>
<key>
$(cat pki/private/$c.key)
</key>
<tls-auth>
$(cat pki/ta.key)
</tls-auth>
key-direction 1
CL
ok "Cliente criado: $out";pause;;
 3)read -r -p 'Cliente: ' c;cd /etc/openvpn/easy-rsa;EASYRSA_BATCH=1 ./easyrsa revoke "$c";EASYRSA_BATCH=1 ./easyrsa gen-crl;cp pki/crl.pem /etc/openvpn/server/crl.pem;grep -q '^crl-verify ' /etc/openvpn/server/nexus.conf||echo 'crl-verify /etc/openvpn/server/crl.pem'>>/etc/openvpn/server/nexus.conf;systemctl restart openvpn-server@nexus;pause;;
 4)systemctl restart openvpn-server@nexus;pause;;5)systemctl stop openvpn-server@nexus;pause;;6)systemctl status openvpn-server@nexus --no-pager||true;journalctl -u openvpn-server@nexus -n 100 --no-pager;pause;;7)systemctl disable --now openvpn-server@nexus nexus-openvpn-nat 2>/dev/null||true;rm -rf /etc/openvpn/server/nexus.conf /etc/openvpn/easy-rsa /etc/systemd/system/nexus-openvpn-nat.service /etc/sysctl.d/98-nexusplus-openvpn.conf;systemctl daemon-reload;pause;;0)return;;esac;done
}
