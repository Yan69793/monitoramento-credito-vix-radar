# Auditoria Completa — VIX Radar (2026-07-04)

`/vix-radar-audit`, pós-deploy v4.9.146 (verificação assíncrona via assinatura Claude Code).

## Síntese executiva

Produção saudável no momento do fechamento (`ok:true`, `verificador_ok:true`, todos os bindings `true`). Porém a auditoria encontrou e corrigiu um bug real que **derrubou 100% da cobertura noturna de ontem** (0/103 emissores processados) — causa raiz não relacionada ao trabalho da rotina em si, e sim a um health-check mal desenhado. Corrigido nos scripts, ainda não observado em produção (próxima execução real só às 18h BRT hoje).

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker | v4.9.146 (`api/wrangler.toml` → `v4.9.146.js`) | v4.9.146 (Version ID `c14e0fa6-c303-49f2-a78c-ec17811b0158`) | Nenhum |
| Frontend | v201.69 (não alterado hoje) | v201.69 | Nenhum (não retestado nesta rodada — ver Lacunas) |
| `.gitignore` | Corrigido hoje: `!api/v4.9.144.js`/`145`/`146` adicionados | — | Estava causando drift potencial (bundles ativos não commitáveis) |

## Incidentes abertos

1. **RESOLVIDO nesta auditoria (correção aplicada, não ainda observada em produção):** rotina noturna de 03/07 (18h BRT) abortou com `ERRO: health` antes de processar qualquer emissor — `run_vixradar_noturno_claude.ps1:286` bloqueava em `$health.ok -ne $true`, e `ok` estava `false` só por `verificador_ok` degradado (saldo Anthropic), sem relação com o trabalho da rotina (busca web + `receber_analise`). Mesmo padrão em `run_vixradar_matinal_claude.ps1:218`. Corrigido: gate agora só bloqueia por `bindings.kv`/`bindings.telemetria` reais.
2. **Observado, não é bug:** tentativa manual às 14:40 BRT de 03/07 (log `vixradar-noturno_20260703.log:11-34`) bateu no limite de sessão da assinatura Claude Code ("You've hit your session limit · resets 6:30pm") — falhou Raízen/Oi/Oncoclínicas/Kora Saúde. Restrição operacional conhecida da assinatura, não código.
3. **Aberto, não corrigido (fora do escopo desta auditoria):** `scripts/azul_payload.json` — `routine_key` real em texto claro, ainda staged, ainda sem `.gitignore` (achado P1 de 04/07, ver nota 38). Continua exposto ao próximo commit.

## Achados

### CRÍTICO

- **Health-gate acoplado indevidamente** (item 1 acima). Evidência bruta: `logs/routines/vixradar-noturno_20260703.log` linha 35-37 (`INICIO` às 18:00:03, `ERRO: health` às 18:00:04, nada mais no arquivo). Resultado: `audit-routine-staleness.ps1` mostrou `stale_24h:3` (Dasa 28h, Minerva Foods 27.2h, Hapvida 27.2h) no momento da checagem (03:08 BRT). Correção aplicada em `run_vixradar_noturno_claude.ps1` e `run_vixradar_matinal_claude.ps1` — validada sintaticamente (`ParseFile`), **não validada em execução real** (próxima chance: noturno de hoje, 18h BRT).

### ALTO

- `stale_24h: 3` no momento da checagem (Dasa, Minerva Foods, Hapvida) — consequência direta do item CRÍTICO acima. Deve se autocorrigir na próxima execução bem-sucedida da noturna (hoje 18h BRT, com o fix já aplicado).

### MÉDIO

- `compatibility_date` em `api/wrangler.toml` é `2026-06-16` (~18 dias atrás) — não crítico, mas vale atualizar periodicamente por prática recomendada de Workers.
- `confirmar_verificacao` (novo endpoint v4.9.146) engolia erro por item sem log — corrigido com `console.error` estruturado, redeployado (Version ID `c14e0fa6...`).
- Repo segue com working tree sujo (mesma lista de untracked de auditorias anteriores) — nada novo além do já registrado em `PENDENCIAS.md`.

### BAIXO

- `.gitignore` não cobria `v4.9.144/145/146.js` — corrigido.

## Validação em produção

| Teste | Resultado | Evidência |
|---|---|---|
| `GET /` | `ok:true`, `versao:"v4.9.146"`, `verificador_ok:true`, todos bindings `true` | HTTP 200, 0.82s, 2026-07-04T06:17:39Z |
| `POST {}` anônimo | 401 "Autenticação necessária" | Confirmado nesta rodada |
| `node --check api/v4.9.146.js` | Sintaxe OK | Pós-fix de observabilidade |
| `ParseFile` nos 2 PS1 corrigidos | Sintaxe OK | noturno + matinal |
| `audit-routine-staleness.ps1` | `stale_24h:3`, `presos_data:0`, exit 2 | Ver achado ALTO acima |

## Lacunas

- Frontend (`app/index.html`, CORS, CSS `<strong>`) não retestado nesta rodada — coberto extensivamente pela auditoria geral de hoje mais cedo (nota 38), sem mudança de frontend desde então.
- `admin_health_check`/`admin_verificar_evento` não testados nesta rodada (senha não usada; já testado mais cedo hoje na verificação da recarga de saldo).
- Fix do health-gate (matinal/noturno) validado só por sintaxe — comportamento real só se confirma na execução agendada de hoje (noturno 18h BRT). Scheduled task nova `vixradar-verificacao-async` também só dispara pela primeira vez ~10:2x BRT hoje — nenhuma das duas foi observada em execução real ainda.
- `scripts/azul_payload.json` (P1 secret) permanece sem correção — fora do escopo desta rodada de auditoria (documentado, não é achado novo).

## Próximos passos

1. **P0** — Conferir `lastRunAt` de `vixradar-noturno` após hoje 18h BRT: confirmar que processou 103/103 (fix do health-gate funcionou de verdade).
2. **P0** — Conferir `lastRunAt` de `vixradar-verificacao-async` após ~10:2x e ~18:2x BRT hoje (primeira execução real da task nova).
3. **P1** — Ainda pendente: despachar `scripts/azul_payload.json` do staging + `.gitignore`.
4. **P2** — Atualizar `compatibility_date` do Worker numa próxima edição.
