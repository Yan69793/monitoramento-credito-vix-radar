# Estado de Produção — VIX Radar

Atualizado: 2026-06-14 (v4.9.110 — PERF op=state paralelizado; consolidação de diretório C:→E:).

## Versões confirmadas

| Componente | Versão | Evidência | Data confirmação |
|---|---|---|---|
| Worker `radar-credito-api` | **v4.9.110** | `GET /` `versao:"v4.9.110"` HTTP 200; CF Version ID `b9da2212-cf3e-4a90-b807-e219318c377c` | 2026-06-14 |
| Frontend `vixradar.com` | **v201.51** | `version.json` `{"version":"v201.51","deployed_at":"2026-06-13T02:20:25Z"}`; sidebar 100 emissores OK | 2026-06-13 |
| Frontend repo | v201.51 | `app/index.html` CACHE_VERSION v201.51; commit `2f74e46` | 2026-06-13 |
| Worker repo | v4.9.110 | `api/v4.9.110.js` `WORKER_VERSAO="v4.9.110"` | 2026-06-14 |

## Incidente 2026-06-14 — Dashboard lento / "CEMIG sem eventos" (RESOLVIDO v4.9.110)

> [!success] PERF op=state paralelizado + consolidação de diretório
>
> **Causa raiz confirmada:** handler `op=state` (`api/v4.9.109.js:13347`) fazia `await lerFlagsEmissor(env, emp)` **dentro de um `for`** sobre ~103 emissores → ~103 leituras KV sequenciais a cada carregamento inicial do dashboard. Latência de vários segundos. Enquanto não retornava, dashboard mostrava "0 de 103 / Nenhum evento" e painel do emissor "sem dados" — estado transitório. Depois populava normalmente.
>
> **Evidência objetiva:** `op=state` autenticado pós-fix = **1,15s cold / 0,39s warm**, 115 emissores, 5 semanas (W24-W20). CEMIG retorna **9 eventos** (debênture R$1,5bi 03/06 + incidente cyber 14/05 + eleição presidente 07/05 + AGO). 47/115 emissores com ≥1 evento. A janela "0 com sinal (7d)" é comportamento correto (eventos fora de 04-12/jun).
>
> **Correção aplicada:** `op=state` agora coleta as flags com `Promise.all` (1 round-trip paralelo em vez de 103×). Edição cirúrgica em `api/v4.9.110.js:13344-13357`; `node --check` OK; demais funções reusadas (`lerFlagsEmissor`, `obterCalendarioEmpresa`, `sanitizarEventosUserFacing`, `carregarEstadoMultiSemana`).
>
> **Validação em produção:** deploy `npx wrangler deploy` 2026-06-14T23:23Z, CF Version ID `b9da2212`. `GET /` → `versao:"v4.9.110"`, kv/rate_limiter/telemetria `true`, 3/3 providers. Login admin com senha documentada confirmado funcionando (o "Credenciais inválidas" relatado era engano de digitação/sessão — sem reset de senha necessário).

## Consolidação de diretório 2026-06-14 — fim do drift C:↔E:

> [!info] Cópia única e repo único
> Havia **duas cópias** em repos git distintos: C:\Projetos Claude\Claude\Sistema de Credito\VixRadar (`VIXRADAR.git`, código defasado v4.9.108, mas dados de hoje mais novos) e E:\Diretorio\Claude\Monitoramento de Credito (`monitoramento-credito-vix-radar.git`, código v4.9.109 + pastas extras). **Decisão:** E:\ é a única cópia ativa, repo `monitoramento-credito-vix-radar.git`.
>
> **Ações:** dados de sessão de hoje fundidos C:→E: via `robocopy /XO` (1 nota Obsidian `2026-06-14.md` + 49 JSONs de noturno em testing/; nenhum código sobrescrito). Pasta-fantasma vazia `E:\...\Sistema de Credito` removida. `.gitignore` corrigido (`_historico/` agora excluído — era furo de PII). CLAUDE.md atualizado (E:\ canônico, C:\ arquivado). C:\ movido para `_ARQUIVO_MORTO_VIXRADAR_2026-06-14\` (reversível). **Sessões futuras DEVEM abrir a partir de E:\Diretorio\Claude\Monitoramento de Credito.**

## Bindings (confirmados via health)

| Binding | Status | Evidência |
|---|---|---|
| RADAR_KV | OK | `bindings.kv:true` |
| RATE_LIMITER_DO | OK | `bindings.rate_limiter:true` |
| RADAR_USAGE_EVENTS | OK | `bindings.telemetria:true` |
| Providers | 3/3 | `providers_configurados:"3/3"` |

## Crons Worker (api/wrangler.toml)

| Cron | Horário BRT | Função (v4.9.106 — AI removida dos crons) |
|---|---|---|
| `30 15 * * 1-5` | 12h30, dias úteis | sync_cvm + recalcular_anomalias + saldo |
| `30 21 * * *` | 18h30, diário | sync_cvm + recalcular_anomalias + sync_anbima + **newsletter** + saldo + healthcheck |
| `0 1 * * *` | 22h00, diário | Watchdog |
| `0 4 * * *` | 01h00, diário | agendaBuildPersistir — calendário 90 dias → KV `agenda:eventos:v1`, TTL 3d (era `0 2 * * *` = 23h BRT, caía no else/noturno duplicando pipeline — corrigido em v4.9.109 / P15*) |

## Scheduled Routines Claude Opus (Claude Code Max)

| Routine | Horário BRT | Função |
|---|---|---|
| `vixradar-matinal` | 13h00, dias úteis | Top 15 emissores por EWS → 9 rodadas de busca → push resultado ao Worker |
| `vixradar-noturno` | 17h30, diário | Top **103** emissores por staleness/EWS → 9 rodadas de busca → push resultado ao Worker (era top_n:30 — corrigido 2026-06-14) |

**Arquivos:** `C:\Users\User\.claude\scheduled-tasks\vixradar-matinal\SKILL.md` e `vixradar-noturno\SKILL.md`

**Secret:** `ROUTINE_API_KEY` configurado no Worker (wrangler secret, 48 chars alfanuméricos). Ver `memory/credenciais.md`.

> [!info] Última execução `vixradar-noturno`: 2026-06-13 (manual, Claude Sonnet 4.6)
> **30/30 emissores concluídos**, 0 falhas de envio (`ok:true` para todos). 11 com `n_eventos≥1`, 19 sem eventos. Janela de análise: 2026-05-14 a 2026-06-13.
>
> **Emissores com eventos persistidos (11):**
> Oncoclínicas (standstill vencido, RE deadline 15/06), Raízen (RE R$64,7bi + S&P CCC+), Light (FR capital R$1-1,5bi plano RJ), Aegea (FR Copasa + downgrade S&P/Fitch), CEMIG (12ª emissão Fitch AAA R$1,5-2bi), Hidrovias (Aviso Debenturistas resgate antecipado), Vibra Energia (Aviso Debenturistas resgate antecipado), CSN (FR Recompra 2026), Azul (FR listagem NYSE post-Ch.11), Simpar (Fitch AA(bra) estável), EcoRodovias (FR Acordo Paraná + Ecoporto), TIM Brasil (Aviso Debenturistas resgate antecipado), Brava Energia (FR anuência debenturistas OPA Ecopetrol), CSN Mineração (FR Recompra 2026; DL/EBITDA 0,11x).
>
> **Alertas de crédito notáveis sem evento CVM persistido:** Oi (leilão 17/06; proteção extraconcursal ~19/06), Kora Saúde (RJ extrajudicial R$2,2bi), GPA (RJ extrajudicial R$4,568bi), MRV (Resia PL negativo US$-32mi), BRK Ambiental (alavancagem 6,0x próxima covenants), Assaí (risco PIS/Cofins R$1-1,2bi deadline 30/06/2026), Neoenergia (fechamento de capital Iberdrola — redução transparência pós-delisting).

> [!success] Varredura completa 103/103 emissores: 2026-06-13 (manual, Claude Sonnet 4.6)
> **103/103 emissores atualizados**, 0 falhas. Todos `ok:true`. Janela: 2026-05-14 a 2026-06-13 (W24).
>
> **Emissores adicionais com eventos de crédito notáveis (pós-noturno):**
>
> | Emissor | Evento | Classificação |
> |---|---|---|
> | **Iguatemi** | IGTAA1 vence 24/06/2026 (11 dias) — monitorar aviso CVM | RELEVANTE |
> | **São Martinho** | Emissão R$1,2bi debêntures verdes 14/06/2026 (IPCA+5,97–6,10%, 10–15a) | RELEVANTE |
> | **Fleury** | Moody's upgrade AAA.br (de AA+.br); DL 1,0x EBITDA | RELEVANTE |
> | **Cogna Educação** | 7ª emissão R$1,25bi aprovada para refinanciamento COGN19/27 | RELEVANTE |
> | **Movida** | 3 debêntures vencendo set–nov/2026 (MOVI17, MOVIA2, MVLV17) | RELEVANTE |
> | **Unidas** | Refinanciamento R$3,4bi; caixa R$3,7bi = 169% vencimentos até 2027 | RELEVANTE |
> | **Direcional Engenharia** | Conselho aprovou emissão de até R$750mi debêntures | RELEVANTE |
> | **Suzano** | Q1 2026 lucro -32%; BofA downgrade equity (não credit rating) | ECO |
> | **Irani** | Q1 2026 lucro -68%; Gaia XI desligada temporariamente | ECO |
> | **Rede D'Or** | Q1 2026 EBITDA +27,3%, receita R$15,5bi; Fitch AAA(bra) mantido | ECO |
> | **Totvs** | Q1 2026 receita +16%, EBITDA +24% | ECO |
> | **Vivo** | Q1 2026 lucro +19,2%, EBITDA +8,9% | ECO |
> | **Cury Construtora** | Q1 2026 receita +32,6%, lucro +42%, ROE 79,5% | ECO |
> | **Multiplan** | Q1 2026 lucro +35,1%, EBITDA +28,9% | ECO |
> | **LWSA** | Q1 2026 lucro +45,3% | ECO |
> | **Ultrapar** | Q1 2026 lucro +100% (Hidrovias covenant breach capturado separadamente) | ECO |
> | **Cyrela** | Q1 2026 lucro -9%, alavancagem 19,6% DL/PL | ECO |
> | **Trisul** | Q1 2026 lucro -31,3% | ECO |
> | **Brisanet** | FOCF negativo previsto 2026 por capex expansão fibra | ECO |
> | **Natura &Co** | Q1 2026 miss: receita -3,7%, EBITDA margin 7,3% | ECO |
>
> **Sem eventos (3):** Algar Telecom, Even Construtora, Log Commercial Properties.
>
> **Lotes anteriores (W24, pré-noturno):** Eletrobras, Eneva, Engie Brasil, Energisa, Copel, ISA Energia, Auren, CPFL, Omega, Comerc, AES Brasil, CCR, Rumo, MRS, Santos Brasil, JSL, Embraer, VLI, Tegma, Arteris, Vamos Locação, Iguá, Copasa, Sanepar, Petrobras, PRIO, Compass, Vale, Gerdau, Usiminas, Tupy, CBA, Nexa, Itaúsa, Itaú, BTG Pactual, Banco Pan, Daycoval, Cielo, B3, Votorantim, Bradesco, Localiza, Klabin, JBS, BRF, Marfrig, Boa Safra, Terra Santa, Camil.

**Novos endpoints Worker (v4.9.106):**
- `action=listar_todos_emissores` (routine_key)
- `action=listar_emissores_prioritarios` (routine_key, top_n)
- `action=dados_para_analise` (routine_key, empresa, setor)
- `action=receber_analise` (routine_key, empresa, setor, resultado)

## CORS

| Origin | Status | Evidência |
|---|---|---|
| `https://vixradar.com` (apex) | OK | `Access-Control-Allow-Origin: https://vixradar.com` |
| `https://www.vixradar.com` (www) | OK | `Access-Control-Allow-Origin: https://www.vixradar.com` |
| Origin rejeitada (evil.example) | OK | ACAO omitido — comportamento correto |

