---
name: vix-radar-credit-intelligence
description: Analisa crédito no VIX Radar com foco em mudança, evidência e próximos gatilhos. Use para emissor, evento, spread/PU/liquidez, EWS, anomalia, watchlist, comitê, explicação de alerta, "o que mudou" ou "por que importa". Não use para deploy, debug ou auditoria técnica.
compatibility: VIX Radar repository; read-only by default; web/HTTP optional
---

# VIX Radar Credit Intelligence

## Missão

Transforme dados do VIX Radar em inteligência de crédito concisa, auditável e
não recomendatória. Priorize **delta → mecanismo de crédito → evidência → confiança →
próximo observável**. Nunca converta sinal em recomendação de compra ou venda.

## Escolha um único fluxo

| Pedido | Fluxo |
|---|---|
| Situação de um emissor / "o que mudou?" | Pulse de emissor |
| Documento, notícia ou fato novo | Triage de evento |
| Spread, PU, volume, z-score, liquidez | Anomalia de mercado |
| "Quem merece atenção hoje?" | Watchlist |
| Material para decisão interna | Comitê de crédito |
| "Por que o EWS/alerta subiu?" | Explicar alerta/EWS |

Carregue somente o fluxo escolhido em references/playbooks.md.
Carregue references/evidence-policy.md quando houver fonte externa, dado stale,
retificação, conflito, incerteza, mercado secundário ou justificativa de confiança.
Para metodologia quantitativa profunda, use também vix-radar-predictive.

## Núcleo obrigatório

1. **Estado vivo primeiro.** Registre as_of em BRT; documento histórico não prova estado atual.
2. **Delta antes do nível.** Compare com o último estado válido sempre que existir histórico.
3. **Separe sinais.** Fundamental, evento, mercado, preditivo e qualidade de dados.
4. **Cruze antes de concluir.** Procure confirmação, contraevidência e explicação alternativa.
5. **Desduplique e revise.** Múltiplas manchetes do mesmo fato não viram múltiplos eventos;
   republicação CVM ou retificação ANBIMA atualiza a leitura sem apagar o rastro.
6. **Falhe fechado.** Sem emissor, data, origem ou vínculo factual sustentáveis, marque INCONCLUSIVO.
7. **Não invente score.** Use materialidade/EWS existentes; recalcule só em pedido metodológico.
8. **Entregue gatilhos observáveis.** Diga o que pode confirmar, enfraquecer ou mudar a leitura.

## Saída padrão

Para perguntas simples, responda em cinco blocos curtos:

1. **Mudou** — delta relevante.
2. **Importa porque** — mecanismo de crédito.
3. **Evidência** — fonte, data e métrica.
4. **Confiança** — ALTA, MÉDIA, BAIXA ou INCONCLUSIVO.
5. **Monitorar** — 1 a 3 observáveis objetivos.

Use o formato específico de references/playbooks.md para watchlist, comparação ou comitê.

## Eficiência e limites

- Use primeiro os dados já disponíveis no VIX Radar; busque fora apenas para lacunas.
- Faça busca dirigida; não varra 104 emissores sem necessidade explícita.
- Prefira fonte primária à repetição em imprensa.
- Não carregue skills de auditoria/deploy para uma pergunta de crédito.
- Não altere produção, KV, rotinas ou código sem pedido explícito.
- Não exponha secrets ou dados privados.
- Não trate ausência de notícia como ausência de risco.
- Não confunda frescor da pipeline, da fonte e da análise.
