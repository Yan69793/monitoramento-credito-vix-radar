---
data: 2026-07-23
tipo: referencia
tags: [vix-radar, infraestrutura, bindings, crons, cors, seguranca, auth]
status: ativo
---

# Infraestrutura — VIX Radar

Referência estática de bindings, crons, CORS, segurança e auth. Para estado atual: [[03 - Estado Atual]]. Para changelog: [[03a - Changelog]].

## Bindings (Worker `radar-credito-api`)

| Binding | Tipo | Status |
|---|---|---|
| RADAR_KV | KV Namespace | `bindings.kv:true` |
| RATE_LIMITER_DO | Durable Object | `bindings.rate_limiter:true` |
| ESTADO_SEMANA_DO | Durable Object | RACEKV1 (serialização FIFO) |
| RADAR_USAGE_EVENTS | Analytics Engine | `bindings.telemetria:true` |
| Providers | Resend + Anthropic | `2/2` configurados |

## Crons Worker

| Cron | BRT | Função |
|---|---|---|
| `30 15 * * 1-5` | 12h30 dias úteis | sync_cvm + recalcular_anomalias + saldo |
| `30 21 * * *` | 18h30 diário | sync_cvm + recalcular_anomalias + sync_anbima + newsletter + saldo + healthcheck |
| `0 1 * * *` | 22h00 diário | Watchdog |
| `0 4 * * *` | 01h00 diário | agendaBuildPersistir (calendário 90 dias → KV) |

## Scheduled Routines (Windows Task Scheduler)

Gatilhos lidos direto do Scheduler (`Get-ScheduledTask ... .Triggers`) em 27/07 13h30. Esta
tabela é derivada da máquina, não de memória de sessão: se divergir, o Scheduler prevalece.

| Task | Gatilho real | Função |
|---|---|---|
| Monitor-Tasks | diário 07h00 | Varre tasks do Scheduler e reporta exit codes |
| VIXRadar-Matinal | seg-sex 10h00 | Top 15 EWS → análise → push ao Worker |
| VIXRadar-Coleta-Volatilidade | diário 17h00 | Coleta cotações de mercado (VOLCOLETA1 pendente) |
| VIXRadar-Noturno | diário 18h00 | 103/103 emissores → análise → push ao Worker |
| VIXRadar-Export-Historico | diário 20h45 | Export de séries para `data/historico/` |
| VIXRadar-AgendaSemanal | seg 22h00 | Atualização de calendário de divulgações |
| VIXRadar-Reconciliacao-CVM | seg 08h00 | Reconciliação CNPJ vs CVM |

Todas registradas com `StartWhenAvailable=true`, `AllowStartIfOnBatteries=true`, `RunLevel=HighestAvailable`.

**Não existem como task (não confundir com "quebradas"):**

| Nome | Situação real |
|---|---|
| VIXRadar-Verificacao-Async | Nunca foi task. Roda inline ao fim da Noturna e da Matinal. `scripts\register-verificacao-async-task.ps1` existe mas não está aplicado |
| VIXRadar-Ranking-Mensal | Removida e não recriada. Funcionalidade nunca entregue. Decisão pendente em `PENDENCIAS.md` |

**Horários que mudaram e por quê:** AgendaSemanal saiu de segunda 03h00 para segunda 22h00 em
27/07 12h50 (commit `b6c8312`), depois da falha das 03h00. Reconciliacao-CVM está em segunda
08h00, não 12h32 como esta nota afirmava desde julho.

## CORS

| Origin | Status |
|---|---|
| `https://vixradar.com` | OK |
| `https://www.vixradar.com` | OK |
| Origem não autorizada | ACAO omitido (correto) |

## Segurança

| Header | Valor |
|---|---|
| Strict-Transport-Security | `max-age=31536000; includeSubDomains; preload` |
| X-Frame-Options | `DENY` |
| X-Content-Type-Options | `nosniff` |
| Referrer-Policy | `strict-origin-when-cross-origin` |
| Permissions-Policy | `geolocation=(), microphone=(), camera=(), payment=()` |
| CSP | Omitida (HTML monolítico, by design) |

## Auth

| Teste | Resultado |
|---|---|
| POST / anônimo | 401 "Autenticação necessária" |
| JWT | PBKDF2, sem `alg:none` |
| Rate limiter | Cobre login + admin (`rl:v2:block:*`) |

## Acesso Admin

| Campo | Valor |
|---|---|
| Email | szuchmacheryan@gmail.com |
| Atalho desktop | Ctrl+Shift+A |
| Atalho mobile | Long-press no logo (700ms) |
| Senha | Ver `memory/credenciais.md` |

## Multi-semana

Todos os endpoints usam `carregarEstadoMultiSemana(env, 5)` (5 semanas de lookback):

`op=state` | `op=ews` | `briefing_executivo` | `historico_emissor` | `comparar`

## Cascade AI

OpenRouter removido desde v4.9.108. Arrays de cascade usam apenas `claude-haiku-analise` como fallback. Análises substantivas via rotinas Claude Code (Matinal/Noturno).

| Contexto | Status |
|---|---|
| `executarVarreduraBatch` | claude-haiku only |
| `executarVarreduraBatchComFila` | claude-haiku only |
| `executarVarreduraMatinal` | claude-haiku only |
| Pulso manual | claude-haiku only |

## Regra CSS

`strong, .text-strong, [class*="strong"] { font-weight: 600; }` — sem `color` (herda do pai). Conforme `CLAUDE.md`.

---

*Última atualização: 2026-07-23. Fonte: health público + `api/wrangler.toml` + Task Scheduler.*
