---
data: 2026-08-18
tipo: auditoria
tags: [vix-radar, auditoria, preditivo, merton]
status: ativo
---

# Auditoria Geral + Preditiva 2026-08-18

Readonly, sem deploy, sem commit. Escopo: general-audit (backend, frontend, veracidade UI, seguranca, perf, a11y, cascade) + predictive (pipeline, Merton, z-scores, coleta).

## Veredito

Saudavel no nucleo. Health `ok:true` v4.9.195 com todos os sub-checks, drift zero nos dois eixos, veracidade da UI conferida e correta nos 5 indicadores do Market Overview. Um achado P2 real na camada preditiva (Merton inativo em producao) e P3s de governanca e a11y.

## Achado principal: Merton DD nunca roda (0/103)

`predictive_v1:latest` no KV (run 17/08, 103/103 com score): `merton_dd` e null para **todos** os emissores, driver `merton` nunca aparece. Causa raiz confirmada nas chaves do KV: `market_cap` vazio tanto em `fundamentals:altman:latest` (Petrobras: z_em=4.7, divida_cp=67,25bi, divida_lp=316,77bi, market_cap vazio) quanto em `cotacoes:volatilidade:v1` (Petrobras: vol_anualizada=0.239, market_cap vazio). O gate do codigo exige `market_cap > 0` de proposito (comentario: "preco por acao e patrimonio liquido nao sao substitutos validos"), e nenhuma coleta preenche o campo. O SKILL.md do general-audit (MERTONLIVE1) assume que "calcMertonDD move score em producao" — premissa falsa desde a implementacao. O codigo de calcMertonDD/scoreMertonToRisk esta correto (KMV iterativo, conferido linha a linha), so nao e exercitado.

Correcao: preencher market_cap na coleta (cotacao x n. de acoes, ou fonte externa) ou declarar oficialmente o Merton em stand-by ate a Fase A do v2. Guarda: contador `com_merton` no payload do pipeline + check na skill preditiva.

## Demais achados

- P3 governanca: `graphify-out/` nao esta no .gitignore e versiona cache de tooling (14 entradas de ruido no working tree a cada execucao).
- P3 frontend: email do admin hardcoded em `app/index.html:4079` para revelar "Painel Admin" no cmdk. O JWT ja carrega `role:admin`, usar o role em vez do email.
- P3 a11y: 3 divs clicaveis sem role/tabindex (mo-table-row, mo-heatmap-row), teclado nao navega no Market Overview.
- P3 veracidade: card "Sem alertas" nao declara a janela de 30 dias no proprio card (o footer da tabela declara; o contrato do glossario pede declaracao no indicador fixo ao lado de filtro).

## Confirmado saudavel (com evidencia)

- Health `ok:true`, kv/rate_limiter/telemetria true, admin_email_ok/sentry_ok/verificador_ok true, HTTP 200.
- Versoes: Worker v4.9.195 repo=prod, frontend v202.10 repo=prod, `deploy_zip` sincronizado por hash.
- Veracidade UI: script `audit-ui-metrics.mjs` exit 0; conferencia manual: Emissores=103 (universo), Criticos=distintos CRITICO 30d, Relevantes=distintos RELEVANTE excluindo criticos, Sem alertas=(103-crit-rel)/103 com denominador e limiares corretos, Setor+Afetado coerente.
- Seguranca: CORS allowlist sem fallback inseguro, contrato de rotina 403 fail-closed (probe anonimo confirmado), JWT HMAC SHA-256, `sanitizarPayloadRadar` com strip HTML no write path, `esc()` no admin e `x()` no Market Overview, `strong` sem color global.
- Pipeline preditivo: 103/103 com score, z-scores ANBIMA vivos (73 emissores, 5 ALERTA, 2 ELEVADO, 0 CRITICO, calculado 17/08 21:34), filtro de liquidez ativo (11 emissores amortecidos), spread_rel_setor shadow com peso zero (65 emissores), Altman coletado (90 com z_em, ainda nao pontua no rule, coerente com roadmap).
- Tasks: Coleta-Volatilidade LR=0, Export-Historico LR=0, Reconciliacao-CVM LR=0, retry tasks novas Ready, 3 tasks do Claude Desktop Disabled (guarda anti-duplicata).
- Fundacao de dados: `data/historico/` ate 17/08, `data/labels/eventos_credito.jsonl` 299 KB.
- Scheduled: disjuntores so nos crons LLM, watchdog e agenda rodam sempre, cada passo com try/catch + heartbeat, pipeline preditivo roda nos dois crons.

## Lacunas declaradas

- Existencia do secret OPENROUTER_API_KEY nao confirmada (token atual nao lista secrets; o codigo so consulta se existir).
- Perf/a11y por analise estatica, sem browser real nesta auditoria.
- `npm test` nao roda local (Smart App Control), CI verde no ultimo push.
- Fila de verificacao real nao exercitada; health `verificador_ok:true` confirma o SLA.

Detalhe dos achados com causa raiz e guarda: ver relatorio da sessao.
