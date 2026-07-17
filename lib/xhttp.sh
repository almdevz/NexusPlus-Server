#!/usr/bin/env bash
source "${NP_ROOT:-/opt/nexusplus}/lib/common.sh"
XHTTP_SRC="$NP_ROOT/xhttp"
XHTTP_CONFIG=/etc/nexus-xhttp/server.json
XHTTP_HISTORY="$NP_VAR/xhttp-config-history"

xhttp_install(){ header 'INSTALAR/ATUALIZAR NEXUS SSH_XHTTP'; (cd "$XHTTP_SRC" && ./install-server.sh); pause; }
xhttp_status(){ header 'STATUS NEXUS XHTTP'; systemctl status nexus-xhttp --no-pager || true; pause; }
xhttp_logs(){ journalctl -u nexus-xhttp -f; }
xhttp_restart(){ systemctl restart nexus-xhttp && /usr/local/bin/nexus-xhttp-health >/dev/null && ok 'Reiniciado e saudável.' || warn 'Falha no restart/health check.'; pause; }
xhttp_health(){ header 'HEALTH CHECK NEXUS XHTTP'; if [[ -x /usr/local/bin/nexus-xhttp-health ]]; then /usr/local/bin/nexus-xhttp-health "$XHTTP_CONFIG" | jq .; else warn 'Health checker não instalado.'; fi; pause; }

xhttp_validate(){
  local cfg=$1
  [[ -x /usr/local/bin/nexus-xhttp-server ]] || { warn 'Binário Nexus XHTTP ausente.'; return 1; }
  /usr/local/bin/nexus-xhttp-server --check --config "$cfg"
}

xhttp_config(){
  header 'EDITAR XHTTP — TRANSAÇÃO COM ROLLBACK'
  [[ -f "$XHTTP_CONFIG" ]] || { warn 'Configuração não encontrada.'; pause; return; }
  install -d -m 0700 "$XHTTP_HISTORY"
  local work backup ts owner group mode
  ts=$(date +%Y%m%d-%H%M%S)
  backup="$XHTTP_HISTORY/server.json.$ts"
  cp -a "$XHTTP_CONFIG" "$backup"
  work=$(mktemp /etc/nexus-xhttp/.server.json.edit.XXXXXX)
  cp -a "$XHTTP_CONFIG" "$work"
  owner=$(stat -c %u "$XHTTP_CONFIG"); group=$(stat -c %g "$XHTTP_CONFIG"); mode=$(stat -c %a "$XHTTP_CONFIG")
  if ! "${EDITOR:-nano}" "$work"; then rm -f "$work"; warn 'Editor cancelado/falhou; nada foi alterado.'; pause; return; fi
  if cmp -s "$work" "$XHTTP_CONFIG"; then rm -f "$work"; warn 'Nenhuma alteração.'; pause; return; fi
  if ! xhttp_validate "$work"; then rm -f "$work"; warn 'Configuração inválida. Original preservado.'; pause; return; fi
  chown "$owner:$group" "$work"; chmod "$mode" "$work"; sync "$work" 2>/dev/null || true
  mv -f "$work" "$XHTTP_CONFIG"
  if systemctl restart nexus-xhttp.service && sleep 1 && /usr/local/bin/nexus-xhttp-health "$XHTTP_CONFIG" >/dev/null; then
    ok "Configuração aplicada. Backup: $backup"
  else
    warn 'Restart ou health check falhou. Executando rollback.'
    cp -a "$backup" "$XHTTP_CONFIG"
    systemctl restart nexus-xhttp.service 2>/dev/null || true
    if /usr/local/bin/nexus-xhttp-health "$XHTTP_CONFIG" >/dev/null 2>&1; then warn 'Rollback concluído e serviço saudável.'; else warn 'Rollback restaurado, porém o serviço requer verificação manual.'; fi
  fi
  pause
}

