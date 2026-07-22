#!/usr/bin/env bash
# shellcheck source=common.sh
source /opt/nexusplus/lib/common.sh
LIMITS="$NP_ETC/limits.conf"
EXPIRY="$NP_ETC/expiry.conf"
touch "$LIMITS" "$EXPIRY"
set_kv(){ local f=$1 k=$2 v=$3; grep -vE "^${k}=" "$f" > "$f.tmp" || true; printf '%s=%s\n' "$k" "$v" >> "$f.tmp"; mv "$f.tmp" "$f"; }
get_kv(){ local f=$1 k=$2 d=${3:-}; local v; v=$(awk -F= -v k="$k" '$1==k{print substr($0,index($0,"=")+1);exit}' "$f"); echo "${v:-$d}"; }
create_user(){
 header 'CRIAR USUÁRIO SSH'; read -r -p 'Usuário: ' u; valid_user "$u" || { warn 'Usuário inválido.'; pause; return; }; id "$u" &>/dev/null && { warn 'Usuário já existe.'; pause; return; }
 read -r -s -p 'Senha: ' p; echo; [[ -n "$p" ]] || { warn 'Senha vazia.'; pause; return; }
 read -r -p 'Dias de validade [30]: ' days; days=${days:-30}; [[ $days =~ ^[0-9]+$ ]] || days=30
 read -r -p 'Limite de conexões [1]: ' lim; lim=${lim:-1}; [[ $lim =~ ^[0-9]+$ ]] || lim=1
 useradd -M -s /bin/false "$u"; echo "$u:$p" | chpasswd
 local exp; exp=$(date -d "+$days days" +%F); chage -E "$exp" "$u"; set_kv "$LIMITS" "$u" "$lim"; set_kv "$EXPIRY" "$u" "$exp"; ok "Usuário $u criado até $exp, limite $lim."; pause
}
create_trial(){
 header 'CRIAR TESTE SSH'; local u="teste$(tr -dc a-z0-9 </dev/urandom | head -c4)"; local p; p=$(tr -dc A-Za-z0-9 </dev/urandom | head -c10); local mins
 read -r -p 'Minutos [60]: ' mins; mins=${mins:-60}; [[ $mins =~ ^[0-9]+$ ]] || mins=60
 useradd -M -s /bin/false "$u"; echo "$u:$p" | chpasswd; set_kv "$LIMITS" "$u" 1
 local exp; exp=$(date -d "+$mins minutes" '+%F %T'); set_kv "$EXPIRY" "$u" "$exp"
 echo "Usuário: $u"; echo "Senha: $p"; echo "Expira em: $exp"; pause
}
change_password(){ header 'ALTERAR SENHA'; read -r -p 'Usuário: ' u; id "$u" &>/dev/null || { warn 'Não encontrado.'; pause; return; }; read -r -s -p 'Nova senha: ' p; echo; echo "$u:$p"|chpasswd; ok 'Senha alterada.'; pause; }
change_limit(){ header 'ALTERAR LIMITE'; read -r -p 'Usuário: ' u; id "$u" &>/dev/null || { warn 'Não encontrado.'; pause; return; }; read -r -p 'Novo limite: ' l; [[ $l =~ ^[0-9]+$ ]] || { warn 'Inválido.'; pause; return; }; set_kv "$LIMITS" "$u" "$l"; ok 'Limite atualizado.'; pause; }
delete_user(){ header 'REMOVER USUÁRIO'; read -r -p 'Usuário: ' u; id "$u" &>/dev/null || { warn 'Não encontrado.'; pause; return; }; pkill -KILL -u "$u" 2>/dev/null || true; userdel -f "$u"; sed -i "/^${u}=/d" "$LIMITS" "$EXPIRY"; ok 'Usuário removido.'; pause; }
list_users(){ header 'USUÁRIOS SSH'; printf '%-20s %-12s %-12s\n' USUARIO LIMITE EXPIRA; while IFS=: read -r u _ uid _; do ((uid>=1000 && uid<60000)) || continue; printf '%-20s %-12s %-12s\n' "$u" "$(get_kv "$LIMITS" "$u" 1)" "$(chage -l "$u" 2>/dev/null|awk -F: '/Account expires/{gsub(/^ +/,"",$2);print $2}')"; done </etc/passwd; pause; }
online_users(){ header 'USUÁRIOS ONLINE'; printf '%-20s %-8s %-8s\n' USUARIO ATIVAS LIMITE; while IFS=: read -r u _ uid _; do ((uid>=1000 && uid<60000)) || continue; local_count=$(pgrep -u "$u" sshd 2>/dev/null|wc -l); ((local_count>0)) && printf '%-20s %-8s %-8s\n' "$u" "$local_count" "$(get_kv "$LIMITS" "$u" 1)"; done </etc/passwd; pause; }
kill_user(){ header 'ENCERRAR CONEXÕES'; read -r -p 'Usuário: ' u; pkill -KILL -u "$u" 2>/dev/null && ok 'Conexões encerradas.' || warn 'Nenhuma conexão.'; pause; }
clean_expired(){ header 'LIMPAR EXPIRADOS'; local n=0; while IFS='=' read -r u exp; do [[ -n "$u" && -n "$exp" ]] || continue; if [[ $(date -d "$exp" +%s) -lt $(date +%s) ]]; then pkill -KILL -u "$u" 2>/dev/null||true; userdel -f "$u" 2>/dev/null||true; sed -i "/^${u}=/d" "$LIMITS" "$EXPIRY"; ((n++))||true; fi; done < <(cat "$EXPIRY"); ok "$n usuário(s) removido(s)."; pause; }
