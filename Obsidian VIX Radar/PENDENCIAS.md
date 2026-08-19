---
data: 2026-08-14
tipo: pendencia
tags: [vix-radar, backlog, acoes]
status: ativo
---

# Pendencias — VIX Radar

Fila de acoes abertas. Prioridade: P1 (critico, trava operacao), P2 (alto, degrada cobertura ou seguranca), P3 (medio, melhoria ou conveniencia), P4 (baixo, cosmetico ou futuro).

---

## 18/08 (tarde-noite) — auditoria geral pós-CONCORVERIF1 (detalhe: [[87 - Auditoria Geral 2026-08-18 (tarde-noite, pos-CONCORVERIF1)]])

### P2 — Recheck pré-submit da verificação não cobre reserva expirada por lentidão

`reservar_itens_fila` (CONCORVERIF1, v4.9.197) tem TTL fixo de 20 min sem renovação. O recheck de segurança antes de `confirmar_verificacao` só é obrigatório quando `protecao_ativa` veio `false` (DO indisponível), não quando o lote simplesmente demorou mais que o TTL com `protecao_ativa:true`. Lote cheio (até 20 itens, até 3 buscas web cada, processamento serial) pode passar de 20 min. Correção: tornar o recheck via `listar_fila_verificacao` com `ids` incondicional antes de todo `confirmar_verificacao`, custa 1 HTTP a mais por lote.

### P2 — Export-Histórico de 18/08 sem commit

`chore(data): historico 2026-08-18` não apareceu no git log até 22h57 BRT, ao contrário de 16 e 17/08 (commit por volta de 20h48-20h49 no mesmo dia). Não apurável nesta sessão remota (sem acesso a `logs/routines/` local). Hipótese: sobreposição com a inversão da junction NTFS relatada na mesma noite. Conferir `FIM:` do Export-Histórico de 18/08 na próxima sessão local.

### P3 — Comentário de cabeçalho do wrangler.toml desatualizado

`api/wrangler.toml:2` diz `main = v4.9.195`, real (linha 536) é `v4.9.198.js`. Sem risco de produção (guard de CI lê a diretiva real), só engana leitura humana. Atualizar comentário junto do próximo deploy.

### P2 — Incidente verificador_ok de 18/08 tarde ficou fora do vault até esta auditoria

`canonical-test.yml` falhou 13:04Z e 18:53Z de 18/08 (`verificador_ok:false`, mesma causa em ambas), corrigido por 3 deploys (v4.9.196/197/198) entre 17h26-18h06 BRT do mesmo dia. Nem o incidente nem o fix tinham nota no vault antes desta auditoria (notas 85 e 86 são da manhã, anteriores ao incidente). Fechado por esta própria entrada + nota 87.

---

## 18/08 — execução: rotação da routine_key + envelope + limpeza (detalhe: [[86 - Rotacao routine_key e envelope noturno 2026-08-18]])

### RESOLVIDO 18/08 — P1 rotação da routine_key

Chave rotacionada nos 3 destinos (GitHub Actions criado, Worker, env User). Validação: 200 com a nova, 403 com inválida. Guarda nova ROTA1: os 3 scripts de rotina hidratam a chave do registro User sempre, processo longevo não manda mais chave morta. O secret nunca existiu no GitHub (C2 confirmado com evidência: repo tinha só ADMIN_PASSWORD), portão do script ajustado para criar.

### RESOLVIDO 18/08 — P2 envelope da noturna (recalibração, sem deploy)

Estimativa do envelope recalibrada para o custo medido (9,5k/emissor na rápida) na skill viva e na cópia versionada. Regra dura anti-replay de subagente adicionada (o vazamento de 142k do 17/08). Efeito real será medido no noturno de 18/08.

### RESOLVIDO 18/08 — P3 graphify-out versionado

`graphify-out/` no .gitignore + `git rm -r --cached`. Working tree sem o ruído da ferramenta.

### RESOLVIDO 18/08 — Pre-flight: 4 scripts vivos com P0

