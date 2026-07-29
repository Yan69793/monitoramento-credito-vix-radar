# Proveniência do artefato v4.9.183

Registro de identidade do Worker que está em produção, com o hash comprovado contra o código
publicado, e correção das duas causas que faziam o repositório perder a fonte canônica.

## Identidade do artefato

| Item | Valor |
|---|---|
| Arquivo | `api/v4.9.183.js` |
| Tamanho com CRLF | 861.553 bytes |
| SHA-256 com CRLF | `2E438B35778EE38A6FA48443206430228E672EFAFFE91729EE5346515D7896A1` |
| Tamanho com LF | 844.411 bytes |
| SHA-256 com LF | `9102827BF51DD743673F10F0704027D652C47C06EBC381F0C4EFC35F2D525116` |
| Fonte canônica | `api/src/worker.js`, 861.563 bytes |
| Gerador | `scripts/build-worker.ps1 -Version v4.9.183` |
| `node --check` | exit 0 |

Produção roda a forma CRLF. Os dois hashes estão registrados porque o mesmo arquivo produz
valores diferentes conforme a quebra de linha, e confundir as duas formas já custou uma
conclusão errada nesta auditoria.

A diferença de 10 bytes entre fonte e artefato é exata e explicável. O placeholder
`__WORKER_VERSION__` tem 18 caracteres e é substituído por `v4.9.183`, que tem 8.

A diferença de 17.142 bytes entre as duas formas também é exata. O arquivo tem 17.142 pares
CRLF, e cada um perde um byte na conversão para LF.

## Como a identidade com produção foi comprovada

Leitura do código publicado pela API da Cloudflare, em 2026-07-28.

```
GET https://api.cloudflare.com/client/v4/accounts/{account_id}/workers/scripts/radar-credito-api/content/v2
```

O endpoint `/content` retorna HTTP 405 com código 10405 para o esquema de autenticação em uso.
O `/content/v2` retorna HTTP 200 com `multipart/form-data`. O módulo extraído do envelope tem
861.553 bytes e SHA-256 igual ao da tabela.

O artefato aqui versionado não foi copiado. Ele foi regerado a partir de `api/src/worker.js`
aplicando a substituição do placeholder, e o hash resultante bateu com o de produção. Isso
prova as duas coisas de uma vez, que a fonte é a fonte real e que o build é reprodutível.

## As duas causas que este commit corrige

**`api/src/` estava no `.gitignore`.** A regra genérica `src/` casa qualquer diretório chamado
`src` em qualquer nível da árvore, e por isso a fonte canônica do Worker não podia ser
rastreada sem `git add -f`. Corrigido com negação explícita para `api/src/`.

**Não havia `.gitattributes`.** Com `core.autocrlf=true` o git grava o blob em LF e devolve
CRLF no checkout. O resultado é que o SHA-256 do arquivo em disco depende da plataforma, e
qualquer verificação por hash responde uma coisa no Windows e outra no Linux ou em CI.
Corrigido marcando `api/src/worker.js` e `api/v4.9.183.js` como `-text`. O escopo é restrito de
propósito, os bundles anteriores já estão gravados em LF e reescrevê-los sairia caro sem ganho.

Efeito colateral aceito. Com o `\r` preservado, `git diff --check` reporta espaço à direita em
toda linha desses dois caminhos. Não é defeito, é a consequência de escolher fidelidade de
bytes. Para eles o portão de integridade é o SHA-256 contra `/content/v2`, não o verificador de
espaços. Ao validar staging, exclua os dois caminhos do `--check` e confira o resto.

## Critério de equivalência para versões futuras

Um artefato só é equivalente ao publicado quando as três condições valem ao mesmo tempo.

1. O SHA-256 do arquivo gerado por `build-worker.ps1` é igual ao SHA-256 do módulo extraído de
   `/content/v2`, comparando as duas formas na mesma convenção de quebra de linha. A publicação
   usa `no_bundle = true`, então a comparação byte a byte é válida. Sem `no_bundle` o Wrangler
   reempacota e a comparação perde sentido.
2. A superfície pública se mantém em `export { EstadoSemanaDO, RateLimiterDO, worker_default as default }`.
3. Os bindings de `api/wrangler.toml` seguem presentes, `RADAR_KV`, `RATE_LIMITER_DO`,
   `ESTADO_SEMANA_DO` e `RADAR_USAGE_EVENTS`, com `telemetria:true` no health pós-deploy.

## Ponteiro de deploy

`api/wrangler.toml` declarava `main = "v4.9.182.js"` mesmo com a v4.9.183 em produção.
Enquanto isso valeu, qualquer deploy disparado a partir do repositório republicava a v4.9.182
e revertia produção em silêncio. Corrigido no commit seguinte a esta preservação, que aponta
`main = "v4.9.183.js"` e acrescenta `no_bundle = true`.

O `no_bundle` não é acessório. Sem ele o Wrangler reempacota o arquivo antes de subir, os bytes
publicados deixam de ser os bytes do repositório, e o critério de equivalência por hash descrito
acima perde validade. Foi assim que a linhagem se perdeu na v4.9.99, quando cada publicação
acrescentava mais uma camada de wrapper sobre a anterior.

Com o ponteiro correto, um deploy a partir desta branch republica exatamente o que já está no
ar. O acidente destrutivo vira operação inócua.

## Correções que a v4.9.183 já entrega em produção

Verificado por leitura do módulo publicado, não por inferência.

- CAL-003. `obterTrimestresEmpresaMergedSync` passou a ser chamado no caminho do calendário,
  então os overrides gravados em KV aparecem em `op=calendario`.
- VOL-001. `market_cap` passou a ler o campo correto com guarda `> 0`, encerrando a confusão
  com preço por ação e a guarda invertida `> 100`.
- VOL-003. O literal `0.1375` não existe mais. A SELIC vem de `volatilidadeKV.selic_anual` com
  validação de faixa e cai para `null` quando não há dado fresco. O Merton só roda com SELIC
  presente, sem substituto inventado.
