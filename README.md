# NexusPlus Server v1.3

Painel modular para Debian/Ubuntu com gerenciamento de usuários SSH, APP Online e servidor próprio Nexus SSH_XHTTP.

## Destaques da v1.3

- limite de conexões SSH aplicado no PAM e reconciliado por timer;
- usuários de teste com expiração persistente após reinício;
- edição do XHTTP transacional, com validação, health check e rollback automático;
- update local/online e rollback do painel;
- emissão Certbot opcional no instalador XHTTP;
- backup/restauração seletivos, sem sobrescrever `/etc/passwd` ou `/etc/shadow` completos;
- endpoint e comando de health check do Nexus XHTTP;
- gerador de `config_ssh_xhttp_unsigned.json` baseado no JSON do Nexus Connect;
- módulos legados distribuídos em pacote opcional separado;
- instalação online com versão fixa e SHA-256 embutido.
- módulo oficial DNSTT/SlowDNS opcional, com SHA-256 obrigatório, systemd, health check, backup e rollback;

## Instalação offline

```bash
unzip NexusPlus-Server-v1.3.zip
cd NexusPlus-Server-v1.3
sudo ./install.sh
nexus
```

Também é possível usar o TAR.GZ:

```bash
tar -xzf NexusPlus-Server-v1.3.tar.gz
cd NexusPlus-Server-v1.3
sudo ./install.sh
```

Verifique antes:

```bash
sha256sum -c SHA256SUMS
```

## Instalação online

Publique `NexusPlus-Server-v1.3.tar.gz` na URL configurada no `install-online.sh` e execute o instalador. O script possui versão e SHA-256 fixos e recusa qualquer arquivo diferente.

## Nexus SSH_XHTTP

No painel, use `16) Nexus SSH_XHTTP` para instalar, validar, editar, restaurar configuração, executar health check e gerar o JSON não assinado do aplicativo.

O protocolo é próprio e não utiliza Xray, V2Ray, VLESS, libXray nem UUID de autenticação. A autenticação continua sendo realizada pelo OpenSSH.

## APP Online

Use `8) APP Online — protocolos e portas` ou:

```bash
nexus-app-online
```

A tela diferencia conexões TCP físicas e sessões XHTTP lógicas obtidas pelo health check.

## Módulos legados

Os módulos legados não são instalados com o núcleo. Use a opção 18 e informe o pacote opcional e seu SHA-256. O pacote v1.3 não inclui módulos V2Ray/Xray.

## Segurança

- arquivos de backup são criados com permissão `0600`;
- restauração é seletiva e valida hashes internos;
- configuração XHTTP é validada antes da troca atômica;
- falha no restart ou health check restaura a configuração anterior;
- certificados TLS não podem usar validação insegura;
- sessões e tokens XHTTP permanecem apenas em memória.

## Nexus DNSTT / SlowDNS opcional

Use `17) Nexus DNSTT / SlowDNS opcional`. O núcleo não ativa DNSTT automaticamente. A instalação exige um binário `dnstt-server` fornecido pelo administrador e o SHA-256 exato; o binário histórico do SSHPLUS é recusado. Consulte `docs/DNSTT-MODULE.md`.
