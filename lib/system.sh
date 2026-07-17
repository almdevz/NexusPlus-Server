#!/usr/bin/env bash
source "${NP_ROOT:-/opt/nexusplus}/lib/common.sh"
system_status(){
  header 'STATUS DO SERVIDOR'
  echo "NexusPlus: v$NP_VERSION"; uptime; echo; free -h; echo; df -h /; echo
  systemctl --no-pager --full status nexusplus-expiry.timer nexusplus-limit.timer nexus-dnstt.service 2>/dev/null | sed -n '1,24p' || true
  echo; ss -lntup | head -30
  pause
}
restart_services(){
  header 'REINICIAR SERVIÇOS'
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  systemctl restart nexus-xhttp 2>/dev/null || true
  systemctl restart nexus-dnstt 2>/dev/null || true
  systemctl restart nexusplus-expiry.timer nexusplus-limit.timer 2>/dev/null || true
  ok 'Serviços reiniciados.'; pause
}
optimize_network(){
  header 'OTIMIZAÇÃO SEGURA'
  cat >/etc/sysctl.d/99-nexusplus.conf <<SYS
net.ipv4.ip_forward=1
net.core.somaxconn=4096
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_fin_timeout=30
SYS
  sysctl --system >/dev/null; ok 'Parâmetros aplicados.'; pause
}
