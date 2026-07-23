# Auditoria de compatibilidade SSHPlus → NexusPlus

Data da revisão: 2026-07-22

## Escopo analisado

O ZIP `SSHPLUS-master.zip` contém 112 arquivos: 60 scripts shell, 3 scripts Python, 12 executáveis ELF, 2 arquivos compactados e 35 outros arquivos/configurações.

Foram mapeados os módulos de usuários, limites, expiração, conexões online, backup, OpenSSH, Dropbear, Squid, WebSocket, Stunnel/SSL, BadVPN, SlowDNS/DNSTT, OpenVPN, UDP, V2Ray e utilitários de sistema.

## Regra de portabilidade

O NexusPlus não deve substituir um comportamento funcional do SSHPlus por uma implementação menor. A ordem obrigatória é:

1. reproduzir a compatibilidade observada;
2. criar teste de regressão;
3. organizar a configuração e o serviço;
4. acrescentar validação, logs e rollback;
5. só então remover o módulo antigo.

## WebSocket SSH

### Comportamento encontrado no SSHPlus

O `Modulos/wsproxy.py` implementa um proxy de injector, não WebSocket RFC6455 completo. Ele:

- aceita um preâmbulo HTTP e responde `HTTP/1.1 101`;
- usa destino padrão `127.0.0.1:22`;
- reconhece `X-Real-Host` e `X-Split`;
- restringe o destino a loopback quando não há senha de proxy;
- realiza relay TCP bidirecional bruto.

O ZIP também contém um executável Go chamado `Modulos/WebSocket`. Como não há fonte desse binário no ZIP, ele não deve ser tratado como código auditável nem copiado como dependência obrigatória.

### Correção NexusPlus

`services/nexus_ws.py` foi substituído por uma implementação compatível com payloads de injector:

- aceita terminações LF, CRLF e misturadas;
- aceita qualquer método na primeira linha;
- aceita payload fragmentado;
- aceita requisições preliminares antes do bloco de Upgrade;
- preserva bytes enviados depois do cabeçalho;
- mantém relay TCP bidirecional;
- preserva `X-Real-Host`, limitado a loopback;
- limita tamanho e tempo do preâmbulo;
- registra conexões e falhas no journal;
- responde `Sec-WebSocket-Accept` quando a chave estiver presente, sem anunciar suporte a framing RFC6455.

Os testes estão em `tests/test_nexus_ws.py`.

## SSL e SSL Proxy

O fluxo compatível com o aplicativo é:

- SSL direto: `444 → 127.0.0.1:22`;
- SSL Proxy: `443 → 127.0.0.1:80 → 127.0.0.1:22`.

A configuração deve usar um único `/etc/stunnel/stunnel.conf`, certificado e chave com permissões corretas, escrita temporária, validação e rollback. Arquivos antigos `*.conf` não podem permanecer ativos ao mesmo tempo.

## Usuários, limites e expiração

Funções que devem permanecer compatíveis:

- criação de usuário SSH;
- criação de usuário teste;
- alteração de senha;
- alteração de limite;
- remoção;
- listagem;
- expiração por data e por minuto;
- encerramento de conexões excedentes;
- limpeza automática de expirados.

A implementação NexusPlus deve manter metadados próprios em `/etc/nexusplus`, mas a conta Linux continua sendo a fonte de verdade para autenticação.

## APP Online

O APP Online do painel deve contar sessões SSH autenticadas por usuário e ignorar `root` e contas de sistema. Conexões que chegam por WebSocket ou Stunnel terminam no OpenSSH e devem aparecer na mesma contagem.

O endpoint remoto `online_app` é uma integração separada. A exibição local não prova que o servidor central foi atualizado.

## BadVPN UDPGW

Mantido como serviço local para clientes SSH que suportam UDPGW:

- padrão `127.0.0.1:7300`;
- não expor a porta publicamente;
- limites editáveis;
- serviço systemd;
- status, logs e remoção.

## Código legado e riscos

A auditoria encontrou:

- scripts ofuscados;
- 12 binários ELF sem fonte correspondente no ZIP;
- 71 referências HTTP/HTTPS, incluindo downloads de repositórios externos;
- referências antigas a Dropbox, Netlify e repositórios de terceiros;
- binários com referências a APIs externas.

Por isso, o NexusPlus não deve executar automaticamente binários ou downloads do ZIP sem fonte, hash fixado e revisão específica.

## Estado de validação

- WebSocket: código corrigido e testes automatizados adicionados; requer teste real no aplicativo.
- SSL direto e SSL Proxy: fluxo corrigido; requer teste real após atualização do módulo.
- OpenSSH, usuários e limite: implementação nativa existente; requer teste de carga e múltiplas sessões.
- OpenVPN, SlowDNS/DNSTT, BadVPN e Chisel: não devem ser marcados como validados apenas por análise estática; exigem VPS limpa e teste funcional.
- Binários legados: preservados apenas como referência de auditoria, não como dependência confiável.

## Critério para marcar um módulo como pronto

Um módulo só pode ser declarado pronto quando tiver:

1. instalação em Debian 12 e Ubuntu 22.04/24.04;
2. configuração editável;
3. validação antes de reiniciar;
4. rollback;
5. status e logs;
6. remoção limpa;
7. teste funcional correspondente ao comportamento do aplicativo.
