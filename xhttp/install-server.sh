#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="nexus-xhttp"
SERVICE_NAME="nexus-xhttp.service"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/nexus-xhttp"
CONFIG_FILE="$CONFIG_DIR/server.json"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
SERVICE_USER="nexus-xhttp"
DEFAULT_PORT="8443"
DEFAULT_PATH="/nexus-xhttp/v3"
DEFAULT_TARGET="127.0.0.1:22"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_BASE_URL="${NEXUS_RELEASE_BASE_URL:-}"
TMP_DIR=""

cleanup() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT
trap 'echo "[ERRO] Falha na linha $LINENO." >&2' ERR

log() { printf '[NEXUS] %s\n' "$*"; }
die() { printf '[ERRO] %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Execute como root: sudo ./install-server.sh"
}

check_os() {
  [[ -r /etc/os-release ]] || die "Sistema sem /etc/os-release."
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) die "Sistema não suportado: ${ID:-desconhecido}. Use Debian ou Ubuntu." ;;
  esac
  command -v systemctl >/dev/null || die "systemd não encontrado."
  command -v openssl >/dev/null || die "openssl não encontrado. Instale o pacote openssl."
  command -v ss >/dev/null || die "ss não encontrado. Instale o pacote iproute2."
}

map_arch() {
  case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) die "Arquitetura não suportada: $(uname -m)" ;;
  esac
  BIN_NAME="nexus-xhttp-server-linux-$ARCH"
}

prompt_value() {
  local label="$1" default="$2" value
  read -r -p "$label [$default]: " value || true
  printf '%s' "${value:-$default}"
}

validate_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || die "Porta inválida: $p"
  (( p >= 1 && p <= 65535 )) || die "Porta fora do intervalo 1..65535: $p"
}

validate_path() {
  local p="$1"
  [[ "$p" == /* ]] || die "O base path deve começar com '/'."
  [[ "$p" != */ ]] || p="${p%/}"
  printf '%s' "$p"
}

port_is_free() {
  local p="$1"
  if ss -H -ltn "sport = :$p" 2>/dev/null | grep -q .; then
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
      return 0
    fi
    return 1
  fi
  return 0
}

find_ssh_target() {
  local target="$1" host port
  host="${target%:*}"
  port="${target##*:}"
  validate_port "$port"
  case "$host" in
    127.0.0.1|localhost|::1) ;;
    *) die "Por segurança, o destino SSH deve ser loopback. Recebido: $host" ;;
  esac
  if ! ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .; then
    log "AVISO: nenhuma porta TCP local escutando em $target neste momento."
  fi
}

obtain_binary() {
  TMP_DIR="$(mktemp -d)"
  local local_bin="$SCRIPT_DIR/$BIN_NAME"
  local dst="$TMP_DIR/$BIN_NAME"

  if [[ -f "$local_bin" ]]; then
    cp "$local_bin" "$dst"
  elif [[ -n "$RELEASE_BASE_URL" ]]; then
    command -v curl >/dev/null || die "curl é necessário para baixar o binário."
    curl -fL --retry 3 --connect-timeout 15 \
      "$RELEASE_BASE_URL/$BIN_NAME" -o "$dst"
    if [[ -f "$SCRIPT_DIR/SHA256SUMS.txt" ]]; then
      cp "$SCRIPT_DIR/SHA256SUMS.txt" "$TMP_DIR/SHA256SUMS.txt"
    else
      curl -fL --retry 3 --connect-timeout 15 \
        "$RELEASE_BASE_URL/SHA256SUMS.txt" -o "$TMP_DIR/SHA256SUMS.txt"
    fi
  else
    die "Binário $BIN_NAME não encontrado ao lado do instalador. Defina NEXUS_RELEASE_BASE_URL para instalação remota."
  fi

  [[ -s "$dst" ]] || die "Binário vazio ou ausente."

  local sums=""
  if [[ -f "$SCRIPT_DIR/SHA256SUMS.txt" ]]; then
    sums="$SCRIPT_DIR/SHA256SUMS.txt"
  elif [[ -f "$TMP_DIR/SHA256SUMS.txt" ]]; then
    sums="$TMP_DIR/SHA256SUMS.txt"
  fi

  if [[ -n "$sums" ]]; then
    local expected actual
    expected="$(awk -v f="$BIN_NAME" '$2==f || $2=="*"f {print $1; exit}' "$sums")"
    [[ -n "$expected" ]] || die "SHA-256 de $BIN_NAME não encontrado em $sums"
    actual="$(sha256sum "$dst" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || die "SHA-256 inválido para $BIN_NAME"
    log "SHA-256 verificado: $actual"
  else
    die "Arquivo SHA256SUMS.txt ausente; instalação cancelada."
  fi

  chmod 0755 "$dst"
  install -m 0755 "$dst" "$INSTALL_DIR/nexus-xhttp-server"
}

install_user() {
  if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --home "$CONFIG_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
  fi
}

