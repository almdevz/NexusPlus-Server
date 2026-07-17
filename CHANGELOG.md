# CHANGELOG — NexusPlus Server v1.3

## 1.3.0

### Nexus DNSTT / SlowDNS
- Incorporado módulo oficial opcional, separado do núcleo SSH_XHTTP.
- Fixada versão upstream de referência `v1.20260501.0`.
- Instalação exige arquivo local e SHA-256 obrigatório; não há download mutável nem execução sem hash.
- Binário legado sem versão encontrado no SSHPLUS foi adicionado à denylist e não é utilizado.
- Serviço `nexus-dnstt.service` executa como usuário sem login e com hardening systemd.
- Geração de chaves, redirecionamento UDP/53→UDP/5300, health check, logs, backup, rollback e remoção.
- Novo gerador `config_dnstt_unsigned.json` com `connection_type=dnstt`.
- APP Online e status do servidor passam a exibir o módulo DNSTT quando instalado.
- Backup seletivo ganhou o componente `dnstt`.
- Nenhum componente Xray, V2Ray, VLESS, libXray ou UUID foi adicionado.

## 1.2.0

### Limites de conexões
- Adicionado gate PAM `nexus-pam-limit` para reservar uma vaga por sessão SSH gerenciada.
- Adicionado lock com `flock` para impedir corrida entre logins simultâneos.
- Adicionado `nexus-limit-reconcile` e timer para aplicar redução de limite e limpar vagas órfãs.
- O limite não afeta root, usuários de sistema ou usuários não gerenciados pelo NexusPlus.

### Usuários e expiração
- Usuários regulares e de teste passam a ser registrados em `users.db`.
- Expiração usa timestamp UTC persistente em `expiry.conf`.
- Removido o `sleep` em segundo plano dos usuários de teste.
- Timer de expiração executa a cada minuto e possui `Persistent=true`.
- Migração idempotente dos metadados da v1.1.

### Nexus SSH_XHTTP
- Corrigida corrida de `max_sessions` e `max_sessions_per_ip` por reserva de vaga pendente.
- Adicionado endpoint `GET /nexus-xhttp/v1/health`.
- Adicionados `--check` e `--version` ao servidor.
- Adicionado `public_host` à configuração.
- Adicionado health checker local com validação TLS.
- Edição de configuração agora é transacional e possui rollback automático.
- Instalador XHTTP ganhou rollback de instalação e Certbot opcional.
- Binários recompilados para linux/amd64 e linux/arm64.

### Backup e restauração
- Novo formato v2 com manifesto e SHA-256 por arquivo.
- Seleção de componentes: usuários, painel, XHTTP e sistema.
- Usuários são restaurados individualmente, sem substituir bancos globais do sistema.
- Links simbólicos, hard links, devices e caminhos com traversal são recusados.
- Snapshot automático é criado antes da restauração.

### Update e rollback
- Atualização por pacote local exige SHA-256 informado.
- Atualização online exige manifesto HTTPS e SHA-256 do pacote.
- Snapshot automático antes da atualização.
- Rollback automático quando a instalação falha.
- Menu para rollback manual.

### JSON Nexus Connect
- Adicionado gerador `nexus-generate-xhttp-config`.
- Gerado modelo `config_ssh_xhttp_unsigned.json` com `connection_type=ssh_xhttp`.
- `ConfigSignature` fica vazia até assinatura pelo Nexus JSON Signer.

### Legado e distribuição
- Módulos legados removidos do pacote principal.
- Criado pacote opcional separado com verificação SHA-256.
- Módulos V2Ray/Xray não são incluídos.
- Adicionado instalador online com versão e SHA-256 fixos.
