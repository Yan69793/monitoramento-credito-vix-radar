---
title: Oportunidades de Melhoria (2026-06-11)
date: 2026-06-11
tags:
  - vixradar
  - melhorias
  - backlog
status: ativo
base: Worker v4.9.102 + Frontend v201.45
---

# Oportunidades de Melhoria — 2026-06-11

Levantamento solicitado pelo operador em duas categorias (Técnicas e Produto), ancorado no estado real de produção confirmado em [[09 - Auditoria 2026-06-10 (Pendências)]] e em verificação direta do código (`api/v4.9.102.js`, `app/index.html` v201.45).

Esta nota **estende** as tabelas T1–T10 (técnicas) e P1–P10 (produto) da seção "Oportunidades de Melhoria" do `PENDENCIAS.md` — não as substitui. A numeração continua de onde elas pararam.

> [!warning] Disambiguação de IDs
> Os IDs T/P desta nota referem-se às tabelas de **Oportunidades de Melhoria** do `PENDENCIAS.md`. São independentes dos achados de auditoria (P01–P22, N01–N13) da tabela de achados — ex.: o achado de auditoria "P11 ADMIN_EMAIL hardcoded" não tem relação com a melhoria de produto "P11 Alertas por emissor".

## 1. Triagem dos exemplos sugeridos (verificado no código)

Antes de propor, cada exemplo citado pelo operador foi verificado contra o código. Quatro deles **já existem em produção** e não devem voltar ao backlog como features novas.

| Exemplo sugerido | Status real | Evidência |
|---|---|---|
| Streaming de resposta para reduzir latência percebida | **Não existe** — resposta bufferizada (JSON único via `resp()`) | `api/v4.9.102.js:13994-14005` |
| Cache inteligente de análises recentes no KV | **Não existe** — caches atuais: evento verificado (`radar:verif:{hash}`, 30d), fallback de último resort (35d), estado semanal. Nenhum "servir análise <Xh sem reprocessar" | `api/v4.9.102.js:8695, 14002` |
| Health check endpoint dedicado | **Já existe** — GET `/` público, `op=ops` (admin, com saldo OpenRouter), `op=health-dashboard`, cron `executarHealthCheckDiario` | `api/v4.9.102.js:13239, 13337, 13532` |
| Métricas de custo por análise logadas no KV | **Parcial** — só disjuntor diário agregado ($1.50/dia em `radar:custo:{hoje}`); sem custo/tokens por análise ou por provider | `api/v4.9.102.js:14400` |
| Alertas push/email para evento crítico em emissor específico | **Não existe** — alertas críticos são globais; favoritos existem mas sem alertas vinculados | `api/v4.9.102.js:4721-4752, 7876` |
| Filtro por setor no frontend | **Já existe** — heatmap de setores clicável no Market Overview, expande lista de empresas | `app/index.html` ~2064 |
| Histórico de eventos por emissor | **Já existe (parcial)** — timeline na UI + backend `op=historico_emissor`; janela curta na UI (estender = P10 do PENDENCIAS) | `app/index.html` ~2140; `api/v4.9.102.js:13016` |
| Exportação de relatório PDF | **Já existe** — com white-label completo (logo, analista, CNPJ, 3 presets visuais) | `app/index.html` ~3227 |
| Comparativo de spread entre emissores do mesmo setor | **Parcial** — backend `op=comparar` pronto; **zero consumidores no frontend** (Grep confirma); dados de spread ANBIMA limitados | `api/v4.9.102.js:13122` |

**Descartados como features novas** (já implementados): filtro por setor, exportação PDF, health check dedicado, histórico básico por emissor.

## 2. Técnicas — itens novos (T11–T15)

