---
data: 2026-07-12
tipo: auditoria
tags: [vix-radar, auditoria, operacional]
status: ativo
---
# Auditoria Completa — VIX Radar (2026-07-12)

**Data:** 2026-07-12 ~15h05 BRT
**Skill:** `/vix-radar-audit` (formato de saída) aplicado ao protocolo de 8 etapas dirigido pelo operador
**Modo:** Escopo dirigido (Worker, frontend, health, providers, EWS/matinal, DNS/e-mail, bug conhecido, registro)
**Escopo:** Produção v4.9.150 + Frontend v201.74

---

## Síntese executiva

**Sistema saudável, sem drift repo/produção.** Worker `radar-credito-api` v4.9.150 e Frontend v201.74 confirmados ao vivo, health `ok:true` com todos os bindings centrais (`kv`, `rate_limiter`, `telemetria`) em `true`, verificador operacional (`verificador_ok:true`). EWS/matinal batem 100% com o especificado. Dois achados novos (ALTO + MÉDIO), nunca antes registrados no vault, e um bloqueio de credencial que impediu 2 das 8 etapas (saldo granular de providers e confirmação ao vivo do `EMAIL_ALERTAS_ENABLED`). Etapa de documentação (8) redirecionada por decisão do operador: os três arquivos citados no pedido original (`DOCUMENTACAO_SISTEMA_ATUAL.docx`, `MANUAL_OPERACIONAL.docx`, `PROTOCOLO_MANUTENCAO.md`) não existem no repositório — registro segue o protocolo real do projeto (este arquivo + nota 03 + índice + `PENDENCIAS.md`).

---

## Versões e drift

| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker `radar-credito-api` | v4.9.150 (`api/wrangler.toml` → `main`) | v4.9.150 (`GET /` → `versao`; `WORKER_VERSAO` confirmado no bundle buscado via `workers_get_worker_code`, linha 3594) | Não |
| Frontend `vixradar.com` | v201.74 (`app/index.html` → `CACHE_VERSION`) | v201.74 (`curl vixradar.com` + `version.json`) | Não |
| `version.json` produção | — | `{"version":"v201.74","deployed_at":"2026-07-07T22:45:43Z"}` | — |

---

## Etapa 8 — resolução da ambiguidade documental

`DOCUMENTACAO_SISTEMA_ATUAL.docx`, `MANUAL_OPERACIONAL.docx` e `PROTOCOLO_MANUTENCAO.md` **não existem** no repositório sob esses nomes (busca recursiva confirmada). Únicos candidatos próximos: dois `.docx` de 2026-04-03 em `vixradar/` — pasta que o próprio `CLAUDE.md` do projeto marca como legada ("não deployar"). Não existe nenhum `PROTOCOLO_MANUTENCAO.md` em lugar nenhum do repo; a "fonte única de instruções do projeto" real e viva é o `CLAUDE.md` da raiz. Decisão do operador (pergunta feita durante o planejamento): **seguir o protocolo real do projeto** — não criar nem tocar nos três arquivos citados; registrar exclusivamente via vault Obsidian (esta nota + nota 03 + índice 00) e `PENDENCIAS.md`.

---

## Achados

### CRÍTICO

Nenhum.

### ALTO

- **ALRT1 — `dispararAlertaCritico` não filtra `prefs.newsletter` (confirmado ao vivo, bug real).** Em `selecionarDestinatariosAlerta` (bundle buscado nesta sessão via `workers_get_worker_code`, linha ~5005), a única exclusão de destinatário é `prefs.alertas === false` (linha 5029). Nunca checa `prefs.newsletter`. Por contraste, o fluxo de newsletter em massa e o de relatório semanal checam `prefs.newsletter === false` corretamente (linhas ~9177 e ~9552 do mesmo bundle). **Efeito:** usuário que desativa apenas "newsletter" mas mantém "alertas" continua recebendo alerta crítico — correto se essa for a intenção do produto, mas nunca foi documentado como decisão explícita. **Achado lateral agravante:** se o binding `EMAIL_ALERTAS_FAVORITOS` não estiver setado em produção, o fallback em `selecionarDestinatariosAlerta` (linha 5009) é broadcast para **todos os usuários aprovados**, sem filtro de preferência algum — não foi possível confirmar ao vivo se esse binding está setado (ver Lacunas). Nunca havia sido registrado como pendência formal — aberto agora como item `ALRT1` em `PENDENCIAS.md`.

### MÉDIO

- **SPF1 — `send.vixradar.com` com SPF em softfail, divergente do domínio raiz hardenizado.** DNS ao vivo (`nslookup -type=TXT`, 2026-07-12):
  - `vixradar.com`: `v=spf1 include:_spf.mx.cloudflare.net include:amazonses.com include:send.resend.com -all` (hardfail) — bate com o hardening documentado na nota 17 (2026-06-17T21:33Z).
  - `send.vixradar.com`: `v=spf1 include:amazonses.com ~all` (**softfail**) — valor hardcoded em `api/tools/criar-token-dns-e-spf.ps1:37`, não atualizado quando o domínio raiz foi hardenizado.
  - `_dmarc.vixradar.com`: `v=DMARC1; p=quarantine; sp=quarantine; rua=mailto:dmarc@vixradar.com; ruf=mailto:dmarc@vixradar.com; pct=100; adkim=r; aspf=r` — ativo, consistente com nota 17.
  Risco: e-mails com return-path em `send.vixradar.com` (transacionais via Resend) têm política de falha mais fraca (`~all`) que o domínio raiz — não é uma falha de entrega hoje, mas é uma inconsistência de hardening a fechar.

### BLOQUEIO (impede parte da auditoria — não é achado de produto)

