# Nexus SSH_XHTTP Server v1.2

Servidor próprio para transportar uma conexão SSH permitida por sessão HTTP/1.1 sobre TLS.

## Segurança e limites

- destinos permitidos explicitamente em `allowed_targets`;
- `max_sessions` e `max_sessions_per_ip` aplicados também às conexões pendentes;
- tokens aleatórios em memória;
- TLS obrigatório;
- serviço systemd sem privilégios;
- health endpoint sem dados sensíveis.

## Health check

```bash
nexus-xhttp-health
```

Endpoint:

```text
GET /nexus-xhttp/v1/health
```

## Validação de configuração

```bash
nexus-xhttp-server --check --config /etc/nexus-xhttp/server.json
```
