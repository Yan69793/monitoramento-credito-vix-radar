# Auditoria Geral Backend/Frontend — VIX Radar (2026-07-13)

## Rodada 2 — caça preditiva + deploy (2026-07-13 ~04:00-04:41 BRT)

Operador pediu explicitamente: aplicar tudo para não recorrer + caçar preditivamente outros bugs. 2 agentes despachados (Worker + rotinas PowerShell), ambos com evidência empírica (código lido linha a linha + testes isolados, não especulação).

**Deploy em produção — Worker v4.9.151 (version `15963cbc-d452-44dc-90ae-788b49577a1c`), aprovado explicitamente pelo operador após apresentação de diff/risco/rollback:**
- **HDASH1 corrigido:** `op=health-dashboard` trocou senha via querystring GET por `_exigeJwtAdmin`. Validado em produção pós-deploy: GET sem JWT e GET com senha antiga na query agora retornam 401 (curl confirmado).
- **Bug real de dedup corrigido:** `isEventoDuplicadoSemantico` tinha `return false` dentro do loop de comparação — parava no 1º candidato não-conclusivo, deixando passar duplicata real de candidato posterior. Trocado por `continue`. Testado isolado fora do Worker: cenário com 2 títulos genéricos idênticos (1º fora da janela/fonte diferente, 2º duplicata real em 5 dias) — bug retornava `false` (duplicata passava), fix retorna `true`; controle sem duplicata real confirma sem falso positivo.
- **2 pontos de `dispararAlertaCritico` sem rede de segurança corrigidos:** rota `consulta_empresa`/pulso manual (sem try/catch, podia derrubar resposta HTTP inteira mesmo com análise já persistida) e rota `admin_upsert_analise` (catch vazio, zero log). Ambos agora capturam+logam+telemetria sem afetar caminho de sucesso.
- **`.gitignore` corrigido:** whitelist de bundles parava em `v4.9.149.js` — `v4.9.150.js` sobrevivia só por add manual anterior, `v4.9.151.js` ficaria invisível ao `git status` sem o fix. Adicionadas as 2 entradas.

**Adiado deliberadamente do deploy** (risco/escopo maior — exigem design ou tocam caminho crítico no dia da validação do CHUNK1): RLADMIN1 (rate limit login/registrar/admin), CASEKEY1 (case-fold `empresa` em `receber_analise`), e os 2 achados P1 do Worker abaixo.

**Rotinas locais — 2 fixes aplicados e commitados (sem deploy, script local):**
- **Mutex no matinal** (`Global\vixradar-matinal-v2`, mesmo padrão do noturno desde 06/07) — matinal nunca teve proteção contra execução concorrente; existem gatilhos manuais (`-RunTask`/`-RunNowMatinal`) capazes de colidir com o disparo nativo das 10h. Aplicado antes do disparo de hoje.
- **Detecção de falha PARCIAL de lote no matinal** — antes só detectava lote com 0 confirmações (`silent_fail`); lote com sucesso parcial (ex.: 4 de 6 emissores) passava sem log, sem retry, sem registro. Novo contador `partial_fail` + log `AVISO` com nomes dos emissores esperados + escalona exit code (mesma severidade de `silent_fail`).
- **`Get-VeredictosArray` (verificação assíncrona) — mesmo padrão preventivo do CHUNK1:** `return $arr` → `return ,$arr`. Hoje inofensivo (só indexado em `[0]`), mas mesma classe de bug latente. Testado isolado: caso `esperado=1` (o que colapsava antes) e caso `esperado=3`, ambos corretos após fix.

### Achados NOVOS não aplicados (P1 arquiteturais + P2/P3 — backlog)