gen-dashboard (BOM), cf-token-status e build-worker (Stop→Continue + exit), collect_cotacoes (Stop→Continue, roda no Task Scheduler).

### RESOLVIDO 18/08 — Drift das skills do Desktop

Noturno e matinal sincronizadas da viva para a versionada. Verificacao-async em dia.

### P2 — ANTHROPIC_API_KEY continua ausente no GitHub Actions

O scan-emergencia usa `secrets.ANTHROPIC_API_KEY` no passo que faz a varredura real, e esse secret também não existe no repo. ROUTINE_API_KEY foi criada na rotação, mas o fallback de emergência segue morto de fato: morreria no primeiro fetch de LLM exatamente no dia em que precisasse rodar. Decidir: criar o secret com a chave paga local, ou remover o passo LLM do workflow.

### P3 — ~20 scripts de ferramenta com ErrorActionPreference Stop

register-*, deploy-pages, lint-encoding, check-drift, check-vault-drift, dry-run, verify-rotinas-v2, atualizar_altman_cvm, seed_labels, install-hooks, skills-audit, push-health, criar-token-dns, unificar-cf-token, apply-security-rotation, disable-vixradar-noturno-task, register-coleta/export/monitor/ranking/reconciliacao, run_vixradar_ranking_mensal, fix_task_coleta_volatilidade, skills-verify-tokens. Nenhum roda no Task Scheduler (os que rodam foram corrigidos: collect_cotacoes, matinal, noturno, verificacao). Correção em lote com parse PS 5.1 de cada um, sessão dedicada.

### P4 — Worktrees órfãos de outras ferramentas poluem o pre-flight recursivo

`git worktree list` mostra 1 do Codex (C:\Users\User\.codex\worktrees), 5 do Traycer e 4 do Claude no caminho antigo (E:\Diretorio\Claude\Monitoramento de Credito\.claude\worktrees, que agora é junction para FREQUENTE). Os .ps1 dessas cópias entram no scan recursivo do pre-flight e geram P0 fantasma. Remover os sem mudança (`git worktree remove`) ou excluir paths de worktrees do scan.

### P4 — check-desktop-orquestrador-drift.ps1 não alertou o drift das skills

O drift noturno (19,4k vs 15,6k bytes) e o da matinal estavam lá há dias sem alerta. Rever por que o check não pegou (agendamento? comparação por hash errado?).

### RESOLVIDO nesta sessão de auditoria — Merton DD 0/103 (ver [[85 - Auditoria Geral e Preditiva 2026-08-18]])

Não resolvido na execução, permanece P2 com o plano de correção descrito na nota 85. Listado aqui para não se perder entre os blocos.

---

## 18/08 — auditoria geral + preditiva (readonly, detalhe: [[85 - Auditoria Geral e Preditiva 2026-08-18]])

### P2 — Merton DD nunca roda em producao (0/103 emissores)

`predictive_v1:latest` (run 17/08): `merton_dd` null em todos os emissores, driver `merton` nunca aparece. Causa: `market_cap` vazio no Altman e na volatilidade (nenhuma coleta preenche; o gate do codigo exige `market_cap > 0` de proposito). Codigo do modelo correto, Fase A de dados incompleta. Correcao: coletar market cap (cotacao x n. de acoes) ou declarar Merton em stand-by. Guarda: contador `com_merton` no payload do pipeline.

### P3 — graphify-out versionado sem .gitignore

Cache de tooling gerando 14 entradas de ruido no working tree a cada execucao. Adicionar `graphify-out/` ao .gitignore.

### P3 — email do admin hardcoded no frontend (app/index.html:4079)

Revelacao do item "Painel Admin" no cmdk por comparacao literal com o email. O JWT ja carrega `role:admin`; trocar a comparacao pelo role.

### P3 — divs clicaveis sem role/tabindex no Market Overview

mo-table-row e mo-heatmap-row nao sao alcancaveis por teclado. Adicionar role="button" + tabindex + handler de teclado, ou trocar por `<button>`.

