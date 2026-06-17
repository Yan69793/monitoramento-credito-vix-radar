# Email Relatório e Deliverability — 2026-06-17

Atualizado: 2026-06-17 02:30Z | Worker produção **v4.9.131** (one-click unsubscribe + footer personalizado)

---

## 1. Causa raiz confirmada

| Área | Causa |
|---|---|
| Destinatários piloto | Secret `RELATORIO_DESTINATARIOS_PILOTO` forçava envio só para 1 e-mail, ignorando usuários `aprovado` com `frequencia=semanal` |
| List-Unsubscribe | Bug em `enviarResend`: header usava literal `"recipient"` em vez do e-mail real do destinatário — unsubscribe inválido em **todos** os envios bulk |
| SPAM (parcial) | DNS autenticado (SPF/DKIM presentes), mas DMARC `p=none` e SPF `~all` (softfail) — enforcement fraco; hipótese de impacto em reputação, não confirmada em inbox |

---

## 2. Evidência objetiva

### Backend mapeado (v4.9.121)

| Peça | Local |
|---|---|
| Cadastro usuários | KV `user:{email}` via `listarUsuarios()` |
| Status ativo | `status === "aprovado"` |
| Prefs e-mail | KV `user_prefs:{email}` — `newsletter`, `alertas`, `frequencia` (default `semanal`) |
| Newsletter diária | `executarNewsletter()` — aprovados, `newsletter !== false` |
| Relatório semanal | `executarRelatorioDiario()` — dedup `relatorio:enviado:{semanaISO}`; cron `30 21 * * *` |
| Resend | `enviarResend()` — From `boletim@vixradar.com`, Reply-To `suporte@vixradar.com` |

### DNS (nslookup 2026-06-17)

- **SPF** `vixradar.com`: `include:send.resend.com` + `~all`
- **DKIM** `resend._domainkey.vixradar.com`: registro presente
- **DMARC** `_dmarc.vixradar.com`: `p=none` (monitoramento)

### Validação produção

- `GET /` → `versao:"v4.9.121"` `providers_configurados:"2/2"` `verificador_ok:true`
- `action=relatorio_dry_run` → **16 destinatários** (16 aprovados, 0 excluídos newsletter, 0 excluídos frequência)
- `action=relatorio_diario_teste` → `enviado:true`, `destinatarios:1` (só admin)
- Secret `RELATORIO_DESTINATARIOS_PILOTO` → **apagado** via `wrangler secret delete`

### Regra de destinatários (pós-fix)

`aprovado` + `newsletter !== false` + `frequencia === "semanal"` (default quando prefs ausentes)

---

## 3. Correção aplicada

| Arquivo | Mudança |
|---|---|
| `api/v4.9.121.js` | `WORKER_VERSAO=v4.9.121`; `List-Unsubscribe` por destinatário no loop; `resolverDestinatariosRelatorio()`; removida lógica `RELATORIO_DESTINATARIOS_PILOTO`; `action=relatorio_dry_run` |
| `api/wrangler.toml` | `main=v4.9.121.js` |
| Produção | Deploy v4.9.121; secret PILOTO deletado |
| Agendador Claude | `vixradar-agenda-semanal` registrada — cron `0 3 * * 1` (segunda 03h BRT, padrão local igual matinal/noturno) |

---

## 4. Validação em produção ou bloqueio explícito

| Item | Status |
|---|---|
| Deploy v4.9.121 | ✅ CF Version ID `c57bb6f6-bd9c-44aa-863d-cab1961367b1` |
| Dry-run 16 destinatários | ✅ sem envio em massa |
| Teste 1 e-mail admin | ✅ `relatorio_diario_teste` |
| Envio semanal em massa | ⏸️ **bloqueado** — aguarda próximo cron `30 21 * * *` em dia de pregão; dedup semana `2026-W25` pode já ter registro se piloto enviou esta semana |
| Diagnóstico SPAM inbox | ⏸️ **bloqueado** — requer inspeção de headers do e-mail recebido (Gmail/Outlook) pós-fix; não automatizado nesta sessão |

