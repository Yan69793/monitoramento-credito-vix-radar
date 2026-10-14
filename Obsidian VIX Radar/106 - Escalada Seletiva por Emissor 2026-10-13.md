---
Status: Homologada em execucao dirigida dry-run (13/13 marcas, 189.018 tokens); segue INERTE em producao (VIXRADAR_COLETOR_PS=0)
Data: 2026-10-13
Data da Versao: 2026-10-13
Origem do Registro: sessao de trabalho COBERTURA-13OUT4, continuacao do handoff da nota 105
Condicao de Obsolescencia: cai quando a escalada rodar em execucao real com `VIXRADAR_COLETOR_PS=1` e a medicao (custo por emissor escalado e taxa de escalada) estiver registrada; o corpo e registro datado e nao se reescreve depois
tags: [vix-radar, cobertura, escalada, coletor, orcamento, triagem]
---

# Escalada seletiva por emissor, 13/10/2026

Escopo: fechar a arquitetura hibrida do VIX Radar sem perder qualidade analitica. Projeto: `E:\Diretorio\Claude\Monitoramento de Credito`. Resultado: **implementado, testado offline e inerte**, sem homologacao em execucao real.

## O que faltava

A nota 105 deixou o handoff escrito: "construir a escalada por emissor e so depois ligar o coletor". O motivo estava medido. O pacote barato custa ~11k por emissor contra ~178k do modo FULL, mas nao abre a fonte primaria; os 3 emissores do lote de medicao de 13/10, todos com manchete nova, voltaram INCONCLUSIVO. Ligar o coletor sem escalada seria trocar "cobertura cara" por "reanalise eterna".

## O que foi feito

**Decisao por emissor.** `Get-VixEscaladaDecisao` (funcao pura, `scripts/lib/vixradar-cobertura.ps1`) decide quem precisa de ferramenta, com gatilho e prioridade: coleta indisponivel (100), divergencia IA x coletor (90), EWS >= 50 (80), documento CVM novo (70), INCONCLUSIVO ou recheck pendente (60), termo de estresse de credito (55), agencia de rating na fonte (52), fato novo relatado pela IA (40). Sem nenhum gatilho o emissor fecha pela rodada barata - e esse e o unico caminho que fecha sem ferramenta, e ele exige coleta completa.

**Rodada de escalada sem caminho paralelo.** A rodada barata roda, decide e RETEM quem tem gatilho, sem submeter e sem gravar ledger. Depois, os retidos viram lotes FULL e entram na MESMA fila de lotes do motor: mesmo orcamento, mesmo disjuntor de provedor, mesmo retry parcial, mesmo portao de ausencia, mesmo submit, mesmo ledger, mesma fila pendente. Duplicar esse caminho seria a forma mais rapida de os dois divergirem em silencio.

**Duas guardas de honestidade.** Retido que o cap nao deixou escalar sai DEFERIDO com motivo `escalada_sem_orcamento`, contador proprio e entrada na fila persistente: vira pendencia obrigatoria e faz a rotina fechar PARCIAL, nunca OK. E o aborto por auth no meio da rodada barata defere os retidos que ainda nao tinham lote, senao eles nao teriam ledger nem fila e sumiriam entre a retencao e a escalada.

**Modo barato explicito, nao inferido.** Achado de desenho: com o coletor ligado, o texto que proibe ferramenta valia para todo lote, inclusive o FULL da rotacao semanal noturna, cuja razao de existir e abrir fonte primaria. Agora quem decide e o chamador, marcando o lote barato (LIGHT da noturna e lotes da matinal). O tier nao serve: a matinal rotula os proprios lotes como FULL.

**Defeito corrigido de passagem (ENVIADOS1).** `$enviados` nunca era atribuido no motor. O ramo `DESCARTE_PARCIAL` comparava `$nEv -lt $enviados` com a variavel inexistente, o PowerShell convertia o `$null` a 0 e o ramo estava morto desde FEEDRETRO1 FASE2. Um submit em que o Worker persiste PARTE dos eventos nao incrementava `descartes_inesperados`, que entra em `errosTotal`, que decide OK x PARCIAL - o dia podia fechar OK com evento descartado por causa inesperada. Corrigido com `$enviados = @($res.eventos).Count`, provado nas duas pontas.

## Numeros

**Medidos (13/10).** FULL ~178k por emissor (356.612 para 2 na noturna de 17:50). Barato ~11k (21.892 para 2, 23.608 para 3). Dia consumido 1.150.955 de 2.600.000, circuito fechado (matinal 445.955, noturno 402.112, sentinela 302.888). Fila persistente com 92 entradas, todas `cap_efetivo`, `tentativas=2`.

**Projetados (nao medidos).** Orcamento util ~2,42M. Cap da noturna (700k) admite 3 emissores no modo FULL atual, ou 63 no barato. Com a triagem ligada, os 62 MATERIAL medidos custam ~679k e cabem no cap da noturna com 21k de sobra - nao sobra nada para escalar dentro do cap da propria noturna. Usando a folga do dia, a escalada cobre ~7 emissores FULL por dia contra 62 sinalizados. Cobertura integral em fonte primaria exigiria ~11M/dia.

