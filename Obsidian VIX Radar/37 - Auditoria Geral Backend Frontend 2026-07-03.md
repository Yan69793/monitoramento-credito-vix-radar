# Auditoria Geral — VIX Radar (2026-07-03)

## Veredito

Saudável. Sem P0. Backend (Worker v4.9.143) e frontend (v201.69) sem drift, checks específicos VIX Radar (schema `sem_eventos`, telemetria, CSS `<strong>`, deploy_zip sync) passam. Único P1 real do dia é operacional (script de rotina, não produto): schema drift no payload de reprocessamento causou 2 lotes mal-diagnosticados como falha de auth (ver [[36 - Auditoria Completa 2026-07-03]]).

## Top riscos

| Sev | Área | Achado | Evidência | Ação |
|---|---|---|---|---|
| P1 | Rotina (scripts) | `cleanup-rotina-artifacts.ps1` apaga log/metrics do dia corrente ao final da execução | log `vixradar-noturno_20260702.log` reduzido a 1 linha pós-execução | Corrigir para nunca deletar `$DateTag` do dia atual |
| P1 | Rotina (scripts) | `noturno-batch-haiku.md`/`noturno-batch-sonnet.md` não especificam schema exato de `receber_analise` (`resultado` deve ser objeto aninhado) | 2 subagentes hoje erraram o schema na 1ª tentativa antes de corrigir lendo `api/v4.9.143.js:15244` | Adicionar exemplo de payload correto nas skills de lote |
| P1 | Rotina (scripts) | `Parse-TokensFromOutput` não lê `--output-format text` do Sonnet — `tokens_total` sempre 0 | `FIM: tokens=0` no log de 02/07 | Corrigir parser; hard cap de 700k está inoperante |
| P2 | Repo | 15+ arquivos/pastas untracked sem relação com o ciclo atual (`FIGMA-INTEGRATION.md`, `app/design/`, `terminals/`, etc.) | `git status --short` | Triagem/commit ou `.gitignore` — fora do escopo desta auditoria |
| P3 | Ops | `Invoke-ClaudeBatch` (`bypassPermissions`) só roda dentro do scheduled task real; bloqueado pelo classificador em execução manual | Confirmado 03/07 ao tentar reprocessar via PS1 | Documentar: reprocessamento manual usa Agent tool, não o PS1 direto |

## Backend

- `receber_analise` (linha 15244) exige `body.resultado` como objeto aninhado — **confirmado no bundle**, é a fonte da verdade que os 2 incidentes de "auth" de ontem ignoravam.
- `sem_eventos:true` protegido por regras explícitas no prompt do modelo (REGRA 2/3, linhas 6552-6553): exige `cobertura_nota` com prova de rodadas executadas antes de aceitar ausência de evento. Não é aceito por omissão — reduz falso `sem_eventos`.
- `RADAR_USAGE_EVENTS` (Analytics Engine) tem alerta explícito se binding ausente (linha 5092) — não falha silenciosa.
- `carregarEstadoMultiSemana` chamado com N variando por endpoint (5, 3, 2 conforme função) — não mapeei 1:1 contra a lista do CLAUDE.md (op=state/ews/briefing_executivo/historico_emissor/comparar → N=5 obrigatório). Registrado como lacuna abaixo.
- Bindings `RADAR_KV`, DO rate limiter, `RADAR_USAGE_EVENTS`, `[observability]` — todos presentes em `wrangler.toml` (confirmado na auditoria operacional [[36 - Auditoria Completa 2026-07-03]]).

## Frontend

- `app/deploy_zip/version.json` == `app/index.html CACHE_VERSION` == produção (`v201.69`) — sem drift, confirmado na auditoria operacional.
- Regra CSS `<strong>` respeitada: nenhuma regra global `strong{}` com `color`, apenas seletores escopados.
- Não testado nesta rodada: estados vazios/erro do dashboard, acessibilidade (teclado/foco/contraste), fluxos admin — fora do escopo do incidente que motivou esta auditoria (rotina noturna).

## Segurança, perf e a11y

- Auth fail-closed confirmado: `POST {}` sem JWT → 401 (não fail-open).
- ROUTINE_KEY não é o problema real dos incidentes de ontem — confirmado hoje com 24/24 submits OK usando a mesma chave após correção de schema.
- Performance/a11y não medidos nesta rodada (não solicitado, escopo era fechar o incidente da rotina).

## Próximos passos

1. **P1** — Corrigir `cleanup-rotina-artifacts.ps1` (não apagar artefatos do dia corrente).
2. **P1** — Adicionar exemplo de payload `receber_analise` correto em `noturno-batch-haiku.md` e `noturno-batch-sonnet.md`.
3. **P1** — Corrigir `Parse-TokensFromOutput`.
4. **P2** — Mapear 1:1 quais endpoints usam `carregarEstadoMultiSemana(env, 5)` vs 3/2 e confirmar contra a regra do CLAUDE.md — pendência de verificação, não achado de bug confirmado.
5. **P3** — Triagem dos untracked no repo (fora do escopo deste incidente).

## Lacunas

- Endpoints admin autenticados (`admin_health_check`, `admin_verificar_evento`) não testados — sem senha solicitada nesta rodada.
- Mapeamento completo de `carregarEstadoMultiSemana(N)` por endpoint não verificado linha a linha.
- Acessibilidade e performance de frontend não medidas.
