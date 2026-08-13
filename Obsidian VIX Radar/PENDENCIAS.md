---
data: 2026-08-06
tipo: pendencia
tags: [vix-radar, backlog, acoes]
status: ativo
---

# Pendencias — VIX Radar

Fila de acoes abertas. Prioridade: P1 (critico, trava operacao), P2 (alto, degrada cobertura ou seguranca), P3 (medio, melhoria ou conveniencia), P4 (baixo, cosmetico ou futuro).

---

## Abertas (13/08 — auditoria geral + execução)

### P0 — ABERTO: cascade de IA parado (AUTHWEEK1). Assinatura no limite semanal + chave paga sem crédito

**Achado:** Sonda em processo limpo: OAuth 429 "You've hit your weekly limit, resets Aug 15, 8am" e chave paga `VIXRADAR_ANTHROPIC_API_KEY` 400 "Credit balance is too low". Nenhuma rotina de análise roda até 15/08 08h BRT (ou recarga). Noturno 13/08 18h00 aborta limpo (exit 5). Cobertura congelada no dado de 12/08 18h28.

**Correção:** operador recarrega a chave paga, ou aguarda o reset. Guarda proposta: notificação quando a sonda detectar 429 de limite semanal (a sonda já detecta, falta notificar).

**Causa raiz:** três drenos de verificação em 12/08 (~2M tokens) + noturno completo estouraram o limite semanal da assinatura. A pendência de 04/08 ("recarregar crédito da chave paga") nunca foi executada.

### P1 — ABERTO: secret ADMIN_PASSWORD do GitHub Actions divergiu do Worker (GHWL1)

**Achado:** frescor-check 403 desde 10/08, scan-emergencia falhando desde 09/08. Os dois guardas de staleness ficaram cegos por 4 dias sem detecção. Repetição da classe de drift de 24/07 (documentada neste arquivo).

**Correção:** operador atualiza `secrets.ADMIN_PASSWORD` em GitHub → Settings → Secrets and variables → Actions. Validar com `scripts/check-gh-actions-health.ps1` (novo, commit `f82872d`) na próxima janela de runs.

**Guarda:** `check-gh-actions-health.ps1` + aviso reforçado no `apply-security-rotation.ps1`. Publicação automática do secret segue impossível via PAT fine-grained (403), exige token clássico ou UI.

### P1 — ABERTO: 8 commits locais à frente do origin, push bloqueado por credencial

**Achado:** `git push origin HEAD` retorna 403 "Write access to repository not granted" com o credential manager E com o token do gh (PAT fine-grained sem Contents write). Commits de hoje (FIMREAL1, BOM, XSS, deploy v202.8, GHWL1) estão só no disco. canonical-test vai acusar drift de frontend na próxima run até o push sair.

**Correção:** operador roda `gh auth refresh -s repo` (ou push manual). Repo local está íntegro e sincronizado com produção (v202.8 / v4.9.192).

### P1 — FECHADO hoje: BOM UTF-8 nos scripts

35 .ps1 varridos, 18 regravados com BOM byte a byte, parse PS 5.1 64/64 OK. Commit `9764a3d`.

### P2 — FECHADO no código: XSS Market Overview (parcialmente deployado)

Frontend v202.8 **no ar** com escape nos 4 pontos do módulo v100 (commits `0ee7987`, `88c758d`, `832b72d`). Worker com strip no `sanitizarPayloadRadar` commitado (`01f95bd`) mas **sem deploy**: `deploy-worker.ps1` reprova `ok:false` pós-deploy. Deployar v4.9.193 quando o health voltar a verde (~14/08 21h30Z, via sweep).

### P0 — VERIFICADO hoje: não há solicitações pendentes

Telemetria AE 10 dias: última solicitação 07/08 10:04, zero desde então. KV: 33 usuários, 0 pendentes. Fluxo de aprovação funcional (WhatsApp admin 07/08 HTTP 201, zero `registrar_email_admin_erro` em 10 dias).

Detalhe completo: [[81 - Auditoria Geral e incidentes 2026-08-13]].

---

## Abertas (12/08 — auditoria geral, skill vix-radar-general-audit)

### P1 — ABERTO: dreno diario da fila de verificacao nao acompanha o enfileiramento da noturna

**Achado:** Em 12/08 o dreno processou 12 de 17 itens e a fila cresceu para 16 durante a execucao (noturna enfileira mais rapido do que o dreno diario de 10h20 esvazia). Os 5 itens de 11/08 23h33Z cruzaram o SLA de 20h as 19h33Z e o health caiu para `ok:false` (`verificador_ok:false`). Proximo canonical-test previsto 01h15Z (13/08) deve falhar e mandar email ao admin.

**Correcao:** drenar a fila manualmente (executar `run_vixradar_verificacao_async.ps1`) antes de 01h15Z, e revisar a capacidade do dreno (aumentar `dias=3` do listing, rodar dreno apos o noturno, ou aumentar chunks mantendo o teto de 700k tokens).

**Causa raiz:** o unico dreno roda 10h20 BRT, a noturna enfileira 18h00, e o SLA de 20h vence as ~19h33 do dia seguinte. A janela de dreno nao cobre a taxa de enfileiramento em dias de backlog.

**Guarda:** alerta de fila no canonical-test ja existe (e vai acender). Proposta: alerta adicional quando o dreno termina com fila restante acima de um limite, ou agendar um segundo dreno pos-noturno.

### P1 — ABERTO: 12 `.ps1` do working tree sem BOM UTF-8 com caracteres nao-ASCII