## Segurança

| Header | Status |
|---|---|
| Strict-Transport-Security | `max-age=31536000; includeSubDomains; preload` |
| X-Frame-Options | `DENY` |
| X-Content-Type-Options | `nosniff` |
| Referrer-Policy | `strict-origin-when-cross-origin` |
| Permissions-Policy | `geolocation=(), microphone=(), camera=(), payment=()` |
| CSP | Omitida (by design — HTML monolítico) |

## Auth

| Teste | Resultado | Evidência |
|---|---|---|
| POST / anônimo | 401 "Autenticação necessária" | HTTP 401 em 0.09s |

## Acesso admin

| Campo | Valor |
|---|---|
| Email | szuchmacheryan@gmail.com |
| Senha (sistema + admin) | Ver `memory/credenciais.md` (gitignored — nunca versionar senha em texto claro) |
| Atalho admin desktop | Ctrl+Shift+A |
| Atalho admin mobile | long-press no logo (700ms) |

## Multi-semana

| Endpoint | Lookback | Status |
|---|---|---|
| op=state | carregarEstadoMultiSemana(env,5) | OK |
| op=ews | carregarEstadoMultiSemana(env,5) | OK |
| briefing_executivo | carregarEstadoMultiSemana(env,5) | OK |
| historico_emissor | carregarEstadoMultiSemana(env,5) | OK |
| comparar | carregarEstadoMultiSemana(env,5) | OK |

