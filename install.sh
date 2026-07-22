#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Execute como root.' >&2; exit 1; }
. /etc/os-release
case ${ID:-} in ubuntu|debian) ;; *) echo 'Somente Debian/Ubuntu.' >&2; exit 1;; esac
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server curl wget unzip tar openssl ca-certificates iproute2 procps nano jq ufw python3 gawk iptables
install -d -m 0755 /opt/nexusplus/{bin,lib,modules,xhttp,services} /etc/nexusplus /var/lib/nexusplus /var/log/nexusplus
cp -a "$ROOT/bin/." /opt/nexusplus/bin/
cp -a "$ROOT/lib/." /opt/nexusplus/lib/
cp -a "$ROOT/modules/." /opt/nexusplus/modules/
cp -a "$ROOT/xhttp/." /opt/nexusplus/xhttp/
cp -a "$ROOT/services/." /opt/nexusplus/services/
chmod +x /opt/nexusplus/bin/* /opt/nexusplus/lib/*.sh /opt/nexusplus/modules/*.sh /opt/nexusplus/xhttp/install-server.sh
ln -sf /opt/nexusplus/bin/nexus /usr/local/bin/nexus
ln -sf /opt/nexusplus/bin/nexus-health /usr/local/bin/nexus-health
mkdir -p /etc/ssh/sshd_config.d
if [[ -f /etc/ssh/sshd_config.d/99-nexusplus.conf ]]; then cp -a /etc/ssh/sshd_config.d/99-nexusplus.conf "/etc/ssh/sshd_config.d/99-nexusplus.conf.pre-v14.$(date +%s)"; fi
cat >/etc/ssh/sshd_config.d/99-nexusplus.conf <<SSH
PasswordAuthentication yes
PermitRootLogin prohibit-password
AllowTcpForwarding yes
GatewayPorts no
X11Forwarding no
SSH
sshd -t
systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd
cat >/opt/nexusplus/bin/nexus-expiry <<'EXP'
#!/usr/bin/env bash
source /opt/nexusplus/lib/common.sh
source /opt/nexusplus/lib/users.sh
now=$(date +%s)
while IFS='=' read -r u exp; do
 [[ -n "$u" && -n "$exp" ]] || continue
 ts=$(date -d "$exp" +%s 2>/dev/null || echo 0)
 if ((ts<=now)); then pkill -KILL -u "$u" 2>/dev/null||true; userdel -f "$u" 2>/dev/null||true; sed -i "/^${u}=/d" "$LIMITS" "$EXPIRY"; fi
done < "$EXPIRY"
EXP
cat >/opt/nexusplus/bin/nexus-limiter <<'LIM'
#!/usr/bin/env bash
source /opt/nexusplus/lib/common.sh
source /opt/nexusplus/lib/users.sh
report=${1:-}
while IFS=: read -r u _ uid _; do
 ((uid>=1000 && uid<60000)) || continue
 lim=$(get_kv "$LIMITS" "$u" 1); [[ $lim =~ ^[0-9]+$ ]] || lim=1
 mapfile -t pids < <(pgrep -u "$u" -f 'sshd: .*@' 2>/dev/null | sort -n)
 [[ $report == --report ]] && printf '%-18s limite=%-4s conexões=%s\n' "$u" "$lim" "${#pids[@]}"
 while ((${#pids[@]}>lim)); do kill -KILL "${pids[-1]}" 2>/dev/null||true; unset 'pids[-1]'; done
done </etc/passwd
LIM
chmod +x /opt/nexusplus/bin/nexus-expiry /opt/nexusplus/bin/nexus-limiter
cat >/etc/systemd/system/nexusplus-expiry.service <<UNIT
[Unit]
Description=NexusPlus expired user cleanup
[Service]
Type=oneshot
ExecStart=/opt/nexusplus/bin/nexus-expiry
UNIT
cat >/etc/systemd/system/nexusplus-expiry.timer <<UNIT
[Unit]
Description=Run NexusPlus expiry cleanup
[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
Persistent=true
[Install]
WantedBy=timers.target
UNIT
cat >/etc/systemd/system/nexusplus-limiter.service <<UNIT
[Unit]
Description=NexusPlus connection limit enforcer
[Service]
Type=oneshot
ExecStart=/opt/nexusplus/bin/nexus-limiter
UNIT
cat >/etc/systemd/system/nexusplus-limiter.timer <<UNIT
[Unit]
Description=Enforce NexusPlus connection limits
[Timer]
OnBootSec=30s
OnUnitActiveSec=10s
AccuracySec=2s
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now nexusplus-expiry.timer nexusplus-limiter.timer
printf '\nNexusPlus v1.4 instalado sem módulos SSHPLUS legados. Execute: nexus\n'
