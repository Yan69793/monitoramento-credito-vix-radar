---
data: 2026-07-11
tipo: pesquisa
tags: [vix-radar, preditivo, altman, dados]
status: ativo
---
# 51 - Pesquisa e Ideias — Preditivo v2 — 2026-07-11

Pesquisa na internet (Firecrawl) sobre como evoluir o VIX Radar de sistema reativo (captura de eventos publicados) para sistema de crédito mais preditivo, cruzada com o mapeamento completo do motor v1 em produção. Origem: pedido do operador em 11/07; escopo aprovado: **quick wins + fundação de dados** (plano em `~/.claude/plans/projeto-vix-radar-vixradar-com-twinkly-karp.md`).

## Contexto consultado

- Motor preditivo v1 **já em produção** (`api/v4.9.149.js`): `calcularEWS` (:11805 — pesos de mercado :11748, taxonomia de tags :11756, decay `exp(-0.046·d)` meia-vida ~15d, floors por evento oficial e por emissor `_RJ_FLOOR` :12251) + `executarPipelinePreditivo` (:12454 — ensemble rule 0,55 + logística 0,45 → score 0-100, `prob_30d`/`prob_90d`, cron Worker 12:30/18:30 BRT, 103 emissores, endpoints `op=ews` e `op=predictive_v1`).
- Roadmap v2 já desenhado em `.claude/skills/vix-radar-predictive/SKILL.md` (Merton DD + macro + XGBoost + backtest) — era o único documento de design da camada; os `references/` e `scripts/` descritos nele não existiam.
- **Gargalo estrutural achado no mapeamento**: todo o histórico vive em KV com TTL (`mercado:serie:*` ~252 pts/90d, `ews:hist:*` 90 pts/120d, `anbima:zscores` 7d, `predictive_v1:latest` 14d) — evapora antes de virar dataset de treino/backtest. Helper `kvFeatureKey` (`features:{empresa}:{dataISO}`, :12315) existe **sem writer**.

## Achados (com fonte e relevância)

1. **Distance-to-default é robusto para ranquear, não para PD absoluta** — Jessen & Lando 2015, J. Banking & Finance (121 cit.). Relevância: no v2, Merton DD entra como feature de ranking; não prometer PD calibrada sem calibração explícita.
2. **ML + distance-to-default superam medidas tradicionais em uso real** — Robeco 2024 ("Using ML and distance-to-default to predict distress risk"). Relevância: valida a arquitetura v2 da skill (Merton + ensemble).
3. **Spread alto vs. PEERS prediz downgrades futuros** — "Credit Spreads, Rating Downgrades and Downside Performance" (ResearchGate); Moody's **Early Warning Toolkit** (CreditEdge EDF) rastreia nível + variação + **relativo a peers** + trigger. Relevância: o z-spread do v1 compara o papel só contra o próprio histórico — feature relativa ao setor é o upgrade de maior valor. Evidência interna do fenômeno: Aegea CDI+2,42%→6,30% no mês do downgrade (scans jun/2026).
4. **Transições de rating/defaults raros são previsíveis com XGBoost/RF tratando class imbalance** — Oliveira et al. 2025, MDPI Algorithms 18(10):608. Relevância: referência metodológica do v2 (defaults são raros em universo de 103).
5. **LLMs em monitoramento de crédito entregam lead time mediano ~3 meses** entre sinal em texto e inadimplência — SSRN 6253818 (SME real-time monitoring); taxonomia: "Interpretable LLMs for Credit Risk" (arXiv 2506.04290 / ESWA 2025). Relevância: o Radar já tem a camada LLM; o gap é persistir eventos como features com timestamp — resolvido pela fundação de dados.
6. **Armadilha nº 1: alert fatigue vs. miss rate** — Moody's EWS whitepaper. Relevância: thresholds do EWS/predictive (16/36/61) nunca foram backtestados; calibrar por precision@k quando houver histórico.
7. **Secundário BR é ilíquido** — BNDES (liquidez do mercado secundário de debêntures). Relevância: sinal de spread sem filtro de liquidez gera falso momentum; `n_papeis`/`n_dias_historico` já existem na série ANBIMA para filtrar.
8. **Altman Z''-score EM** (variante para emergentes, Salomon/STOXX; alerta de uso em Brattle "Solvency Shortcuts"). Relevância: feature estrutural barata com dados gratuitos de dados.cvm.gov.br (ITR/DFP CSV, 5 anos); **inválida para setor Financeiro** (excluir).
9. **Players AI-native (9fin, Octus CreditAI) não cobrem crédito doméstico BR** — reforça o gap competitivo da [[50 - Análise Competitiva e Baseline SEO 2026-07-11]]. Economatica pivotou para "dados para agentes de IA" (APIs/MCP) — ameaça de médio prazo e validação da demanda por sinal via API.
10. **Inferência de ML no Worker**: treinar offline e exportar pesos/árvores como JSON para JS puro (a skill já previa; <50 KB) — sem dependência nova de runtime.

## Decisões arquiteturais (validadas por agente de design em 11/07)

