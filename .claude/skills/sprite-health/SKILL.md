---
name: sprite-health
description: >
  Health check VIX Radar via Sprite MCP (vantagem externa). Invocado como /sprite-health.
  Use automaticamente após deploy Worker, auditoria, incidente, ou quando curl local falhar.
  Script permanente: health_vix.sh na VM site.
---

# /sprite-health — Health check via Sprite

Valida o Worker `radar-credito-api` a partir da VM remota **`site`** (Sprites.app), complementando o curl local.

## Quando usar (automático — não pedir confirmação)

Acione **sem perguntar** quando qualquer destes for verdadeiro:

1. **Pós-deploy** Worker, Pages, endpoint, cron ou binding alterado
2. **Auditoria** `/vix-radar-audit` ou checklist pós-edição do `CLAUDE.md`
3. **Incidente** outage, degradação, telemetria ausente, health `ok:false`
4. **Usuário** menciona Sprite, MCP sprite, ou validação externa
5. **curl local** falhou, timeout, ou rede sandbox bloqueada

Se nenhum acima: curl local basta. Em deploy/auditoria/incidente: **curl local + Sprite** (dupla confirmação).

## Execução (MCP)

```
CallMcpTool server=sprite toolName=exec_command
  arguments: { "sprite": "site", "command": "sh health_vix.sh", "timeout": 60000 }
```

**Não** passar `curl` com flags direto no `exec_command` — o CLI `sprite exec` intercepta `-s`, `-w`, etc. O script `health_vix.sh` contorna isso.

## Critérios de sucesso

| Campo | Esperado |
|-------|----------|
| Linha HTTP | `HTTP:200` |
| `ok` | `true` |
| `bindings.kv` | `true` |
| `bindings.telemetria` | `true` |
| `bindings.rate_limiter` | `true` |
| `verificador_ok` | `true` |

Registrar no Obsidian em deploy/auditoria: origem **Sprite site**, corpo JSON bruto, HTTP e TEMPO.

## Sync do script (se alterou `scripts/sprite/health_vix.sh`)

```powershell
.\scripts\sprite\push-health.ps1
```

## Fallback se Sprite indisponível

```powershell
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```

## Limitações conhecidas

- `push_file` MCP pode falhar no Windows — usar `sprite file push` via `push-health.ps1`
- VM padrão: `site` (org `default`). Outra VM → atualizar skill + script