**Conclusao do numero.** O pacote barato resolve a COLETA dos 104. O teto atual nao resolve a CONFIRMACAO em fonte primaria. Essa e a decisao que sobra para o operador.

## Verificacao

Suite nova `scripts/test-cobertura-escalada.ps1`, **71/71 em Windows PowerShell 5.1 e 71/71 em pwsh 7** (decisao por gatilho nas duas pontas, prioridade e dedup da fila, texto do prompt de escalada x barato, orcamento com cap ficticio, recuperacao de 4 execucoes encadeadas sem duplicar nem perder, e 21 guardas estruturais no motor).

Regressao verde: analitica 115/115, recuperacao 72/72, contrato 29/29, orcamento-sentinela 48/48, varredura-defeitos 50/50, cutover 33/33, retry-janela 39/39, profundidade-noturna 154/154, idempotencia-janela 31/31, busca-degradada 31/31, locks-overlap **31/31 isolado** (sobe o motor real 4 vezes com a fila de lotes reestruturada), lint-encoding RISCO 0, check-claude-free exit 0. Runner do projeto: 49 suites, 47 verdes, as 2 vermelhas sao as do baseline declarado.

## O que NAO esta provado

- A escalada nunca rodou ponta a ponta. A prova e offline: as funcoes sao reais, mas o custo real de um lote de escalada so a execucao mede.
- Nao ha medicao de revocacao da sombra: nenhum `logs/routines/relevancia_sombra_*.jsonl` existe, porque a sombra nunca rodou em execucao real. O log da noturna de 13/10 mostra `COLETOR_PS: ativo=False` e `TRIAGEM: desligada`.
- Zero token gasto nesta sessao: nenhuma rotina, nenhum dry-run, nenhum deploy, nenhum commit.
- A Sentinela nao tem escalada por emissor: ela so roda lote que cabe no proprio cap.
- Rating e sinal de mercado continuam sem campo proprio no plano do Worker, entao entram na escalada pela via indireta (F2, agencia na fonte e EWS), nao como gate proprio.

## Revisao do proprio diff (mesmo dia, turno seguinte)

Tres correcoes, todas por leitura do codigo e com prova:

1. **Retencao sem exigir lote barato.** O lote FULL da rotacao semanal noturna (Sonnet, com ferramenta, escolhido por risco, cheio de EWS >= 50) casaria gatilho em quase todo emissor, seria retido e re-escalado: a rodada boa, que ja abriu a fonte primaria, seria descartada, e o mesmo emissor pagaria dois lotes FULL na mesma noite. Guard novo `[bool]$job.Barato`.
2. **Escalada ligando sob provedor sem ferramenta.** Sob `deepseek` - o provedor para o qual o coletor e obrigatorio porque a IA nao tem WebSearch/WebFetch - o lote de escalada cairia em `Test-VixColetorObrigatorioPronto` para um emissor cuja coleta falhou (que e um dos gatilhos) e o motor sairia com exit 6, matando a execucao inteira. Guard novo `-not $script:VixColetorObrigatorio`.
3. **Retencao barrada em dry-run.** A homologacao e uma execucao dirigida em dry-run; com o guard, a rodada de escalada nunca seria exercitada antes de ligar o coletor em producao, e a unica forma de medir o custo real de um lote de escalada seria uma execucao real. Em dry-run nada e submetido e o ledger sai com prefixo `DRYRUN`, que os leitores de entrega nao contam.

Suite da escalada: **83/83** em PowerShell 5.1 e em pwsh 7 (subiu de 71: S1-S6 do escopo da retencao e V1-V5 do validador de homologacao). `test-varredura-defeitos` 50/50 e `test-profundidade-noturna` 154/154 re-rodados porque o motor mudou depois de eles passarem.

## Capacidade real com os caps atuais

Insumos medidos e declarados: `TETO_DIA=2.600.000`, `MARGEM_MINIMA=100.000`, `RESERVA_VERIFICACAO=150.000`, cap proprio da noturna 700.000 e da matinal 400.000, custo medido de 178.306 por emissor FULL e 10.946 por emissor barato, 104 emissores e 62 MATERIAL.

| Caminho | Cabe no cap da noturna (700k) |
|---|---|
| FULL puro (hoje) | **3 emissores** |
| Barato puro | 63 emissores |
| Barato dos 104 | **nao cabe** (1.138.384) - so cabe com a triagem fechando os 42 QUIETO a zero token |
| Barato dos 62 MATERIAL | 678.652, sobra 21.348 |
| Escalada FULL depois do barato | **0 emissores** dentro do cap da propria noturna |
| Escalada FULL com linha propria no dia | 9 emissores (de 62 sinalizados) |
| Desenho completo (104 coletados, 62 baratos, 62 FULL) | 11,7M + margem = **~12M/dia** contra teto de 2,6M |

## Homologacao preparada (NAO executada)

Validador: `scripts/check-homologacao-escalada.ps1 -LogPath <log> [-Emissor <nome>]`, 13 marcas fechadas, exit 0 = aprovado. Prova das duas pontas no proprio validador (log completo aprova; sem decisao, sem fetch, sem ledger FULL, sem o interruptor ou com `CAP_EXCEDIDO` reprova apontando a marca que faltou).

