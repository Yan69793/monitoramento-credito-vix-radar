---
Status: Vigente (parcial, sem homologacao operacional)
Data: 2026-10-13
Data da Versao: 2026-10-13
Origem do Registro: sessao de trabalho COBERTURA-13OUT1/2/3 (Sentinela, triagem em sombra, medicao do modo coletor)
Condicao de Obsolescencia: cai quando a escalada por emissor (pacote barato, ferramenta so onde ha divergencia) estiver em producao e medida; o corpo e registro datado e nao se reescreve depois
tags: [vix-radar, cobertura, sentinela, orcamento, coletor, triagem]
---

# Cobertura analitica, Sentinela e modo coletor, 13/10/2026

Escopo: preparar o VIX Radar para os 104 emissores com menor consumo possivel. Projeto: `E:\Diretorio\Claude\Monitoramento de Credito`. Resultado: **parcial**, controles implementados e testados, nenhuma homologacao em producao.

## Feito

- **Sentinela, estouro real medido.** Log `vixradar-sentinela_20261013.log`: 17:26:55 `CAP_EXCEDIDO` 156.293 contra cap 120.000, 17:33:24 `CAP_EXCEDIDO` 146.595 contra estimativa 250.000. Causa: cap e so teto de admissao (o Codex nao tem flag de limite de tokens), custo medido por emissor acima do cap, e a correcao inicial (clamp do default ao cap) mascarava a estimativa.
- **Controle preventivo.** `Get-VixDecisaoCapSentinela`: estimativa honesta, calibracao unica de 1 emissor por dia so sem medicao e com orcamento do dia cobrindo a estimativa. Medicao persistente em `logs/routines/sentinela_custo_emissor.jsonl` (maximo, 7 dias). Logs `CAP_PREVENTIVO` e `CAP_CALIBRACAO`.
- **Triagem em sombra** (`VIXRADAR_TRIAGEM_DETERMINISTICA=sombra`, escopo User, ligada nesta sessao) e **filtro de relevancia em sombra** (`Get-VixRelevanciaCredito`, registros em `relevancia_sombra_AAAAMMDD.jsonl`, revocacao por `Get-VixRevocacaoRelevancia`). Nenhum emissor sai da IA.
- **Gate de evento critico** na triagem (termos de estresse em F1 sem citar o nome).
- **Gate anti-Claude** sem enfraquecer regra: teste monta o nome do executavel em runtime e prova duas pontas (L0 a L4).
- **Modo coletor na via da IA:** `Add-VixFontesColetorAoResultado` soma as consultas do orquestrador ao resultado da IA e NAO soma com coleta incompleta nem em divergencia IA x coletor.
- **Agendador (medido):** `VIXRadar-Sentinela` 2 gatilhos seg-sex 09:25 e 09:55, repeticao PT1H por PT8H = 18 execucoes planejadas, `IgnoreNew`, `StartWhenAvailable`, limite PT40M. Em 13/10: 8 disparos por horario (13:55 a 17:25), 3 catch-ups.

## Nao feito / bloqueado

- **Escalada por emissor** (pacote barato primeiro, ferramenta so onde ha divergencia) nao existe. Sem ela nao ligar `VIXRADAR_COLETOR_PS` em producao.
- Rating e sinal de mercado como gate proprio: exige campo novo no Worker (deploy).
- Rodizio FULL semanal por risco.
- Decisao do operador: cap da Sentinela (custo medido 147k a 156k acima do cap de 120k, hoje ela nao admite mais emissor pelo Codex) e teto do dia (2,6M comporta ~28 analises de IA por dia).

## Verificacao

- `test-cobertura-analitica` 115/115 (pwsh 7 e Windows PowerShell 5.1), `test-cobertura-recuperacao` 72/72, `test-cobertura-contrato` 29/29, `test-orcamento-sentinela` 48/48, `test-retry-janela` 39/39, `test-varredura-defeitos` 50/50, `test-cutover-motor` 33/33, `test-locks-overlap` 31/31 isolado (29/31 em rodada paralela por colisao de lock), `lint-encoding` sem reprovados, `check-claude-free` na arvore exit 0.
- Noturna manual 17:50: PARCIAL, 2 analisados a 356.612 tokens (~178k cada), 90 deferidos, `pendentes_obrigatorios=92`.
- Dry-run do modo coletor: ~11k tokens por emissor (21.892 para 2, 23.608 para 3), os 3 emissores com manchete fresca INCONCLUSIVO porque a IA sem ferramentas nao abre a fonte.
- Raiz do workspace sem arquivo solto novo, nenhum processo rg/grep/find vivo.

## Estado deixado

- `VIXRadar-Noturno` **DESABILITADA** (17:56, pedido do operador). Reabilitar: `Enable-ScheduledTask -TaskName "VIXRadar-Noturno"`. Matinal e Sentinela habilitadas.
- `VIXRADAR_TRIAGEM_DETERMINISTICA=sombra` ligada. `VIXRADAR_COLETOR_PS=0` inalterada, sem motivo documentado.
- Base NAO atualizada para os 104 hoje.
- Medicao da Sentinela gravada (146.595 e 156.293, backfill do log). Marcador `sentinela_calibracao_20261013.json` existe.
- Alteracoes sem commit nem deploy, sobre arvore ja suja de sessoes paralelas.

## Riscos

- A execucao de 17:31 da Sentinela (catch-up do Agendador) usou o script editado e gastou 146.595: editar script vivo no meio do dia tem esse efeito.
- Sem limite de tokens do provedor nao ha garantia absoluta de cap.
- Nenhuma medicao de revocacao da sombra existe ainda.
- Noturna desabilitada: se ninguem reabilitar, nenhuma varredura completa roda a noite.

## Handoff

Proximo passo de maior retorno: construir a escalada por emissor e so depois ligar o coletor. Decidir quando reabilitar a noturna. Evitar: ligar `VIXRADAR_COLETOR_PS` em producao ou subir cap/teto sem a medicao da sombra.
