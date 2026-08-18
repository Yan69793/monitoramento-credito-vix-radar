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

## Como verificar

Portão de verificação do CLAUDE.md, antes de declarar tarefa concluída:

```powershell
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```

Esperado: HTTP 200, `ok:true`, `telemetria:true`, `kv:true`, `sentry_ok:true`.
A suíte vitest não roda localmente (Smart App Control bloqueia `workerd.exe`),
só em CI via `worker-tests.yml`, detalhe no CLAUDE.md.

## Onde está o resto

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
