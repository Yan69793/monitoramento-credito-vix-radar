# Margem de covenant pela definição contratual, rodada v3 (17/10/2026)

Definições v3 congeladas antes do cálculo (sha256 `6842fa32f52ba279785128e446b732169e8348686598507becc86a20ca93cba1`). A v1 e a v2 seguem intactas. A classificação reproduzível ou parcial foi registrada antes de ver qualquer razão.

## Concordância com o relatório do agente fiduciário (tolerância de 5%)

| Grupo | Pares | Dentro de 5% | Mesmo lado do limite | Cálculo CVM acima do agente |
|---|---|---|---|---|
| Dívida líquida/EBITDA, definição reproduzível (Dasa, Simpar, Eneva, Engie, Sanepar) | 20 | **13** (65%) | 20 | 16 |
| Dívida líquida/EBITDA, definição parcial (Localiza, Energisa, Equatorial) | 12 | 0 | 12 | **12** |
| EBITDA/despesa financeira, reproduzível (Dasa, Simpar, Engie, Sanepar) | 16 | 0 | 16 | 6 |
| Total | 48 | 13 (27%) | 48 | 34 |

Por emissor, dívida líquida/EBITDA: Dasa 4 de 4, Engie 4 de 4, Simpar 3 de 4, Eneva 2 de 4, Sanepar 0 de 4, Localiza 0 de 4, Energisa 0 de 4, Equatorial 0 de 4.

## O que se aprende

- **Quando a definição cabe nas contas da CVM, a dívida líquida/EBITDA reproduz o agente.** Dasa e Engie batem em todos os trimestres. O erro mediano nesses casos é de poucos pontos percentuais.
- **Quando não cabe, o cálculo erra para cima, nunca para baixo.** Nos 12 pares parciais (Localiza +10%, Energisa +13 a 19%, Equatorial +8 a 52%) o cálculo ficou sempre acima do agente. Somando os reproduzíveis, a CVM superestima a alavancagem em 28 dos 32 trimestres de dívida líquida/EBITDA. Para alerta preventivo isso significa mais alarme falso do que alarme perdido, o lado menos caro.
- **O lado do limite bate nos 48 casos, mas isso pouco prova.** Só 2 dos 48 estão a menos de 15% do limite, e nenhum cruzou.
- **A cobertura de juros não reproduz.** 0 de 16. O DRE não separa os juros de dívida do resto da despesa financeira. Fica fora.
- **Dois casos reproduzíveis falham sem explicação.** Sanepar fica 46 a 53% acima do agente nos 4 trimestres e a Eneva 28% e 15% nos dois primeiros trimestres de 2025 (diagnóstico em `eneva_diagnostico.json`). A Sanepar mede em base individual, que o motor cobre, mas o gap ficou.

## Extração das escrituras (fora da amostra)

Em 5 escrituras novas, 7 de 8 covenants foram encontrados (recall 87,5%) e 16 de 21 campos estavam certos (**76%, mínimo 95%**). O defeito dominante é o operador invertido quando a escritura descreve o gatilho de vencimento ("superior a 4,0") em vez do limite mantido (Engie, Localiza). O 27 de 27 do dia 4 era de amostra ajustada. Detalhe em `conferencia_extracao_lote2.json`.

## Atualização: correção do operador e controle (`conferencia_extracao_controle.json`)

O extrator agora decide o operador pelo tipo da cláusula: negação ("não poderá ser superior") e gatilho ("caso... seja superior") invertem o literal, e cobre "maior do que" e o símbolo "≤". 42 testes passam, incluindo os 5 casos do lote 2.

O controle foram 8 escrituras que eu não tinha lido. Rotulei à mão antes de comparar: 7 covenants reais, 6 achados com 18 de 18 campos certos, e 1 perdido (Rumo, escrito com "≤"). Auren e Raízen não têm EBITDA no texto e o extrator não inventou nada. Depois de cobrir o símbolo, a Rumo também sai certa, mas deixa de contar como controle limpo.

Limites do controle: só uma das 8 usa a forma de gatilho (CCR) e nenhuma usa negação, então o conserto do operador ainda não foi testado fora da amostra em que foi desenhado. A CCR é restrição a dividendos, não covenant de vencimento, e o extrator não distingue.

## Veredito

**REVISAR**, o mesmo, mas agora com um recorte que sustenta o próximo passo.

- Não atinge APROVAR: concordância geral 27% (mínimo 90%), extração 76% (mínimo 95%), 8 emissores mapeados.
- O que ficou provado em amostra pequena: para emissor cuja definição cabe nas contas da CVM, dá para antecipar a margem de dívida líquida/EBITDA meses antes do relatório do agente (31 a 357 dias, mediana 214). Para os demais, o número serve como teto conservador, não como o número do agente.
- O produto razoável não é "o número do agente", é **margem estimada com um selo de confiança**: reproduzível (erro baixo), parcial (teto conservador) ou não calculável. Esse selo sai da classificação feita à mão na leitura da escritura.

## Próximos passos, em ordem

1. Corrigir o operador na extração pelo tipo de cláusula e cobrir "não deverá ser maior do que". Reavaliar em escrituras ainda não vistas.
2. Investigar Sanepar e Eneva, onde a definição parece cobrir e o número não bate.
3. Só então ampliar a amostra de definições (cerca de 30 a 60 minutos por emissor).