### P3 — card "Sem alertas" sem declaracao de janela no proprio card

O indicador tem janela fixa de 30 dias ao lado do toggle 7D/30D do grafico; o glossario manda declarar. Trocar o sub para "X de Y emissores · 30 dias".

---

## 17/08 — sessão de custo/benefício e limpeza de fila (sem deploy)

### RESOLVIDO 17/08 — P2 express/openai órfãos no package.json (C3)

Zero import ou require de `express`/`openai` em todo o `api/`. Removidos com `npm uninstall`, `api/package.json` fica só com `@sentry/cloudflare` em dependencies. `npm ci` revalidado, árvore com os 3 pacotes esperados. Efeito só na próxima publicação, nada em produção mudou.

### RESOLVIDO 17/08 — P2 ~25 .ps1 sem commit, 12 reprovados no lint

Pendência estava vencida. `lint-encoding.ps1` varreu 63 arquivos, 63 OK, 0 risco, e o working tree não tem `.ps1` modificado. Foi fechado pelo commit `9764a3d` (18 arquivos regravados com BOM) e ficou aberto na fila por falta de reconciliação.

### RESOLVIDO 17/08 — P3 listar_plano_rotina devolveu 19 para top_n=15

Não é bug. `selecionarEmissoresPrioritarios` corta em `topN` e depois o mínimo por setor do v4.9.157 (`api/src/worker.js:8953`) adiciona emissores dos setores sem cobertura, senão setor com EWS perto de zero nunca entra no top-N. Na matinal de 15/08 isso somou 4. Contrato descreve `top_n` como se fosse teto, e ele é piso. Corrigir a redação do contrato, não o código.

### RESOLVIDO 17/08 — FIMRUN21, alerta 9001 falso do monitor desde 13/08

`monitor-tasks.ps1` lia só a última linha `FIM:` do log da rotina. O noturno de 15/08 escreveu duas, run-1 com `FIM: noturno 103/103 processados` e run-2 com `FIM: noturno run-2 11/11 emissores DEFERRED ... Total do dia 103/103 com analise real`. A segunda não casava com nenhum padrão de contador, `submit_ok` caía para -1 e disparava 9001 mesmo com o dia entregue inteiro. Vermelho crônico desde 13/08 escondendo sinal verdadeiro. Fix varre todas as linhas `FIM:` do dia e fica com o maior contador, mais padrão novo para `Total do dia N/M`. Validado contra o log real de 15/08, resultado `submitOk=103`, sem alerta.

### RESOLVIDO 17/08 — Portão de verificação saía verde com o sistema doente

A task do VS Code chamava `curl.exe -s` direto, que sai com código 0 mesmo quando o health responde `ok:false`. Novo `scripts/portao-verificacao.ps1` parseia o JSON e sai com 1 se qualquer flag obrigatória não vier `true`, cobrindo os 4 do CLAUDE.md mais `rate_limiter`, `admin_email_ok` e `verificador_ok`. Achado durante o próprio teste: `kv` e `telemetria` moram dentro de `bindings`, não na raiz, a primeira versão reprovava um health saudável. Portão virou build task padrão, Ctrl+Shift+B. `.vscode/tasks.json` ganhou verificar rotinas local e live, monitor de tasks, lint de encoding e drift do vault, que eram o braço do agendador faltando.

### P2 — Envelope da noturna, agora é a alavanca única de custo

Com plano Max a rotina local é flat, trocar modelo dela economiza zero. Dólar real só aparece quando a assinatura estoura o limite semanal e a execução cai na chave paga `VIXRADAR_ANTHROPIC_API_KEY`. O cap de 700k estourando toda noite (~70% acima do desenho) é o que consome a folga semanal. Recalibrar o envelope ou fixar modelo da fila rápida deixa de ser afinação e vira o item de maior retorno da fila inteira.

### P2 — ROUTINE_API_KEY do scan-emergencia continua não validada

