---
name: vixradar-noturno
description: VIX Radar noturno: varre os 103 emissores e submete ao Worker (diario 10h BRT)
---

Rotina VIX Radar NOTURNO. Varre os 103 emissores e submete ao Worker.

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

Esta rotina roda nesta sessao do Claude Desktop. Ela substituiu a Windows Scheduled Task `VIXRadar-Noturno`, que foi desabilitada em 04/08/2026 porque o `claude` CLI standalone parou de autenticar. NAO chame `run_vixradar_noturno_claude.ps1`, ele depende do CLI quebrado. Use PowerShell apenas para HTTP e arquivo.

## Passo 0 - Guarda anti-duplicidade

A task nativa `VIXRadar-Noturno` do Windows Task Scheduler tem que ficar `Disabled`, esta sessao e o unico caminho de execucao. Ela ja voltou a `Ready` sozinha uma vez (04/08/2026, causa nao identificada) e ficou assim por 3 dias sem ninguem notar. Confirme e corrija a cada execucao, no inicio, antes do health check:

```powershell
try { Disable-ScheduledTask -TaskName "VIXRadar-Noturno" -ErrorAction Stop | Out-Null } catch {}
```

Idempotente, nao falha se a task ja estiver `Disabled` ou ausente. Nao aborte a rotina se este passo falhar, so registre no log e siga.

Desde 17/08/2026 existe retry automatico: a task `Szuchmacher-RetryVixNoturno` (21:30) relanca esta skill via `claude` CLI quando o log do dia nao tem FIM valido. O lock e o mutex deste Passo 0 protegem o retry de duplicar execucao viva; nao crie outra guarda.

Isso nao cobre tudo. Em 08/08/2026 o Cowork disparou `run_vixradar_noturno_claude.ps1` direto, por fora do Task Scheduler e desta sessao, no meio de uma varredura ja em andamento aqui. A segunda analise leu fonte mais velha e sobrescreveu 3 emissores (Rumo, Bradesco, Tupy) antes de ser corrigida manualmente. Rode o bloco abaixo logo apos o comando acima, antes do health check:

```powershell
$MutexName = 'Global\vixradar-noturno-v2'
$mutex = New-Object System.Threading.Mutex($false, $MutexName)
$mutexLivre = $mutex.WaitOne(0)
if ($mutexLivre) { $mutex.ReleaseMutex() }
$mutex.Dispose()

$LockFile = "E:\Diretorio\Claude\Monitoramento de Credito\logs\routines\vixradar-noturno_$(Get-Date -Format 'yyyyMMdd').lock"
$lockLivre = $true
if (Test-Path $LockFile) {
    $idadeMin = ((Get-Date) - (Get-Item $LockFile).LastWriteTime).TotalMinutes
    if ($idadeMin -lt 180) { $lockLivre = $false }
}

if ($mutexLivre -and $lockLivre) {
    "source=claude-desktop-skill`npid=$PID`ninicio=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $LockFile -Encoding UTF8
}
```

`$mutexLivre` falso significa que `run_vixradar_noturno_claude.ps1` esta rodando agora (mutex de longa data do proprio script, so enxerga outra copia dele mesmo). `$lockLivre` falso significa que outra execucao desta sessao ja esta em andamento ha menos de 3 horas. Qualquer um dos dois falso: aborte a rotina inteira aqui, registre no log qual dos dois bloqueou, e pare, sem health check, sem plano, sem subagente. Os dois livres: o lock acima ja foi criado e a rotina segue para o Passo 1.

O threshold de 3h e folga generosa acima do tempo normal de execucao (o orcamento de tokens do Passo 6 limita isso a bem menos). Em QUALQUER saida da rotina depois deste ponto, sucesso no Passo 11 ou aborto em qualquer passo seguinte, rode `Remove-Item $LockFile -Force -ErrorAction SilentlyContinue`. Esquecer nao trava para sempre, o lock se autolimpa sozinho apos 3h, so atrasa uma tentativa manual no mesmo dia.

## Arquitetura desta rotina

Sao 103 emissores, nao cabem num contexto so. Voce e o ORQUESTRADOR:
- Voce chama o Worker, monta os lotes, submete os resultados e escreve o log.
- Subagentes (`Agent`, subagent_type `general-purpose`) fazem a analise de cada lote com WebSearch e devolvem as linhas `RESULTADO|`.
- Subagente NAO submete nada. Nao chama curl, nao faz POST. Quem grava e voce.

