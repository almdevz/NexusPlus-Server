# Nexus SSH_XHTTP Protocol v1

## Identidade

- `CONNECTION_TYPE=ssh_xhttp`
- `NEXUS_SSH_XHTTP_PROTOCOL_VERSION=1`
- HTTP/1.1 sobre TLS.
- Sem Xray, VLESS, VMess, UUID VLESS ou SOCKS intermediário.
- XHTTP transporta bytes; OpenSSH autentica com `user` e `pass`.

## Base path e porta

A porta é configurável. O base path padrão é `/nexus-xhttp/v1`.

## Criação da sessão

`POST {base_path}/session`

Headers: `Host`, `User-Agent: NexusConnect/1`, `Accept: application/json`, `Content-Type: application/json`, `X-Nexus-Protocol: 1`, `Connection: close`.

```json
{
  "protocol": "nexus-ssh-xhttp",
  "version": 1,
  "target_host": "SERVER_IP_SELECIONADO",
  "target_port": 22,
  "client_nonce": "BASE64URL_SEM_PADDING"
}
```

O nonce contém 32 bytes de `SecureRandom`. O servidor **deve validar o destino contra `allowed_targets`**; nunca deve funcionar como proxy aberto.

Resposta `201 Created`:

```json
{
  "session_id": "BASE64URL_SEM_PADDING",
  "session_token": "BASE64URL_SEM_PADDING",
  "expires_in": 120
}
```

`session_id`, `session_token` e `client_nonce` são efêmeros e não são credenciais permanentes de usuário.

## Download

Abrir primeiro:

`GET {base_path}/session/{session_id}/download`

Com `Authorization: Bearer {session_token}` e `X-Nexus-Protocol: 1`.

Resposta: `200 OK`, `application/octet-stream`, `Transfer-Encoding: chunked`. O corpo contém somente bytes do OpenSSH.

## Upload

Abrir depois do download:

`POST {base_path}/session/{session_id}/upload`

Com `Authorization: Bearer {session_token}`, `Transfer-Encoding: chunked`, `Expect: 100-continue`.

O servidor responde `100 Continue` antes de consumir o corpo. Cada chunk carrega bytes SSH binários sem Base64 ou framing adicional. O chunk zero encerra a escrita e a resposta final é `204 No Content`. O download pode continuar aberto para half-close.

## Encerramento

`DELETE {base_path}/session/{session_id}` com Bearer token. Resposta `204 No Content`. É best effort e idempotente do ponto de vista do cliente.

## TLS

TLS 1.2 e 1.3 quando disponíveis. Certificado validado pelo SNI com trust store do sistema. Sem `allow insecure` remoto, TrustManager permissivo ou hostname verifier inseguro.

## Segurança do destino

Como o Android envia `target_host` e `target_port`, o servidor deve conter uma allowlist explícita (`allowed_targets`). Uma solicitação fora da lista retorna `403 target_not_allowed`. Isso é obrigatório para impedir proxy aberto.

## Ordem

1. Criar sessão.
2. Abrir download e exigir 200.
3. Abrir upload e exigir 100 Continue.
4. Entregar streams à Trilead.
5. Handshake e autenticação SSH.
6. DynamicPortForwarder.
7. VPN/TUN/tun2socks.

## Limites

JSON de sessão: 65536 bytes. Headers e parser estrito ficam sob responsabilidade do cliente Android conforme a especificação de integração. O servidor usa limites do `net/http` e configuração própria.

## Health check v1.2

`GET {base_path}/health`

Resposta `200 OK`:

```json
{
  "status": "ok",
  "protocol_version": 1,
  "server_version": "1.2.0",
  "active_sessions": 0,
  "pending_sessions": 0,
  "max_sessions": 1000,
  "uptime_seconds": 10
}
```

O endpoint não retorna tokens, destinos ou endereços de clientes.

## Aplicação dos limites v1.2

O servidor reserva uma vaga antes de iniciar a conexão TCP com o backend SSH. Sessões ativas e conexões pendentes são contabilizadas juntas. Isso impede que requisições simultâneas ultrapassem `max_sessions` ou `max_sessions_per_ip` durante a janela de conexão ao backend.
