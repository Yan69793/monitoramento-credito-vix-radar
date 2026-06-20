# Deploy Readiness v4.9.142

**Data:** 2026-06-18  
**Sessão:** continuação da sessão pós-v4.9.141 (context compaction)

---

## Escopo da versão

`v4.9.142` acumula dois fixups sobre `v4.9.141`:

1. **SEC admin_mercado** — login via POST form-urlencoded (senha fora da URL; fix da regressão v4.9.112/113 que nunca tinha sido corrigida de forma limpa)
2. **Email modo_teste** — KV flag `email:modo_teste = "true"` bloqueia envio para todos os destinatários exceto `ADMIN_EMAIL`; acionado via 3 novas ações admin (`email_modo_teste_ativar/desativar/status`)

---

## Bloqueio de deploy identificado

### Causa raiz
`.gitignore` linha 58: padrão `api/v4.*.js` bloqueia TODOS os bundles v4.x.x.  
Exceções individuais existiam até `!api/v4.9.141.js` (linha 90).  
**`v4.9.142.js` não tinha exceção** → arquivo gitignored.

Wrangler v4 usa descoberta de arquivos com awareness de git. Quando o `main` declarado no `wrangler.toml` está gitignored, ele cai no fallback TypeScript (`worker\src\index.ts`), que também não existe, gerando o erro:
```
[ERROR] The entry-point file at "worker\src\index.ts" was not found.
```

### Evidência
- `.gitignore` linhas 58–90: exceções `!api/v4.9.109.js` … `!api/v4.9.141.js`, nenhuma para 142
- `api/wrangler.toml` linha 49: `main = "v4.9.142.js"` já correto
- Erro wrangler: fallback para `worker\src\index.ts` (padrão TypeScript)

### Correção aplicada
`.gitignore` — linha 91 adicionada:
```
!api/v4.9.141.js
!api/v4.9.142.js
```

---

## Validação admin_mercado (v4.9.142)

| Ponto | Status |
|-------|--------|
| Form login `method="post"` | ✅ confirmado na linha 11297 |
| Handler lê `formData.get("senha")` no POST | ✅ linha 11375-11376 |
| POST só ativado com Content-Type `x-www-form-urlencoded` ou `multipart/form-data` | ✅ linhas 14584-14590 |
| Fallback GET ainda aceita `?senha=X` | ⚠️ P2 residual — não bloqueante |
| `senhaEmbed` na página autenticada | by-design (HTTPS; necessário para ações JS do dashboard) |

---

## Email modo_teste (v4.9.142)

Três caminhos de envio cobertos pelo guard `isModoTesteEmail(env)`:

| Função | Linha aprox. | Comportamento modo_teste |
|--------|-------------|--------------------------|
| `selecionarDestinatariosAlerta` | ~4832 | retorna `[ADMIN_EMAIL]` |
| `executarNewsletter` (destinatários) | ~8599 | `destinatarios = [ADMIN_EMAIL]` |
| `resolverDestinatariosRelatorio` | ~8931 | retorna `{ destinatarios: [ADMIN_EMAIL], modo_teste: true }` |

Ativação via KV: `POST ?action=email_modo_teste_ativar&admin_senha=<ADMIN_PASSWORD>` → `RADAR_KV.put("email:modo_teste", "true", { expirationTtl: 7776000 })`

**Pendente pós-deploy:** ativar modo_teste via ação admin antes do próximo cron noturno.

---

## CLAUDE.md

Arquivo foi podado em sessão anterior (~100 linhas de protocolo removidas). **Revertido via `git checkout CLAUDE.md`** para preservar regras de leitura/escrita obrigatória, campos mínimos e escopo de registro.

---

## Pendências abertas

| Item | Status |
|------|--------|
| Deploy `npx wrangler deploy` (de `api/`, com `CLOUDFLARE_API_TOKEN`) | 🔴 PENDENTE |
| Health check GET / → `ok:true, telemetria:true` | 🔴 PENDENTE (pós-deploy) |
| Ativar `email_modo_teste_ativar` via admin | 🔴 PENDENTE (pós-deploy) |
| Atualizar `EXPECTED_WORKER` no CI para `v4.9.142` | 🔴 PENDENTE |
| POST scans/onco.json + kora.json | 🔴 BLOQUEADO (nova `ROUTINE_API_KEY` necessária) |
| GPA: análise fresca (sem scan JSON) | 🔴 PENDENTE |

---

## Parecer final

**PODE SUBIR** — com ressalvas pós-deploy obrigatórias:
1. Health check via Sprite: `ok:true, telemetria:true, verificador_ok:true`
2. Ativar `email_modo_teste` via ação admin (protege usuários durante testes)
3. Atualizar `CI EXPECTED_WORKER=v4.9.142` em `.github/workflows/canonical-test.yml`

---

## Acompanhamento Codex 2026-06-19 01:15 BRT

**Situação observada:** árvore de trabalho estável após espera de 20s; não houve nova escrita detectada. O processo do Claude aparenta ter encerrado ou ficado ocioso antes do deploy.

**Evidência objetiva:**
- `git status --short` permanece com `api/v4.9.142.js` não rastreado e alterações locais em `.github/workflows/canonical-test.yml`, `.gitignore`, `api/wrangler.toml`, índice/estado Obsidian.
- Health check público em `2026-06-19T04:15:22Z`: `HTTP 200`, `ok:true`, `versao:"v4.9.141"`, `telemetria:true`, `kv:true`, `verificador_ok:true`.

**Impacto:** produção segue em `v4.9.141`; `v4.9.142` permanece como readiness local, não deployado.

**Próximo passo:** deployar `v4.9.142` de `api/`, validar health em produção e ativar `email_modo_teste_ativar` antes dos próximos testes/rotinas de e-mail.

---

## Acompanhamento Codex 2026-06-19 02:01 BRT

**Situação observada:** `claude-code` não aparece mais na lista de processos por ciclos consecutivos. Restam processos do app Claude e Node, mas sem o executável `C:\Users\User\AppData\Roaming\Claude\claude-code\2.1.181\claude.exe`.

**Evidência objetiva:**
- Health check público em `2026-06-19T05:01:50Z`: `HTTP 200`, `ok:true`, `versao:"v4.9.142"`, `telemetria:true`, `kv:true`, `verificador_ok:true`.
- `api/v4.9.142.js` aparece staged (`A`) no Git.
- `api/wrangler.toml` aponta `main = "v4.9.142.js"`.
- Artefato parcial `scripts/azul_payload.json` existe com payload de Azul; não foi encontrada evidência local de fechamento `103/103`.
- `AGENTS.md` e `CLAUDE.md` foram reduzidos substancialmente; `AGENTS.md` virou ponteiro para `CLAUDE.md` e `CLAUDE.md` foi enxugado. Risco: perda de protocolo operacional detalhado se isso não foi decisão deliberada.

**Impacto:** Worker `v4.9.142` está em produção e saudável. A rotina `vixradar-noturno` não tem evidência de conclusão completa nesta observação; tratar como execução parcial/inconclusiva até prova contrária.

**Pendências:**
- Confirmar se houve `103/103 ok:true` por saída da rotina ou por métrica/artefato consolidado.
- Validar `email_modo_teste` pós-deploy, se ainda aplicável.
- Revisar redução de `AGENTS.md`/`CLAUDE.md` antes de commit.