Isso espelha o desenho original, onde cada lote rodava num processo separado.

## Passo 1 - Health check

GET `https://api.vixradar.com`. Exija SOMENTE `bindings.kv:true` e `bindings.telemetria:true`. Se um dos dois for falso, aborte e reporte.

NAO bloqueie pelo campo `ok` agregado. Ele inclui `verificador_ok`, `sentry_ok` e Resend, que nao tem
relacao nenhuma com o trabalho desta rotina (busca web + submit via `receber_analise`). Isso ja derrubou
a noturna duas vezes:

- 03/07/2026, os 103 emissores abortados porque `ok:false` vinha de saldo Anthropic do verificador.
- 07/08/2026, abortou de novo com `kv=true telemetria=true` e `verificador_ok=false`, causado por 11
  itens parados na fila `radar:verif_fila:2026-08-06` ha mais de 12h. Zero emissores processados.

O script `scripts/run_vixradar_noturno_claude.ps1` (linha ~504) ja carregava essa correcao com o
comentario explicando o incidente de 04/07. A migracao para o Claude Desktop reescreveu este passo e
trouxe o bug de volta. Nao reintroduza `ok:true` aqui.

Registre no log a linha completa do health, incluindo `ok` e `verificador_ok`, para diagnostico
posterior. Registrar sim, abortar por eles nao.

Nao ha skip de fim de semana nem feriado nesta rotina, ela roda todo dia.

## Passo 2 - Chave

A chave esta em `$env:ROUTINE_API_KEY` (escopo User, ja persistida na maquina). Leia direto da variavel dentro do comando PowerShell.
NUNCA imprima, ecoe ou escreva a chave em log, resposta, arquivo ou prompt de subagente. Se estiver vazia, aborte e me diga.

## Passo 3 - Plano

POST body: `{"action":"listar_plano_rotina","routine_key":"<chave>","modo":"noturno"}`
Sem `top_n`. Exija `ok:true` e `total == 103`. Se `total` divergir de 103, aborte e reporte o numero recebido, e sinal de problema no Worker.

Cada emissor traz: `empresa, setor, tier, motivos, ews_score, cvm_novos, cvm_documentos, contexto_historico, janela_inicio, janela_fim`.
Tudo que a analise precisa ja vem aqui. NAO chame `dados_para_analise`.

Extraia a janela do primeiro emissor (`janela_inicio`, `janela_fim`). Ela vai no cabecalho de todo prompt de subagente.

### Feed bulk da CVM escuro (CVMURL404, 2026-08-24)

No health do Passo 1, olhe `cvm_fonte_falha_dura`. Quando for `true`, o arquivo bulk
da CVM nao esta sendo baixado: o Worker nao consegue pegar o ZIP do ano corrente. Foi
o que aconteceu entre 23 e 24/08/2026, quando a CVM removeu `ipe_cia_aberta_2026.zip`
do servidor e o painel ficou 4 dias sem nenhum fato novo.

Nesse estado, `cvm_novos` e `cvm_documentos` vem congelados na ultima carga boa e
**ausencia de documento novo nao significa ausencia de fato novo**. Registre no log:

```
FONTE_CVM_ESCURA: cvm_fonte_falha_dura=true motivo=<cvm_fonte_motivo> ultimo_bom=<cvm_fonte_ultimo_sync_ok_em>
```

E mude a busca dos subagentes: nao trate `cvm_novos=0` como sinal de silencio do
emissor, busque imprensa e `rad.cvm.gov.br` normalmente para todo emissor da fila,
inclusive os que nao tem documento novo listado. A rotina segue, nao aborta.

O subagente NAO le esta secao, ele so recebe o cabecalho do Passo 7. Entao mudar a
busca dele nao e figura de linguagem, e uma troca literal de linha: o cabecalho tem
uma `LINHA FONTE CVM` com duas variantes e voce cola a variante FONTE CVM ESCURA
neste estado. Sem essa troca a guarda fica so no log e o subagente segue com a
instrucao de nao rebuscar CVM, que e o oposto do que este bloco pede.

Dia de fonte escura custa mais, porque todo emissor do lote ganha busca que nao
teria. Orce pelo topo da faixa observada, nao pela media.

## Passo 4 - Idempotencia

