# Auditoria Geral Backend/Frontend — VIX Radar — 2026-07-07 (noite)

`/vix-radar-general-audit` sob disciplina ysz-superpowers (brainstorm → diagnóstico → execução cirúrgica → verificação real). Modelo Opus 4.8. Origem: pedido do operador de "vistoria completa e profunda para não cometer mais erros, e então corrigir".

## Veredito

Backend sólido (zero P0/P1). Frontend sólido, com 1 P1 real de segurança corrigido. Rotinas de ingestão tinham 1 P0 ativo (ingestão noturna cega) — corrigido e commitado nesta sessão. Deploy dos fixes de frontend pendente de autorização.

## P0 — Rotina noturna e matinal quebradas por dependência de arquivo movida

- **[Fato]** A noturna oficial de 07/07 18:00 (Task nativa `VIXRadar-Noturno`) morreu em 2s. Log `logs/routines/vixradar-noturno_20260707.log`: `18:00:02 ERRO: skill ausente E:\...\scripts\noturno-batch-haiku.md`, `exit 1`. Resultado: **0/103 emissores** processados na janela oficial. A única cobertura de hoje foi o disparo indevido das 10:07 (10/103 com submit, resto deferred por hard-cap de tokens) — não é a rotina oficial.
- **[Causa raiz]** Commit `15647ef` ("v4.9.147 z-scores ANBIMA", 07/07 15:08 BRT) moveu 15 artefatos para `scripts/_archive/` numa limpeza de governança (registrada como P-RH em `PENDENCIAS.md`). Entre eles, `noturno-batch-{haiku,sonnet}.md` e `matinal-batch-{haiku,sonnet}.md`. Mas `run_vixradar_noturno_claude.ps1:15-16` e `run_vixradar_matinal_claude.ps1:14-15` referenciam esses arquivos por caminho fixo em `scripts/`, com guard de existência (`noturno:304-306`, `matinal:222-224`) que aborta a rotina inteira (`exit 1`) **antes** do health check. A limpeza não checou quem consumia os arquivos.
- **[Efeito colateral]** A matinal (10h BRT dias úteis) quebraria igual no próximo dia útil (segunda 08/07).
- **[Correção]** `git mv` dos 4 arquivos de volta a `scripts/` — commit `464f77b`. Conteúdo inalterado; guard passa. Reversível.
- **[Risco residual/Recomendação]** A causa é sistêmica: mover artefato referenciado por path fixo sem validação. `scripts/verify-rotinas-v2.ps1:108-113` testa exatamente essa condição (`Test-Path` dos 4 arquivos) mas **não roda em lugar nenhum** — sem CI, sem hook, sem log de execução. Recomendação: (a) marcar os 4 `*-batch-*.md` como dependência runtime dos PS1 (comentário no `.gitignore`/CLAUDE.md); (b) transformar `verify-rotinas-v2.ps1` em gate pós-mudança em `scripts/**`. O próprio `verify-rotinas-v2.ps1` está desatualizado (checa `v4.9.143`, produção em `v4.9.148`) — precisa atualização antes de virar gate.

## P1 — Janela de corrida XSS em carregarAlertasAnbima (frontend)