Execucao dirigida (exige autorizacao; **gasta token**, estimado ~190k para 1 emissor barato + 1 escalado):

```powershell
# escopo PROCESS: nao altera a configuracao do operador (User/Machine seguem intactos)
$env:VIXRADAR_COLETOR_PS = '1'
$env:VIXRADAR_ESCALADA_FULL = '1'
# a matinal garante lote barato com -MaxEmissores 1; a noturna com -MaxEmissores 1 pode cair
# inteira no lote FULL da rotacao, que NAO retem, e entao nao exercita a escalada
pwsh ./scripts/run_vixradar_varredura.ps1 -Rotina matinal -DryRun -MaxEmissores 1
pwsh ./scripts/check-homologacao-escalada.ps1 -LogPath logs/routines/vixradar-matinal_<AAAAMMDD>_dryrun_<pid>.log
```

Segunda sonda, mais forte, depois da primeira passar: `-Rotina noturno -DryRun -MaxEmissores 2`, que exercita as duas metades do guard `Barato` de uma vez (lote FULL da rotacao nao retem, lote LIGHT retem).

## Handoff

Proximo passo de maior retorno: rodar a sonda dirigida acima e julgar com o validador. Depois decidir `VIXRADAR_COLETOR_PS`, o cap da Sentinela e a linha de orcamento da escalada - e so entao reavaliar a reabilitacao da noturna, que segue desabilitada.

## Homologacao executada (HOMOLOG-13OUT5, 13/10/2026)

A sonda da secao anterior foi executada exatamente como escrita: `-Rotina matinal -DryRun -MaxEmissores 1`, com `VIXRADAR_COLETOR_PS=1` e `VIXRADAR_ESCALADA_FULL=1` so no escopo do processo. **13/13 marcas, exit 0, APROVADA.** Log `logs/routines/vixradar-matinal_20261013_dryrun_25620.log`.

O emissor sorteado foi a **Light**, retida pelo gatilho `divergencia_ia_coletor` (prioridade 90): o coletor trouxe 4 itens e a IA nao os converteu em evento. A rodada FULL abriu a fonte primaria (`"provedor":"codex:web_search"`), e o desfecho foi honesto - INCONCLUSIVO, dizendo na nota de cobertura o que confirmou (notas comerciais da Light SESA de setembro) e o que NAO conseguiu certificar (o documento CVM de encerramento da oferta nao abriu). Nenhum NENHUM foi carimbado. Uma unica linha de ledger para o emissor, `DRYRUN|Light|FULL|INCONCLUSIVO|0|false|ANALISADO|0`: a escalada substituiu a submissao barata em vez de somar.

**Custo medido:** barato 21.250 (1 emissor), escalada 167.768 (1 emissor, `buscas=3`), total **189.018**. Abaixo do custo-base de 178.306 por emissor, entao `cap_excedido=0`. Dos 167.768 da escalada, 129.408 sao `cached_input`, que a regua do cap conta como trabalho de proposito - o numero do cap e conservador.

**Tres defeitos do validador, corrigidos.** Ele foi escrito e provado contra um log de execucao real, mas existe para julgar uma execucao em dry-run, e reprovava justamente essa: H9 exigia prefixo `OK|` (em dry-run o ledger sai `DRYRUN|`); H12 exigia `resultado=(OK|PARCIAL|FALHA)` (em dry-run sai `resultado=DRYRUN`); e H10 nao passava em log nenhum, porque `-match` e insensivel a caixa e o contador saudoso `cap_excedido=0` da linha de resumo casava com o marcador de falha `CAP_EXCEDIDO`. O log sintetico "bom" das provas nao tinha o campo `cap_excedido=`, por isso o defeito nao aparecia. H13 tambem deixou de ser eco do resultado anterior e passou a fechar a conta de verdade. Suite: **86/86** em 5.1 e em pwsh 7 (era 83/83).

**Capacidade real:** o orcamento util do dia e 2.500.000; com os caps nominais sobram 1.130.000, que comportam **6 FULL** por dia; com o consumo medido da Sentinela (302.888, contra cap de 120.000) sobram 947.112, que comportam **5**. Dentro do cap da propria noturna cabem 0 escaladas. Os 62 MATERIAL sinalizados levariam ~11 dias nessa folga.

**Sonda noturna nao foi executada:** a autorizacao era de 250.000 tokens, a matinal consumiu 189.018 e sobraram 60.982, enquanto `-MaxEmissores 1` ou `2` na noturna roda lote FULL da rotacao a ~170k cada. O guard `Barato` segue provado so estruturalmente (G3/G20) mais o lado positivo da sonda.

**Preservacao:** a fila persistente segue com 92 entradas e data de 18:58:33 (da sentinela), o ledger definitivo do dia com 14:02/17:55 e a config de teto com 12/10 - a sonda rodou 19:17-19:19, depois de todos. Em dry-run o motor nao submete e nao escreve fila, entao a preservacao e por construcao e a data confirma.
