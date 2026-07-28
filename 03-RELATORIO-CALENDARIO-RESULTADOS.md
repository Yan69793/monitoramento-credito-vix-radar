# 03 — Relatório do Calendário de Resultados VIX Radar

Data: 2026-07-28. Base: SHA `fdae5cb`, bundle `api/v4.9.182.js:3828-3917`. Achados por ID no registro canônico (`00-AUDITORIA-SISTEMA-COMPLETA.md`): CAL-001, CAL-002, CAL-003, CAL-004.

## 1. Reconstrução completa da base

`CALENDARIO_RESULTADOS_V1`: 20 emissores de 103 (19% de cobertura), `schema_version: 1`, `ultima_atualizacao: "2026-05-09"` (80 dias atrás), `fontes_validacao` compostas por dois portais secundários (InfoMoney, MoneyTimes).

| Emissor | 1T26 | Status 1T26 | Fonte 1T26 | 2T26 | Status 2T26 |
|---|---|---|---|---|---|
| Petrobras | 2026-05-11 | agendado | InfoMoney | **2026-07-28 (hoje, não confirmada)** | estimado |
| Vale | 2026-04-28 | divulgado | MoneyTimes | **2026-07-24 (errado, oficial 30/07)** | estimado |
| Eletrobras (AXIA) | 2026-05-05 | divulgado | InfoMoney | 2026-08-12 | estimado |
| Itaúsa | 2026-05-11 | agendado | InfoMoney | 2026-07-29 | estimado |
| Bradesco | 2026-05-06 | divulgado | MoneyTimes | **2026-07-28 (errado, oficial 05/08)** | estimado |
| BTG Pactual | 2026-05-12 | agendado | MoneyTimes | 2026-08-04 | estimado |
| Engie Brasil | 2026-05-07 | agendado | MoneyTimes | 2026-08-12 | estimado |
| CEMIG | 2026-05-07 | agendado | InfoMoney | 2026-08-12 | estimado |
| Equatorial | 2026-05-13 | agendado | MoneyTimes | 2026-08-13 | estimado |
| Sabesp | 2026-05-07 | agendado | InfoMoney | 2026-08-12 | estimado |
| Suzano | 2026-04-29 | divulgado | MoneyTimes | 2026-07-30 | estimado |
| Klabin | 2026-05-06 | divulgado | MoneyTimes | 2026-08-07 | estimado |
| JBS | 2026-05-12 | agendado | MoneyTimes | 2026-08-12 | estimado |
| BRF | 2026-05-14 | agendado | ADVFN | 2026-08-13 | estimado |
| Hapvida | 2026-05-07 | agendado | InfoMoney | 2026-08-11 | estimado |
| Rede D'Or | 2026-05-13 | agendado | InfoMoney | 2026-08-14 | estimado |
| Tupy | 2026-05-14 | agendado | InfoMoney | 2026-08-13 | estimado |
| Embraer | 2026-05-08 | agendado | InfoMoney | 2026-07-30 | estimado |
| Cosan | 2026-05-14 | agendado | InfoMoney | 2026-08-14 | estimado |
| Gerdau | 2026-04-27 | divulgado | Gerdau (RI próprio) | 2026-07-29 | estimado |

Todos os 20 registros 2T26 têm `fonte: "estimado_historico"` e `nota: "Data estimada com base em padrao historico. Confirmar no RI."`.

Leitura dos números:

0. **Duas das datas 2T26 estão comprovadamente erradas** (seção 3). Bradesco e Vale foram checados contra o RI oficial em 28/07 e divergem. Nenhuma das outras 18 foi checada, e a taxa observada até agora é de 2 erros em 2 testes.
1. O 2T26 é 100% estimativa. Não existe uma única data confirmada do trimestre corrente, e a temporada começa agora (4 datas até 30/07).
2. Dos 1T26, 14 de 20 continuam "agendado" para datas de abril/maio que já passaram há mais de dois meses. Ninguém promoveu os status para "divulgado" depois do fato. Hoje isso não vaza para a UI porque o campo status da divulgação passada não é exibido, mas confirma que a base não tem manutenção (CAL-004).
3. Fonte primária aparece uma única vez em 40 registros: o RI da Gerdau, no 1T26. Todo o resto é secundária ou extrapolação (violação da hierarquia do relatório 02).

## 2. Como isso chega ao usuário

O trajeto completo está no relatório 01 (fluxo 4) e no registro CAL-001/CAL-003. O resumo com os três agravantes de hoje:

1. **Petrobras e Bradesco, 2T26 estimado para hoje, 28/07.** A UI exibe "Próxima divulgação 2T26: 28/07/2026 · AGENDADO" (`app/index.html:4869` colapsa "estimado" em AGENDADO). O usuário abre o dashboard hoje e lê que dois dos maiores emissores do país divulgam resultado hoje, com selo de agendamento, sustentado por extrapolação de padrão histórico feita em maio. No caso do Bradesco a data é comprovadamente errada, a oficial é 05/08 (seção 3). No da Petrobras, não confirmada em nenhuma direção.
2. **Vale, 2T26 estimado para 24/07, data que já passou e que é errada.** Para a Vale, `obterCalendarioEmpresa` não encontra data futura e devolve o 24/07 como `ultima_divulgacao_prevista`. A UI então exibe "Última divulgação 2T26: 24/07/2026" (`app/index.html:4871-4872`), afirmando como fato pretérito um evento que o sistema nunca confirmou que aconteceu, e que oficialmente ainda não aconteceu: a Vale divulga em 30/07 (seção 3). É a forma mais aguda do CAL-001, estimativa vencida vira história.
3. **A agenda de eventos** (`agenda:eventos`, horizonte 90 dias) publica cada uma dessas datas como "2T26 - divulgacao de resultado" sem os campos `status` e `nota` (`api/v4.9.182.js:10989-11001`), então e-mail e painel de agenda herdam a estimativa como fato.

## 3. Validação contra fonte oficial (CAL-002, P0 ativo)

Consultas executadas em 2026-07-28T08:00Z (05:00 BRT), primeiro nível da hierarquia do relatório 02 (RI da companhia), captura por `curl.exe -sL` com a saída registrada.

**Bradesco.** Fonte: `https://www.bradescori.com.br/informacoes-ao-mercado/agenda-2t26/` (HTTP 200, 66789 bytes). Tabela da própria página:

| Evento | Data | Horário |
|---|---|---|
| Período de Silêncio | 22/07/2026 a 05/08/2026 | — |
| Divulgação de Resultados | 05/08/2026 | Após o fechamento dos mercados, B3 e NYSE |
| Videoconferência | 06/08/2026 | 10h30 (horário de Brasília) |

Sistema: 28/07. Oficial: 05/08. Divergência de 8 dias, e a data que o sistema exibe como AGENDADO está dentro do período de silêncio declarado pelo banco, ou seja é uma data em que a divulgação seria formalmente impossível.

**Vale.** Fonte: `https://vale.com/pt/w/vale-divulga-as-datas-para-o-relatorio-de-desempenho-no-2t26`. Texto do comunicado: "Divulgação dos resultados do 2T26: Data: 30 de julho de 2026 (quinta-feira), Horário: Após o fechamento do mercado". O mesmo comunicado traz "Relatório de produção e vendas do 2T26: Data: 21 de julho de 2026 (terça-feira), Após o fechamento", evento distinto que não é o resultado financeiro.

Sistema: 24/07, exibido como "Última divulgação". Oficial: 30/07, ainda não ocorrido. A proximidade entre o 24/07 do sistema e o 21/07 do relatório de produção sugere que a extrapolação histórica confundiu os dois eventos, hipótese não confirmada.

**Petrobras.** Não confirmada. Nenhuma fonte primária reproduzível foi obtida nesta sessão, e a data de hoje (28/07) segue exibida como AGENDADO sem respaldo. Permanece pendência de validação dentro deste ID, sem afirmação em nenhuma direção.

Fontes secundárias não foram usadas para decidir nada, conforme a regra. CVM e B3 não precisaram ser consultadas nos dois casos fechados, o primeiro nível bastou.

Desfecho: dois casos encerrados como divergência oficial confirmada, um mantido como pendência explícita. A correção das datas é mutação de produção (override em KV ou base do bundle) e depende de Gate C, com os pré-requisitos F0 do relatório 04. Nada foi executado.

## 4. Estrutura existente que a correção deve aproveitar

O sistema já tem as peças, o que falta é ligá-las:

1. Overrides em KV (`calendario:overrides:v1`) com endpoint admin de escrita e rebuild automático da agenda. Defeito: o selo da UI não os lê (CAL-003).
2. Campo `status` e `nota` honestos na origem. Defeito: descartados na exibição (CAL-001).
3. Ferramenta de staleness (`listarEmissoresCalendarioStale`, marca sem_calendario e stale acima de 7 dias). Defeito: nenhum consumidor automático (CAL-004).

## 5. Critérios de aceite consolidados da família CAL

1. Nenhum caminho de exibição descarta `status`/`nota`; estimativa aparece como ESTIMADO (CAL-001).
2. Bradesco 05/08 e Vale 30/07 corrigidas no sistema com `fonte` primária e `status` correto; Petrobras confirmada por fonte primária ou exibida como estimativa; nenhuma data com selo de certeza sem fonte oficial (CAL-002).
3. `op=calendario` e agenda leem a mesma base mesclada com overrides (CAL-003).
4. Staleness do calendário visível em canal monitorado, e revalidação 2T26 com hierarquia de fontes (CAL-004).