Workflow verde nas 4 últimas noites (última 16/08 23:45), mas o log mostra só a checagem de idade do estado (`Idade do estado: 2h`) e saída pelo caminho no-op. A chave nunca é exercitada, então o verde não prova nada. Falharia exatamente no dia em que o fallback precisasse rodar. Validar por `workflow_dispatch` forçado ou junto da rotação.

---

## Abertas (15/08 — auditoria geral profunda)

Detalhe: [[83 - Auditoria Geral 2026-08-15]]. Plano completo: `C:\Users\User\.claude\plans\graceful-soaring-hopper.md`.

### RESOLVIDO 15/08 — Deploy v4.9.195 + v202.10 (correções locais da auditoria)

Worker v4.9.195 e frontend v202.10 no ar e validados em produção (commits `f4b8780`..`5175a97`). Health verde com todos os sub-checks, providers com perplexity "removido" e nivel normal, drift zerado, CI Worker Tests verde no push. Fecha OPENROUTER-ORFAO1 (alerta falso desde 30/07) e LLMXSS1 em produção.

### P1 — Rotação da routine_key (bloqueio de PAT pode ter caído em 17/08, não testado)

Chave redigida em 15/08 de `~/.claude/scheduled-tasks/gen_workflow.py` + `vixradar-noturno-v2.js` (com backup), mas cópias históricas em backups/transcripts seguem existindo e a chave não foi rotacionada. `rotate-routine-key.ps1` cobre os 3 destinos (Worker secret, GitHub Actions secret, env User da máquina). Bloqueava porque o `GH_TOKEN` ativo era um PAT fine-grained sem permissão de Secrets. Em 17/08, resolvendo um bloqueio parecido no `git push` (ver item abaixo), achamos que existe uma credencial OAuth já autenticada no keyring do Windows com escopo `repo` clássico, que inclui gerenciar secret de repositório, e que `GH_TOKEN` (mesmo vazio) segue tendo prioridade sobre ela. Não tentamos rodar `rotate-routine-key.ps1` ainda com esse keyring ativo, mas é candidato forte a destravar sem precisar mexer em PAT nenhum. Ao concluir, reiniciar o Claude Desktop antes da noturno 18:00 para a sessão absorver o env novo.

### RESOLVIDO 17/08 — P1 push de 3 commits bloqueado por credencial (regressão do incidente já documentado em 13/08)

`git push` reprovava com 403, PAT fine-grained sem escopo Contents. Ajustar a permissão do token pelo GitHub não bastou, e no meio da correção o usuário rodou `[Environment]::SetEnvironmentVariable('GH_TOKEN', ...)` duas vezes com erro, primeiro gravando o placeholder literal `cole-o-token-aqui`, depois esvaziando a variável, e colou o valor completo de um token fine-grained em texto puro no chat ao tentar corrigir. Achado real: a trava nunca foi permissão, `GH_TOKEN`, mesmo quebrado, tinha prioridade sobre uma credencial OAuth já autenticada e guardada no keyring do Windows (escopo `repo`, `read:org`, `gist`, `workflow`), suprimindo ela. Limpar `GH_TOKEN` (`$null` em escopo User) destravou o push na hora, sem gerar token novo. Os 3 commits (`960b56c`, `ed40757`, `2fc9216`) estão em `origin/main`, working tree limpo, `0 0` de diferença.

### P3 — Token fine-grained "Token name" exposto em texto puro no chat

Durante a correção acima, o valor completo desse token (o mesmo que teve a permissão Contents ajustada para Read/write) foi colado no chat pelo usuário. Não está mais em uso, `GH_TOKEN` foi removido e o push passou a usar o keyring, mas o valor ficou exposto no histórico da conversa. Regenerar ou apagar esse token específico por higiene quando for conveniente, sem urgência operacional.

### P2 — monitor-tasks.ps1 não detecta rotina completa sem linha FIM:

