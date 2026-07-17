# Origens e decisões

- NexusPlus Server v1.1 fornecido pelo usuário: base funcional das revisões v1.2/v1.3.
- Módulos SSHPLUS históricos: movidos para pacote opcional separado; módulos V2Ray/Xray foram excluídos.
- Documentação pública DTProto: referência de experiência de gerenciamento, sem distribuição de binários DTProto/DTProxy.
- Nexus SSH_XHTTP: implementação própria em Go, protocolo versão 1, sem Xray, VLESS, libXray ou UUID de autenticação.
- JSON Nexus Connect fornecido pelo usuário: base estrutural para geração do arquivo não assinado; credenciais são sanitizadas no modelo distribuído dentro do pacote.
- DNSTT: módulo opcional reescrito; versão upstream de referência v1.20260501.0; nenhum script legado é executado.