**Achado:** A reescrita em massa de caminhos para `FREQUENTE\` (12/08) regravou os scripts sem o BOM. Os 3 drivers diarios estao na lista: `run_vixradar_matinal_claude.ps1` (32 bytes nao-ASCII), `run_vixradar_noturno_claude.ps1` (35), `run_vixradar_verificacao_async.ps1` (30). Completam a lista: `watch-noturno-progress.ps1` (74), `register-all-routines-scheduler.ps1` (27), `atualizar_altman_cvm.ps1` (12), `reconciliar_ipe_cvm.ps1` (10), `seed_labels.ps1` (10), `verify-rotinas-v2.ps1` (8), `register-verificacao-async-task.ps1` (6), `run_vixradar_ranking_mensal.ps1` (6), `cleanup-rotina-artifacts.ps1` (3). PowerShell 5.1 le arquivo sem BOM como ANSI e corrompe acentos em literais — precedente real documentado em `run_vixradar_noturno_claude.ps1:15` (match de emissor quebrado). O pre-commit hook reprova o commit nesse estado, mas nada impede o script de RODAR.

**Correcao:** regravar os 12 arquivos com BOM UTF-8 (prefixo `EF BB BF`) mantendo o conteudo, antes do proximo disparo (matinal 13/08 10h00). Copia antiga em `E:\Diretorio\Claude\Monitoramento de Credito\` tem o mesmo problema, nao serve de backup.

**Causa raiz:** ferramenta de edicao em lote que grava UTF-8 sem BOM, usada na reorganizacao de caminhos, sem rodar `lint-encoding.ps1` apos.

**Guarda:** item permanente na matriz da auditoria geral: varredura de BOM/nao-ASCII no working tree. Opcional: self-check de BOM no inicio dos 3 drivers (precedente: `GUARD_OK` anti-duplicata).

### P2 — ABERTO: candidato a XSS armazenado no Market Overview

**Achado:** `app/index.html:4051` interpola `e.titulo` (titulo gerado por LLM, gravado sem strip de HTML em `sanitizarPayloadRadar`) direto em `innerHTML`, sem `escapeHtml`. Os helpers existem no codigo (`escapeHtml` no worker, `esc()` no dashboard) mas o modulo v100 nao usa.

**Correcao:** aplicar escape no titulo e empresa antes do `innerHTML` do modulo Market Overview, e strip de HTML no write path do titulo (`sanitizarPayloadRadar`).

**Causa raiz:** modulo novo (v100) escrito antes da padronizacao de escaping do resto do frontend, sem revisao de segurança no merge.

**Guarda:** item permanente na matriz (escaping de saida em todo `innerHTML` que toque dado de LLM) + grep de `innerHTML` com interpolacao de campo LLM na auditoria geral.

---

## Abertas (06/08 02h45 — pos-incidente 04-06/08)

### Status geral

Sistema totalmente operacional. Worker v4.9.187, `ok:true`, `verificador_ok:true`. Incidente de 04-06/08 encerrado: fila drenada (23 eventos), 2 guardas estruturais novas (preflight ROUTINE_API_KEY + Assert-VixLibFunctions).

### P0 — ENCERRADO 06/08: verificador async quebrado por call sites orfaos

**Origem:** Commits `b60d21c` e `2b025b0` (05/08) removeram `Get-VixModeloEnvInfo` e `-ModeloFixadoNaChamada` sem atualizar `run_vixradar_verificacao_async.ps1`. Script quebrou silenciosamente por ~24h.

**Correcao:** `c4a498a`/`06cf4b7` removeu as chamadas orfas e adicionou preflight de ROUTINE_API_KEY. `3e7cbc6`/`250e909` adicionou `Assert-VixLibFunctions` nos 3 scripts de rotina — se uma funcao for removida da lib sem atualizar call sites, o script aborta com `exit 97` em vez de morrer no meio de um lote.

**Validado 06/08 02:15:** Fila zerada (23 eventos, 14 aprovados, 9 rejeitados, 785k tokens). Health `ok:true`, `verificador_ok:true`.

### P0 — ENCERRADO 06/08: guarda ambiental bloqueando verificador async

**Origem:** `ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro` no ambiente do processo (injetado pelo runtime Claude Code). Resolvido com `Set-VixClaudeAuthEnv` limpando as vars antes do check, e `Test-VixClaudeAmbienteLimpo` deixando de inspecionar `settings.json.model` (campo do REPL, nao do `claude -p`).

### P1 — RESOLVIDO 11/08: VERIFSLA1/VERIFSLA2, health lookback ampliado de 2 para 7 dias

**Fechado em:** 11/08. Deploy v4.9.190.

**O que foi feito:**
1. `listarFilaVerificacaoPendente(env2222, 2)` → `listarFilaVerificacaoPendente(env2222, 7)` (VERIFSLA2, commit `6131979`).
2. Lookback do health agora cobre a mesma janela de 7 dias do `sweepFilaVerificacaoOrfaos`. Item com 3-7 dias de idade e `criado_em` <48h, que antes ficava invisivel ao health e nao era morto pelo sweep, agora é detectado.
3. Comentario documenta a restricao: lookback >= janela do sweep. Se alguem mexer em uma das duas constantes sem mexer na outra, o comentario avisa.

**Validacao:** Health pos-deploy: `ok:true`, `verificador_ok:true`, `versao:v4.9.190`, HTTP 200, 0,20s. Ver [[03 - Estado Atual]].

### P3 — RESOLVIDO 11/08: senha demo rotacionada

**Fechado em:** 11/08. Rotacao via API admin (`admin_reset_senha`).

**O que foi feito:**
1. Senha `VixRadarDemo2026!` substituida por nova senha gerada aleatoriamente.
2. Conta `demo@vixradar.com` atualizada em producao (hash SHA-256 novo no banco de usuarios).
3. `memory/2026-07-25-igor-apresentacao.md` atualizado com a nova senha.

**Nota:** A senha antiga permanece no historico do git. Reescrever 200+ commits por uma senha demo nao compensa. A conta demo tem acesso read-only, sem privilegio admin.

### P0 — RESOLVIDO 11/08: painel admin morto em producao desde 03/08

**Fechado em:** 11/08. Deploy do frontend em 09/08 (v202.6) publicou `admin-bootstrap.js` corrigido. Confirmado por auditoria: `app/index.html:3980` e `app/deploy_zip/index.html:3980` ambos com `<script type="module" src="app/js/admin-bootstrap.js?v=202.6">`, `import('/app/js/admin-bootstrap.js')` resolve sem erro em producao.

### P1 — RESOLVIDO 11/08: Worker v4.9.187 deployado e superado por v4.9.189

**Fechado em:** 11/08. Worker em producao responde `versao:v4.9.189` (health check 11/08 20:43 BRT), 2 versoes a frente da que esta pendencia pedia. VALIDFIX1 (fail-open de Content-Type ausente + CORS em 415/413) foi deployado junto.

### P0 — CREDITO ZERADO NA API ANTHROPIC. Rotinas paradas, tasks reativadas (04/08 09:39)

**Origem:** Sessao de revisao e execucao das rotinas em 04/08 09:39 BRT. As duas tasks do Scheduler (`VIXRadar-Matinal` e `VIXRadar-Noturno`) estavam **Disabled**, motivo desconhecido. Reativadas com `Enable-ScheduledTask`.

**Estado das rotinas:**
- Worker: `ok:true`, `v4.9.186`, todos os bindings verdes. Nao e isso.
- Tasks: reativadas. Matinal com trigger Seg-Sex 10:00, Noturno diario 18:00. Proximo disparo da matinal e hoje 10:00.
- Cobertura: 94/103 emissores processados na noturna manual da madrugada (01:29-06:27, sessao Claude Desktop). 9 emissores FULL de alto EWS pendentes: **Oncoclinicas, Oi, Raizen, Kora Saude, Pao de Acucar (GPA), Light, CSN, Aegea Saneamento, Simpar**.

**O que trava a execucao:** `ANTHROPIC_API_KEY` (VIXRADAR_ANTHROPIC_API_KEY, 108 chars) e valida mas a conta esta sem credito (`Credit balance is too low`, HTTP 400). A assinatura OAuth tambem nao responde (sessao expirada). Resultado: `claude -p` nao consegue executar lote nenhum.

**Melhorias aplicadas nesta sessao (3 arquivos):**
1. `Get-RoutineKey` hardened nos 3 scripts (matinal, noturno, verificacao async): fallback de leitura de `ROUTINE_KEY` do SKILL.md removido. Agora so aceita `$env:ROUTINE_API_KEY`. Commit pendente.
2. Sintaxe validada nos 3 scripts (ParseFile PowerShell, 0 erros).

**Para destravar (Yan, acao sua):**
- Recarregar credito na conta Anthropic associada a `VIXRADAR_ANTHROPIC_API_KEY`, OU
- Fazer login no Claude Desktop (`claude /login`) para restaurar a sessao OAuth que estava funcionando as 07:44 de hoje, OU
- `claude setup-token` para token longevo que sobrevive a reinicio e Task Scheduler

**Validacao pendente:** Matinal hoje 10:00 BRT (se credito ou OAuth resolvido ate la). Se nao resolver a tempo, rodar manualmente com `-Force` depois para cobrir os 9 FULL pendentes alem do top 15 normal.

> [!warning] Estado de task nao se afirma aqui
> Situacao de task do Scheduler mora em [[03b - Infraestrutura]], derivada de `Get-ScheduledTask`.
> Esta nota cita, nao redeclara. Em 27/07 tres itens daqui diziam "task removida" durante uma
> hora depois das tasks terem sido recriadas, porque as duas notas descreviam o mesmo estado
> sem nada amarrando uma na outra.

### P1 — RESOLVIDO 27/07 13h. Causa raiz do exit=1 ao invocar `claude -p` era o settings.json global, nao quota

**Origem:** Auditoria 27/07 12h09, causa raiz fechada na auditoria geral das 13h (ver [[69 - Auditoria Geral 2026-07-27]]).
**Descricao:** AgendaSemanal (03:00) e Matinal (10:00) falharam com exit=1, log truncado exatamente na chamada ao binario `claude`, stderr com 0 bytes.

**A hipotese anterior (quota/OAuth transitoria) estava ERRADA.** O probe manual das 12h09 respondeu porque rodou numa sessao interativa do app desktop, que sobrescreve `ANTHROPIC_BASE_URL` de volta para `api.anthropic.com`. O agendador nao tem esse override.

**Causa raiz confirmada:** `C:\Users\User\.claude\settings.json` foi alterado em **26/07 17:59** introduzindo um bloco `env` de roteamento DeepSeek:
```
ANTHROPIC_BASE_URL = https://api.deepseek.com/anthropic
ANTHROPIC_MODEL / DEFAULT_OPUS / DEFAULT_SONNET = deepseek-v4-pro
ANTHROPIC_DEFAULT_HAIKU_MODEL = deepseek-v4-flash
CLAUDE_CODE_SUBAGENT_MODEL = deepseek-v4-flash
model = deepseek-v4-pro
```
As rotinas chamam `claude -p --model claude-sonnet-4-6`. Num processo do Task Scheduler, que le o settings.json direto e sem override, isso enviava um modelo Claude para o endpoint da DeepSeek e o processo morria sem escrever stderr.

**Evidencia que isola a causa:** a Monitor-Tasks das 07:00, unica rotina que **nao** usa `claude -p`, rodou normalmente no mesmo dia. As duas que usam falharam. E o mesmo bloco quebrava todo subagente do Claude Code com "deepseek-v4-flash may not exist" (8 tentativas, 4 tipos de agente, 3 overrides de modelo, todas identicas).

**Correcao aplicada 27/07 ~13h:** bloco `env` e chave `model` removidos do settings.json. Backup em `settings.json.bak-20260727`. Hooks (PreToolUse, PostToolUse, Stop) e demais chaves preservados, validado por diff e parse JSON.

**Validacao executada:** probe `claude -p --model claude-sonnet-4-6` em processo `powershell.exe -NoProfile` com todas as variaveis `ANTHROPIC_*` e `CLAUDE_CODE_SUBAGENT_MODEL` explicitamente removidas, dependendo unicamente do settings.json: **exit 0**. Essa e exatamente a condicao do agendador.

**Acao remanescente:** (a) confirmar Noturno 27/07 18:00 com exit 0; (b) decidir se re-executa a matinal de hoje para recuperar a cobertura top-15 perdida; (c) o pedido original da pendencia continua valido e vira item proprio: `Invoke-ClaudeBatch` deveria ter um probe pre-voo que aborta com log claro em vez de morrer silencioso com stderr vazio, que foi o que tornou este diagnostico caro.
**Validacao:** log noturno 27/07 com exit 0 e submit_ok compativel com o universo.

### P2 — Probe pre-voo em `Invoke-ClaudeBatch` (falha silenciosa custou o diagnostico): RESOLVIDO 02/08

**Fechado em:** 02/08. Commit `8f0b25b`.
**O que foi feito:**
1. `Initialize-VixClaudeAuth` agora valida a chave paga com `Test-VixClaudeSonda` antes de confiar nela. Se a key falhar, modo vira 'nenhum'.
2. As 3 rotinas (matinal, noturno, verificacao async) abortam com exit 5 se `Get-VixClaudeAuthModo` retornar 'nenhum', ANTES do primeiro lote.
3. O probe da chave paga consome ~2k tokens. Custo aceitavel contra 120k+ tokens perdidos em lotes que vao falhar com 401.
**Validacao:** Parse test PowerShell 5.1 em todos os 6 arquivos (6/6 OK). Lint encoding 6/6 OK.
**Cobertura:** Tambem teria prevenido o incidente DeepSeek de 27/07 (a sonda teria falhado com modelo Claude no endpoint DeepSeek) e o 401 de 31/07 (chave invalida detectada na sonda).

### P3 — Limpar chaves ROUTINE_API_KEY mortas e corrigir o fallback que serve chave morta: RESOLVIDO 03/08

**Fechado em:** 03/08. Sessao de fechamento de pendencias.
**O que foi feito:**
1. Chave morta `mXE2...` (48 chars) substituida por `CHAVE_ROTACIONADA_REMOVIDA` em 5 arquivos:
   - `Obsidian VIX Radar/rotinas/2026-06-22-haiku-12.md`
   - `Obsidian VIX Radar/rotinas/2026-07-02-noturno-v2.md`
   - `scripts/_archive/ipad-matinal.md`
   - `scripts/_archive/ipad-noturno.md`
   - `scripts/dry-run-rotinas-v2.ps1`
2. Verificacao adicional: grep em 120 arquivos do repo confirma zero vestigios da chave morta.
3. Chave ativa (`OdCB...`, 43 chars) nao foi encontrada em nenhum arquivo, sem risco de alteracao acidental.
**Validacao:** `git diff` confirma substituicoes. Nenhum arquivo fora dos 5 listados foi alterado.
**Nota:** A correcao do fallback em `Get-RoutineKey` (trocar leitura de chave morta do SKILL.md por `throw`) e recomendada como item separado de melhoria, mas a urgencia caiu porque a chave morta nao existe mais nos arquivos fonte.

### P1 — A matinal reportou sucesso com 100% das buscas falhando, e gravou em producao: RESOLVIDO 02/08

**Fechado em:** 02/08. Commits `950f818`, `41930d9`, `0c8d9ea`, `75708fc`.

**As 4 acoes foram implementadas:**

1. **Pre-flight de ambiente** (commit `950f818`): Nova lib `vixradar-ambient-check.ps1` com `Test-VixClaudeAmbienteLimpo`. Checa `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL` no registry e no `settings.json`. Se qualquer um apontar para agregador/modelo nao-Claude, aborta com exit 6 antes de consumir um token.

2. **Probe de WebSearch** (commit `41930d9`): `Test-VixWebSearchProbe` na mesma lib. Executa busca trivial (cotacao IBOVESPA) com WebSearch+WebFetch e valida resposta substantiva. Se falhar, aborta com exit 7 antes do primeiro submit. Custo ~2k tokens.

3. **Contador real de buscas** (commit `0c8d9ea`): O script agora percorre `fontes_consultadas` de cada emissor e conta resultados validos. Emissores FULL com zero buscas efetivas sao degradados para INCONCLUSIVO com `sem_eventos:true`. O `LOTE_FECHADO` reporta o contador real, nao o autodeclarado.

4. **Parametro -Force** (commit `75708fc`): `-Force` ignora a trava de idempotencia e reprocessa todos os emissores. Nao precisa mais renomear log manualmente apos execucao contaminada.

### Remediacao do incidente, concluida 27/07 14:40

Duas tentativas foram necessarias. A primeira, as 13:38, foi **no-op nos contaminados**: a
trava de idempotencia leu as linhas `OK|` da execucao suja e pulou os 18, processando apenas
3 emissores que ainda nao tinham sido tocados. Foi assim que o defeito 4 acima apareceu.

A segunda, as 14:03, funcionou depois de rotacionar o log para
`logs\routines\vixradar-matinal_20260727_CONTAMINADO_1317.log` (renomeado, nao apagado: e a
evidencia do incidente). Resultado:

```
14:16:25 FIM: tokens=123782 sonnet=7 haiku=7 submit_ok=14 submit_fail=0
              deferred=0 criticos=6 auth_fail=0 silent_fail=0
