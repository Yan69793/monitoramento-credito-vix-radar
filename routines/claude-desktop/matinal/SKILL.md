---
name: vixradar-matinal
description: VIX Radar matinal: analisa top 15 emissores por EWS e submete ao Worker (seg-sex 10h BRT)
---

Rotina VIX Radar MATINAL. Analisa os 15 emissores de maior EWS e submete ao Worker.

## Modo de comunicacao

Ative /caveman (nivel full) para TODA narracao sua, updates de progresso e o relatorio final. Terse, sem filler.

CAVEMAN NAO SE APLICA A DADOS. Os campos abaixo vao para o produto final, visiveis ao usuario no card do VIX Radar. Escreva-os em portugues normal, completo, com acentuacao correta:
- `cobertura_nota`
- `memo_acontecimento`, `memo_importancia_credito`, `memo_monitorar`
- `titulo`, `evento`, `impacto_credito`
Comprimir esses campos corrompe a entrega. Caveman e so para falar comigo.

## Contexto

Projeto: `E:\Diretorio\Claude\Monitoramento de Credito`
Worker: `https://api.vixradar.com` (POST, Content-Type application/json; charset=utf-8)

Esta rotina roda nesta sessao do Claude Desktop. Ela substituiu a Windows Scheduled Task `VIXRadar-Matinal`, que foi desabilitada em 04/08/2026 porque o `claude` CLI standalone parou de autenticar. NAO chame `run_vixradar_matinal_claude.ps1`, ele depende do CLI quebrado. Use PowerShell apenas para HTTP e arquivo, a analise e voce que faz, com WebSearch.

## Passo 0 - Guarda anti-duplicidade

A task nativa `VIXRadar-Matinal` do Windows Task Scheduler tem que ficar `Disabled`, esta sessao e o unico caminho de execucao. Ela ja voltou a `Ready` sozinha uma vez (04/08/2026, causa nao identificada) e ficou assim por 3 dias sem ninguem notar. Confirme e corrija a cada execucao, no inicio, antes do health check:

```powershell
try { Disable-ScheduledTask -TaskName "VIXRadar-Matinal" -ErrorAction Stop | Out-Null } catch {}
```

Idempotente, nao falha se a task ja estiver `Disabled` ou ausente. Nao aborte a rotina se este passo falhar, so registre no log e siga.

Desde 17/08/2026 existe retry automatico: a task `Szuchmacher-RetryVixMatinal` (13:30, dias uteis) relanca esta skill via `claude` CLI quando o log do dia nao tem FIM valido. O lock e o mutex deste Passo 0 protegem o retry de duplicar execucao viva; nao crie outra guarda.

## Passo 1 - Feriado

Se hoje for feriado B3, registre SKIP no log e encerre. Lista 2026:
2026-01-01, 2026-02-16, 2026-02-17, 2026-04-03, 2026-04-21, 2026-05-01, 2026-06-04, 2026-09-07, 2026-10-12, 2026-11-02, 2026-11-15, 2026-11-20, 2026-12-25
Fim de semana ja e tratado pelo cron.

## Passo 2 - Health check

GET `https://api.vixradar.com`. Exija SOMENTE `bindings.kv:true` e `bindings.telemetria:true`. Se um dos dois for falso, aborte e reporte, nao tente analisar.

NAO bloqueie pelo campo `ok` agregado. Ele inclui `verificador_ok`, `sentry_ok` e Resend, que nao tem
relacao com o trabalho desta rotina (busca web + submit via `receber_analise`). A noturna abortou por
isso em 03/07/2026 e de novo em 07/08/2026, com `kv` e `telemetria` ambos true. Mesma armadilha aqui.
O `run_vixradar_matinal_claude.ps1` e o `run_vixradar_noturno_claude.ps1` (linha ~504) ja tratavam isso,
a correcao se perdeu na migracao para o Claude Desktop.

Registre a linha completa do health no log, incluindo `ok` e `verificador_ok`. Registrar sim, abortar
por eles nao.

## Passo 3 - Chave

A chave esta em `$env:ROUTINE_API_KEY` (escopo User, ja persistida na maquina). Leia direto da variavel dentro do comando PowerShell.
NUNCA imprima, ecoe ou escreva a chave em log, resposta ou arquivo. Se a variavel estiver vazia, aborte e me diga, nao invente nem procure a chave em outro lugar.

