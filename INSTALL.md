# Instruções de instalação — NexusPlus Server v1.3

## Requisitos

- Debian 11/12 ou Ubuntu 20.04/22.04/24.04;
- acesso root;
- systemd;
- arquitetura amd64 ou arm64 para Nexus XHTTP;
- DNS apontado para o servidor quando Certbot for utilizado.

## Instalação principal

```bash
sha256sum -c SHA256SUMS
unzip NexusPlus-Server-v1.3.zip
cd NexusPlus-Server-v1.3
sudo ./install.sh
nexus
```

## Atualização da v1.1

Execute o instalador da v1.3 sobre a instalação existente:

```bash
sudo ./install.sh --upgrade
```

O instalador preserva `/etc/nexusplus`, migra limites/expirações e adiciona os timers persistentes.

## Instalar Nexus SSH_XHTTP

No menu `nexus`, escolha a opção 16 e depois `Instalar/atualizar`.

Você poderá escolher:

1. certificado existente;
2. Certbot standalone.

O instalador valida certificado e chave, inicia o serviço e exige health check aprovado. Em falha, restaura a instalação XHTTP anterior.

## Gerar JSON do aplicativo

No menu XHTTP, escolha `Gerar config_ssh_xhttp_unsigned.json`, ou execute:

```bash
sudo nexus-generate-xhttp-config \
  --input /caminho/config.json \
  --output /root/config_ssh_xhttp_unsigned.json \
  --server IP_OU_DOMINIO_XHTTP \
  --host DOMINIO_XHTTP \
  --port 8443 \
  --base-path /nexus-xhttp/v1
```

O arquivo gerado não possui assinatura válida. Assine posteriormente com o Nexus JSON Signer.

## Backup

No menu, escolha `Backup seletivo`. O arquivo contém manifesto e hashes internos e é salvo com permissão 0600.

## Update e rollback

Use a opção 18. Pacotes locais exigem SHA-256. Antes de atualizar, o painel cria snapshot em `/var/lib/nexusplus/updates`.

## Módulos legados

Use a opção 17 e forneça o pacote legado separado e o SHA-256 publicado.


## Módulo DNSTT opcional

Após instalar o painel, use a opção 17. O instalador exige um arquivo `dnstt-server`, o SHA-256 exato e um subdomínio DNS delegado. Nenhum binário DNSTT é executado sem hash. Consulte `docs/DNSTT-MODULE.md`.
