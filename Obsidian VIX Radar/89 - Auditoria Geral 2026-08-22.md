---
data: 2026-08-22
tipo: auditoria
tags: [vix-radar, auditoria-geral, veracidade-ui]
status: saudavel
---

# Auditoria Geral 2026-08-22 — VIX Radar

Readonly, skill `vix-radar-general-audit`. Sem deploy, sem mudança em produção.

## Veredito

Saudável. Núcleo verificado sem achado novo: auth fail-closed nos 3 probes, veracidade da UI batendo com o glossário nos 3 termos reservados, drift zero nos dois eixos (Worker v4.9.208, frontend v202.28), health completo verde. Achados novos são todos P3 de documentação e rotulagem.

## Achados novos (entraram em [[PENDENCIAS.md]])

| Sev | Achado | Evidência |
|---|---|---|
| P3 | Changelog do `wrangler.toml` parado em v4.9.195, banner diz `main = v4.9.195` com main real `v4.9.208.js`, zero entradas v4.9.196-208 | `rg "v4\.9\.20[0-9]" api/wrangler.toml` = 1 (só o main) |
| P3 | Pulso do Market Overview diz "N eventos relevantes" contando EMISSORES, contrariando o glossário (Relevantes = emissores distintos) | `app/index.html:4173`, ramo `relevantesAtivos` |
| P3 | Card "Sem alertas" declara denominador mas não a janela fixa de 30 dias, exigência do glossário por estar ao lado do toggle 7D/30D que não o afeta | `app/index.html:4181`, sub termina em "de Y emissores" |
| P3 | Seção "Versoes" do [[03 - Estado Atual]] parada em v4.9.194/v202.9, topo já declara v4.9.208/v202.28. Mesmo padrão reconciliado em 11/08, voltou | `03 - Estado Atual.md:159-161` |
| P3 | Working tree sujo da sessão de 21/08: MOC + ESTADO modificados, notas 87 e 88 untracked, main ahead 1 (`50384b3`) | `git status --short --branch` |

Observação de design, não achado: `dados_para_analise` usa `carregarEstadoMultiSemana(env2222, 2)`, contexto histórico da rotina limitado a 2 semanas. Eventos de 15 a 30 dias ficam invisíveis para o modelo. Dedup do Worker (data_evento|empresa|fonte_base) mitiga re-narração. Registrar, não mudar sem decisão.

## Confirmado OK (método + evidência)

- **Veracidade da UI.** `audit-ui-metrics.mjs` exit 0, 0 bloqueante. Conferência manual dos 3 termos reservados: Emissores = `totalEmissores` (universo 103) ok. Críticos = `Set` de emissores com evento CRÍTICO na janela de 30 dias ok. Relevantes = emissores RELEVANTE excluindo críticos ok. Faixas >=90 verde `#16a34a`, >=70 âmbar `#d97706`, <70 vermelho `#dc2626`, cor derivada do mesmo valor que o selo. Guarda `_semLeitura` cobre os 5 cards (ZEROINDISPONIVEL1 e MOCARDFALSO1 presentes no código).
- **Auth.** `op=state` sem JWT → 401. Login inexistente → 401 genérico (anti-enumeração). `receber_analise` anônimo → 403. Fail-closed.
- **Drift.** Health público `versao v4.9.208`. Bundle de produção recuperado via MCP, `WORKER_VERSAO = "v4.9.208"`. Repo `wrangler.toml main = v4.9.208.js` e bundle `api/v4.9.208.js` presentes. Frontend prod `v202.28` = HEAD do repo. `app/deploy_zip/index.html` hash SHA-256 idêntico ao `app/index.html`.
- **Health.** `ok:true`, `kv:true`, `rate_limiter:true`, `telemetria:true`, `admin_email_ok:true`, `sentry_ok:true`, `verificador_ok:true`, `fonte_externa_ok:true` com `cvm_fonte_ciclos_perdidos:0`, providers 2/2, HTTP 200 em 2,1s.
- **OpenRouter.** `verificarSaldoOpenRouter` vivo com 1 call site (`worker.js:14466`), monitora saldo da conta do Perplexity, não contamina o health. Perplexity segue `{status:"removido"}` sem alarme falso.
- **Cascade.** `deveVerificar` e fila `radar:verif_fila:{data}` no caminho de `receber_analise`. `sanitizarPayloadRadar` com 17 ocorrências. `waitUntil` 5 usos. `document.write` zero.
- **CSS.** `strong` global só com `font-weight:600`, sem color.
- **Multi-semana.** Endpoints críticos (state, ews, briefing, historico, comparar) com `carregarEstadoMultiSemana(env, 5)`. Varredura, plano, newsletter, health diário e preditivo com 2-3 semanas por desenho.
- **Exposição.** Repo confirmado PRIVATE via `gh repo view`, o `tracker-primeiros-clientes.csv` de prospecção não fica público.

## Lacunas declaradas

- Core Web Vitals não re-medidos nesta auditoria (rodada mobile com Lighthouse 100/100/100 foi 21/08, nota [[88 - Sessao Frontend Mobile 2026-08-21]]).
- A11y por teclado/leitor de tela não executada a fundo.
- OWASP LLM Top 10 não re-analisado item a item, só o caminho crítico do verificador.
- Suíte vitest não rodada local (CI verde no push, `worker-tests.yml`).
- `wrangler secret list` não executado, health cobre os 3 secrets que derrubam `ok`.

## Pendências canônicas reabertas em [[PENDENCIAS.md]]

MANIFESTOFRAGIL1, DEDUPON2, FEEDRERENDER1, ORF3D593D6, SACFALSA-RESIDUO, WORKTREE12, SPREADUNIDADE1-resíduo, PUBDATA1, CACHEBUMP1, DRIVERMORTO1, envelope da noturna, ANTHROPIC_API_KEY no GitHub, ROUTINE_API_KEY do scan-emergencia, CLOUDFLARE_API_TOKEN Pages:Edit.
