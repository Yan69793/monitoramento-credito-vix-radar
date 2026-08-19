# Estado do projeto — VIX Radar

Última atualização: 2026-08-18 (agente: Claude Code)

Leia este arquivo antes de começar qualquer trabalho, seja qual for o agente.
Atualize a data e os itens abertos ao fechar uma sessão que mudou o estado.
Não duplique conteúdo do CLAUDE.md nem do README.md: aqui fica só o ponto de
partida com os ponteiros.

## O que é

Sistema de inteligência de crédito privado com IA que monitora 103 emissores de
renda fixa no Brasil e classifica eventos por criticidade (CRÍTICO / RELEVANTE /
ECO / RUÍDO). O backend roda 100% em Cloudflare (Worker + KV + DO + Analytics
Engine), mas o cérebro de IA é local: scripts PowerShell agendados no Windows
Task Scheduler chamam o Claude CLI e enviam o resultado ao Worker por POST
autenticado com `routine_key`.

## Estado em 2026-08-18

Segundo o CLAUDE.md (hardened 2026-07-25) e o README: produção em Worker v4.9.198
(confirmado ao vivo em 2026-08-18 via health check) e frontend v202.10 (confirmado
em 2026-08-15), 103 emissores em 13 setores. A migração KV→DO está em andamento
com o KV ainda como fonte da verdade (dual-write com fail-open: um DO quebrado não
derruba o sistema, mas a migração pode parar em silêncio). A rotação da
`routine_key` segue como decisão pendente do usuário. O CLAUDE.md não tem seção
formal de pendências; cada item aberto está resumido em "Itens abertos" abaixo,
com o detalhe no CLAUDE.md.

Hoje, 17/08: criado o retry automático com as tasks Szuchmacher-RetryVixNoturno
(21:30) e Szuchmacher-RetryVixMatinal (13:30), script `scripts/retry-vixradar.ps1`,
e o `monitor-tasks.ps1` ganhou regras de cota e guard. Matinal do dia rodou via
sessão agendada (19/19 emissores, 6 CRITICO), detalhe no vault
`Obsidian VIX Radar/03 - Estado Atual.md`.

Hoje, 18/08: primeira prova ao vivo de dual-execução na fila de verificação
adversarial — a sessão local (Claude Desktop) e a nova Claude Code Routine remote
drenaram a mesma fila `radar:verif_fila` em paralelo, com reserva atômica
confirmada (`protecao_ativa:true`, CONCORVERIF1). Fila de 26 itens foi para 0: a
sessão local processou 6 (4 reaproveitados via `cache_hits` sem busca nova, 2
verificados do zero contra fonte primária CVM — Movida e Aegea Saneamento), a
remote já tinha reservado e processado os outros 20 cerca de 11 minutos antes.
Health final voltou `ok:true` e `verificador_ok:true` (a fila drenada derruba o
`verificador_ok:false` sozinha, sem reinício). Corrigida na mesma sessão a
documentação do contrato de `confirmar_verificacao` (contagens vêm aninhadas em
`resultado{}`, não na raiz) e a regra de reaproveitamento de `cache_hits`, ver
`routines/README.md` e o `SKILL.md` da rotina `vixradar-verificacao-async`.
Nenhuma alteração de código nem deploy nesta sessão, só documentação.

Ainda em 18/08, à noite, a junction NTFS do projeto foi invertida. O caminho físico
canônico passou a ser `E:\Diretorio\Claude\Monitoramento de Credito`, e
`E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito` virou junction legado de
compatibilidade apontando para ele. Antes era o contrário. Rodou por script
transacional com rollback automático, preflight que barra a operação se qualquer
processo tiver working directory dentro da árvore, e baseline capturado em runtime
na mesma execução, sem nenhum valor de referência gravado no código. A validação
fechou com 43890 arquivos, 5787 pastas, delta zero de bytes, HEAD
`a3462c29ef5066a0e92c80932e1ed6f22a238d06` preservado, 12 worktrees íntegros e as 12
tarefas agendadas resolvendo seus scripts. Log em
`%TEMP%\mdc-inversao-20260818-193245.log`.

Duas tentativas anteriores falharam porque sessão do Claude Code viva no diretório
arrasta cerca de trinta processos filhos que herdam o working directory e seguram a
raiz, e é por isso que o preflight passou a existir.

A migração fechou na mesma noite. Das 12 tarefas agendadas que referenciam o projeto,
as 8 que ainda usavam o caminho legado foram reapontadas para o canônico preservando
ação, argumentos, trigger, usuário e privilégio. O `VIXRadar-Health-Watch` só aceitou
a mudança sob execução elevada, por usar logon S4U, e a primeira tentativa sem
elevação abortou e reverteu sozinha. O worktree `quizzical-nightingale-0c534b` foi
normalizado com `git worktree repair` apontando o caminho canônico, então o `.git`
dele, o `gitdir` no repo principal e o `worktree list --porcelain` deixaram de citar
FREQUENTE. A alteração local que esse worktree carregava foi preservada intacta.

