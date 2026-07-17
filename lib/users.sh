#!/usr/bin/env bash
# Gerenciamento persistente de usuários SSH NexusPlus.
# shellcheck source=common.sh
source "${NP_ROOT:-/opt/nexusplus}/lib/common.sh"

LIMITS="$NP_ETC/limits.conf"
EXPIRY="$NP_ETC/expiry.conf"
USERS_DB="$NP_ETC/users.db"
USERS_LOCK="$NP_VAR/users.lock"

users_init(){
  ensure_runtime_dirs
  touch "$LIMITS" "$EXPIRY" "$USERS_DB" "$USERS_LOCK"
  chmod 0600 "$LIMITS" "$EXPIRY" "$USERS_DB" "$USERS_LOCK"
}

set_kv_unlocked(){
  local f=$1 k=$2 v=$3 tmp
  tmp=$(mktemp "$(dirname "$f")/.kv.XXXXXX")
  awk -F= -v k="$k" '$1!=k{print}' "$f" > "$tmp"
  printf '%s=%s\n' "$k" "$v" >> "$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$f"
}

set_kv(){
  local f=$1 k=$2 v=$3
  users_init
  exec 9>"$USERS_LOCK"; flock -x 9
  set_kv_unlocked "$f" "$k" "$v"
}

remove_kv_unlocked(){
  local f=$1 k=$2 tmp
  tmp=$(mktemp "$(dirname "$f")/.kv.XXXXXX")
  awk -F= -v k="$k" '$1!=k{print}' "$f" > "$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$f"
}

get_kv(){
  local f=$1 k=$2 d=${3:-} v
  [[ -r "$f" ]] || { echo "$d"; return; }
  v=$(awk -F= -v k="$k" '$1==k{print substr($0,index($0,"=")+1);exit}' "$f")
  echo "${v:-$d}"
}

upsert_user_db_unlocked(){
  local u=$1 type=$2 created=$3 expires=$4 limit=$5 tmp
  tmp=$(mktemp "$(dirname "$USERS_DB")/.users.XXXXXX")
  awk -F'\t' -v u="$u" '$1!=u{print}' "$USERS_DB" > "$tmp"
  printf '%s\t%s\t%s\t%s\t%s\n' "$u" "$type" "$created" "$expires" "$limit" >> "$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$USERS_DB"
}

remove_user_records_unlocked(){
  local u=$1 tmp
  remove_kv_unlocked "$LIMITS" "$u"
  remove_kv_unlocked "$EXPIRY" "$u"
  tmp=$(mktemp "$(dirname "$USERS_DB")/.users.XXXXXX")
  awk -F'\t' -v u="$u" '$1!=u{print}' "$USERS_DB" > "$tmp"
  chmod 0600 "$tmp"
  mv -f "$tmp" "$USERS_DB"
  rm -rf "$NP_RUN/sessions/$u"
}

record_user(){
  local u=$1 type=$2 expires=$3 limit=$4 created=${5:-$(now_utc)}
  users_init
  exec 9>"$USERS_LOCK"; flock -x 9
  set_kv_unlocked "$LIMITS" "$u" "$limit"
  set_kv_unlocked "$EXPIRY" "$u" "$expires"
  upsert_user_db_unlocked "$u" "$type" "$created" "$expires" "$limit"
}

create_user(){
  header 'CRIAR USUÁRIO SSH'
  local u p days lim exp exp_date
  read -r -p 'Usuário: ' u
  valid_user "$u" || { warn 'Usuário inválido.'; pause; return; }
  id "$u" &>/dev/null && { warn 'Usuário já existe.'; pause; return; }
  read -r -s -p 'Senha: ' p; echo
  [[ -n "$p" ]] || { warn 'Senha vazia.'; pause; return; }
  read -r -p 'Dias de validade [30]: ' days; days=${days:-30}
  valid_positive_int "$days" || { warn 'Validade inválida.'; pause; return; }
  read -r -p 'Limite de conexões [1]: ' lim; lim=${lim:-1}
  valid_positive_int "$lim" || { warn 'Limite inválido.'; pause; return; }
  exp=$(date -u -d "+$days days" +%Y-%m-%dT%H:%M:%SZ)
  exp_date=${exp%%T*}
  useradd -M -s /bin/false "$u"
  if ! echo "$u:$p" | chpasswd; then userdel -f "$u" 2>/dev/null || true; die 'Falha ao definir senha.'; fi
  chage -E "$exp_date" "$u"
  record_user "$u" regular "$exp" "$lim"
  ok "Usuário $u criado até $exp, limite $lim conexão(ões)."
  pause
}

create_trial(){
  header 'CRIAR TESTE SSH'
  local u p mins exp exp_date
  u="teste$(python3 -c 'import secrets; print(secrets.token_hex(2))')"
  p=$(python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(12)))')
  read -r -p 'Minutos [60]: ' mins; mins=${mins:-60}
  valid_positive_int "$mins" || { warn 'Tempo inválido.'; pause; return; }
  exp=$(date -u -d "+$mins minutes" +%Y-%m-%dT%H:%M:%SZ)
  exp_date=${exp%%T*}
  useradd -M -s /bin/false "$u"
  if ! echo "$u:$p" | chpasswd; then userdel -f "$u" 2>/dev/null || true; die 'Falha ao definir senha.'; fi
  chage -E "$exp_date" "$u"
  record_user "$u" trial "$exp" 1
  echo "Usuário: $u"
  echo "Senha: $p"
  echo "Expira em: $exp"
  echo 'A expiração é persistente e será aplicada mesmo após reinício.'
  pause
}

