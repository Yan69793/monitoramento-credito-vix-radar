# Conclusão final das cinco PoCs do VIX Radar (17/10/2026)

Tudo em pesquisa local, sem IA paga, sem commit, sem deploy e sem tocar em produção, EWS 2.0, providers ou agendamentos. Critérios congelados antes dos experimentos (`dia1/criterios_poc.json`). Nenhum número abaixo é validação estatística definitiva.

## Decisão por PoC

| PoC | Decisão final | Base |
|---|---|---|
| **Margem de covenant** | **Evoluir, como ferramenta assistida, só dívida líquida/EBITDA.** Reprovada como cálculo automático que replica o agente | Abaixo |
| Placar com hash encadeado | **APROVAR** como mecanismo | Original passa, alteração de 1 caractere reprova. Não prova imutabilidade nem eficácia |
| Flow-at-Risk | **REVISAR, baixa prioridade** | Pressão sobe depois do evento (5 de 6), não antes. Muda com a defasagem premissa. Sem volume público |
| Spread residual | **REVISAR, esperar dado** | Cobertura 22,8%, zero episódios avaliáveis. Reavaliar com rótulos de ago a dez/2026 e 120 dias de série |
| Diff de notas explicativas | **DESCARTAR na forma atual** | Precisão 5 de 18 (27,8%). O EWS 2.0 já cobre reapresentação e troca de auditor |

## Margem de covenant, o resultado que decide

Amostra final: 45 escrituras extraídas e 9 emissores com relatório do agente fiduciário comparável. As definições contratuais foram mapeadas e congeladas antes do cálculo (v1 a v5, todas preservadas, v5 sha256 `7aa2b3b9…580f`).

| Grupo | Trimestres | Dentro de 5% do agente | Cálculo acima do agente |
|---|---|---|---|
| Dívida líquida/EBITDA, definição cabe nas contas da CVM (Dasa, Simpar, Eneva, Engie, Sanepar) | 20 | **13 (65%)** | 16 |
| Dívida líquida/EBITDA, definição parcial (Localiza, Energisa, Equatorial, Assaí) | 16 | 0 | **16** |
| Cobertura de juros | 16 | 0 | 4 |

**Extração das escrituras, teste fora da amostra (lote 3, 21 escrituras rotuladas antes de rodar):** 15 de 16 covenants achados (94%), 41 de 45 campos certos (91%, mínimo 95%). Os erros vieram da regra de operador que eu mesmo criei: "For" de cabeçalho de tabela e uma exceção de incorrência lida como gatilho. Além disso, um número com ponto decimal, um erro de OCR e uma tabela de degraus.

**Divergências explicadas e não explicadas:**
- **Sanepar, provável e não provado:** a diferença de EBITDA fica estável em R$ 1,4 a 1,6 bi em todos os trimestres de 2025, o padrão de um item único do 1T25. O precatório foi registrado nesse trimestre (Fato Relevante de 24/04/2025). O agente mantém esse item no EBITDA, e a escritura manda tirar a receita financeira.
- **Eneva, sem explicação:** a hipótese do impairment de 4T24 foi testada e rejeitada.

**O que isso significa:**
1. Não dá para prometer "o número do agente" com dado público. Mesmo com a definição certa, 7 de 20 trimestres reproduzíveis passam de 5%, e os parciais erram 8% a 63%.
2. O erro tem direção. Em 32 de 36 trimestres o cálculo superestima a alavancagem. Para monitoramento preventivo esse é o lado barato do erro, gerando mais alarme falso do que alarme perdido.
3. A antecedência é real. O ITR fica público, em mediana, 214 dias antes do relatório anual do agente (31 a 357).
4. O "mesmo lado do limite" (52 de 52) prova pouco, porque só 4 dos 36 trimestres de dívida líquida/EBITDA estavam a menos de 15% do limite e nenhum cruzou.

**Forma recomendada do produto:** margem estimada de dívida líquida/EBITDA por emissão, com selo de confiança (reproduzível, parcial ou não calculável). O extrator propõe o covenant e a definição, uma pessoa confirma lendo a escritura, e o sistema recalcula a cada ITR com data de publicação. Sem cobertura de juros. O caso que justifica o produto é a Dasa, cuja margem até 4,0x caiu de 40% para 15% entre set/25 e jun/26, com o dado público desde 13/08/2026. Esse número de 2026 ainda não tem conferência do agente.

**Custo honesto:** a confirmação humana leva cerca de 30 a 60 minutos por emissor (estimativa minha). Para os 104 emissores, são cerca de 50 a 100 horas, uma única vez, e depois só para emissão nova.

## Arquivos

- Veredito dos 5 dias: `dia5/veredito.md`
- Covenant: `dia6/resultado_v3.md`, `dia6/covenant_contratual_resultado_v5.json`, `dia6/avaliacao_rotulos_lote3.json`, `dia6/sanepar_diagnostico.json`, `dia6/eneva_diagnostico.json`
- Código: `scripts/predictive/ideias/` (43 testes)
