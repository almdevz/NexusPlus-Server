# Nexus XHTTP v3

Servidor próprio de transporte SSH sobre HTTPS.

## Características

- GET persistente para download;
- POSTs sequenciais numerados para upload;
- destino SSH fixo no servidor;
- TLS com validação normal;
- sessão e token temporários;
- compatibilidade opcional com v2;
- health check em `{base_path}/healthz`;
- sem Xray, VLESS, VMess, DTProxy ou UUID de autenticação.

## Instalação

```bash
sudo ./install-server.sh
```

## Validação

```bash
sudo nexus-xhttp-server --config /etc/nexus-xhttp/server.json --check
curl -fsS https://DOMINIO:PORTA/nexus-xhttp/v3/healthz
```
