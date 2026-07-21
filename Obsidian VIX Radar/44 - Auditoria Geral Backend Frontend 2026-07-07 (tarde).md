# Auditoria Geral — VIX Radar (2026-07-07, ~16:15-16:35 BRT)

Skill: `/vix-radar-general-audit`. 4 subagentes paralelos (backend/segurança, frontend, confiabilidade+governança, perf/a11y) + spot-check manual dos achados mais graves + fixes aplicados no repo (commits `8c1d79f` worker, `c5ff9a6` frontend). Complementa [[42 - Auditoria Geral Backend Frontend 2026-07-06]] e [[43 - Auditoria Geral Backend Frontend 2026-07-07]] (auditoria da manhã, achados P0 de governança já resolvidos por outra sessão antes desta rodada).

## Contexto — sessões concorrentes

Esta auditoria rodou enquanto outra sessão Claude Code trabalhava no mesmo repo em paralelo (commit `15647ef`, feature de z-scores ANBIMA v4.9.147 + deploy). Por isso parte do trabalho desta nota é **correção de registro**: `PENDENCIAS.md`/`03 - Estado de Produção.md` tinham alegações escritas pela outra sessão que não se sustentaram na checagem independente ("rotina 07/07 executada 103/103", "working tree limpo") — corrigidas nesta rodada, ver essas notas.

## Veredito

Produção saudável no runtime (Worker v4.9.147 `ok:true`, Frontend v201.70 sem drift, 103/103 emissores `stale_24h:0` na foto do meio-dia), mas a auditoria achou **2 regressões de segurança reais** (uma delas contradiz um changelog que dizia "resolvido"), **1 endpoint novo público sem auth que gasta dinheiro de verdade**, **1 falha silenciosa no carregamento principal do dashboard de crédito**, e confirmou que a matinal de hoje ficou pela metade. Todos os achados de código foram corrigidos no repo (`v4.9.148`/`v201.71`) — **nenhum deploy foi feito**, aguarda autorização.

## Top riscos (corrigidos no repo, deploy pendente salvo indicação contrária)

| Sev | Área | Achado | Evidência | Status |
|---|---|---|---|---|
| P1 | Backend/Auth | `admin_mercado` aceitava senha via `?senha=` GET, changelog v4.9.142 alegava fechado — só somou path POST, não removeu o GET | `api/v4.9.147.js:11785-11787`; curl HTTP 200 no GET com senha | **Corrigido** `api/v4.9.148.js` — só POST autentica |
| P1 | Frontend/UX | `carregarResultadosCompartilhados()` (`op=state`) engolia qualquer erro (rede/500/403/parse), caía pro cache local sem avisar — dashboard de crédito podia mostrar dado stale sem sinalizar | `app/index.html`, função com 3 pontos de `return!1` silenciosos | **Corrigido** — banner `dados_desatualizados` nos 3 pontos |
| P1 | A11y | 6 campos de login/cadastro/admin (`admin-senha-input` + 5 de login/registro/recuperação) sem `for=`/`aria-label` — mesma classe do bug já corrigido em 4 campos de senha, ficaram de fora | `app/index.html` (múltiplas linhas) | **Corrigido** — `for=`/`aria-label`/`aria-labelledby` em todos |
| P1 | Rotinas | Matinal hoje interrompida — Task nativa `LastResult=3221225786` (CTRL_C_EXIT), log sem `FIM:`, sem metrics file. Só 4/15 emissores confirmados | `logs/routines/vixradar-matinal_20260707.log` | **Aberto** — precisa rerun ou confirmação via `op=state` |
| P1 | Rotinas | Noturno oficial (18h BRT) não tinha rodado até a hora da auditoria; mitigação de ontem contra disparo fantasma já falhou 1x hoje (rodou 10:07 mesmo `enabled:false`) | `Get-ScheduledTask VIXRadar-Noturno` NextRun 18:00; SKILL.md documenta falha | **Em observação** — checar log das 18h |
| P2 | Backend/Auth | `action=zscores_anbima` (novo em v4.9.147) e `action=teste` públicos sem auth — o 2º dispara chamadas reais pagas a OpenRouter/Perplexity, vetor de abuso de custo | `api/v4.9.147.js:14935,14937`; curl 200 anônimo em ambos | **Corrigido** `api/v4.9.148.js` — `_exigeJwtAdmin` nos dois |
| P2 | Backend | `tel(env2222,"verificacao_async_rejeitado",{...})` mesmo bug já corrigido em `routine_analise_recebida`, aqui não — telemetria de rejeição do verificador assíncrono nunca gravava | `api/v4.9.147.js:15573` | **Corrigido** `api/v4.9.148.js:15575` |
| P2 | A11y | 11 botões "×"/"✕" sem `aria-label`; Esc não fechava 5 de 11 modais (LGPD×2, admin, onboarding, modal de varredura) | `app/index.html`, grep `&times;`/`✕` | **Corrigido** — `aria-label` nos 11, Esc handler novo pros 5 modais |
| P3 | Backend | `sourceMappingURL` stale (`v4.9.99.js.map`); `executarRotaWebSecundariaExa` código morto (zero call sites) | `api/v4.9.147.js:16152` | Função morta **removida**; sourcemap deixado (cosmético, sem `.map` real de qualquer versão) |