change_password(){
  header 'ALTERAR SENHA'; local u p
  read -r -p 'Usuário: ' u
  id "$u" &>/dev/null || { warn 'Não encontrado.'; pause; return; }
  read -r -s -p 'Nova senha: ' p; echo
  [[ -n "$p" ]] || { warn 'Senha vazia.'; pause; return; }
  echo "$u:$p" | chpasswd
  ok 'Senha alterada.'; pause
}

change_limit(){
  header 'ALTERAR LIMITE'; local u l type created expires
  read -r -p 'Usuário: ' u
  id "$u" &>/dev/null || { warn 'Não encontrado.'; pause; return; }
  read -r -p 'Novo limite: ' l
  valid_positive_int "$l" || { warn 'Inválido.'; pause; return; }
  users_init
  exec 9>"$USERS_LOCK"; flock -x 9
  set_kv_unlocked "$LIMITS" "$u" "$l"
  if IFS=$'\t' read -r _ type created expires _ < <(awk -F'\t' -v u="$u" '$1==u{print;exit}' "$USERS_DB"); then
    upsert_user_db_unlocked "$u" "${type:-regular}" "${created:-$(now_utc)}" "${expires:-never}" "$l"
  else
    upsert_user_db_unlocked "$u" regular "$(now_utc)" "$(get_kv "$EXPIRY" "$u" never)" "$l"
  fi
  flock -u 9
  /opt/nexusplus/bin/nexus-limit-reconcile "$u" >/dev/null 2>&1 || true
  ok 'Limite atualizado e aplicado.'; pause
}

delete_user(){
  header 'REMOVER USUÁRIO'; local u
  read -r -p 'Usuário: ' u
  id "$u" &>/dev/null || { warn 'Não encontrado.'; pause; return; }
  pkill -KILL -u "$u" 2>/dev/null || true
  userdel -f "$u"
  users_init
  exec 9>"$USERS_LOCK"; flock -x 9
  remove_user_records_unlocked "$u"
  ok 'Usuário removido.'; pause
}

expiry_human(){
  local exp=$1
  [[ "$exp" == never || -z "$exp" ]] && { echo 'Nunca'; return; }
  date -d "$exp" '+%d/%m/%Y %H:%M' 2>/dev/null || echo "$exp"
}

list_users(){
  header 'USUÁRIOS SSH'; users_init
  printf '%-20s %-9s %-8s %-18s\n' USUARIO TIPO LIMITE EXPIRA
  while IFS=$'\t' read -r u type _ exp lim; do
    [[ -n "$u" ]] || continue
    id "$u" &>/dev/null || continue
    printf '%-20s %-9s %-8s %-18s\n' "$u" "$type" "$lim" "$(expiry_human "$exp")"
  done < "$USERS_DB"
  pause
}

count_slots(){
  local u=$1 d="$NP_RUN/sessions/$u" n=0 f pid start current
  [[ -d "$d" ]] || { echo 0; return; }
  for f in "$d"/*.session; do
    [[ -f "$f" ]] || continue
    IFS=$'\t' read -r pid start _ < "$f" || true
    if [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/stat" ]]; then
      current=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || true)
      [[ "$current" == "$start" ]] && { ((n++)) || true; continue; }
    fi
    rm -f "$f"
  done
  echo "$n"
}

online_users(){
  header 'USUÁRIOS ONLINE'; users_init
  printf '%-20s %-8s %-8s\n' USUARIO ATIVAS LIMITE
  while IFS=$'\t' read -r u _ _ _ lim; do
    [[ -n "$u" ]] || continue
    local_count=$(count_slots "$u")
    ((local_count>0)) && printf '%-20s %-8s %-8s\n' "$u" "$local_count" "$lim"
  done < "$USERS_DB"
  pause
}

kill_user(){
  header 'ENCERRAR CONEXÕES'; local u
  read -r -p 'Usuário: ' u
  valid_user "$u" || { warn 'Usuário inválido.'; pause; return; }
  pkill -KILL -u "$u" 2>/dev/null && ok 'Conexões encerradas.' || warn 'Nenhuma conexão.'
  rm -rf "$NP_RUN/sessions/$u"
  pause
}

clean_expired(){
  local quiet=${1:-} now n=0 u exp
  [[ "$quiet" == --quiet ]] || header 'LIMPAR EXPIRADOS'
  users_init
  now=$(date +%s)
  exec 9>"$USERS_LOCK"; flock -x 9
  while IFS='=' read -r u exp; do
    [[ -n "$u" && -n "$exp" && "$exp" != never ]] || continue
    exp_epoch=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    if (( exp_epoch > 0 && exp_epoch <= now )); then
      pkill -KILL -u "$u" 2>/dev/null || true
      userdel -f "$u" 2>/dev/null || true
      remove_user_records_unlocked "$u"
      logger -t nexusplus "expired user removed user=$u expiry=$exp" 2>/dev/null || true
      ((n++)) || true
    fi
  done < <(cat "$EXPIRY")
  if [[ "$quiet" != --quiet ]]; then ok "$n usuário(s) removido(s)."; pause; fi
}

migrate_v11_users(){
  users_init
  exec 9>"$USERS_LOCK"; flock -x 9
  local u lim exp
  while IFS='=' read -r u lim; do
    valid_user "$u" || continue
    id "$u" &>/dev/null || continue
    awk -F'\t' -v u="$u" '$1==u{found=1} END{exit !found}' "$USERS_DB" && continue
    exp=$(get_kv "$EXPIRY" "$u" never)
    [[ "$exp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && exp="${exp}T23:59:59Z"
    upsert_user_db_unlocked "$u" regular "$(now_utc)" "$exp" "${lim:-1}"
  done < "$LIMITS"
}

users_init
