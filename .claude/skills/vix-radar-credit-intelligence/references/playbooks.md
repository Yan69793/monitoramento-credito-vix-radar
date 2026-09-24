# Playbooks

## Pulse de emissor

Entrada: nome do emissor e, opcionalmente, horizonte.

1. Ler estado vivo, últimos eventos, EWS/preditivo e dados de mercado disponíveis.
2. Comparar com o último estado válido.
3. Identificar no máximo 3 mudanças materialmente relevantes.
4. Separar deterioração, melhora e ruído.
5. Entregar: Mudou / Importa porque / Evidência / Confiança / Monitorar.

## Triage de evento

Entrada: evento/documento/notícia.

1. Confirmar emissor, data e fonte original.
2. Verificar duplicidade ou reapresentação.
3. Mapear mecanismo de crédito afetado.
4. Conferir se mercado/EWS confirmam ou contradizem.
5. Classificar usando a régua já existente do VIX Radar; não criar nova pontuação.
6. Se a evidência não fechar, INCONCLUSIVO.

## Anomalia de mercado

Entrada: spread, PU, z-score, volume ou papel específico.

1. Confirmar data e liquidez da observação.
2. Comparar com histórico do papel.
3. Comparar com curva de rating/duration e pares quando disponível.
4. Procurar fato fundamental/regulatório próximo no tempo.
5. Classificar a leitura como idiossincrática, setorial/macro, técnica/liquidez
   ou INCONCLUSIVA.

## Watchlist

Objetivo: priorizar investigação, não recomendar ativos.

Ordene por combinação de:
- mudança recente;
- severidade/materialidade;
- evidência confirmada;
- velocidade do EWS;
- divergência mercado-fundamental;
- proximidade de catalisador;
- baixa cobertura/frescor que exija rechecagem.

Saída por nome:
**Emissor | Motivo | Evidência | Confiança | Próximo gatilho**

Nunca colocar emissor no topo apenas por score alto antigo.

## Comitê de crédito

Use esta estrutura:

### Tese atual
Uma frase factual sobre o estado de crédito.

### O que mudou
Até 3 deltas com data.

### Evidências a favor
Fontes e métricas.

### Contraevidências
Fatos que enfraquecem a leitura dominante.

### Mercado
Spread/PU/liquidez/pares, se disponíveis.

### Incertezas
Lacunas, conflitos e dados stale.

### Próximos gatilhos
Datas/documentos/métricas que podem mudar a leitura.

Não incluir recomendação de compra, venda ou sizing.

## Explicar alerta/EWS

1. Mostrar os drivers observáveis que contribuíram.
2. Separar evento, mercado, fundamental e estrutural.
3. Mostrar o delta do score se houver histórico.
4. Não atribuir causalidade ao modelo além das features disponíveis.
5. Para implementação/metodologia, usar vix-radar-predictive.
