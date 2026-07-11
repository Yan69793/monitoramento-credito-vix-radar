---
name: vix-radar-predictive
description: Motor preditivo do VIX Radar — scores quantitativos de crédito (z-scores ANBIMA, pipeline rule+logistic, Merton DD, calibração e backtesting). Use quando o usuário pedir análise preditiva de crédito, score de default, early warning quantitativo, Merton, z-score, probabilidade de default, backtest do modelo, calibração de scores, ou melhoria do pipeline preditivo. Também use quando o usuário mencionar "predictive_v1", "executarPipelinePreditivo", "scorePreditivo", ou quiser entender/comparar o score preditivo de emissor específico.
compatibility: requires Worker (wrangler), KV RADAR_KV, Node.js 18+
---

# VIX Radar — Motor Preditivo

## Decisões vigentes (2026-07-11 — pesquisa nota 51 do vault + plano quick wins)

- **Fundação de dados**: exporter local diário (`scripts/run_vixradar_export_historico.ps1`, task `VIXRadar-Export-Historico` 20h45 BRT) versiona em `data/historico/YYYY-MM-DD/` o que o KV apaga por TTL (predictive+features, zscores, delta diário das séries, full semanal gz). O dataset do v2 nasce daqui — R2/D1 só se a confiabilidade exigir.
- **Labels**: `data/labels/eventos_credito.jsonl` (seed via `scripts/predictive/seed_labels.ps1`); target = evento real, nunca proxy.
- **v4.9.150** (repo; deploy sob aprovação): filtro de liquidez ATIVO no sinal de spread (amortece papel ilíquido via `n_papeis`/`n_dias_historico` do `anbima:zscores`); `spread_rel_setor` em **SHADOW MODE** (z-spread vs peers do setor, mín. 4 peers, peso zero — promoção só após 2-4 semanas de observação + proto-backtest); vetor `features` + `model_version` embutidos no payload `predictive_v1:latest` (substitui o writer `features:{empresa}:{data}` — não usar).
- **Altman Z''-EM**: `scripts/predictive/atualizar_altman_cvm.ps1` (DFP CVM consolidado, trimestral, Financeiro=null) grava UMA chave agregada `fundamentals:altman:latest` via `wrangler kv key put` — sem endpoint novo. Pipeline lê null-safe.
- **Proto-backtest mensal** (gated: ≥1 mês de `data/historico/`): precision@k do top-10 vs eventos CRITICO nos 30d seguintes, segmentado por `model_version` — decide promoção do shadow e go/no-go do v2 (Merton+XGBoost abaixo).

## Contexto

O VIX Radar monitora 103 emissores de dívida corporativa brasileira. O pipeline atual combina:

- **Análise fundamentalista**: Claude Sonnet/Opus (rotinas matinal/noturno) varre CVM, imprensa, fatos relevantes e classifica eventos (CRITICO/RELEVANTE/ECO)
- **Análise quantitativa**: pipeline preditivo v1 (`executarPipelinePreditivo`) com rule-based scoring + regressão logística + z-scores ANBIMA

**Objetivo desta skill**: evoluir o motor preditivo de v1 (rule+logistic) para v2 (Merton DD + features macro + ML ensemble com backtesting), mantendo o que já funciona.

## Arquitetura atual (v1 — produção v4.9.147)

### Fluxo

```
Crons Worker (12:30 / 18:30 BRT)
  └─ scheduled() → executarPipelinePreditivo(env)
       ├─ carregarEstadoMultiSemana(env, 3)   ← eventos das últimas 3 semanas
       ├─ carregarAnomalias(env)               ← spreads ANBIMA + anomalias de volume
       ├─ _carregarMapaFlags(env)              ← flags estruturais (em_reestruturacao, etc.)
       ├─ calcularEWS(empresa, anomalias, eventos, [])  ← Early Warning Score por emissor
       ├─ calcularStressSetorialDeCache(ewsCache)       ← stress agregado por setor
       │
       └─ Para cada emissor:
            ├─ features = { ews_score, velocity_delta, direction, spread_score,
            │              event_cluster, structural_floor, setor_stress, ... }
            ├─ rule = scorePreditivoRuleV1(features)        ← peso 0.55
            ├─ logistic = scorePreditivoLogisticV2(features) ← peso 0.45 (prob_30d, prob_90d)
            ├─ scoreFinal = min(100, rule*0.55 + logistic.prob_30d*100*0.45)
            └─ label: alto(≥61) | médio(≥36) | baixo(≥16) | neutro

Persistência:
  predictive_v1:latest → KV (TTL 14d)
  ews:hist:{empresa}   → KV (últimos 90d, atualizado a cada run)
```

