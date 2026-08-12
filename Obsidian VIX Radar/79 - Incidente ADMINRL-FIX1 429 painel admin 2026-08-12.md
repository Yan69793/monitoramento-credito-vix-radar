---
data: 2026-08-12
tipo: post-mortem
tags: [vix-radar, incidente, rate-limit, painel-admin, worker]
status: encerrado
---

# 79 - Incidente ADMINRL-FIX1: 429 no painel admin (2026-08-12)

## Sintoma

Painel admin exibindo erro ao carregar a tela Hoje. Screenshot do Yan 15:13:52 BRT, 12/08. Mensagem: "Muitas varreduras em pouco tempo. Tente novamente em N segundo(s)."

## Causa raiz

Regressao do gate RLADMIN2 (v4.9.164). O gate manda para `checkRateLimitV2` qualquer request com `admin_senha` no body, para fechar o vetor de brute force da ADMIN_PASSWORD nos ~52 handlers admin. So que o painel admin legitimo autentica exatamente assim:

- `app/js/admin/shared.js` `postAdmin()` manda `admin_senha` em todo POST e nao manda o JWT (`radar_jwt`) no header.
- `app/js/admin/modules.js` `loadHoje()` dispara 4 POSTs em paralelo (`admin_listar`, `uso` x2, `relatorio_dry_run`).
- Sem JWT, o request cai como anonimo: burst de 3/60s (`RATE_LIMITS_ANONIMO`).
- O 4o POST estoura o burst e responde 429. Clicar em Atualizar estoura session (10/30min) e o painel fica inutilizavel por meia hora mesmo com senha certa.

Confirmado em Observability do Worker: rajada de 7+ POSTs 429 entre 15:13:27 e 15:13:37 BRT, cada um precedido de `POST /check` no RateLimiterDO. Zero excecoes no Worker (GraphQL analytics errors:0). O 429 era resposta de aplicacao, nao falha de execucao, por isso health e CI estavam verdes.

## Correcao

v4.9.191, commit `c2b2d5f`, deploy `4a35977`. No gate (`api/src/worker.js` ~15935): se `admin_senha === ADMIN_PASSWORD`, pula o `checkRateLimitV2`. Brute force continua throttled: senha errada segue no check com limites anonimos.

Testes de regressao em `api/test/rate-limit.test.mjs` (CI `worker-tests.yml` verde):
- `admin_listar` com senha errada x4: 1a-3a 403, 4a 429/burst.
- `admin_listar` com senha correta x6: nenhum 429, 1a 200.

## Licoes

1. O anti-brute-force cobria "qualquer request com admin_senha", mas o cliente legitimo do painel autentica por admin_senha em paralelo de 4. Regra: gate de rate limit sobre credencial precisa de bypass para credencial correta, senao o fluxo legitimo estoura antes do atacante.
2. Resposta 429 de aplicacao nao aparece como "error" no GraphQL analytics do Cloudflare (errors = excecoes/timeouts). Sintoma so aparece em Observability events olhando status code. O monitor de rotinas tambem nao cobre isso. Se o Yan nao tivesse mandado o screenshot, seguiria invisivel.
3. O painel admin tem JWT disponivel (`radar_jwt` no localStorage) mas nao usa no `postAdmin`. Com o bypass atual nao importa, mas e divida de identidade: se o fluxo admin mudar, enviar o Bearer passaria a usar limites de tenant (vix_core 5/60s).

## Pendencias

- Nenhuma aberta para este incidente. Pendencia registrada no backlog: `postAdmin` enviar `Authorization: Bearer` quando `radar_jwt` existir (redundante hoje, util se o bypass for revisto).

## Verificacao

- Health 12/08 15:48 BRT: `ok:true`, `versao:v4.9.191`, `telemetria:true`, `kv:true`, `sentry_ok:true`, HTTP 200, 0,32s.
- Worker Tests CI no commit `c2b2d5f`: success.
- Validacao final pendente do uso real do painel pelo Yan apos o deploy (sem novos 429 na tela Hoje).