xhttp_restore_config(){
  header 'RESTAURAR CONFIGURAÇÃO XHTTP'
  local files=() f i choice current
  install -d -m 0700 "$XHTTP_HISTORY"
  while IFS= read -r f; do files+=("$f"); done < <(find "$XHTTP_HISTORY" -maxdepth 1 -type f -name 'server.json.*' | sort -r)
  ((${#files[@]})) || { warn 'Nenhum histórico.'; pause; return; }
  for i in "${!files[@]}"; do printf '%2d) %s\n' "$((i+1))" "$(basename "${files[$i]}")"; done
  read -r -p 'Backup: ' choice
  [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=${#files[@]})) || { warn 'Inválido.'; pause; return; }
  f=${files[$((choice-1))]}
  xhttp_validate "$f" || { warn 'Backup inválido.'; pause; return; }
  current="$XHTTP_HISTORY/server.json.before-restore-$(date +%Y%m%d-%H%M%S)"; cp -a "$XHTTP_CONFIG" "$current"
  cp -a "$f" "$XHTTP_CONFIG"
  if systemctl restart nexus-xhttp && sleep 1 && /usr/local/bin/nexus-xhttp-health >/dev/null; then ok 'Configuração restaurada.'; else cp -a "$current" "$XHTTP_CONFIG";systemctl restart nexus-xhttp 2>/dev/null||true;warn 'Falha; configuração anterior restaurada.';fi
  pause
}

xhttp_generate_json(){
  header 'GERAR CONFIG SSH_XHTTP NÃO ASSINADA'
  local input output server host port base
  read -r -p 'JSON base: ' input
  [[ -f "$input" ]] || { warn 'JSON não encontrado.'; pause; return; }
  read -r -p 'Saída [/root/config_ssh_xhttp_unsigned.json]: ' output; output=${output:-/root/config_ssh_xhttp_unsigned.json}
  read -r -p 'IP/domínio físico XHTTP [IP_OU_DOMINIO_XHTTP]: ' server; server=${server:-IP_OU_DOMINIO_XHTTP}
  read -r -p 'Host/SNI [DOMINIO_XHTTP]: ' host; host=${host:-DOMINIO_XHTTP}
  read -r -p 'Porta [8443]: ' port; port=${port:-8443}
  read -r -p 'Base path [/nexus-xhttp/v1]: ' base; base=${base:-/nexus-xhttp/v1}
  /opt/nexusplus/bin/nexus-generate-xhttp-config --input "$input" --output "$output" --server "$server" --host "$host" --port "$port" --base-path "$base" && ok 'JSON não assinado gerado.' || warn 'Falha na geração.'
  pause
}

xhttp_remove(){ header 'REMOVER NEXUS XHTTP'; if [[ -x /usr/local/bin/nexus-xhttp-uninstall ]];then /usr/local/bin/nexus-xhttp-uninstall;else systemctl disable --now nexus-xhttp 2>/dev/null||true;rm -rf /etc/nexus-xhttp /usr/local/bin/nexus-xhttp-server /usr/local/bin/nexus-xhttp-health /etc/systemd/system/nexus-xhttp.service;systemctl daemon-reload;fi;pause; }

xhttp_menu(){ while true;do header 'NEXUS SSH_XHTTP';echo '1) Instalar/atualizar';echo '2) Status';echo '3) Health check';echo '4) Logs';echo '5) Editar configuração transacional';echo '6) Restaurar configuração anterior';echo '7) Reiniciar';echo '8) Gerar config_ssh_xhttp_unsigned.json';echo '9) Remover';echo '0) Voltar';read -r -p 'Opção: ' o;case $o in 1)xhttp_install;;2)xhttp_status;;3)xhttp_health;;4)xhttp_logs;;5)xhttp_config;;6)xhttp_restore_config;;7)xhttp_restart;;8)xhttp_generate_json;;9)xhttp_remove;;0)return;;*)warn 'Inválida';sleep 1;;esac;done; }