Achado na medição de cobertura de 17/08 (ver `03 - Estado Atual.md`, callout 05h10): 08/11 e 08/14 fecharam 103 de 103 emissores sem nunca escrever `FIM:` no log, um caminho de conclusão legítimo que o FIMRUN21 não cobre. Hoje isso cai em "sem linha FIM, execução não chegou ao fim" mesmo com o trabalho completo. Fix recomendado, ainda não implementado: quando não achar `FIM:`, `monitor-tasks.ps1` fazer fallback pra a mesma contagem por nome único de emissor usada na medição manual, antes de declarar 9001. Código puro, sem custo de token.

### P3 — routines/README.md descreve top_n como teto, e ele é piso

Achado junto do item RESOLVIDO do `top_n=15` devolvendo 19 (ver acima). O comportamento está correto, `selecionarEmissoresPrioritarios` garante mínimo por setor depois do corte. A correção pendente é só de redação em `routines/README.md`, ainda não editada.

### P2 — Orçamento da noturna (A1)

Cap de 700k estoura toda noite (~70% acima do desenho). Recalibrar envelope ou fixar modelo da fila rápida. A recuperação mecânica do defer (P1-2) foi RESOLVIDA nesta meta (DEFERREDREC1 com persistência real do flag nos 5 ramos).

### P2 — Validar ROUTINE_API_KEY do scan-emergencia no GitHub (C2)

Chave possivelmente morta desde 03/08; se morta, o fallback de emergência falha exatamente quando deveria rodar. Coberto junto da rotação.

### P2 — express/openai do package.json (C3)

Remover dependências não usadas no próximo ciclo de deploy.

### P3 — listar_plano_rotina devolveu 19 emissores para top_n=15 solicitado (matinal 15/08)

Plano da matinal de 15/08 trouxe `total=19` em vez dos 15 esperados pelo contrato (0 SKIP, 10 LIGHT, 9 FULL, 0 AUDIT). Rotina prosseguiu processando os 19 sem erro. Verificar se `top_n` está sendo respeitado na composição do plano no Worker, ou se a contagem por tier ignora o limite quando não há SKIP suficiente para completar a diferença. Detalhe: [[84 - Rotina Matinal 2026-08-15]].

### RESOLVIDO nesta meta (aguardando deploy): P1 matinal sem alarme, P1 governança do orquestrador, P2 REGDRIFT1, P2 timeouts de cron, P2 falso-verde CI

ROTINAGAP1 no watch-vixradar-health (alerta por rotina faltante com dedup por nome), 7 arquivos do Claude Desktop versionados em `routines/claude-desktop/` + `check-desktop-orquestrador-drift.ps1`, guarda dura nos 2 registradores legados + Disabled reproduzido no register-all, AbortSignal.timeout nos 6 fetches de cron, canonical-test fail-closed no rate_limiter.

---

## Abertas (13/08 — auditoria geral + execução)

### P0 — PARCIALMENTE RESOLVIDO: cascade de IA (AUTHWEEK1). Assinatura no limite semanal, chave paga recarregada

**Estado:** OAuth 429 "weekly limit, resets Aug 15, 8am" segue valendo para a assinatura. Chave paga `VIXRADAR_ANTHROPIC_API_KEY` **recarregada pelo operador 13/08 15h12** e validada (sonda exit 0). Dreno de 13/08 15h16-15h27 rodou por pay-per-token (11 eventos, 9 aprovados, 2 rejeitados, 223k tokens), health voltou a `ok:true`. Rotinas funcionam via chave paga até o reset de 15/08 08h BRT.

**Causa raiz:** três drenos de verificação em 12/08 (~2M tokens) + noturno completo estouraram o limite semanal da assinatura. A pendência de 04/08 ("recarregar crédito da chave paga") ficou 9 dias aberta.

**Guarda proposta:** notificação quando a sonda detectar 429 de limite semanal (a sonda já detecta, falta notificar).

### P1 — RESOLVIDO: secret ADMIN_PASSWORD do GitHub Actions (GHWL1)

