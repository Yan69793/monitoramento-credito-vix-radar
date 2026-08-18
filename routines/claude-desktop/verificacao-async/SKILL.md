---
name: vixradar-verificacao-async
description: VIX Radar verificacao-async: drena fila de verificacao factual adversarial e submete veredictos ao Worker (10:20 e 18:20 BRT)
---

Rotina VIX Radar VERIFICACAO ASYNC. Drena a fila de eventos pendentes de verificacao factual adversarial e submete os veredictos ao Worker.

## Modo de comunicacao

Ative /caveman (nivel full) para TODA narracao sua, updates de progresso e o relatorio final. Terse, sem filler.

CAVEMAN NAO SE APLICA A DADOS. O campo `motivo` de cada veredicto vai pro estado do emissor e pode aparecer em auditoria futura. Escreva em portugues normal, completo, com acentuacao correta. Comprimir corrompe o registro.

## Contexto

Projeto: `E:\Diretorio\Claude\Monitoramento de Credito`
Worker: `https://api.vixradar.com` (POST, Content-Type application/json; charset=utf-8)

Esta rotina roda nesta sessao do Claude Desktop, mesmo padrao de vixradar-noturno e vixradar-matinal. Substitui a Windows Scheduled Task `VIXRadar-Verificacao-Async` e o script `run_vixradar_verificacao_async.ps1`, que dependiam do `claude` CLI standalone. O script tinha uma guarda (`Test-VixClaudeAmbienteLimpo`) que passou a abortar com exit 6 assim que o ambiente local ficou contaminado por um agregador nao-Claude. Rodando aqui dentro da sessao do Claude Desktop esse problema nao existe, a sessao ja e Claude genuino. NAO chame `run_vixradar_verificacao_async.ps1`. Use PowerShell apenas para HTTP e para a guarda do Passo 0.

Verificacao adversarial existe desde v4.9.146, quando `receber_analise` parou de chamar API paga por token pra eventos CRITICO/RELEVANTE. Em vez disso, o evento fica pendente em `radar:verif_fila:{data}` ate uma sessao Claude aprovar ou rejeitar com busca web ativa.

**Desde 18/08/2026 esta rotina tambem roda em paralelo como Claude Code Routine Remote** (02:00 e 14:00 BRT, prompt em `ROUTINES-CLOUD.md` nesta mesma pasta), cobrindo as janelas em que o PC do operador esta desligado. As duas execucoes (local e remote) competem pela mesma fila, por isso o Passo 3.5 abaixo (reserva atomica) e obrigatorio, nao opcional.

## Passo 0 - Guarda anti-duplicidade

A task nativa `VIXRadar-Verificacao-Async` do Windows Task Scheduler tem que ficar `Disabled`, esta sessao e o unico caminho de execucao LOCAL a partir de agora (a Remote e um caminho diferente, coexiste de proposito). Confirme e corrija a cada execucao, antes do health check:

```powershell
try { Disable-ScheduledTask -TaskName "VIXRadar-Verificacao-Async" -ErrorAction Stop | Out-Null } catch {}
```

Idempotente, nao falha se a task ja estiver `Disabled` ou ausente. Nao aborte a rotina se este passo falhar, so registre no log e siga.

## Passo 1 - Health check

GET `https://api.vixradar.com`. Exija `bindings.kv:true` e `bindings.telemetria:true`. Se um dos dois for falso, aborte e reporte.

NAO aborte por `verificador_ok:false`, nunca, em nenhuma circunstancia. Isto e regra permanente, nao
excecao de transicao. O Worker marca `verificador_ok:false` quando existe item na fila de verificacao ha
mais de 12h, e drenar essa fila e exatamente a razao de existir desta rotina. Abortar por esse campo cria
deadlock fechado: a fila enche, o health cai, a rotina se recusa a rodar, a fila nunca drena, o health
nunca sobe. Sem intervencao manual o sistema nao sai sozinho desse estado.

Pelo mesmo motivo nao use o campo `ok` agregado como criterio, ele carrega `verificador_ok` dentro.
Em 07/08/2026 a noturna abortou por causa disso, com `kv` e `telemetria` ambos true e 11 itens presos na
fila `radar:verif_fila:2026-08-06`. Zero emissores processados.