| Decisão | Escolha | Motivo |
|---|---|---|
| Persistência histórica durável | **Script local diário + git** (`wrangler kv key get --remote`), delta-dump ~100-300 KB/dia + full semanal gzip | Zero mudança no Worker, começa hoje; falha auto-recuperável por ~90d (janela de TTL); consumidor final é treino offline local. R2/D1 ficam para o v2 se confiabilidade exigir |
| Escrita do Altman | **`wrangler kv key put`** em UMA chave agregada `fundamentals:altman:latest` (mapa empresa→{z_em,...}) | Trimestral; evita endpoint novo com superfície de auth (histórico de segurança do projeto); 1 get por run do pipeline |
| Features diárias | **Embutidas no payload `predictive_v1:latest`** (com `model_version`) | Elimina writer novo de `features:{empresa}:{data}` (103 writes/dia); o exporter já captura o payload |
| `spread_rel_setor` | **Shadow mode** no v4.9.150 (calculada e exposta, peso zero; mínimo 4 peers com série, senão null) | Protege comparabilidade do histórico e os floors calibrados; promoção a peso após 2-4 semanas de observação |
| Filtro de liquidez | **Ativo já** no sinal de spread | Só reduz ruído (rebaixa confiança de papel ilíquido), não cria falso positivo novo |
| Diff pendente no bundle | **Mesmo bump v4.9.150**, commits separados (pendente primeiro, features depois) | Uma decisão de deploy em vez de duas; bisecável; corrige a edição in-place do v4.9.149.js |

## Recomendações acionáveis (viram execução no plano)

1. **Exporter diário de histórico** (`scripts/run_vixradar_export_historico.ps1` + task `VIXRadar-Export-Historico` 20:45 BRT) — porque cada dia sem export perde permanentemente o que sai da janela de TTL; conecta com o gate de backtest do v2.
2. **Worker v4.9.150**: filtro de liquidez ativo + `spread_rel_setor` em shadow + features/`model_version` no payload + leitura null-safe de `fundamentals:altman:latest` — porque são os únicos quick wins de sinal com respaldo na literatura que não desalinham o histórico.
3. **Altman Z''-EM trimestral via CVM** (`scripts/predictive/atualizar_altman_cvm.ps1`) — porque é a única feature fundamentalista de custo zero; Financeiro = null; validação manual dos 2-3 primeiros emissores é gate.
4. **Labels seed** (`data/labels/eventos_credito.jsonl` das semanas vivas de `radar:estado:*` + `scans/`) — porque o target de treino do v2 é evento real, não proxy; começar a rotular agora.
5. **Proto-backtest mensal (precision@k)** quando houver ≥1 mês de histórico — porque é o que calibra thresholds (anti alert-fatigue), decide a promoção do shadow e o go/no-go do v2 (Merton + XGBoost).

## Fora do escopo agora (registrado para o v2)

Merton DD (exige cotações + estrutura de capital), features macro (BCB/CDS/DI), meta-modelo XGBoost com time-series CV, calibração Platt/isotonic, migração da fundação de dados para R2/cloud. Tudo permanece especificado na skill `vix-radar-predictive`.

## Fontes principais

- Jessen & Lando 2015 — Robustness of distance-to-default: https://www.sciencedirect.com/science/article/abs/pii/S0378426614001770
- Robeco 2024 — ML + DtD distress risk: https://www.robeco.com/en-us/insights/2024/02/real-life-experience-using-ml-and-distance-to-default-to-predict-distress-risk
- Credit Spreads, Rating Downgrades and Downside Performance: https://www.researchgate.net/publication/340257346
- Moody's Early Warning Toolkit (EDF): https://ma.moodys.com/rs/961-KCJ-308/images/Using%20EDF%20Measures%20to%20Identify%20At%20Risk%20Names%20-%20Monitoring%20and%20Early%20Warning%20Toolkit1.pdf
- Moody's EWS whitepaper (alert fatigue): https://www.moodys.com/web/en/us/insights/resources/early-warnings-whitepaper.pdf
- Oliveira et al. 2025 — Ratings transitions ML: https://www.mdpi.com/1999-4893/18/10/608
- LLM SME monitoring (lead time 3m): https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6253818
- Interpretable LLMs for Credit Risk (review): https://arxiv.org/html/2506.04290v2
- BNDES — Liquidez do secundário de debêntures: https://web.bndes.gov.br/bib/jspui/bitstream/1408/7083/1/RB%2044%20Liquidez%20do%20mercado%20secund%C3%A1rio%20de%20deb%C3%AAntures_P.pdf
- Brattle — Solvency Shortcuts (uso/misuso de Z-score): https://www.brattle.com/wp-content/uploads/2022/05/Solvency-Shortcuts-The-Use-and-Misuse-of-Simple-Tools-for-Predicting-Financial-Distress.pdf
- CVM Dados Abertos (ITR/DFP): https://dados.cvm.gov.br/ · ANBIMA Data / REUNE: https://data.anbima.com.br/ · https://www.debentures.com.br/
- EY — Future of EWS in banking: https://www.ey.com/en_us/insights/banking-capital-markets/the-future-of-early-warning-systems-in-banking
- 9fin: https://www.9fin.com/ · Octus CreditAI: https://octus.com/
