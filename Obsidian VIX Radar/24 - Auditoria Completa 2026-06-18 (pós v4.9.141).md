# Auditoria Completa — VIX Radar (2026-06-18 pós v4.9.141)

Data: 2026-06-18T14:22Z | Invocação: `/vix-radar-audit` pós-deploy v4.9.141 + rotação `ROUTINE_API_KEY`

Método: [[13 - Metodo de Vistoria Operacional]] | Anterior: [[21 - Auditoria Completa 2026-06-18]]

---

## Síntese executiva

Sistema **saudável**. Produção em **v4.9.141** com fixes CVM (v4.9.140) e hardening de segurança. Auth fail-closed confirmado. GETs operacionais protegidos por JWT admin. `ROUTINE_API_KEY` rotacionada — chave antiga retorna `403`.

**Veredito:** operacional. Pendências P2 documentais e hygiene (não bloqueantes).

---

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker bundle | v4.9.141 (`api/wrangler.toml`) | v4.9.141 | Nenhum ✅ |
| Git `main` | `83dc503` + commit pendente | — | Alinhado pós-commit ✅ |
| Frontend | v201.69 (`app/version.json`) | v201.69 | Nenhum ✅ |
| CI `EXPECTED_WORKER` | v4.9.141 (working tree) | v4.9.141 | Alinhado ✅ |
| Obsidian `03 - Estado` | v4.9.139 citado | v4.9.141 | Atualizar ⚠️ |

**Health público (2026-06-18T14:20:43Z):**
```json
{"ok":true,"versao":"v4.9.141","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}
```

**Frontend:**
```json
{"version":"v201.69","deployed_at":"2026-06-18T13:46:10Z"}
```

---

## Validação em produção

| Teste | Resultado | Evidência |
|---|---|---|
| `GET /` | ✅ v4.9.141 | `versao`, `verificador_ok:true` |
| `POST {}` anônimo | ✅ 401 | `Autenticação necessária` |
| `GET ?action=cobertura_status` | ✅ 401 | `Autenticacao necessaria` |
| `GET ?action=observabilidade` | ✅ 401 | idem |
| `POST resend_webhook` sem assinatura | ✅ 401 | `Assinatura inválida` |
| `listar_todos_emissores` chave antiga | ✅ 403 | `Acesso negado` |
| `listar_todos_emissores` chave nova | ✅ 103 emissores | `total:103` |
| `dados_para_analise` Vibra | ✅ | `cvm_documentos:2`, janela 2026-05-19..2026-06-18 |
| `admin_health_check` | ✅ | `anthropic:true`, `resend:true`, `telemetria:true`, KV ok |
| `tel_test` | ✅ | `binding_presente:true`, `write_result.ok:true` |
| Re-ingest Simpar | ✅ | `n_eventos:5` (sessão anterior) |

---

## Achados

### MÉDIO

- **`admin_mercado` senha em query string** — `handleAdminMercado` ainda aceita `?senha=` no GET. Mitigação parcial em v4.9.141 nos GETs ops; refactor POST pendente v4.9.142.
- **`.claude/settings.local.json`** — histórico de curls com `routine_key` antiga na allowlist Bash (não executável, mas lixo sensível). Limpar manualmente.
- **`scheduled-tasks/backups/`** — prompts com chave antiga; backups não usados em runtime.

### BAIXO

- **`tel_test` na skill de auditoria** — documentação cita `routine_key`; endpoint exige `admin_senha` (corrigir nota 13/skill).
- **`scans/`** — adicionado ao `.gitignore`; arquivos locais atualizados com chave nova.

### Resolvido nesta sessão

- ✅ `ROUTINE_API_KEY` rotacionada via `wrangler secret put`
- ✅ Rotinas `vixradar-{noturno,matinal,agenda-semanal}` atualizadas
- ✅ `replay-falhas.ps1` usa `$env:ROUTINE_API_KEY`
- ✅ Webhook fail-closed / GETs ops JWT / `_teste` exige routine_key em prod

---

## Lacunas

- `admin_verificar_evento` smoke — não executado (custo Haiku); `verificador_ok:true` no health cobre parcialmente.
- Playwright UI admin pós-`sessionStorage` — não executado nesta auditoria.

---

## Próximos passos

| P | Ação |
|---|---|
| P1 | Limpar `settings.local.json` (refs chave antiga) |
| P2 | `admin_mercado` → auth POST sem senha na URL |
| P2 | Atualizar nota 13: `tel_test` usa `admin_senha` |
| P3 | `admin_corrigir_datas_cvm_kv` em lote pós-matinal 18/06 |