Log do dia: `E:\Diretorio\Claude\Monitoramento de Credito\logs\routines\vixradar-noturno_<yyyyMMdd>.log` (ex: vixradar-noturno_20260804.log). Este e o caminho fisico canonico desde a inversao da junction em 18/08/2026. O caminho antigo (prefixo FREQUENTE) ainda resolve por junction legada de compatibilidade, mas nao usar mais - usar sempre o caminho canonico acima.

Se o arquivo existe, leia as linhas que casam `^[\d-]+ [\d:]+ OK\|([^|]+)\|` e extraia os nomes ja processados. Pule esses emissores. Compare ignorando acentuacao. Aplique esse filtro TAMBEM aos emissores tier SKIP.

Log em `yyyy-MM-dd HH:mm:ss <mensagem>`, UTF8, append. Primeira linha: `INICIO: noturno 103 emissores (sessao agendada Claude Desktop)`.

## Passo 5 - Emissores tier SKIP

Nao precisam de busca nem subagente. Submeta direto:

```
resultado = {
  "empresa": <empresa>, "setor": <setor>, "sem_eventos": true,
  "cobertura_nota": "Tier SKIP. CVM: <resumo dos cvm_documentos>. <cvm_novos> novos. Motivos: <motivos separados por virgula>.",
  "fontes_consultadas": [{"rodada":"0","query":"Worker plano","resultado":"<resumo cvm>"}],
  "eventos": [], "_tier": "SKIP", "_rotina_v2": true
}
```
Falhou o submit, espere 2s e tente 1 vez mais.

## Passo 6 - Lotes e ordem

Dos restantes (tier != SKIP, nao processados hoje), ordene cada fila por `ews_score` desc ANTES de lotear. O corte de orcamento sempre cai na cauda, e com a fila ordenada essa cauda e de ews 0-1, nao de nome que importa.

- Fila RAPIDA: todos que NAO se qualificam para a aprofundada. Lotes de ate 15. Processe PRIMEIRO.
- Fila APROFUNDADA: `tier == "FULL"` E (`ews_score >= 38` OU `cvm_novos > 0` OU `motivos` conter `imprensa_recente_7d`). Lotes de ate 16. Processe DEPOIS.
  O `imprensa_recente_7d` vem do Worker (FONTELATENCIA1, decisao do operador em 21/08/2026): evento CRITICO/RELEVANTE na imprensa ou de rotina anterior promove para aprofundada na mesma semana, sem esperar o ZIP semanal da CVM.

Lote cheio e mais barato que lote pequeno, o custo e quase todo boot fixo de subagente (ver `Orcamento de tokens`). Dividir a mesma fila em mais lotes so multiplica boot. Encha o lote ate o teto antes de abrir o proximo. O teto de 16 na aprofundada e limite de contexto do subagente, nao de custo, medido em 25/08/2026: 16 emissores com ate 3 buscas cada couberam num lote so, 39 chamadas de ferramenta, sem truncar e sem perder emissor. Nao subir acima de 16 sem medir de novo.

A ordem importa, rapida antes de aprofundada. Se a sessao degradar no meio, o que sobra e a fila cara, que voce defere no passo 10. Isso NAO autoriza deferir a fila aprofundada inteira para caber mais lote rapido, ela e curta e concentra os ews altos. Reserve o custo dela primeiro, conforme a regra de decisao do `Orcamento de tokens`.

Um subagente por lote. Rode no maximo 3 subagentes em paralelo, para nao saturar WebSearch.

Para cada lote, decida o caminho do arquivo de saida ANTES de disparar o subagente: diretorio scratchpad desta sessao (nunca o repo git), nome `out_rapida_<n>.txt` ou `out_aprofundada_<n>.txt`, `<n>` = ordem do lote na fila. Passe esse caminho absoluto no prompt do subagente (Passo 7). O subagente nao escolhe o proprio nome de arquivo.

NUNCA reabra um subagente apos o retorno (via SendMessage ou qualquer outro mecanismo) so para gravar linhas em arquivo. Reabrir um subagente custa o replay do transcript inteiro - medido em 17/08: +142260 tokens em UM lote, preco equivalente ao da analise original, e foi isso que estourou o orcamento daquele dia. Se o arquivo de saida voltou ausente, vazio ou incompleto, extraia as linhas RESULTADO| do RETORNO do subagente e grave-as voce mesmo no arquivo com Add-Content via PowerShell.

