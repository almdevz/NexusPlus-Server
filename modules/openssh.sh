#!/usr/bin/env bash
openssh_port(){ sshd -T 2>/dev/null | awk '$1=="port"{print $2;exit}' || echo 22; }
openssh_manage(){
 while true; do header 'GERENCIAR OPENSSH'; local p; p=$(openssh_port); echo "PORTA: $p   STATUS: $(service_active ssh && echo ATIVO || echo INATIVO)"; echo '1) Alterar porta'; echo '2) Reiniciar'; echo '3) Status'; echo '4) Logs'; echo '0) Voltar'; read -r -p 'Opção: ' o
 case $o in
 1) read -r -p "Nova porta [$p]: " np; np=${np:-$p}; require_free_port "$np" sshd || { pause; continue; }; local f=/etc/ssh/sshd_config.d/99-nexusplus.conf bak; bak="$f.bak.$(date +%s)"; cp -a "$f" "$bak" 2>/dev/null||true; { echo "Port $np"; echo 'PasswordAuthentication yes'; echo 'PermitRootLogin prohibit-password'; echo 'AllowTcpForwarding yes'; echo 'GatewayPorts no'; echo 'X11Forwarding no'; } >"$f"; if sshd -t && (systemctl restart ssh 2>/dev/null||systemctl restart sshd); then ufw allow "$np/tcp" 2>/dev/null||true; ok "Porta alterada para $np"; else cp -af "$bak" "$f" 2>/dev/null||true; systemctl restart ssh 2>/dev/null||systemctl restart sshd 2>/dev/null||true; warn 'Rollback aplicado.'; fi; pause;;
 2)systemctl restart ssh 2>/dev/null||systemctl restart sshd;pause;;3)systemctl status ssh --no-pager 2>/dev/null||systemctl status sshd --no-pager;pause;;4)journalctl -u ssh -u sshd -n 100 --no-pager;pause;;0)return;;esac
 done
}
