# PENDENCIAS.md — VIX Radar

**Atualizado:** 2026-07-20 16h50 BRT (auditoria geral autônoma — F002/F014 corrigidos no repo como v4.9.167.js, NÃO deployado; CLEANAGG1 confirmado já resolvido 14/07, drift de doc corrigido; achado novo INGEST-GAP1: Matinal 20/07 e Noturna 19/07 não executaram) | **Produção:** Worker v4.9.166, Frontend v201.80, health ok, verificador_ok true | **Repo (não deployado):** v4.9.167.js pronto

## Síntese executiva

0. **[NOVO, P0] INGEST-GAP1 — ingestão parada ~41h, todos os 103 emissores stale.** `VIXRadar-Noturno` (19/07, deveria rodar 18h) e `VIXRadar-Matinal` (20/07, deveria rodar 10h) **não executaram** — Task Scheduler recusou o lançamento do processo com `0x800710E0` ("o operador ou administrador recusou o pedido") antes mesmo do script `.ps1` iniciar (zero arquivo de log criado para nenhum dos dois). Medição ao vivo (`medir_staleness.ps1`, 20/07 16h46 UTC): **103/103 emissores em STALE 24-48h, 0 frescos, idade máxima 41,7h**; último scan bem-sucedido foi a noturna de 18/07 (~23h UTC). `claude` CLI testado e autenticado agora (não é o mesmo bug de OAuth expirado de 18/07). Evidência de correlação: às 20/07 12:32:02, um lote de tasks não relacionadas (`Szuchmacher-AgendaAgent`, `Szuchmacher-LeadNurture`, `Szuchmacher-MacroCron`, `VIXRadar-Matinal`) falhou com o mesmo código no mesmo segundo — Windows registrou eventos de wake/boot (`Hipervisor iniciado`) às 12:24:39, ~7min antes. Hipótese mais provável (não 100% confirmada): a máquina estava suspensa/desligada na janela do trigger e o disparo de tasks perdidas ao acordar esbarrou num limite de sessão/concorrência do Task Scheduler. **Não executei rerun manual** (ação teria custo real em tokens Anthropic e escrita em KV de produção — fora do escopo autorizado desta sessão de "corrigir código, sem deploy"). Ação recomendada ao operador abaixo.
1. **Sistema operacional, sem drift técnico no que já estava em produção.** Worker v4.9.166, Frontend v201.80, health `ok:true`, bindings todos true, verificador_ok true — confirmado ao vivo nesta sessão (curl direto). Repo local tem v4.9.167.js pronto (F002+F014, ver "Resolvido nesta sessão") apontado em `wrangler.toml`, ainda não deployado.
2. **Ingestão recuperada 18/07 23:46 BRT** (histórico, ver item 0 para o gap atual, distinto). Sessão OAuth do CLI `claude` expirou, noturna 18/07 18h abortou com `submit_ok:0` (95/103 sem análise). Operador reautenticou (`claude /login`) e agente disparou rerun manual: `submit_ok:100 + skip_ok:3 = 103/103`, `submit_fail:0`. Ver Obsidian `03 - Estado de Produção.md` (nota 18/07 23:46).
3. **Verificador async operacional** com mutex + token budget (commit d329510).
4. **Monitor-TaskScheduler:** Falso positivo 0x41301 corrigido (commit 37e7e2f). Confirmado ainda funcionando nesta sessão (relatório 20/07 12:32 capturou o INGEST-GAP1 corretamente).
5. **VIXRadar-AgendaSemanal:** rodou com sucesso às 20/07 12:32 (LastResult=0) — desbloqueada, não precisa mais de checagem.
6. **RACEKV1 confirmado deployado** (histórico) — `wrangler.toml` ao vivo declara `ESTADO_SEMANA_DO`; health público confirma. Ver "Resolvido".
7. **LOGLOCK1-REC — mitigação parcial aplicada nesta sessão.** Backoff exponencial (8 tentativas, ~11s no pior caso, era 5x200ms~1s) nos 3 scripts de rotina. Não resolve lock de minutos inteiros (causa raiz provável: OneDrive sync no diretório do projeto) — ver entrada própria abaixo.
8. **CLEANAGG1 — já estava resolvido (14/07, commit `31035fa`), este arquivo tinha drift.** Corrigido a entrada abaixo para refletir o estado real (movida para "Resolvido").
9. **register-vixradar-tasks.ps1 corrigido nesta sessão:** faltava `-AllowStartIfOnBatteries`/`-DontStopIfGoingOnBatteries`, única entre todos os scripts `register-*-task.ps1` do projeto sem essas flags. Live task (`Export-ScheduledTask`) confirma `DisallowStartIfOnBatteries=true` ainda ativo — script corrigido, mas a task viva só atualiza se o script for reexecutado como Administrador. Achado colateral: existe um SEGUNDO script (`register-all-routines-scheduler.ps1`) que também registra `VIXRadar-Matinal`/`VIXRadar-Noturno`, com config mais resiliente (`RestartCount`, `LogonType` diferente) — os dois scripts divergem e não está documentado qual é o canônico. Ver entrada REGDRIFT1 abaixo.

