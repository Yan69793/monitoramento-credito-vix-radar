---
Status: Vigente (Fase A em andamento, portoes do operador abertos)
Data: 2026-09-04
Data da Versão: 2026-09-04
Origem do Registro: execução do plano aprovado fluffy-prancing-grove (CLAUDE-FREE-MIGRATION Fase A)
Condição de Obsolescência: cai quando a Fase A for declarada concluída no fechamento da sessão (G1-G7); o corpo é registro datado e não se reescreve depois
tags: [vix-radar, claude-free, migracao, provider, scheduler, governanca]
---

# CLAUDE-FREE-MIGRATION Fase A — desacoplar scheduler de Claude + BLOQUEADO_SEM_PROVIDER

Nota de auditoria da execução da Fase A. Complementa o fechamento em
`status/ESTADO.md`, o item em `PENDENCIAS.md`, a marca em
[[10_Estado_Atual_Validado]] e o bloco Fase A em `routines/README.md`.
Referência viva do scheduler: `routines/README.md`. Protocolo no `CLAUDE.md`.

## Governança (registrada 2026-09-04)

- `CLAUDE_SUBSCRIPTION = FREE`
- `CLAUDE_CODE = OPCIONAL / NÃO GARANTIDO` (executor eventual/manual)
- `ANTHROPIC_API_PAYG = NÃO AUTORIZADO` (sem auto-recharge, sem API paga)
- `DEPENDÊNCIA OPERACIONAL DE CLAUDE CODE = PROIBIDA`
- Produção (Worker/Cloudflare) INTOCADA nesta fase, por decisão do operador

Divisão conceitual nova (substitui o regime em que o Claude Code era o executor
agendado): Claude Web Free = consulta manual/advisory; Claude Code = eventual/manual,
nunca requisito operacional; ChatGPT = revisão adversarial (manual); Gemini/outros =
segunda cabeça futura; providers configurados por capability (`VIXRADAR_LLM_PROVIDER`);
scripts, Worker e Task Scheduler = infraestrutura autônoma determinística. O caminho
`Obsidian VIX Radar/operacional/Modelo_de_Atuacao.md` **não existe** no vault; a ausência
foi registrada no `CLAUDE.md` e a divisão conceitual vive aqui e lá.

## Config única de provider

Env User **`VIXRADAR_LLM_PROVIDER`**:

| Valor | Significado | Efeito |
|---|---|---|
| ausente / `none` | sem provider | rotina LLM sai bloqueada: linha `BLOQUEADO_SEM_PROVIDER provider=<v> exit=86 gatilho=<script> motivo=...`, exit **86** |
| `claude-manual` | Claude só manual | exige `-ForceClaude` explícito (operador), fora do scheduler; sem a flag = 86 |
| `deepseek` / `openrouter` | reservado Fase B | ainda BLOQUEADO até o motor migrar (o log avisa) |

Exit 86 canônico (`$VixLlmBloqueadoExit`), não colide com o mapa 0-8 do monitor.
Núcleo: `scripts/lib/vixradar-llm-provider.ps1` (novo, sem dependência, nunca chama
claude). Funções: `Get-VixLlmProvider` (L38), `Test-VixLlmPermiteClaude [-ForceClaude]`
(L52), `Get-VixLlmBloqueadoMsg` (L74), `Stop-VixLlmBloqueado` (L82, `exit $VixLlmBloqueadoExit`
L99). Corte da escalação automática para chave paga: a auth lib exige `claude-manual`
(escalada nunca automática) e, ao entrar no ramo bloqueado/manual, remove as chaves do
processo (`Remove-Item Env:\...`); **registry User do operador nunca é apagado**.

## Inventário A/B/C/D/E (arquivo por arquivo, âncoras medidas em 2026-09-04)

### Classe A — executável LLM → BLOQUEADO (gate de provider)