### Z-Scores ANBIMA (`calcularZScoresANBIMA`)

Calculado separadamente, persiste em `anbima:zscores` (TTL 7d):

| Campo | Definição |
|-------|-----------|
| `z_spread` | (spread_atual - média_histórica) / desvio_padrão |
| `spread_momentum` | (média_5d - média_20d_anterior) / desvio_padrão |
| `z_volume` | (n_papeis_atual - média_histórica) / desvio_padrão |
| `classificacao` | CRITICO (≥3σ) / ALERTA (≥2σ) / ELEVADO (≥1σ) / NORMAL |

### Endpoints

| Endpoint | Auth | Retorno |
|----------|------|---------|
| `action=pipeline_preditivo` | JWT admin | `predictive_v1:latest` do KV |

### Chamada programática

```js
// Admin — força execução e retorna resultado
GET /?action=pipeline_preditivo  (JWT admin)

// Interno — executar e persistir
await executarPipelinePreditivo(env, { skip_hist_persist: false })

// Interno — só calcular sem persistir histórico
await executarPipelinePreditivo(env, { skip_hist_persist: true })
```

## O que funciona bem

- **Z-scores ANBIMA**: cálculo estatístico correto, classificação por desvios-padrão, TTL razoável
- **Pipeline rule+logistic**: ensemble de dois modelos com pesos fixos, cobre todos os 103 emissores em cada run
- **Features extraídas**: EWS score, velocity (delta 7d), cluster de eventos, stress setorial, floor estrutural
- **Persistência**: KV com TTL, heartbeat de telemetria (`pipeline_preditivo:ok`)

## O que esta skill implementa (v2)

### 1. Merton Distance to Default (DD)

Modelo estrutural de crédito baseado em Merton (1974). Para cada emissor de capital aberto:

```
DD = (ln(V/F) + (μ - σ²/2)T) / (σ√T)

Onde:
  V  = valor de mercado dos ativos (market cap equity + dívida total)
  F  = face value da dívida (curto prazo + 0.5 * longo prazo)
  μ  = drift esperado dos ativos (~ risk-free rate)
  σ  = volatilidade dos ativos (σ_equity * (E/V))
  T  = horizonte (1 ano)
```

**Fontes de dados necessárias:**
- Market cap diário (já temos `cotacoes`/B3 ou Yahoo Finance)
- Dívida CP/LP (extraível dos DFs na CVM — `dados_para_analise` já retorna estrutura de capital)
- Volatilidade equity (calculável da série de cotações)
- Risk-free rate (Selic ou DI futuro)

**Output**: `merton_dd`, `merton_pd_1y` (probabilidade de default implícita), `merton_spread_implied`

### 2. Features macroeconômicas

Adicionar ao vetor de features do pipeline:

| Feature | Fonte | Frequência |
|---------|-------|------------|
| Selic (% a.a.) | BCB API | Diária |
| CDS Brasil 5Y | Bloomberg/ICE | Diária |
| IBOVESPA (var 30d) | B3 | Diária |
| DXY (var 30d) | Fed | Diária |
| Curva DI (spread 1Y-5Y) | B3/ANBIMA | Diária |
| EMBI+ Brasil | JP Morgan | Diária |

### 3. ML Ensemble tuning

Substituir pesos fixos 55/45 por:

- **Meta-modelo**: XGBoost ou LightGBM treinado sobre as features do pipeline + Merton DD + features macro
- **Treinamento**: janela rolante 5 anos (2021-2026), target = evento de crédito em 30/90/180 dias
- **Validação**: time-series cross-validation (expanding window), não k-fold aleatório
- **Métricas**: AUC-ROC, precision@k (k=10), Brier score (calibração)

### 4. Backtesting

Framework de validação contra defaults reais:

