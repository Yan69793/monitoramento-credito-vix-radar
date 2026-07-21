---
data: 2026-07-20
tipo: changelog
tags: [vix-radar, changelog, incidentes, deploys]
status: ativo
---

# Changelog — VIX Radar

Registro cronológico de incidentes, deploys e eventos de produção. Cobertura: julho 2026. Para histórico anterior: [[_Arquivo/historico-03-2026-06]].

---

> [!warning] 21/07 12h30 — **Rastreabilidade: v4.9.167 foi publicada três vezes, com conteúdos diferentes.**
> Três commits com a mesma mensagem, `chore(worker): deploy v4.9.167 em producao`, alteraram `api/v4.9.167.js` com diffs distintos: `1842499` 15h34 (2 linhas), `ab8b478` 19h03 (117 linhas) e `5af9b39` 19h15 (1 linha). O do meio não é ajuste cosmético, é o **modelo Merton Distance to Default entrando no pipeline preditivo**: `calcMertonDD` (iterativo, padrão KMV, ref. Bharath & Shumway 2008) mais `scoreMertonToRisk`, que soma até 35 pontos ao score de risco de crédito do emissor e adiciona o driver `merton` quando `merton_dd < 1.5`. O commit das 19h15 é hotfix disso: passa a exigir `market_cap > 100` e cai para patrimônio líquido, ou seja, o primeiro deploy podia usar market cap espúrio como insumo do score.
> Consequência prática: `WORKER_VERSAO = "v4.9.167"` deixou de identificar o build, o `canonical-test` compara só o número e não detecta divergência de conteúdo, e "voltar para v4.9.167" virou instrução ambígua. Nem esta nota nem o `PENDENCIAS.md` mencionavam Merton até agora, os dois descreviam a v4.9.167 como sendo apenas F002 e F014.
> **Regra a partir daqui: um número de versão por deploy.** Mudança de comportamento do score nunca reaproveita número já publicado.

> [!danger] 21/07 12h45 — **MERTONLIVE1: o Merton está movendo score real, e o driver não aparece.**
> Build em produção identificado com autorização do MCP: é o terceiro, `5af9b39`. Três evidências convergentes. O histórico do wrangler mostra os dois últimos deploys às 19h06 e 19h18 BRT de 20/07, três minutos depois dos commits `ab8b478` (19h03) e `5af9b39` (19h15), e nada depois; o `api/v4.9.167.js` local é byte-idêntico a `5af9b39` e diferente dos outros dois; e esse arquivo contém as 4 ocorrências de `scoreMertonToRisk` mais o guard `market_cap > 100`.
> Efeito medido no artefato `predictive_v1:latest` gerado hoje 12h30 BRT: dos 103 emissores, **65 têm `merton_dd` calculado e 22 tiveram o score alterado** (2 recebendo +20, 7 recebendo +10, 13 recebendo +4 no `rule.score`, que entra no final com peso 0,55).
> Dois achados que não estavam no radar de ninguém. Primeiro, **o driver é invisível na maioria dos casos**: `drivers.push("merton")` exige `dd < 1.5`, mas o `score +=` roda para todo `dd != null`, então 20 dos 22 afetados não mostram `merton` na lista de drivers. Light (dd 1,86), Pão de Açúcar (1,83), Simpar, EcoRodovias, Vamos, JSL, Minerva, Cosan, Raízen e CSN têm score inflado por um fator que o painel não exibe. Segundo, **dois emissores mudaram de classificação por causa dele**: EcoRodovias (16, baixo; seria 10, neutro) e Movida (16, baixo; seria 5, neutro).
> Ver `PENDENCIAS.md`, MERTONLIVE1.

