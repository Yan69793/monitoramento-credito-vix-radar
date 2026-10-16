# Contrato de integração reversível do EWS 2.0 ao VIX Radar (modo sombra publicado em 16/10/2026, não ativado)

Estado atual: EWS2SHADOW1 implantado no Worker `v4.9.270` em 16/10/2026, somente no laboratório
administrativo `op=predictive_v1`, por autorização do operador. `ews2:flag` ausente no KV remoto (404):
integração desativada; nenhuma previsão experimental foi exposta, nem alterados EWS público, app ou rotinas.
O gate G1-eq passou (30/30), mas G1a/G1b/G1c/G2/G3/G4 e eficácia preditiva real seguem sem homologação.
Código: `api/src/worker.js` e pontes `api/{src/,}ews2_adapter.mjs`; rollback do Worker: `v4.9.269`.

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

## Ponto único de ligação no Worker (implementado em `v4.9.270`, somente admin)

Em `op=predictive_v1`, após autenticação administrativa e leitura de `predictive_v1:latest`, o Worker
lê as chaves `ews2:latest` e `ews2:flag` com fallback `null` e aplica `fundirEws2Lab` (fail-closed).
As pontes `api/src/ews2_adapter.mjs` e `api/ews2_adapter.mjs` apontam ao mesmo módulo canônico.
Teste de integração: `api/test/ews2-shadow.test.mjs` (5/5, Workers Vitest); suíte total 531/531.
Deploy oficial: `scripts/deploy-worker.ps1 -Version v4.9.270` (aprovado, produção e Git sincronizados).

## Rollback (três níveis, do mais barato ao mais caro)

1. `ews2:flag` para `{"ativo": false}` (efeito imediato, sem deploy). É o estado padrão.
2. Apagar `ews2:latest` (o adaptador devolve o payload original com motivo "payload invalido").
3. Deploy da versão anterior do Worker (`main = "v4.9.<anterior>.js"` em `wrangler.toml`), como em qualquer rollback.

## O que este contrato não cobre

Score, alerta, piso, classificação, e-mail ou tela do EWS atual. O EWS 2.0 não substitui o EWS atual antes do G4
e, mesmo então, só por decisão registrada do operador.
