---
data: 2026-08-31
tipo: fechamento
tags: [vix-radar, incidente, braskemdetect1, deploy, imprensa]
status: fechado
---

# Fechamento BRASKEMDETECT1 e Deploy v4.9.227 — 2026-08-31

## Escopo

Endurecer o gatilho de imprensa para recuperação judicial/extrajudicial e fechar a pendência BRASKEMDETECT1. Resultado: concluído, código em produção v4.9.227.

## Causa raiz (medida, não hipótese)

A Braskem protocolou recuperação extrajudicial em 24/08 (US$ 10,9 bi reestruturados) e o painel não pegou pela imprensa. Dois defeitos independentes somados ao 404 do ZIP da CVM (CVMURL404, gatilho primário morto):

1. A query de busca de imprensa **R5** (e a **R3** da newsletter) não incluía "extrajudicial", então o protocolo não era nem buscado.
2. A camada determinística `aplicarRegrasNegocio` → `PALAVRAS_CRITICAS` só reconhecia "recuperacao judicial". A substring "recuperacao judicial" **não existe** dentro de "recuperacao extrajudicial", então um evento RELEVANTE com essa descrição passava intacto, sem promoção a CRÍTICO. O caso depende do LLM classificar certo sozinho, e essa camada de segurança nunca disparava.

## Correção (3 camadas em `api/src/worker.js`)

- **R5** e **R3** (newsletter): query ganhou "extrajudicial" ao lado de "judicial".
- **PALAVRAS_CRITICAS**: termo "recuperacao extrajudicial" nas duas formas (com e sem acento). Auto-promoção RELEVANTE → CRÍTICO com `_promovido_automaticamente:true`.
- **emitirAlertaTier1**: evento com "recuperação extrajudicial" recebe a tag `recuperacao-judicial`.

Exports novos: `aplicarRegrasNegocio` e `PALAVRAS_CRITICAS` para a suíte de teste.

## Guarda

`api/test/gatilho-recuperacao.test.mjs`, 5 testes, prova reversa medida (contra o código pré-correção, o teste 1 e 2 falham). Contraexemplo fixo: protocolo da Braskem de 24/08, não dado inventado. Cobre: promoção extrajudicial, variante acentuada, presença nas duas formas em PALAVRAS_CRITICAS, evento já CRÍTICO sem regressão (sem flag falsa), janela de 30 dias intacta (fora → null).

## Verificação

- Suíte vitest completa: **158/158, 19 arquivos** (153 + 5 novos), rodada local com devDeps instaladas.
- esbuild do bundle: EXIT 0.
- Deploy `deploy-worker.ps1 -Version v4.9.227`: gates de versão, working tree e SENTRY_DSN verdes; bundle 1010 KB; `WORKER_VERSAO` confere; changelog presente (WRCGL1).
- Produção validada na 1ª tentativa: `versao:v4.9.227`.
- Portão do projeto (31/08 17:25 BRT): `HTTP:200 TEMPO:0.23s`, `ok:true`, `kv:true`, `telemetria:true`, `sentry_ok:true`, `verificador_ok:true`, `fonte_externa_ok:true`.

## Commits

- `dddb009` fix(worker): BRASKEMDETECT1, gatilho de recuperacao extrajudicial (v4.9.227) — worker.js + teste + changelog.
- `bb1ec65` docs(vault+estado): fecha BRASKEMDETECT1 no codigo, deploy pendente.
- `af2abb1` chore(worker): deploy v4.9.227 em producao — bundle `api/v4.9.227.js` + toml + README.
- `ea5dfdb` docs(vault): 03 - Estado Atual em v4.9.227.

## Estado deixado

- Working tree limpo, `main` == `origin/main` (push OK).
- Produção em v4.9.227, health verde. Frontend segue v202.35 (não tocado).
- `Obsidian VIX Radar/PENDENCIAS.md`: BRASKEMDETECT1 marcado como fechado (corrigido no código + deployado).
- `status/ESTADO.md` e `03 - Estado Atual.md` sincronizados em v4.9.227.

## Resíduos (pré-existentes, decisão do operador)

- Rotação da `routine_key` (ROUTINEKEY-PLAIN1) segue pendente.
- Migração KV → DO (v5) em andamento, KV ainda fonte da verdade.
- `npm ci --omit=dev` do deploy removeu o vitest local; próximo `npm test` precisa de `npm ci` em `api/` antes.

## Handoff

Próximo passo: deixar a próxima passada de imprensa correr com o código novo e conferir que o primeiro evento extrajudicial chega CRÍTICO via camada determinística. Se voltar RELEVANTE, é regressão de R5 ou de PALAVRAS_CRITICAS. Relacionado: [[PENDENCIAS.md]], [[03 - Estado Atual]], [[95 - Auditoria Geral 2026-08-30 (madrugada)]].