## Orcamento de tokens

Meta 500000 tokens (500k). Soft cap operacional 700000 tokens (700k). Tolerancia maxima 725000 tokens (725k).

Os tres numeros nao sao sinonimos. 500k e o alvo. 700k e o teto de DECISAO, nunca dispare deliberadamente um lote cuja estimativa leve o acumulado acima disso. 725k e so a folga que absorve o erro de estimativa de um lote JA disparado, porque o `subagent_tokens` so fica conhecido quando o subagente volta e ate la voce ja esta comprometido com o gasto. Tolerancia nao e permissao. Passar de 700k por escolha e violacao, passar por overshoot de lote em voo e o custo previsto de nao saber o numero antes.

**O custo e por LOTE, nao por emissor.** Orce com `130000 x numero_de_lotes + 5000 x numero_de_emissores`.

Medido em 25/08/2026, quatro lotes reais, pelo campo `subagent_tokens` que a sessao recebe no retorno de cada subagente, mesma regua que consome o orcamento:

| Lote | Emissores | Chamadas de ferramenta | Custo |
|---|---|---|---|
| rapida_3 | 8 | 24 | 147565 |
| rapida_2 | 15 | 27 | 162612 |
| rapida_1 | 15 | 45 | 199815 |
| aprofundada_1 | 16 | 39 | 208325 |

Resolvendo os dois lotes de busca leve, 8 e 15 emissores, sai boot de 130365 por lote e 2150 por emissor. Os outros dois mostram de onde vem a variancia real, e nao e do tamanho do lote. rapida_1 e rapida_2 tem 15 emissores cada e custaram 37k de diferenca, com 45 contra 27 chamadas de ferramenta. Profundidade de busca e que move o numero. Por isso a formula usa marginal de 5000 e nao 2150, e folga deliberada. Ela cobre os quatro pontos medidos, 170k sobre 147,6k, 205k sobre 199,8k e 210k sobre 208,3k.

A calibragem anterior dizia 15000 fixos mais 9500 por emissor na rapida e 13000 na aprofundada. Estava invertida, subestimava o fixo em quase 9 vezes e superestimava o marginal, e acreditar nela leva a quebrar a fila em muitos lotes pequenos, que e o jeito mais caro de rodar. Os tamanhos 15 e 11 do texto antigo vinham do desenho original em Haiku e Sonnet, que e historia de modelo, nao medicao de custo.

**Regra de decisao antes de disparar cada lote:**

Calcule uma vez, no inicio, a `reserva_aprofundada` = `130000 x lotes_aprofundada + 5000 x emissores_aprofundada`. Ela cobre a fila aprofundada inteira e so diminui conforme lote APROFUNDADO e executado, nunca conforme lote rapido roda.

1. Antes de cada lote RAPIDO, exija as duas condicoes ao mesmo tempo:
   - `restante_do_cap >= 130000 + 5000 x tamanho_do_lote`
   - `restante_do_cap - custo_estimado_do_lote_rapido >= reserva_aprofundada_ainda_nao_executada`
   Falhando qualquer uma, NAO dispare o lote rapido. Pare a fila rapida ali e defira o resto dela conforme o passo 10.
2. Antes de cada lote APROFUNDADO, so a primeira condicao. A reserva ja era dele.
3. Depois que a fila aprofundada inteira tiver sido executada, `reserva_aprofundada_ainda_nao_executada` e zero e a segunda condicao deixa de morder sozinha.
4. `restante_do_cap` = 700000 menos o acumulado REALIZADO, a soma dos `subagent_tokens` que ja voltaram. Nunca menos a soma das estimativas.
5. Com a fila ordenada por ews desc no Passo 6, a cauda deferida e sempre a de menor risco.

A segunda condicao do item 1 e o que impede o modo de falha obvio, que e queimar o cap inteiro em lote rapido e chegar na aprofundada sem orcamento, deferindo justamente os ews mais altos. Como a rapida roda PRIMEIRO, sem essa guarda a reserva nao sobrevive.

Voce nao tem contagem exata durante a sessao, mas TEM o custo real de cada lote depois que ele volta, no `subagent_tokens` do retorno. Some conforme os lotes fecham e decida o proximo com o acumulado real, nao com a estimativa.

