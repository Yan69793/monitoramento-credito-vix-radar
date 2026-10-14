---
Status: Vigente (correcoes locais aplicadas e testadas; nada ativado, nada publicado)
Data: 2026-10-13
Data da Versao: 2026-10-13
Origem do Registro: sessao de trabalho ORCAMENTO-13OUT6, continuacao do handoff da nota 106
Condicao de Obsolescencia: cai quando o operador decidir o cap da Sentinela e a linha de orcamento da escalada, e a noturna rodar com `VIXRADAR_COLETOR_PS=1`; o corpo e registro datado e nao se reescreve depois
tags: [vix-radar, orcamento, sentinela, noturna, ativacao, rollback]
---

# Orcamento, Sentinela e preparo da ativacao da noturna, 13/10/2026

Escopo: fechar a conta do orcamento antes de religar a rotina noturna. Projeto: `E:\Diretorio\Claude\Monitoramento de Credito`. Resultado: **causa do consumo da Sentinela comprovada, cinco correcoes locais aplicadas e testadas, alocacao sustentavel projetada e plano de ativacao com rollback escrito**. Nada foi ativado, agendado, publicado ou commitado.

## Por que a Sentinela gastou 302.888 com cap de 120.000

O cap de 120.000 e **por execucao**, e a Sentinela roda **18 vezes por dia** (09h25 a 17h55, nos minutos :25 e :55). Em 13/10 rodou 14 vezes; 12 gastaram zero e **duas passaram do cap**, cada uma por um motivo distinto:

1. **17:25, estimativa mascarada.** `CAP_LOTE_REDUZIDO: ... custo_emissor=120000 fonte=default` seguido de `CAP_EXCEDIDO: ... custou 156293 contra estimativa 120000`. O custo-base estava limitado ao proprio cap (o antigo `Get-VixDefaultLimitadoAoCap`): a estimativa nascia 120.000, cabia, admitia o lote, e o lote custava 156.293. Nao era o cap que falhava, era a estimativa que mentia para caber. **Ja corrigido hoje as 17:42** (o clamp foi removido e o teste I9 prende isso).
2. **17:32, calibracao declarada.** `CAP_CALIBRACAO: estimativa honesta 250000 ... RISCO DECLARADO: pode passar do cap`. A excecao existe para medir quando nao ha medicao; e limitada a 1 lote por dia e o limite dela e o **orcamento do dia**, nao o cap da execucao. Custou 146.595, abaixo dos 250.000 estimados. **Auto-extinta**: depois dela existe `historico_proprio`, o ramo nunca mais liga - e as 18:58 a Sentinela recusou corretamente (`motivo=custo_medido_nao_cabe_no_cap`).

O controle do dia existe e funcionou (`Get-VixDisponivelSentinela` + o clamp do cap da execucao ao que sobra do dia depois da reserva de noturna e verificacao). O efeito colateral e a pendencia real: com 156.293 medidos contra cap de 120.000, **a Sentinela nao admite mais emissor nenhum** - virou no-op. Isso so se resolve mexendo em teto, e teto nao estava autorizado.

## Cinco correcoes, todas locais e testadas

