# Política de evidência e frescor

## Hierarquia

1. Estado vivo do próprio VIX Radar, quando o campo vem de fonte identificável.
2. Fonte primária: CVM/Empresas.NET, ANBIMA, B3, RI do emissor, agência de rating.
3. Fonte secundária especializada: imprensa financeira com data e atribuição claras.
4. Agregadores, snippets e redes sociais apenas como pista para localizar a origem.

Fonte secundária nunca substitui primária quando a primária estiver disponível.

## Pacote mínimo por afirmação factual

Registre mentalmente ou na saída estruturada:

- claim: fato afirmado;
- issuer: emissor correto;
- source: origem;
- source_date: data do documento/dado;
- observed_at: quando foi consultado;
- freshness: atual, stale ou desconhecido;
- evidence_type: primária, secundária ou derivada;
- confidence: ALTA, MÉDIA, BAIXA ou INCONCLUSIVO.

Se claim, issuer, source ou source_date estiverem ambíguos, não trate como fato confirmado.

## Regras temporais

- Sempre diferencie data do evento, data de publicação e data de observação.
- Use horário de Brasília para operações do VIX Radar.
- ANBIMA mercado secundário: divulgação diária a partir de 20h BRT.
- ANBIMA curvas de crédito: divulgação diária a partir de 11h BRT.
- Antes do horário esperado, ausência de D0 não é sinal de fonte atrasada.
- Dados abertos IPE da CVM têm atualização semanal; para eventos recentes prefira
  Empresas.NET/RAD ou o mecanismo vivo já usado pelo VIX Radar.

## Revisões e retificações

- ANBIMA: quando houver campos retificados, use o valor retificado como estado atual
  e marque que a observação anterior foi revisada.
- CVM: reapresentações e versões de documentos devem ser tratadas como revisão do
  mesmo fato quando economicamente equivalentes, não como evento independente.
- Nunca apague a existência da versão anterior se a mudança for material para auditoria.

## Mercado secundário

Ao interpretar spread ou PU:

- compare com histórico do próprio papel;
- ajuste a leitura por duration, indexador e curva de rating quando disponível;
- compare com pares/setor quando o conjunto for suficientemente homogêneo;
- use %REUNE/volume como sinal de qualidade do preço, não como risco de crédito puro;
- trate papel ilíquido com confiança menor.

Não inferir deterioração fundamental apenas de abertura de spread.

## Conflitos

Se duas fontes primárias divergem:

1. conferir timestamps e eventual republicação;
2. conferir se tratam do mesmo instrumento, entidade e período;
3. preferir a versão oficialmente retificada/mais recente;
4. se persistir conflito, marcar INCONCLUSIVO e escalar.

## Frescor da fonte != frescor da pipeline

Reporte separadamente:

- pipeline_freshness: quando o VIX Radar processou por último;
- source_freshness: quão recente é o dado na origem;
- analysis_freshness: quando o emissor foi efetivamente analisado.

Pipeline verde com fonte parada não é evidência de cobertura atual.

## Referências oficiais para rechecagem

- CVM Empresas.NET: https://www.rad.cvm.gov.br/ENETWEB
- CVM dados IPE: https://dados.cvm.gov.br/dataset/cia_aberta-doc-ipe
- ANBIMA mercado secundário e curvas: https://developers.anbima.com.br/pt/documentacao/precos-indices/apis-de-precos/debentures/
- ANBIMA curvas de crédito: https://www.anbima.com.br/pt_br/informar/precos-e-indices/curvas/curvas-de-credito.htm
- B3 UP2DATA: https://www.b3.com.br/pt_br/market-data-e-indices/servicos-de-dados/up2data/dados-disponiveis/

## Régua de confiança

A confiança mede evidência, não "certeza do modelo".

- ALTA: fonte primária atual, emissor inequivocamente mapeado e dado coerente.
- MÉDIA: fonte confiável, mas há uma lacuna relevante ou falta confirmação.
- BAIXA: apenas fonte secundária, inferência temporal ou cobertura incompleta.
- INCONCLUSIVO: conflito, stale ou evidência insuficiente.

Múltiplas matérias que reproduzem a mesma origem contam como uma evidência, não várias.

## Materialidade de crédito

Trate como potencialmente material quando houver efeito plausível sobre capacidade de
pagar, liquidez, estrutura de capital, covenant, rating/outlook, acesso a funding,
controle, risco regulatório, prioridade de credores ou precificação do passivo.

Resultado operacional positivo, notícia institucional ou oscilação isolada de mercado
não são automaticamente evento de crédito.

## Divergência mercado-fundamental

Procure, quando houver dados:
- spread/PU deteriorando sem fato fundamental novo;
- fato fundamental negativo sem repricing proporcional;
- movimento explicado por curva de rating, duration, setor ou macro;
- baixa participação REUNE/liquidez tornando o preço menos informativo.

Descreva a divergência e hipóteses concorrentes. Não rotule como "oportunidade".
