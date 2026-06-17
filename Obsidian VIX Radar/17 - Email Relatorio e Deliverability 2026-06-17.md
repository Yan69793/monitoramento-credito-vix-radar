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

1. ~~**DNS:** endurecer SPF (`-all`), DMARC (`p=quarantine`)~~ **APLICADO 2026-06-17** via Cloudflare. Propagado em DNS público (Google 8.8.8.8).
2. ~~**Resend:** confirmar domínio verificado~~ **VALIDADO 2026-06-17T21:33Z** — `admin_health_check` → `resend:true`; envios teste com `resend_id`.
3. ~~**Mailbox mailto unsubscribe**~~ **SUPERADO** — v4.9.131+ usa só HTTPS one-click (`?action=email_unsubscribe`); mailto removido do `List-Unsubscribe`.
4. ~~**Inbox test**~~ **EXECUTADO 2026-06-17T21:33Z** — `relatorio_diario_teste` + `newsletter_teste` → `enviado:true` para admin. Conferir caixa de entrada `szuchmacheryan@gmail.com` (não spam).
5. **Primeiro envio semanal real:** cron `30 21 * * *` em sexta de fechamento B3; dry-run **15 destinatários** semanais.

---

## Validação deliverability P2 (2026-06-17T21:33Z)

### DNS (nslookup 8.8.8.8 + script deliverability-checker)

| Registro | Status | Valor |
|---|---|---|
| SPF | ✅ hardfail | `v=spf1 include:_spf.mx.cloudflare.net include:amazonses.com include:send.resend.com -all` |
| DKIM (resend) | ✅ | `resend._domainkey.vixradar.com` presente |
| DMARC | ✅ quarantine | `p=quarantine; sp=quarantine; pct=100; adkim=r; aspf=r` |

Score audit (resend selector): **SPF + DKIM + DMARC válidos**.

### Envio teste (produção v4.9.134)

| Ação | Resultado |
|---|---|
| `relatorio_diario_teste` | `enviado:true`, `destinatarios:1`, `semana:2026-W25`, briefing semanal |
| `newsletter_teste` | `enviado:true`, `resend_id:e681141b-3985-4749-9dc6-1d3e62f94f1d` |
| `relatorio_dry_run` | `total_destinatarios:15` (massa semanal pronta) |
| `email_unsubscribe` sig inválido | HTML "Link expirado" (endpoint vivo) |
| `admin_health_check` | `resend:true`, `anthropic:true`, `telemetria:true` |

### Conferência manual restante (1 min)

Abrir Gmail admin e confirmar:
- Briefing semanal e newsletter teste na **caixa de entrada** (não spam)
- Headers `Authentication-Results`: `spf=pass`, `dkim=pass`, `dmarc=pass`

---

## Checagem envio aos clientes — 2026-06-17 ~18:35 BRT

**Pergunta operacional:** verificar como está o relatório/briefing "diário" para envio aos clientes hoje.

**Conclusão corrigida:** há dois fluxos distintos no Worker v4.9.134:

1. **Newsletter diária** (`executarNewsletter`) — existe, roda no cron noturno e pode ser disparada por `action=newsletter_manual`. Usa eventos de **hoje ou ontem** no KV, filtra apenas `CRITICO` e `RELEVANTE`, deduplica, envia para usuários `aprovado` com `newsletter !== false`, e grava dedup diário `newsletter:enviada:{YYYY-MM-DD}` por 24h.
2. **Briefing/relatório semanal** (`executarRelatorioDiario`, nome legado) — apesar do nome "diário", hoje opera como **Briefing Semanal**. Em dia comum, sem `_teste` ou `_forcar`, retorna `motivo:"nao_eh_fechamento_semanal"`.

**Evidência objetiva:**
- Produção `GET /`: Worker `v4.9.134`, HTTP 200, `ok:true`, `telemetria:true`, `verificador_ok:true`, `providers_configurados:"2/2"`.
- `api/v4.9.134.js`: `executarRelatorioDiario()` valida `RELATORIO_DIARIO_ENABLED`, `EMAIL_ALERTAS_ENABLED` e depois bloqueia envio se `!ehFechamentoSemanalB3(hoje)`.
- `api/v4.9.134.js`: assunto do fluxo é `Briefing Semanal VIX Radar — semana {semanaISO}`.
- `api/wrangler.toml`: cron noturno `30 21 * * *` roda diariamente, mas o relatório fica em no-op fora do fechamento semanal.

