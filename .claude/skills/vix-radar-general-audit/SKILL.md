---
name: vix-radar-general-audit
description: >
  Auditoria geral de engenharia do VIX Radar cobrindo backend Cloudflare Worker,
  frontend Pages/app/index.html, seguranca, auth/CORS, secrets, telemetria,
  performance, acessibilidade, confiabilidade, deploy, drift repo/producao,
  divida tecnica e qualidade de codigo. Use quando o usuario pedir auditoria
  geral, audit geral backend e frontend, revisar arquitetura, varrer o projeto,
  encontrar riscos, revisar seguranca/performance do app, ou preparar um relatorio
  tecnico priorizado alem do health operacional.
---

# VIX Radar General Audit

Auditoria ampla de engenharia para o VIX Radar. Esta skill complementa
`vix-radar-audit`: use `vix-radar-audit` para health operacional/producao e esta
skill para revisao de backend + frontend + qualidade do projeto.

## Antes de auditar

1. Ler `CLAUDE.md`, `.claude/SKILLS-ROUTER.md`, `Obsidian VIX Radar/00 - Indice (MOC).md` e `Obsidian VIX Radar/03 - Estado de Producao.md`.
2. Ler a matriz em `references/audit-matrix.md`.
3. Carregar skills auxiliares conforme escopo:
   - `vix-radar-audit` para health, drift e evidencia de producao.
   - `workers-best-practices` para Cloudflare Worker.
   - `web-perf` quando medir frontend em navegador.
4. Manter modo readonly por padrao. Nao deployar, nao alterar secrets e nao fazer POST destrutivo sem pedido explicito.

## Escopo padrao

Auditar estas camadas:

| Camada | Evidencia minima |
|---|---|
| Repo e governanca | `git status`, ultimo commit, arquivos untracked, artefatos legados, documentacao viva |
| Backend Worker | `api/wrangler.toml`, bundle ativo `api/v4.9.*.js`, bindings, routes, crons, auth, CORS, rate limit, telemetria |
| Frontend | `app/index.html`, `app/admin/*.js`, `app/deploy_zip/`, versionamento, cache, auth headers, estados vazios/erro |
| Seguranca | ASVS/WSTG: secrets, hardcoded data, JWT, fail-open/fail-closed, inputs, headers, logs, admin actions |
| Performance | Core Web Vitals, payload HTML/JS, bloqueio de main thread, cache headers, dependencias, assets |
| Acessibilidade | WCAG 2.2 AA pragmatica: teclado, foco, labels, contraste, estados, tabelas, dialogs |
| Confiabilidade | health real, verificador, ingestao, KV, DO, crons, retries, idempotencia, observabilidade |
| Produto/dominio | cobertura 103 emissores, materialidade, datas CVM, rotina matinal/noturna, UX de risco |

## Metodo

1. **Inventario rapido:** listar estrutura relevante sem varrer diretorios legados em profundidade (`producao/`, `_historico/`, `archive/`, `vixradar/`).
2. **Mapa de versoes:** comparar repo vs producao para Worker e frontend. Se houver drift, classificar antes de qualquer conclusao tecnica.
3. **Leitura dirigida:** inspecionar os arquivos vivos, nao os bundles antigos. Worker vivo = `api/wrangler.toml main`. Frontend vivo = `app/index.html` e modulos em `app/admin/`.
4. **Checks automaticos baratos:** sintaxe, busca por padroes de risco, diff, tamanhos, headers publicos, health publico.
5. **Amostragem manual profunda:** escolher fluxos criticos: login, `op=state`, `receber_analise`, admin, newsletter, briefing/comparar, pulso manual.
6. **Classificacao:** separar bug confirmado, risco plausivel, divida tecnica e melhoria de produto.
7. **Evidencia:** cada achado precisa de arquivo+linha, comando/HTTP bruto, ou trecho de diff. Sem evidencia, registrar em "lacunas".

## Checks especificos VIX Radar

- Nao editar bundles antigos; a verdade de deploy e `api/wrangler.toml`.
- Confirmar que `RADAR_USAGE_EVENTS` continua declarado e usado.
- Confirmar que `RADAR_KV`, `RATE_LIMITER_DO`, route `api.vixradar.com` e crons permanecem no `wrangler.toml`.
- Confirmar que o health publico nao mascara falhas de verificador, ingestao ou telemetria.
- Confirmar que `receber_analise` nao aceita eventos e grava `sem_eventos:true` por erro de schema.
- Confirmar que endpoints multi-semana usam `carregarEstadoMultiSemana(env, 5)`.
- Confirmar regra CSS global: `strong` sem `color`, apenas `font-weight`.
- Confirmar que `app/deploy_zip/` esta sincronizado com `app/` antes de qualquer deploy Pages.
- Tratar `openrouter`, `gemini` e `perplexity` em health como residuos de schema, salvo evidencia de uso vivo.

## Severidade

| Nivel | Criterio |
|---|---|
| P0 Critico | Perda de dados, auth fail-open, secret exposto, ingestao cega, prod quebrada, drift perigoso |
| P1 Alto | Telemetria ausente, verificador degradado, admin inseguro, frontend derruba sessao, cron inconsistente |
| P2 Medio | Divida tecnica com risco claro, cache/version drift, a11y/perf com impacto real, testes faltando em fluxo critico |
| P3 Baixo | Limpeza, organizacao, docs, melhorias de DX, refatoracao sem impacto imediato |

## Saida esperada

Entregar relatorio curto e acionavel:

```markdown
# Auditoria Geral — VIX Radar (YYYY-MM-DD)

## Veredito
[saudavel / degradado / critico em 2-4 frases]

## Top riscos
| Sev | Area | Achado | Evidencia | Acao |

## Backend
[achados confirmados, lacunas]

## Frontend
[achados confirmados, lacunas]

## Seguranca, perf e a11y
[achados confirmados, lacunas]

## Proximos passos
[P0/P1/P2 em ordem]
```

Ao final de auditorias relevantes, registrar resumo e pendencias no Obsidian, conforme `CLAUDE.md`.
