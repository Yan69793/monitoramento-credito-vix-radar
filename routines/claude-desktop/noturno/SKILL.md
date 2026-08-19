---
name: vixradar-noturno
description: VIX Radar noturno: varre os 103 emissores e submete ao Worker (diario 18h BRT)
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

Dos restantes (tier != SKIP, nao processados hoje):
- Fila RAPIDA: todos que NAO se qualificam para a aprofundada. Lotes de 15. Processe PRIMEIRO.
- Fila APROFUNDADA: `tier == "FULL"` E (`ews_score >= 38` OU `cvm_novos > 0`). Ordene por ews_score desc. Lotes de 11. Processe DEPOIS.

A ordem importa, rapida antes de aprofundada. Se a sessao degradar no meio, o que sobra e a fila cara, que voce defere no passo 10.

Um subagente por lote. Rode no maximo 3 subagentes em paralelo, para nao saturar WebSearch.

Para cada lote, decida o caminho do arquivo de saida ANTES de disparar o subagente: diretorio scratchpad desta sessao (nunca o repo git), nome `out_rapida_<n>.txt` ou `out_aprofundada_<n>.txt`, `<n>` = ordem do lote na fila. Passe esse caminho absoluto no prompt do subagente (Passo 7). O subagente nao escolhe o proprio nome de arquivo.

NUNCA reabra um subagente apos o retorno (via SendMessage ou qualquer outro mecanismo) so para gravar linhas em arquivo. Reabrir um subagente custa o replay do transcript inteiro - medido em 17/08: +142260 tokens em UM lote, preco equivalente ao da analise original, e foi isso que estourou o hard cap daquele dia. Se o arquivo de saida voltou ausente, vazio ou incompleto, extraia as linhas RESULTADO| do RETORNO do subagente e grave-as voce mesmo no arquivo com Add-Content via PowerShell.

## Orcamento de tokens

Meta 500000 tokens (500k). Hard cap 700000 tokens (700k). Herdado do desenho original, onde a fila rapida rodava em Haiku (lotes de 15) e a aprofundada em Sonnet (lotes de 11).

Voce nao tem contagem exata de tokens nesta sessao. Use o orcamento como envelope de custo, nao como numero a medir. Estimativa calibrada 2026-08-18: cerca de 15000 fixos mais 9500 por emissor na fila rapida (medido: 9,4k/emissor em 17/08, 12,4k/emissor em 15/08) e 13000 por emissor na aprofundada (sem medicao recente, revalidar). Use isso para decidir se ainda cabe mais um lote antes de dispara-lo.

Chegando perto do hard cap, NAO dispare o proximo lote. Defira os emissores restantes conforme o passo 10.

Respeitar o maximo de buscas por emissor e o que mantem o custo dentro do envelope. Nao estoure o limite de buscas para "melhorar" a analise.

## Passo 7 - O que mandar para o subagente

Para cada emissor do lote, envie SO estes campos: `empresa, setor, tier, ews_score, cvm_novos, cvm_documentos` (max 3 docs, com categoria, assunto truncado em 100 chars, data, link) e `contexto_historico` truncado (400 chars se ews_score >= 38 ou o texto casar REX/RJ/recuperacao/default/CRITICO, senao 200).

Nunca inclua a routine_key no prompt do subagente.

Cabecalho do prompt do subagente, literal:

```
JANELA: <janela_inicio> a <janela_fim>

BUSCAS por emissor (WebSearch).
[fila RAPIDA]  R2 sempre (noticias de credito: rating, divida, default, covenant, M&A, resultado). R6 (cross-check rating/regulatorio) SOMENTE se R2 trouxe sinal CRITICO/RELEVANTE, ou ews_score>=20, ou cvm_novos>0. R2 limpo em emissor de EWS baixo: classificar ECO/NENHUM com 1 busca e cobertura_nota de 1 frase.
[fila APROFUNDADA]  max 3 buscas, adaptativas. R2 primeiro. R6 se R2 trouxe sinal ou ews_score>=38. R5 (covenants, rolagem, liquidez) SOMENTE se R2/R6 confirmaram evento CRITICO/RELEVANTE.

Dados CVM ja vem no JSON, nao rebuscar CVM.
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

Apos cada submit bem-sucedido:
`OK|<empresa>|<tier>|<classificacao>|<n_eventos>|<true|false do submit>`

Essa linha e o ledger de idempotencia.

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

Escreva no log a linha `FIM: noturno concluido. Total do dia <N>/103.`, onde `<N>` = total de linhas `OK|` no log de hoje (SKIP + analisados + deferidos). Formato exigido pelo watchdog `scripts/retry-vixradar.ps1`, que le o log as 21h30 e relanca a rotina inteira se nao achar um numero >=90 casando `Total do dia (\d+)/\d+`, `submit_ok=(\d+)`, `(\d+)/\d+ processados` ou `processados=(\d+)` numa linha `FIM:`. Incidente 17/08/2026: a primeira versao deste passo so mandava reportar em prosa livre ("103 no ledger, 3 SKIP..."), nenhum numero batia com os quatro formatos aceitos, e o watchdog teria relancado a rotina inteira as 21h30 mesmo com entrega completa (103/103, 0 falha). Escreva essa linha SEMPRE, com esse formato exato, mesmo que o resto do relatorio va em caveman.

Depois da linha FIM, o relatorio para o usuario e em caveman. Reporte: processados, SKIP, deferidos, distribuicao por classificacao, degradados para INCONCLUSIVO, lotes com silent_fail, emissores que falharam submit. Liste os CRITICO com nome e uma linha do que aconteceu.

Se abortou, diga onde e por que, sem suavizar.