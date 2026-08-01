---
name: vix-radar-next-steps
description: >
  VIX Radar product advisor. Invoked as /vix-radar-next-steps to analyze pending work
  and suggest the next 3 prioritized actions. Reads Obsidian vault state + classifies
  by impact/effort. Output: priority table (P0/P1/P2) + quick wins. Terse, caveman-friendly.
argument-hint: "[--full]"
---

# VIX Radar — Next Steps Advisor

Analisa pendências abertas e sugere próximos passos priorizados por impacto × esforço.

## Fontes de dados

1. `E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\00 - Índice (MOC).md` — lista de pendências abertas
2. `E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\03 - Estado Atual.md` — estado Worker + frontend + incidentes
3. `E:\Diretorio\Claude\Monitoramento de Credito\CLAUDE.md` — regras invioláveis + arquitetura atual

## Formato de saída

```
VIX RADAR — PRÓXIMOS PASSOS (2026-06-16)

PRIORIDADE P0 (crítico/bloqueante):
→ [item] — [razão] — [esforço estimado]

PRIORIDADE P1 (alto impacto, baixo risco):
→ [item] — [razão] — [esforço estimado]

PRIORIDADE P2 (melhoria/roadmap):
→ [item] — [razão] — [esforço estimado]

QUICK WINS (< 1h, sem risco):
• [item]
• [item]
```

## Lógica interna

1. Lê `00 - Índice (MOC).md` seção "Pendências abertas"
2. Lê `03 - Estado Atual.md` seção de incidentes e próximos passos
3. Classifica cada pendência:
   - **P0**: incidentes ativos, falhas de segurança, bloqueadores de produção
   - **P1**: alto impacto para usuários finais, baixo esforço ou debloqueiam outros itens
   - **P2**: roadmap, melhorias de UX, features novas
   - **Quick win**: correção trivial (comentário, micro-drift, doc) — < 1 hora
4. Output: top 3 (uma por prioridade) + 2 quick wins

## Critérios de impacto (VIX Radar–específico)

Alto impacto:
- Afeta telemetria (cega o painel de Engajamento)
- Afeta verificador Haiku (quarentena silenciosa de eventos)
- Afeta 103 emissores em cron noturno
- Expõe credencial em produção

Baixo impacto:
- Comentário stale em arquivo
- Documentação desatualizada
- Micro-drift de version.json

## Opções

- `--full`: mostra todas as pendências classificadas (não só top 3 + quick wins)

## Quando usar

- Início de sessão: `/vix-radar-next-steps` após `/vix-briefing` para priorizar o trabalho
- Após resolver incidente: re-priorizar o que fazer a seguir
- Planejamento de sprint: `/vix-radar-next-steps --full` para visão completa

## Referências canônicas

- Obsidian MOC: `E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\00 - Índice (MOC).md`
- Estado: `E:\Diretorio\Claude\Monitoramento de Credito\Obsidian VIX Radar\03 - Estado Atual.md`
- CLAUDE.md: `E:\Diretorio\Claude\Monitoramento de Credito\CLAUDE.md`
