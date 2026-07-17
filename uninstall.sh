#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Execute como root.' >&2; exit 1; }
if [[ -f /etc/nexus-dnstt/server.json ]]; then
  read -r -p 'Nexus DNSTT está instalado e depende do painel. Remover o módulo e continuar? [s/N]: ' d
  [[ $d =~ ^[Ss]$ ]] || { echo 'Desinstalação cancelada para preservar o DNSTT.'; exit 1; }
  /opt/nexusplus/dnstt/nexus-dnstt uninstall || exit 1
fi
systemctl disable --now nexusplus-expiry.timer nexusplus-expiry.service nexusplus-limit.timer nexusplus-limit.service 2>/dev/null || true
rm -f /etc/systemd/system/nexusplus-expiry.{timer,service} /etc/systemd/system/nexusplus-limit.{timer,service}
rm -f /usr/local/bin/nexus /usr/local/bin/nexus-app-online /usr/local/bin/nexus-generate-xhttp-config /usr/local/bin/nexus-dnstt /usr/local/bin/nexus-dnstt-health /usr/local/bin/nexus-generate-dnstt-config
if [[ -f /etc/pam.d/sshd ]]; then
  sed -i '/^# NexusPlus managed connection limit v1\.2$/d;/pam_exec\.so quiet \/opt\/nexusplus\/bin\/nexus-pam-limit/d' /etc/pam.d/sshd
fi
rm -rf /opt/nexusplus /run/nexusplus
read -r -p 'Remover configurações e estados /etc/nexusplus /var/lib/nexusplus /var/log/nexusplus? [s/N]: ' a
[[ $a =~ ^[Ss]$ ]] && rm -rf /etc/nexusplus /var/lib/nexusplus /var/log/nexusplus
systemctl daemon-reload
echo 'NexusPlus removido. Nexus XHTTP e Nexus DNSTT instalados são serviços independentes; remova-os antes com seus respectivos comandos se desejar apagar também esses módulos.'