**Estado:** gh reautenticado via OAuth (escopos repo/read:org/gist) após autorização do operador no device flow. Secret `ADMIN_PASSWORD` atualizado no GitHub Actions com a credencial recuperada do DPAPI local. Validação: run manual do frescor-check. Guarda nova: `scripts/check-gh-actions-health.ps1` (commit `f82872d`) + aviso reforçado no `apply-security-rotation.ps1`.

### P1 — RESOLVIDO: push bloqueado por credencial

**Estado:** origem era o token fine-grained sem Contents write (403). OAuth novo resolveu. Merge do `cbda7d1` (sessão paralela) feito, conflito do PENDENCIAS resolvido mantendo as duas visões. Push completo após este commit.

### P1 — FECHADO: BOM UTF-8 nos scripts

35 .ps1 varridos, 18 regravados com BOM byte a byte, parse PS 5.1 64/64 OK. Commit `9764a3d`. Pre-flight confirmou 0 EM DASH sem BOM nos scripts vivos.

### P2 — FECHADO e DEPLOYADO: XSS Market Overview (frontend + worker)

Frontend v202.8 no ar (escape nos 4 pontos do módulo v100). Worker **v4.9.193 no ar** com strip de HTML em `titulo`/`empresa` no `sanitizarPayloadRadar`. Deploy validado: `ok=true kv=true telemetria=true sentry_ok=true`, versão viva v4.9.193.

### Solicitações de acesso

1 nova solicitação 13/08 15h12 (WhatsApp admin enviado 1s depois, sem erro de email), já aprovada. KV: 34 usuários, 0 pendentes.

Detalhe completo: [[81 - Auditoria Geral e incidentes 2026-08-13]].

---

## Abertas (13/08 — pos v4.9.192 / CALVAL-V2, sessão paralela)

### Status geral

Reconciliado nesta sessao (checkout estava ~40 commits atras, atualizado via `git pull`). Todo o bloco anterior (04/08 a 11/08, ver "Fechadas — bloco 04-11/08" abaixo) esta **RESOLVIDO**. Rastreamento de pendencias havia migrado informalmente para notas de auditoria avulsas (77, 79, 80) sem consolidacao central; este bloco reconsolida os 6 itens reais em aberto hoje.

### P2 — ~25 scripts `.ps1` de rotina modificados sem commit, 12 reprovados pelo lint-staged

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. Paths FREQUENTE + BOM alterados na sessao de 11/08 — sintaxe PS 6/7 em scripts que rodam sob PS 5.1 e BOM removido. Fora do escopo do CALVAL-V2, precisa sessao dedicada.

### P2 — canonical-test.yml: fix do post-mortem 77 nunca implementado

**Origem:** post-mortem 77 (05/08, verificador_ok). Correcao proposta para o workflow ficou em backlog aberto (item Jarvis), nao entrou no repo.

### P2 — Fila de verificacao >20h no fechamento do deploy CALVAL-V2 (12/08 23:33Z) — validar

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. 5 itens enfileirados 11/08 23:33Z cruzaram o SLA de 20h (VERIFSLA1) as 19:33Z de 12/08, derrubando `verificador_ok` no fechamento do deploy. Backlog pre-existente da fila (teto de token), sem relacao com CALVAL. O dreno async de 13/08 10:20 BRT deveria ter zerado — **nao confirmado em log ainda**. Conferir.

### P3 — CLOUDFLARE_API_TOKEN sem permissao Pages:Edit

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. Deploy de Pages caiu para OAuth do wrangler (aviso do proprio `deploy-pages.ps1`). Adicionar a permissao Cloudflare Pages: Edit ao token.

### P3 — Rotina agenda-semanal rodando 1x/semana, regra pede 2x

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. Regra 9 do CALVAL-V2 exige revalidacao 2x/semana (Dom+Qua) para cumprir plenamente. Aumentar frequencia da task local.

### P3 — postAdmin sem Authorization: Bearer

**Origem:** [[79 - Incidente ADMINRL-FIX1 429 painel admin 2026-08-12]]. Backlog registrado, ainda nao implementado.

---

## Fechadas (14/08 — execução das pendências da auditoria)

