#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
NP_ROOT=/opt/nexusplus
NP_ETC=/etc/nexusplus
NP_VAR=/var/lib/nexusplus
NP_LOG=/var/log/nexusplus
NP_MODULES=/opt/nexusplus/modules
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; CYAN='\033[1;36m'; NC='\033[0m'
info(){ echo -e "${BLUE}[INFO]${NC} $*"; }
ok(){ echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[AVISO]${NC} $*"; }
die(){ echo -e "${RED}[ERRO]${NC} $*" >&2; exit 1; }
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die 'Execute como root.'; }
pause(){ read -r -p 'Pressione Enter para continuar...' _ || true; }
valid_port(){ [[ ${1:-} =~ ^[0-9]+$ ]] && (( 10#$1>=1 && 10#$1<=65535 )); }
valid_user(){ [[ ${1:-} =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]; }
header(){ clear; echo -e "${CYAN}╔══════════════════════════════════════════════╗"; printf '║ %-44s ║\n' "$1"; echo -e "╚══════════════════════════════════════════════╝${NC}"; }
service_exists(){ systemctl cat "$1" >/dev/null 2>&1; }
service_active(){ systemctl is-active --quiet "$1" 2>/dev/null; }
port_owner(){ ss -Hltnup 2>/dev/null | awk -v p=":$1" '$4 ~ p"$" || $5 ~ p"$" {print; exit}'; }
require_free_port(){ local p=$1 ignore=${2:-}; valid_port "$p" || { warn 'Porta inválida.'; return 1; }; local x; x=$(port_owner "$p"); [[ -z "$x" || "$x" == *"$ignore"* ]] || { warn "Porta $p ocupada: $x"; return 1; }; }
atomic_write(){ local dest=$1; local tmp; tmp=$(mktemp "${dest}.XXXX"); cat >"$tmp"; chmod --reference="$dest" "$tmp" 2>/dev/null || true; mv -f "$tmp" "$dest"; }