> [!success] 21/07 12h30 — **Reconciliação CVM destravada.**
> `scripts/predictive/reconciliar_ipe_cvm.ps1` morria na primeira leitura de KV que voltasse 404. Com `$ErrorActionPreference = 'Stop'` herdado do topo, o não-zero do wrangler virava erro terminante e o guard gracioso logo abaixo nunca executava. Como a chave `radar:estado:{semana ISO corrente}` ainda não existe na segunda de manhã, e a task roda justamente na segunda, a rotina falhava de forma determinística toda semana: em 20/07 casou 4 documentos severos da CVM com 3 emissores e morreu em seguida, quatro dias sem ground truth. Fix aplica o mesmo idioma `Continue`/`Stop` já usado na linha 336 do próprio arquivo e nos scripts irmãos. Validado em DryRun nos dois caminhos: 3/3 semanas lidas no caso normal, e com `-SemanasEstado 12` os três 404 viram `AVISO` e a rotina termina em 9/12 semanas com exit 0. O guard de `semanasLidas -eq 0` segue abortando quando nenhuma semana lê, então dado incompleto continua não sendo publicado.

> [!success] 20/07 16h00 — **INGEST-GAP1 resolvido. Recovery manual + deploy v4.9.167 + fix estrutural.**
> Noturno 103/103 (9 críticos, 535k tokens) + Matinal 13/13 (7 críticos, 132k tokens). Causa raiz: máquina desligada 00:25, cold boot 12:24, `StartWhenAvailable=false`. Fix: register reexecutado Admin. Ver [[63 - Recovery e Deploy 2026-07-20]].

> [!danger] 20/07 16h50 — **INGEST-GAP1 detectado: 103/103 stale 24-48h.**
> Matinal 20/07 e Noturna 19/07 não executaram (`0x800710E0`). Diagnóstico completo em [[62 - Auditoria Completa e Correcoes 2026-07-20]].

> [!danger] 19/07 12h25 — **ESCAPEH1 (P0): `renderEventoCard` quebrada 2 dias. Corrigido v201.80.**
> `ReferenceError: h is not defined` — fix de XSS do v201.76 introduziu chamadas a `h()` sem defini-la no escopo. Nenhum card de evento renderizava. Ver [[03 - Estado de Produção]].

> [!warning] 19/07 12h18 — **JANELA30x90 corrigido. Frontend v201.79.**
> `normalizarResultadoPayload` filtrava eventos com janela de 30 dias em vez de 90. Eventos entre 30-90 dias sumiam de todos os emissores.

> [!success] 19/07 12h07 — **JANELACONF1: Worker v4.9.166.**
> Rename cosmético de campo de bookkeeping. Deploy + git reconciliado.

> [!success] 19/07 11h52 — **V0EMPTY1: Frontend v201.78.**
> Dashboard renderizava "0 críticos" como estado definitivo antes do fetch assíncrono resolver. Fix: guarda `Object.keys(resultados).length>0`.

> [!warning] 19/07 08h — **Auditoria geral (`/vix-radar-general-audit`).**
> Achou V0EMPTY1. Confirmou drifts de documentação. RACEKV1 confirmado deployado (não era pendência). [[03 - Estado de Produção]].

> [!success] 18/07 23:46 — **Ingestão recuperada pós-OAuth expirado.**
> Noturna 18/07 abortou com `submit_ok:0` (sessão OAuth expirada). Reauth + rerun manual: 103/103, 6 críticos. [[03 - Estado de Produção]].

> [!warning] 18/07 — **RACEKV1 corrigido no repo.**
> Durable Object `EstadoSemanaDO` serializa 4 funções com fila FIFO. Não deployado nesta data.

> [!success] 18/07 — **Auditoria completa (triple-pass). Sem incidente novo.**
> Drift de documentação ALRT1 e HDASH1 corrigidos. Ambos já estavam resolvidos em produção.

> [!warning] 17/07 noite — **LOGLOCK1 corrigido.**
> Lock de arquivo cegava log da noturna (dados OK). Fix: retry exponencial no `Write-Log`. Commit `49904ea`.

> [!success] 17/07 22h — **FIN1-REV confirmado em produção.**
> 79 emissores destravados. Stale >48h: 76→0. Idade máx: 92.9h→3.8h.

