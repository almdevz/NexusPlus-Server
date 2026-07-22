# NexusPlus Server v1.4

Painel limpo para Debian/Ubuntu, sem copiar ou executar módulos legados do SSHPLUS.

## Funções
- usuários SSH, usuários teste persistentes, expiração, limite real e monitor online;
- portas editáveis e rollback para OpenSSH, Squid, Dropbear, WebSocket e SSL/Stunnel;
- OpenVPN com PKI Easy-RSA e geração/revogação de clientes;
- SlowDNS/DNSTT compilado do projeto oficial;
- BadVPN UDPGW compilado do código-fonte oficial e restrito a loopback;
- Chisel fixado na versão v1.11.5;
- Nexus SSH_XHTTP, health check, APP Online, backup seletivo e restore sem sobrescrever contas do sistema.

## Instalação pelo GitHub
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/almdevz/NexusPlus-Server/main/install-online.sh)
```

Ou:
```bash
git clone https://github.com/almdevz/NexusPlus-Server.git
cd NexusPlus-Server
sudo ./install.sh
nexus
```

## Segurança
- nenhum arquivo da pasta `legacy/SSHPLUS-Modulos` é incluído;
- SOCKS aberto na VPS não é criado; o SOCKS é feito por encaminhamento dinâmico autenticado do SSH;
- BadVPN escuta somente em `127.0.0.1`;
- configurações críticas são validadas e restauradas quando a aplicação falha;
- certificados autoassinados do Stunnel são apenas fallback inicial. Para produção, substitua por certificado válido.

## Limitações
V2Ray e Trojan-Go não são incluídos na distribuição limpa porque não fazem parte do transporte Nexus SSH_XHTTP e adicionariam outra pilha de autenticação/protocolo. O painel concentra-se em SSH e transportes que encaminham para SSH.
