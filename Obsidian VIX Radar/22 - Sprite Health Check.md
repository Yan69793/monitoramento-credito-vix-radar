# Sprite Health Check — VIX Radar

**Data:** 2026-06-18  
**VM:** `site` (Sprites.app, org `default`)  
**URL VM:** https://site-bstvx.sprites.app

## Objetivo

Health check padrão do Worker a partir de **vantagem externa** (não depende da rede local do operador). Complementa o curl local do ritual pós-deploy.

## Script permanente

| Local | Caminho |
|-------|---------|
| Repo | `scripts/sprite/health_vix.sh` |
| Sprite VM | `health_vix.sh` (home `/home/sprite`) |

## Comandos

### Sync repo → Sprite

```powershell
.\scripts\sprite\push-health.ps1
```

### Execução manual

```powershell
sprite exec -s site -- sh health_vix.sh
```

### MCP (agente)

- Tool: `exec_command`
- `sprite`: `site`
- `command`: `sh health_vix.sh`

## Uso automático (agente)

Sem pedir confirmação quando:

- deploy Worker/Pages/endpoint
- auditoria `/vix-radar-audit` ou pós-edição `CLAUDE.md`
- incidente (outage, telemetria off)
- curl local falhou

Skill: `.claude/skills/sprite-health/` (`/sprite-health`)

## Validação 2026-06-18

```
HTTP:200 TEMPO:0.115608s
{"ok":true,"versao":"v4.9.139","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"verificador_ok":true}
```

## Limitação

`sprite exec` com `curl -s` direto falha — flags interceptadas pelo CLI. Usar sempre `sh health_vix.sh`.

`push_file` MCP falhou no Windows (`<< was unexpected`). Sync via `sprite file push`.

## Próximo passo

- [ ] Segundo sprite de backup (opcional)
- [ ] Webhook pós-deploy chamar health via n8n (Fase 2)