---

## Pendências abertas

| ID | Sev | Área | Achado | Ação |
|----|-----|------|--------|------|
| HDASH1-RES | P3 | Backend / segurança | Registro estava desatualizado desde v4.9.151. Handler atual (`api/v4.9.164.js:15200-15213`) usa só `_exigeJwtAdmin`; testado ao vivo (18/07): `senha`/`admin_senha` por querystring retornam 401 em todos os casos. `handleUso` ainda lê `searchParams.get("senha")` (linha 5181) mas é código morto (único call site pré-valida via POST body). | Nenhuma. Considerar remover o fallback morto de `handleUso` por higiene (não é vulnerabilidade). |
| ALRT1-RES | P3 | Backend / e-mail | Parte P1 (broadcast total sem filtro quando `EMAIL_ALERTAS_FAVORITOS` ausente) **já corrigida em v4.9.163/164** — confirmado ao vivo no bundle (`selecionarDestinatariosAlerta`, `api/v4.9.164.js:4840-4867`), os dois caminhos agora checam `prefs.alertas===false` simetricamente. Residual documentado no próprio código: `prefs.newsletter` não governa alerta crítico (decisão de produto deliberada, não bug). | Operador decidir se alerta crítico deve respeitar `prefs.newsletter` (hoje trata como canal independente) |
| INGEST-GAP1 | **P0** | Rotinas / infra local | Matinal 20/07 e Noturna 19/07 não executaram — Task Scheduler recusou o lançamento (`0x800710E0`) antes do script iniciar. 103/103 emissores em stale 24-48h agora (idade máx 41,7h). Ver síntese item 0. | Operador: rodar catch-up manual (`Start-ScheduledTask VIXRadar-Noturno` seguido de `VIXRadar-Matinal`, ou os `.ps1` direto) e decidir sobre resiliência estrutural (manter PC acordado no horário, ou reativar fallback cloud) |
| REGDRIFT1 | P2 | Rotinas / governança | Dois scripts registram as mesmas tasks `VIXRadar-Matinal`/`VIXRadar-Noturno` com configs diferentes: `register-vixradar-tasks.ps1` (corrigido nesta sessão, faltava battery) e `register-all-routines-scheduler.ps1` (já tinha battery + `RestartCount 1`/15min + `LogonType Interactive`, mais resiliente). Não documentado qual é o canônico; a task viva no Windows não bate 100% com nenhum dos dois scripts atuais (foi registrada por uma versão anterior). | Operador decidir qual script é a fonte de verdade, rodar como Administrador e descontinuar/documentar o outro |
| SPF1 | P2 | DNS / deliverability | `send.vixradar.com` em softfail `~all` vs raiz `-all` (reconfirmado via `Resolve-DnsName` nesta sessão). Script-fonte `api/tools/criar-token-dns-e-spf.ps1` corrigido para `-all` nesta sessão, mas essa função só CRIA o registro se ausente — não faz PATCH de um registro já existente, então rodar o script não muda o DNS ao vivo. | Atualizar o TXT `send.vixradar.com` no painel Cloudflare DNS (ou PATCH via API) para `-all` |
| FOCUSTRAP1 | P2 | Frontend / acessibilidade | Modal `role="dialog"` não retém foco (falha WCAG 2.4.3 confirmada ao vivo). Não corrigido nesta sessão — `app/index.html` tem 8 dialogs com padrões de abertura/fechamento distintos e histórico recente de regressões P0 em edições pontuais (ESCAPEH1, JANELA30x90); um focus-trap genérico e seguro exige mapear os 8 fluxos com teste comportamental real, maior que o escopo de correção cirúrgica desta sessão. | Trap de Tab + foco inicial, testado em navegador real contra os 8 dialogs antes de deploy |
| PRED2 | P3 | Ingestão / dados | Chaves com case divergente em `radar:estado:2026-W28`. Causa raiz identificada (CASEKEY1). | Limpeza manual do KV (ação em dado de produção, requer admin_senha) |
| P-CVM | P3 | Dados / CVM | `admin_corrigir_datas_cvm_kv` em lote. Requer admin_senha. | Operador executar via painel |
| E-MT | P3 | Email | Confirmar se `email_modo_teste` ativado. Endpoint `email_modo_teste_status` exige `ADMIN_PASSWORD` (secret só no Worker, não presente em `api/.env` local — confirmado nesta sessão que não dá para checar sem a credencial do operador). | Operador verificar |
| ADMINSECRET1 | P3 | Backend / segurança | Dois secrets admin paralelos: `ADMIN_SENHA` (usado por `admin_auto_login`, presente em `api/.env` local) e `ADMIN_PASSWORD` (usado por ~52 handlers que comparam `body.admin_senha` direto, incl. `email_modo_teste_*`, `admin_upsert_analise`; só existe como secret do Worker). Já apontado em auditoria de 13/07 (nota 54), ainda não consolidado. | Decisão de produto/segurança: consolidar em 1 secret ou documentar por que são 2 |
| LOGLOCK1-REC | P2 | Rotinas / observabilidade | Reincidência do LOGLOCK1 (fix 17/07, commit `49904ea`) na noturna de 18/07: log travado 100% das escritas por 7+min seguidos (suspeita OneDrive/SearchIndexer). **Mitigação parcial aplicada nesta sessão:** backoff exponencial em `Write-Log` nos 3 scripts de rotina, 5x200ms (~1s) → 8 tentativas até 2s cada (~11s no pior caso). Não cobre lock de minutos inteiros — continua sem validação sob a mesma carga real (não reproduzida nesta sessão). | Avaliar excluir `logs/` do sync do OneDrive (fora do escopo de código); validar o novo backoff sob carga real na próxima ocorrência |