Registre a linha completa do health no log, incluindo `ok` e `verificador_ok`. Registrar sim, abortar por
eles nao.

## Passo 2 - Chave

A chave esta em `$env:ROUTINE_API_KEY` (escopo User, ja persistida na maquina). Leia direto da variavel dentro do comando PowerShell.
NUNCA imprima, ecoe ou escreva a chave em log, resposta ou arquivo. Se estiver vazia, aborte e me diga.

## Passo 3 - Checar fila

POST body: `{"action":"listar_fila_verificacao","routine_key":"<chave>","origem":"local"}`
Se `ok` nao for true, aborte. Se a fila vier vazia, registre `FILA_VAZIA` no log e encerre limpo, isso e comportamento normal, nao erro.

Guarde o horario deste passo (ISO), vai como `inicio` no Passo 7. O campo `origem` alimenta um heartbeat automatico no Worker (`heartbeat:verificacao_async`, mesmo mecanismo dos outros agentes vigiados pelo watchdog), voce nao precisa fazer nada alem de mandar o campo, a gravacao e do lado do Worker.

Dos itens retornados, selecione ate 20 (a fila pode ter mais, o resto fica pra proxima execucao).

## Passo 3.5 - Reservar antes de verificar (protecao de concorrencia real, 18/08/2026)

**Obrigatorio, nao pule mesmo se a fila estiver pequena.** Desde que a Remote Routine passou a rodar em paralelo (mesma fila, origens diferentes), reservar antes de gastar verificacao evita trabalho duplicado e veredicto conflitante silencioso. Antes de qualquer busca adversarial:

POST `{"action":"reservar_itens_fila","routine_key":"<chave>","origem":"local","itens":[{"id":"...","data_fila":"..."}, ...]}`
(um objeto por item selecionado no Passo 3, com `id` e `data_fila` de cada um)

Resposta:
- `reservados`: ids que voce tem exclusividade pra processar agora (janela de 20 minutos).
- `ja_reservados`: ids que a Remote (ou outra sessao local) reservou ha pouco. **Remova esses do lote, nao verifique, nao submeta veredicto pra eles.**
- `protecao_ativa`: `true` se rodou via Durable Object (protecao atomica de verdade). `false` no fallback raro sem DO — nesse caso, faca o recheck extra do Passo 6 antes de cada submit.

Isso roda dentro do mesmo Durable Object que ja serializa a fila (`EstadoSemanaDO`, instancia por dia), nao e uma releitura por HTTP, e atomico quando `protecao_ativa` vem `true`.

## Passo 4 - Log

Log do dia: `E:\Diretorio\Claude\Monitoramento de Credito\logs\routines\vixradar-verificacao-async_<yyyyMMdd>.log` (ex: vixradar-verificacao-async_20260807.log). UTF8, append, formato `yyyy-MM-dd HH:mm:ss <mensagem>`. Primeira linha: `INICIO: verificacao-async (sessao agendada Claude Desktop)`.

A fila e a propria idempotencia: item aprovado ou rejeitado sai dela via `confirmar_verificacao`, a proxima chamada de `listar_fila_verificacao` nao traz mais esse item. O log e so pra auditoria, nao precisa filtrar reprocessamento por ele.

## Passo 5 - Lotes e verificacao adversarial

Processe em lotes de 4 eventos, **maximo 5 lotes por execucao (20 eventos)** — subiu de 12 (3 lotes) em 18/08/2026, cap recalculado contra fila real de 25 itens vista no mesmo dia (ver `ROUTINES-CLOUD.md` Passo 0 pra evidencia completa). Processe so os itens que vieram em `reservados` no Passo 3.5. Se sobrar fila depois disso, registre quantos ficaram e encerre, a proxima execucao (local ou Remote, o que rodar primeiro) continua.

