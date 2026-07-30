# 72 - Correcao Estrutural e Deploy v4.9.183 (2026-07-28)

## Estado final

- Worker em producao: `v4.9.183`.
- Frontend em producao: `v201.93`.
- Branch: `codex/system-finalization-v4.9.183`.
- Commit: `12f24907662f1b3fa1cabe9bb648345b2aa1389e`.
- PR: <https://github.com/Yan69793/monitoramento-credito-vix-radar/pull/18> (aberta, mergeavel, 20 arquivos).

## Correcoes entregues

1. `api/src/worker.js` passa a ser a fonte canonica; `scripts/build-worker.ps1` gera o artefato de forma reproduzivel e o Wrangler publica com `no_bundle=true`.
2. CAL-003: `op=state` e `op=calendario` aplicam `calendario:overrides:v1`; o build da agenda ja usava a mesma base mesclada.
3. CAL-002: frontend `v201.93` nao exibe data estimada com selo de certeza.
4. VOL-001: Merton nao usa mais preco por acao nem patrimonio contabil como valor de mercado; sem market cap real o indicador fica nulo.
5. VOL-003: Selic efetiva vem do BCB SGS 1178; fonte, data, faixa e staleness sao validadas. Payload publicado com `0.1415`, `as_of=2026-07-28`.
6. O uploader remove `market_cap` falso e corrige mojibake dos nomes antes do KV.
7. CI, fallback e coleta agora falham com exit nao-zero quando nao executam ou ficam parciais.
8. Rotinas matinal/noturna e wrapper generico toleram pipe de console oculto sem trocar a politica global de erro para Continue.
9. A agenda semanal carrega `ROUTINE_API_KEY` do ambiente e sanitiza qualquer chave literal antes de montar o prompt; a definicao local tambem foi limpa.

## Evidencias

- Parsers PowerShell, `node --check`, YAML e Bash: verdes.
- Teste `tests/system-final-regressions.mjs`: verde.
- Build repetido: SHA-256 `2E438B35778EE38A6FA48443206430228E672EFAFFE91729EE5346515D7896A1` nas duas execucoes.
- Wrangler 4.115.0 `--dry-run`: verde; KV, Durable Objects e Analytics Engine preservados.
- Uploader `-DryRun`: 73 emissores; sem `market_cap` falso e sem mojibake.
- Testes de falha da coleta: coletor exit 7 e uploader exit 8 resultaram em exit 1 da rotina.
- Runner da agenda no PowerShell 5.1 com Claude falso: exit 0, sem rede nem KV.
- Exportador historico `-DryRun`: exit 0, quatro arquivos e manifest validos.
- Health administrativo: `ok=true`, 103 emissores, `updated_at=2026-07-28T21:00:28.079Z`, semanas W31/W30.

## Portao final (23:33Z)

```text
workers.dev: HTTP 200, ok=true, versao=v4.9.183, kv=true, rate_limiter=true, telemetria=true
api.vixradar.com: HTTP 200, ok=true, versao=v4.9.183, kv=true, rate_limiter=true, telemetria=true
vixradar.com/version.json: HTTP 200, version=v201.93
```

A primeira checagem do script ocorreu quatro segundos apos o upload e ainda encontrou `v4.9.182` no dominio customizado. A propagacao convergiu em seguida; seis leituras consecutivas e o portao final retornaram `v4.9.183`.

## Observacoes nao bloqueantes

- O status Vercel da PR 18 esta vermelho, mas o mesmo status ja falha em `origin/main` e na PR 17. O deploy oficial deste projeto e Cloudflare Pages; portanto e integracao Vercel legada, nao regressao desta entrega. Remover/desconectar a integracao exige decisao administrativa separada.
- O token Cloudflare de deploy nao possui leitura direta de KV (401), principio de menor privilegio preservado. A escrita foi confirmada pelo endpoint administrativo com `UPLOAD_OK`; nenhuma permissao foi ampliada.
- Os resultados antigos do Task Scheduler continuam no historico ate a proxima execucao real. O codigo foi instalado localmente e validado com caminhos sem efeito externo.

## Rollback

- Worker: `pwsh ./scripts/deploy-worker.ps1 -Version v4.9.182` a partir de uma arvore que contenha o artefato anterior.
- Frontend: republicar `v201.92` somente se a contencao CAL-002 precisar ser revertida.
- O KV novo expira em 24h e pode ser republicado pelo uploader anterior, mas isso reintroduziria Selic stale/market cap invalido e nao e recomendado.