| ID | Oportunidade | Justificativa | Impacto | Esforço |
|---|---|---|---|---|
| T11 | **Cache inteligente de análise recente.** Chave `radar:analise:{empresa}` com TTL 4–6h; pulso manual serve cache se fresh, com flag `_cache_recente` e idade no payload. | Corta custo de API e latência de ~7-13s para <1s em repetições; protege orçamento além do rate limit. Especialmente relevante com OpenRouter 402 (N01) e sistema em haiku-only. | Alto | M |
| T12 | **Dedup de requisições concorrentes.** Lock leve em KV/DO por empresa durante cascade em voo; segunda requisição aguarda e recebe o mesmo resultado. | Evita cascade dupla paga pelo mesmo dado quando 2 usuários pedem a mesma análise simultaneamente. Hoje não há nenhuma proteção. | Médio | M |
| T13 | **Custo por análise logado.** Registrar tokens + USD estimado por provider em cada análise: dimensão extra no `tel()` (Analytics Engine) + agregado diário em KV `radar:custo:detalhe:{data}`. | O disjuntor diário ($1.50) passa a ter base real em vez de estimativa; permite custo por tenant — pré-requisito de pricing B2B (Mirabaud, gestoras). | Alto | M |
| T14 | **Feedback progressivo de análise (pseudo-streaming).** SSE ou polling de status da cascade (provider em uso, rodada N/9, eventos encontrados) em chave KV efêmera; frontend mostra progresso real em vez de spinner. | Latência percebida cai sem quebrar a validação de schema — streaming token-a-token é incompatível com `sanitizarPayloadRadar`, que precisa do JSON completo. | Médio | G |
| T15 | **Backoff + timeout por provider na cascade.** Timeout individual e backoff exponencial com jitter entre tiers (hoje: retry sequencial fail-fast, timeout global). | Reduz cauda de latência quando um provider degrada sem falhar de vez. | Médio | P |

Itens T1–T10 do `PENDENCIAS.md` permanecem válidos. Destaques por sinergia com os novos: T1 (pipeline CI/CD de build — resolve N02/P08), T2 (refresh token JWT), T4 (alerta automático de provider 402 — teria detectado N01 no dia), T5 (backup KV semanal para R2).

## 3. Produto — itens novos (P11–P15)

| ID | Oportunidade | Justificativa | Impacto | Esforço |
|---|---|---|---|---|
| P11 | **Alertas por emissor (watchlist com alertas).** Favorito ganha opt-in "alertar evento crítico" → email imediato (Resend) disparado no pipeline de persistência; prefs em `user_prefs:{email}`. | Feature de maior valor percebido para gestor profissional (Mirabaud, family office): "me avise quando MEU emissor tiver evento crítico". Infra de favoritos + email já existe; falta só o vínculo. | Alto | M |
| P12 | **UI de comparação de emissores.** Tela side-by-side (até 5) consumindo `op=comparar` já pronto no backend — eventos da semana, materialidade, EWS, anomalias. | Quick win: endpoint completo desde v4.8.0 sem nenhum consumidor (confirmado via Grep em `app/index.html`). Análise relativa intra-setor é fluxo natural de crédito. | Alto | P/M |
| P13 | **Briefing executivo na UI.** Card/tela "Briefing do dia" consumindo `op=briefing_executivo` já pronto (top 10 materialidade, distribuição setorial, EWS, CVM). | Mesmo padrão do P12: endpoint órfão de alto valor (única menção no frontend é texto de tooltip, linha 3408). Vira a "primeira tela do dia" do gestor. | Alto | P/M |
| P14 | **Gráfico de série temporal por emissor.** Spread/EWS/anomalias ao longo do tempo a partir das chaves `serie:` do KV (sparkline ou chart leve no painel do emissor). | O dado histórico existe no KV mas não é visualizado em lugar nenhum; gestor enxerga tendência, não só snapshot. | Médio | M |
| P15 | **Histórico estendido na timeline (3 meses).** Ampliar janela da timeline do emissor usando `op=historico_emissor` (reclassificação do P10 original como prioridade). | Backend pronto; mudança só de frontend. | Médio | P |

Itens P1–P10 do `PENDENCIAS.md` permanecem válidos. Destaques: P1/P2 (status de providers e saldo OpenRouter no painel admin — visibilidade do incidente N01), P3 (landing page), P9 (onboarding guiado).

## 4. Priorização recomendada (valor ÷ esforço)

1. **P12 — UI de comparação**: backend pronto, esforço P/M.
2. **P13 — Briefing executivo na UI**: backend pronto, esforço P/M.
3. **P11 — Alertas por emissor favoritado**: maior valor B2B, esforço M.
4. **T11 — Cache inteligente de análise recente**: corta custo imediato, esforço M.
5. **T13 — Custo por análise**: pré-requisito de pricing, esforço M.

> [!note] Pré-condição operacional
> Nada disso supera em urgência os 3 críticos abertos da auditoria: N01 (OpenRouter 402), P05* (CI quebrado) e P15* (cron duplo noturno). Ver [[09 - Auditoria 2026-06-10 (Pendências)]]. As melhorias acima são o backlog pós-estabilização.

## Status de implementação (2026-06-11)

> [!success] P12 + P13 implementados no repo (frontend v201.46) — commit `bbe54e9`
> Fase 1 do plano executada. Módulo auto-contido anexado ao fim de `app/index.html` (append-only, padrão overlay espelhado de `#agenda-overlay`), consumindo `op=briefing_executivo` e `op=comparar` (já prontos no Worker v4.9.102). Dois botões na sidebar: "Briefing do dia" e "Comparar emissores".