| ID | Sev | Achado | Evidência | Ação sugerida |
|---|---|---|---|---|
| RACEKV1 | **P1** | `radar:estado:{semana}` é 1 única chave KV para os 103 emissores; `persistirResultadoCompartilhado` faz read-modify-write sem lock/CAS. Escrita concorrente de 2 empresas na mesma semana → a última grava por cima, apaga a outra silenciosamente. Mesmo padrão em `mercado:anomalias:ativas` | `api/v4.9.151.js:7430-7495`, `:4120`, `:10629` | Chave por empresa (`radar:estado:{semana}:{empresa}`) ou serializar via Durable Object |
| ANOMPROMO1 | **P1** | Anomalia promovida pelo admin reaparece no próximo cron — `recalcularTodasAnomalias` reconstrói do zero a cada matinal/noturno sem checar `KV_EVENTOS_PROMOVIDOS`. Condições monotônicas (iliquidez) sempre redetectam | `:10783-10800` (overwrite), `:10664-10719` (promote) | Merge preservando estado "promovida", ou checar log de promoções recentes antes de reinserir |
| RETRYDROP1 | **P1** | Noturno: quando o retry-por-emissores-faltantes de um lote esbarra em auth failure, o `break` na linha do retry sai do loop ANTES de submeter os resultados já obtidos com sucesso na chamada principal do mesmo lote — tokens já pagos, resultados (potencialmente CRITICO) descartados sem log de perda | `scripts/run_vixradar_noturno_claude.ps1:528-570` (loop de submissão fica inacessível após o `break`) | Submeter `$parsed.Map` já obtido antes do `break`, ou mover loop de submissão para antes do bloco de retry |
| — | P2 | `receber_analise`/newsletter/demais achados do Worker (janela de corrida no dedup do newsletter, cap 120 `ews:hist:`, `KV.list()` sem cursor em vários prefixos, cap 500 `promovidos`) | Ver relatório completo do agente (Worker) nesta sessão | Backlog, sem urgência imediata |
| — | P2 | Rotinas: idempotência SKIP é código morto (`Submit-SkipEmissor` não loga `OK\|`), limpeza de task órfã reporta sucesso sem verificar, 2 registradores de task divergentes (`pwsh` vs `powershell.exe`) para os mesmos nomes, noturno aborta 100% da cobertura se total≠103 (matinal só avisa), feriados B3 do matinal hardcoded só até 2026 | Ver relatório completo do agente (rotinas) nesta sessão | Backlog, sem urgência imediata (feriado 2026 só vence em 2027) |

**Validação em produção pós-deploy:** `WORKER_VERSAO` estava hardcoded desatualizada (`v4.9.150` dentro do `v4.9.151.js` recém-copiado) — achado durante a própria auditoria, corrigido e redeployado (version `d8251578-bd2a-4c97-87b3-4934dc79fcb0`). `GET /` health final: `ok:true, versao:"v4.9.151", bindings{kv,rate_limiter,telemetria}:true, verificador_ok:true` — confirmado via curl duplo (local + Sprite). Matinal 13/07 10h BRT e noturno 18h BRT são os primeiros testes reais de todo o pacote de hoje (CHUNK1 + mutex + migração de auth + v4.9.151).

**Skill:** `/vix-radar-general-audit` (auditoria ampla de engenharia — complementar à `/vix-radar-audit`)
**Modo:** Readonly. Nenhum deploy, secret ou POST destrutivo executado.
**Escopo:** Worker `api/v4.9.150.js` (bundle ativo), `app/index.html` v201.75 + `app/admin/*.js`, scripts de rotina (`scripts/run_vixradar_*.ps1`), governança de repo, pesquisa externa de mercado.
**Método:** 3 subagentes paralelos em modo readonly (backend, frontend, rotinas/confiabilidade) + verificação ao vivo em navegador (WCAG focus trap) + reprodução isolada de bug em PowerShell + pesquisa externa (Firecrawl).

---

## Nota de processo — colisão com sessão concorrente

Durante esta auditoria, uma **segunda sessão Claude Code rodou em paralelo** (`/vix-radar-audit`, operacional), entre ~03:15–03:34 BRT, quase exatamente sobreposta à janela desta auditoria. Essa sessão:

- Diagnosticou `VIXRadar-Matinal` parada desde 10/07 por saldo Anthropic esgotado (-US$1,21, **confirmado diretamente pelo operador** naquela sessão) — nota [[53 - Auditoria Completa 2026-07-13]].
- Aplicou correção **não commitada** (working tree) em 3 scripts (`run_vixradar_matinal_claude.ps1`, `run_vixradar_noturno_claude.ps1`, `run_vixradar_verificacao_async.ps1`): migração de pay-per-token (`ANTHROPIC_API_KEY`) para assinatura Claude Code (OAuth), e ampliação do regex `Test-ClaudeAuthFailure` para cobrir `credit balance is too low|insufficient.*credit`.

