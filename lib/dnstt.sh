#!/usr/bin/env bash
source "${NP_ROOT:-/opt/nexusplus}/lib/common.sh"
DNSTT_ROOT="$NP_ROOT/dnstt"
dnstt_install(){
 header 'INSTALAR/ATUALIZAR NEXUS DNSTT'
 local bin hash domain target listen public dns mtu extra=()
 read -r -p 'Caminho do dnstt-server: ' bin; [[ -f "$bin" ]] || { warn 'Arquivo não encontrado.'; pause; return; }
 read -r -p 'SHA-256 exato do binário: ' hash
 read -r -p 'Subdomínio delegado (ex.: t.seudominio.com): ' domain
 read -r -p 'Destino SSH local [127.0.0.1:22]: ' target; target=${target:-127.0.0.1:22}
 read -r -p 'Escuta UDP interna [0.0.0.0:5300]: ' listen; listen=${listen:-0.0.0.0:5300}
 read -r -p 'Porta UDP pública [53]: ' public; public=${public:-53}
 read -r -p 'Resolver DNS para o cliente [1.1.1.1:53]: ' dns; dns=${dns:-1.1.1.1:53}
 read -r -p 'MTU do cliente [1232]: ' mtu; mtu=${mtu:-1232}
 "$DNSTT_ROOT/install-server.sh" --binary "$bin" --sha256 "$hash" --domain "$domain" --target "$target" --listen "$listen" --public-port "$public" --dns-server "$dns" --mtu "$mtu"
 pause
}
dnstt_status(){ header 'STATUS NEXUS DNSTT'; /opt/nexusplus/dnstt/nexus-dnstt status; pause; }
dnstt_health(){ header 'HEALTH CHECK NEXUS DNSTT'; /opt/nexusplus/dnstt/nexus-dnstt health | jq . || true; pause; }
dnstt_logs(){ journalctl -u nexus-dnstt.service -f; }
dnstt_restart(){ systemctl restart nexus-dnstt.service && sleep 1 && /opt/nexusplus/dnstt/nexus-dnstt health >/dev/null && ok 'DNSTT reiniciado e saudável.' || warn 'Falha no restart/health check.'; pause; }
dnstt_show_client(){ header 'CONFIGURAÇÃO CLIENTE DNSTT'; /opt/nexusplus/dnstt/nexus-dnstt show-client | jq . || true; pause; }
dnstt_generate_json(){
 header 'GERAR CONFIG DNSTT NÃO ASSINADA'
 local input output
 read -r -p 'JSON base: ' input; [[ -f "$input" ]] || { warn 'JSON não encontrado.'; pause; return; }
 read -r -p 'Saída [/root/config_dnstt_unsigned.json]: ' output; output=${output:-/root/config_dnstt_unsigned.json}
 /opt/nexusplus/dnstt/nexus-dnstt generate-config --input "$input" --output "$output" && ok 'JSON DNSTT não assinado gerado.' || warn 'Falha na geração.'
 pause
}
dnstt_backup(){ header 'BACKUP DNSTT'; local out; out="/root/nexus-dnstt-backup-$(date +%Y%m%d-%H%M%S).tar.gz"; /opt/nexusplus/dnstt/nexus-dnstt backup "$out" && ok "$out" || warn 'Falha.'; pause; }
dnstt_rollback(){ header 'ROLLBACK DNSTT'; local f; read -r -p 'Arquivo de backup DNSTT: ' f; [[ -f "$f" ]] || { warn 'Arquivo não encontrado.'; pause; return; }; /opt/nexusplus/dnstt/nexus-dnstt rollback "$f"; pause; }
dnstt_remove(){ header 'REMOVER NEXUS DNSTT'; /opt/nexusplus/dnstt/nexus-dnstt uninstall; pause; }
dnstt_menu(){ while true; do
 header 'NEXUS DNSTT / SLOWDNS OPCIONAL'
 echo '1) Instalar/atualizar com binário + SHA-256'
 echo '2) Status'
 echo '3) Health check'
 echo '4) Logs'
 echo '5) Reiniciar'
 echo '6) Mostrar configuração do cliente'
 echo '7) Gerar config_dnstt_unsigned.json'
 echo '8) Backup do módulo'
 echo '9) Rollback do módulo'
 echo '10) Remover'
 echo '0) Voltar'
 read -r -p 'Opção: ' o
 case $o in 1)dnstt_install;;2)dnstt_status;;3)dnstt_health;;4)dnstt_logs;;5)dnstt_restart;;6)dnstt_show_client;;7)dnstt_generate_json;;8)dnstt_backup;;9)dnstt_rollback;;10)dnstt_remove;;0)return;;*)warn 'Inválida';sleep 1;;esac
 done; }
