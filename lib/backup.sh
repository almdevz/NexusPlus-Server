#!/usr/bin/env bash
source /opt/nexusplus/lib/common.sh
backup_create(){
 header 'BACKUP SELETIVO'; local d f manifest
 d=$(mktemp -d); f="/root/nexusplus-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
 mkdir -p "$d/meta" "$d/users" "$d/config"
 cp -a "$NP_ETC" "$d/config/nexusplus" 2>/dev/null || true
 cp -a /etc/nexus-xhttp "$d/config/nexus-xhttp" 2>/dev/null || true
 cp -a /etc/systemd/system/nexus-* "$d/config/" 2>/dev/null || true
 while IFS='=' read -r u _; do
   [[ -n "$u" ]] || continue; id "$u" >/dev/null 2>&1 || continue
   getent passwd "$u" >>"$d/users/passwd"
   getent shadow "$u" >>"$d/users/shadow"
   getent group "$u" >>"$d/users/group" || true
 done <"$NP_ETC/expiry.conf"
 printf 'version=1.4.0\ncreated=%s\n' "$(date -Is)" >"$d/meta/manifest"
 tar -C "$d" -czf "$f" .; rm -rf "$d"; ok "Criado: $f"; pause
}
backup_restore(){
 header 'RESTAURAÇÃO SELETIVA'; read -r -p 'Arquivo .tar.gz: ' f; [[ -f "$f" ]] || { warn 'Arquivo não encontrado.'; pause; return; }
 local d; d=$(mktemp -d); tar -xzf "$f" -C "$d"
 [[ -f "$d/meta/manifest" ]] || { rm -rf "$d"; warn 'Backup incompatível.'; pause; return; }
 cp -a "$NP_ETC" "${NP_ETC}.before-restore.$(date +%s)" 2>/dev/null || true
 [[ -d "$d/config/nexusplus" ]] && cp -a "$d/config/nexusplus/." "$NP_ETC/"
 while IFS=: read -r u pw uid gid gecos home shell; do
   [[ -n "$u" ]] || continue
   id "$u" >/dev/null 2>&1 || useradd -M -u "$uid" -g "$gid" -c "$gecos" -d "$home" -s "$shell" "$u" 2>/dev/null || useradd -M -s /usr/sbin/nologin "$u"
 done <"$d/users/passwd"
 while IFS=: read -r u hash rest; do [[ -n "$u" ]] && usermod -p "$hash" "$u"; done <"$d/users/shadow"
 rm -rf "$d"; systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
 ok 'Restauração concluída sem sobrescrever contas de sistema.'; pause
}
backup_menu(){ while true; do header 'BACKUP / RESTORE'; echo '1) Criar backup seletivo'; echo '2) Restaurar backup seletivo'; echo '0) Voltar'; read -r -p 'Opção: ' o; case $o in 1)backup_create;;2)backup_restore;;0)return;;esac; done; }
