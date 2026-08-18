---
data: 2026-08-18
tipo: sessao
tags: [vix-radar, rotacao, routine-key, envelope, noturno, seguranca]
status: ativo
---

# Rotação da routine_key + recalibração do envelope noturno (2026-08-18)

Sessão de execução, sem deploy de Worker. Health antes e depois: `ok:true` v4.9.195 com todos os sub-checks.

## 1. Rotação da routine_key (P1 fechado)

Rodei `scripts/rotate-routine-key.ps1` de verdade, com o destravamento do keyring previsto em 17/08 (GH_TOKEN limpo, `gh auth status` = keyring OAuth clássico com escopo de secrets).

**O que mudou no caminho:** o portão 2 do script abortava porque `ROUTINE_API_KEY` não existia no GitHub Actions, confirmando a pendência C2 com evidência: o repo tinha UM único secret (`ADMIN_PASSWORD`), o scan-emergencia só ficava verde porque o gate de staleness usa ADMIN_PASSWORD e o passo que consome a chave nunca foi exercitado. Ajustei o portão para tratar criação como caso legítimo (o `gh secret set` cria), com comentário C2.

**Resultado:** chave nova de 43 chars (RNGCryptoServiceProvider) nos 3 destinos, GitHub criado em 05:52:51Z, Worker atualizado via `wrangler secret bulk`, env User atualizado. Validação real: chamada autenticada 200 ok=true total=103, probe com chave inválida 403 (fail-closed). Fp da chave em vigor: `514c6af06e2d`.

**ROTA1 (guarda nova):** os 3 scripts de rotina (matinal, noturno, verificacao-async) liam a chave SÓ do env do processo. Sessão longeva do Claude Desktop com env antigo mandaria a chave morta. Agora `Get-RoutineKey` hidrata do registro User SEMPRE (fonte da verdade), caindo para o env herdado só se o registro estiver vazio. O reinício do Claude Desktop vira recomendação, não requisito.

## 2. Envelope da noturna (P2, recalibrado)

Diagnóstico dos logs de 15/08 e 17/08:

- Fila rápida (Haiku) consumiu 9,4k/emissor em 17/08 e 12,4k/emissor em 15/08, contra 4,5k do desenho. O plano pré-lote achava que 89 emissores cabiam no cap e estourava no meio, desperdiçando a priorização por EWS.
- Vazamento de 142.260 tokens em 17/08: o orquestrador reabriu um subagente via SendMessage só para gravar linhas RESULTADO em arquivo, pagando o replay do transcript inteiro. Foi isso que estourou o hard cap daquele dia.
- Subir o cap de 700k só legalizaria o gasto, não resolve a folga semanal.

Correções aplicadas na skill viva (`~/.claude/scheduled-tasks/vixradar-noturno/SKILL.md`) e espelhadas na cópia versionada (`routines/claude-desktop/noturno/SKILL.md`):

- Estimativa do envelope: 9.500/emissor na rápida (medido), 13.000 na aprofundada (sem medição recente, revalidar).
- Regra dura: NUNCA reabrir subagente após o retorno para gravar arquivo. Se o arquivo de saída voltar ausente, o orquestrador extrai as linhas RESULTADO do retorno e grava ele mesmo com Add-Content.
- Caminho do log corrigido para FREQUENTE (o caminho antigo funciona por junction, é frágil).

Constantes do `run_vixradar_noturno_claude.ps1` atualizadas junto (CALIB1), apesar do script não ser mais o executor.

**Efeito esperado:** o plano passa a deferir antes de estourar, priorizando EWS como desenhado, e o cap deixa de vazar 142k por replay. O consumo total por noite segue alto (~1M+), a medição da próxima noite dirá se o envelope recalibrado comporta os 103 com menos defer.

## 3. Pre-flight corrigido no caminho

O pre-flight pré-rotação acusou P0 em scripts vivos e em cópias de worktrees antigos. Corrigido nos vivos:

- `gen-dashboard.ps1`: BOM UTF-8 adicionado (tinha 3 em dashes sem BOM).
- `api/tools/cf-token-status.ps1`: Stop→Continue + exit 0.
- `scripts/build-worker.ps1`: Stop→Continue + exit 0.
- `scripts/collect_cotacoes.ps1` (Task Scheduler): Stop→Continue.

Abertos para sessão dedicada: ~20 scripts de ferramenta (register-*, deploy-*, lint, check-drift, etc.) ainda usam `$ErrorActionPreference = 'Stop'`, todos interativos, nenhum roda no Task Scheduler. Ver item no PENDENCIAS.

## 4. graphify-out ignorado (P3 da auditoria)

`graphify-out/` adicionado ao .gitignore e desversionado (`git rm -r --cached`). O working tree para de receber ~14 entradas de ruído por execução da ferramenta.

## 5. Drift das skills do Desktop corrigido

A skill viva do noturno (19.369 b) divergia da cópia versionada (15.611 b), e a matinal tinha o caminho antigo do projeto. Ambas sincronizadas com a viva como autoridade. Verificacao-async estava em dia. O `check-desktop-orquestrador-drift.ps1` deveria ter pego isso, vale revisar por que não alertou.

## Validações finais

- Nova chave: HTTP 200, `ok:true total=103` via `action=listar_todos_emissores`.
- Chave inválida: HTTP 403.
- Parse PS 5.1 + BOM OK nos 3 scripts de rotina e nos 4 corrigidos.
- Portão de verificação: `{"ok":true,"versao":"v4.9.195","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","admin_email_ok":true,"sentry_ok":true,"verificador_ok":true}` HTTP 200.

## Para o próximo agente

- A matinal de 18/08 10:00 é o primeiro teste real da chave nova. Se der 403, o problema NÃO é a chave, é algum destino que não recebeu a rotação: conferir `gh secret list`, `wrangler secret list` e o registro User (`[Environment]::GetEnvironmentVariable('ROUTINE_API_KEY','User')`).
- O noturno de 18/08 18:00 é o primeiro teste do envelope recalibrado. Comparar o consumo por emissor da rápida com os 9,5k estimados e conferir se o defer ocorre no plano, não no meio da execução.
- Pendências novas estão no PENDENCIAS.md (bloco 18/08): ANTHROPIC_API_KEY ausente no GitHub Actions, Stop nos scripts de ferramenta, worktrees órfãos de outras ferramentas (Codex/Traycer), check-desktop-orquestrador-drift sem alertar.
