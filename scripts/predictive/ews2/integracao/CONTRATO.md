# Contrato de integração reversível do EWS 2.0 ao VIX Radar (preparado em 16/10/2026, NÃO ativado)

Estado: preparação. Nenhuma linha de `api/`, `app/`, rotina ou KV de produção foi alterada (G0-v1 item 11 proíbe
durante a validação). Este contrato, o adaptador puro `ews2_adapter.mjs` e os testes `node --test` ficam fora do
Worker até a homologação da base e a autorização do operador. Produto não mostra nada do EWS 2.0 antes do G4.

## Fluxo quando autorizado

1. O pipeline local (`scripts/predictive/ews2/backtest.py --real`) só roda com `guarda_treino` em exit 0
   (registro de homologação da base com G1a, G1b, G1c aprovados e sha256 do CSV de rótulos congelado).
2. Sinais aprovados em G2 e, se G3 passar, a probabilidade recalibrada entram em UM payload `ews2/1`
   (esquema no cabeçalho do adaptador), gravado na chave KV `ews2:latest` por script local autenticado com a
   `routine_key` existente, via action nova de escrita restrita ao admin (a definir na mudança do Worker, não aqui).
3. A flag `ews2:flag` nasce `{"ativo": false}`. Com ela desligada, `op=predictive_v1` devolve exatamente o que
   devolve hoje mais `ews2: {ativo:false, motivo}`. Nada muda para o consumidor.
4. Ligar a flag (decisão do operador, por script, nunca por deploy) faz `fundir(pv1, ews2, flag)` acrescentar
   `ews2` por emissor e no topo. Nenhum campo existente de `predictive_v1` é alterado (teste cobre).
5. `op=predictive_v1` continua sob `_exigeLabPreditivoAdmin`: só admin vê. Exposição ao usuário final é G4
   (6 meses de sombra, cada alerta gravado antes do evento), fora deste contrato.

## Ponto único de ligação no Worker (a fazer em PR própria, depois da autorização)

Em `op=predictive_v1` (api/src/worker.js, hoje linha ~20756), depois de ler `predictive_v1:latest`:
`const ews2 = await KV.get("ews2:latest","json"); const flag = await KV.get("ews2:flag","json"); return resp({...fundir(pv1, ews2, flag)})`.
Importação do adaptador como módulo do bundle (esbuild do Wrangler resolve). Teste em `api/test/ews2-adapter.test.mjs`
no padrão `@cloudflare/vitest-pool-workers`, mesma suíte do deploy. Deploy pelo `deploy-worker.ps1` como sempre.

## Rollback (três níveis, do mais barato ao mais caro)

1. `ews2:flag` para `{"ativo": false}` (efeito imediato, sem deploy). É o estado padrão.
2. Apagar `ews2:latest` (o adaptador devolve o payload original com motivo "payload invalido").
3. Deploy da versão anterior do Worker (`main = "v4.9.<anterior>.js"` em `wrangler.toml`), como em qualquer rollback.

## O que este contrato não cobre

Score, alerta, piso, classificação, e-mail ou tela do EWS atual. O EWS 2.0 não substitui o EWS atual antes do G4
e, mesmo então, só por decisão registrada do operador.
