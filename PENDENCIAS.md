# PENDENCIAS.md — VIX Radar

**Atualizado:** 2026-07-19 12:25 BRT (ESCAPEH1 P0 corrigido — `renderEventoCard` estava quebrada desde v201.76, nenhum card de evento renderizava em emissor algum; Frontend v201.80, commit `dc505d7`) | **Produção:** Worker v4.9.166, Frontend v201.80, health ok, verificador_ok true

## Síntese executiva

1. **Sistema operacional, sem drift técnico.** Worker v4.9.165, Frontend v201.77, health `ok:true`, bindings todos true, verificador_ok true. Drift era só de documentação (este arquivo e o Obsidian citavam v201.76 e RACEKV1 como não deployado; ambos já estavam resolvidos em produção, corrigido nesta atualização).
2. **Ingestão recuperada 18/07 23:46 BRT.** Sessão OAuth do CLI `claude` expirou, noturna 18/07 18h abortou com `submit_ok:0` (95/103 sem análise). Operador reautenticou (`claude /login`) e agente disparou rerun manual: `submit_ok:100 + skip_ok:3 = 103/103`, `submit_fail:0`. Staleness pós-rerun: `fresh_le24h:103, idade_max_h:3.6`. Ver Obsidian `03 - Estado de Produção.md` (nota 18/07 23:46).
3. **Rotinas ativas:** Matinal 17/07 OK. Noturna 18/07 recuperada (ver item 2). Verificador async operacional com mutex + token budget (commit d329510).
4. **Monitor-TaskScheduler:** Falso positivo 0x41301 corrigido (commit 37e7e2f).
5. **VIXRadar-AgendaSemanal:** Desabilitada desde 13/07 (credit balance too low). Não verificado se o mesmo reauth de hoje destrava — pendente checagem.
6. **RACEKV1 confirmado deployado.** `wrangler.toml` ao vivo (`main=v4.9.165.js`) já declara o binding `ESTADO_SEMANA_DO`; health público confirma `versao:v4.9.165`. A entrada antiga deste arquivo ("não deployado") estava desatualizada — commit `2dac9c0` já registra o deploy. Ver RACEKV1 em "Resolvido" abaixo.
7. **LOGLOCK1 reincidiu, agora sustentado.** Ver `LOGLOCK1-REC` abaixo — não corrigido nesta sessão (fora do escopo aprovado).
8. **V0EMPTY1 publicado em produção.** Frontend v201.78, deploy validado (version.json + CACHE_VERSION no HTML confirmados ao vivo), commit `8ae3127` pushado — reconcilia de quebra o drift de git da reforma visual (que já estava no ar desde 18/07 sem commit). Ver "Resolvido" abaixo.
9. **JANELACONF1 publicado em produção.** Worker v4.9.166 no ar (commit `dde2e84`), health confirma `versao:v4.9.166` e `ESTADO_SEMANA_DO` continua no binding (RACEKV1 intacto).

---

## Pendências abertas

| ID | Sev | Área | Achado | Ação |
|----|-----|------|--------|------|
| HDASH1-RES | P3 | Backend / segurança | Registro estava desatualizado desde v4.9.151. Handler atual (`api/v4.9.164.js:15200-15213`) usa só `_exigeJwtAdmin`; testado ao vivo (18/07): `senha`/`admin_senha` por querystring retornam 401 em todos os casos. `handleUso` ainda lê `searchParams.get("senha")` (linha 5181) mas é código morto (único call site pré-valida via POST body). | Nenhuma. Considerar remover o fallback morto de `handleUso` por higiene (não é vulnerabilidade). |
| ALRT1-RES | P3 | Backend / e-mail | Parte P1 (broadcast total sem filtro quando `EMAIL_ALERTAS_FAVORITOS` ausente) **já corrigida em v4.9.163/164** — confirmado ao vivo no bundle (`selecionarDestinatariosAlerta`, `api/v4.9.164.js:4840-4867`), os dois caminhos agora checam `prefs.alertas===false` simetricamente. Residual documentado no próprio código: `prefs.newsletter` não governa alerta crítico (decisão de produto deliberada, não bug). | Operador decidir se alerta crítico deve respeitar `prefs.newsletter` (hoje trata como canal independente) |
| SPF1 | P2 | DNS / deliverability | `send.vixradar.com` em softfail `~all` vs raiz `-all`. Hardcoded em script. | Atualizar script + DNS |
| CLEANAGG1 | P2 | Rotinas / governança | Cleanup aggressive apaga logs/métricas de todos os dias anteriores (retenção real = 1 dia) | Aggressive deve poupar `*.log`/`*_metrics_*.json` |
| FOCUSTRAP1 | P2 | Frontend / acessibilidade | Modal `role="dialog"` não retém foco (falha WCAG 2.4.3 confirmada ao vivo) | Trap de Tab + foco inicial |
| PRED2 | P3 | Ingestão / dados | Chaves com case divergente em `radar:estado:2026-W28`. Causa raiz identificada (CASEKEY1). | Limpeza manual do KV |
| P-CVM | P3 | Dados / CVM | `admin_corrigir_datas_cvm_kv` em lote. Requer admin_senha. | Operador executar via painel |
| E-MT | P3 | Email | Confirmar se `email_modo_teste` ativado. Requer admin_senha. | Operador verificar |
| LOGLOCK1-REC | P2 | Rotinas / observabilidade | Reincidência do LOGLOCK1 (fix 17/07, commit `49904ea`, retry de 5x200ms) na noturna de 18/07: `vixradar-noturno_20260718.log` travado em 100% das escritas desde 22:59:34 até o fim da corrida (23:43:15+), sem se recuperar — diferente do incidente original, que era intermitente. Teste direto (`[System.IO.File]::Open(...,'None')`) confirmou lock ocupado por 7+ min seguidos. Suspeita: `OneDrive.Sync.Service`+`SearchIndexer` ativos no host (diretório do projeto sob sync), alta frequência de escrita (~1 linha/seg) supera a janela de retry atual. **Dado não foi afetado** (`submit_ok:100` confirma pipeline de persistência independente do log). Ver Obsidian `03 - Estado de Produção.md` (nota 18/07 23:46). | Avaliar excluir `logs/` do sync do OneDrive (config de pasta, fora do escopo de código) ou aumentar retry/backoff em `Write-Log`; validar sob a mesma carga antes de fechar |