## Passo 4 - Plano

POST body: `{"action":"listar_plano_rotina","routine_key":"<chave>","modo":"matinal","top_n":15}`
Se `ok` nao for true, aborte. Se `total` for 0, encerre limpo. Se `total` != 15, siga mas registre o aviso.

Cada emissor traz: `empresa, setor, tier, motivos, rodadas, ews_score, cvm_novos, cvm_documentos, contexto_historico, janela_inicio, janela_fim`.
Tudo que voce precisa ja vem aqui. NAO chame `dados_para_analise`.

### Feed bulk da CVM escuro (CVMURL404, 2026-08-24)

No health, olhe `cvm_fonte_falha_dura`. Quando for `true`, o Worker nao esta conseguindo
baixar o ZIP do ano corrente da CVM, entao `cvm_novos` e `cvm_documentos` vem congelados
na ultima carga boa. Foi o que travou o painel em 20/08/2026 por 4 dias.

Nesse estado, **ausencia de documento novo nao significa ausencia de fato novo**.
Registre no log:

```
FONTE_CVM_ESCURA: cvm_fonte_falha_dura=true motivo=<cvm_fonte_motivo> ultimo_bom=<cvm_fonte_ultimo_sync_ok_em>
```

E busque imprensa e `rad.cvm.gov.br` para todo emissor da fila, inclusive os que estao
com `cvm_novos=0`. A rotina segue, nao aborta.

## Passo 5 - Idempotencia

Log do dia: `E:\Diretorio\Claude\Monitoramento de Credito\logs\routines\vixradar-matinal_<yyyyMMdd>.log` (ex: vixradar-matinal_20260804.log).

Se o arquivo existe, leia as linhas que casam `^[\d-]+ [\d:]+ OK\|([^|]+)\|` e extraia os nomes ja processados. Pule esses emissores, ja foram submetidos hoje. Compare nomes ignorando acentuacao.

Escreva cada linha de log no formato `yyyy-MM-dd HH:mm:ss <mensagem>`, UTF8, append. Comece com a linha `INICIO: matinal top=15 (sessao agendada Claude Desktop)`.

## Passo 6 - Emissores tier SKIP

Emissor com `tier == "SKIP"` NAO precisa de busca nem analise. Submeta direto:

```
resultado = {
  "empresa": <empresa>, "setor": <setor>, "sem_eventos": true,
  "cobertura_nota": "Tier SKIP. CVM: <resumo dos cvm_documentos>. <cvm_novos> novos. Motivos: <motivos separados por virgula>.",
  "fontes_consultadas": [{"rodada":"0","query":"Worker plano","resultado":"<resumo cvm>"}],
  "eventos": [], "_tier": "SKIP", "_rotina_v2": true
}
```
Se o submit falhar, espere 2s e tente 1 vez mais.

## Passo 7 - Filas e ordem

Dos emissores restantes (tier != SKIP, nao processados hoje):
- Fila APROFUNDADA: `tier == "FULL"` E (`ews_score >= 38` OU `cvm_novos > 0`). Ordene por ews_score desc, depois cvm_novos desc. Processe PRIMEIRO, em grupos de 4.
- Fila RAPIDA: todo o resto. Processe depois, em grupos de 6.

## Orcamento de tokens

Meta 120000 tokens (120k). Hard cap 180000 tokens (180k). Herdado do desenho original, onde a fila aprofundada rodava em Sonnet e a rapida em Haiku.

Voce nao tem contagem exata de tokens nesta sessao. Use o orcamento como envelope de custo, nao como numero a medir. Sinais praticos de que esta perto do teto: muitas buscas por emissor alem do maximo permitido, retomada repetida do mesmo lote, ou contexto claramente saturado.

Chegando la, PARE de analisar e defira o que sobrou em vez de submeter analise vazia:

```
resultado = {
  "empresa": <empresa>, "setor": <setor>, "sem_eventos": true,
  "cobertura_nota": "Tier <tier>. Cap de sessao - ledger minimo. EWS=<ews_score>. Priorizar amanha.",
  "fontes_consultadas": [{"rodada":"0","query":"token_cap","resultado":"deferred"}],
  "eventos": [], "_tier": <tier>, "_rotina_v2": true, "_token_cap_deferred": true
}
```
com `"provedor":"claude-cap-deferred"`. Registre no log quantos foram deferidos.