> [!success] 17/07 — **v4.9.164 + v201.76 deployados.**
> 3 P1 (VERIFREJ1, EMAILGET1, RLADMIN2) + fix XSS frontend. Ver [[03 - Estado de Produção]].

> [!success] 16/07 — **Auditoria de rotinas. 5 ativas, documentação reconciliada.**
> AgendaSemanal desabilitada. Commit `48ec5f9`.

> [!success] 15/07 noite — **v4.9.161 (RESEARCHDOWN1).**
> InfoMoney/imprensa financeira era rebaixada como research. Oncoclínicas CRITICO restaurado.

> [!success] 15/07 manhã — **Canonical-test verde após 8 dias.**
> Drift repo/prod reconciliado. `deploy-worker.ps1` criado. PR #10 mergeado.

> [!success] 14/07 tarde — **Aprovação via WhatsApp + CLEANAGG1 corrigido.**
> Cleanup agressivo destruía logs (desde 02/07). Corrigido commit `31035fa`.

> [!success] 14/07 manhã — **v4.9.155 + P0 secrets.**
> 3 credenciais órfãs removidas. Token CF vivo `f3e3d6b4` — revogar no painel.

> [!warning] 13/07 — **Matinal parada 3 dias (saldo -US$1,21). Migração para assinatura.**
> CHUNK1 identificado: `Split-IntoChunks` colapsava lotes de 1 emissor. 3 P1 novos (HDASH1 GET, XSS, rate limiter fail-open). [[53 - Auditoria Completa 2026-07-13]] [[54 - Auditoria Geral Backend Frontend 2026-07-13]].

> [!success] 12/07 — **Frontend v201.75 (co-branding Szuchmacher).**
> Monograma YS em landing + modais. Marca VIX Radar intocada.

> [!info] 11/07 — **v4.9.150 + preditivo v2 + análise competitiva SEO.**
> Altman Z''-EM (69 emissores). Baseline SERP 10 keywords. Task `VIXRadar-Ranking-Mensal` criada.

> [!warning] 10/07 — **Matinal: run 10h falhou (saldo), run 12h cobriu 11/11.**
> 5 CRITICOs: Raízen, Kora, Oi, Oncoclínicas, GPA. Fila de verificação drenada.

> [!error] 09/07 — **Painel sem notícias desde 06/07.**
> Cadeia de falhas 07-08/07 + fila de verificação presa. [[46 - Auditoria Completa 2026-07-09]] [[47 - Auditoria Completa 2026-07-09 (v2)]].

> [!info] 07/07 — **v4.9.147/148 deployados.**
> `admin_mercado` POST-only, `zscores_anbima` auth, `tel()` fix. [[43 - Auditoria Geral Backend Frontend 2026-07-07]] [[44 - Auditoria Geral Backend Frontend 2026-07-07]].

> [!warning] 06/07 — **Noturno rodou duplicado (colisão Task nativa + scheduled).**
> Fix: stderr por-PID + mutex global. [[41 - Auditoria Completa 2026-07-06]].

> [!error] 05/07 — **Bug encoding CP850 corrompia nomes acentuados e descartava CRITICOs.**
> Raízen e Oncoclínicas confirmados. Corrigido nos 3 scripts. [[40 - Auditoria Geral Backend Frontend 2026-07-05]].

> [!error] 04/07 — **Health-gate bloqueou noturna inteira (0/103).**
> `verificador_ok` degradado → script abortava tudo. Fix: health não-bloqueante. [[39 - Auditoria Completa 2026-07-04]].

> [!error] 02/07 — **Rotinas paradas 9 dias. Scheduler zerado (2ª vez).**
> 103/103 stale. 5 tasks recriadas. Mesmo padrão do incidente 15/06. [[35 - Auditoria Completa 2026-07-02]].

---

*Para notas detalhadas de cada evento, ver links [[wikilink]] em cada entrada. Para infraestrutura: [[03b - Infraestrutura]].*