```
Dados de treino: 2021-01 a 2025-12
Dados de teste:  2026-01 a 2026-07
Target: evento de crédito em [30, 90, 180] dias
  - Default/RJ/RE: rótulo positivo
  - Waiver/standstill/reperfilamento aprovado: rótulo intermediário
  - Sem evento: rótulo negativo
```

**Métricas de backtest:**
- AUC-ROC por horizonte (30d, 90d, 180d)
- Precision/Recall/F1 por threshold
- Brier score (calibração de probabilidade)
- Lift chart (quantas vezes o modelo é melhor que aleatório nos top-k)
- Estabilidade temporal (desvio padrão do AUC entre janelas)

### 5. Workflow de implementação

```
Fase A — Dados
  1. Coletar séries históricas de cotações (Yahoo Finance ou B3 API) para emissores listados
  2. Extrair estrutura de capital (DFs CVM) — dívida CP, dívida LP, EBITDA, FCO
  3. Coletar features macro (BCB, ANBIMA, Bloomberg/ICE se disponível)
  4. Construir dataset rotulado: eventos de crédito 2021-2026 com data precisa

Fase B — Modelagem
  5. Implementar calcMertonDD(empresa, data) no Worker (JS puro, sem lib externa)
  6. Expandir vetor de features com Merton DD + features macro
  7. Treinar meta-modelo (XGBoost) offline em Python, exportar coeficientes/pesos para JSON
  8. Implementar scorePreditivoEnsembleV2(features) no Worker usando os pesos exportados
  9. Adicionar endpoint action=predictive_v2 (JWT admin)

Fase C — Validação
  10. Backtest contra defaults reais 2021-2026
  11. Calibrar probabilidades (Platt scaling ou isotonic regression)
  12. Comparar v1 vs v2: AUC, precision@10, Brier score
  13. Se v2 > v1 em todas as métricas, promover a produção

Fase D — Produção
  14. Substituir executarPipelinePreditivo → executarPipelinePreditivoV2
  15. Manter v1 como fallback (KV predictive_v1:latest preservado 30 dias)
  16. Adicionar métricas de qualidade ao health check (AUC trailing 90d)
  17. Dashboard: coluna "Score Preditivo" na tabela de emissores + sparkline 90d
```

## Regras

### Sempre
- **Validar com `ParseFile`** antes de sugerir edição em bundle (`api/v4.9.*.js`)
- **Nunca editar bundle diretamente** — editar fonte (se disponível) ou aplicar patches cirúrgicos com `Edit`
- **Testar endpoint** após deploy: `action=pipeline_preditivo` com JWT admin
- **Atualizar Obsidian** (`03 - Estado de Produção.md`) com versão nova e métricas do modelo

### Features novas
- **Não quebrar o pipeline existente**: v1 segue rodando até v2 validado
- **Compatibilidade**: novas features usam os mesmos bindings KV do v1
- **Custo**: Merton DD é determinístico (O(n) por emissor, sem API externa). Features macro: 1 fetch por dia. Meta-modelo: inferência local (JSON de pesos < 50 KB)

### Backtesting
- **Target label**: evento de crédito público (Fato Relevante CVM categorizado como default/RJ/RE) — não usar proxy (spread) como target
- **Janela mínima**: 36 meses de dados rotulados para treino
- **Data leakage**: features na data T só usam informações disponíveis até T-1

## Estrutura de diretórios

```
.claude/skills/vix-radar-predictive/
├── SKILL.md              ← este arquivo
├── references/
│   ├── merton-model.md   ← detalhamento matemático do Merton DD
│   ├── features.md       ← dicionário completo de features (v1 + v2)
│   └── backtest.md       ← framework de backtesting e métricas
└── scripts/
    └── train_ensemble.py ← script de treino offline do meta-modelo
```

## Invocação

```
/vix-radar-predictive                    → status do pipeline preditivo
/vix-radar-predictive emissor <nome>     → score detalhado de 1 emissor
/vix-radar-predictive backtest           → rodar backtest e gerar relatório
/vix-radar-predictive calibrar           → calibrar probabilidades com Platt scaling
/vix-radar-predictive features <nome>    → features extraídas para 1 emissor
```
