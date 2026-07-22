#!/usr/bin/env bash
set -Eeuo pipefail
REPO='almdevz/NexusPlus-Server'
REF='main'
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Execute como root.' >&2; exit 1; }
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates
GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$REF" "https://github.com/${REPO}.git" "$TMP/repo"
cd "$TMP/repo"
exec ./install.sh
