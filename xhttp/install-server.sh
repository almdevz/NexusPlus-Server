#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
APP_NAME=nexus-xhttp
SERVICE_NAME=nexus-xhttp.service
INSTALL_DIR=/usr/local/bin
CONFIG_DIR=/etc/nexus-xhttp
STATE_DIR=/var/lib/nexus-xhttp
CONFIG_FILE=$CONFIG_DIR/server.json
SERVICE_FILE=/etc/systemd/system/$SERVICE_NAME
SERVICE_USER=nexus-xhttp
DEFAULT_PORT=8443
DEFAULT_PATH=/nexus-xhttp/v1
DEFAULT_TARGET=127.0.0.1:22
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RELEASE_BASE_URL=${NEXUS_RELEASE_BASE_URL:-}
TMP_DIR=
ROLLBACK=
cleanup(){ [[ -n ${TMP_DIR:-} && -d $TMP_DIR ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT
trap 'echo "[ERRO] Falha na linha $LINENO." >&2' ERR
log(){ printf '[NEXUS] %s\n' "$*"; }
die(){ printf '[ERRO] %s\n' "$*" >&2; exit 1; }
require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die 'Execute como root.'; }
check_os(){
  [[ -r /etc/os-release ]] || die 'Sistema sem /etc/os-release.'; . /etc/os-release
  case ${ID:-} in debian|ubuntu);;*)die "Sistema não suportado: ${ID:-desconhecido}";;esac
  for c in systemctl openssl ss jq curl sha256sum; do command -v "$c" >/dev/null || die "$c não encontrado."; done
}
map_arch(){ case $(uname -m) in x86_64|amd64)ARCH=amd64;;aarch64|arm64)ARCH=arm64;;*)die "Arquitetura não suportada: $(uname -m)";;esac; BIN_NAME="nexus-xhttp-server-linux-$ARCH"; }
prompt_value(){ local label=$1 default=$2 value; read -r -p "$label [$default]: " value || true; printf '%s' "${value:-$default}"; }
validate_port(){ [[ $1 =~ ^[0-9]+$ ]] && ((1<=$1 && $1<=65535)) || die "Porta inválida: $1"; }
validate_path(){ local p=$1; [[ $p == /* && $p != *..* ]] || die 'Base path inválido.'; [[ $p != */ ]] || p=${p%/}; printf '%s' "$p"; }
validate_host(){ [[ $1 =~ ^[A-Za-z0-9.-]+$ && $1 != .* && $1 != *. ]] || die "Host inválido: $1"; }
port_is_free(){ local p=$1; if ss -H -ltn "sport = :$p" 2>/dev/null|grep -q .;then local current=""; [[ -r $CONFIG_FILE ]] && current=$(jq -r ".listen_port // empty" "$CONFIG_FILE" 2>/dev/null || true); [[ "$current" == "$p" ]] && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && return 0; return 1; fi; }
find_ssh_target(){ local target=$1 host=${target%:*} port=${target##*:};validate_port "$port";case $host in 127.0.0.1|localhost|::1);;*)die "Destino SSH deve ser loopback: $host";;esac; }

snapshot_existing(){
  [[ -e $CONFIG_DIR || -e $SERVICE_FILE || -e $INSTALL_DIR/nexus-xhttp-server ]] || return 0
  install -d -m 0700 "$STATE_DIR/rollback"; ROLLBACK="$STATE_DIR/rollback/$(date +%Y%m%d-%H%M%S)";install -d -m 0700 "$ROLLBACK"
  [[ -d $CONFIG_DIR ]]&&cp -a "$CONFIG_DIR" "$ROLLBACK/config"
  [[ -f $SERVICE_FILE ]]&&cp -a "$SERVICE_FILE" "$ROLLBACK/service"
  [[ -f $INSTALL_DIR/nexus-xhttp-server ]]&&cp -a "$INSTALL_DIR/nexus-xhttp-server" "$ROLLBACK/server"
}
rollback_install(){
  [[ -n ${ROLLBACK:-} && -d $ROLLBACK ]] || return 0
  systemctl stop "$SERVICE_NAME" 2>/dev/null||true
  [[ -d $ROLLBACK/config ]]&&{ rm -rf "$CONFIG_DIR";cp -a "$ROLLBACK/config" "$CONFIG_DIR"; }
  [[ -f $ROLLBACK/service ]]&&cp -a "$ROLLBACK/service" "$SERVICE_FILE"
  [[ -f $ROLLBACK/server ]]&&cp -a "$ROLLBACK/server" "$INSTALL_DIR/nexus-xhttp-server"
  systemctl daemon-reload;systemctl start "$SERVICE_NAME" 2>/dev/null||true
}

obtain_binary(){
  TMP_DIR=$(mktemp -d);local local_bin=$SCRIPT_DIR/$BIN_NAME dst=$TMP_DIR/$BIN_NAME sums expected actual
  if [[ -f $local_bin ]];then cp "$local_bin" "$dst"
  elif [[ -n $RELEASE_BASE_URL ]];then
    curl -fL --proto '=https' --tlsv1.2 --retry 3 "$RELEASE_BASE_URL/$BIN_NAME" -o "$dst"
    curl -fL --proto '=https' --tlsv1.2 --retry 3 "$RELEASE_BASE_URL/SHA256SUMS.txt" -o "$TMP_DIR/SHA256SUMS.txt"
  else die "Binário $BIN_NAME não encontrado.";fi
  if [[ -f $SCRIPT_DIR/SHA256SUMS.txt ]];then sums=$SCRIPT_DIR/SHA256SUMS.txt;else sums=$TMP_DIR/SHA256SUMS.txt;fi
  [[ -r $sums ]]||die 'SHA256SUMS.txt ausente.'
  expected=$(awk -v f="$BIN_NAME" '$2==f||$2=="*"f{print $1;exit}' "$sums");[[ $expected =~ ^[A-Fa-f0-9]{64}$ ]]||die 'SHA esperado ausente.'
  actual=$(sha256sum "$dst"|awk '{print $1}');[[ ${actual,,} == ${expected,,} ]]||die 'SHA-256 do binário inválido.'
  install -m 0755 "$dst" "$INSTALL_DIR/nexus-xhttp-server";log "SHA-256 verificado: $actual"
}
install_user(){ id "$SERVICE_USER" >/dev/null 2>&1||useradd --system --home "$CONFIG_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"; }

certbot_tls(){
  local domain=$1 email=$2
  command -v certbot >/dev/null||{ apt-get update -y;DEBIAN_FRONTEND=noninteractive apt-get install -y certbot; }
  if ss -H -ltn 'sport = :80' 2>/dev/null|grep -q .;then die 'Porta 80 ocupada; use certificado existente ou libere a porta para Certbot standalone.';fi
  certbot certonly --standalone --non-interactive --agree-tos --no-eff-email -m "$email" -d "$domain"
  CERT_SOURCE="/etc/letsencrypt/live/$domain/fullchain.pem";KEY_SOURCE="/etc/letsencrypt/live/$domain/privkey.pem"
  install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
  cat >/etc/letsencrypt/renewal-hooks/deploy/nexus-xhttp-restart <<'HOOK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ -n ${RENEWED_LINEAGE:-} ]] || exit 0
install -m 0644 "$RENEWED_LINEAGE/fullchain.pem" /etc/nexus-xhttp/cert.pem
install -m 0640 "$RENEWED_LINEAGE/privkey.pem" /etc/nexus-xhttp/key.pem
chown root:nexus-xhttp /etc/nexus-xhttp/key.pem
/usr/local/bin/nexus-xhttp-server --check --config /etc/nexus-xhttp/server.json
systemctl restart nexus-xhttp.service
HOOK
  chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/nexus-xhttp-restart
}

configure_tls(){
  local cert=$1 key=$2
  [[ -r $cert && -r $key ]]||die 'Certificado/chave não encontrados.'
  openssl x509 -in "$cert" -noout >/dev/null 2>&1||die 'Certificado inválido.'
  openssl pkey -in "$key" -noout >/dev/null 2>&1||die 'Chave inválida.'
  openssl x509 -in "$cert" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum >"$TMP_DIR/cert.mod"
  openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | sha256sum >"$TMP_DIR/key.mod"
  cmp -s "$TMP_DIR/cert.mod" "$TMP_DIR/key.mod"||die 'Certificado e chave não correspondem.'
  install -m 0644 "$cert" "$CONFIG_DIR/cert.pem";install -m 0640 "$key" "$CONFIG_DIR/key.pem";chown root:"$SERVICE_USER" "$CONFIG_DIR/key.pem"
}
write_config(){ local port=$1 base=$2 target=$3 public=$4;cat >"$CONFIG_FILE.tmp" <<JSON
{
  "listen_host": "0.0.0.0",
  "listen_port": $port,
  "public_host": "$public",
  "tls_cert": "$CONFIG_DIR/cert.pem",
  "tls_key": "$CONFIG_DIR/key.pem",
  "base_path": "$base",
  "allowed_targets": ["$target"],
  "session_expires_seconds": 120,
  "idle_timeout_seconds": 120,
  "backend_connect_timeout_ms": 15000,
  "max_sessions": 1000,
  "max_sessions_per_ip": 20,
  "max_session_json_bytes": 65536
}
JSON
  chmod 0640 "$CONFIG_FILE.tmp";chown root:"$SERVICE_USER" "$CONFIG_FILE.tmp";"$INSTALL_DIR/nexus-xhttp-server" --check --config "$CONFIG_FILE.tmp";mv -f "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}
write_service(){ cat >"$SERVICE_FILE" <<'UNIT'
[Unit]
Description=Nexus XHTTP Server v1.2
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
User=nexus-xhttp
Group=nexus-xhttp
ExecStartPre=/usr/local/bin/nexus-xhttp-server --check --config /etc/nexus-xhttp/server.json
ExecStart=/usr/local/bin/nexus-xhttp-server --config /etc/nexus-xhttp/server.json
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/etc/nexus-xhttp
CapabilityBoundingSet=
AmbientCapabilities=

[Install]
WantedBy=multi-user.target
UNIT
}
configure_firewall(){ local port=$1;if command -v ufw >/dev/null&&ufw status 2>/dev/null|grep -q '^Status: active';then ufw allow "$port/tcp" comment 'Nexus XHTTP' >/dev/null;log "UFW liberado: $port/tcp";else log "Libere $port/tcp no firewall, se necessário.";fi; }
write_uninstaller(){ cat >"$INSTALL_DIR/nexus-xhttp-uninstall" <<'UNINSTALL'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]]||exit 1
systemctl disable --now nexus-xhttp.service 2>/dev/null||true
rm -f /etc/systemd/system/nexus-xhttp.service /usr/local/bin/nexus-xhttp-server /usr/local/bin/nexus-xhttp-health /usr/local/bin/nexus-xhttp-uninstall
rm -f /etc/letsencrypt/renewal-hooks/deploy/nexus-xhttp-restart
systemctl daemon-reload
read -r -p 'Remover /etc/nexus-xhttp e certificados copiados? [s/N]: ' a
[[ $a =~ ^[Ss]$ ]]&&rm -rf /etc/nexus-xhttp
id nexus-xhttp >/dev/null 2>&1&&userdel nexus-xhttp 2>/dev/null||true
echo 'Nexus XHTTP removido.'
UNINSTALL
chmod 0755 "$INSTALL_DIR/nexus-xhttp-uninstall";}
main(){
  require_root;check_os;map_arch
  local port base target public mode cert key email
  port=$(prompt_value 'Porta Nexus XHTTP' "$DEFAULT_PORT");validate_port "$port";port_is_free "$port"||die "Porta $port ocupada."
  base=$(validate_path "$(prompt_value 'Base path' "$DEFAULT_PATH")")
  target=$(prompt_value 'Destino SSH permitido' "$DEFAULT_TARGET");find_ssh_target "$target"
  public=$(prompt_value 'Domínio público/SNI do certificado' 'xhttp.seudominio.com');validate_host "$public"
  echo 'TLS: 1) Certificado existente  2) Certbot standalone'
  read -r -p 'Opção [1]: ' mode;mode=${mode:-1}
  CERT_SOURCE=;KEY_SOURCE=
  case $mode in
    1)cert=$(prompt_value 'Certificado fullchain' "/etc/letsencrypt/live/$public/fullchain.pem");key=$(prompt_value 'Chave privada' "/etc/letsencrypt/live/$public/privkey.pem");CERT_SOURCE=$cert;KEY_SOURCE=$key;;
    2)read -r -p 'E-mail Certbot: ' email;[[ $email == *@*.* ]]||die 'E-mail inválido.';certbot_tls "$public" "$email";;
    *)die 'Opção TLS inválida.';;
  esac
  snapshot_existing;install_user;install -d -m 0750 -o root -g "$SERVICE_USER" "$CONFIG_DIR";install -d -m 0700 "$STATE_DIR"
  obtain_binary;install -m 0755 "$SCRIPT_DIR/nexus-xhttp-health" "$INSTALL_DIR/nexus-xhttp-health"
  configure_tls "$CERT_SOURCE" "$KEY_SOURCE";write_config "$port" "$base" "$target" "$public";write_service;write_uninstaller
  systemctl daemon-reload
  if ! systemctl enable --now "$SERVICE_NAME";then rollback_install;die 'Serviço não iniciou; rollback aplicado.';fi
  sleep 1
  if ! "$INSTALL_DIR/nexus-xhttp-health" "$CONFIG_FILE" >/dev/null;then systemctl status "$SERVICE_NAME" --no-pager||true;journalctl -u "$SERVICE_NAME" -n 50 --no-pager||true;rollback_install;die 'Health check falhou; rollback aplicado.';fi
  configure_firewall "$port"
  cat <<INFO

Nexus XHTTP v1.2 instalado.
Serviço: $SERVICE_NAME
Configuração: $CONFIG_FILE
Health: nexus-xhttp-health
Porta: $port
Host/SNI: $public
Base path: $base
Destino SSH: $target
Limites: max_sessions=1000, max_sessions_per_ip=20 (aplicados inclusive durante conexão pendente)
INFO
}
main "$@"