1. **Cache do Codex deixa de ser invisivel.** 129.408 dos 167.768 tokens de uma escalada real eram cache (77%), e o fechamento do dia dizia `tokens_cache_read = 0` para codex, porque o cache so existia na linha FIM, que a lib de custo nao le. Agora e parcela propria (`cache_codex`), publicada no metrics como `tokens_cache_codex` e somada a parte no `CUSTO_DIA`. **A regua do cap nao mudou**: `trabalho` continua somando o cache, de proposito.
2. **INCONCLUSIVO virava QUIETO.** Duas linhas vizinhas do motor se contradiziam: uma carimbava `ultima_ia` para qualquer submit aceito (inclusive INCONCLUSIVO), a outra tratava INCONCLUSIVO como pendencia viva. Efeito: carimbo fresco -> portao de revalidacao da triagem passava -> emissor certificado QUIETO sem ninguem resolver a pergunta. As duas passam a ler `Test-VixAnaliseConcluida`.
3. **Estado nao resolvido nunca vira QUIETO.** Pendencia aberta de analise (`recheck_cobertura`, `submit_recusado`) ou `inconclusivo*` no plano barram o QUIETO e mandam o emissor para a IA. Motivos de orcamento (`cap_efetivo`, `cap_sentinela`, `escalada_sem_orcamento`, `falha_provider`, `uso_desconhecido`) **nao** barram: ali a divida era de gasto, nao de fato. Ordem importa: coleta indisponivel continua `INDISPONIVEL` e revalidacao vencida continua `MATERIAL`.
4. **Contabilizacao da Sentinela igual nos dois lugares.** O log `CIRCUITO_DIA` usava `trabalho`, a decisao usa `consumo` (inclui lote que falhou por provedor). Em dia com falha, o log mostrava folga que nao existia.
5. **A prova do rodizio FULL deixa de ser prova de copia.** A suite provava a retencao com uma replica local do predicado escrita a mao no teste. A condicao virou funcao pura (`Test-VixEscaladaRetem`), o motor chama, e as duas pontas ficam presas: o motor delega, a lib define, a condicao inline morreu.

## Testes

`test-cobertura-escalada` **89/89** em 5.1 e em pwsh 7. `test-cobertura-analitica` **132/132** (secao L nova, 17 provas). Regressao verde: recuperacao 72/72, varredura-defeitos 50/50, orcamento-sentinela 48/48, contrato 29/29, profundidade-noturna 154/154, cutover 33/33, retry-janela 39/39, idempotencia-janela 31/31, busca-degradada 31/31, `lint-encoding` RISCO 0, `check-claude-free` exit 0. Zero token externo, nenhuma rotina executada.

## Alocacao sustentavel (projetada sobre custos medidos)

| Linha | Emissores | Custo |
|---|---|---|
| Matinal (pacote barato) | 20 | 218.920 |
| Noturna MATERIAL (pacote barato) | 62 | 678.652 |
| Reserva de verificacao | - | 150.000 |
| Sentinela no dia | - | 300.000 |
| **Comprometido** | | **1.347.572** de 2.500.000 uteis |
| **Sobra para escalada FULL** | | **1.152.428 = 6 confirmacoes/dia** |

**O numero que decide e o tamanho do lote barato.** Com lote de 1 emissor (21.250/emissor) a sobra cai para 307.500 e cabe **1** FULL; com lote de 2 (10.946) cabem **6**. Amortizar o boot da coleta vale mais que qualquer ajuste de teto.

Cobertura diaria sustentavel: **62 coletados** com a triagem fechando os QUIETO, **6 confirmados em fonte primaria**, **56 MATERIAL residuais por dia** na fila, ~11 dias para varrer os 62. Cobertura integral em fonte primaria custaria ~11,7M/dia contra teto de 2,6M. Nao e possivel com o teto atual, e nenhum teto foi alterado.

## Ativacao e rollback

Ver `status/ESTADO.md`, bloco ORCAMENTO-13OUT6, para os comandos exatos. Em resumo: ligar `VIXRADAR_COLETOR_PS=1` no escopo User, reabilitar a task `VIXRADAR-Noturno`, e antes disso decidir o cap da Sentinela e a linha de orcamento da escalada. **Rollback de primeiro nivel e uma variavel**: `VIXRADAR_COLETOR_PS=0` desliga o coletor e, com ele, a escalada inteira (a ligacao exige coletor ativo), sem tocar em agendamento.

## O que NAO esta provado

- O guard `Barato` so tem prova deterministica (fixtures na secao S/W da suite) - a prova operacional do lado negativo (lote FULL da rotacao real nao retido) continua pendente de orcamento para uma sonda noturna.
- A triagem deterministica segue em modo sombra: as correcoes 2 e 3 sao sobre o caminho que so liga em `VIXRADAR_TRIAGEM_DETERMINISTICA=1`. Nada de producao mudou de comportamento nesta sessao.
- A parcela de cache so aparece em metrics gravados a partir de agora (o metrics de 13/10 e anterior a correcao e nao tem o campo - compatibilidade garantida pelo teste L17).