| Item | Status | Evidência |
|---|---|---|
| P13 Briefing executivo na UI | **Implementado (repo v201.46)** | Render verificado em pages dev: 5 cards, top 10 materialidade, distribuição setorial, alertas EWS, confiança média |
| P12 Comparação de emissores | **Implementado (repo v201.46)** | Modal seleção 2–5 (103 emissores) + tabela lado a lado verificados em pages dev |
| Segurança (vetor N03) | **Não reaberto** | Teste adversarial: payload `<img onerror>` renderizado como texto, `onerror` não dispara |

> [!success] Deploy concluído — em produção (v201.46)
> Deployado em 2026-06-11 (`wrangler pages deploy ./app/deploy_zip`, deployment `0f3c1d32`). Produção valida: `CACHE_VERSION="v201.46"`, `version.json` apex+www v201.46, módulo `_VIX_INTEL_VERSAO="v201.46"` no HTML servido, endpoints `op=briefing_executivo`/`op=comparar` retornando 401 sem token (gated). Ver [[03 - Estado de Produção#Atualização 2026-06-11 (frontend v201.46 — DEPLOYADO)]].

> [!warning] Rotacionar o token Cloudflare
> O token usado no deploy foi colado no chat — rotacionar e reconfigurar como variável de ambiente do Windows.

## 6. Rotina noturna 2026-06-12 — execução e achados do verificador

> [!info] Execução `vixradar-noturno` 2026-06-12 (~19h30 BRT)
> 30 emissores (top staleness/EWS) analisados em 6 lotes paralelos. **0 falhas de envio — todos `receber_analise` retornaram `ok:true`.** Worker `v4.9.106`, health OK (kv/rate_limiter/telemetria `true`, 3/3 providers). Janela de análise: 2026-05-13 a 2026-06-12.

**Fato bruto (enviado vs. persistido).** De ~40 eventos submetidos pelos analisadores, ~10 persistiram (`n_eventos>0`). Persistidos confirmados: Aegea 1, CEMIG 2, Hidrovias 2, EcoRodovias 1, TIM 1, BRK 1, Grupo Mateus 1, Eneva 1. `sem_eventos` legítimos: Equatorial (1T26 fora da janela), Assaí (eventos pré-13/05), Terra Santa Agro (**fechou capital out/2021, não é mais emissor ativo — higienizar do universo**).

**Interpretação calibrada (NÃO é incidente).** O verificador adversarial (`verificarEventosBatch`, Haiku→Sonnet) **está operando** — não houve queda 100% como um dos lotes inferiu por leitura de código. O padrão observado é a **verdade graduada por design**: eventos ancorados em `rad.cvm.gov.br` passam; eventos só-imprensa não-corroborados são rejeitados/quarentenados. A maior parte das rejeições é esse filtro + filtro de janela de 30d funcionando como projetado.

**T16 (técnica, NÃO confirmado) — falso-negativo de data por URL.** Suspeita de que `validarDatasFontes` extraia data do *path* da URL (ex.: `ri.empresa.com.br/wp-content/uploads/2018/11/...` → lê "2018-11" → descarta evento de 2026 silenciosamente). Reportado por inferência de comportamento + leitura de bundle, **não verificado em produção** (log `radar:auditoria:rejeitados:2026-W24` no KV exige `admin_senha`, indisponível à rotina). Ação: operador confirmar o parser e priorizar `data_evento`/nome-de-arquivo sobre o caminho de upload. Impacto: Médio · Esforço: P.

**P16 (produto) — emissores em distress contínuo perdem sinalização.** O filtro por *data do evento* descarta marcos legais de reestruturação datados fora da janela de 30d, mesmo quando o processo está **vivo e materialíssimo agora**. Casos confirmados por verificação web independente (não são alucinação dos analisadores):
> - **Oncoclínicas** — medida cautelar contra credores 17/04; 1T26 (15/05) prejuízo R$438,7mi, alavancagem 5,2x, dívida total R$3,2bi; RE em avaliação. ([NeoFeed](https://neofeed.com.br/negocios/apos-quebra-de-covenants-oncoclinicas-pede-protecao-da-justica-contra-credores/en/), [Capital Aberto](https://capitalaberto.com.br/companhias-abertas/oncoclinicas-recuperacai-extrajudicial-dividas/))
> - **Raízen** — perda de grau de investimento por Fitch/S&P/Moody's em 09/02/2026 (rating fora da janela; assembleias de CRA mai/jun dentro). ([XP](https://conteudos.xpi.com.br/renda-fixa/relatorios/raizen-e-rebaixada-perde-grau-investimento/), [ADVFN](https://br.advfn.com/jornal/2026/02/raizen-tem-rating-de-credito-rebaixado-por-fitch-s-amp-p-e-moody-s))
> - **Kora Saúde** — RE homologada 04/05; **GPA** — RE edital 10/06.
>
> Para um radar de **crédito**, um emissor em RE/recuperação ativa deveria permanecer flagado enquanto o processo durar, independentemente da data do marco inicial. Hoje some do painel quando o marco "envelhece" 30 dias. Sugestão: flag de estado `em_reestruturacao` por emissor (sticky até resolução), desacoplada da janela rolling de eventos. Impacto: Alto · Esforço: M.

**Nota operacional.** Esta execução agendada disparou ~19h30 BRT (`ts 2026-06-12T22:30Z`), ~2h **após** o cron de newsletter do Worker (18h30 BRT). Os dados persistidos alimentam o dashboard e as próximas execuções, mas **não entraram no newsletter de hoje**. Avaliar alinhar o gatilho da routine para antes das 18h30, ou o newsletter para depois da routine.

## 7. Implementação 2026-06-12 — T16, P16, T15

> [!success] T16 + P16 + T15 implementados e deployados (2026-06-12)
> Worker v4.9.107 (CF Version ID `9c958883-ba48-439d-a9f0-b00f1382fbce`) + Frontend v201.50 (Pages deploy `18c443ed`). Health check pós-deploy: `versao:"v4.9.107"`, `kv/rate_limiter/telemetria:true`, `3/3 providers`.

| Item | Status | Worker/Frontend | Evidência |
|---|---|---|---|
| **T16** Fix system prompt — data URL path | **✅ Implementado** | Worker v4.9.107 | `buildSystemPrompt` corrigido: data do path é contexto informacional, nunca causa de descarte; `data_evento` DEVE vir do conteúdo |
| **P16** Flags `em_reestruturacao` por emissor | **✅ Implementado** | Worker v4.9.107 + Frontend v201.50 | KV `emissor:flags:*`; helpers `lerFlagsEmissor`/`gravarFlagsEmissor`; admin endpoints `flags_emissor_get/set/list`; `_flags` exposto em `op=state`; badge roxo "RE" na sidebar; aba "Flags RE" no admin |
| **T15** Retry 1x com backoff 2s nos 3 providers | **✅ Implementado** | Worker v4.9.107 | Loop `for (_try<2)` nos 3 providers; AbortController recriado por tentativa; retry apenas em AbortError/5xx; 401/429 jogam exceção imediatamente |
| **P11** Alertas por emissor favoritado | ✅ (v4.9.103, 2026-06-08) | — | Já estava implementado; corrigido N06 em v4.9.105 |

**Commits:**
- `afe1250` — `fix+feat(worker): v4.9.107 — T16 fix data URL, P16 flags em_reestruturacao, T15 retry`
- `21c36ac` — `feat(frontend): v201.50 — P16 badge RE emissores em reestruturacao, admin flags`
- `dd29661` — `chore(frontend): regenera version.json v201.50 para deploy Pages`

**Como usar P16 (ops):**
```
# Setar emissor em reestruturação (via admin do painel)
# Aba "Flags RE" → selecionar emissor → marcar checkbox → salvar

# Via API direta (admin):
POST https://radar-credito-api.prospects-intel.workers.dev
{"action":"flags_emissor_set","admin_senha":"<senha>","empresa":"Oncoclínicas","em_reestruturacao":true,"nota":"RE ativa — medida cautelar 17/04/2026"}
```

## Lacunas e Próximos Passos

- Dados de spread ANBIMA continuam limitados (sem `duration` populada em escala, sem séries longas) — P14 depende parcialmente da qualidade dessas séries; validar cobertura de `serie:` antes de iniciar.
- Esforços (P/M/G) são estimativas qualitativas; dimensionar em sessão de implementação.
- Decisão de operador pendente: ordem de execução do top 5 e se P11 dispara também WhatsApp (infra Twilio existe) ou só email.

## Referências

- [[09 - Auditoria 2026-06-10 (Pendências)]] — achados e críticos ativos
- [[08 - Análise de Risco e Arquitetura de Confiabilidade]] — matriz de risco
- [[03 - Estado de Produção]] — versões e bindings
- `PENDENCIAS.md` (raiz do repo) — tabelas T1–T15 / P1–P15 consolidadas