**Verificado ao vivo nesta sessão (`git diff --stat` + leitura direta pós-edição):** a correção está de fato no disco (10+19+18 linhas alteradas nos 3 arquivos, não commitada). O subagente de rotinas desta auditoria leu esses arquivos durante a janela de edição concorrente — por isso, o achado "matinal sem guard de billing" que ele reportou **já não reflete o estado atual** e foi excluído da lista de novos achados abaixo (rebaixado a nota de reconciliação). Todos os demais achados dos 3 subagentes foram cruzados contra o disco após a descoberta da colisão.

**Não foi tocado pela sessão concorrente:** o bug de chunking (`CHUNK1` abaixo) é o achado central desta auditoria e não tem sobreposição com o trabalho da outra sessão — ela documentou o sintoma (`DEF1`, hard cap 12/07) mas não investigou a causa.

**Recomendação de processo:** revisar as duas auditorias (nota 53 + esta) em conjunto antes de decidir commits. Evitar rodar `/vix-radar-audit` e `/vix-radar-general-audit` simultaneamente no mesmo repo — ambas editam os mesmos arquivos de registro (`PENDENCIAS.md`, índice).

---

## Síntese executiva

**Sistema funcionalmente saudável em produção (sem drift Worker/Frontend), mas com um bug de engenharia de alta severidade na rotina noturna que provavelmente é causa estrutural — não pontual — da perda de cobertura dos emissores mais críticos.** Confirmado, reproduzido isoladamente e com correção validada: a função `Split-IntoChunks` (presente em `matinal` e `noturno`) sofre do bug clássico de "array unwrapping" do PowerShell — quando a fila do dia cabe inteira em 1 chunk (o caso comum, já que os tamanhos de chunk do noturno — 15 Haiku / 11 Sonnet — foram dimensionados generosamente), a função devolve os itens **individualmente** em vez de agrupados. Resultado documentado em produção (12/07): 12 emissores Haiku + 8 Sonnet viraram **20 chamadas `claude -p` individuais** em vez de 2 chamadas em lote, consumindo ~10x mais tokens de overhead fixo (~13,6k/chamada) e estourando o hard cap antes de processar os 8 emissores Sonnet — justamente o tier de maior risco (EWS≥38).

Além disso: 1 novo P1 de segurança backend (senha admin via querystring GET, mesma classe de bug já corrigido uma vez), 1 P1 de XSS confirmado em produção (conteúdo gerado por IA sem escape, sem CSP como último obstáculo), e ausência de rate limit em login/registrar/admin combinada com comparação de senha não constant-time.

---

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker `radar-credito-api` | v4.9.150 | v4.9.150 (`GET /`) | Não |
| Frontend `vixradar.com` | v201.75 (`deploy_zip`) | v201.75 | Não |
| `app/version.json` (fonte, não deploy) | v201.74 | — | **Sim, documental** — já registrado como DRIFT1 pela sessão concorrente (nota 53); não bloqueia produção pois `deploy_zip/version.json` está correto |
| `app/admin/*.js` vs `deploy_zip/admin/*.js` | — | — | Falso alarme investigado: hash difere só por final de linha (CRLF vs LF); conteúdo idêntico nos 5 módulos |

---

## Achados novos

### P0 — Crítico

**CHUNK1 — `Split-IntoChunks` colapsa em lotes de 1 emissor quando a fila cabe em 1 chunk; causa raiz confirmada do `DEF1` (nota 53).**

