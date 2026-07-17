#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

NP_ROOT="${NP_ROOT:-/opt/nexusplus}"
NP_ETC="${NP_ETC:-/etc/nexusplus}"
NP_VAR="${NP_VAR:-/var/lib/nexusplus}"
NP_LOG="${NP_LOG:-/var/log/nexusplus}"
NP_BIN="${NP_BIN:-/usr/local/bin}"
NP_RUN="${NP_RUN:-/run/nexusplus}"
NP_VERSION="$(cat "$NP_ROOT/VERSION" 2>/dev/null || echo '1.3.0')"

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; CYAN='\033[1;36m'; NC='\033[0m'
info(){ echo -e "${BLUE}[INFO]${NC} $*"; }
ok(){ echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[AVISO]${NC} $*"; }
die(){ echo -e "${RED}[ERRO]${NC} $*" >&2; exit 1; }
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || die 'Execute como root.'; }
pause(){ read -r -p 'Pressione Enter para continuar...' _ || true; }
valid_port(){ [[ ${1:-} =~ ^[0-9]+$ ]] && (( $1>=1 && $1<=65535 )); }
valid_user(){ [[ ${1:-} =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]; }
valid_positive_int(){ [[ ${1:-} =~ ^[0-9]+$ ]] && (( $1 >= 1 )); }
header(){ clear 2>/dev/null || true; echo -e "${CYAN}╔══════════════════════════════════════════════╗"; printf '║ %-44s ║\n' "$1"; echo -e "╚══════════════════════════════════════════════╝${NC}"; }
now_utc(){ date -u +%Y-%m-%dT%H:%M:%SZ; }

ensure_runtime_dirs(){
  install -d -m 0755 "$NP_ETC" "$NP_VAR" "$NP_LOG"
  install -d -m 0755 "$NP_RUN" "$NP_RUN/sessions"
}

atomic_replace(){
  local src=$1 dst=$2 mode=${3:-0644} owner=${4:-root:root} dir tmp
  dir=$(dirname "$dst")
  install -d -m 0755 "$dir"
  tmp=$(mktemp "$dir/.nexusplus.XXXXXX")
  cat "$src" > "$tmp"
  chmod "$mode" "$tmp"
  chown "$owner" "$tmp" 2>/dev/null || true
  sync "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$dst"
}

sha256_verify(){
  local file=$1 expected=${2,,} actual
  [[ -f "$file" ]] || return 1
  [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || return 1
  actual=$(sha256sum "$file" | awk '{print tolower($1)}')
  [[ "$actual" == "$expected" ]]
}

safe_extract_archive(){
  local archive=$1 dest=$2
  command -v python3 >/dev/null || die 'python3 é necessário para extração segura.'
  python3 - "$archive" "$dest" <<'PY'
import os, sys, tarfile, zipfile
from pathlib import Path
src=Path(sys.argv[1]); dst=Path(sys.argv[2]); dst.mkdir(parents=True, exist_ok=True)
def safe(name):
    p=Path(name)
    return not p.is_absolute() and '..' not in p.parts
if zipfile.is_zipfile(src):
    with zipfile.ZipFile(src) as z:
        for i in z.infolist():
            if not safe(i.filename): raise SystemExit(f'caminho inseguro: {i.filename}')
            mode=(i.external_attr >> 16) & 0o170000
            if mode == 0o120000: raise SystemExit(f'link simbólico recusado: {i.filename}')
        z.extractall(dst)
else:
    with tarfile.open(src, 'r:*') as t:
        for m in t.getmembers():
            if not safe(m.name): raise SystemExit(f'caminho inseguro: {m.name}')
            if m.issym() or m.islnk() or m.isdev(): raise SystemExit(f'item especial recusado: {m.name}')
        t.extractall(dst, filter='data')
PY
}
