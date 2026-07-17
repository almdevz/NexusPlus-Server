# Módulo oficial Nexus DNSTT

O DNSTT é opcional e não é ativado durante a instalação do núcleo. O módulo transporta o SSH local por um subdomínio DNS delegado e permanece separado do Nexus SSH_XHTTP.

## Segurança da distribuição

O NexusPlus não usa o binário histórico presente nos módulos SSHPLUS. Para instalar, forneça um `dnstt-server` de fonte confiável e o SHA-256 exato:

```bash
sudo /opt/nexusplus/dnstt/install-server.sh \
  --binary /root/dnstt-server-linux-amd64 \
  --sha256 SEU_SHA256_DE_64_CARACTERES \
  --domain t.seudominio.com
```

A versão de referência fixada no módulo é `v1.20260501.0`. O hash do binário efetivamente instalado fica registrado em `/etc/nexus-dnstt/server.json` e é verificado em todo start e health check.

## DNS

No provedor DNS, delegue o subdomínio do túnel a um registro NS que aponte para esta VPS. O painel não altera automaticamente o DNS público do domínio.

## Arquitetura

- `dnstt-server` executa como usuário sem login `nexus-dnstt`;
- escuta interna padrão UDP/5300;
- regra transacional redireciona UDP/53 para UDP/5300;
- backend padrão: `127.0.0.1:22`;
- chaves em `/etc/nexus-dnstt`;
- serviço `nexus-dnstt.service` com hardening systemd;
- backup/rollback seletivo no formato NexusPlus v2.

## Comandos

```bash
nexus-dnstt status
nexus-dnstt health
nexus-dnstt logs
nexus-dnstt show-client
nexus-dnstt backup
```

## JSON Android

O gerador adiciona uma rede com:

```json
{
  "connection_type": "dnstt",
  "dnstt_dns_server": "1.1.1.1:53",
  "dnstt_domain": "t.seudominio.com",
  "dnstt_public_key": "CHAVE_PUBLICA",
  "dnstt_local_port": 7001,
  "dnstt_mtu": 1232
}
```

O arquivo gerado fica sem assinatura e deve ser assinado pelo Nexus JSON Signer antes da publicação.