## Regra CSS `<strong>` global

Regra em `app/index.html:2593`: `strong, .text-strong, [class*="strong"] { font-weight: 600; }` — **sem `color`** ✅

## Cascade AI (v4.9.108)

OpenRouter **removido** de todos os 7 arrays de cascade (batch cron, batch com fila ×2, matinal ×2, Pulso manual). Cada array agora contém apenas `claude-haiku-analise` como fallback.

| Contexto | Arrays | Status |
|---|---|---|
| `executarVarreduraBatch` | `_tier1P`, `_tier23P` | claude-haiku only ✅ |
| `executarVarreduraBatchComFila` | `_mTier1P`, `_mTier23P` | claude-haiku only ✅ |
| `executarVarreduraMatinal` | `_mTier1P`, `_mTier23P` | claude-haiku only ✅ |
| Pulso manual | `providers` | claude-haiku only ✅ |

Rotinas Claude Opus (`vixradar-matinal`, `vixradar-noturno`) são independentes — usam `action=receber_analise` diretamente e não passam por esse cascade.

## Drift repo vs produção

| Componente | Repo | Produção | Drift |
|---|---|---|---|
| Worker | v4.9.109 | v4.9.109 | Nenhum ✅ |
| Frontend | v201.51 | v201.51 | Nenhum ✅ |
| deploy_zip | v201.51 | v201.51 | Nenhum ✅ |

## Histórico recente

- **2026-06-14:** **Worker v4.9.109** — 5 correções aplicadas e deployadas. (1) **N04** `worker_version` hardcoded removido: dois pontos no bundle (`handleOps` linha 11612 `"v4.8.0"` + `executarHealthCheckDiario` linha 13214 `"v4.8.5"`) substituídos por `WORKER_VERSAO`; health check agora reporta versão correta. (2) **N11** catch vazio em `__fixCorsResp` ganhou `console.error("[cors-fix]", ...)` — erros de CORS agora visíveis nos logs do Worker. (3) **P15*** cron `0 2 * * *` (23h BRT) renomeado para `0 4 * * *` (01h BRT): eliminado o pipeline noturno duplicado e ativado `agendaBuildPersistir` (calendário 90 dias → KV `agenda:eventos:v1`, TTL 3d), que nunca havia rodado. (4) **N09** CLAUDE.md corrigido: teste padrão obrigatório trocado de POST anônimo (401) para `GET /` health check público. (5) **P05*** CI `canonical-test.yml` atualizado: `EXPECTED_WORKER="v4.9.102"` → `"v4.9.109"`. Versão WORKER_VERSAO atualizada para `"v4.9.109"` (linha 3483). `wrangler.toml` atualizado (main + crons + changelog). Deploy CF Version ID `089135fe-c640-44dd-967b-06b732576535`. Health check pós-deploy: `{"ok":true,"versao":"v4.9.109","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"3/3"}` HTTP 200. Skill `radar-credito-privado` reescrita completa (v3.9.6/v61 → v4.9.108/v201.51 real). Rotina `vixradar-noturno` corrigida: `top_n:30` → `top_n:103`.
- **2026-06-13 (3):** **vixradar-noturno executado manualmente** — 30/30 emissores, 0 falhas. 11 com eventos persistidos. Emissores CRÍTICOS: Oncoclínicas (standstill vencido, deadline RE 15/06), Raízen (CCC+, RE R$64,7bi), Light (FR capital RJ), Aegea (downgrade S&P/Fitch). Brava Energia: FR OPA Ecopetrol (anuência debenturistas waiver). Noturno anterior: 2026-06-12 (automático).
- **2026-06-13 (2):** **Worker v4.9.108** — OpenRouter removido de todos os 7 arrays de cascade. Causa: OR com saldo -$0.20 (overdraft), todos os providers externos inoperantes. Decisão: usar apenas claude-haiku-analise como fallback para Pulso manual; análises substantivas via rotinas Claude Opus. Deploy CF Version ID `ff307140`. Health check: versao v4.9.108, telemetria OK, tel_test OK.
- **2026-06-13 (1):** **INCIDENTE — Frontend v201.50 derrubou sidebar completa.** Causa raiz: commit P16 (badge RE emissores em reestruturação) introduziu template literal quebrado — `':'}</span>` em vez de `':''}</span>`. O `}` ficava preso dentro de string aberta, derrubando o parser JS inteiro. Detecção: usuário reportou "sistema não está funcionando". Fix: 1 char adicionado. Deploy v201.51 em ~10min. Validated: snapshot Playwright 100 emissores, zero erros. Commit `2f74e46`.
- **2026-06-12:** Worker v4.9.106 deployado. Migração cascade AI externa → Claude Opus scheduled routines. ROUTINE_API_KEY configurado como Wrangler secret. Duas routines criadas no Claude Code (vixradar-matinal 13h BRT dias úteis, vixradar-noturno 17h30 BRT diário). Todos endpoints validados em produção.
- **2026-06-08:** Worker v4.9.102 + Frontend v201.45 — sem drift.