---

## Hipóteses SPAM (não confirmadas em inbox)

- List-Unsubscribe inválido (corrigido em v4.9.121)
- `Precedence: bulk` + layout marketing-like
- DMARC `p=none` sem enforcement
- SPF `~all` em vez de `-all`
- `mailto:unsubscribe@vixradar.com` — mailbox pode não existir
- Footer HTML newsletter usa `?unsubscribe=1` genérico (não por e-mail) — pendente alinhar

---

## Incidente 2026-06-16/17 — cron não enviou

**Causa:** secret `EMAIL_ALERTAS_ENABLED` **ausente** em produção. `executarNewsletter` e `executarRelatorioDiario` retornam `motivo:"EMAIL_ALERTAS_ENABLED_ausente"` no cron `30 21 * * *` (18h30 BRT).

**Correção:** `wrangler secret put EMAIL_ALERTAS_ENABLED=1` (2026-06-17). Próximo disparo automático: cron noturno do dia útil seguinte.

**Nota:** `relatorio:enviado:2026-W25` não existia no KV — dedup semanal **não** era o bloqueio.

---

## Deploy v4.9.131 — one-click unsubscribe (2026-06-17 02:30Z)

**Causa raiz SPAM (código):** `List-Unsubscribe-Post: One-Click` declarado mas URL apontava para frontend (`?unsubscribe=email`) sem handler POST; `mailto:unsubscribe@vixradar.com` sem mailbox.

**Correção:** endpoint `GET/POST ?action=email_unsubscribe` no Worker com token HMAC (`gerarTokenEmail` ação `unsubscribe`); `List-Unsubscribe` só HTTPS assinado; footer boletim/briefing usa link personalizado por destinatário (`htmlPara` em `enviarResend`).

**Validação:** `GET /` → `v4.9.131` HTTP 200; endpoint unsubscribe retorna HTML em sig inválido (esperado). CF Version ID `b669402a-6e0c-4b29-a500-e74595bcd3c3`.

**Envio semanal em massa:** agendado **sexta 19/06/2026 18h30 BRT** (`ehFechamentoSemanalB3` + cron `30 21 * * *`). 16 destinatários `frequencia=semanal`.

## Pendências (acesso externo)

1. ~~**DNS:** endurecer SPF (`-all`), DMARC (`p=quarantine`)~~ **APLICADO 2026-06-17** via Global API Key + API Cloudflare. SPF: `-all`. DMARC: `p=quarantine; sp=quarantine`. Propagação TTL ~5min.
2. **Resend:** confirmar domínio verificado e reputação no dashboard
3. **Mailbox:** criar/rotear `unsubscribe@vixradar.com` se mailto for mantido
4. **Inbox test:** inspecionar headers `Authentication-Results` do e-mail de teste pós v4.9.121
5. **Primeiro envio semanal real:** monitorar após cron noturno; se `relatorio:enviado:2026-W25` já existe, próximo disparo só na semana seguinte

---

## Briefing semanal — decisão de produto (2026-06-16)

**Pedido:** e-mail semanal às sextas, após o mercado, com principais notícias da semana + agenda da próxima semana.

### Estado atual (v4.9.128)

| Peça | Comportamento hoje | Gap |
|---|---|---|
| Cron | `30 21 * * *` = 18h30 BRT **todo dia** | Não é só sexta |
| `executarRelatorioDiario` | Roda no cron noturno junto com newsletter | Nome/corpo dizem "diário" |
| Conteúdo eventos | `coletarDestaquesDia` — só `data_evento === hoje` | Não agrega a semana |
| Agenda | Semana ISO corrente (fallback +7d) | Deveria ser **próxima semana** no fechamento |
| Destinatários | `frequencia=semanal` (16 aprovados) | Recebem em **todo dia útil**, não 1×/semana |
| Dedup | `relatorio:enviado:{YYYY-MM-DD}` | Diário — não impede 5 envios/semana |

**Newsletter** (`executarNewsletter`) continua separada: eventos hoje/ontem, todos com `newsletter!=false`.

