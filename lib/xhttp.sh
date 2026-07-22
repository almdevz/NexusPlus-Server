#!/usr/bin/env bash
source /opt/nexusplus/lib/common.sh
XHTTP_SRC=/opt/nexusplus/xhttp
xhttp_install(){ header 'INSTALAR NEXUS SSH_XHTTP'; (cd "$XHTTP_SRC" && ./install-server.sh); pause; }
xhttp_status(){ header 'STATUS NEXUS XHTTP'; systemctl status nexus-xhttp --no-pager || true; pause; }
xhttp_logs(){ journalctl -u nexus-xhttp -f; }
xhttp_restart(){ systemctl restart nexus-xhttp && ok 'Reiniciado.' || warn 'Falha.'; pause; }
xhttp_config(){
 local cfg=/etc/nexus-xhttp/server.json bak tmp; [[ -f "$cfg" ]] || { warn 'Servidor não instalado.'; pause; return; }
 bak="${cfg}.bak.$(date +%s)"; cp -a "$cfg" "$bak"; tmp=$(mktemp); cp -a "$cfg" "$tmp"; ${EDITOR:-nano} "$tmp"
 if /usr/local/bin/nexus-xhttp-server --config "$tmp" --check && install -m 0640 "$tmp" "$cfg" && systemctl restart nexus-xhttp; then ok 'Configuração aplicada.'; else cp -af "$bak" "$cfg"; systemctl restart nexus-xhttp 2>/dev/null || true; warn 'Falha: rollback aplicado.'; fi
 rm -f "$tmp"; pause
}
xhttp_health(){ /opt/nexusplus/bin/nexus-health xhttp; pause; }
xhttp_remove(){ header 'REMOVER NEXUS XHTTP'; if [[ -x /usr/local/bin/nexus-xhttp-uninstall ]]; then /usr/local/bin/nexus-xhttp-uninstall; else systemctl disable --now nexus-xhttp 2>/dev/null||true; rm -rf /etc/nexus-xhttp /usr/local/bin/nexus-xhttp-server /etc/systemd/system/nexus-xhttp.service; systemctl daemon-reload; fi; pause; }
xhttp_menu(){ while true; do header 'NEXUS SSH_XHTTP'; echo '1) Instalar'; echo '2) Status'; echo '3) Logs'; echo '4) Editar configuração com rollback'; echo '5) Reiniciar'; echo '6) Health check'; echo '7) Remover'; echo '0) Voltar'; read -r -p 'Opção: ' o; case $o in 1)xhttp_install;;2)xhttp_status;;3)xhttp_logs;;4)xhttp_config;;5)xhttp_restart;;6)xhttp_health;;7)xhttp_remove;;0)return;;*)warn 'Inválida';sleep 1;;esac; done; }
