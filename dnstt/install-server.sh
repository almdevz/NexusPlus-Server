#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PINNED_VERSION=$(cat "$ROOT/UPSTREAM_VERSION")
CFG_DIR=/etc/nexus-dnstt
STATE_DIR=/var/lib/nexus-dnstt
HISTORY_DIR=$STATE_DIR/history
LIB_DIR=/usr/local/lib/nexus-dnstt
SERVICE=/etc/systemd/system/nexus-dnstt.service
USER=nexus-dnstt
BIN_SRC= SHA= DOMAIN= TARGET=127.0.0.1:22 LISTEN=0.0.0.0:5300 PUBLIC_PORT=53 DNS_SERVER=1.1.1.1:53 MTU=1232 FIREWALL=true YES=false
usage(){ cat <<EOF
Uso: $0 --binary ARQUIVO --sha256 HASH --domain T.DOMINIO [opções]

Obrigatórios:
  --binary ARQUIVO       dnstt-server obtido de fonte confiável
  --sha256 HASH          SHA-256 exato do arquivo acima
  --domain DOMINIO       subdomínio delegado ao servidor, ex.: t.example.com

Opcionais:
  --target HOST:PORTA    destino SSH local (padrão 127.0.0.1:22)
  --listen IP:PORTA      escuta interna UDP (padrão 0.0.0.0:5300)
  --public-port PORTA    porta UDP pública redirecionada (padrão 53)
  --dns-server HOST:PORT resolver sugerido ao aplicativo (padrão 1.1.1.1:53)
  --mtu N                MTU do cliente (512..1500; padrão 1232)
  --no-firewall-redirect não criar REDIRECT UDP público→interno
  --yes                  não pedir confirmação

Versão de referência fixada pelo módulo: $PINNED_VERSION
O instalador não baixa nem executa binário sem SHA-256 informado.
EOF
}
while (($#)); do case "$1" in
 --binary) BIN_SRC=${2:-}; shift 2;; --sha256) SHA=${2:-}; shift 2;; --domain) DOMAIN=${2:-}; shift 2;;
 --target) TARGET=${2:-}; shift 2;; --listen) LISTEN=${2:-}; shift 2;; --public-port) PUBLIC_PORT=${2:-}; shift 2;;
 --dns-server) DNS_SERVER=${2:-}; shift 2;; --mtu) MTU=${2:-}; shift 2;; --no-firewall-redirect) FIREWALL=false; shift;;
 --yes) YES=true; shift;; -h|--help) usage; exit 0;; *) echo "Argumento desconhecido: $1" >&2; usage; exit 2;; esac; done
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Execute como root.' >&2; exit 1; }
for c in jq sha256sum systemctl ss python3; do command -v "$c" >/dev/null || { echo "$c é obrigatório." >&2; exit 1; }; done
if $FIREWALL; then command -v iptables >/dev/null || { echo "iptables é obrigatório quando o redirecionamento de firewall está ativo." >&2; exit 1; }; fi
[[ -f "$BIN_SRC" ]] || { echo 'Informe --binary com arquivo existente.' >&2; exit 1; }
SHA=${SHA,,}; [[ "$SHA" =~ ^[a-f0-9]{64}$ ]] || { echo 'SHA-256 inválido.' >&2; exit 1; }
ACTUAL=$(sha256sum "$BIN_SRC"|awk '{print tolower($1)}'); [[ "$ACTUAL" == "$SHA" ]] || { echo "SHA-256 divergente. Atual: $ACTUAL" >&2; exit 1; }
if awk -v h="$SHA" 'tolower($1)==h{found=1} END{exit !found}' "$ROOT/DENYLIST_SHA256"; then echo 'Binário recusado: hash presente na denylist de versões legadas/inseguras.' >&2; exit 1; fi
HELP=$("$BIN_SRC" -h 2>&1 || true)
for marker in '-udp' '-privkey-file' '-gen-key'; do grep -Fq -- "$marker" <<<"$HELP" || { echo "Binário não parece ser dnstt-server: marcador $marker ausente." >&2; exit 1; }; done
DOMAIN=${DOMAIN%.}; [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]] || { echo 'Domínio DNSTT inválido.' >&2; exit 1; }
valid_ep(){ [[ "$1" =~ ^(127\.0\.0\.1|localhost|::1):([0-9]+)$ ]] && ((BASH_REMATCH[2]>=1 && BASH_REMATCH[2]<=65535)); }
valid_ep "$TARGET" || { echo 'Destino deve ser loopback HOST:PORTA.' >&2; exit 1; }
[[ "$LISTEN" =~ ^([A-Za-z0-9:.]+):([0-9]+)$ ]] || { echo 'listen inválido.' >&2; exit 1; }; INTERNAL_PORT=${BASH_REMATCH[2]}; ((INTERNAL_PORT>=1 && INTERNAL_PORT<=65535)) || exit 1
[[ "$PUBLIC_PORT" =~ ^[0-9]+$ ]] && ((PUBLIC_PORT>=1 && PUBLIC_PORT<=65535)) || { echo 'public-port inválida.' >&2; exit 1; }
[[ "$MTU" =~ ^[0-9]+$ ]] && ((MTU>=512 && MTU<=1500)) || { echo 'MTU inválida.' >&2; exit 1; }
if ss -H -lun "sport = :$INTERNAL_PORT" 2>/dev/null | grep -q . && ! systemctl is-active --quiet nexus-dnstt.service 2>/dev/null; then echo "Porta UDP interna $INTERNAL_PORT ocupada." >&2; exit 1; fi
if ! $YES; then
 cat <<EOF