- **Onde:** `scripts/run_vixradar_noturno_claude.ps1:205-214` e `scripts/run_vixradar_matinal_claude.ps1:158-167` (mesma função nos dois scripts).//Chamada: `noturno.ps1:470/473`, `matinal.ps1:319/322`.
- **Configuração que dispara o bug:** noturno usa `$HaikuChunk=15`, `$SonnetChunk=11` (`noturno.ps1:28-29`) — deliberadamente maiores que o volume típico diário para tentar agrupar mais emissores por chamada. Matinal usa `$HaikuChunk=6`, `$SonnetChunk=4` (`matinal.ps1:27-28`) — mesma função, risco menor mas não nulo (dispara sempre que a fila do dia for ≤ chunkSize, o que é comum no tier Sonnet dado o filtro EWS≥38).
- **Mecanismo (PowerShell):** `return $chunks` sem o operador unário `,` — quando `$chunks` tem exatamente 1 elemento (fila inteira cabe em 1 chunk), o pipeline do PowerShell desenrola esse elemento único ao passar por `foreach`, entregando os itens individuais em vez do array agrupado.
- **Evidência em produção (12/07, noturno):** log mostra `Filas: sonnet=8 haiku=12` seguido de `Lote haiku-1: Eneva` … `Lote haiku-11: MRV Engenharia` (11 lotes de 1 emissor cada, não 1 lote de 12) e depois 8 lotes Sonnet de 1 emissor cada, todos `deferred` pelo hard cap. `noturno_metrics_20260712.json`: `tokens_total_est:736030` (hard cap 700000), `sonnet_llm:0`, `deferred:9`.
- **Reprodução isolada (nesta sessão, PowerShell):** a função exata do script, executada com fila de 12 itens e chunkSize 15, devolveu **12 iterações de 1 item** no `foreach` (esperado: 1 iteração de 12). Com chunkSize 6 (força 2 chunks reais), devolveu corretamente 2 iterações de 6. Confirma o mecanismo, não é só correlação de log.
- **Fix validado (nesta sessão):** trocar `return $chunks` por `return ,$chunks` (vírgula unária força o pipeline a tratar o array externo como objeto único). Testado nos 4 casos relevantes — fila cabe em 1 chunk, fila exige múltiplos chunks, fila vazia, fila de 1 item — todos corretos após o fix, nenhuma regressão.
- **Impacto:** ~10x mais chamadas `claude -p` que o necessário em qualquer dia de fila pequena (o caso comum do noturno) → hard cap de tokens atingido prematuramente → exatamente os emissores de maior risco (tier Sonnet, EWS≥38) ficam sem análise, silenciosamente (`deferred`, não alarme). Provável causa estrutural recorrente, não um evento isolado de 12/07 — recomenda-se checar `noturno_metrics_*.json` históricos para `sonnet_llm:0` combinado com `deferred>0` em outras datas.
- **Ação:** aplicar `return ,$chunks` nas 2 cópias da função (`noturno.ps1:213`, `matinal.ps1:166`). Mudança de 1 caractere por arquivo, sem deploy.
- **APLICADO 2026-07-13 ~03:55 BRT, com aprovação explícita do operador.** Validação pós-edição: `[System.Management.Automation.Language.Parser]::ParseFile` — 0 erros nos 2 arquivos. Função extraída do conteúdo real do arquivo (não cópia digitada) e re-testada com os tamanhos exatos do incidente de 12/07: 12 itens/chunkSize 15 → 1 lote de 12 (era 12 lotes de 1); 8 itens/chunkSize 11 → 1 lote de 8 (era 8 lotes de 1); controle 20 itens/chunkSize 6 → 4 lotes (6+6+6+2, inalterado); fila vazia → 0 lotes (inalterado). **Não commitado** — decisão de commit (isolado ou junto com a migração de auth da nota 53) em aberto. Efeito real só se confirma no próximo disparo agendado (matinal 13/07 10h BRT ou noturno 18h BRT) — recomenda-se checar `noturno_metrics_*.json`/`matinal_metrics_*.json` do próximo run por número de lotes vs. tamanho de fila.

---

### P1 — Alto

**HDASH1 — `op=health-dashboard` aceita senha admin via querystring GET.**

- `api/v4.9.150.js:14760-14763` — `url.searchParams.get("senha")` comparado a `env.ADMIN_SENHA` (nota: variável distinta de `ADMIN_PASSWORD`, usada nos ~60 outros pontos de admin).
- Mesmo padrão já removido do `admin_mercado` em v4.9.148 (regressão de classe, não a mesma rota). Com `[observability] head_sampling_rate=1` ativo no `wrangler.toml`, a senha em querystring fica gravada em log de request na Cloudflare.
- **Ação:** migrar para `_exigeJwtAdmin` ou POST form-urlencoded, como já feito em `admin_mercado`.

**XSSEVT1 — XSS confirmado em `renderEventoCard` e no bloco `alertas_mercado`: conteúdo gerado por IA interpolado sem escape, sem CSP como contenção.**