Respeitar o maximo de buscas por emissor e o que mantem o custo dentro do envelope. Nao estoure o limite de buscas para "melhorar" a analise.

## Passo 8 - Analise (WebSearch)

R7 (auditoria 19/08/2026): reforco preventivo, nao correcao de caso comprovado. A investigacao original (rotina
noturna) suspeitou que a Copasa tinha perdido um voto de privatizacao na Assembleia de MG datado de 17/08/2026 -
R2 busca por palavra de credito e nao cobre naturalmente noticia legislativa/regulatoria, e R6 so dispara com
ews_score>=20, entao emissor de risco baixo nesses 3 setores nunca aciona o cross-check. Antes de gravar qualquer
coisa em producao, a data foi verificada na fonte primaria (site da ALMG): a votacao foi em 17/12/2025, oito meses
antes, sem ligacao com agosto de 2026. O achado era o resumo da propria busca colando o dia certo (17) no mes
errado. R7 entra mesmo assim, autorizado pelo operador, como cobertura preventiva do buraco metodologico real, nao
porque exista caso perdido comprovado. Mesmo escopo e mesma logica da rotina noturna, para as duas nao divergirem
como ja divergiram no passado (formato da linha FIM). R2 e R6 ficam com a definicao exatamente como estava.

Fila RAPIDA, max 2 buscas por emissor (3 nos setores abaixo, ver R7):
- R2 sempre: noticias de credito do emissor (rating, divida, default, covenant, M&A, resultado).
- R6 so se R2 trouxe sinal CRITICO/RELEVANTE, ou ews_score >= 20, ou cvm_novos > 0: cross-check de rating/regulatorio.
- R7 (estrutura societaria: privatizacao, mudanca de controle, intervencao legislativa ou regulatoria): roda SEMPRE, alem de R2, quando setor for Energia Eletrica, Saneamento ou Transportes e Logistica, independente do ews_score. Fora desses 3 setores, R7 nao roda por padrao.
- R2 limpo em emissor de EWS baixo: classifique ECO ou NENHUM com 1 busca e `cobertura_nota` de 1 frase; nos 3 setores acima, R7 conta como busca adicional antes de fechar ECO/NENHUM, nao substitui R2.

Fila APROFUNDADA, max 3 buscas por emissor: R2, R6, e R5 (covenants, rolagem, liquidez) SOMENTE se R2/R6 confirmaram evento CRITICO/RELEVANTE. Nos mesmos 3 setores do R7 acima, R7 roda sempre, contando dentro do orcamento de 3 buscas junto com R2 e adaptativo como as demais. Condicao do R5 fica igual, nao afetada pelo R7.

Emissor cujo `contexto_historico` ja indica CRITICO/REX/RJ/default: nao re-descubra o historico, busque so o delta na janela (`janela_inicio` a `janela_fim`).

Os `cvm_documentos` ja vem no plano. Nao rebusque CVM.

### Gate obrigatorio antes de criar evento CRITICO ou RELEVANTE

(a) `fonte_primaria` tem que ser URL profunda especifica: documento CVM com parametros, pagina de rating action, materia com slug. PROIBIDO dominio raiz, homepage, URL de resultado de busca ou link de download generico.

Evento de recuperacao judicial/extrajudicial, default ou rebaixamento: SEMPRE cheque `rad.cvm.gov.br` por Fato Relevante ou Comunicado ao Mercado do proprio protocolo na janela antes de fechar com fonte de imprensa. Achando, use o Fato Relevante como `fonte_primaria` com `fonte_tipo=CVM_FATO_RELEVANTE`, e a imprensa so como `fontes_consultadas` complementar. Nao achando, mantenha imprensa como fonte_primaria normalmente, nao bloqueie o evento.

(b) `data_evento` dentro da janela informada. Formato YYYY-MM-DD. Nunca "nao_identificada", use `data_aproximada: true`.

Sem URL primaria valida OU fora da janela: registre o achado em `cobertura_nota` como watchlist e NAO crie o evento.
CRITICO exige URL primaria sempre. ECO/NENHUM: `cobertura_nota` de 1 frase e `eventos: []`.

