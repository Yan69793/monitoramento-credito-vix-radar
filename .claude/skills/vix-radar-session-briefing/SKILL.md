---
name: vix-radar-session-briefing
description: >
  VIX Radar project health briefing. Invoked as /vix-radar-briefing to output current state:
  versions, health check, top pendencies, next steps. Aggregates Obsidian docs + live Worker health.
  Terse output (~5-10 bullets, caveman-friendly). ~<5s response time.
argument-hint: "[--full]"
---

# VIX Radar Session Briefing

Automated project health briefing for new sessions.

## Quick Start

Invoke `/vix-radar-session-briefing` (or `/vix-briefing`) to get:

- **Estado:** versões (Worker, Frontend) + saúde geral
- **Health:** telemetria, bindings, providers (live curl)
- **Pendências:** top 3-5 de Obsidian MOC
- **Próximos passos:** 2-3 ações críticas do Estado de Produção

Output em modo **caveman** — máxima densidade, zero fluff.

---

## Formato de saída

```
VIX RADAR SESSION BRIEFING — 2026-06-16 18:35Z

Estado: ✅ SAUDÁVEL (v4.9.111 + v201.51)
Health: telemetria ✅ | kv ✅ | rate_limiter ✅ | providers 3/3

Pendências TOP 3:
1. v4.9.112: verificador_ok no health (credencial inválida cega 4+ dias)
2. SEGURANÇA: chave Anthropic exposta — rotacionar após sessão
3. OpenRouter 402 com saldo $76 — investigar billing

Próximos passos:
→ Noturno 18h replaya 33 eventos (quarentena 15-16/06)
→ Integrar 4 skills (análise/roadmap/segurança/quality)
→ Git commit: wrangler.toml + app/version.json
```

---

## Lógica interna

1. **Lê Obsidian**
   - `03 - Estado de Produção.md` → versão Worker, Frontend, status incidente
   - `00 - Índice (MOC).md` → pendências abertas (parse list)

2. **Health check live**
   - `GET https://radar-credito-api.prospects-intel.workers.dev` (timeout 3s)
   - Extrai: `versao`, `telemetria`, `bindings` (kv, rate_limiter), `providers_configurados`

3. **Agrega**
   - Estado (OK se telemetria:true e todos bindings:true, WARN se algum false)
   - Top 3 pendências (primeiro 3 bullets de MOC)
   - Top 2 próximos passos (do Estado de Produção "Próximos passos" seção)

4. **Output**
   - Timestamp UTC
   - 1 linha estado + health (emoji check/warn)
   - Lista pendências + próximos passos
   - Total ~<5s

---

## Opções

- `--full`: expande saída (10-15 bullets em vez de 5-10)

---

## Implementação esperada

O comando invoca:
```bash
# Lê Obsidian
cat "$HOME/Diretorio/Claude/Monitoramento de Credito/Obsidian VIX Radar/03 - Estado de Produção.md" | grep -A2 "Versões confirmadas"
cat "$HOME/Diretorio/Claude/Monitoramento de Credito/Obsidian VIX Radar/00 - Índice (MOC).md" | grep -A5 "Pendências abertas"

# Health check (3s timeout)
curl -s --max-time 3 https://radar-credito-api.prospects-intel.workers.dev | jq '.telemetria, .bindings, .providers_configurados'

# Agrega output
# [caveman-format briefing aqui]
```

---

## Referências canônicas

- Obsidian Estado: `E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\03 - Estado de Produção.md`
- Obsidian MOC: `E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\00 - Índice (MOC).md`
- Health endpoint: `https://radar-credito-api.prospects-intel.workers.dev`
- CLAUDE.md: `E:\Diretorio\Claude\Monitoramento de Credito\CLAUDE.md`

---

## Quando usar

- **Novo dia, nova sessão:** `/vix-briefing` → 10 segundos de context
- **Quick health check:** `/vix-briefing` antes de começar a trabalhar
- **Antes de deploy:** confirma estado + pendências
- **Após merge:** verifica se algo quebrou ou ficou pendente