DNSTT será configurado com:
  versão de referência: $PINNED_VERSION
  binário SHA-256:      $SHA
  domínio:              $DOMAIN
  escuta interna:       $LISTEN
  porta pública UDP:    $PUBLIC_PORT
  destino SSH:          $TARGET
  redirect firewall:    $FIREWALL
EOF
 read -r -p 'Continuar? [s/N]: ' ans; [[ "$ans" =~ ^[Ss]$ ]] || exit 0
fi
install -d -m 0700 "$HISTORY_DIR"
PREVIOUS=false; SNAPSHOT=
if [[ -e "$CFG_DIR/server.json" || -e "$LIB_DIR/dnstt-server" || -e "$SERVICE" ]]; then
 PREVIOUS=true; SNAPSHOT="$HISTORY_DIR/pre-install-$(date +%Y%m%d-%H%M%S).tar.gz"
 /opt/nexusplus/bin/nexus-backup create --output "$SNAPSHOT" --components dnstt >/dev/null
fi
rollback(){
 echo '[ERRO] Instalação falhou; aplicando rollback.' >&2
 systemctl disable --now nexus-dnstt.service 2>/dev/null || true
 /opt/nexusplus/dnstt/nexus-dnstt-firewall remove 2>/dev/null || true
 if $PREVIOUS && [[ -f "$SNAPSHOT" ]]; then /opt/nexusplus/bin/nexus-backup restore --archive "$SNAPSHOT" --components dnstt || true
 else rm -rf "$CFG_DIR" "$LIB_DIR" "$SERVICE"; id "$USER" >/dev/null 2>&1 && userdel "$USER" 2>/dev/null || true; systemctl daemon-reload; fi
}
trap rollback ERR
id "$USER" >/dev/null 2>&1 || useradd --system --home "$CFG_DIR" --shell /usr/sbin/nologin "$USER"
install -d -m 0750 -o root -g "$USER" "$CFG_DIR" "$LIB_DIR" "$STATE_DIR"
install -m 0755 "$BIN_SRC" "$LIB_DIR/dnstt-server"
if [[ ! -s "$CFG_DIR/server.key" || ! -s "$CFG_DIR/server.pub" ]]; then
 "$LIB_DIR/dnstt-server" -gen-key -privkey-file "$CFG_DIR/server.key.tmp" -pubkey-file "$CFG_DIR/server.pub.tmp"
 install -m 0640 -o root -g "$USER" "$CFG_DIR/server.key.tmp" "$CFG_DIR/server.key"
 install -m 0644 -o root -g root "$CFG_DIR/server.pub.tmp" "$CFG_DIR/server.pub"
 rm -f "$CFG_DIR/server.key.tmp" "$CFG_DIR/server.pub.tmp"
fi
cat >"$CFG_DIR/server.json.tmp" <<JSON
{
  "schema_version": 1,
  "upstream_version": "$PINNED_VERSION",
  "binary_path": "$LIB_DIR/dnstt-server",
  "binary_sha256": "$SHA",
  "listen_udp": "$LISTEN",
  "public_udp_port": $PUBLIC_PORT,
  "firewall_redirect": $FIREWALL,
  "tunnel_domain": "$DOMAIN",
  "target": "$TARGET",
  "private_key_file": "$CFG_DIR/server.key",
  "public_key_file": "$CFG_DIR/server.pub",
  "client_dns_server": "$DNS_SERVER",
  "client_mtu": $MTU
}
JSON
jq -e '.schema_version==1 and (.binary_sha256|test("^[a-f0-9]{64}$")) and (.tunnel_domain|length>3)' "$CFG_DIR/server.json.tmp" >/dev/null
install -m 0640 -o root -g "$USER" "$CFG_DIR/server.json.tmp" "$CFG_DIR/server.json"; rm -f "$CFG_DIR/server.json.tmp"
install -m 0644 /opt/nexusplus/systemd/nexus-dnstt.service "$SERVICE"
systemctl daemon-reload
systemctl enable --now nexus-dnstt.service
sleep 1
/opt/nexusplus/dnstt/nexus-dnstt-health "$CFG_DIR/server.json" >/dev/null
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then ufw allow "$PUBLIC_PORT/udp" comment 'Nexus DNSTT' >/dev/null || true; fi
trap - ERR
cat <<EOF
[OK] Nexus DNSTT instalado.
Serviço: nexus-dnstt.service
Configuração: $CFG_DIR/server.json
Domínio: $DOMAIN
Chave pública: $(cat "$CFG_DIR/server.pub")
Health: nexus-dnstt health

IMPORTANTE: configure no provedor DNS a delegação NS do subdomínio $DOMAIN para o IP público desta VPS.
EOF