**Consequencia estrutural do cap.** Pela formula conservadora cabem uma aprofundada de 16 e dois lotes rapidos de 15, ou seja 46 emissores por cerca de 620000 estimados. O terceiro lote rapido levaria a estimativa a 825000 e por isso nao pode ser disparado.

Em 25/08 sairam 54 analisados fechando em 718317 realizados, e isso NAO desmente o paragrafo acima. Aconteceu porque o custo realizado veio abaixo da estimativa conservadora, nao porque 700k comprem 50 a 55 emissores. Pela regra de decisao acima o terceiro lote rapido daquele dia nao teria sido disparado, a condicao de reserva reprovava (restante 337573 menos 205000 estimados = 132573, abaixo da reserva de 210000), e a entrega teria sido 46 analisados por cerca de 571000 realizados. Nao planeje contando com essa folga. Ela existe do lado da estimativa, nao do lado do compromisso, e so aparece depois que o lote ja voltou.

Cobrir os 81 nao-SKIP num dia exigiria perto de 1,2 milhao. Subir ou nao o cap e decisao do operador, nao do agente.

Respeitar o maximo de buscas por emissor e o que mantem o custo dentro do envelope. Nao estoure o limite de buscas para "melhorar" a analise.

## Passo 7 - O que mandar para o subagente

Para cada emissor do lote, envie SO estes campos: `empresa, setor, tier, motivos, ews_score, cvm_novos, cvm_documentos` (max 3 docs, com categoria, assunto truncado em 100 chars, data, link) e `contexto_historico` truncado (400 chars se ews_score >= 38 ou o texto casar REX/RJ/recuperacao/default/CRITICO, senao 200).

Nunca inclua a routine_key no prompt do subagente.

R7 (auditoria 19/08/2026): reforco preventivo, nao correcao de caso comprovado. A investigacao original suspeitou
que a Copasa tinha perdido um voto de privatizacao na Assembleia de MG datado de 17/08/2026 - o R2 busca por
palavra de credito (rating, divida, default, covenant) e nao cobre naturalmente noticia legislativa/regulatoria, e
R6 so dispara com ews_score>=20, entao emissor de risco baixo nesses 3 setores nunca aciona o cross-check. Antes
de gravar qualquer coisa em producao, a data foi verificada na fonte primaria (site da ALMG): a votacao foi em
17/12/2025, oito meses antes, sem nenhuma ligacao com agosto de 2026. O "achado" era o resumo da propria busca
colando o dia certo (17) no mes errado, mesma falha ja vista com outro emissor na mesma investigacao. R7 entra
mesmo assim, autorizado pelo operador, como cobertura preventiva do buraco metodologico real (privatizacao,
mudanca de controle, intervencao legislativa fogem do vocabulario de R2/R6), nao porque exista caso perdido
comprovado. Escopo restrito aos 3 setores estruturalmente expostos, para nao estourar o orcamento dos outros 2/3
dos emissores, que hoje fazem so 1 busca. R2 e R6 ficam com a definicao exatamente como estava.

LINHA FONTE CVM. O cabecalho abaixo tem o marcador `<LINHA FONTE CVM>`. Substitua por UMA
das duas linhas, conforme o `cvm_fonte_falha_dura` lido no Passo 1. Nunca as duas, nunca
nenhuma, e nunca deixe o marcador cru chegar ao subagente.

- `cvm_fonte_falha_dura=false`, fonte saudavel, comportamento de sempre:

```
Dados CVM ja vem no JSON, nao rebuscar CVM.
```

- `cvm_fonte_falha_dura=true`, fonte escura (CVMURL404, ver Passo 3):

```
FONTE CVM ESCURA: o feed bulk da CVM esta fora do ar e os campos cvm_novos e cvm_documentos vieram congelados na ultima carga boa. cvm_novos=0 NAO significa silencio do emissor, significa que a fonte parou de publicar para todo mundo. Para TODO emissor deste lote, inclusive os sem documento novo listado, faca a busca de imprensa normalmente e cheque rad.cvm.gov.br por Fato Relevante ou Comunicado ao Mercado dentro da janela. A lista de documentos que veio no JSON continua valida, so nao esta completa, entao nao a use para concluir ausencia de evento.
```

Cabecalho do prompt do subagente, literal:

```
JANELA: <janela_inicio> a <janela_fim>

BUSCAS por emissor (WebSearch).
[fila RAPIDA]  R2 sempre (noticias de credito: rating, divida, default, covenant, M&A, resultado). R6 (cross-check rating/regulatorio) SOMENTE se R2 trouxe sinal CRITICO/RELEVANTE, ou ews_score>=20, ou cvm_novos>0. R7 (estrutura societaria: privatizacao, mudanca de controle, intervencao legislativa ou regulatoria) roda SEMPRE, alem de R2, quando setor for Energia Eletrica, Saneamento ou Transportes e Logistica - independente do ews_score, porque R6 exige ews_score>=20 e por isso nao cobre emissor de risco baixo nesses 3 setores. Fora desses 3 setores, R7 nao roda por padrao. R2 limpo em emissor de EWS baixo: classificar ECO/NENHUM com 1 busca e cobertura_nota de 1 frase; nos 3 setores acima, R7 conta como busca adicional antes de fechar ECO/NENHUM, nao substitui R2.
[fila APROFUNDADA]  max 3 buscas, adaptativas. R2 primeiro. R6 se R2 trouxe sinal ou ews_score>=38. Nos mesmos 3 setores (Energia Eletrica, Saneamento, Transportes e Logistica), R7 roda sempre, contando dentro do orcamento de 3 buscas junto com R2 e adaptativo como as demais. R5 (covenants, rolagem, liquidez) SOMENTE se R2/R6 confirmaram evento CRITICO/RELEVANTE.

<LINHA FONTE CVM>
Emissor cujo contexto_historico indica CRITICO/REX/RJ/default: NAO re-descobrir o historico, buscar so o delta na janela.

EVENTOS - gate obrigatorio antes de criar evento CRITICO/RELEVANTE:
(a) fonte_primaria = URL profunda especifica (documento CVM com parametros, pagina de rating action, materia com slug).
    PROIBIDO: dominio raiz, homepage, URL de resultado de busca, link de download generico.
    Evento de recuperacao judicial/extrajudicial, default ou rebaixamento: SEMPRE checar rad.cvm.gov.br por Fato
    Relevante/Comunicado ao Mercado do proprio protocolo na janela antes de fechar com fonte de imprensa. Achando,
    usar o Fato Relevante CVM como fonte_primaria (fonte_tipo=CVM_FATO_RELEVANTE); imprensa so como fontes_consultadas
    complementar. Sem Fato Relevante localizavel, manter imprensa como fonte_primaria normalmente (nao bloquear o evento).
(b) data_evento dentro da JANELA. Datas YYYY-MM-DD; nunca "nao_identificada" (usar data_aproximada:true).
Sem URL primaria valida OU fora da janela: registrar em cobertura_nota (watchlist) e NAO criar evento.
CRITICO exige URL primaria sempre. ECO/NENHUM: cobertura_nota 1 frase, eventos=[].
Evento CRITICO/RELEVANTE exige memo_acontecimento + memo_importancia_credito + memo_monitorar preenchidos - alimentam o card do usuario e o contexto_historico de amanha.

SAIDA: grave as linhas RESULTADO| e ANOTA| (uma por emissor, sem markdown, sem tabelas, sem backticks, sem narrativa) com a ferramenta Write, UTF-8, no arquivo <caminho absoluto definido pelo orquestrador para este lote>. Grave DENTRO desta mesma execucao, como ultimo passo antes de responder.
Depois de gravar, sua resposta final deve ser SO uma linha: "GRAVADO <numero de linhas RESULTADO> em <caminho>". Nao repita o conteudo das linhas RESULTADO| na resposta, o orquestrador le do arquivo.
NAO executar curl nem qualquer submit HTTP - o orquestrador grava no Worker.
Preservar a acentuacao exata do nome da empresa no RESULTADO|.

Formato (1 linha por emissor, JSON compacto sem quebras):
RESULTADO|<empresa exatamente como no JSON de entrada, com acentuacao identica>|{"classificacao_geral":"CRITICO|RELEVANTE|ECO|NENHUM","sem_eventos":true,"cobertura_nota":"...","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"...","resultado":"..."}]}

Campos obrigatorios por evento: classificacao, titulo, evento, impacto_credito, memo_acontecimento (2-3 frases, o que aconteceu), memo_importancia_credito (por que importa para o credito), memo_monitorar (o que observar a seguir), fonte_primaria (URL), fonte_tipo, data_evento, data_aproximada, tags.

Em fontes_consultadas, o campo resultado descreve o que a busca retornou de fato. Busca que falhou ou nao retornou nada: dizer explicitamente ("indisponivel", "falha", "vazio").

Escrever cobertura_nota, memo_* , titulo, evento e impacto_credito em portugues normal e completo. Nao comprimir, nao abreviar, esses campos sao vistos pelo usuario final.
```