- `app/index.html:3610` (definição ~linha 24774 no bundle minificado) — `titulo`, `evento`/`descricao`, `tags`, `data_evento`, `fonte_tipo`, `memo_acontecimento` e demais campos `memo_*`, `query`, `resultado` das buscas, e `cobertura_nota` são interpolados em `innerHTML` sem `esc()`. Contraste direto: comentários digitados por usuário passam por `_escapeHtmlComentario`, mas a saída da análise de IA (maior superfície do produto) não.
- `_headers` declara explicitamente que a CSP foi omitida "de propósito" (linha 7-9) — não há `<meta>` CSP alternativa. Os `nonce=` nos `<script>` são inertes sem o header correspondente.
- **Impacto:** se uma fonte de notícia processada pela IA contiver HTML malicioso (via memo/título gerado a partir de conteúdo web), executa no contexto do usuário logado com acesso a `radar_jwt` em `localStorage` — mesma classe já corrigida em XSS1/XSS2, superfície bem maior.
- **Ação:** aplicar `esc()` em todos os campos de evento; escapar o corpo dentro de `_mdAnchor`; avaliar CSP em staging (pendência já registrada no vault desde 2026-06-01).

**RLADMIN1 — Rate limiter fail-open combinado com zero cobertura em login/registrar/admin e comparação de senha não constant-time.**

- `checkRateLimitV2` retorna `allowed:true` (fail-open) em 3 cenários de falha: env indisponível, binding ausente, exceção do Durable Object (`api/v4.9.150.js:12895, 12899-12901, 12938-12941`).
- Único call site de rate limit: o caminho de pulso/análise (`:15630`). **Login, registrar, reset de senha e ~60 comparações de `admin_senha`/`ADMIN_PASSWORD` não têm nenhum rate limit nem lockout.**
- Comparação de senha admin é `!==` direto (string compare), não constant-time — teoricamente sujeita a timing attack, mas o risco prático dominante aqui é força bruta sem fricção alguma.
- **Ação:** aplicar `checkRateLimitV2` (ou equivalente) em login/registrar/admin; fail-closed (ou fallback KV) quando o DO falhar.

**ALRT1 (reconfirmado, sem mudança) —** `dispararAlertaCritico` não filtra `prefs.newsletter`; broadcast total se `EMAIL_ALERTAS_FAVORITOS` ausente. Aberto desde 12/07 (nota 52), sem correção até o momento. Ver `PENDENCIAS.md`.

---

### P2 — Médio

| ID | Achado | Evidência | Ação |
|---|---|---|---|
| CASEKEY1 | `receber_analise` grava `body.empresa` cru como chave de `results`, sem case-fold nem validação contra `EMISSORES_LISTA` — **causa raiz confirmada do PRED2** (chaves duplicadas por caixa em `radar:estado:2026-W28`) | `api/v4.9.150.js:15492,15500,15531,15567`; contraste com upsert admin que valida `EMISSORES_LISTA.includes` (`:15078`) | Resolver contra lista canônica antes de persistir (reusar `resolverEmpresa` já existente no parser CSV admin, `:10861`) |
| VERIFMUTEX1 | Dreno de verificação assíncrona sem mutex, com 3 gatilhos concorrentes (cron 10:20/18:20 + inline pós-matinal + inline pós-noturno) — risco de processar o mesmo evento 2x, custo Sonnet duplicado | `run_vixradar_verificacao_async.ps1` sem mutex (contraste: noturno/export/ranking têm) | Mutex `Global\vixradar-verifasync` no padrão já usado no noturno |
| CLEANAGG1 | `cleanup -Aggressive` no `finally` de matinal/noturno apaga logs e métricas de **todos** os dias anteriores — retenção real é 1 dia, não os 7 configurados (`KeepDays`) | `cleanup-rotina-artifacts.ps1:22,59-61`; nenhum log anterior a 12/07 sobrevive em disco hoje — inclusive o log do incidente de billing de 10/07 já não existe | Aggressive deve poupar `*.log`/`*_metrics_*.json`, restringir a prompts/planos temporários |
| COMPARN1 | `comparar` recarrega estado 5-semanas + anomalias por emissor via `handleEWS` interno — N+1: comparar 4 emissores gera 25+ leituras KV redundantes | `api/v4.9.150.js:14578-14585` vs `:12614-12615` | Calcular EWS reaproveitando o estado já carregado no escopo, sem recarregar por emissor |
| FOCUSTRAP1 | Modal `role="dialog" aria-modal="true"` não retém foco — **confirmado ao vivo nesta sessão**: ao abrir o modal de Termos/Documentação, o foco inicial fica em `BODY` (nunca move para dentro do dialog) e `Tab` circula por botões da página por trás enquanto o modal cobre a tela. Falha real de WCAG 2.4.3, não só ausência teórica de trap | Testado via `document.activeElement` + `Tab`×3 no navegador contra `vixradar.com` em produção | Focar o primeiro elemento focável ao abrir + implementar trap de `Tab` dentro do dialog |
| HDASHVER1 | `ADMIN_SENHA` (usado em `health-dashboard`) é variável distinta de `ADMIN_PASSWORD` (usado nos demais ~60 pontos admin) — duas credenciais admin paralelas no mesmo sistema | `api/v4.9.150.js:14763` vs. os demais call sites | Confirmar se `ADMIN_SENHA` ainda é secret vivo em produção; se não, remover a rota; se sim, unificar em `ADMIN_PASSWORD` |

