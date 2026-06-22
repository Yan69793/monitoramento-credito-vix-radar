# Auditoria Geral Backend/Frontend — 2026-06-20

Skill usada: `/vix-radar-general-audit` em modo readonly.

## Veredito

Sistema de produção saudável no caminho público: Worker v4.9.143 responde 200 em `api.vixradar.com` e `workers.dev`, com KV, RateLimiterDO, telemetria e `verificador_ok:true`. Frontend público está em v201.69.

Achado principal: há drift confirmado entre `app/admin/` e `app/deploy_zip/admin/`, e o drift está publicado em produção. A fonte corrigida usa `sessionStorage` para `radar_admin_senha`, mas o pacote `deploy_zip` e `https://vixradar.com/admin/*.js` ainda usam `localStorage`.

## Evidência bruta

### Produção

| Teste | Resultado |
|---|---|
| `GET https://api.vixradar.com/` | `{"ok":true,"versao":"v4.9.143","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}` HTTP 200, 0.366s |
| `GET https://radar-credito-api.prospects-intel.workers.dev/` | mesmo payload v4.9.143 HTTP 200, 0.132s |
| `POST https://api.vixradar.com/ {}` | `{"ok":false,"erro":"Autenticação necessária."}` HTTP 401 |
| `GET https://vixradar.com/version.json` | `{"version":"v201.69","deployed_at":"2026-06-18T13:46:10Z"}` HTTP 200 |
| Headers `version.json` | `Cache-Control: no-cache, no-store, must-revalidate`; `X-Frame-Options: DENY`; `X-Content-Type-Options: nosniff` |
| Headers `admin/vr-admin-shared.js` | `Cache-Control: public, max-age=14400, must-revalidate`; `Content-Length: 6093`; `CF-Cache-Status: REVALIDATED` |

### Repo e drift

| Arquivo | Tamanho | Observação |
|---|---:|---|
| `app/index.html` | 688341 | hash igual a `app/deploy_zip/index.html` |
| `app/deploy_zip/index.html` | 688341 | alinhado com fonte |
| `app/admin/vr-admin-shared.js` | 6156 | usa `sessionStorage` |
| `app/deploy_zip/admin/vr-admin-shared.js` | 6093 | usa `localStorage` |
| `app/admin/vr-admin-modules.js` | 22559 | usa `sessionStorage` |
| `app/deploy_zip/admin/vr-admin-modules.js` | 22555 | usa `localStorage` |

Trechos confirmados:

- Fonte `app/admin/vr-admin-shared.js`: `return sessionStorage.getItem("radar_admin_senha") || "";` e `sessionStorage.setItem("radar_admin_senha", v)`.
- Deploy local `app/deploy_zip/admin/vr-admin-shared.js`: `return localStorage.getItem("radar_admin_senha") || "";` e `localStorage.setItem("radar_admin_senha", v)`.
- Produção `https://vixradar.com/admin/vr-admin-shared.js`: linhas 96/104 usam `localStorage`.
- Produção `https://vixradar.com/admin/vr-admin-modules.js`: linhas 21/563 usam `localStorage`.

### Worker/config

- `api/wrangler.toml` aponta `main = "v4.9.143.js"`.
- Bindings presentes no toml: `RADAR_KV`, `RATE_LIMITER_DO`, `RADAR_USAGE_EVENTS`.
- Route presente: `api.vixradar.com`.
- Observability presente: `[observability] enabled = true`.
- Crons presentes: `30 15 * * *`, `30 21 * * *`, `0 1 * * *`, `0 4 * * *`.
- `api/v4.9.143.js`: `WORKER_VERSAO = "v4.9.143"`.
- Multi-semana: várias chamadas confirmadas a `carregarEstadoMultiSemana(env2222, 5)`, incluindo roteamento para `briefing_executivo`, `historico_emissor` e `comparar`.
- `receber_analise`: protegido por `ROUTINE_API_KEY`; calcula `_raSaneado.sem_eventos = _raEvs.length === 0`.
- Sintaxe: `node --check api/v4.9.143.js` sem erro; `node --check app/admin/vr-admin-shared.js` sem erro.

## Top riscos

| Sev | Área | Achado | Impacto | Ação |
|---|---|---|---|---|
| P1 | Frontend/admin | Drift publicado: senha admin persiste em `localStorage` nos módulos de produção, embora fonte use `sessionStorage` | A senha admin pode sobreviver ao fechamento do navegador e ampliar superfície em máquina compartilhada/comprometida | Sincronizar `app/deploy_zip/admin/*.js` a partir de `app/admin/*.js`, redeploy Pages, validar produção |
| P2 | Governança repo | Working tree bastante sujo, com várias skills e artefatos untracked; `git status` mostra `.claude/SKILLS-ROUTER.md` e muitas skills novas não rastreadas | Dificulta saber o que será levado para deploy/commit; aumenta risco de omissão ou inclusão indevida | Separar mudanças da skill/auditoria em commit próprio; classificar o restante |
| P2 | Performance/manutenibilidade | `app/index.html` tem 688 KB / 6603 linhas; Worker ativo tem 15905 linhas de bundle | Custo de manutenção alto; risco de regressão por edição em monólito | Continuar extração Admin HEART e módulos; evitar editar bundle antigo |
| P3 | Acessibilidade | Há sinais positivos (`role`, `aria`, `focus`, `Escape`), mas sem teste browser/teclado nesta rodada | Lacuna de validação real de foco/trap em dialogs | Rodar passe visual/teclado com browser quando a prioridade for UX |

## Achados descartados/baixados

- `Math.random()` em `api/v4.9.143.js:9657` aparece em `VERIFICADOR_CONFIG.relevante_sample_rate`; não é geração de token/secret nesta leitura, portanto não foi classificado como bug de segurança.
- Regra global `strong` permanece correta: `strong, .text-strong, [class*="strong"] { font-weight: 600; }` sem `color`. Há cores em seletores específicos, permitido pelo protocolo.

## Lacunas

- Não rodei `tel_test`, `admin_health_check` nem `admin_verificar_evento`: exigem senha/admin ou routine key; auditoria ficou readonly sem expor credenciais.
- Não rodei Lighthouse/Core Web Vitals em navegador; análise de performance foi estática.
- Não usei Cloudflare API/Wrangler remoto para listar crons/secrets; usei toml + health público.

## Fontes externas usadas

- OWASP ASVS 5.0.0: https://owasp.org/www-project-application-security-verification-standard/
- OWASP WSTG: https://owasp.org/www-project-web-security-testing-guide/
- NIST SSDF SP 800-218: https://csrc.nist.gov/pubs/sp/800/218/final
- Web Vitals: https://web.dev/articles/vitals
- WCAG 2.2: https://www.w3.org/TR/WCAG22/
- Cloudflare Workers best practices: https://developers.cloudflare.com/workers/best-practices/workers-best-practices/

## Próximos passos

1. P1: sincronizar `app/deploy_zip/admin/vr-admin-shared.js` e `app/deploy_zip/admin/vr-admin-modules.js` com `app/admin/`, redeploy Pages e validar que produção usa `sessionStorage`.
2. P2: organizar o working tree antes de qualquer deploy: separar skill nova, auditoria, Obsidian e artefatos não relacionados.
3. P2: se houver janela, rodar health profundo autenticado: `admin_health_check`, `admin_verificar_evento`, `tel_test`.
4. P3: rodar passe browser teclado/mobile para dialogs e admin.
