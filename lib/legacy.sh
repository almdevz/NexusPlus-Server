#!/usr/bin/env bash
source "${NP_ROOT:-/opt/nexusplus}/lib/common.sh"
LEG="$NP_ROOT/legacy/SSHPLUS-Modulos"

legacy_installed(){ [[ -d "$LEG" && -f "$LEG/menu" ]]; }

legacy_install_package(){
  header 'INSTALAR PACOTE LEGADO OPCIONAL'
  local pkg sha tmp root
  read -r -p 'Caminho do pacote legado TAR.GZ/ZIP: ' pkg
  [[ -f "$pkg" ]] || { warn 'Pacote não encontrado.'; pause; return; }
  read -r -p 'SHA-256 esperado: ' sha
  sha256_verify "$pkg" "$sha" || { warn 'SHA-256 inválido.'; pause; return; }
  tmp=$(mktemp -d); safe_extract_archive "$pkg" "$tmp"
  root=$(find "$tmp" -type d -path '*/SSHPLUS-Modulos' | head -n1)
  [[ -n "$root" ]] || { rm -rf "$tmp"; warn 'Estrutura legada inválida.'; pause; return; }
  if find "$root" -maxdepth 1 -type f \( -iname '*v2ray*' -o -iname '*xray*' \) | grep -q .; then
    rm -rf "$tmp"; warn 'Pacote recusado: contém módulos V2Ray/Xray.'; pause; return
  fi
  install -d -m 0755 "$NP_ROOT/legacy"
  rm -rf "$LEG.new"; cp -a "$root" "$LEG.new"; rm -rf "$LEG"; mv "$LEG.new" "$LEG"
  chmod -R go-w "$LEG"; rm -rf "$tmp"
  ok 'Módulos legados opcionais instalados.'; pause
}

run_legacy(){
  local f=$1
  [[ -f "$LEG/$f" ]] || { warn 'Módulo não encontrado.'; pause; return; }
  warn 'Módulo legado isolado. Revise antes de usar; ele pode conter práticas e downloads externos antigos.'
  read -r -p "Executar $f? [s/N]: " a
  [[ $a =~ ^[Ss]$ ]] && bash "$LEG/$f"
}

legacy_remove(){
  header 'REMOVER MÓDULOS LEGADOS'
  read -r -p 'Confirmar remoção do pacote opcional? [s/N]: ' a
  [[ $a =~ ^[Ss]$ ]] && { rm -rf "$LEG"; ok 'Pacote legado removido.'; }
  pause
}

legacy_menu(){
  while true; do
    header 'MÓDULOS LEGADOS OPCIONAIS'
    if ! legacy_installed; then
      echo 'Pacote legado não instalado.'
      echo '1) Instalar pacote opcional com SHA-256'
      echo '0) Voltar'
      read -r -p 'Opção: ' o
      case $o in 1)legacy_install_package;;0)return;;*)warn 'Inválida';sleep 1;;esac
      continue
    fi
    echo 'SlowDNS/DNSTT legado foi desativado; use o módulo oficial na opção 17 do menu principal.'
    echo '1) WebSocket legado'
    echo '2) BadVPN UDPGW legado'
    echo '3) Speedtest legado'
    echo '8) Reinstalar pacote opcional'
    echo '9) Remover pacote opcional'
    echo '0) Voltar'
    read -r -p 'Opção: ' o
    case $o in 1)run_legacy wsmenu;;2)run_legacy badvpn;;3)run_legacy speedtest;;8)legacy_install_package;;9)legacy_remove;;0)return;;*)warn 'Inválida';sleep 1;;esac
  done
}