---

## Resolvido desde 2026-07-13

| ID | Data | O que |
|----|------|------|
| ESCAPEH1 | 19/07 (P0, vigente desde 17/07) | `renderEventoCard` chamava `h()` (escape HTML) 14x sem que `h` existisse no escopo do bloco principal — resquício do fix XSS do v201.76 (commit `10568a9`), que introduziu as chamadas mas não a definição. A `function h(s)` existente no arquivo está em outro bloco `<script>` (módulo de temas/PDF), invisível dali. `ReferenceError: h is not defined` estourava dentro do template do `innerHTML`, abortando a atribuição inteira: **nenhum card de evento renderizava em nenhum dos 103 emissores por 2 dias**. Mascarado porque o feed do painel geral usa outro caminho (`_v201RenderCard`) e seguia funcionando. **Fix:** `function h(s)` definida no escopo correto, antes de `renderEventoCard`. **Validado:** 26/26 blocos JS com `node --check` limpo; varredura pós-deploy com 78 emissores com eventos e 0 falhas de render; prova visual em 2 emissores; console sem erros; escape XSS confirmado intacto. **Publicado em v201.80** (commit `dc505d7`). |
| JANELA30x90 | 19/07 | `normalizarResultadoPayload` (`app/index.html`) filtrava eventos com janela de 30 dias enquanto todo o resto do sistema usa 90 dias, e marcava `sem_eventos:true` ao zerar a lista. Rodando ANTES no pipeline (em `carregarResultadosCompartilhados`/`carregarResultados`), apagava qualquer evento com data entre 30 e 90 dias atrás e marcava o emissor como vazio — atingia toda a base, não só os 2 emissores do report do operador (Eletrobras 20/05, Auren 01/06). Confirmado ao vivo: backend retornava o evento, `normalizarResultadoPayload(raw)` no console entrava com 1 e saía com 0. **Fix:** `-30` → `-90` (1 caractere). Validado sobre dado real (Eletrobras/Auren voltam com 1 evento, Oncoclínicas mantém 18) + prova visual pós-deploy (aba "Eventos (1)" na Eletrobras). **Publicado em produção v201.79** (commit `8eba296`). Distinto do V0EMPTY1 (aquele era flash transitório de loading; este apagava dado real de forma permanente). |
| JANELACONF1 | 19/07 | Campo `_ultima_janela_inicio`/`_ultima_janela_fim` (bookkeeping de 1 dia, só gravado em `sem_eventos:true`) tinha nome idêntico ao conceito real de janela de busca de 30 dias (`montarPlanoRotina`), gerando falsa suspeita de busca "só de 1 dia". Renomeado para `_ultima_checagem_vazia_inicio`/`_ultima_checagem_vazia_fim`. Campo é write-only (confirmado via grep em todo o repo, nenhum leitor). **Publicado em produção v4.9.166** (commit `dde2e84`, `deploy-worker.ps1`, health validado ao vivo). |
| RACEKV1 | 19/07 (deploy confirmado; fix era de 18/07) | Escrita concorrente sem lock em `radar:estado:{semana}` (KV sem CAS). Fix: Durable Object `EstadoSemanaDO` (1 instância/semana) serializa as 4 funções afetadas via fila de promises FIFO, com fail-open se o binding faltar (nunca descarta dado). **Confirmado deployado nesta auditoria:** `wrangler.toml` ao vivo com `main=v4.9.165.js` + binding `ESTADO_SEMANA_DO`; health público `versao:v4.9.165`. Residual: comportamento do DO sob concorrência real de produção ainda não validado por teste de carga dedicado (só simulação Node isolada). |
| V0EMPTY1 | 19/07 | Dashboard (`Painel de eventos`) renderizava "0 críticos/0 relevantes/nenhum alerta ativo" como estado definitivo antes do fetch assíncrono de `op=state` resolver — achado ao vivo em produção (1º paint mostrou zero, reload com wait de 3s mostrou os 12 críticos reais). Causa raiz: `_v201Init` (`app/index.html`) disparava `_v201RenderDashboardOverride()` num `setTimeout` fixo de 500ms sem checar se `resultados` já tinha dados; `_v201RenderBanner`/`_v201RenderFeed` computam direto sobre `resultados`, sem guarda de loading. **Fix:** o `setTimeout` só chama o render se `Object.keys(resultados).length>0`; se os dados ainda não chegaram, mantém o placeholder neutro ("Selecione um emissor...") em vez de afirmar "zero risco". **Publicado em produção v201.78** (commit `8ae3127`, `deploy-pages.ps1`, version.json + CACHE_VERSION validados ao vivo). |
| STATELEAK1 | 13/07 | KV com 125 chaves em results vs 103 emissores (22 resíduos mojibake). Fix v4.9.153. |
| CHUNK1 | 13/07 | Split-IntoChunks devolvia lotes de 1 emissor (bug array-unwrapping PowerShell). Fix `return ,$chunks`. |
| MIG1 | 13/07 | 3 scripts migrados pay-per-token → assinatura Claude Code. |
| MAT1 | 13/07 | Matinal parada 3 dias por saldo -US$1,21. Resolvido com MIG1. |
| DEF1 | 13/07 | Noturna 12/07 estourou hard cap. Resolvido com CHUNK1 + MIG1. |
| XSSEVT1 | 16/07 | `renderEventoCard` sem `esc()`. Fix deployado v201.76 (commit 10568a9). |
| PRED3 | 16/07 | 16 dos 22 CNPJs sem match resolvidos (commit 6cb1790). |
| ANOMPROMO1 | ~15/07 | Anomalia promovida reaparecia no cron seguinte. Fix em v4.9.152+, deployado na cadeia. |
| RLADMIN1 | ~15/07 | Rate limit fail-open em login/registrar. Fix em v4.9.152+, deployado. |
| CASEKEY1 | ~15/07 | `receber_analise` gravava chave sem case-fold. Fix em v4.9.152+, deployado. |
| RETRYDROP1 | 13/07 | Noturno descartava resultados pagos em retry auth-failure. Fix no disco. |
| VERIFMUTEX1 | 17/07 | Dreno de verificação sem mutex com 3 gatilhos concorrentes. Fix commit d329510. |
| ALRT1 (broadcast) | 17/07 (confirmado 18/07) | Fallback sem `EMAIL_ALERTAS_FAVORITOS` fazia broadcast total sem checar `prefs.alertas`. Fix v4.9.163/164, confirmado ao vivo no bundle. Residual movido para ALRT1-RES (P3, decisão de produto). |
| Staleness 79/103 | 17/07 (confirmado 18/07) | Noturna 17/07 (0 SKIP) reescreveu `_last_scanned_at` de todos. Snapshot pós-noturna: 0 stale >24h. |
| HDASH1 | v4.9.151 (confirmado 18/07) | Senha admin via querystring GET em `health-dashboard`. Fix real desde commit `5cff1cc` (11/07); `PENDENCIAS.md` carregou como aberto por 5 versões. Testado ao vivo: 401 em todas as tentativas de bypass. |
| Monitor 0x41301 | 17/07 | Monitor-TaskScheduler reportava SCHED_S_TASK_RUNNING como erro. Fix commit 37e7e2f. |
| DRIFT1 | ~15/07 | `app/version.json` v201.74 vs prod v201.75. Resolvido com deploy v201.76. |
| Bundle drift | 15/07 | Bundle saiu do .gitignore, canonical-test verde (commit a2e7d84). |