Worker v4.9.194 e frontend v202.9 no ar, commits `f8bcf7c`..`08e2557` pushed.

### RESOLVIDO — P0 AUTHWEEK1: guarda de notificação implementada

Novo `action=notificar_rotina` no Worker (auth routine_key, email ao admin via Resend) + `Send-VixRoutineAlert` na lib `vixradar-claude-auth.ps1`, chamado nos 3 pontos de abort por auth (matinal, noturno, verificacao-async) e validado no `Assert-VixLibFunctions`. Probe em producao: 403 com chave invalida, fail-closed confirmado. O reset da assinatura (15/08 08h) segue como evento externo; a partir de agora qualquer estouro de limite semanal notifica o admin na hora.

### RESOLVIDO — P2 canonical-test.yml: fix ja estava implementado

A pendencia estava errada. `canonical-test.yml:58-60` ja le `admin_email_ok`/`sentry_ok`/`verificador_ok` individuais (commits `15feb31` e `870b29f`) e as linhas 111-117 nomeiam o fator que caiu. Nada a implementar, item fechado por evidencia.

### RESOLVIDO — P3 agenda-semanal 2x/semana (CALVAL-V2 regra 9)

Task `VIXRadar-AgendaSemanal` atualizada no Scheduler: de Monday para Sunday+Wednesday 22h00 (DaysOfWeek=9), proximo disparo 16/08. `register-all-routines-scheduler.ps1` atualizado junto para a re-registracao nao reverter.

### RESOLVIDO — P3 postAdmin sem Authorization: Bearer

`app/admin/vr-admin-shared.js` agora usa `authHeaders()` (Bearer quando ha JWT local) + `admin_senha` no body. Deployado em v202.9.

### RESOLVIDO — P3 "Cobertura ANBIMA" terceiro sentido

Termo "Cobertura ANBIMA" adicionado ao `glossario-dominio.md` como termo qualificado proprio (disponibilidade da serie no arquivo de precos diario ANBIMA para um emissor), com a regra de nunca usar "Cobertura" simples para esse sentido.

### RESOLVIDO — P3 disjuntor de custo catch mudo (CUSTOBRAKE1)

`verificarDisjuntorDiario` agora loga `console.error` quando a leitura do KV falha, em vez de engolir. Deployado em v4.9.194.

### RESOLVIDO — P3 card "Sem alertas" sem denominador

Card do Market Overview agora declara "X de Y emissores". Deployado em v202.9.

### RESOLVIDO — P3 diretorios untracked

