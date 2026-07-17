#!/usr/bin/env bash
source "${NP_ROOT:-/opt/nexusplus}/lib/common.sh"
UPDATE_DIR="$NP_VAR/updates"
UPDATE_CONF="$NP_ETC/update.conf"

update_init(){ install -d -m 0700 "$UPDATE_DIR"; touch "$UPDATE_CONF"; chmod 0600 "$UPDATE_CONF"; }

snapshot_panel(){
  update_init
  local id dir
  id=$(date +%Y%m%d-%H%M%S)
  dir="$UPDATE_DIR/$id"
  install -d -m 0700 "$dir"
  cp -a "$NP_ROOT" "$dir/opt-nexusplus"
  [[ -d "$NP_ETC" ]] && cp -a "$NP_ETC" "$dir/etc-nexusplus"
  [[ -f /etc/pam.d/sshd ]] && cp -a /etc/pam.d/sshd "$dir/pam-sshd"
  find /etc/systemd/system -maxdepth 1 -type f -name 'nexusplus-*' -exec cp -a {} "$dir/" \; 2>/dev/null || true
  printf 'created=%s\nversion=%s\n' "$(now_utc)" "$NP_VERSION" > "$dir/metadata"
  echo "$dir"
}

restore_snapshot(){
  local dir=$1
  [[ -d "$dir/opt-nexusplus" ]] || die 'Snapshot inválido.'
  systemctl stop nexusplus-expiry.timer nexusplus-limit.timer 2>/dev/null || true
  rm -rf "$NP_ROOT.rollback-tmp"
  [[ -d "$NP_ROOT" ]] && mv "$NP_ROOT" "$NP_ROOT.rollback-tmp"
  cp -a "$dir/opt-nexusplus" "$NP_ROOT"
  if [[ -d "$dir/etc-nexusplus" ]]; then rm -rf "$NP_ETC"; cp -a "$dir/etc-nexusplus" "$NP_ETC"; fi
  [[ -f "$dir/pam-sshd" ]] && cp -a "$dir/pam-sshd" /etc/pam.d/sshd
  find "$dir" -maxdepth 1 -type f -name 'nexusplus-*' -exec cp -a {} /etc/systemd/system/ \;
  ln -sf "$NP_ROOT/bin/nexus" /usr/local/bin/nexus
  ln -sf "$NP_ROOT/bin/nexus-app-online" /usr/local/bin/nexus-app-online
  ln -sf "$NP_ROOT/bin/nexus-generate-xhttp-config" /usr/local/bin/nexus-generate-xhttp-config
  if [[ -x "$NP_ROOT/dnstt/nexus-dnstt" ]]; then
    ln -sf "$NP_ROOT/dnstt/nexus-dnstt" /usr/local/bin/nexus-dnstt
    ln -sf "$NP_ROOT/dnstt/nexus-dnstt-health" /usr/local/bin/nexus-dnstt-health
    ln -sf "$NP_ROOT/dnstt/nexus-dnstt-generate-config" /usr/local/bin/nexus-generate-dnstt-config
  elif [[ -f /etc/nexus-dnstt/server.json ]]; then
    systemctl disable --now nexus-dnstt.service 2>/dev/null || true
    warn 'Snapshot não contém suporte DNSTT; serviço foi parado para evitar execução quebrada.'
  fi
  systemctl daemon-reload
  sshd -t || { warn 'Snapshot restaurado, mas sshd -t falhou. Arquivo anterior mantido em /opt/nexusplus.rollback-tmp.'; return 1; }
  systemctl enable --now nexusplus-expiry.timer nexusplus-limit.timer 2>/dev/null || true
  rm -rf "$NP_ROOT.rollback-tmp"
}

find_package_root(){
  local d=$1 root
  root=$(find "$d" -mindepth 1 -maxdepth 3 -type f -name install.sh -printf '%h\n' | head -n1)
  [[ -n "$root" && -f "$root/VERSION" ]] || return 1
  echo "$root"
}

