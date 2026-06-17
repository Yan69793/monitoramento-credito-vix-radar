# Email Relatório e Deliverability — 2026-06-17

Atualizado: 2026-06-17 | Worker **v4.9.121** (CF Version ID `c57bb6f6-bd9c-44aa-863d-cab1961367b1`)

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

## Pendências (acesso externo)

1. **DNS:** endurecer SPF (`-all`), DMARC (`p=quarantine` ou `p=reject` após monitoramento)
2. **Resend:** confirmar domínio verificado e reputação no dashboard
3. **Mailbox:** criar/rotear `unsubscribe@vixradar.com` se mailto for mantido
4. **Inbox test:** inspecionar headers `Authentication-Results` do e-mail de teste pós v4.9.121
5. **Primeiro envio semanal real:** monitorar após cron noturno; se `relatorio:enviado:2026-W25` já existe, próximo disparo só na semana seguinte

---

## Próximo passo recomendado

1. Abrir e-mail de teste (`relatorio_diario_teste`) e capturar headers SPF/DKIM/DMARC
2. Após 1 semana com DMARC reports, subir policy para `p=quarantine`
3. Rodar `vixradar-agenda-semanal` na primeira segunda 03h BRT e validar `calendario:overrides:v1`
4. Confirmar envio semanal automático no cron da próxima semana ISO nova

---

## Arquivos alterados nesta sessão

- `api/v4.9.121.js` (novo)
- `api/wrangler.toml`
- `scheduled-tasks.json` (Claude Code session — `vixradar-agenda-semanal`)
- `Obsidian VIX Radar/17 - Email Relatorio e Deliverability 2026-06-17.md` (este)
- `Obsidian VIX Radar/00 - Índice (MOC).md`
- `Obsidian VIX Radar/03 - Estado de Produção.md`