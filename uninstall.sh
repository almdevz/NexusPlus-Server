#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Execute como root'; exit 1; }
services=(nexusplus-expiry.timer nexusplus-limiter.timer nexus-websocket nexus-stunnel-tunnel nexus-stunnel-proxy nexus-openvpn-nat nexus-dnstt nexus-badvpn nexus-chisel)
for s in "${services[@]}"; do systemctl disable --now "$s" 2>/dev/null||true; done
rm -f /etc/systemd/system/nexusplus-* /etc/systemd/system/nexus-websocket.service /etc/systemd/system/nexus-stunnel-*.service /etc/systemd/system/nexus-openvpn-nat.service /etc/systemd/system/nexus-dnstt.service /etc/systemd/system/nexus-badvpn.service /etc/systemd/system/nexus-chisel.service
rm -f /usr/local/bin/nexus /usr/local/bin/nexus-health
rm -rf /opt/nexusplus
read -r -p 'Remover configurações e dados NexusPlus? [s/N]: ' a
[[ $a =~ ^[Ss]$ ]] && rm -rf /etc/nexusplus /var/lib/nexusplus /var/log/nexusplus
systemctl daemon-reload
echo 'NexusPlus removido. Serviços de terceiros instalados via apt não foram purgados automaticamente.'