---

## Resolvido desde 2026-07-13

| ID | Data | O que |
|----|------|------|
| F002 (TECH_DEBT_AUDIT) | 20/07 (repo, não deployado) | 7 `catch{}` vazios remanescentes no bundle (dos 43 originais do audit de 16/06 — os outros 36 já tinham sido corrigidos sem registro explícito). 2 no health check (`_verificadorRealOk`, `_filaVerifAtrasada` — os mais importantes, mascaravam degradação do próprio health sem sinal), 2 em leitura de KV cache, 3 em telemetria-da-telemetria. Todos passam a logar a exceção (`console.error`), mudança puramente aditiva, mesmo fallback em todos. **v4.9.167.js criado, `wrangler.toml` apontado, `node --check` limpo, NÃO deployado.** |
| F014 (TECH_DEBT_AUDIT) | 20/07 (repo, não deployado) | `handleResendWebhook` lia `request.text()` sem limite de tamanho antes do parse/verificação Svix. Cap de 1MB (Content-Length + tamanho pós-leitura), 413 se exceder. Mesmo bundle v4.9.167.js do F002. |
| register-vixradar-tasks.ps1 (battery) | 20/07 (script corrigido, task viva ainda não reregistrada) | Único `register-*-task.ps1` do projeto sem `-AllowStartIfOnBatteries`/`-DontStopIfGoingOnBatteries` — exatamente as 2 tasks mais críticas (Matinal/Noturno). Corrigido no script-fonte; aplicar requer rodar como Administrador (não executado nesta sessão). |
| CLEANAGG1 | **14/07** (commit `31035fa`) — este arquivo carregava como aberto por engano, drift de documentação puro. | Cleanup agressivo usava `$Aggressive -or $item.LastWriteTime -lt $cutoff` (deletava por idade OU por estar em modo agressivo, ignorando `-KeepDays`). Corrigido para `$item.LastWriteTime -lt $cutoff` (retenção de 7 dias respeitada sempre). Confirmado ao vivo nesta sessão: `logs/routines/` tem arquivos de 14/07 a 20/07 coexistindo (retenção multi-dia funcionando de fato). |
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