**Impacto para hoje, quarta-feira 2026-06-17:**
- A **newsletter diária** pode sair hoje no cron noturno se houver eventos `CRITICO`/`RELEVANTE` com `data_evento` hoje ou ontem, se `EMAIL_ALERTAS_ENABLED` estiver ativo, e se `newsletter:enviada:2026-06-17` ainda não existir.
- O **briefing semanal em massa** não deve sair hoje pelo caminho normal. O primeiro envio em massa esperado permanece **sexta 2026-06-19 às 18h30 BRT**, se for dia de pregão/fechamento B3 e se `RELATORIO_DIARIO_ENABLED=1` + `EMAIL_ALERTAS_ENABLED=1` estiverem ativos.

**Recomendação:** renomear endpoints/actions e variáveis legadas do briefing semanal (`relatorio_diario_teste`, `RELATORIO_DIARIO_ENABLED`, `executarRelatorioDiario`) para nomes semanais em próxima janela de manutenção, preservando aliases temporários para compatibilidade. Também criar `newsletter_dry_run` para saber, antes do cron, quantos eventos e destinatários a newsletter diária teria hoje sem enviar e sem depender de admin manual.

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

## Sessão 2026-06-17 (noite) — redesign Boletim Diário v4.9.135

### Causa

| Área | Causa |
|---|---|
| Visual amador | `montarEmailHTML` herdava estilo marketing (bordas coloridas, numeração 01/02, título genérico) — confundia com briefing semanal |
| Bug preview | Strings `sC`/`sR` misturavam aspas simples/dobras (`">'` fechava string cedo); `return` principal alternava aspas dentro de literal longo — quebrava `new Function()` do preview |
| Drift versão | HTML editado em `v4.9.134.js` com `WORKER_VERSAO=v4.9.135` sem bundle/wrangler alinhados |

### Correção

| Arquivo | Mudança |
|---|---|
| `api/v4.9.135.js` | `montarEmailHTML` redesenhado: header navy/gold, KPIs em tabela, seções Críticos/Relevantes, nota diário vs semanal, copy direta (ghost), `escapeHtml` em dinâmicos, unsubscribe HTTPS preservado |
| `api/wrangler.toml` | `main=v4.9.135.js` |
| `api/tools/preview-boletim-diario.mjs` | Fixture + stub `__name22222222`; aponta v4.9.135 |
| `.gitignore` | `!api/v4.9.135.js` |
| `.github/workflows/canonical-test.yml` | `EXPECTED_WORKER=v4.9.135` |

**Lógica de envio inalterada:** `executarNewsletter`, dedup diário, destinatários, gates, `enviarResend` bulk com `htmlPara` + unsubscribe one-click.

### Evidência

| Item | Resultado |
|---|---|
| Preview local | `app/_preview/boletim-diario.html` + screenshot Playwright `boletim-diario-preview.png` |
| Deploy | CF Version ID `472c9236-54d3-4925-8c6f-1dbd36eb5469` |
| Health | `GET /` → `versao:"v4.9.135"` |
| `newsletter_teste` | `enviado:true`, `resend_id:94c6ccc8-1b98-4f80-ac19-7020a8f55859` |

### Pendências

1. Inspecionar inbox do e-mail de teste (layout Gmail + Outlook real)
2. Commit/push repo (`v4.9.135.js`, wrangler, CI, preview tool, Obsidian)
3. Confirmar que briefing semanal (`montarRelatorioSemanalHTML`) permanece distinto no próximo `relatorio_diario_teste` de sexta

---

## Arquivos alterados nesta sessão

- `api/v4.9.121.js` (novo)
- `api/v4.9.135.js` (novo — redesign boletim diário)
- `api/wrangler.toml`
- `api/tools/preview-boletim-diario.mjs`
- `scheduled-tasks.json` (Claude Code session — `vixradar-agenda-semanal`)
- `Obsidian VIX Radar/17 - Email Relatorio e Deliverability 2026-06-17.md` (este)
- `Obsidian VIX Radar/00 - Índice (MOC).md`
- `Obsidian VIX Radar/03 - Estado de Produção.md`
- `app/index.html` + `app/deploy_zip/` (v201.54 P15)
- `app/_preview/boletim-diario.html`