| Arquivo | Dot-source da lib | Gate (marcador) | Invoca claude |
|---|---|---|---|
| `scripts/run_vixradar_varredura.ps1` (motor) | sim | L476-478 (`Test-VixLlmPermiteClaude`, antes de auth/sonda/exit 2) | `claude -p` dentro de function L318; `Get-Command claude`/exit 2 L583 (depois do gate) |
| `scripts/run_vixradar_matinal_claude.ps1` | (via motor) | delega `& $engine -Rotina matinal ... -ForceClaude:$ForceClaude` L19 ao motor gateado; sem claude direto | — |
| `scripts/run_vixradar_noturno_claude.ps1` | (via motor) | idem L21 (`-Rotina noturno`) | — |
| `scripts/run_vixradar_verificacao_async.ps1` | sim | L325-327 | `claude -p` dentro de function L174; exit 2 L408 (depois do gate) |
| `scripts/run_vixradar_sentinela.ps1` | sim (L372) | L373-377 | `claude` via Start-Process em function (~L488-498); `claude.exe ausente` L382 |
| `scripts/run_vixradar_agenda_semanal.ps1` | sim | L263-265 | `claude -p` dentro de function L115; exit 2 L332 (depois do gate) |
| `scripts/run_claude_routine.ps1` | sim (L141, só p/ `vixradar-*`) | L147-149 (`Test-VixLlmPermiteClaude -ForceClaude:$ForceClaude`); Szuchmacher fora do escopo | `& claude` L398; exit 2 L344 |
| `scripts/retry-vixradar.ps1` | sim | L76-78, `- no-op, nao relanca` (none ⇒ sentinela + exit 0, sem relançar/alerta) | — (relança via rotina base gateada) |
| `scripts/probe-claude-auth.ps1` | sim | L70-72 | `claude -p` real L124 (diagnóstico) |
| `scripts/lib/vixradar-claude-auth.ps1` | sim (L52) | self-gates L65 (`Get-VixAnthropicApiKey`), L115 (`Set-VixClaudeAuthEnv`), L208 (`Initialize-VixClaudeAuth`) | auth/claude headless por dentro, só sob `claude-manual` |
| `scripts/lib/vixradar-ambient-check.ps1` | sim (L12) | per-function L139 (`Test-VixWebSearchProbe`), L353 (`Test-VixHeadlessTools`) | claude nas funções de sonda, só sob provider liberado |

Fora do repo (não versionados, aguardam G2 do operador): CCD store com 4 tasks enabled
(`vixradar-matinal`, `vixradar-noturno`, `vixradar-verificacao-async-11h`,
`vixradar-verificacao-async-1845`) + `SKILL.md` vivos do Claude Desktop; 2 Remote Routines
(verificação remota, frescor remoto 23h). Ambos saem de cena na Fase A.

### Classe B — modelo Anthropic, produção intocada (residual documentado, correção Fase B)

`api/src/worker.js` cascade Anthropic-only (arrays de provedor entrada única com
`chamarClaudeAnalise`, secret `ANTHROPIC_API_KEY`), health `providers_configurados 2/2`,
rota `consulta_empresa`, `sentry_ok`. `.github/workflows/scan-emergencia.yml` (fallback
23:30 UTC) desarmado sem chave. **Não muda na Fase A**; pendência no `PENDENCIAS.md`.

### Classe C — determinística/opcional, sobrevive intacta

Coleta-Volatilidade, Export-Historico, Reconciliacao-CVM (nativas), Health-Watch
(Disabled, decisão 21/08), housekeeping dos crons do Worker, watchdog
(`monitor-tasks.ps1` corre sempre, agora provider-aware), `repor-varredura.ps1` (PS puro),
deploy/build. Não dependem de LLM.

### Classe D — documentação (esta fase)

`CLAUDE.md`, `routines/README.md`, `status/ESTADO.md`, [[10_Estado_Atual_Validado]],
`PENDENCIAS.md` (item datado), esta nota.

### Classe E — falso positivo (não exige gate)

`api/v4.*.js` (builds gerados do bundle), `scripts/run_vixradar_noturno-shadow-deepseek.ps1`
(legado desconectado), probes de health legados citando `claude` só em string.

## Monitor-tasks.ps1 (anti-tempestade + fail-closed)

Dot-source da lib (L34), lê provider no topo (`$LlmProvider` L35, `$LlmBloqueado` L36).
Com provider=none: task LLM com `LastTaskResult=86` ⇒ ok, linha `BLOQUEADO_SEM_PROVIDER
esperado`, não entra em erro/email; resultado ≠ 86 ⇒ **ERRO 9006** (violação do gate /
possível bypass); vigilância de entrega das 5 LLM suprimida com `ROTINA BLOQUEADA
(provider=none)`. Exit 86 novo no mapa (hoje cobre 2-8; L549 descreve exit 2). `9004
ALERTA_AUTH` segue valendo para escalação paga detectada em log.

## Gate anti-regressão