O `FREQUENTE\Monitoramento de Credito` continua existindo como junction, mas agora só
por compatibilidade. Nenhuma tarefa, worktree ou metadado do git depende mais dele.

Ainda 18/08, à noite: FASE 2 de governança das rotinas fechada. Achado principal: a
`VIXRadar-AgendaSemanal` estava morta em silêncio desde antes de 10/08 (rodava sem shell,
gravava `FIM: concluido` sem fazer nada, 20 emissores com calendário trimestral vencido em
produção). Corrigida com `scripts/run_vixradar_agenda_semanal.ps1` dedicado, validado com dois
testes ao vivo contra produção (o primeiro interrompido pelo limite de uso da própria conta do
usuário durante a sessão, com falha corretamente reportada em vez de mascarada; o segundo
limpo, exit 0, 8/20 emissores atualizados, confirmado fora do script via nova consulta a
`listar_calendario_stale`). Também corrigidos: `VIXRadar-Ranking-Mensal` descontinuada
formalmente (task não existe no Scheduler há 5+ semanas), segunda Remote Routine não
documentada (`VIX Radar — frescor diário`) trazida para `routines/README.md`, cron da
verificação assíncrona remota corrigido (estava 3h fora do horário prometido desde a criação
no mesmo dia, string do cron local colada sem converter fuso), `ROUTINES-CLOUD.md` de
matinal/noturno marcados órfão/especulativo. Matriz completa das 13 rotinas locais + 2 remotas
+ 5 GitHub Actions + 4 Cloudflare Cron em
`Obsidian VIX Radar/10_Estado_Atual_Validado.md`. Health final: `ok:true kv:true telemetria:true
sentry_ok:true verificador_ok:true`, v4.9.198.

## Como verificar

Portão de verificação do CLAUDE.md, antes de declarar tarefa concluída:

```powershell
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```

Esperado: HTTP 200, `ok:true`, `telemetria:true`, `kv:true`, `sentry_ok:true`.
A suíte vitest não roda localmente (Smart App Control bloqueia `workerd.exe`),
só em CI via `worker-tests.yml`, detalhe no CLAUDE.md.

## Onde está o resto

- Caminho físico canônico do projeto: `E:\Diretorio\Claude\Monitoramento de Credito`. O `FREQUENTE\Monitoramento de Credito` é junction legado de compatibilidade, use o canônico em caminho novo
- `CLAUDE.md` (protocolo operacional, deploy, incidentes) e `README.md`
- `scripts/` (deploy e automações) e `routines/` (`README.md` é a fonte da verdade do agendamento)
- `logs/routines/` (saúde real das rotinas, linha `FIM:` no log)
- `api/` (fonte viva: `api/src/worker.js`; bundles `v4.*.js` são artefatos gerados) e `app/` (frontend, `index.html`)
- Worker `radar-credito-api` em `api.vixradar.com` e Pages `radar-credito` em `vixradar.com`
- Vault `Obsidian VIX Radar/` (memória canônica: `00 - Índice (MOC).md`, `03 - Estado Atual.md`, `PENDENCIAS.md`)
- `producao/` é legado desconectado, nunca deployar

## Itens abertos

- Rotação da `routine_key`, decisão pendente do usuário, detalhe no incidente ROUTINEKEY-PLAIN1 do CLAUDE.md
- Migração KV→DO em andamento com KV ainda como fonte da verdade; auditar `console.warn` atrás de `[DO][dual-write]`/`[DO][read]`, detalhe no CLAUDE.md
- `npm test` só é confiável em CI: `workerd.exe` bloqueado localmente pelo Smart App Control, detalhe no CLAUDE.md
- Deploy de `producao/` é proibido, regrediria o frontend para v30/v40, detalhe no CLAUDE.md
- P2, não bloqueante: `monitor-tasks.ps1` tem diagnóstico específico para `VIXRadar-AgendaSemanal` preso ao exit code antigo (1); o script novo usa 2-8, catch-all genérico ainda pega qualquer falha como erro, só perde a mensagem específica. Detalhe em `routines/README.md`
- P2, não bloqueante: retrofit da linha `ROTINA_RESUMO` padronizada em matinal/noturno/coleta-volatilidade/export-historico/reconciliacao-cvm (hoje só a agenda-semanal, recém-reescrita, tem essa linha). Sessão separada já em andamento (task_12edfa2c)
