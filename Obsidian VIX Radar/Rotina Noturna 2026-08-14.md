# Rotina Noturna — 2026-08-14

**Data:** 2026-08-14
**Modo:** noturno v2 (tiered), sessão Claude Desktop
**Versão Worker:** v4.9.194
**Janela:** 2026-07-15 a 2026-08-14

---

## Resumo Executivo

| Métrica | Valor |
|---------|-------|
| Total emissores | 103/103 ✓ |
| Analisados por subagente | 103 (SKIP 0) |
| CRITICO | **5** |
| RELEVANTE | 29 |
| ECO | 63 |
| NENHUM | 5 |
| INCONCLUSIVO (guarda de cobertura) | 1 (Banco Pan, tier FULL com 1 busca vazia) |
| Submits com falha | 0 |
| silent_fail | 0 |
| Persistido no KV | `radar:estado:2026-W33`, updated_at 21:54 UTC, 103 empresas |

---

## 🔴 CRITICOs — Ação Requerida

### 1. Cosan — Petróleo, Gás e Combustíveis
- Moody's rebaixou de Ba3 para B1 em 16/07, perspectiva negativa, segundo corte no ano (após S&P para B+ em 08/07).
- Holding com alavancagem acima de 4,5x e cobertura de juros abaixo de 1x; contágio da reestruturação da Raízen.
- Fonte primária: relatório da Moody's protocolado na CVM em 16/07 (numProtocolo 1545584).
- Monitorar: venda da fatia de ~23% na Rumo (oito propostas), meta de dívida líquida zero.

### 2. Hapvida — Saúde
- 2T26 (12/08): EBITDA -44,3%, margem de 6,3% (gatilho de rebaixamento da Fitch é 10%), sinistralidade 75,2%, queima de caixa R$ 666,5 mi, ação -33% (mínima desde IPO).
- 947 mil beneficiários (11% da carteira) em contratos deficitários sob análise.
- Covenant de alavancagem com folga (1,61x contra 3,0x), mas gatilho de margem acionado em bases recorrentes.
- Monitorar: próximo ciclo de revisão da Fitch, sinistralidade no 3T26.

### 3. Oncoclínicas — Saúde
- Recuperação extrajudicial de R$ 5,1 bi protocolada 13/07; Justiça deferiu processamento no início de agosto com stay de 180 dias.
- Assembleias de ratificação em 05/08 na CVM; debenturistas (~R$ 1,5 bi) ainda sem acordo.
- Fitch tratou extensão de juros de parte das debêntures como inadimplência restrita.
- Monitorar: aprovação de 50% dos credores para homologar, proposta do IG4 de R$ 500 mi em conversíveis.

### 4. Oi — Telecom e Tecnologia
- TJ-RJ marcou 25/08 julgamento dos agravos (Itaú, Bradesco) que suspendem a falência; relatora já votou contra os recursos.
- Quarto adiamento de balanços (11/08, sem nova data); gestão judicial aponta caixa só até meados de agosto.
- Monitorar: julgamento de 25/08, retomada do processo falimentar se recursos negados.

### 5. Raízen — Petróleo, Gás e Combustíveis
- Homologação judicial da maior recuperação extrajudicial do país (R$ 65 bi), apoio de mais de 81% dos credores, noticiada 04/08.
- Opções: conversão a R$ 0,25/ação ou haircut de 80% com pagamento único em 2047; aporte de R$ 3,5 bi da Shell.
- 1T27 com prejuízo de R$ 1,6 bi, dívida líquida de R$ 56,8 bi (4,8x EBITDA).
- Monitorar: execução do plano até mar/2027, separação em duas empresas, mudança de categoria CVM.

---

## Relevantes em destaque

- Light: aumento de capital de R$ 1,5 bi e conversão de até R$ 2,2 bi em debêntures, pedido de encerramento da RJ protocolado 15/07.
- GPA: credores aprovaram term sheet das novas debêntures da RE de R$ 4,5 bi em 12/08.
- CSN: troca de US$ 1 bi em bonds da CSN Inova concluída a 11% (adesão 77,49%).
- Rumo: Moody's rebaixou Ba2 para Ba3 (17/07), contágio Cosan.
- Aegea: Moody's manteve B2 mas mudou perspectiva para negativa em 14/08; aporte de até R$ 2,1 bi aprovado.
- Kora Saúde: assembleias de exchange de debêntures da 2ª emissão (27/07), RE de R$ 1,3 bi em curso.
- Natura &Co: S&P revisou perspectiva para negativa em 27/07 (BB mantido).
- Petrobras: Moody's cortou Baa3 para Ba2 (perda de grau de investimento) com rating em revisão, mas data da ação não confirmada na janela, ficou em watchlist sem evento.

---

## Incidentes da sessão

1. **402 Insufficient Balance na wave 1.** Os 3 primeiros subagentes morreram no meio. Usuário recarregou crédito, agentes retomados via SendMessage e entregaram 45/45.
2. **Hard cap de tokens estourado.** Consumo real ~110-130k tokens por lote de 15 emissores (total ~820k para os 8 lotes + aprofundada + lote 7), contra ~82k estimados no desenho. Após a wave 2 (~692k) os 13 restantes foram deferidos conforme o spec (`claude-cap-deferred`). O usuário ordenou rodar a aprofundada e o lote 7 na mesma sessão, substituindo os DEFERRED por análise real no Worker. Zero deferidos restantes ao final.
3. **Sandbox do tool PowerShell bloqueou `Remove-Item -LiteralPath`** em comando combinado ("protected path" `'\`). Forma simples `Remove-Item $LockFile -Force` funciona. Não afetou a rotina.

## Aprendizado acionável

O envelope de tokens do prompt da noturna (meta 500k, hard cap 700k) foi calibrado para o desenho original com Haiku na fila rápida. Com subagentes rodando no modelo da sessão, o consumo por emissor fica ~70% acima e o cap estoura toda noite, forçando deferimento e decisão manual. Recomendação: recalibrar o orçamento do prompt da rotina (ver nota [[27 - Otimizacao Tokens Rotina Noturna]]) ou fixar modelo mais barato nos subagentes da fila rápida.

## Verificação

- KV: chave `radar:estado:2026-W33` (RADAR_KV), 103 empresas, `_provedor` correto por fila (`claude-sonnet-routine` na aprofundada, `claude-haiku-routine` na rápida), `_matinal:false`, acentuação íntegra (bug de encoding não reaberto).
- Frontend consome `op=state` → `carregarEstadoMultiSemana(5)` → essa chave. Renderização visual não conferida (exige JWT de usuário).
- Log: `logs/routines/vixradar-noturno_20260814.log`, 116 linhas OK, 0 falha de submit.
- Task nativa `VIXRadar-Noturno` conferida `Disabled`; lock da rotina removido.

## Estado deixado

- Working tree do repo limpo, sem deploy nesta sessão.
- Worker segue v4.9.194, nenhuma mudança de código ou config.

## Handoff

- Conferir visualmente os 5 cards CRITICO no frontend logado.
- Decidir sobre recalibração do orçamento de tokens da noturna (item acima).
- Na próxima noturna, o histórico dos nomes (ver passo 4 de idempotência) está no log do dia 14/08.