---

### P3 — Baixo (condensado — detalhe completo nos relatórios dos subagentes, disponíveis nesta sessão)

- Logout do frontend não limpa `sessionStorage` (deixa `radar_admin_senha` residual) nem `radar_access_log`/`radar_carteira_v1`/`radar_prefs_*` — `app/index.html:3426`.
- Sessão admin sem TTL — senha em `sessionStorage` até fechar a aba; ações de flags leem direto sem revalidar.
- Cookie `radar_token` Max-Age 7 dias vs JWT `exp` 12h (sessão zumbi); e-mail de reset diz "expira em 1h" mas TTL real é 24h.
- PII em log do Worker: e-mail de terceiro em `console.error` (`:4315`); IP+UA crus em `TEST_MODE_BYPASS` (`:15607`) — persistem via observability.
- `FERIADOS_B3` só cobre 2026-2027; falha (trata feriado como pregão) a partir de 2028.
- `resp()` cai em objeto CORS estático quando o call site omite `request` — erros 400/401 de login/registrar sob `www.vixradar.com` podem não expor `Access-Control-Allow-Origin` correto.
- `_raRejeicoes` sempre `[]` no response de `receber_analise`; campos `rejeitados`/`quarentenados` estruturalmente 0 no caminho de rotina — mascara descartes do sanitizador (invisíveis ao chamador).
- `handleRegistrar` revela status da conta por e-mail (409 diferenciado) sem rate limit — enumeração de usuários.
- `.gitignore` whitelist de bundles para em `!api/v4.9.149.js` — falta `!api/v4.9.150.js` (arquivo está tracked mesmo assim via add manual, mas convenção quebrou para o próximo bundle).
- Manifest do exporter histórico grava `$pred.modelo` em vez de `$pred.model_version` — quem audita só pelo manifest não vê a versão real do modelo.
- Métricas do dreno de verificação são sobrescritas a cada execução do dia (3+ runs/dia) — perde o resultado de runs intermediários.
- Task `VIXRadar-Matinal-Retry` órfã (trigger one-time já expirado, sem próxima execução) aponta para o mesmo script sem mutex.
- `verify-rotinas-v2.ps1` não é gate em lugar nenhum (sem hook, sem CI, sem task) — recomendação de 07/07 segue aberta.
- Frontend: monólito 668 KB (67% JS inline, 25% CSS inline em 3 linhas de 221 KB); 5 `admin/*.js` sem `defer`; Google Fonts render-blocking (2 stylesheets externos); `renderSidebar`/`renderDashboard` sem `DocumentFragment` (re-render total a cada filtro); toasts sem `aria-live`; cache-busting dos `admin/*.js` (`?v=201.69`) dessincronizado do `CACHE_VERSION` atual (v201.75) — mitigado por `must-revalidate`+ETag, não é stale-serving real, só round-trip extra.

---

## Verificações que PASSARAM (sem achado)

| Item | Evidência |
|---|---|
| POST anônimo em rota protegida | `op=state` → 401 `Autenticação necessária`; `receber_analise` → 403 `Acesso negado` |
| Multi-semana nos 5 endpoints obrigatórios | `carregarEstadoMultiSemana(env,5)` confirmado em `state`(:14789)/`ews`(:12615)/`briefing_executivo`(:14405)/`historico_emissor`(:14432)/`comparar`(:14544) |
| CSS `strong` sem `color` global | Nenhuma ocorrência fora de seletor específico |
| JWT | HS256 via WebCrypto, assinatura+exp verificados em toda rota autenticada; sem fallback de secret |
| `admin/*.js` vs `deploy_zip/admin/*.js` | Sync real (diferença só de EOL, não de conteúdo) |
| Compressão HTML | `Content-Encoding: gzip` confirmado; 678KB decodificado → 160KB transferido |
| `ctx.waitUntil` nos crons | Uso correto nos 4 triggers; sem trabalho CPU-bound síncrono relevante |
| Performance de carregamento (medição ao vivo, desktop) | TTFB 157ms, DOM interativo 426ms, load 710ms — sem alarme |

