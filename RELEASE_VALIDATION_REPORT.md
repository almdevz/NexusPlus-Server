# Relatório de validação — NexusPlus Server v1.3

## Escopo

A v1.3 incorpora o Nexus DNSTT/SlowDNS como módulo oficial opcional, mantendo o núcleo SSH, APP Online e Nexus SSH_XHTTP. O módulo não é ativado durante a instalação do painel e não inclui Xray, V2Ray, VLESS, libXray ou UUID.

## Resultados

```text
PACKAGE_VERSION=1.3.0
SHELL_SYNTAX=PASS
PYTHON_SYNTAX=PASS
BASE_JSON_DNSTT_GENERATION=PASS
BASE_JSON_SIGNATURE_CLEARED=PASS
EXISTING_SERVERS_PRESERVED=PASS
EXISTING_NETWORKS_PRESERVED=PASS
DNSTT_MENU_INTEGRATION=PASS
DNSTT_SYSTEMD_UNIT_VALIDATED=PASS
DNSTT_BINARY_SHA256_REQUIRED=PASS
DNSTT_LEGACY_BINARY_DENYLIST=PASS
DNSTT_UNVERIFIED_DOWNLOAD_PRESENT=NO
DNSTT_CONFIG_VALIDATION=PASS
DNSTT_BACKUP_CREATE_INSPECT=PASS
DNSTT_BACKUP_RESTORE_LOGIC=PASS_WITH_MOCKED_SYSTEMD
DNSTT_HEALTH_LOCAL_CHECKS=PASS
DNSTT_REAL_DNS_DELEGATION_TEST=NOT_AVAILABLE
DNSTT_REAL_CLIENT_END_TO_END=NOT_AVAILABLE
DNSTT_BINARY_BUNDLED=NO
DNSTT_REFERENCE_UPSTREAM_VERSION=v1.20260501.0
XHTTP_REGRESSION=PASS_EXISTING_TESTS
GO_TESTS=PASS
GO_RACE_TEST=PASS
V2RAY_XRAY_INCLUDED=NO
SHA256SUMS_VALIDATION=PASS
```

## Limitação deliberada

O pacote não incorpora o executável histórico DNSTT encontrado no legado, pois ele é antigo, não versionado e não possui proveniência suficiente. O administrador deve fornecer um binário confiável e o SHA-256 exato. O instalador registra e verifica esse hash em cada inicialização.

## Homologação restante

A homologação completa exige VPS com subdomínio NS delegado, UDP/53 acessível externamente e cliente DNSTT no Nexus Connect. Esses testes não foram simulados como se fossem reais.
