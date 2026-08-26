# SKILLS-ROUTER — VIX Radar

Roteamento leve. Ler **só este arquivo** na descoberta de skills. Carregar `SKILL.md` completo apenas após match confirmado.

Gerar índice local: `pwsh scripts/skills-index.ps1`

## Regras

1. Default = skill mais barata em tokens
2. `/vix-radar-audit` completo só sob pedido explícito
3. `npx skills find` só se router + índice local falharem
4. Nunca `Glob` recursivo no repo para descobrir skills

## Mapa intent → skill

| Intent | Skill | Modo | Não carregar |
|--------|-------|------|--------------|
| Abrir sessão, status rápido | `/vix-radar-briefing` | default | audit, Obsidian inteiro |
| Pós-deploy Worker/Pages | `/sprite-health` | auto | `/vix-radar-audit` |
| Health local falhou/sandbox | `/sprite-health` | auto | — |
| Priorizar backlog | `/vix-radar-next-steps` | default | audit |
| Auditoria completa | `/vix-radar-audit` | `--quick` primeiro | carteiras |
| Auditoria geral backend/frontend, arquitetura, seguranca/perf/a11y | `/vix-radar-general-audit` | readonly primeiro | deploy |
| Drift repo/prod, pós-incidente | `/vix-radar-audit` | `--readonly` se só leitura | — |
| Deploy Worker, wrangler, KV, DO | `/wrangler` + `/workers-best-practices` | — | audit |
| Feature/debug profundo Radar | `radar-credito-privado` (VIXRADAR/skills) | lazy | só quando necessário |
| Incidente urgente | `/ODDA` | — | — |
| Resposta densa/expert | `/299` ou `/godmode` | sob pedido | — |
| Humanizar texto | `/ghost` | — | — |
| Protótipo HTML | `/artifact` | — | — |
| Descobrir skill nova | `/find-skills` | local primeiro | instalar sem confirmação |
| Executar plano PR DAG | `/execute-plan` | sob pedido | subagentes paralelos |
| Fluxo superpowers (plan/debug/TDD) | `/using-superpowers` → skill filha | sob pedido | auto em toda mensagem |

## Skills locais (projeto)

| Skill | Escopo |
|-------|--------|
| `vix-radar-briefing` | Sessão, versões, health, top pendências |
| `sprite-health` | Health Worker via VM Sprite |
| `vix-radar-audit` | Vistoria multi-camada |
| `vix-radar-general-audit` | Auditoria geral backend/frontend, segurança, performance, acessibilidade e dívida técnica |
| `vix-radar-next-steps` | P0/P1/P2 + quick wins |
| `wrangler` | CLI Cloudflare |
| `workers-best-practices` | Anti-patterns Worker |
| `ODDA` | Decisão sob pressão |
| `ghost` | Texto humano |
| `299` / `godmode` | Profundidade máxima |
| `artifact` | Entregável visual |
| `execute-plan` | Orquestrar PR stack a partir de design doc |
| `writing-plans` / `executing-plans` | Plano + execução superpowers |
| `systematic-debugging` | Debug estruturado |
| `using-superpowers` | Meta — roteamento obrigatório de skills |

## Ordem de descoberta (rotina /skills)

```
1. Este arquivo (SKILLS-ROUTER.md)
2. pwsh scripts/skills-index.ps1  → tabela compacta
3. Ler 1 SKILL.md do match
4. npx skills find [query]        → só se passos 1-3 falharem
```

## Limites de governança

- SKILL.md novo: ≤ 8 KB texto
- Assets binários: pasta `references/`, nunca inline no markdown
- Duplicata global: não instalar skill já presente em `.claude/skills` do projeto

## Tokens no system prompt (fix 2026-06-19)

**SKILLS-ROUTER não reduz `agent_skills` injetado a cada turno.** Só guia descoberta manual.

| Camada | O que faz |
|--------|-----------|
| Dump global arquivado | `~/.grok/_off-skills`, `~/.agents/_off-skills`, `~/.claude/_off-skills` |
| Config | `~/.grok/config.toml` — `compat.claude skills=false`, sem `extra_skill_dirs` |
| Projeto | `.grok/skills/` (junctions) + `.claude/skills/` — 11 skills VIX |
| Rotinas 103 | `~/.claude/scheduled-tasks/vixradar-{matinal,noturno}/` — **independente** do chat |

**Verificar:** `pwsh scripts/skills-verify-tokens.ps1` + `node scripts/check-emissores-cnpj.mjs` + `node scripts/check-emissores-cadastro.mjs`

**Restaurar tudo:** `pwsh scripts/skills-restore.ps1` + backup `config.toml.bak-pre-skills-fix`

**Não fazer:** `import-claude` / `sk sync` sem confirmação — repõe dump global.

**Sessão nova obrigatória** após mudança de config/arquivo para tokens caírem no chat.
