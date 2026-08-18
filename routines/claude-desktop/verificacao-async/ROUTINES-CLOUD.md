# VIX Radar — verificacao async cloud (Remote Routine)

Reescrito 2026-08-18 (segunda revisao, mesmo dia) contra o contrato real verificado direto no
codigo-fonte do Worker, incluindo o mecanismo de reserva atomica adicionado nesta mesma revisao
(`CONCORVERIF1`). A primeira revisao do dia ja tinha corrigido o payload e o criterio de health
em cima da versao de 20/07/2026 (obsoleta). Esta revisao muda dois pontos a mais: reserva real
via Durable Object no lugar de so recheck por HTTP, e o cap de lote subiu de 12 para 20 eventos
por execucao (capacidade recalculada contra fila real de 25 itens em 18/08, ver Passo 0).

Execucao autonoma em nuvem, Claude Code Routine (Remote). Sem PS1 local. Sem `claude -p`
aninhado. Sem guarda de Task Scheduler (nao existe nesse ambiente).

Esta rotina roda em paralelo com a sessao agendada do Claude Desktop (mecanismo local). As duas
coexistem de proposito: o Remote cobre as janelas em que o PC do operador esta desligado, e
soma capacidade real de drenagem, o local continua sendo o caminho principal quando a maquina
esta ligada.

WORKER_URL = `https://api.vixradar.com`
ROUTINE_KEY = ler da variavel de ambiente do Environment desta rotina (secret configurado no
painel `claude.ai/code`, nunca em texto puro neste arquivo, nunca logado, nunca ecoado).

## Passo 0 — Identidade, agendamento e por que o cap mudou

Identifique-se como `"origem":"remote"` em toda chamada ao Worker (heartbeat
`heartbeat:verificacao_async`, visivel no painel admin mesmo com o PC do operador desligado).

Gatilho: 02:00 e 14:00 BRT. Escolhidos para preencher a maior lacuna de cobertura do mecanismo
local (10:20 e 18:20 BRT, ~16h sem nenhum toque entre 18:20 e o dia seguinte), nao para espelhar
o horario local.

Cap por execucao: **20 eventos (5 lotes de 4)**, subiu de 12 (3 lotes) nesta revisao. Motivo,
com evidencia: em 18/08 a fila real chegou a 25 itens pendentes ANTES do noturno das 18h rodar
(que historicamente e o maior gerador de itens do dia — log de 17/08 mostra a fila indo de 20
para 20 depois de processar 12, porque chegaram 12 novos no meio da execucao). Com cap de 12 e
2 execucoes locais/dia, a capacidade teorica maxima era 24/dia, que os proprios logs mostram
insuficiente pra picos reais. Com cap de 20 e 4 execucoes/dia combinadas (2 local + 2 Remote),
a capacidade teorica sobe pra 80/dia, com folga real sobre o pior dia observado.

## Passo 1 — Health

GET `https://api.vixradar.com`

Exigir `bindings.kv == true` e `bindings.telemetria == true`. Se qualquer um dos dois for
falso, abortar e reportar.

**NAO abortar por `ok` agregado nem por `verificador_ok:false`, nunca, em nenhuma
circunstancia.** `verificador_ok` cai pra `false` exatamente quando ha item na fila ha mais de
12h, e drenar essa fila e a razao desta rotina existir. Abortar por esse campo trava a fila pra
sempre (incidente real de 07/08/2026, 11 itens presos, processamento zero).

Guarde o horario deste passo (ISO), vai como `inicio` no Passo 6.

## Passo 2 — Checar fila

POST `https://api.vixradar.com`
Body: `{"action":"listar_fila_verificacao","routine_key":"<ROUTINE_API_KEY do Environment>","origem":"remote"}`

Se `ok != true`: abortar e reportar. Se a fila vier vazia (`total: 0`): encerrar limpo, isso e
comportamento normal, nao erro. Esse check-in ja grava heartbeat no Worker mesmo com fila
vazia, nao precisa fazer nada alem de mandar o campo `origem`.

Dos itens retornados, selecione ate 20 (a fila pode ter mais, o resto fica pra proxima
execucao, local ou Remote, o que rodar primeiro).

## Passo 3 — Reservar antes de verificar (protecao de concorrencia real)

**Isto e novo nesta revisao (`CONCORVERIF1`, 18/08/2026) e nao e opcional.** Antes de gastar
qualquer busca adversarial num item, reserve-o:

POST `{"action":"reservar_itens_fila","routine_key":"<chave>","origem":"remote","itens":[{"id":"...","data_fila":"..."}, ...]}`
(um objeto por item selecionado no Passo 2, com `id` e `data_fila` de cada um)