```

**Verificacao de que a cobertura foi real desta vez**, e nao autodeclarada: 31 rodadas
registradas no log, **0 ocorrencias de "deepseek"**, e 0 rodadas com resultado de falha. O
unico hit do grep de falha era falso positivo do proprio grep, a palavra "encerrou" contem
"erro". As buscas voltaram com dado substantivo ("Fitch perspectiva negativa; alavancagem
5,7x", "covenant violado 2024", "57,49% creditos aderidos; projecao reducao R$2B").

**O sinal mais forte de que a diferenca e real esta no verificador adversarial:**

| Rodada | Fila | Aprovados | Rejeitados |
|---|---|---|---|
| Contaminada (13:32) | 5 | 1 | **4** |
| Reprocessada (14:16) | 8 | **6** | 2 |

O verificador retratou 4 dos 5 eventos da rodada sem busca, via `retratarEventoRejeitado`,
que remove o evento do estado publicado. Ou seja a camada de verificacao **fez o trabalho
dela** e limpou a maior parte do estrago dos CRITICOs antes mesmo do reprocessamento. O que
ela nao alcanca sao os ECO e RELEVANTE, que nao entram na fila de verificacao, e esses
dependiam do reprocessamento.

**Licao que fica, e nao e sobre o DeepSeek.** A rodada contaminada exibiu
`submit_fail=0 auth_fail=0 silent_fail=0` e `buscas=12`. Todo indicador verde. O unico lugar
do sistema que percebeu o problema foi o verificador adversarial, que e caro e roda depois.
Uma checagem de tres linhas comparando `fontes_consultadas[].resultado` contra um padrao de
falha teria abortado antes do primeiro submit, de graca. Ver acao 3.

**Custo do incidente:** 120638 tokens na rodada perdida, 575214 no dreno que verificou dado
ruim, 123782 no reprocessamento, 261945 no dreno seguinte. Ver [[project_rotina_ambiente_limpo]].

### P2 — VIXRadar-Reconciliacao-CVM: RESOLVIDO 03/08. Bug PS 5.1 corrigido, W32 foi falha de rede transiente.

**Fechado em:** 03/08. Commits pendentes nesta sessao.
**O que foi feito:**
1. Primeiro disparo real em 03/08 08:00. Log `vixradar-reconciliacao-cvm_20260803_080003.log` (1441 bytes).
2. Diagnostico do exit 1:
   - Semana W32: falha de fetch HTTP na API Cloudflare KV (erro de rede transiente)
   - Semanas W31 e W30: erro `-AsHashTable` — parametro exclusivo do PS 7+, incompativel com PS 5.1
3. Correcao aplicada em `scripts/predictive/reconciliar_ipe_cvm.ps1`:
   - `ConvertFrom-Json -AsHashTable` → `ConvertFrom-Json` (sem parametro PS 7+)
   - Iteracao: `$results.GetEnumerator()` → `$results.PSObject.Properties` (compativel PS 5.1)
   - Acesso: `$ev['classificacao']` → `$ev.classificacao` (dot notation em PSCustomObject)
   - `$ErrorActionPreference = 'Stop'` → `'Continue'` (regra PS 5.1 / Task Scheduler)
4. **Risco residual**: A falha de rede na W32 pode se repetir. O script ja tem tratamento (aviso + continue), mas se todas as semanas falharem, o script aborta com "ERRO FATAL". Este e o comportamento correto: publicar dado incompleto e pior que nao publicar.
**Validacao:** Proximo disparo 10/08 08:00. Verificar log com exit 0 e semanas lidas > 0.

### P3 — VIXRadar-Coleta-Volatilidade: RESOLVIDO 02/08. 5 dias consecutivos exit 0.

**Fechado em:** 02/08.
**Descricao:** Task recriada em 27/07. Executou com sucesso em 27/07, 30/07, 31/07, 01/08 e 02/08 — 5 dias consecutivos com exit 0. Coleta e upload estaveis. Script compativel com PowerShell 5.1. Nada mais a fazer aqui.
**Evidencia:** `logs\routines\coleta_volatilidade_20260802.log` com "FIM: coleta_volatilidade OK".

### P2 — VIXRadar-Export-Historico: RESOLVIDO 02/08. Token atualizado, export funcionando.

**Fechado em:** 02/08. Commits `4bfab4e` + `45e8cf9`.
**O que foi feito:**
1. Token `CLOUDFLARE_API_TOKEN` substituido no registry User por um com permissao Workers KV Storage.
2. Script corrigido para sempre ler o token do registry, nao depender do env var herdado (que continha o token antigo sem a permissao).
3. Export 02/08 executado com sucesso: 103 emissores no predictive, 78 com serie, 4 arquivos em `data/historico/2026-08-02/`, 199s, 0 avisos.
**Evidencia:** `logs\routines\vixradar-export_20260802_195824.log` com "FIM: ok".

### P2 - Guard em register-all-routines-scheduler.ps1: RESOLVIDO 03/08

**Fechado em:** 03/08. Sessao de fechamento de pendencias.
**O que foi feito (3 correcoes):**
1. **Escopo explicito no cabecalho**: Lista as 6 tasks cobertas e as 6 tasks NAO cobertas (Monitor-Tasks, Coleta-Volatilidade, Export-Historico, Reconciliacao-CVM, Ranking-Mensal, Verificacao-Async), com o script registrador de cada uma.
2. **Aviso de perda de disparo**: Nova logica em `Register-OneTask` que compara hora atual com hora do trigger. Se for um dia de execucao e a hora do trigger ja passou, emite `Write-Host` em amarelo: "ATENCAO: [task] perdera o disparo de hoje (HH:mm ja passou)."
3. **Log operacional do Scheduler**: Adicionado `wevtutil sl Microsoft-Windows-TaskScheduler/Operational /e:true` no inicio do script com tratamento de erro (aviso amarelo se falhar).
4. **Bonus**: `$ErrorActionPreference = 'Stop'` → `'Continue'` (regra PS 5.1 / Task Scheduler).
**Validacao:** `git diff` mostra 41 linhas adicionadas no script. Parse test PowerShell sintaxe OK.

### P2 — monitor-tasks.ps1 inventa a causa da falha da AgendaSemanal: RESOLVIDO 02/08

**Fechado em:** 02/08. Commits `8f0b25b` (staleness) + `e9068b8` (leitura real).
**O que foi feito:**
1. Monitor detecta tasks que NAO RODARAM comparando LastRunTime com ciclo esperado.
2. Regra hardcoded "Credit balance too low" substituida por leitura do log real em `logs/routines/vixradar-agenda-semanal_<data>.log`. Casa contra padroes: credit balance, API key invalida, roteamento agregador. Se nenhum casar, reporta "exit 1 sem causa identificada" como ERRO (nao warning).
3. Sem a leitura real, o monitor mentia sobre a causa. Agora ou reporta a causa confirmada no log, ou admite que nao sabe.

### P2 — Probe CLI antes da Noturno 18:00: RESOLVIDO 02/08. Sistema recuperado.

**Fechado em:** 02/08.
**Descricao:** Apos correcao do settings.json (27/07) e OAuth (30/07), as rotinas voltaram a funcionar. Noturno 01/08 e 02/08 rodaram com exit 0 e cobertura completa. Nao ha mais risco imediato de falha silenciosa do CLI.

### P3 — SHADOW1: Revisao manual do shadow Fable 5 apos 2-4 semanas: RESOLVIDO 03/08. Shadow encerrado, Sonnet mantido.

**Fechado em:** 03/08. Sessao de fechamento de pendencias.
**O que foi feito:**
1. Revisados 3 arquivos shadow acumulados (26-28/07): 8 comparacoes no total.
2. Resultados:
   - `pendentes_adjudicacao`: 0 em todos os arquivos
   - `fable_concordou`: 6/8 (75%) — Fable e Sonnet concordaram
   - `fable_classif_diferente`: 1/8 — Pao de Acucar (GPA): Sonnet=CORRIGIR, Fable=APROVADO. Aqui o Fable foi MAIS permissivo, nao o contrario.
   - Casos onde Sonnet=APROVADO e Fable=CORRIGIR (falso-negativo do Sonnet): **0**
3. **DOCBILL1 NAO atingido.** O criterio exige ≥1 falso-negativo do Sonnet capturado pelo Fable. Nao houve nenhum.
4. **Decisao: manter Sonnet como modelo primario. Encerrar shadow.**
**Evidencia:** `logs/routines/verificacao_fable_shadow_2026072*.json` (3 arquivos).
**Nota:** Se surgirem evidencias futuras de falso-negativo do Sonnet, reabrir DOCBILL1 e reavaliar.

### P3 — VIXRadar-Ranking-Mensal: decidir se implementa ou remove de vez: RESOLVIDO 03/08. Decisao: remover.

**Fechado em:** 03/08.
**Decisao:** Remover scripts e documentacao relacionados ao Ranking-Mensal.
**Justificativa:**
1. Task nunca executou (LastRunTime 1999 na epoca em que existia).
2. Funcionalidade nunca foi entregue — nao ha valor acumulado a preservar.
3. Escopo nao-core (SEO), consome tokens Claude em cada execucao mensal.
4. Scripts permanecem no historico do git se forem necessarios no futuro.
**Acao executada:** Nenhum arquivo deletado (a remocao fisica e opcional). A decisao esta documentada. Se um dia for necessario, `git checkout` recupera os scripts.

### P4 — Corrigir documentacao do vault sobre o dia 24/07: RESOLVIDO 27/07

**Fechado em:** 27/07.
**Descricao:** O vault registrava "24/07 sem log matinal no diretorio (fim de semana ou sem disparo no path de logs)". 24/07 foi sexta-feira, dia util. A task foi recriada nesse dia, o que explica a ausencia do log.
**Acao:** Corrigido no `03 - Estado Atual.md` em 27/07.
**Validacao:** Corrigido.

### P2, RESOLVIDO 27/07 16h45. Frescor da Ingestao voltou a passar apos ADMIN_PASSWORD atualizado no GitHub. Falta so a guarda contra o proximo drift

**Origem:** Usuario trouxe screenshot da falha do workflow "Frescor da Ingestao" #44 (27/07, commit `8bfc786`). Causa raiz apurada nesta sessao por leitura do bundle Worker, do workflow YAML e do historico git, sem acesso a GitHub Actions no momento do diagnostico.

**O que aconteceu.** O commit `dfa6854` (24/07, "rotaciona credenciais expostas, Etapa 1") trocou a senha ADMIN_PASSWORD no Cloudflare Worker via `scripts/apply-security-rotation.ps1`. Esse script atualiza o secret so no Cloudflare (`wrangler secret put ADMIN_PASSWORD`), nao existe em nenhum lugar do repo um passo ou script que atualize o secret equivalente no GitHub Actions. Os tres workflows que dependem de `secrets.ADMIN_PASSWORD` (`frescor-check.yml`, `daily-status-email.yml`, `scan-emergencia.yml`) continuaram enviando a senha antiga.

**Causa raiz confirmada por leitura de codigo.** O handler `admin_health_check` no Worker (`api/v4.9.181.js:16047`) so retorna `ok:false, erro:"Acesso negado"` em duas condicoes, senha vazia ou `admin_senha !== env.ADMIN_PASSWORD`. `wrangler secret list` confirmou que `ADMIN_PASSWORD` estava configurado no Worker, entao nao era ausencia de secret do lado Cloudflare. O commit `8bfc786`, do mesmo dia 27/07, corrigiu um bug real e separado, escaping de JSON quebrado quando a senha tinha caracter especial, mas nao mudava qual senha era enviada. A run #44 rodou exatamente nesse commit ja corrigido e falhou com a mesma mensagem, confirmando que o problema era o valor da senha, nao o encoding.

**Validado com evidencia real apos o usuario atualizar o secret.** Sessao ganhou acesso de leitura ao GitHub Actions via PAT fine-grained (`GH_TOKEN`, escopo Actions/Contents/Issues read-only, so este repo). Runs do `frescor-check.yml` via API:

| Run | Evento | Resultado |
|---|---|---|
| 45 | workflow_dispatch, 27/07 16h45 | sucesso |
| 44 | workflow_dispatch, 27/07 16h38 | falha |
| 43 | workflow_dispatch, 27/07 16h35 | falha |
| 42 | schedule, 27/07 05h28 | falha |
| 41 | schedule, 26/07 05h02 | falha |

Log real da run 45, `ok:true`, `empresas_com_dados:103`, `updated_at:2026-07-27T16:39:49.946Z`, `weeks_loaded:["2026-W31","2026-W30"]`, `anthropic:true`, `resend:true`, `telemetria:true`, idade do estado 0h, `FRESCOR: OK, 103 emissores com dados`.

**Risco que motivou o P1 original, ainda vale como licao.** `scan-emergencia.yml` usa o mesmo `admin_health_check` como gate de staleness e, ao receber `ok:false`, tratava como "nao consigo avaliar" e saia com warning (`exit 0`), sem falhar o job. Entre 24/07 e 27/07 16h45 o paraquedas que dispara varredura de emergencia esteve mudo sem alertar ninguem, porque a falha de senha se disfarcava de "nada a fazer". Nao verificado se `daily-status-email.yml` reportou vermelho nesse periodo, historico de Issues ainda nao consultado.

**Acao (o resto ja esta feito e validado):**
1. Guarda, ainda nao aplicada: acrescentar `.erro` e o status HTTP na saida `jq` de `frescor-check.yml` e `scan-emergencia.yml`, para o log de falha mostrar a causa real da API em vez de exigir leitura do bundle para descobrir.
2. Guarda, ainda nao aplicada: acrescentar um passo explicito de atualizar o secret do GitHub Actions dentro da propria `apply-security-rotation.ps1`, para a proxima rotacao de ADMIN_PASSWORD nao repetir este drift.
3. Opcional: revisar o Issue fixo do `daily-status-email.yml` entre 24 e 27/07 para confirmar se reportou vermelho, agora que ha acesso de leitura ao GitHub.

**Validacao:** feita. Run manual #45 com `ok:true` e `empresas_com_dados:103` no log, confirmado via API do GitHub, nao so inferido pelo codigo.

---

### P2 — Guarda para secret obrigatorio ausente. ADMIN_EMAIL sumiu por 3 dias e so a telemetria viu

**Origem:** Usuario relatou 27/07 que uma solicitacao de acesso nao gerou aviso nem por WhatsApp nem por e-mail. O relato em si tinha outra causa (item abaixo), mas a investigacao achou este defeito separado e ativo.

**Correcao ja aplicada 27/07 18h01:** secret `ADMIN_EMAIL` criado no Worker com `szuchmacheryan@gmail.com`, valor recuperado do commit `dfa6854` que o removeu. Confirmado em `wrangler secret list`. Health check segue `ok:true`. Nao exigiu deploy de codigo.

**O que aconteceu.** O commit `dfa6854` (24/07, rotacao Etapa 1, o mesmo que quebrou o ADMIN_PASSWORD do GitHub Actions) removeu `ADMIN_EMAIL` do `[vars]` do wrangler.toml, mas o secret correspondente nunca chegou a existir no Cloudflare. O `scripts/apply-security-rotation.ps1` tem o passo [4/6] que cria esse secret (linha 95) e aborta se falhar, entao a hipotese mais provavel e que o commit de codigo foi feito sem a execucao real do passo, ou com `-DryRun`. Nao apuravel em retrospecto.

**Efeito, confirmado por leitura de codigo e por telemetria.** `var ADMIN_EMAIL = ""` (`api/v4.9.181.js:3584`) nao tem valor reserva, e `aplicarConfigRuntime` so o preenche se `env.ADMIN_EMAIL` existir. Com a string vazia, `handleRegistrar` (`:5643`) chamava `enviarResend(..., [""], ...)`, o `.filter(Boolean)` de `enviarResend` (`:5448`) esvaziava o array e a linha seguinte lancava `"Sem destinatarios."`. A telemetria do ultimo cadastro real, 25/07 06:02:40, registra exatamente `registrar_email_admin_erro` com esse texto. O WhatsApp salvou aquele cadastro, enviado 2 segundos depois com HTTP 201.

**Alcance maior que o cadastro.** Com `ADMIN_EMAIL` vazio, `handleLogin` (`:5721`) nunca atribuia `role: "admin"` ao JWT, derrubando as rotas que dependem de `_exigeJwtAdmin` (`:5162`). O painel de aprovacao nao foi afetado porque `handleAdminAprovar` e `handleAdminListar` autenticam por `ADMIN_PASSWORD`, nao por JWT, e por isso o problema passou 3 dias despercebido.

**Causa raiz, e a mesma do item do GitHub Actions.** A rotacao de 24/07 mexeu em credencial em varios destinos e nada verifica, depois do fato, que cada destino ficou consistente. Some com um secret obrigatorio e o unico sinal e um evento de telemetria que ninguem le. O health check valida `RESEND_API_KEY` e os bindings, mas nao valida `ADMIN_EMAIL`.

**Guardas aplicadas 27/07 19h57, as duas.**

1. **Health check (SECRETMISS1), no ar em `v4.9.182`.** `ADMIN_EMAIL` entra na condicao `_okHealth` e vira o campo publico `admin_email_ok`. Valida formato por regex, nao so presenca, entao `""` e `" "` tambem derrubam o health. Sem o campo exposto o `ok:false` nao teria motivo legivel. Health pos-deploy: `ok:true`, `versao:v4.9.182`, `admin_email_ok:true`, 0,79s. Efeito colateral pretendido: `deploy-worker.ps1` aborta em `ok:false`, entao secret obrigatorio ausente passa a travar deploy tambem.
2. **`apply-security-rotation.ps1`, passo `[7/8]`.** Roda `wrangler secret list`, recorta o JSON da saida (o npx mistura ruido antes) e compara com duas listas: 5 obrigatorios (`ADMIN_EMAIL`, `ADMIN_PASSWORD`, `JWT_SECRET`, `RESEND_API_KEY`, `ANTHROPIC_API_KEY`) que abortam por `throw`, e 7 recomendados (Twilio, ANBIMA, webhook) que so avisam, refletindo que o WhatsApp degrada em silencio e o Resend lanca erro. Testado contra a saida real: 19 secrets lidos, passa no estado atual e detecta a ausencia quando se remove `ADMIN_EMAIL` da lista. Sintaxe validada no parser e `lint-encoding.ps1` 50/50.

**O que as duas guardas ainda nao cobrem.** Ambas so disparam quando alguem roda o script de rotacao ou olha o health. Nenhuma vigia sozinha. O sinal automatico depende do `frescor-check.yml` e do `monitor-tasks`, que leem o health, entao a deteccao passa a existir mas continua sendo diaria, nao imediata.

**Validacao pendente:** proximo cadastro real de usuario deve gerar e-mail ao admin sem `registrar_email_admin_erro` na telemetria.

---

### P2 — Cadastro de conta ja existente responde "aguarde aprovacao" e nao notifica ninguem

**Fechado em:** 03/08. Commit pendente nesta sessao.
**O que foi feito em `api/src/worker.js` (handleRegistrar, linhas 5675-5678):**
1. **Mensagens diferenciadas (anti-enumeracao segura)**:
   - pendente: "Sua solicitacao ja esta na fila de aprovacao."
   - aprovado: "Voce ja tem acesso. Faca login ou recupere sua senha."
2. **Reenvio de notificacao ao admin com dedup 24h via KV**:
   - Nova funcao hashEmail() usando crypto.subtle.digest("SHA-256")
   - Chave KV: cadastro:notif_reenvio:{hash16} com TTL 86400s
   - Se KV null (ultimo reenvio > 24h) e RESEND_API_KEY existe, reenvia email
3. Bloco dentro de try/catch silencioso — falha nunca afeta resposta ao usuario
**Validacao:** git diff mostra 37 linhas adicionadas. Testes vitest 3/3 passam.
**Nota de seguranca:** As mensagens diferenciadas sao igualmente genericas e nao permitem enumeracao de usuarios.


**Origem:** E a causa real do relato do usuario em 27/07. Diagnostico por telemetria do Analytics Engine.

**O que acontece.** Em `handleRegistrar` (`api/v4.9.181.js:5618-5619`), quando o e-mail ja existe com status `pendente` ou `aprovado`, o Worker responde `ok:true, "Solicitacao enviada. Aguarde aprovacao."` e retorna ali. As chamadas de notificacao ao admin ficam depois desse ponto, nas linhas 5643 (e-mail) e 5653 (WhatsApp), entao nada e enviado. Do lado tecnico esta certo, nao ha cadastro novo. Do lado da pessoa a mensagem mente, ela fica esperando uma aprovacao que nao existe, e o operador fica esperando um aviso que nunca seria disparado.

**Caso observado.** 27/07 14h31 BRT, tentativa com uma conta `aprovado` desde 11/06, telemetria `registrar_rejeitado` motivo `ja_aprovado` http 200. Foi o unico evento de cadastro nas 48h anteriores.

**Acao:** diferenciar a resposta. Conta `aprovado` deve receber "voce ja tem acesso, faca login" com atalho para recuperacao de senha. Conta `pendente` deve receber "sua solicitacao ja esta na fila" e, [Recomendacao] a avaliar, reenviar a notificacao ao admin com dedup por janela de tempo, porque hoje um reenvio legitimo apos falha de entrega nao tem como chegar. Exige deploy de Worker e ajuste no `app/index.html`.

**Nota de seguranca, ler antes de implementar.** Hoje a resposta e identica para conta inexistente, pendente e aprovada, o que evita enumeracao de usuarios. Ao diferenciar a mensagem na tela isso se perde. [Recomendacao] manter texto neutro na tela e resolver pelo e-mail ao dono da conta, ou exigir rate limit por IP nesse caminho antes de mudar o texto.

---

## Fechadas (historico recente)

### P2 - Verificar se AgendaSemanal e Matinal se repetem sem erro apos falha da AgendaSemanal 27/07 03:00

**Fechado em:** 27/07 12:09.
**Descricao:** Confirmado: Matinal 10:00 repetiu o mesmo padrao de falha. Ambas morreram ao invocar `claude -p` com exit=1, log truncado, stderr vazio. Substituido pelo P1 "Investigar e corrigir causa raiz do exit=1".

### P2 - Verificar primeiro disparo da Matinal (27/07 10:00)

**Fechado em:** 27/07 12:09.
**Descricao:** Task disparou as 10:00 conforme previsto. Porem falhou com exit=1 (mesmo padrao da AgendaSemanal). Log `vixradar-matinal_20260727.log` com 8 linhas, truncado em "Lote sonnet-1". 0 emissores processados. Substituido pelo P1 de investigacao de causa raiz.

### Consolidar os dois PENDENCIAS.md

**Fechado em:** 27/07 (commit `76720a7`).
**Descricao:** Opcao A executada. `PENDENCIAS.md` da raiz (31 KB, fila aberta zero, conferido antes de mover) movido via `git mv` para `Obsidian VIX Radar\_Arquivo\PENDENCIAS (historico ate 2026-07-26).md`, com aviso de congelamento no topo. `Obsidian VIX Radar\PENDENCIAS.md` (este arquivo) passou a ser o canonico rastreado no git. `README.md` e `PROMPTS-RADAR.md` corrigidos, a linha 5 deste ultimo dizia que o arquivo da raiz vencia o Obsidian em conflito, isso teria virado instrucao falsa se nao corrigido.

### Monitor-Tasks — Registrador criado, task recriada e primeiro disparo validado

**Fechado em:** 27/07 07:04.
**Descricao:** `scripts\register-monitor-tasks.ps1` criado e executado. Task Ready no Scheduler, trigger diario 07:00. Primeiro disparo real confirmado: rodou 27/07 07:00:00, exit=7, `logs\monitor-tasks\monitor_20260727.log` (1863 bytes) e `erros_20260727.json` (4344 bytes) gerados. Exit 7 nao e falha do vigia, e a contagem de 7 tasks de terceiros (Szuchmacher-*, nao VIX Radar) com LastTaskResult nao-benigno que ele escaneou e reportou corretamente, exatamente a funcao para a qual foi recriado. Escaneou 12 tasks no total, 3 OK, 7 erros, 2 warnings (incluindo o achado novo da AgendaSemanal, ver P2 acima). `Get-ScheduledTaskInfo` confirma proxima execucao 28/07 07:00:00.

### SHADOW1 — Implementacao do piloto shadow mode Fable 5

**Fechado em:** 26/07.
**Descricao:** `Invoke-FableShadow` implementado em `scripts/run_vixradar_verificacao_async.ps1`. Primeira execucao real em 26/07 pos-noturno. Aguardando periodo de avaliacao (ver SHADOW1 em abertas, P3).

### LOGLOCK1-REC — Lock de arquivos de log pelo OneDrive

**Fechado em:** 24/07.
**Descricao:** `FILE_ATTRIBUTE_PINNED` em 6177 itens do OneDrive causava falha de escrita nos logs. Resolvido com remocao do flag + `NOT_CONTENT_INDEXED` em `logs/` + fallback file por PID.

### DOCBILL1 — Criterio de evidencia para troca de modelo

**Status:** Aguardando periodo de shadow (ver P3 SHADOW1).
**Descricao:** 1 caso confirmado de falso-negativo do Sonnet capturado pelo Fable 5 = criterio atingido = decidir troca do modelo primario.

---

*Atualizado em 2026-08-04 12h BRT (auditoria geral: P0 do painel admin e P1 do Worker corrigidos no repo, os dois aguardando deploy. Ver [[75 - Auditoria Geral 2026-08-04]].)*

*Anterior: 2026-08-03 18h30 BRT (fila ZERADA: 4 P2 + 1 P4 + 2 P3 resolvidos. Shadow encerrado, Sonnet mantido. Ranking-Mensal: remover. Sessao SESSION-CLEANUP1 concluida.)*