## Pendências abertas

> [!success] Resolvidas em 2026-06-14: P05* (CI), P15* (cron 0 2 duplicado), N04 (worker_version hardcoded), N09 (CLAUDE.md teste anônimo), N11 (catch vazio CORS)

1. **MÉDIO** — `archive/`, `docs/`, `research/`, `testing/` não trackeados no git
2. **INFO** — Saldos providers só verificáveis via painel admin (action=status_providers)
3. **INFO** — `agenda:eventos:v1` no KV: aguarda primeira execução do cron `0 4 * * *` (próxima 01h BRT) para confirmar que `agendaBuildPersistir` popula corretamente

---

## Atualização 2026-06-10 (auditoria repeat-run)

> [!warning] OpenRouter sem créditos (HTTP 402)
> Confirmado em 2026-06-10 via `action=teste`. Sistema rodando exclusivamente em `claude-haiku-4-5-20251001`. Recarregar créditos ou promover haiku a tier primário.

| Item | Status |
|---|---|
| Worker prod | v4.9.102 ✅ |
| Frontend prod | v201.45 ✅ |
| Telemetria | OK (`binding_presente:true`) |
| OpenRouter | **INOPERANTE (402)** |
| Anthropic / haiku | OK |
| Resend | OK |
| CI canonical-test | **QUEBRADO** (401 + EXPECTED_WORKER desatualizado) |

**Drift de artefato (novo achado 2026-06-10):** prod (717 KB, 15.635 linhas) ≠ repo (676 KB, 14.431 linhas). Mesma versão v4.9.102, mas builds diferentes (máquinas distintas). Substituir `api/v4.9.102.js` pelo snapshot de prod em próxima sessão.

Ver relatório completo: [[09 - Auditoria 2026-06-10 (Pendências)]] e `PENDENCIAS.md` (root).

---

## Atualização 2026-06-11 (frontend v201.46 — DEPLOYADO)

> [!success] Deploy concluído — repo == prod == v201.46 (drift fechado)
> Features P12 (comparação de emissores) e P13 (briefing executivo) implementadas e em produção. Commit `bbe54e9`. Deploy Pages em 2026-06-11 via `wrangler pages deploy ./app/deploy_zip` (deployment `0f3c1d32`).

| Componente | Repo | Produção | Evidência |
|---|---|---|---|
| Frontend `vixradar.com` | v201.46 | **v201.46** | `CACHE_VERSION="v201.46"`; `version.json` apex+www v201.46; Cache-Control no-store |
| Worker | v4.9.102 | v4.9.102 | sem mudança |