- **CRED1 — `admin_senha` fornecida na sessão não autentica contra produção.** `POST {action:"admin_health_check", admin_senha:"..."}` retornou `{"ok":false,"erro":"Acesso negado."}` (HTTP correspondente a `admin_senha !== env.ADMIN_PASSWORD`, confirmado no código-fonte linha 15774). `POST {action:"status_providers", admin_senha:"..."}` retornou `{"ok":false,"erro":"Token necessário."}` — essa action nunca aceitou `admin_senha`: exige JWT de login admin (`extractToken`/`verificarJWT`, linhas 13307-13317). **Não tentei outras senhas** (não é apropriado adivinhar credencial de produção). Bloqueou: Etapa 4 completa (saldo/status granular dos providers) e parte da Etapa 6 (valor ao vivo de `EMAIL_ALERTAS_ENABLED`, que é secret e não aparece no repo).

### BAIXO

- Nenhum novo (o mismatch de nomes de arquivo na Etapa 8 foi tratado como decisão de processo, não como achado técnico).

---

## Validação em produção

| Etapa (protocolo do operador) | Resultado | Evidência |
|---|---|---|
| 1. Estado do Worker (`workers_get_worker_code`) | PASS | `WORKER_VERSAO="v4.9.150"` linha 3594; nenhum `TODO`/`FIXME` no bundle; ~75 `actions` e ~20 `ops` distintos mapeados (ver lista completa no output da sessão) |
| 2. Frontend (`CACHE_VERSION` + `version.json`) | PASS | `CACHE_VERSION="v201.74"` no HTML; `{"version":"v201.74","deployed_at":"2026-07-07T22:45:43Z"}` |
| 3. Health check (`GET /`) | PASS | `{"ok":true,"versao":"v4.9.150","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}` HTTP 200, 0.73s |
| 4. Status de providers (`status_providers` + `admin_senha`) | **BLOQUEADO** | Ver CRED1 — action exige JWT, não `admin_senha`; sem sessão de login admin nesta auditoria |
| 5. EWS/matinal (`MATINAL_TOP_N`, `score_combinado`) | PASS | `MATINAL_TOP_N=30` (linha 8333); `score_combinado = ews.score*0.6+matMax*0.4+ecoCount*0.1+stalenessBoost` (linha 8361) — caractere por caractere igual ao especificado. Pesos não questionados (julgamento do operador) |
| 6. DNS/e-mail (SPF/DMARC + `EMAIL_ALERTAS_ENABLED`) | **PARCIAL** | SPF/DMARC confirmados ao vivo (ver SPF1); `EMAIL_ALERTAS_ENABLED` **não confirmado ao vivo** — bloqueado por CRED1, última confirmação documentada é nota 17 (ativado 2026-06-17) |
| 7. Bug `dispararAlertaCritico`/`prefs.newsletter` | **CONFIRMADO ABERTO** | Ver ALRT1 — não corrigido, código ao vivo confere com análise estática prévia |
| 8. Documentação | **REDIRECIONADO** | Decisão do operador — ver seção "Etapa 8" acima; esta nota + nota 03 + índice + `PENDENCIAS.md` substituem os 3 arquivos citados originalmente |

---

## Lacunas

- Saldo/status granular por provider (Etapa 4) — requer login JWT admin, não disponível nesta sessão (readonly, sem credencial válida).
- Valor ao vivo de `EMAIL_ALERTAS_ENABLED` (secret Cloudflare, fora do repo) — requer `admin_senha` correta ou acesso ao painel Cloudflare; não confirmado desde 2026-06-17.
- Confirmação ao vivo de `EMAIL_ALERTAS_FAVORITOS` (relevante para o achado ALRT1 — determina se o fallback é broadcast total) — mesma dependência de credencial.
- Cobertura dos 103 emissores / staleness — fora do escopo das 8 etapas pedidas nesta rodada (não solicitado pelo operador; ver `/vix-radar-audit` Bloco F para próxima auditoria completa).

---

## Próximos passos

| P | Ação | Ref |
|---|------|-----|
| P1 | Operador confirmar/rotacionar `ADMIN_PASSWORD` de produção e validar `admin_senha` correta para desbloquear Etapas 4 e 6 | CRED1 |
| P1 | Decidir e implementar comportamento correto de `dispararAlertaCritico` frente a `prefs.newsletter` (incluir checagem, ou documentar explicitamente que "alertas" e "newsletter" são independentes por design) | ALRT1 |
| P2 | Atualizar `api/tools/criar-token-dns-e-spf.ps1:37` e o registro DNS de `send.vixradar.com` para `-all` (hardfail), alinhando com o domínio raiz | SPF1 |
| P2 | Confirmar se `EMAIL_ALERTAS_FAVORITOS` está setado em produção (determina severidade real de ALRT1 — broadcast total vs. só favoritos) | ALRT1 |

---

## Notas de processo

- Auditoria conduzida em modo Plan (aprovação prévia do operador via `ExitPlanMode`) — ambiguidade da Etapa 8 resolvida por `AskUserQuestion` antes da execução.
- `workers_get_worker_code` retornou bundle grande (>800 mil caracteres) — analisado via arquivo salvo + `Grep` segmentado, não lido integralmente linha a linha; números de linha citados acima referem-se a esse bundle salvo, não ao arquivo `api/v4.9.150.js` do repo local (que é a mesma fonte, mas a numeração de linha pode variar por formatação do MCP).
- Nenhuma senha de admin foi tentada além da fornecida pelo operador; nenhuma credencial foi registrada neste arquivo.
- Tempo total: sessão única, modo caveman ativado a meio da execução (sem impacto na evidência coletada).