---

## Histórico resolvido (compacto, pré-13/07)

- v4.9.150 (11/07): Mojibake read path + briefing fix + preditivo quick wins
- v4.9.148 (07/07): admin_mercado POST-only, zscores_anbima auth, tel() fix
- v4.9.147 (07/07): z-scores ANBIMA no pipeline EWS
- v4.9.143 (20/06): listar_plano_rotina, cascade externa obsoleta
- v4.9.142 (18/06): admin_mercado auth, email_modo_teste
- Incidente 15/06: ANTHROPIC_API_KEY inválida cegava verificador. Secret rotacionado.
- v4.9.109 (14/06): cron duplicado, CLAUDE.md rewrite

---

## Próximos passos priorizados

| P | Ação | Ref |
|---|------|-----|
| P0 | Confirmar que noturna 17/07 completou 103/103 e timestamps atualizados | Staleness |
| P0 | Operador revisar e aprovar commit d329510 (protocolo RESULTADO + token budget + mutex) | Working tree |
| P0 | Operador decidir sobre VIXRadar-AgendaSemanal (desabilitada desde 13/07) | Agenda |
| P2 | Hardening SPF send.vixradar.com para `-all` | DNS |
| P2 | Corrigir CLEANAGG1 (retenção de logs) | Rotinas |
| P2 | Corrigir FOCUSTRAP1 (trap de foco em modais) | A11y |
| P3 | Limpar chaves duplicadas por case no KV (PRED2) | Dados |