configure_tls() {
  local cert="$1" key="$2"
  [[ -r "$cert" ]] || die "Certificado não encontrado ou ilegível: $cert"
  [[ -r "$key" ]] || die "Chave TLS não encontrada ou ilegível: $key"
  openssl x509 -in "$cert" -noout >/dev/null 2>&1 || die "Certificado TLS inválido."
  openssl pkey -in "$key" -noout >/dev/null 2>&1 || die "Chave TLS inválida."
  install -m 0644 "$cert" "$CONFIG_DIR/cert.pem"
  install -m 0640 "$key" "$CONFIG_DIR/key.pem"
  chown root:"$SERVICE_USER" "$CONFIG_DIR/key.pem"
}

write_config() {
  local port="$1" base_path="$2" target="$3"
  cat > "$CONFIG_FILE" <<JSON
{
  "listen_host": "0.0.0.0",
  "listen_port": $port,
  "tls_cert": "$CONFIG_DIR/cert.pem",
  "tls_key": "$CONFIG_DIR/key.pem",
  "base_path": "$base_path",
  "fixed_target": "$target",
  "allowed_targets": [
    "$target"
  ],
  "session_expires_seconds": 300,
  "idle_timeout_seconds": 120,
  "backend_connect_timeout_ms": 15000,
  "max_sessions": 1000,
  "max_sessions_per_ip": 20,
  "max_session_json_bytes": 65536,
  "max_post_bytes": 1048576,
  "enable_legacy_v2": true
}
JSON
  chmod 0640 "$CONFIG_FILE"
  chown root:"$SERVICE_USER" "$CONFIG_FILE"
}

write_service() {
  cat > "$SERVICE_FILE" <<'UNIT'
[Unit]
Description=Nexus XHTTP Server
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
User=nexus-xhttp
Group=nexus-xhttp
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

configure_firewall() {
  local port="$1"
  if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow "$port/tcp" comment 'Nexus XHTTP' >/dev/null
    log "Regra UFW adicionada para $port/tcp."
  else
    log "Firewall não alterado automaticamente. Libere $port/tcp, se necessário."
  fi
}

write_uninstaller() {
  cat > "$INSTALL_DIR/nexus-xhttp-uninstall" <<'UNINSTALL'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Execute como root." >&2; exit 1; }
systemctl disable --now nexus-xhttp.service 2>/dev/null || true
rm -f /etc/systemd/system/nexus-xhttp.service
systemctl daemon-reload
rm -f /usr/local/bin/nexus-xhttp-server /usr/local/bin/nexus-xhttp-uninstall
printf 'Remover também /etc/nexus-xhttp e certificados? [y/N]: '
read -r answer
if [[ "$answer" =~ ^[Yy]$ ]]; then rm -rf /etc/nexus-xhttp; fi
id nexus-xhttp >/dev/null 2>&1 && userdel nexus-xhttp 2>/dev/null || true
echo "Nexus XHTTP removido."
UNINSTALL
  chmod 0755 "$INSTALL_DIR/nexus-xhttp-uninstall"
}

main() {
  require_root
  check_os
  map_arch

  local port base_path target cert key
  port="$(prompt_value 'Porta do Nexus XHTTP' "$DEFAULT_PORT")"
  validate_port "$port"
  port_is_free "$port" || die "A porta $port já está ocupada."

  base_path="$(prompt_value 'Base path' "$DEFAULT_PATH")"
  base_path="$(validate_path "$base_path")"

  target="$(prompt_value 'Destino SSH permitido' "$DEFAULT_TARGET")"
  find_ssh_target "$target"

  cert="$(prompt_value 'Caminho do certificado TLS' '/etc/letsencrypt/live/SEU_DOMINIO/fullchain.pem')"
  key="$(prompt_value 'Caminho da chave TLS' '/etc/letsencrypt/live/SEU_DOMINIO/privkey.pem')"

  log "Instalando Nexus XHTTP para arquitetura $ARCH..."
  install_user
  install -d -m 0750 -o root -g "$SERVICE_USER" "$CONFIG_DIR"
  obtain_binary
  configure_tls "$cert" "$key"
  write_config "$port" "$base_path" "$target"
  write_service
  write_uninstaller

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  sleep 1
  systemctl is-active --quiet "$SERVICE_NAME" || {
    systemctl status "$SERVICE_NAME" --no-pager || true
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager || true
    die "O serviço não iniciou."
  }

  configure_firewall "$port"

  cat <<INFO

Nexus XHTTP instalado com sucesso.

Serviço:        $SERVICE_NAME
Configuração:   $CONFIG_FILE
Porta TCP:      $port
Base path:      $base_path
Destino SSH:    $target
Status:         systemctl status $SERVICE_NAME
Logs:           journalctl -u $SERVICE_NAME -f
Desinstalar:    sudo nexus-xhttp-uninstall

Campos para a Network do Nexus Connect:
  "connection_type": "ssh_xhttp"
  "proxy_ip": "IP_OU_DOMINIO_DO_SERVIDOR"
  "tlsport": "$port"
  "sni": "DOMINIO_DO_CERTIFICADO"
  "xhttp_host": "DOMINIO_DO_CERTIFICADO"
  "xhttp_base_path": "$base_path"
  "xhttp_tls": true
  "xhttp_protocol_version": 3

Modo v3: GET persistente + POSTs sequenciais numerados.
Compatibilidade v2 permanece habilitada por padrão.
A autenticação do usuário continua sendo feita por SSH.
INFO
}

main "$@"