## Passo 9 - Formato do resultado

Um objeto por emissor, JSON compacto:

```
{"classificacao_geral":"CRITICO|RELEVANTE|ECO|NENHUM","sem_eventos":<bool>,"cobertura_nota":"...","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"...","resultado":"..."}]}
```

Cada evento em CRITICO ou RELEVANTE exige TODOS estes campos preenchidos: `classificacao`, `titulo`, `evento`, `impacto_credito`, `memo_acontecimento` (2-3 frases, o que aconteceu), `memo_importancia_credito` (por que importa para o credito), `memo_monitorar` (o que observar a seguir), `fonte_primaria` (URL), `fonte_tipo`, `data_evento`, `data_aproximada`, `tags`.

Os tres campos `memo_*` alimentam o card do usuario e o `contexto_historico` de amanha. Evento sem eles fica incompleto.

Em `fontes_consultadas`, o campo `resultado` deve descrever o que a busca retornou de fato. Se a busca falhou ou nao retornou nada, diga isso explicitamente ("indisponivel", "falha", "vazio").

## Passo 10 - Guarda de cobertura

Para cada emissor, conte as buscas efetivas: entradas de `fontes_consultadas` cujo `resultado` seja nao-vazio e NAO contenha "indisponivel", "falha", "erro", "nao executou", "timeout" nem seja apenas "vazio".

Se `tier == "FULL"` E buscas efetivas == 0 E a classificacao nao for CRITICO: degrade para INCONCLUSIVO. Ponha `sem_eventos: true` e, se `cobertura_nota` estiver vazia, escreva "Zero buscas efetivas - cobertura nao verificavel (falha de ferramenta ou modelo)." Registre WARN no log.

Nao confie em contagem autodeclarada de buscas. Conte voce, a partir de `fontes_consultadas`.

## Passo 11 - Submit

Um POST por emissor, logo apos analisar cada grupo. NAO acumule tudo para o fim, submeta incremental para que uma falha no meio nao perca o trabalho ja feito.

Body: `{"action":"receber_analise","routine_key":"<chave>","empresa":<empresa>,"setor":<setor>,"_matinal":true,"provedor":"claude-sonnet-routine","resultado":<objeto do passo 9>}`

Use `"provedor":"claude-sonnet-routine"` para a fila APROFUNDADA e `"claude-haiku-routine"` para a RAPIDA.

Preserve a acentuacao do nome da empresa exatamente como veio no plano. Envie o corpo como UTF-8.

Apos cada submit bem-sucedido, escreva no log:
`OK|<empresa>|<tier>|<classificacao>|<n_eventos>|<true|false do submit>`

Essa linha e o ledger de idempotencia. Sem ela, uma re-execucao reprocessa o emissor.

## Passo 12 - Relatorio

Antes do relatorio, escreva no log a linha `FIM: matinal <N>/<TOTAL> processados.`, onde `<N>` = total de linhas `OK|` no log de hoje e `<TOTAL>` = emissores do plano. Formato exigido pelo watchdog `scripts/retry-vixradar.ps1`, que le o log as 13h30 e relanca a rotina inteira se nao achar um numero >=12 numa linha `FIM:`. Escreva SEMPRE, com esse formato exato, mesmo que o resto do relatorio va em caveman.

Este passo existe porque a matinal, ao contrario do noturno, nao tinha formato exigido e escreveu tres variantes em quatro dias: `19/19 emissores processados` (17/08), `20/20 processados` (18/08) e `19 emissores processados` (15/08, sem denominador). A de 17/08 nao casava com o parser e o watchdog relancou a rotina as 13h30 mesmo com os 19 emissores ja entregues, queimando uma sessao Claude Desktop a toa. O parser foi endurecido depois, mas a correcao de verdade e nao deixar o formato solto.

Depois da linha FIM, o relatorio e em caveman. Reporte: quantos emissores processados, quantos SKIP, quantos deferidos por cap, quantos por classificacao, quantos degradados para INCONCLUSIVO, total de buscas efetivas, e qualquer emissor que falhou submit. Liste os CRITICO com nome e uma linha do que aconteceu.

Se algo abortou, diga o que foi e em que passo, sem suavizar.