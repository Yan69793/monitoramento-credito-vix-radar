# Protocolo Operacional — VIX Radar (hardened 2026-07-25)

## Memória canônica

Vault Obsidian: `E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\`
Começar por `00 - Índice (MOC).md` e `03 - Estado Atual.md`.
Se conflito chat vs Obsidian: Obsidian prevalece.
Nunca deixar informação crítica só no chat — gravar no Obsidian ao final.

Repo: `monitoramento-credito-vix-radar.git` (branch `main`).

## Regras de infra

### Deploy
- Worker: `pwsh ./scripts/deploy-worker.ps1 -Version v4.9.XXX`. Nunca `wrangler deploy` direto.
- Pages: `pwsh ./scripts/deploy-pages.ps1`. Sincroniza `app/deploy_zip/` antes.
- Wrangler 4.x: sempre `--no-autoconfig`. Sem isso detecta `E:\Diretorio\Claude\dashboard` como projeto.
- Fonte do Worker: `api/src/worker.js`; gerar com `pwsh ./scripts/build-worker.ps1 -Version v4.9.XXX`.
- Bundles `api/v4.*.js` são artefatos gerados — não editar diretamente; publicar com `no_bundle=true`.
- Fonte viva do frontend: `app/index.html` → sincronizar `app/deploy_zip/` antes do deploy.
- Token Cloudflare: variável de ambiente do sistema, nunca no repo.

### Bindings obrigatórios
- `RADAR_USAGE_EVENTS` em `api/wrangler.toml`. Pós-deploy validar `telemetria:true`.
- `RADAR_KV` + `RateLimiterDO` — não remover bindings.

### CSS
- `<strong>`: sem `color` global, só `font-weight`. Cor por seletor específico se necessário.

### Multi-semana
- Endpoints `op=state`, `op=ews`, `briefing_executivo`, `historico_emissor`, `comparar` usam `carregarEstadoMultiSemana(env, 5)`. Escrita na semana corrente.

## Portão de verificação

Antes de declarar qualquer tarefa concluída, execute:
```powershell
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```
Esperado: HTTP 200, `ok:true`, `telemetria:true`, `kv:true`.
Cole a saída real na resposta. Se falhar ou não puder executar, diga explicitamente. Nunca declare "funcionando" sem a saída colada.
