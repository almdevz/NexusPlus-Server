#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
UPGRADE=false
SKIP_PACKAGES=false
for a in "$@"; do case "$a" in --upgrade)UPGRADE=true;;--skip-packages)SKIP_PACKAGES=true;;*)echo "Argumento desconhecido: $a" >&2;exit 2;;esac;done
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Execute como root.' >&2; exit 1; }
[[ -f "$ROOT/VERSION" ]] || { echo 'VERSION ausente.' >&2; exit 1; }
. /etc/os-release
case ${ID:-} in ubuntu|debian);;*)echo 'Somente Debian/Ubuntu.' >&2;exit 1;;esac
if ! $SKIP_PACKAGES; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server curl wget unzip tar openssl ca-certificates iproute2 procps nano jq ufw python3 util-linux iptables
fi
install -d -m 0755 /opt/nexusplus/{bin,lib,legacy,xhttp,dnstt,systemd,docs,templates,tools} /etc/nexusplus /var/lib/nexusplus /var/log/nexusplus /run/nexusplus/sessions
install -m 0644 "$ROOT/VERSION" /opt/nexusplus/VERSION
for d in bin lib xhttp dnstt systemd docs tools; do [[ -d "$ROOT/$d" ]] && cp -a "$ROOT/$d/." "/opt/nexusplus/$d/"; done
# Legacy is additive so an already installed optional package survives panel upgrades.
[[ -d "$ROOT/legacy" ]] && cp -a "$ROOT/legacy/." /opt/nexusplus/legacy/
[[ -d "$ROOT/templates" ]] && cp -a "$ROOT/templates/." /opt/nexusplus/templates/
[[ -f "$ROOT/README.md" ]] && install -m 0644 "$ROOT/README.md" /opt/nexusplus/README.md
[[ -f "$ROOT/CHANGELOG.md" ]] && install -m 0644 "$ROOT/CHANGELOG.md" /opt/nexusplus/CHANGELOG.md
chmod +x /opt/nexusplus/bin/* /opt/nexusplus/lib/*.sh /opt/nexusplus/xhttp/install-server.sh /opt/nexusplus/xhttp/nexus-xhttp-health /opt/nexusplus/dnstt/install-server.sh /opt/nexusplus/dnstt/nexus-dnstt /opt/nexusplus/dnstt/nexus-dnstt-health /opt/nexusplus/dnstt/nexus-dnstt-generate-config /opt/nexusplus/dnstt/nexus-dnstt-firewall /opt/nexusplus/dnstt/run-server
find /opt/nexusplus/templates -type f -exec chmod 0600 {} \; 2>/dev/null || true
ln -sf /opt/nexusplus/bin/nexus /usr/local/bin/nexus
ln -sf /opt/nexusplus/bin/nexus-app-online /usr/local/bin/nexus-app-online
ln -sf /opt/nexusplus/bin/nexus-generate-xhttp-config /usr/local/bin/nexus-generate-xhttp-config
ln -sf /opt/nexusplus/dnstt/nexus-dnstt /usr/local/bin/nexus-dnstt
ln -sf /opt/nexusplus/dnstt/nexus-dnstt-health /usr/local/bin/nexus-dnstt-health
ln -sf /opt/nexusplus/dnstt/nexus-dnstt-generate-config /usr/local/bin/nexus-generate-dnstt-config

mkdir -p /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-nexusplus.conf <<'SSH'
PasswordAuthentication yes
PermitRootLogin prohibit-password
AllowTcpForwarding yes
GatewayPorts no
X11Forwarding no
SSH
sshd -t
systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd

# Enforce managed-user connection limits at PAM session open. The helper fails open for unmanaged/system users.
PAM=/etc/pam.d/sshd
MARK='# NexusPlus managed connection limit v1.2'
if [[ -f "$PAM" ]] && ! grep -Fq "$MARK" "$PAM"; then
  [[ -f /etc/pam.d/sshd.nexusplus-pre-v1.2 ]] || cp -a "$PAM" /etc/pam.d/sshd.nexusplus-pre-v1.2
  printf '\n%s\nsession required pam_exec.so quiet /opt/nexusplus/bin/nexus-pam-limit\n' "$MARK" >> "$PAM"
fi

install -m 0644 "$ROOT/systemd/nexusplus-expiry.service" /etc/systemd/system/nexusplus-expiry.service
install -m 0644 "$ROOT/systemd/nexusplus-expiry.timer" /etc/systemd/system/nexusplus-expiry.timer
install -m 0644 "$ROOT/systemd/nexusplus-limit.service" /etc/systemd/system/nexusplus-limit.service
install -m 0644 "$ROOT/systemd/nexusplus-limit.timer" /etc/systemd/system/nexusplus-limit.timer

# Initialize and migrate v1.1 metadata without deleting existing users.
export NP_ROOT=/opt/nexusplus
source /opt/nexusplus/lib/common.sh
source /opt/nexusplus/lib/users.sh
migrate_v11_users

systemctl daemon-reload
systemctl enable --now nexusplus-expiry.timer nexusplus-limit.timer
/opt/nexusplus/bin/nexus-expiry --quiet || true
/opt/nexusplus/bin/nexus-limit-reconcile || true

if $UPGRADE; then
  echo "NexusPlus atualizado para $(cat /opt/nexusplus/VERSION)."
else
  echo "NexusPlus Server $(cat /opt/nexusplus/VERSION) instalado. Execute: nexus"
fi