- **[Fato]** O patch `<script id="anomalias-patch">` (`app/index.html:3871`) é a versão segura: define `esc()` e renderiza `.anomalia-card-desc` com `esc(a.descricao)`. Mas sobrescrevia `window.carregarAlertasAnbima` dentro de `setTimeout(...,50)`. Durante esses 50ms o binding global apontava para `function carregarAlertasAnbima` original (`app/index.html:3607`), que injeta `descricao`/`acaoSugerida`/`isin`/`tipo` direto em `innerHTML` sem escape.
- **[Vetor]** Clique na aba de alertas nos primeiros 50ms de carregamento usaria o caminho vulnerável. Probabilidade prática baixa (janela curta; dados de anomalia vêm do Worker, não input direto de terceiro arbitrário), mas é dívida de segurança real — não apenas mascarada por ordem de execução. Confirma o que a nota da tarde (44) chamou de "XSS1 resolvido" — a defesa `esc()` existia mas era contornável pela janela de corrida.
- **[Correção]** Removido o wrapper `setTimeout(...,50)` → override imediato. Confirmado seguro: script é clássico (`<script nonce>`, não `type="module"`), então `function carregarAlertasAnbima` é global e o override via `window.` afeta as chamadas; `s`/`e`/`a` já hoisted no mesmo IIFE; parse síncrono sem gap para input entre a def original e o patch. Não tocou nos ~50KB minificados da função original (evita risco de quebra de balanceamento tipo incidente v201.50) — ela fica como dead code inalcançável. `CACHE_VERSION` 71→72. Commit `e258893`.
- **[Verificação]** `node --check` do patch inteiro extraído: válido. `esc(a.descricao)` preservado no card. `app/index.html` == `app/deploy_zip/index.html` (sem drift). Grep confirma janela fechada (0) e override imediato (1).
- **[Lacuna]** Render de card de anomalia com dados reais não validado em navegador (exige sessão autenticada + `op=anomalias`). Validação estática apenas.
- **[Deploy]** PENDENTE de autorização. `version.json` continua v201.71 (verdade de produção); regenerar para v201.72 no deploy, conforme padrão do projeto (commit de correção bumpa só `CACHE_VERSION`; commit de deploy bumpa `version.json`).

## Backend (readonly, bundle ativo v4.9.148.js) — sem achado acionável

Confirmado `wrangler.toml main="v4.9.148.js"` = bundle local = produção (`GET /` → `versao:"v4.9.148"`), sem drift. Verificados sem regressão: secrets sem fallback inseguro; `admin_mercado` GET não autentica mais (regressão histórica não voltou); `zscores_anbima`/`teste` exigem `_exigeJwtAdmin`; CORS sem wildcard; `Math.random` só em sample-rate não sensível; `receber_analise` distingue `sem_eventos` legítimo de inconclusivo (`persistirResultadoCompartilhado:7429-7495`); multi-semana nos 5 endpoints; rate limiter fail-open é logado via `console.warn`.

## Backlog aberto (P2/P3 — não executados nesta sessão por decisão de risco)

Cada um exige editar bundle proibido, refactor com teste real, ou desenho de infra — fazer às pressas contrariaria o objetivo da vistoria. Registrados para priorização:

- **P2 a11y** — 14 overlays/modais no app, só 3 com `role="dialog"`/`aria-modal`; zero focus-trap (grep "trap" = 0). Handlers de Esc presentes em 6 pontos. Adicionar role+trap+foco inicial aos demais; validar por teclado em navegador.
- **P2 divergência de protocolo** — noturno endurecido (mutex global, retry parcial, `--tools WebSearch,WebFetch`, `--strict-mcp-config`, submit central pelo PS1); matinal permaneceu no protocolo antigo (agente faz submit via `Invoke-RestMethod`, `--add-dir` sem restrição de tools, sem mutex, token count por regex frágil em texto livre). Não é bug — o `matinal-batch-*.md` restaurado é coerente com o protocolo do matinal. Decidir se migra ou documenta como intencional.
- **P3 verify-rotinas-v2.ps1** — desatualizado (v4.9.143) e não integrado a nenhum gate. Atualizar para v4.9.148 e rodar pós-mudança em `scripts/**`.
- **P3 CORS** — 2 origens `.pages.dev` (staging/preview) além das 2 de produção em `v4.9.148.js:3536-3541`. Remover se staging não existe mais (requer rebuild+deploy do Worker).
- **P3 dead code** — rate limiter v1 (`checkRateLimit`, KV) sem call sites em `v4.9.148.js:12781-12811`. Remover em próximo bundle.
- **P3 governança** — untracked: `.devin/workflows/vix-radar-session-briefing.md` (ferramenta externa, workflow vazio); `scripts/ipad-noturno.md` (prompt alternativo iPad, 152 linhas, difere de `_archive/ipad-noturno.md`); `.claude/skills/vix-radar-predictive/`. Decidir versionar, ignorar ou descartar.

## Commits da sessão

- `464f77b` fix(rotinas): restaura *-batch-*.md para scripts/ (P0)
- `e258893` fix(frontend): v201.72 - fecha janela XSS em carregarAlertasAnbima (P1)
