# Campanha LinkedIn — VIX Radar

Pacote de campanha de marketing no LinkedIn para o VIX Radar (monitoramento de crédito privado com IA). Estruturado no método de operar anúncios com IA: arquivos de conhecimento reutilizáveis + plano + copy pronto, alimentando um ciclo semanal de experimentos.

## Estrutura

```
marketing/linkedin/
├── README.md                     # este arquivo
├── plano_campanha.md             # cronograma full-funnel de 8 semanas, segmentação, metas de CPL
├── planejamento_campanha.csv     # tabela operacional (planejamento + colunas de resultado em branco)
├── conhecimento/                 # o "cérebro" reutilizável — toda campanha futura parte daqui
│   ├── product.md                # o que é o VIX Radar, benefícios, provas
│   ├── icp.md                    # cliente ideal, anti-ICP, segmentação de nicho BR
│   ├── positioning.md            # posicionamento, funil e papel da newsletter
│   ├── copy-rules.md             # regras de escrita e guardrails de compliance
│   └── ads-history.md            # planilha viva de experimentos (preencher a cada ciclo)
├── copy/
│   ├── posts_organicos.md        # 10 posts prontos (voz Yan)
│   └── anuncios.md               # 3 anúncios em tabela (Single Image, Document, TLA)
└── criativo/
    └── briefing_visual.md        # diretrizes de arte para o designer
```

## Premissas adotadas (ajustáveis)

1. Foco em gerar lead, sustentado por autoridade e newsletter.
2. Começar orgânico; escalar os melhores posts como Thought Leader Ads.
3. Voz principal: perfil pessoal do Yan Szuchmacher; página institucional reforça.
4. Público estreito e qualificado (~8-15k), não amplo.

## Guardrails de compliance (valem para toda peça)

1. Conteúdo informativo, **não-recomendatório** (CVM 598/2018). Não é rating.
2. Números oficiais: **103 emissores, 13 setores**.
3. IA é **Anthropic Claude**. Nunca citar OpenRouter/Gemini/Perplexity.
4. **Não** vender análise preditiva como pronta (é roadmap).
5. LGPD: não expor dado de terceiro/cliente.

## Como usar (ciclo semanal)

1. **Publicar orgânico** (3-5 posts/semana de `copy/posts_organicos.md`, no perfil do Yan).
2. **Medir** quais posts engajaram (idealmente conectando o LinkedIn Pages ao Claude via MCP da Porter Metrics — só API oficial read-only, nunca scraping).
3. **Escalar** o melhor post como Thought Leader Ad; subir os anúncios de `copy/anuncios.md` conforme o estágio.
4. **Rodar 7 dias**, registrar impressões/cliques/CTR/CPL/leads no `conhecimento/ads-history.md`.
5. **Decidir**: manter / iterar / descartar. Aprendizado recorrente vira regra em `copy-rules.md`.
6. Repetir. O CSV `planejamento_campanha.csv` é o ponto de partida operacional (as colunas de resultado ficam em branco para você preencher).

## Pré-requisitos antes de colocar verba (ver plano_campanha.md)

- Landing de captura da newsletter + double opt-in instrumentados.
- Página do VIX Radar/Szuchmacher no LinkedIn ativa.
- LinkedIn Insight Tag instalado em vixradar.com (Matched Audiences e conversão).
- Post e autorização do Yan para o Thought Leader Ad.

## Fora de escopo deste pacote

- Publicar/agendar posts ou subir os anúncios (feito manualmente por você, na sua conta).
- Geração das artes finais (o briefing orienta; a criação é etapa seguinte).
- Configuração técnica da integração MCP de métricas.

## Fontes

Dossiê de produto e melhores práticas levantados em 2026-07-13. Base factual: `app/index.html`, `README.md`, `CLAUDE.md`, vault Obsidian VIX Radar. Referências externas: método de operação de anúncios com IA (Luana Pereira), conexão LinkedIn Pages + Claude via MCP (Porter Metrics), e benchmarks B2B/LinkedIn Ads 2025-2026 (Milkable, Metricool, Factors.ai, Nav43, Impactable, The B2B House, specs oficiais do LinkedIn).
