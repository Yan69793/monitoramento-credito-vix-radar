---
data: 2026-08-13
tipo: pendencia
tags: [vix-radar, backlog, acoes]
status: ativo
---

# Pendencias — VIX Radar

Fila de acoes abertas. Prioridade: P1 (critico, trava operacao), P2 (alto, degrada cobertura ou seguranca), P3 (medio, melhoria ou conveniencia), P4 (baixo, cosmetico ou futuro).

---

## Abertas (13/08 — pos v4.9.192 / CALVAL-V2)

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
