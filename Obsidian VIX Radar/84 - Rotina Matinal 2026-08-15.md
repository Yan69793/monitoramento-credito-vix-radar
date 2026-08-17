---
data: 2026-08-15
tipo: rotina
tags: [vix-radar, matinal, rotina, credito, cvm]
status: concluido
---

# 84 — Rotina Matinal 2026-08-15

Execução via Claude Code (retry manual após troca de modelo para `claude-sonnet-5`; a sessão original do Claude Desktop não concluiu). Guarda anti-duplicidade confirmada (`VIXRadar-Matinal` do Task Scheduler disabled). Health check inicial e final: `ok:true kv:true telemetria:true sentry_ok:true verificador_ok:true admin_email_ok:true`, v4.9.195 estável, HTTP 200 (~0,2-1,9s).

Executado num sábado. Não é feriado B3 (não consta na lista de 2026), mas também não é dia útil — o script não tem guarda própria de fim de semana (isso normalmente é papel do cron, que não dispara aos sábados). Prosseguido por ser retry explícito do usuário.

## Números

19 emissores processados, 19/19 submit OK, 0 falha. 0 SKIP, 0 deferido por cap de token, 0 degradado para INCONCLUSIVO. ~36 buscas efetivas no total (WebSearch), bem dentro do envelope de 120k tokens (não medido diretamente, orçamento tratado como teto de buscas por emissor).

**Anomalia registrada:** o plano (`listar_plano_rotina`, `top_n=15`) devolveu `total=19` em vez de 15. Composição: 0 SKIP, 10 LIGHT, 9 FULL, 0 AUDIT. Seguido o protocolo (prosseguir com aviso, não abortar). Pendência aberta em [[PENDENCIAS.md]] para investigar se `top_n` está sendo respeitado na composição do plano.

| Classificação | Qtd | Emissores |
|---|---|---|
| CRITICO | 3 | Oncoclínicas, Kora Saúde, CSN |
| RELEVANTE | 9 | Oi, Raízen, Pão de Açúcar (GPA), Light, Hapvida, Rumo, Aegea Saneamento, Simpar, MRV Engenharia |
| ECO | 4 | Cosan, Dasa, Omega Energia, SLC Agrícola |
| NENHUM | 3 | Vamos, Itaúsa, Klabin |

## CRITICO

- **Oncoclínicas** — Justiça (3ª Vara de Falências e RJ de SP) deferiu processamento da recuperação extrajudicial em 04-05/08, suspensão de 180 dias, dívida quirografária de R$5,1bi, adesão de credores em 37% (precisa >50% em 90 dias). Fonte: CVM Fato Relevante já presente no plano.
- **Kora Saúde** — Sucessivas Assembleias Gerais de Debenturistas entre 17-28/07 (exchange de debêntures, aditamento de escritura), rating Fitch em faixa de risco de default, standstill de juros já aprovado, dívida 4x EBITDA. Fonte: CVM (AGD no plano).
- **CSN** — Fitch rebaixou IDR de B para CCC+ em 31/07, observação negativa mantida, dívida pode superar R$60bi em 2026-2027, alavancagem projetada 5,7x-6,3x. Fonte: CVM Fato Relevante "Atualização Ratings" localizado via busca.

## RELEVANTE — destaques

- **Light** — Virada positiva: homologou aumento de capital de R$1,5bi e pediu encerramento da recuperação judicial (última obrigação do plano de 2024 cumprida). Bônus de subscrição (LIGT13) encerrou exercício em 14/08.
- **Aegea Saneamento** — Aporte de R$2,1bi subscrito em 05/08 (GIC + Itaúsa), resposta ao rebaixamento a grau especulativo de abril/26.
- **Simpar** — Venda da CS Porto Aratu à ICTSI por R$1,8bi (assinado 23/07), desalavancagem, pendente aprovação Cade.
- **MRV Engenharia** — Venda final dos ativos da Resia (EUA, US$170mi) encerra o "problema Resia", mas 2T26 teve prejuízo de R$626,3mi (mais que o dobro do projetado) e alavancagem se aproximou do limite de covenant.
- **Hapvida** — 2T26 fraco (lucro ajustado -95,8% a/a), ação caiu 8,77% em 13/08, leverage caminhando para 2,8x (perto do gatilho de novo rebaixamento Fitch).
- **Rumo** — Moody's rebaixou Ba2→Ba3 em 17/07 por contágio do grupo Cosan/Raízen, fundamentos operacionais da própria Rumo relativamente estáveis.
- **Oi** e **Raízen** — Sinal forte encontrado (alerta de continuidade de caixa da Oi; sucessivos rebaixamentos e reestruturação de R$65bi da Raízen), mas tratados como *watchlist sem evento formal*: a fonte primária mais específica caía fora da janela de 30 dias (Oi: Fato Relevante de 09/07; Raízen: rebaixamentos de março/26). Gate de data bloqueou a criação de evento novo — registrado só em `cobertura_nota`.

## ECO / NENHUM

Cosan (desalavancagem em curso, sem fato novo no período), Dasa (segue reduzindo dívida líquida, resultado do 2T26 positivo), Omega Energia e SLC Agrícola (sem fato novo localizado), Vamos/Itaúsa/Klabin (perfis limpos, sem sinal de crédito negativo).

## Padrão transversal

Contágio de rating dentro do grupo Cosan: Cosan, Rumo e CSN tiveram ações de rating no período todas citando (direta ou indiretamente) o estresse de crédito originado na reestruturação da Raízen, mesmo em casos com fundamentos operacionais isolados razoáveis (caso Rumo).

## Log de idempotência

`logs/routines/vixradar-matinal_20260815.log` — 19 linhas `OK|empresa|tier|classificacao|n_eventos|true`, INICIO/FIM registrados.

Ver [[03 - Estado Atual]] e [[00 - Índice (MOC)]].