panel_update_file(){
  header 'ATUALIZAR PAINEL — PACOTE LOCAL'
  local pkg expected tmp root snap confirm
  read -r -p 'Caminho do ZIP/TAR.GZ: ' pkg
  [[ -f "$pkg" ]] || { warn 'Pacote não encontrado.'; pause; return; }
  read -r -p 'SHA-256 esperado (64 caracteres): ' expected
  sha256_verify "$pkg" "$expected" || { warn 'SHA-256 inválido. Atualização cancelada.'; pause; return; }
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  safe_extract_archive "$pkg" "$tmp"
  root=$(find_package_root "$tmp") || { warn 'Pacote NexusPlus inválido.'; pause; return; }
  echo "Versão instalada: $NP_VERSION"
  echo "Versão do pacote: $(cat "$root/VERSION")"
  read -r -p 'Continuar? [s/N]: ' confirm
  [[ "$confirm" =~ ^[Ss]$ ]] || { warn 'Cancelado.'; pause; return; }
  snap=$(snapshot_panel)
  info "Snapshot criado: $snap"
  if "$root/install.sh" --upgrade --skip-packages; then
    ok 'Painel atualizado.'
  else
    warn 'Atualização falhou; executando rollback automático.'
    restore_snapshot "$snap" && warn 'Rollback concluído.' || warn 'Rollback automático incompleto; restaure manualmente o snapshot.'
  fi
  pause
}

panel_update_online(){
  header 'ATUALIZAR PAINEL — MANIFESTO ONLINE'
  local url manifest version pkg_url sha tmp pkg
  url=$(awk -F= '$1=="manifest_url"{print substr($0,index($0,"=")+1);exit}' "$UPDATE_CONF")
  read -r -p "URL HTTPS do manifesto [$url]: " answer; url=${answer:-$url}
  [[ "$url" == https://* ]] || { warn 'Somente HTTPS é permitido.'; pause; return; }
  tmp=$(mktemp -d); manifest="$tmp/update.json"; pkg="$tmp/package"
  curl -fL --proto '=https' --tlsv1.2 --retry 3 "$url" -o "$manifest" || { warn 'Falha ao baixar manifesto.'; rm -rf "$tmp"; pause; return; }
  version=$(jq -r '.version // empty' "$manifest"); pkg_url=$(jq -r '.url // empty' "$manifest"); sha=$(jq -r '.sha256 // empty' "$manifest")
  [[ -n "$version" && "$pkg_url" == https://* && "$sha" =~ ^[A-Fa-f0-9]{64}$ ]] || { warn 'Manifesto inválido.'; rm -rf "$tmp"; pause; return; }
  info "Versão disponível: $version"
  curl -fL --proto '=https' --tlsv1.2 --retry 3 "$pkg_url" -o "$pkg" || { warn 'Falha no download.'; rm -rf "$tmp"; pause; return; }
  sha256_verify "$pkg" "$sha" || { warn 'SHA-256 do pacote não confere.'; rm -rf "$tmp"; pause; return; }
  # Feed the verified package into the same local path without weakening the mandatory hash check.
  printf '%s\n%s\n%s\n' "$pkg" "$sha" s | panel_update_file
  rm -rf "$tmp"
}

panel_rollback(){
  header 'ROLLBACK DO PAINEL'; update_init
  local dirs=() d i choice
  while IFS= read -r d; do dirs+=("$d"); done < <(find "$UPDATE_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)
  ((${#dirs[@]})) || { warn 'Nenhum snapshot disponível.'; pause; return; }
  for i in "${!dirs[@]}"; do printf '%2d) %s\n' "$((i+1))" "$(basename "${dirs[$i]}")"; cat "${dirs[$i]}/metadata" 2>/dev/null || true; done
  read -r -p 'Snapshot: ' choice
  [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=${#dirs[@]})) || { warn 'Opção inválida.'; pause; return; }
  warn 'O rollback restaura painel, configuração NexusPlus, PAM e units; não altera usuários do sistema nem /etc/nexus-xhttp.'
  read -r -p 'Confirmar rollback? [s/N]: ' a
  [[ "$a" =~ ^[Ss]$ ]] || { warn 'Cancelado.'; pause; return; }
  restore_snapshot "${dirs[$((choice-1))]}" && ok 'Rollback concluído.' || warn 'Rollback falhou.'
  pause
}

update_menu(){
  while true; do
    header 'UPDATE E ROLLBACK DO PAINEL'
    echo '1) Atualizar por pacote local + SHA-256'
    echo '2) Atualizar por manifesto HTTPS'
    echo '3) Rollback para snapshot anterior'
    echo '0) Voltar'
    read -r -p 'Opção: ' o
    case $o in 1)panel_update_file;;2)panel_update_online;;3)panel_rollback;;0)return;;*)warn 'Opção inválida';sleep 1;;esac
  done
}
