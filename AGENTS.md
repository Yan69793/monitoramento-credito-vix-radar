# AGENTS.md

Regras permanentes e protocolo operacional: **[CLAUDE.md](./CLAUDE.md)** (fonte única — não duplicar aqui).

- Histórico do protocolo: versionado no git (`git log --oneline -- CLAUDE.md`); snapshot verboso antigo é só local (`docs/archived/CLAUDE-HISTORICO.md`, `docs/archived/` está no .gitignore e não chega em clone novo)
- Roteamento de skills: [.claude/SKILLS-ROUTER.md](./.claude/SKILLS-ROUTER.md)
- Estado vivo: `Obsidian VIX Radar/03 - Estado Atual.md`

## PROJECT REHYDRATION / INÍCIO DE SESSÃO

Antes de qualquer tarefa relevante, e sempre depois de sessão nova ou reset de contexto, reconstrua o estado real do projeto **sem modificar arquivo nenhum**. Ler, medir e relatar não é editar.

1. **Ler o contexto necessário, nunca o repositório inteiro.** Este arquivo, mais os de contexto que existirem, como `CLAUDE.md`, `README.md`, `status/ESTADO.md`, `Obsidian VIX Radar/PENDENCIAS.md`, `Obsidian VIX Radar/03 - Estado Atual.md` e `routines/README.md`. Seguir só as referências que a tarefa exigir, sem varredura ampla.
2. **Medir o Git antes de acreditar em documento.** Branch, HEAD, commits recentes, staged, unstaged, untracked e divergência com o remoto.

   ```powershell
   git fetch --quiet origin
   git log --oneline -5
   git status --short
   git rev-list --left-right --count HEAD...origin/main
   ```

3. **Nomear quatro coisas.** Último marco concluído, trabalho em andamento, pendência real e o próximo passo lógico.
4. **Confrontar com o ambiente quando a tarefa tocar em runtime.** Testes, build, CI/CD, deploy, produção, Task Scheduler, workflows, logs e serviços externos. Neste projeto o gate de produção é o health público, e a saída vai colada na resposta.

   ```powershell
   curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
   ```

5. **Ordem de precedência das fontes de verdade**, do mais forte para o mais fraco. Produção e ambiente real ganham de Git atual, que ganha de testes e logs, que ganham de documentação, que ganha de contexto histórico. Conflito se resolve descendo essa ordem, nunca subindo.
6. **Documento não é prova.** Nunca assumir que `status/ESTADO.md`, `PENDENCIAS.md` ou memória de sessão anterior estão atualizados. Quando o documento divergir do Git ou do ambiente, o Git e o ambiente estão certos, e a divergência é achado a registrar.
7. **Não alterar nada durante a reidratação.** Nem arquivo, nem índice, nem stash, nem branch, nem produção. Se a reidratação revelar que algo precisa mudar, isso é proposta, e proposta espera autorização.
8. **Evidência antes de afirmação.** Estado, versão, commit, pendência e conclusão só se declaram com comando e saída ao lado. Sem evidência, declarar incerteza em vez de palpite.

Saída da reidratação, curta e sempre nestes campos.

```
ESTADO
HEAD
ÚLTIMO MARCO
EM ANDAMENTO
PROBLEMAS
PRÓXIMO PASSO
CAMINHOS-CHAVE
```

Depois de qualquer alteração futura, rodar um Verification Gate com os testes e validações pertinentes e revisar o diff completo antes de declarar PASS. Gate reprovado não se mascara, se reporta.

## O que um agente deve saber antes de tocar em código