## Passo 8 - Parse

Incidente 17/08/2026: o orquestrador deixou os subagentes devolverem as linhas RESULTADO na propria resposta e, para nao duplicar esse texto no seu contexto, depois reabriu cada um via SendMessage so para gravar em arquivo. Reabrir subagente relê o transcript inteiro, cada reabertura custou de 142k a 165k tokens, preco de uma analise nova so para salvar texto que ja existia. O unico lote que ja tinha recebido a instrucao de Write dentro da propria execucao (o que o Passo 7 agora exige sempre) saiu de graca. Nunca peca para o subagente gravar por fora depois, so dentro da execucao original.

Leia as linhas do ARQUIVO do lote (Read ou Get-Content), nao da resposta em texto do subagente, que agora e so a confirmacao curta "GRAVADO N em <caminho>". Extraia `^RESULTADO\|([^|]+)\|(\{.*\})$`. Case o nome com o emissor do plano ignorando acentuacao. Linhas `ANOTA|` sao so observacao, registre no log e siga.

Se disparou o subagente em background (`run_in_background: true`), espere o arquivo aparecer com um loop de polling em PowerShell (`Test-Path` a cada poucos segundos) ou pelo Monitor, nunca com a ferramenta Bash (roda Git Bash, o projeto usa so PowerShell). Se disparou em foreground, o arquivo ja existe quando a chamada retorna, va direto para o parse.

Arquivo ausente, vazio, ou com menos linhas RESULTADO do que emissores do lote: confira primeiro se as linhas aparecem na resposta em texto do subagente, fallback aceitavel se so o Write falhou. Achando la, extraia dali, sem reabrir o subagente. Emissor do lote que nao apareceu em nenhum dos dois lugares: rode UM retry so com os faltantes, pedindo de novo Write mais confirmacao curta. Persistindo a falta, submeta com fallback `classificacao_geral: "NENHUM"`, `sem_eventos: true`, `cobertura_nota: "Falha de parse do agente apos retry."` e registre no log.

Lote que voltou com ZERO linhas `RESULTADO` (nem no arquivo, nem na resposta): registre `silent_fail` no log. Nao trate como sucesso.

## Passo 9 - Guarda de cobertura

Para cada emissor, conte as buscas efetivas: entradas de `fontes_consultadas` com `resultado` nao-vazio e que NAO contenha "indisponivel", "falha", "erro", "nao executou", "timeout" nem seja apenas "vazio".

Se `tier == "FULL"` E buscas efetivas == 0 E a classificacao nao for CRITICO: degrade para INCONCLUSIVO. Ponha `sem_eventos: true` e, se `cobertura_nota` estiver vazia, escreva "Zero buscas efetivas - cobertura nao verificavel (falha de ferramenta ou modelo)." Registre WARN no log.

Nao confie em contagem autodeclarada. Conte voce, a partir de `fontes_consultadas`.

## Passo 10 - Submit

Um POST por emissor, logo apos processar cada lote. NAO acumule para o fim, submeta incremental.

Body: `{"action":"receber_analise","routine_key":"<chave>","empresa":<empresa>,"setor":<setor>,"_matinal":false,"provedor":"claude-haiku-routine","resultado":<objeto>}`

`"provedor":"claude-haiku-routine"` para a fila RAPIDA, `"claude-sonnet-routine"` para a APROFUNDADA.

Atencao: `_matinal` e `false` aqui. Enviar true contamina o estado da matinal.

Corpo em UTF-8, acentuacao do nome da empresa preservada exatamente como veio no plano.

Apos cada submit bem-sucedido (aceito pelo Worker):
`OK|<empresa>|<tier>|<classificacao>|<n_eventos>|<true|false do submit>|<SKIP|ANALISADO|DEFERIDO>`