### Recomendação (melhor prática crédito privado)

**Modelo dois canais:**

1. **Diário (já existe)** — newsletter intraday: alertas CRÍTICO/RELEVANTE do dia anterior + hoje.
2. **Semanal (ajustar)** — briefing de fechamento de semana:

| Campo | Valor recomendado |
|---|---|
| Quando | **Sexta 18h30 BRT** (após fechamento B3 17h + buffer CVM) |
| Alternativa | Último dia útil da semana se sexta for feriado (`ehDiaPregaoB3`) |
| Assunto | `Briefing Semanal VIX Radar — semana {W##} · {data}` |
| Bloco 1 | KPI strip: N críticos / N relevantes / emissores com evento na semana |
| Bloco 2 | Top 8–12 eventos da semana por materialidade (dedup empresa+data+fonte) |
| Bloco 3 | Heatmap setorial (contagem Crít./Rel. por setor — reutilizar lógica Briefing Executivo) |
| Bloco 4 | **Agenda próxima semana** (resultados, vencimentos, assembleias de `agenda:eventos:v1`) |
| CTA | Link dashboard + preferências |
| Dedup | `relatorio:enviado:{semanaISO}` — 1 envio por semana |
| Custo IA | **Zero** — só render KV (mesma filosofia P17 Opção A) |

**Não usar Opus/Claude na geração do e-mail** — dados já estruturados no KV após rotina noturna.

### Implementado v4.9.129 (2026-06-16)

| Item | Status |
|---|---|
| Deploy Worker v4.9.129 | CF Version ID `f47bb65d-cf4d-4433-9153-a3657b22e6c4` |
| Gate `ehFechamentoSemanalB3` | ultimo pregao da semana (sexta ou quinta se sexta feriado) |
| Conteudo | KPI + top 12 semana + heatmap setorial + agenda proxima semana |
| Dedup | `relatorio:enviado:{semanaISO}` TTL 10d |
| Cron | `30 21 * * *` — no-op fora fechamento semanal |
| Newsletter diaria | inalterada |
| Teste admin | `relatorio_diario_teste` OK — `tipo:semanal`, semana 2026-W25 |

---

## Próximo passo recomendado

1. Abrir e-mail de teste (`relatorio_diario_teste`) e capturar headers SPF/DKIM/DMARC
2. Após 1 semana com DMARC reports, subir policy para `p=quarantine`
3. Rodar `vixradar-agenda-semanal` na primeira segunda 03h BRT e validar `calendario:overrides:v1`
4. Confirmar primeiro envio semanal em massa na proxima sexta 18h30 (16 destinatarios)

---

## Sessão 2026-06-17 (tarde) — commit + P15 frontend

| Item | Status |
|---|---|
| Git commit | wrangler v4.9.131, CI EXPECTED_WORKER, Obsidian, frontend v201.54 |
| Git push | `origin/main` alinhado em `462bfa5` (2026-06-17) — `83cf9d6` + `462bfa5` |
| P15 timeline 90d | `app/index.html` — módulo append-only; janela painel emissor 90d; `op=historico_emissor` no `selecionar()` |
| Deploy Pages v201.54 | **OK** 2026-06-17T02:40Z — `version.json` + `CACHE_VERSION` confirmados em produção |
| Lacuna P15 | API `historico_emissor` cobre ~5 semanas KV (regra inviolável); janela UI 90d preenche com `ARQUIVO_PRE` onde existir |

---

## Arquivos alterados nesta sessão

- `api/v4.9.121.js` (novo)
- `api/wrangler.toml`
- `scheduled-tasks.json` (Claude Code session — `vixradar-agenda-semanal`)
- `Obsidian VIX Radar/17 - Email Relatorio e Deliverability 2026-06-17.md` (este)
- `Obsidian VIX Radar/00 - Índice (MOC).md`
- `Obsidian VIX Radar/03 - Estado de Produção.md`
- `app/index.html` + `app/deploy_zip/` (v201.54 P15)