## Backend (bundle v4.9.147 → v4.9.148)

Confirmado OK (sem achado): `wrangler.toml` íntegro; secrets sem fallback inseguro; POST anônimo 401; CORS allowlist sem wildcard; rate limiter fail-open logado; `receber_analise` distingue sem-evento de pendente-verificação; multi-semana nos 5 endpoints; CVM sem fallback silencioso "hoje"; `calcularZScoresANBIMA` com try/catch e TTL 7d; sem leak de secret em log; `fetch()` não recebe `ctx` (sem `waitUntil`, tudo síncrono — dívida técnica, não bug de correção, deixado como backlog).

## Frontend

Sem drift `index.html`↔`deploy_zip` antes da auditoria (byte-idêntico). Auth Bearer correto em todos GETs protegidos. `esc()`/XSS sem regressão. Regra CSS `strong` sem `color`, íntegra. `sessionStorage` senha admin sem regressão. `CACHE_VERSION` bumpado v201.70→v201.71 depois das mudanças de conteúdo, `deploy_zip` ressincronizado.

## Perf e a11y adicional (achados NÃO corrigidos nesta rodada — backlog)

- Contraste `#4E6070` sobre fundos navy calculado em ~3.0-3.16:1 (precisa 4.5:1 pra texto normal), usado 73× no arquivo — sistêmico no design system, não corrigido (mudança de cor em 73 pontos exige revisão visual, fora do escopo desta rodada).
- 2 requisições Google Fonts fragmentadas + `preconnect` mal posicionado.
- 5 scripts admin (~36.7KB) sem `defer`, carregados por todo visitante.
- `Market Overview` é `<div>` estilizado como tabela, sem semântica `<table>`.
- CRLF/LF entre `app/admin/*.js` e `deploy_zip/admin/*.js` (cosmético).
- `.mo-back-btn` sem indicador de foco visível (outline:none sem compensação) — não corrigido.

## Validação dos fixes

- `node --check api/v4.9.148.js` → OK.
- Frontend: servido via `python -m http.server` local (`app/` estático), `preview_eval` confirmou: Esc fecha `lgpdPrivacidade` (`classList.contains('vis')` false após Escape sintético); `for=` presente nos 5 novos campos; `aria-label`/`aria-labelledby` presentes nos campos admin/branding. Sem erro de console após reload.
- **Nenhum teste contra produção real** (endpoints corrigidos não foram exercitados ao vivo pós-fix — deploy ainda não aconteceu).

## Próximos passos

1. **P1** — Deploy `v4.9.148` (Worker) e `v201.71` (Pages), mediante autorização do operador. Pós-deploy: revalidar `admin_mercado` GET não autentica mais, `zscores_anbima`/`teste` retornam 401 sem token, `GET /` → `versao:"v4.9.148"`, `version.json` → `v201.71`.
2. **P1** — Confirmar/rerodar matinal de hoje (só 4/15 confirmados).
3. **P1** — Observar noturno das 18h BRT; se disparo fantasma se repetir, mitigação por cron impossível não é suficiente.
4. **P2** — Contraste `#4E6070`, fonts fragmentadas, scripts admin sem `defer`, tabela Market Overview semântica — backlog de perf/a11y não corrigido nesta rodada.