`Operacoes-Recorrentes/` (Trading View, repo proprio) movido para `FREQUENTE\Operacoes-Recorrentes\`, posicao de irmao dos projetos. `docs/entrevista-ff/` (material Financial Finesse) movido para `FREQUENTE\Emprego (1)\Finance\entrevista-ff\`. Working tree limpo.

---

## Abertas (14/08 — execução das pendências da auditoria)

### P3 — CLOUDFLARE_API_TOKEN sem Pages:Edit

Verificado em 14/08: token ativo mas `pages/projects` devolve Authentication error. A API do Cloudflare nao cria nem edita permissoes de token existente (dashboard-only). Passo manual: em https://dash.cloudflare.com/profile/api-tokens, criar token novo com "Cloudflare Pages: Edit" (zona/account `7ac79fb1030e4e81115ef33c21a9b070`) e gravar como `CLOUDFLARE_API_TOKEN` no registro User. Enquanto isso o deploy-pages segue funcional pelo fallback OAuth do wrangler (usado no deploy de hoje).

---

## Fechadas — bloco 04-11/08 (P0/P1/P2), RESOLVIDO

**Marcado resolvido em:** 13/08. Todos os itens abaixo foram superados por deploys subsequentes (Worker v4.9.186 -> v4.9.192, frontend v201.9x -> v202.7). Ja constavam RESOLVIDO individualmente no corpo original desta nota; consolidados aqui como historico, sem status ativo.

- **P0 — Verificador async quebrado por call sites orfaos (05/08):** corrigido 06/08, `Assert-VixLibFunctions` no ar.
- **P0 — Guarda ambiental bloqueando verificador async (04/08):** corrigido 06/08.
- **P1 — VERIFSLA1/VERIFSLA2, lookback do health 2 -> 7 dias:** deploy v4.9.190, 11/08.
- **P3 — Senha demo rotacionada:** 11/08.
- **P0 — Painel admin morto em producao desde 03/08 (modulos ES truncados):** deploy publicado 09/08 (v202.6), superado por v202.7.
- **P1 — Worker v4.9.187 (VALIDFIX1) aguardando deploy:** publicado, Worker avancou ate v4.9.192.
- **P0 — Credito zerado API Anthropic, rotinas paradas (04/08):** rotinas normalizadas a partir de 06/08, guardas estruturais no ar.
- **P1 — settings.json DeepSeek causando exit=1 no `claude -p` (27/07):** corrigido, guarda de ambiente permanente.
- **P2 — Probe pre-voo `Invoke-ClaudeBatch`:** 02/08.
- **P3 — Chaves ROUTINE_API_KEY mortas:** 03/08.
- **P1 — Matinal reportava sucesso com buscas falhando:** 02/08, 4 guardas aplicadas.
- **P2 — VIXRadar-Reconciliacao-CVM (bug PS 5.1):** 03/08.
- **P3 — VIXRadar-Coleta-Volatilidade:** 02/08.
- **P2 — VIXRadar-Export-Historico (token KV):** 02/08.
- **P2 — Guard em register-all-routines-scheduler.ps1:** 03/08.
- **P2 — monitor-tasks.ps1 inventava causa de falha:** 02/08.
- **P2 — Probe CLI antes da Noturno 18:00:** 02/08.
- **P3 — SHADOW1 (Fable 5):** 03/08, Sonnet mantido, shadow encerrado.
- **P3 — VIXRadar-Ranking-Mensal:** 03/08, decisao: remover.
- **P2 — Frescor da Ingestao / ADMIN_PASSWORD desatualizado no GitHub (27/07):** 27/07 16h45.
- **P2 — ADMIN_EMAIL ausente 3 dias, so telemetria viu:** 27/07 19h57, 2 guardas aplicadas (SECRETMISS1).
- **P2 — Cadastro de conta existente nao notificava admin:** 03/08.

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
**Descricao:** `Invoke-FableShadow` implementado em `scripts/run_vixradar_verificacao_async.ps1`. Primeira execucao real em 26/07 pos-noturno. Encerrado 03/08 (ver bloco acima) — Sonnet mantido.

### LOGLOCK1-REC — Lock de arquivos de log pelo OneDrive

**Fechado em:** 24/07.
**Descricao:** `FILE_ATTRIBUTE_PINNED` em 6177 itens do OneDrive causava falha de escrita nos logs. Resolvido com remocao do flag + `NOT_CONTENT_INDEXED` em `logs/` + fallback file por PID.

### DOCBILL1 — Criterio de evidencia para troca de modelo

**Status:** Encerrado 03/08. Shadow Fable 5 avaliado (8 comparacoes, 0 falso-negativo do Sonnet capturado) — criterio nao atingido, Sonnet mantido como modelo primario.

---

*Atualizado em 2026-08-13 (reconciliacao pos-checkout: bloco 04-11/08 fechado, consolidados 6 itens reais em aberto vindos das notas 77/79/80).*

*Anterior: 2026-08-06 02h45 BRT (incidente 04-06/08 encerrado, fila drenada).*

*Anterior: 2026-08-04 12h BRT (auditoria geral: P0 do painel admin e P1 do Worker corrigidos no repo, os dois aguardando deploy).*

*Anterior: 2026-08-03 18h30 BRT (fila ZERADA: 4 P2 + 1 P4 + 2 P3 resolvidos. Shadow encerrado, Sonnet mantido. Ranking-Mensal: remover. Sessao SESSION-CLEANUP1 concluida.)*
