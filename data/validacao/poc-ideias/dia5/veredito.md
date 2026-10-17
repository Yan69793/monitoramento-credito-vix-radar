# Veredito das cinco PoCs, 17/10/2026

Critérios congelados em `dia1/criterios_poc.json` (sha256 `e4d09ff93e514ee109f296922ea578dff3de1de3a6fbee31abeeba645010cda9`) antes de qualquer experimento. Nenhuma PoC atingiu APROVAR. Nenhum resultado abaixo é validação estatística.

| PoC | Veredito | Por que | Próxima ação |
|---|---|---|---|
| 3 Placar com hash encadeado | **APROVAR** (como mecanismo) | Ledger com 114 alertas reais: original EXIT=0, 1 caractere alterado EXIT=1 (linha 51). 7 testes, incluindo remoção, reordenação e cadeia forjada. Não alega imutabilidade nem eficácia preditiva | Guardar a âncora (cabeça `696f8318…5c8f`) fora do disco, em `status/ESTADO.md`, e decidir o disparo diário |
| 1 Flow-at-Risk | **REVISAR** | Pressão sobe depois do evento em 5 de 6 casos, mas a antecipação não se sustenta: só GPA fica acima do p90 de controles (0,97), Raízen 0,63. Muda com a defasagem premissa (Raízen 0,97 com 90 dias). Sem volume público, não validado economicamente | Corrigir a regra "competência mais recente por fundo" (esconde linha confidencial nova) e achar denominador de volume |
| 2 Spread residual | **REVISAR** | Método passa nos 6 testes e no controle de vazamento (versão vazada reprovada). Cobertura 22,8% (limite 70%). Zero episódios independentes avaliáveis (precisa de 5): a janela avaliável vai de 30/06 a 09/07 e os rótulos acabam em 09/07 | Reavaliar quando houver rótulos de ago a out e 120 dias de série |
| 5 Margem de covenant | **REVISAR** | Extração dos limites funciona (27 de 27 campos, ajustada na própria amostra), e os limites da escritura batem 20 de 20 com o relatório do agente. O cálculo padronizado com contas CVM concorda em só 6 de 20 casos (30%, mínimo 90%) e erra o lado do limite em 11 de 20. Amostra de 10 escrituras (mínimo 20) | Calcular com a definição contratual por emissor, o que exige leitura da escritura caso a caso |
| 6 Diff de notas | **REVISAR** (método atual reprovado) | Precisão 5 de 18 (27,8%, mínimo 70%). Tabelas viram frases e notas de controladas se misturam. Separação de notas falhou na Dasa, sem recall medido | Só vale refazer restrito a dívida e eventos subsequentes, com leitura de tabela |

## Números que sustentam

- Spread: 73 emissores, 114 dias, 8.130 emissor-dias, 1.854 avaliáveis (22,8%), 114 alertas residuais (6,15% dos avaliáveis) contra 164 do z_spread nos mesmos emissor-dias (8,85%). Sobreposição de 15 em mesmo emissor e dia.
- Flow-at-Risk: 5.184 fundos com debênture, R$ 2.849 bi mapeados de R$ 8.615 bi somando os 12 meses (33%). Fundos sob pressão em 25% ou mais dos dias venderam 0,32% da posição no mês contra 0,13% sem pressão, mas só 1,1% a 2,4% dos fundo-mês têm venda registrada.
- Covenant: 10 pares escritura e relatório do agente, 2 escrituras escaneadas sem texto (Oncoclínicas, Marfrig), 4 relatórios com tabela (Dasa, Simpar, Eneva, Oncoclínicas). Dasa DL/EBITDA 4 de 4; Simpar 0 de 8 (EBITDA Adicionado e dívida contratual diferem do consolidado CVM); Dasa EBITDA/resultado financeiro 0 de 4.
- Leitura de produto: o relatório do agente chega até 357 dias depois do ITR do trimestre. A margem calculada da CVM antecipa esse documento, mas hoje daria alarme falso em Simpar (calcula 1,6 contra limite 2,0 quando o agente apura 3,1).

## Adendo 17/10 noite: margem de covenant pela definição contratual (`dia6/`)

Fórmula de cada emissor tirada da escritura com a linha citada e congelada antes da comparação. A v1 (`definicoes_contratuais.json`, sha256 `42f045aa…31d3`) é preservada. A v2 (`a307d56c…dd18`) corrige três falhas de casamento de texto e código: "ativos não financeiros" caía na exclusão, a CVM abrevia "empres." e o código de longo prazo estava errado. Nenhuma das correções muda a definição.

| Medida | Conta padrão (dia 4) | Contratual v1 | Contratual v2 |
|---|---|---|---|
| Dentro de 5% do agente, todos os índices | 6 de 20 | 6 de 16 | 9 de 20 |
| Dívida líquida/EBITDA dentro de 5% | 6 de 12 | 6 de 12 | **9 de 12** (erro mediano 2,5%) |
| Mesmo lado do limite que o agente | 9 de 20 | 16 de 16 | **20 de 20** |
| Cobertura de juros dentro de 5% | 0 de 8 | 0 de 4 | 0 de 8 |

A dívida líquida/EBITDA pela definição contratual reproduz o agente em Dasa (4 de 4) e Simpar (3 de 4). A Eneva diverge 28% e 15% no 1º e no 2º trimestre de 2025, sem causa achada. A cobertura de juros não reproduz, porque o DRE não separa juros de dívida de juros de arrendamento e de outras despesas.

O ITR fica público, em mediana, 214 dias antes do relatório anual do agente (mínimo 31, máximo 357). O sinal preventivo aparece na Dasa: a margem até 4,0x foi de 40% (set/25) para 36%, 28% e **15% (jun/26, publicado em 13/08/2026)**. O próximo relatório do agente sai em abril de 2027. Esse ponto de 2026 não tem conferência do agente.

**Veredito revisado da margem de covenant: REVISAR, com indicação de evoluir só a dívida líquida/EBITDA.** Ainda não chega a APROVAR. São 3 emissores comparáveis e menos de 20 escrituras. A concordância geral fica em 45%, abaixo do mínimo de 90%, e a Eneva tem divergência sem explicação. O caminho tem um custo que não se esconde: a definição contratual precisa ser mapeada à mão por emissor, lendo a escritura (cerca de 30 a 60 minutos cada, estimativa minha). A vantagem é que esse mapeamento vira base própria, difícil de copiar.

## O que não foi feito

Sem IA paga. Sem OCR das escrituras escaneadas. Sem short interest da B3 (fonte não verificada). Sem commit, push, deploy, nem mudança em produção, EWS 2.0, agendamentos ou providers.