- **Dois lados, dois mecanismos.** Cloudflare (`api/` + `app/`) e Task Scheduler local (`scripts/` + `routines/`). Eles se comunicam por POST autenticado com `routine_key` em `body.routine_key` — **não existe header `X-Routine-Key`**. Ler `CLAUDE.md` "Arquitetura híbrida" antes de escrever cliente novo.
- **Fontes vivas são só `api/src/worker.js` e `app/index.html`.** `api/v4.*.js` são bundles gerados (nunca editar). `producao/`, `_historico/`, `archive/`, `vixradar/`, `research/` fora do fluxo; `producao/` tem versão estática desconectada e NUNCA é deployado.
- **Deploy Worker:** `pwsh ./scripts/deploy-worker.ps1 -Version v4.9.NNN` — nunca `wrangler deploy` direto. Ele faz build, aponta `main`, `npm ci`, deploy com `--no-autoconfig`, valida GET / e só então commita. Sem `--no-autoconfig` o Wrangler 4.x detecta outro diretório como projeto.
- **Deploy Pages:** `pwsh ./scripts/deploy-pages.ps1`.
- **Testes:** `cd api && npm ci && npm test`. Teste isolado: `npx vitest run test/health.test.mjs`. `app/` não tem package.json, build nem testes.
- **Pre-commit hook** (Gate 1–9) roda sobre o blob em staging, não o working tree. Instalar com `scripts/install-hooks.ps1`. Emergência: `git commit --no-verify`.

## PowerShell 5.1 — regras de compatibilidade

Os scripts do Task Scheduler rodam no `powershell.exe` 5.1. O hook Gate 1 reprova se não respeitado:

- `.ps1` com caractere não-ASCII precisa de BOM UTF-8 (`EF BB BF`) no primeiro byte. Sem BOM, PowerShell 5.1 interpreta como ANSI e corrompe acentos.
- Nunca usar operadores do PowerShell 7+: sem ternário (`$a ? $b : $c`), sem `??`, sem `?.`.
- `$ErrorActionPreference = 'Continue'`, nunca `'Stop'` (senão o Task Scheduler engole o erro e morre silencioso).
- Variáveis de ambiente: `$env:VAR`, nunca `export`.

## Rotinas agendadas (fonte da verdade: `routines/README.md`)

- Provider único de LLM nas rotinas: env User `VIXRADAR_LLM_PROVIDER`. Ausente/`none` = bloqueado (exit 86, `BLOQUEADO_SEM_PROVIDER`); `openrouter` = ativo (Fase B D1); `claude-manual` = só com `-ForceClaude` manual.
- 5 rotinas LLM no Task Scheduler nativo: Matinal (diário 10h), Noturno (seg-sex 18h, 104 emissores), Verificacao-Async (11h03 e 19h15), Sentinela (:25/:55, 09h25–17h55), AgendaSemanal (Dom e Qua 22h).
- `VIXRadar-Health-Watch` está DESATIVADO (decisão 21/08). `VIXRadar-Ranking-Mensal` é OBSOLETO.
- Mudar horário de rotina exige atualizar `_painelSlaAtivo` no `api/src/worker.js` junto, senão o health passa a cobrar pontualidade de horário inexistente.

## GitHub Actions

- `worker-tests.yml`: suíte vitest em push/PR que toque `api/**`. Inclui job de relogio adiantado (196 dias) para pegar testes frágeis com `Date.now()`.
- `canonical-test.yml`: health GET / a cada 6h. Gate usa o campo `ok` agregado — cai se `verificador_ok`, `sentry_ok` ou `admin_email_ok` ficarem `false`.
- `frescor-check.yml`: diário, reprova por idade do evento mais novo em dias úteis.
- `scan-emergencia.yml`: fallback quando estado principal stale.
- `claude-free.yml`: gate anti-regressão CLAUDE-FREE-MIGRATION.
- `emissores-cadro.yml`: confere os 104 emissores contra `cad_cia_aberta.csv`.

## Antes de declarar tarefa concluída

```powershell
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```
Esperado: HTTP 200, `ok:true`, `telemetria:true`, `kv:true`, `sentry_ok:true`. Cole a saída real na resposta. Nunca declare "funcionando" sem a saída colada.

## Não inventar

- Sem lint configurado no repo, não criar um.
- Não edite `api/v4.*.js` diretamente — é artefato gerado por `scripts/build-worker.ps1`.
- Nunca edite `app/index.html`'s `CACHE_VERSION` à mão; use `pwsh ./scripts/bump-cache-version.ps1 -NewVersion v<N>.<N>`.
- `CLOUDFLARE_API_TOKEN` é variável de ambiente, nunca no repo. Escopo `User`, não `Machine`.
- `ROUTINE_API_KEY` e demais secrets nunca no repo — o pre-commit Gate 3 reprova.