O 6o campo `<SKIP|ANALISADO|DEFERIDO>` descreve o QUE aquele emissor realmente rendeu nesta rodada, e e o ledger de idempotencia. Use:
- `SKIP` — emissor ja analisado/atualizado hoje (idempotencia), nada novo a processar.
- `ANALISADO` — emissor com analise REAL submetida e aceita nesta execucao (eventos processados, nao vazio).
- `DEFERIDO` — emissor deixado para amanha por cap de tokens/degradacao de sessao (payload `_token_cap_deferred`), submetido apenas o marcador.
NUNCA trate o 6o campo como sinonimo de analise. `submit_ok`/valor `true` de submit significa que a gravacao foi aceita — pode esconder um DEFERIDO ou um SKIP. O numero de emissores REALMENTE analisados nesta sessao e o total de linhas com `ANALISADO`, nao o total de `OK|`.

### Deferimento

Se bater o orcamento de tokens, ou se a sessao estiver claramente degradando (lotes falhando em sequencia, contexto saturado, WebSearch indisponivel), pare de analisar e defira os emissores restantes em vez de submeter analise vazia:

```
resultado = {
  "empresa": <empresa>, "setor": <setor>, "sem_eventos": true,
  "cobertura_nota": "Tier <tier>. Cap de sessao - ledger minimo. EWS=<ews_score>. Priorizar amanha.",
  "fontes_consultadas": [{"rodada":"0","query":"token_cap","resultado":"deferred"}],
  "eventos": [], "_tier": <tier>, "_rotina_v2": true, "_token_cap_deferred": true
}
```
com `"provedor":"claude-cap-deferred"`. Registre no log quantos foram deferidos e por que.

## Passo 11 - Relatorio

Antes de qualquer outra coisa, apague o lock do Passo 0 (`Remove-Item $LockFile -Force -ErrorAction SilentlyContinue`). Vale tambem se a rotina abortou em qualquer passo anterior por motivo diferente de mutex/lock ocupado (ex.: health check, plano).

Escreva no log a linha `FIM: noturno concluido. Total do dia <N>/103. analisados=<A> skip=<S> deferidos=<D> submits_aceitos=<X>.`, onde:
- `<N>` = total de linhas `OK|` no log de hoje = `A + S + D` (SKIP + analisados + deferidos). Esse `<N>` ainda é o que o watchdog `scripts/retry-vixradar.ps1` lê para decidir se relança a rotina (>=90), então mantenha `Total do dia N/103` SEMPRE com `<N>` = soma das três categorias.
- `<A>` = total de linhas `OK|` cujo 6o campo é `ANALISADO` (emissor REALMENTE analisado nesta sessão — o número honesto de análise).
- `<S>` = total de linhas com `SKIP` (idempotência, já atualizado hoje).
- `<D>` = total de linhas com `DEFERIDO` (cap de sessão/degradado, deixado para amanhã).
- `<X>` = total de submits aceitos pelo Worker = `<A> + <S> + <D>` = `<N>` (pois SKIP/DEFERIDO também são submetidos e gravados).
Exemplo real do dia em que o reportar confundia: 50 analisados, 22 SKIP, 31 DEFERIDOS, os três sumavam 103 — e o resumo errado dizia apenas `submit_ok=103`, dando a entender 103 análises. O correto é `Total do dia 103/103. analisados=50 skip=22 deferidos=31 submits_aceitos=103.`.
Formato exigido pelo watchdog `scripts/retry-vixradar.ps1`, que relança a rotina inteira as 21h30 se nao achar um numero >=90 casando `Total do dia (\d+)/\d+`, `submit_ok=(\d+)`, `(\d+)/\d+ processados` ou `processados=(\d+)` numa linha `FIM:`. Incidente 17/08/2026: a primeira versao deste passo so mandava reportar em prosa livre ("103 no ledger, 3 SKIP..."), nenhum numero batia com os quatro formatos aceitos, e o watchdog teria relancado a rotina inteira as 21h30 mesmo com entrega completa (103/103, 0 falha). Escreva essa linha SEMPRE, com esse formato exato, mesmo que o resto do relatorio va em caveman.

Depois da linha FIM, o relatorio para o usuario e em caveman. Reporte: processados, SKIP, deferidos, distribuicao por classificacao, degradados para INCONCLUSIVO, lotes com silent_fail, emissores que falharam submit. Liste os CRITICO com nome e uma linha do que aconteceu.

Se abortou, diga onde e por que, sem suavizar.