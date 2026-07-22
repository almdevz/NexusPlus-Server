# Nexus SSH_XHTTP v3

O protocolo v3 transporta uma conexão SSH por HTTPS sem Xray, VLESS, VMess ou UUID de autenticação.
A autenticação final continua sendo feita pelo OpenSSH com usuário e senha.

## Fluxo

1. `POST {base}/session` cria uma sessão temporária.
2. `GET {base}/{session_id}` abre o canal persistente de download.
3. `POST {base}/{session_id}/0`, `/1`, `/2`... envia blocos SSH em ordem.
4. `DELETE {base}/{session_id}` encerra a sessão.

## Criação da sessão

```http
POST /nexus-xhttp/v3/session HTTP/1.1
Content-Type: application/json
X-Nexus-Protocol: 3
```

```json
{
  "protocol": "nexus-ssh-xhttp",
  "version": 3,
  "client_nonce": "BASE64URL_SEM_PADDING"
}
```

Resposta `201`:

```json
{
  "session_id": "temporario",
  "session_token": "temporario",
  "expires_in": 300,
  "version": 3,
  "upload_mode": "sequential-post"
}
```

Todos os canais da sessão usam:

```http
Authorization: Bearer SESSION_TOKEN
X-Nexus-Protocol: 3
```

## Download

```http
GET /nexus-xhttp/v3/{session_id}
```

A resposta `200 application/octet-stream` permanece aberta e entrega os bytes recebidos do SSH.

## Upload

```http
POST /nexus-xhttp/v3/{session_id}/{sequence}
Content-Type: application/octet-stream
Content-Length: N
```

A sequência começa em `0` e cresce sem saltos. O servidor aceita somente um POST por vez por sessão e responde `204`.
Repetição ou salto recebe `409 out_of_order`.

## Segurança

- TLS usa certificado confiável, SNI e hostname válidos.
- O destino SSH é fixado no servidor por `fixed_target`, normalmente `127.0.0.1:22`.
- O cliente não transforma o serviço em proxy arbitrário.
- IDs e tokens são aleatórios, temporários e não são usados como autenticação SSH.
- Há limites globais, por IP, de tamanho por POST, inatividade e expiração.

## Compatibilidade

O servidor pode manter o protocolo v2 anterior habilitado com `enable_legacy_v2: true` durante a migração.
