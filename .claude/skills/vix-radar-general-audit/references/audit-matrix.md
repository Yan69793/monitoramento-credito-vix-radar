# Audit Matrix

Referencia rapida para auditoria geral backend/frontend do VIX Radar.

## Fontes externas pesquisadas

- OWASP ASVS: usar como baseline de controles de seguranca de aplicacao. Fonte: https://owasp.org/www-project-application-security-verification-standard/ (ASVS 5.0.0 stable).
- OWASP WSTG: usar como guia de cenarios de teste de seguranca web. Fonte: https://owasp.org/www-project-web-security-testing-guide/ (stable v4.2; v5.0 em desenvolvimento).
- NIST SSDF SP 800-218: usar para governanca de desenvolvimento seguro e prevencao de vulnerabilidades no SDLC. Fonte: https://csrc.nist.gov/pubs/sp/800/218/final.
- Web Vitals: usar Core Web Vitals como foco de performance e UX, avaliando percentil 75 em mobile e desktop. Fonte: https://web.dev/articles/vitals.
- WCAG 2.2: usar como baseline de acessibilidade, priorizando criterios A/AA aplicaveis. Fonte: https://www.w3.org/TR/WCAG22/.
- Cloudflare Workers observability: usar docs oficiais para logs/erros/observabilidade em Workers. Fonte: https://developers.cloudflare.com/workers/observability/errors/ e https://developers.cloudflare.com/workers/observability/logs/workers-logs/.

## Backend Worker

Checklist:

- `api/wrangler.toml`: `main`, `compatibility_date`, route custom domain, KV, DO, Analytics Engine, observability, crons.
- Bundle ativo: `WORKER_VERSAO`, roteamento `fetch`, `scheduled`, auth, CORS, rate limit, newsletter, ingestao.
- Seguranca:
  - Secrets sempre via `env`, sem fallback inseguro para JWT/API keys.
  - Admin actions exigem senha/admin/JWT/routine key conforme risco.
  - POST anonimo deve retornar 401/403 em rotas protegidas.
  - CORS deve ter allowlist e fallback seguro.
  - Logs nao devem vazar segredo, senha, token, email sensivel desnecessario ou payload LGPD.
- Confiabilidade:
  - `ctx.waitUntil` para trabalho assicrono que nao pode bloquear response.
  - Operacoes longas devem ter idempotencia/dedup/status.
  - Falha de provider deve ser visivel no health/admin health, nao virar ACK falso.
  - `receber_analise` deve persistir eventos aprovados e diferenciar "sem eventos legitimo" de "verificador falhou".
- Dados:
  - Multi-semana em endpoints criticos.
  - Datas CVM nao podem cair em fallback "hoje" sem sinalizacao.
  - `EMISSORES_LISTA`/setores/materialidade devem estar coerentes.

Comandos uteis:

```powershell
git status --short
git diff -- api/wrangler.toml app/index.html app/deploy_zip/index.html
rg -n "JWT_SECRET|ADMIN_EMAIL|ROUTINE_API_KEY|ANTHROPIC_API_KEY|OPENROUTER|Math.random|sem_eventos|receber_analise|carregarEstadoMultiSemana|RADAR_USAGE_EVENTS" api app
curl.exe -s https://api.vixradar.com/ -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```

## Frontend Pages

Checklist:

- `app/index.html` e `app/deploy_zip/index.html`: versions/cache alinhados.
- `app/admin/*.js` e `app/deploy_zip/admin/*.js`: modulos sincronizados.
- Auth:
  - Requests autenticados usam `Authorization: Bearer`.
  - 401 em endpoint secundario nao deve derrubar sessao sem contexto.
  - Senha admin nao deve ir em URL quando houver alternativa POST.
- UX:
  - Loading, empty, error e retry para state, briefing, comparar, admin e pulso.
  - Estados de dados atrasados devem ser explicitos.
  - Tabelas e cards precisam caber em mobile sem overflow critico.
- CSS:
  - Regra global `strong` sem `color`.
  - Evitar mudancas que quebrem contraste ou hierarquia.

## Performance

Priorizar:

- LCP: hero/conteudo inicial, HTML enorme, CSS/JS bloqueante.
- INP: handlers pesados, render de listas grandes, filtros/sorts no main thread.
- CLS: imagens/paineis sem dimensao, toasts/modais que empurram layout.
- Cache: `version.json` no-store, HTML coerente com estrategia de deploy, assets com nomes/versoes.

Limiares praticos:

- Core Web Vitals devem ser avaliados no percentil 75 por mobile e desktop.
- Quando nao houver lab/browser, registrar lacuna e fazer revisao estatica: tamanho do HTML, scripts inline, imagens, fontes, handlers globais.

## Acessibilidade

Amostra minima:

- Navegacao por teclado em login, dashboard, modais, admin e comparar.
- Foco visivel, fechamento de modal por Esc, trap de foco em dialogs.
- Labels em inputs, botoes com nome acessivel, status messages para loading/erro.
- Contraste de texto, badges e estados criticos.
- Tabelas com cabecalhos semanticos quando aplicavel.

## Relatorio

Cada achado deve incluir:

- Severidade.
- Area.
- Evidencia reproduzivel.
- Impacto.
- Acao recomendada.
- Se e bug confirmado ou risco a validar.

Evitar listas gigantes. Entregar top riscos primeiro e anexar lacunas.
