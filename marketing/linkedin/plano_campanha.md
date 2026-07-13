# plano_campanha.md — Campanha LinkedIn VIX Radar (8 semanas)

Cronograma full-funnel para o buy-side de crédito privado brasileiro. Premissas: foco em lead, começar orgânico e escalar os melhores posts como Thought Leader Ads, voz principal no perfil do Yan Szuchmacher.

## Princípios

- Começar **orgânico**. Só colocar verba atrás de post que já performou organicamente (base do Thought Leader Ad).
- Público **estreito e qualificado** (ver icp.md): o universo real de crédito privado no Brasil é ~8-15k pessoas. Não afrouxar segmentação para inflar alcance.
- Topo de funil = **newsletter**, não demo. Demo/acesso fica para o público quente.
- Ciclo semanal de experimentos (ver ads-history.md): audita, propõe, aprova copy, sobe pausado, roda 7 dias, avalia, decide, registra.

## Segmentação base (nicho, ver icp.md)

- Job Function: Finance / Investment Management / Risk.
- Seniority: Manager, Director, VP, CxO, Owner.
- Industry: Investment Management / Financial Services / Capital Markets / VC & PE.
- **Member Skills (estreita para crédito):** Fixed Income OU Credit Risk (+ Credit Analysis, Portfolio Management, Asset Management).
- Localização: Brasil. Público esperado por conjunto: 8-15k. Desligar LinkedIn Audience Network no início.

## Cronograma

### Semanas 1-3 — Awareness / topo (público frio)
- Objetivo: alcance qualificado e autoridade; construir o pool de retargeting; crescer a newsletter.
- Orgânico: 3-4 posts/semana no perfil do Yan (dor do gestor, framework de risco, caso setorial público, bastidor do produto).
- Pago (a partir da semana 2, sobre o melhor post orgânico): **Thought Leader Ad** com objetivo de engagement/awareness. CTA newsletter.
- Formato de apoio: **Single Image** com um número de impacto, objetivo awareness barato.
- CTA primário: newsletter (Lead Gen Form ou landing de captura).

### Semanas 3-6 — Consideração / meio (público morno)
- Objetivo: gerar lead qualificado com material de valor.
- Público: Matched Audiences (engajou com os posts, viu vídeo, visitou vixradar.com) + lookalike quando houver volume.
- Formatos: **Document Ad / Carrossel** (ex.: "5 sinais de deterioração de crédito privado", trecho de relatório de emissor) com **Lead Gen Form** (converte 2-3x mais que landing externa).
- CTA: baixar relatório/framework.

### Semanas 6-8 — Conversão / fundo (público quente)
- Objetivo: solicitação de acesso ao painel / conversa comercial.
- Público: retargeting de alta intenção + ABM em contas nomeadas (gestoras, tesourarias, family offices).
- Formatos: **Conversation/Message Ad** e Single Image de produto+preço para retargeting.
- CTA: solicitar acesso / falar com o time.

## Split de orçamento

- Inicial: **40% awareness / 35% consideração / 25% conversão**.
- Após 30-60 dias, com o pool de retargeting maduro, migrar verba para meio/fundo (onde o custo por oportunidade cai).
- Espaçamento de 3-5 dias entre toques na mesma pessoa.

## Metas de CPL (ajustadas ao ticket real — não usar benchmark de enterprise)

O ticket Essencial é R$ 119/mês; o LTV realista fica em ~R$ 600-1.200/ano por assinante (dado o churn). Portanto o benchmark genérico de US$ 150-300/lead de "wealth/fintech" **não se aplica** ao funil do Essencial — CPL acima de ~R$ 80 inviabiliza a economia. Metas realistas:

| Estágio | Ação | CPL alvo |
|---|---|---|
| Topo | Cadastro na newsletter | R$ 15-40 |
| Fundo (Essencial R$ 119) | Solicitação de acesso | R$ 40-80 |
| Fundo (Profissional R$ 490 / ABM) | Solicitação de acesso / reunião | R$ 150-300 (tolerável pelo LTV maior) |

CTR de referência: sponsored content acima de 0,5%; Thought Leader Ad acima de 1,5% (podendo chegar a ~2,7%, muito mais eficiente que single image). Tratar US$/enterprise como aspiracional, não como meta.

## Orgânico vs pago

- Cadência orgânica sustentável: 3-5 posts/semana no perfil do Yan (mix opinião / framework / prova/caso / bastidor). Regra 80/20 (80% valor, 20% promoção direta).
- Pago escala o que o orgânico validou. Não subir anúncio de post que não engajou organicamente.

## Pré-requisitos antes de ativar tráfego

- Confirmar/instrumentar a landing de captura da newsletter e o double opt-in (ver positioning.md).
- Página do VIX Radar/Szuchmacher no LinkedIn ativa (para reforço e para hospedar Document Ads).
- Pixel/Insight Tag do LinkedIn instalado em vixradar.com (para Matched Audiences e conversão).
- Definir quem é a "pessoa" do Thought Leader Ad (Yan) e autorizar o uso do post.

## Mensuração (camada de dados)

Conectar o LinkedIn Pages ao Claude via MCP (Porter Metrics) para ler métricas do orgânico em linguagem natural, achar os posts candidatos a virar anúncio e alimentar o `ads-history.md`. Usar apenas API oficial read-only — nada de extensão/scraping (risco de banimento).
