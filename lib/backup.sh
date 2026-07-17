#!/usr/bin/env bash
source "${NP_ROOT:-/opt/nexusplus}/lib/common.sh"

select_components(){
  local defaults=${1:-users,panel,xhttp,dnstt,system} answer
  echo 'Componentes disponíveis: users,panel,xhttp,dnstt,system'
  read -r -p "Componentes separados por vírgula [$defaults]: " answer
  printf '%s' "${answer:-$defaults}"
}

backup_create(){
  header 'BACKUP SELETIVO E SEGURO'
  local components f
  components=$(select_components)
  f="/root/nexusplus-backup-v1.3-$(date +%Y%m%d-%H%M%S).tar.gz"
  /opt/nexusplus/bin/nexus-backup create --output "$f" --components "$components" || { warn 'Falha ao criar backup.'; pause; return; }
  ok "Criado com permissão 600: $f"; pause
}

backup_restore(){
  header 'RESTAURAR BACKUP SELETIVO'
  local f components confirm
  read -r -p 'Arquivo .tar.gz: ' f
  [[ -f "$f" ]] || { warn 'Arquivo não encontrado.'; pause; return; }
  /opt/nexusplus/bin/nexus-backup inspect --archive "$f" || { warn 'Backup inválido.'; pause; return; }
  components=$(select_components users,panel,xhttp,dnstt,system)
  warn 'A restauração não substitui /etc/passwd ou /etc/shadow completos; somente usuários NexusPlus selecionados são criados/atualizados.'
  read -r -p 'Confirmar restauração? [s/N]: ' confirm
  [[ "$confirm" =~ ^[Ss]$ ]] || { warn 'Cancelado.'; pause; return; }
  /opt/nexusplus/bin/nexus-backup restore --archive "$f" --components "$components" && ok 'Restauração concluída.' || warn 'Restauração falhou; consulte o snapshot de rollback informado.'
  pause
}
