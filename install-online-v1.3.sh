#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
VERSION='1.3'
PACKAGE='NexusPlus-Server-v1.3.tar.gz'
EXPECTED_SHA256='98b548675c651c9b47a2f5065727455c3b531bdd83aa6477f3ba54629b37c34e'
DEFAULT_BASE_URL='https://github.com/almdevz/NexusPlus-Server/releases/download/v1.3'
BASE_URL="${NEXUSPLUS_RELEASE_BASE_URL:-$DEFAULT_BASE_URL}"
[[ $BASE_URL == https://* ]] || { echo '[ERRO] A URL deve usar HTTPS.' >&2; exit 1; }
for c in curl sha256sum python3 tar; do command -v "$c" >/dev/null || { echo "[ERRO] $c não encontrado." >&2; exit 1; }; done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
URL="${BASE_URL%/}/$PACKAGE"
echo "[NEXUS] Baixando versão fixa $VERSION: $URL"
curl -fL --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 15 "$URL" -o "$TMP/$PACKAGE"
ACTUAL=$(sha256sum "$TMP/$PACKAGE" | awk '{print tolower($1)}')
[[ $ACTUAL == $EXPECTED_SHA256 ]] || { echo '[ERRO] SHA-256 inválido; instalação cancelada.' >&2; echo "Esperado: $EXPECTED_SHA256" >&2; echo "Obtido:   $ACTUAL" >&2; exit 1; }
echo "[NEXUS] SHA-256 verificado: $ACTUAL"
python3 - "$TMP/$PACKAGE" "$TMP/extract" <<'PY'
import sys,tarfile
from pathlib import Path
src=Path(sys.argv[1]);dst=Path(sys.argv[2]);dst.mkdir()
with tarfile.open(src,'r:*') as t:
 for m in t.getmembers():
  p=Path(m.name)
  if p.is_absolute() or '..' in p.parts or m.issym() or m.islnk() or m.isdev(): raise SystemExit('arquivo inseguro: '+m.name)
 t.extractall(dst,filter='data')
PY
ROOT="$TMP/extract/NexusPlus-Server-v1.3"
[[ -x $ROOT/install.sh && $(cat "$ROOT/VERSION") == 1.3.0 ]] || { echo '[ERRO] Pacote ou versão inválida.' >&2; exit 1; }
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$ROOT/install.sh"; else sudo "$ROOT/install.sh"; fi