Por evento, voce e o auditor factual adversarial, nao o autor original do evento. Ceticismo e o padrao:
1. Confira `fonte_primaria` do evento. Precisa ser URL profunda especifica (documento CVM com parametros, pagina de rating action, materia com slug). Dominio raiz, homepage ou link generico reprova direto.
2. Busque (WebSearch/WebFetch) pra confirmar que o fato descrito em `evento.evento` e `evento.titulo` realmente aconteceu, na data declarada, com os numeros e termos declarados. Fonte primaria (CVM, agencia de rating, comunicado oficial) pesa mais que imprensa secundaria.
3. `data_evento` tem que estar numa janela razoavel (ate 30 dias antes de hoje). Fora disso, reprove ou aceite se `data_aproximada` ja sinalizava a incerteza e o resto confere.
4. Classificacao (CRITICO/RELEVANTE/ECO/NENHUM) tem que ser proporcional ao que a fonte realmente diz. Evento inflado (ex: chamar de CRITICO algo que a fonte descreve como rotineiro) reprova.
5. `memo_acontecimento`, `memo_importancia_credito`, `memo_monitorar` presentes e coerentes com a fonte, exigido para CRITICO/RELEVANTE.

Veredicto `APROVADO` exige as 5 checagens passando. Qualquer uma falhando, `REJEITADO` com `motivo` especifico (qual checagem falhou e por que), em portugues completo, isso fica no registro do emissor.

Maximo 3 buscas por evento. Sem sinal de confirmacao apos isso, reprove por precaucao, nao aprove por falta de evidencia contraria.

## Passo 6 - Submeter veredictos

**Atencao, formato abaixo confirmado contra o codigo-fonte do Worker (`api/src/worker.js`, handler `confirmar_verificacao`) em 18/08/2026. Versoes anteriores deste SKILL documentavam um formato plano (`veredictos:[{id,veredicto,motivo}]`) que o Worker rejeita ou aceita e descarta silenciosamente (`erros` incrementado, nada processado). Use exatamente o formato abaixo.**

O campo do array chama-se `itens`, nao `veredictos`. Cada item precisa ecoar de volta os campos que vieram de `listar_fila_verificacao` (`id`, `empresa`, `semana`, `data_fila`, `setor`, `evento` completo), mais um objeto `veredicto` aninhado (nao string solta):

```json
{
  "action": "confirmar_verificacao",
  "routine_key": "<chave>",
  "origem": "local",
  "inicio": "<horario ISO do Passo 3>",
  "itens": [
    {
      "id": "<id do evento, vindo de listar_fila_verificacao>",
      "empresa": "<empresa>",
      "semana": "<semana>",
      "data_fila": "<data_fila>",
      "setor": "<setor>",
      "evento": { "...": "objeto evento completo, tal como recebido na fila" },
      "veredicto": {
        "veredicto": "APROVADO|REJEITADO",
        "confianca": 0.0,
        "motivo": "...",
        "fontes_validas": ["https://..."]
      }
    }
  ]
}
```

Se `id`, `empresa`, `semana`, `data_fila` ou `veredicto` faltarem em um item, o Worker so incrementa `erros` e segue sem processar aquele item, sem detalhar qual campo faltou. A resposta so devolve contagens agregadas (`processados/aprovados/rejeitados/retratados/erros`), nunca por item, entao monte o payload com cuidado antes de enviar, nao va tentando por eliminacao.

**Se `protecao_ativa` veio `false` no Passo 3.5**, reconfira cada id antes deste submit: POST `{"action":"listar_fila_verificacao","routine_key":"<chave>","ids":[<ids do lote>]}` e remova do lote qualquer id que nao aparecer mais em `itens` (ja foi processado por outra execucao). Se `protecao_ativa` veio `true`, pode confiar na reserva e pular esse recheck extra.

Apos remover um item da fila, `listar_fila_verificacao` pode devolver por alguns segundos o mesmo total antigo (a remocao passa por um Durable Object com escrita assincrona, ha lag de propagacao). Nao trate isso como falha de remocao: se precisar confirmar a fila vazia, reconsulte depois de alguns segundos antes de declarar erro.

Falhou o submit do lote, espere 2s e tente 1 vez mais. Persistindo a falha, registre no log e siga pro proximo lote, nao trave a rotina inteira por um lote.

Apos cada submit bem-sucedido, log: `OK|<id>|<empresa>|<veredicto>`

## Passo 7 - Relatorio

Em caveman. Reporte: total na fila ao iniciar, quantos reservados vs ja_reservados por outra origem, quantos lotes processados, aprovados, rejeitados (com motivo resumido de cada rejeitado), erros de submit, quantos ficaram pendentes pra proxima execucao.

Se abortou, diga onde e por que, sem suavizar.