---

## Pesquisa externa aplicada

- **Anthropic billing auto-reload** (`support.claude.com/articles/8977456`) — a causa recorrente dos incidentes de "saldo esgotado" (3 episódios em 10 dias, por MAT1/nota 53) tem solução direta e documentada: ativar auto-reload com teto de gasto na Billing page do console. Complementar (não substitui) a migração para assinatura já aplicada pela sessão concorrente — o modo assinatura ainda tem limite semanal, que também pode ser esgotado.
- **Cloudflare Workers KV performance** (`blog.cloudflare.com/faster-workers-kv`, `rearchitecting-workers-kv-for-redundancy`) — hot reads já são cacheados na edge, mas o Worker não usa `cacheTtl` nem Cache API em nenhum ponto (achado item 12 do subagente backend). Para `op=state` (~108 leituras KV/request) e `comparar` (N+1 confirmado), aplicar `cacheTtl` nos `KV.get` de dados que mudam no máximo 1-2x/dia reduziria latência e custo sem sacrificar frescor.
- **Dead man's switch / monitoramento de cron** (`healthchecks.io/docs/monitoring_cron_jobs`, padrão de heartbeat + grace period) — a falha da `VIXRadar-AgendaSemanal` desta madrugada (03:01 BRT, `Credit balance is too low`) só foi descoberta porque uma sessão de auditoria leu o log manualmente. Um heartbeat externo (ping HTTP no fim de cada rotina, alerta se o ping não chegar dentro do grace period) teria capturado esse e todos os incidentes de rotina documentados no vault desde 07/07 — reforça a recomendação já aberta de migração para Claude Code Routines (Remote), ou como paliativo imediato, um monitor de heartbeat de baixo custo antes da migração completa.

---

## Lacunas

- `status_providers`/`admin_health_check` — bloqueado por `CRED1` (persiste desde 12/07).
- Frequência histórica do bug `CHUNK1` em runs anteriores — não verificada (exigiria varrer `noturno_metrics_*.json`/`matinal_metrics_*.json` históricos por `sonnet_llm:0`+`deferred>0`; a maioria já foi apagada por `CLEANAGG1`).
- Não há canal de suporte/reclamação de clientes identificado no sistema para correlacionar com a alegação de "reclamações de clientes" que motivou este pedido de auditoria — não verificável com as ferramentas desta sessão.
- Verificação de contraste de badges de criticidade — não medido (exigiria captura de tela renderizada, bloqueada por instabilidade do navegador nesta sessão).

---

## Próximos passos priorizados

| P | Ação | Blast radius | Ref |
|---|---|---|---|
| P0 | Aplicar `return ,$chunks` em `noturno.ps1:213` e `matinal.ps1:~166` | Script local, sem deploy — efeito no próximo disparo agendado | CHUNK1 |
| P0/operacional | Revisar e decidir commit da migração de auth (nota 53) antes das 10h de hoje (primeiro teste real) | Já no working tree, não commitado | Nota 53 |
| P1 | `op=health-dashboard`: migrar para JWT admin ou POST | Requer deploy do Worker | HDASH1 |
| P1 | `esc()` em `renderEventoCard`/`alertas_mercado`; avaliar CSP em staging | Deploy frontend (esc); CSP exige teste dedicado | XSSEVT1 |
| P1 | Rate limit em login/registrar/admin; fail-closed no DO | Deploy do Worker | RLADMIN1 |
| P1 | Decidir comportamento de `prefs.newsletter` em alertas críticos | Deploy do Worker | ALRT1 (12/07) |
| P2 | Resolver `empresa` contra `EMISSORES_LISTA` antes de persistir | Deploy do Worker | CASEKEY1 |
| P2 | Mutex no dreno de verificação | Script local | VERIFMUTEX1 |
| P2 | Cleanup agressivo não apagar logs/métricas | Script local | CLEANAGG1 |
| P2 | Focus trap + foco inicial nos modais | Deploy frontend | FOCUSTRAP1 |
| P3 | Ver lista condensada acima | Variado | — |

Nenhuma correção foi aplicada nesta sessão — auditoria readonly por definição da skill. Todas as ações acima aguardam aprovação explícita do operador, indicando quais priorizar.