A resposta tem 3 campos:
- `reservados`: ids que voce tem exclusividade pra processar agora (janela de 20 minutos).
- `ja_reservados`: ids que outra execucao (local ou Remote) reservou ha pouco. **Remova esses
  do lote, nao gaste verificacao neles, nao tente confirmar veredicto pra eles.**
- `protecao_ativa`: `true` se a reserva rodou de verdade (Durable Object disponivel), `false`
  se caiu no fallback sem protecao (raro). Se `false`, faca o recheck extra do Passo 5 antes de
  cada submit, ele e a rede de seguranca pra esse caso.

A reserva roda dentro do mesmo Durable Object que ja serializa o resto da fila
(`EstadoSemanaDO`, instancia por dia), por isso e atomica de verdade quando `protecao_ativa` e
`true`, ao contrario de uma simples releitura por HTTP.

## Passo 4 — Verificacao adversarial, ate 5 lotes de 4 (20 eventos)

Voce e o auditor factual adversarial, nao o autor original do evento. Ceticismo e o padrao, so
sobre os itens que vieram em `reservados` no Passo 3. Todas as 5 checagens abaixo tem que
passar pra `APROVADO`:

1. `fonte_primaria` e URL profunda especifica (documento CVM com parametros, pagina de rating
   action, materia com slug). Dominio raiz, homepage ou link generico reprova direto.
2. WebSearch/WebFetch confirma que o fato descrito em `evento.evento`/`evento.titulo`
   realmente aconteceu, na data declarada, com numeros e termos batendo. Fonte primaria (CVM,
   agencia de rating, comunicado oficial) pesa mais que imprensa secundaria. Maximo 3 buscas
   por evento, sem sinal de confirmacao apos isso, reprove por precaucao.
3. `data_evento` numa janela razoavel (ate 30 dias antes de hoje), ou `data_aproximada` ja
   sinalizava a incerteza e o resto confere.
4. Classificacao (`CRITICO`/`RELEVANTE`/`ECO`/`NENHUM`) proporcional ao que a fonte realmente
   diz. Evento inflado (ex: chamar de CRITICO algo que a fonte descreve como rotineiro)
   reprova.
5. `memo_acontecimento`, `memo_importancia_credito`, `memo_monitorar` presentes e coerentes
   com a fonte, exigido para CRITICO/RELEVANTE.

Qualquer checagem falhando: `REJEITADO` com `motivo` especifico (qual checagem falhou e por
que), em portugues completo — esse texto fica no registro do emissor, nao comprima.

Se sobrar fila depois de 5 lotes, registre quantos ficaram e encerre. A proxima execucao
(local as 10:20/18:20, ou esta Remote as 02:00/14:00, o que vier primeiro) continua.

## Passo 5 — Submeter via confirmar_verificacao

Campo do array e `itens`, **nao** `veredictos` (formato antigo, o Worker rejeita ou descarta
silenciosamente, `erros` incrementado, nada processado). Cada item ecoa de volta `id`,
`empresa`, `semana`, `data_fila`, `setor`, `evento` completo (tal como veio da fila), mais um
objeto `veredicto` aninhado:

```json
{
  "action": "confirmar_verificacao",
  "routine_key": "<ROUTINE_API_KEY do Environment>",
  "origem": "remote",
  "inicio": "<horario ISO do Passo 1>",
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

**Se `protecao_ativa` veio `false` no Passo 3**, reconfira cada id antes deste submit: POST
`{"action":"listar_fila_verificacao","routine_key":"<chave>","ids":[<ids do lote>]}` e remova
do lote qualquer id que nao aparecer mais em `itens` (ja foi processado por outra execucao). Se
`protecao_ativa` veio `true`, pode confiar na reserva e pular esse recheck.

Se `id`, `empresa`, `semana`, `data_fila` ou `veredicto` faltarem em um item, o Worker so
incrementa `erros` e segue sem processar aquele item, sem detalhar qual campo faltou. A
resposta so devolve contagens agregadas, nunca por item, entao monte o payload com cuidado.

Falha no submit do lote: esperar 2s, tentar 1 vez mais. Persistindo, registrar e seguir pro
proximo lote, nao travar a execucao inteira por um lote.

Apos remover um item da fila, `listar_fila_verificacao` pode devolver por alguns segundos o
total antigo (lag de propagacao do Durable Object). Nao tratar isso como falha.

## Passo 6 — Resumo final

Uma linha, formato:
`VERIFICACAO_ASYNC_RESUMO|origem=remote|total_fila_inicial|reservados|ja_reservados_outro|lotes_processados|aprovados|rejeitados|erros_submit|pendentes_proxima_execucao`

Evidencia legivel na sessao via `RemoteTrigger get_run_log`. Evidencia persistente no Worker:
`heartbeat:verificacao_async` (Passo 0/2) e o placar de cada confirmacao (Passo 5), visiveis no
painel admin mesmo com o PC do operador desligado.
