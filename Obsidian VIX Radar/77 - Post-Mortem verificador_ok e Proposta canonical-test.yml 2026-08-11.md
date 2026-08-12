---
data: 2026-08-11
tipo: post-mortem
tags: [vix-radar, incidente, verificador_ok, canonical-test, observabilidade]
status: incidente-fechado-fix-aplicado
---

# Post-Mortem — verificador_ok:false (05/08) e proposta de fix para canonical-test.yml

Nota consolidada a partir de 3 diagnósticos de IA feitos em sessão de terminal
em 05/08 (arquivos `Plano Code - Grok.txt`, `Plano Code - Vixradar.txt`,
`Plano Code - deepseek.txt`, extraídos aqui e depois apagados da raiz do repo
em 11/08 — auditoria de organização do working tree). Os 3 convergem no mesmo
diagnóstico com ângulos complementares.

## Conclusão

`ok:false` em 05/08 **não era secret ausente**. `admin_email_ok:true` e
`sentry_ok:true` o tempo todo. A causa era `verificador_ok:false`, que por sua
vez vinha de fila de verificação (`radar:verif_fila:{data}`) com itens parados
há mais de 12h sem consumo.

## Como o Worker decide `ok` (lido direto do bundle de produção v4.9.187)

```js
var _adminEmailOk = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(env.ADMIN_EMAIL || "").trim());
var _sentryOk     = /^https:\/\/[^\s@]+@[^\s@]+\/\d+$/.test(String(env.SENTRY_DSN || "").trim());
const _okHealth = !!env.RADAR_KV && !!env.RADAR_USAGE_EVENTS && !!env.RESEND_API_KEY
                  && _adminEmailOk && _sentryOk && _verificadorRealOk;
```

`ok` depende de 6 fatores (KV, telemetria/Analytics Engine, Resend, e-mail
admin, Sentry, verificador). Bindings saudáveis não bastam — um único item
CRITICO preso na fila por mais de 12h já derruba `verificador_ok` e com isso
`ok` inteiro, mesmo com todo o resto verde.

## Cadeia causal do incidente de 04-05/08

1. Matinal e noturno de 04/08 enfileiraram eventos normalmente em
   `radar:verif_fila:2026-08-04` (22 itens).
2. O consumo da fila (`run_vixradar_verificacao_async.ps1`) falhou repetidas
   vezes com **ambiente contaminado**: `ANTHROPIC_DEFAULT_SONNET_MODEL` ou
   `settings.json.model` apontando para `deepseek-v4-pro` em vez de um modelo
   Claude. A guarda de contaminação do script é fail-closed por desenho (abortar
   é o comportamento correto), mas isso significa que a fila fica sem dreno até
   alguém corrigir o ambiente manualmente.
3. Por volta de 20 dos 22 itens (criados antes de 13h32 BRT) passaram de 12h
   de idade, health foi a vermelho por desenho.
4. Causa raiz definitiva (documentada em `03 - Estado Atual.md`, seção
   "04-06/08 — Guarda ambiental, call sites orfaos e prevencao estrutural"):
   dois incidentes encadeados, primeiro a contaminação de ambiente, depois um
   commit de correção (`2b025b0`) que removeu funções ainda referenciadas pelos
   scripts, quebrando o dreno de novo por 2 dias antes de `Assert-VixLibFunctions`
   fechar o buraco estrutural.

## Achado técnico (implementado entre 05/08 e 11/08)

O endpoint de health **já devolve** os 3 fatores individuais no JSON
(`admin_email_ok`, `sentry_ok`, `verificador_ok`), mas nenhum workflow do
GitHub Actions os lê — só o campo agregado `ok`. Resultado prático: toda vez
que `ok:false` aparece, o alerta não diz qual dos 6 fatores caiu, e alguém
precisa recuperar o bundle de produção ou vasculhar log pra descobrir. Isso
se repetiu de novo em **11/08 13h37 UTC** (`canonical-test.yml` run
`31393983894`, mesmo padrão: `verificador_ok:false` por fila de verificação
crescendo durante o dreno, kv/telemetria seguiam `true`) — o gap de
observabilidade identificado aqui em 05/08 ainda não foi fechado.

### Proposta concreta

Em `.github/workflows/canonical-test.yml`, no step que já roda `jq` sobre a
resposta do health:

```bash
ADMIN_EMAIL_OK=$(echo "$BODY" | jq -r '.admin_email_ok // "unknown"')
SENTRY_OK=$(echo "$BODY" | jq -r '.sentry_ok // "unknown"')
VERIFICADOR_OK=$(echo "$BODY" | jq -r '.verificador_ok // "unknown"')
```

E na validação, trocar a mensagem cega por uma que nomeia o fator:

```bash
if [ "$OK" != "true" ]; then
  echo "::error::Health ok=$OK — fatores: admin_email_ok=$ADMIN_EMAIL_OK sentry_ok=$SENTRY_OK verificador_ok=$VERIFICADOR_OK (kv/telemetria/resend ja validados acima)"
  FAIL=1
fi
```

Ganho durável e independente da causa de cada ocorrência futura: o alerta
passa a apontar o culpado em vez de só dizer "produção degradada". Não mexe em
nenhuma outra lógica do workflow (guard anti-drift, drift de frontend,
`CACHE_VERSION`).

**Status 11/08:** Fix aplicado. `canonical-test.yml:58-60,111-117` ja le `admin_email_ok`, `sentry_ok` e `verificador_ok` individuais e reporta no log de falha. Confirmado por auditoria de codigo.

Backlog relacionado ainda aberto: VERIFSLA1 (health lookback de 2 dias nao cobre janela do sweep de 7 dias), ver [[PENDENCIAS.md]].

## O que não precisava ter sido feito em 05/08 (e não foi)

- Mexer em secrets do Cloudflare (`ADMIN_EMAIL`/`SENTRY_DSN`) — já verdes.
- Redeploy do Worker — versão e bindings estavam corretos.
- Investigar providers — 2/2 o tempo todo.

## Ação imediata considerada e não executada

Um dos rascunhos propôs zerar a fila deletando a chave `radar:verif_fila:2026-08-04`
do KV como atalho pra voltar o health a verde, descartando a verificação AI dos
22 eventos pendentes. Não foi essa a rota tomada — o incidente fechou pelo
conserto estrutural (`Assert-VixLibFunctions`, preflight de credencial) em vez
de descarte de dado, ver `03 - Estado Atual.md`.