`scripts/check-claude-free.ps1` (PS 5.1-safe, exit real) + `.github/workflows/claude-free.yml`
(push/PR tocando `scripts/**`/`routines/**`, diff-mode) + Gate 8 no `scripts/hooks/pre-commit`
(materializa blobs em staging). Allowlists por relpath: **G** (gate obrigatório, 11
arquivos), **L** (legado morto: `ranking_mensal`, `vixradar-runner-args`), **N** (referência
não-invocante: `monitor-tasks`, `cutover-motor`, `register-all-routines-scheduler`), **K**
(material de chave: auth lib, provider lib, sonda, o próprio checker). Regras R1-R5 (ver
cabeçalho do checker). Invocação dentro de function é segura por construção (o gate roda no
corpo executável antes de qualquer chamada); R2 mede `(última function, gate]` no corpo.
`routines/claude-desktop/**`, Obsidian datado, `api/**` e comentários fora do escopo.

## Scheduler: CCD → Task Scheduler nativo

`scripts/cutover-motor.ps1 -Acao Ativar` (elevação, modo sim disponível; `-Acao Reverter`
atômico): 5 natives Enabled (Matinal 10h, Noturno 18h, Verificacao-Async 11h00+18h45,
Sentinela, AgendaSemanal Dom/Qua 22h), 2 retries Disabled, grava
`logs\monitor-tasks\motor.json = {"motor":"task-scheduler"}`. `register-all-routines-
scheduler.ps1` NÃO reproduz o estado (1 trigger por task, sem retries) e foi ajustado para
registrar as 3 tasks migradas Enabled (ramo `$t.Disabled` virou guarda genérica). Horários
canônicos declarados em `routines/README.md`.

## Portões (estado em 2026-09-04 noite)

| Portão | Dono | Estado |
|---|---|---|
| G0 | agente | código + libs + gate + docs + backups `.bak-2026-09-04` prontos; testes T1-T9 a rodar com saída crua colada |
| G1 | operador | ABERTO — setar `VIXRADAR_LLM_PROVIDER=none` em User |
| G2 | operador | ABERTO — desligar 4 CCD (MCP) + pausar 2 Remote; `nextRunAt` nulo |
| G3 | operador (elevação) | ABERTO — `cutover-motor.ps1 -Acao Ativar` |
| G4 | observação | ABERTO — 1 disparo real de cada rotina bloqueada (log canônico + exit 86) |
| G5 | observação | ABERTO — `monitor-tasks.ps1 -DryRun` + ciclos |
| G6 | agente | ABERTO — commit da migração por caminho explícito + CI verde |
| G7 | verificação | ABERTO — portão final com saída crua colada |

## Riscos e bloqueios

1. Produção intocada = residual Anthropic no Worker segue (health, `consulta_empresa`);
   correção Fase B.
2. Rotinas LLM paradas sem provider ⇒ feed sem análise nova e heartbeats de varredura
   stale; consequência aceita, correção Fase B.
3. `run_claude_routine.ps1` compartilhado: gate só para `vixradar-*` (Szuchmacher fora).
4. Tempestade de alerta evitada por design (86 = esperado); 9006 intencional (fail-closed).
5. Drifts pré-existentes registrados sem corrigir agora: RetryVixNoturno 2 triggers
   (21:30+23:20), CCD `verificacao-async-1845` cron real 19:15 vs nome 18:45, doc diz matinal
   Haiku mas o motor roda Sonnet FULL. Horário canônico declarado em `routines/README.md`.
6. `cutover-motor.ps1` hoje untracked (WIP de sessão paralela): conferir estado real do
   scheduler antes de confiar (medição `Get-ScheduledTask` precede o G3).

## Arquivos da migração (conjunto de commit, por caminho explícito)

11 rotinas/libs gateadas (lista da Classe A) + `scripts/lib/vixradar-llm-provider.ps1`
(novo) + `scripts/check-claude-free.ps1` (novo) + `.github/workflows/claude-free.yml` (novo)
+ `scripts/hooks/pre-commit` (Gate 8) + docs (`CLAUDE.md`, `routines/README.md`,
`status/ESTADO.md`, vault `10_Estado_Atual_Validado.md`, `PENDENCIAS.md`, esta nota).
`cutover-motor.ps1` e `register-all-routines-scheduler.ps1` ajustados na Fase A e incluídos
no conjunto de commit. Backups `.bak-2026-09-04` na árvore. Fora do commit (não fazem parte
da migração): `scripts/lib/vixradar-custo.ps1`, `scripts/skills-verify-tokens.ps1`,
`api/` (intocado), untracked de testes (`test-cutover-motor.ps1` etc.).