**Validação pós-deploy (2026-06-11):**
- Módulo live no HTML: `_VIX_INTEL_VERSAO="v201.46"`, `briefingAbrir`/`compararAbrir` presentes.
- `GET api.vixradar.com/?op=briefing_executivo` sem token → **HTTP 401 em 0.09s** (gated, roteado).
- `GET api.vixradar.com/?op=comparar` sem token → **HTTP 401 em 0.08s**.
- Verificação local (pages dev) pré-deploy: render de ambas as telas com payload real-shape + teste adversarial XSS aprovado.

> [!warning] Ação de segurança pendente (operador)
> O token Cloudflare usado neste deploy foi colado no chat — **rotacionar imediatamente** (Pages Edit + Account Settings Read + User Details Read) e reconfigurar como variável de ambiente do Windows. Transcrições de sessão podem ser logadas. Precedente: token anterior já foi comprometido por exposição.

Detalhe da implementação em [[10 - Oportunidades de Melhoria (2026-06-11)#Status de implementação (2026-06-11)]].

---

## Atualização 2026-06-11 (verificação online + fix v201.47)

Verificação end-to-end por Claude in Chrome (logado em produção) sobre a entrega v201.46. Resultado: 5/7 itens OK; 1 fix de frontend; 1 refinamento de diagnóstico crítico.

### Fix v201.47 — Briefing sempre mostra seção "Alertas EWS"

> [!success] DEPLOYADO em produção 2026-06-11 (commit `745e8cb`)
> Autorizado pelo operador. Deployment `44119551`. Evidência bruta: `version.json` apex+www = v201.47; `CACHE_VERSION`/`_VIX_INTEL_VERSAO` = v201.47 no HTML servido; string do empty-state ("Nenhum alerta de mercado ativo") presente no bundle de produção.

- **Causa raiz:** `_renderBriefing` (`app/index.html:5371`) escondia a seção EWS inteira quando `ews_resumo.top_alertas` vinha vazio (`if (alertas.length)`). Como as anomalias de mercado (spread/volume ANBIMA) são limitadas, a lista vem legitimamente vazia → seção sumia, indistinguível de feature quebrada.
- **Correção:** sempre renderiza cabeçalho "Alertas EWS (N com anomalia)" + empty-state explícito quando vazio. Caminho populado inalterado.
- **Evidência:** validado em pages dev (porta 8788) com `fetch` mockado exercitando o `_renderBriefing` real — caso vazio (seção + "Nenhum alerta de mercado ativo…") e caso populado (2 linhas CEMIG/Raízen + "spread_alto (alta)"). `CACHE_VERSION`/`_VIX_INTEL_VERSAO` = v201.47, módulo recarrega sem erro de parse.

### Refinamento do crítico N01 (OpenRouter) — NÃO é falta de crédito

> [!danger] Diagnóstico anterior superado: saldo OpenRouter $76.08 + HTTP 402
> O health do Worker em 2026-06-11 retorna `openrouter:true` (genérico) mas `perplexity_primario` e `openrouter_web_search_exa` com `PROVEDOR_INDISPONIVEL: 402` — **com saldo positivo de $76.08**. 402 + saldo ≠ "sem créditos". Causa provável: billing de add-on / spending limit / modelo de web-search depreciado no OpenRouter. **Ação revisada:** investigar no painel OpenRouter por que os modelos `perplexity/sonar` e `exa web search` retornam 402 com saldo — não basta "recarregar créditos". Sistema segue operando em `claude-haiku-4-5` (Anthropic direto), que não usa web search.

### Achado de dado — setor "Outros" no comparar/briefing (N06)

- Auren Energia aparece com Setor "Outros" no `op=comparar` (esperado: Energia Elétrica). Backend (`handleBriefingExecutivo:12925` e comparar) usa `resultado.setor || "Outros"` — o estado semanal do emissor não tem `setor` persistido. Sintoma do N06 (divergência `CRITICIDADE_SETOR` × `EMISSORES_MAP` / setor não persistido no payload). Backend — não tocado nesta sessão.

### Demais itens da verificação — OK

`version.json` v201.46 + Cache-Control no-store; `window.CACHE_VERSION`/`_VIX_INTEL_VERSAO` v201.46; sidebar com os 2 botões; Comparar emissores funcional (105 emissores, seleção 2-5, tabela lado a lado); regressão OK (painel do emissor + Market Overview).

---

## Atualização 2026-06-11 (reconciliação Worker + P11 implementado)

### Drift de artefato do Worker — RECONCILIADO (fecha achado de 2026-06-10)

Snapshot de produção puxado via Cloudflare MCP (`workers_get_worker_code`) e comparado com `api/v4.9.102.js`:

| Arquivo | Bytes | Linhas | WORKER_VERSAO |
|---|---|---|---|
| PROD (snapshot) | 717.241 | 15.657 | v4.9.102 |
| REPO (`v4.9.102.js`) | 676.385 | 14.431 | v4.9.102 |

> [!success] VEREDICTO: equivalentes (só o build difere)
> Mesmos 293 nomes de função (módulo sufixo de minificação), mesmos 69 `action`/16 `op`/52 `handle`, mesmos literais exceto artefatos de bundler. Delta de ~40 KB = camada extra de wrapping de polyfills (esbuild de máquina distinta: prod bundlado em `User`, repo em `szuch`). **Produção não tem código funcional ausente no repo.** Base segura para editar = repo. Snapshot gitignorado (`api/_prod_snapshot_*.js`), mantido só como evidência. Ressalva: ambos são bundles minificados, sem fonte hand-authored — dívida técnica aberta.

### P11 — alerta crítico direcionado por favorito (Worker v4.9.103)

> [!warning] IMPLEMENTADO em repo (commit `c829fd3`) — NÃO DEPLOYADO
> Produção segue v4.9.102. `wrangler.toml main` já aponta `v4.9.103.js` (preparado).

- **Mudança** (cirúrgica, aditiva): nova fn `selecionarDestinatariosAlerta(env, empresa)` — com gate `EMAIL_ALERTAS_FAVORITOS`, seleciona destinatários = quem favoritou a empresa E não optou por sair (`prefs.alertas !== false`), via scan `user_favoritos:*`; fail-closed em erro. `dispararAlertaCritico` passa a usá-la. Sem o gate, mantém broadcast a todos os aprovados (idêntico a v4.9.102).
- **Frontend não muda:** toggle "Alertas críticos" (`prefs.alertas`) e favoritos já existem e persistem server-side (`action=salvar_prefs`).
- **Validação local (sem deploy):** `node --check` OK; `testing/test-p11-selecao-destinatarios.mjs` 8/8 asserts (fn real extraída do bundle); Worker sobe no `wrangler dev` como v4.9.103 (bindings de infra true).
- **Para ativar em produção:** (1) rotacionar token + autorizar deploy Worker; (2) `cd api && npx wrangler deploy`; (3) `wrangler secret put EMAIL_ALERTAS_FAVORITOS` = "1"; (4) confirmar `EMAIL_ALERTAS_ENABLED` (kill-switch); (5) validar pulso em emissor favoritado.

---

## Atualização 2026-06-11 02:07 BRT — Validação online completa (Claude in Chrome)

Verificação end-to-end em produção sobre v201.47 + v4.9.102. Resultado geral: **nenhuma regressão**; todos os fluxos principais operacionais.

### Confirmado em produção

| Item | Resultado |
|---|---|
| Frontend v201.47 (`deployed_at 2026-06-11T04:17:40Z`) | OK |
| Worker v4.9.102 (3/3 providers, kv, telemetria, rate_limiter) | OK |
| Fix v201.47 — seção "Alertas EWS" sempre visível (0 anomalias + empty-state) | **CONFIRMADO** |
| Briefing: 190 eventos, 22 críticos, 71 relevantes, 106 emissores, confiança 76%, 622 docs CVM | OK |
| Comparar: tabela lado a lado, bloqueio >5 (checkboxes disabled), botão disabled <2 | OK |
| Visão Geral, painel emissor (Sabesp), modal Novo Pulso, toggle Alertas críticos | OK |
| Engajamento admin: erro genérico v201.47 exibido; mensagem melhorada v201.48 ausente | Esperado (v201.48 não deployado) |

### Pendente de deploy — confirmado pelo sintoma em produção

- **v4.9.104 (N06 display):** distribuição setorial do Briefing exibe mix de nomes canônicos e lowercase da cascade (`mineracao`, `energia`, `alimentos`, `financeiro`, `aeroespacial`, `saude`, `construcao`, `servicos`, `imobiliario`), com **duplicação de categorias** (ex.: "Saúde" e "saude" como linhas separadas, inflando SETORES=21). Auren Energia segue "Outros" no Comparar. Tudo isso é o sintoma exato que o fix `SETOR_DE_EMPRESA[emp]` resolve.
- **v201.48:** mensagem de erro específica do Engajamento.

### Achado — autenticação admin

`RadarAdmin@2026` **rejeitada** em produção ("Acesso negado"). Senha vigente para sistema e admin: a do operador (registrada em `memory/credenciais.md`). A skill `radar-credito-privado` (plugin) contém a credencial antiga — desatualizada, não é fonte de verdade.

---

## Atualização 2026-06-11 — Deploy Worker v4.9.105 + Frontend v201.48

> [!success] DEPLOYADO em produção 2026-06-11 05:29Z
> Worker v4.9.105 Version ID `c8e93a7a-8535-4c25-bedc-cc441d88b24f`. Pages deployment `8077def8`. Validado: `GET /` retorna `versao:"v4.9.105"`, `version.json` apex = v201.48, CACHE_VERSION no HTML = v201.48.

| Componente | Versão | Evidência |
|---|---|---|
| Worker `radar-credito-api` | **v4.9.105** | `versao:"v4.9.105"` + `ok:true` + `3/3 providers` + `kv/telemetria/rate_limiter:true` |
| Frontend `vixradar.com` | **v201.48** | `version.json` v201.48 apex OK; CACHE_VERSION no HTML OK |
| `EMAIL_ALERTAS_FAVORITOS` | "1" (P11 ativo) | Secret configurado via `wrangler secret put` |

**Crons ativos:** 4 triggers confirmados (`30 15 * * 1-5`, `30 21 * * *`, `0 1 * * *`, `0 2 * * *`).

> [!success] RESOLVIDO — Engajamento operacional (2026-06-11 sessão continuação)
> `CLOUDFLARE_API_TOKEN` configurado como secret do Worker. Token `vixradar-analytics-engine-read` criado no Cloudflare dashboard: permissão `Account Analytics:Read`, escopo conta `Szuchmacheryan@gmail.com's Account` (7ac79fb1030e4e81115ef33c21a9b070). Validação: `POST {action:"uso",visao:"overview"}` → HTTP 200 com dados reais (587 `admin_upsert_analise`, 110 `login`, etc.).

---

## Atualização 2026-06-11 — N06 cálculo resolvido em repo (Worker v4.9.105)

> [!success] IMPLEMENTADO em repo — NÃO DEPLOYADO (aguarda rotação de token)
> `wrangler.toml main = "v4.9.105.js"`. Produção segue v4.9.102.

- **Causa raiz confirmada:** `CRITICIDADE_SETOR` (bundle linha 11983) tinha 6 chaves divergentes das 13 canônicas do `EMISSORES_MAP` (linha 3933). `enriquecerEvento` consulta `CRITICIDADE_SETOR[setor] || 0.7` (linha 12056) com o setor canônico vindo de `SETOR_DE_EMPRESA` — **48/103 emissores (~47%) caíam no fallback 0.7**, distorcendo a materialidade. Pior caso: Financeiro (9 empresas) calculado com 0.7 quando o peso correto é 0.95.
- **Correção aplicada:** objeto `CRITICIDADE_SETOR` realinhado às 13 chaves canônicas. Mapeamento de pesos: Transportes e Logística 0.85, Financeiro 0.95, Real Estate e Construção 0.7, Petróleo, Gás e Combustíveis 0.85, Telecom e Tecnologia 0.65, Locação de Veículos e Mobilidade 0.7 (novo, neutro). 7 setores já coincidentes inalterados. 6 chaves órfãs removidas.
- **Evidência objetiva:** diff v4.9.104→v4.9.105 = exatamente 8 linhas (2 de versão + 6 chaves); `node --check` OK; `testing/test-n06-criticidade-setor.mjs` PASS — 13/13 setores cobertos, zero chaves órfãs (objetos extraídos do bundle real).
- **Validação em produção:** PENDENTE — após deploy, verificar materialidade de emissor Financeiro/Transportes no Briefing (deve refletir peso 0.95/0.85, não 0.7).
