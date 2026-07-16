# Campanha LinkedIn — VIX Radar

v2 — 13/07/2026. Pacote de campanha de marketing no LinkedIn para o VIX Radar (monitoramento de crédito privado com IA). Estruturado no método de operar anúncios com IA: arquivos de conhecimento reutilizáveis + plano + copy pronto, alimentando um ciclo semanal de experimentos. Revisado com pesquisa real de mercado (concorrentes de inteligência de crédito, frameworks de copywriting testados, dados de engajamento no LinkedIn, jargão e eventos reais de crédito privado brasileiro).

## Estrutura

```
marketing/linkedin/
├── README.md                     # este arquivo
├── plano_campanha.md             # cronograma full-funnel de 8 semanas, segmentação, metas de CPL
├── planejamento_campanha.csv     # tabela operacional (planejamento + colunas de resultado em branco)
├── conhecimento/                 # o "cérebro" reutilizável — toda campanha futura parte daqui
│   ├── product.md                # o que é o VIX Radar, benefícios, provas
│   ├── icp.md                    # cliente ideal, anti-ICP, segmentação de nicho BR
│   ├── positioning.md            # posicionamento, contraposicionamento de preço, funil e newsletter
│   ├── copy-rules.md             # regras de escrita, regra de gancho, regra de preço, guardrails
│   ├── pesquisa-mercado.md       # pesquisa real: concorrentes, frameworks, dados de engajamento, jargão BR
│   └── ads-history.md            # planilha viva de experimentos (já com o primeiro log real)
├── copy/
│   ├── posts_organicos.md        # 10 posts prontos (voz Yan), v2 com ganchos Story/Statement
│   └── anuncios.md               # 3 anúncios em tabela, v2 com contraposicionamento de preço
└── criativo/
    └── briefing_visual.md        # diretrizes de arte para o designer
```

## Premissas adotadas (ajustáveis)

1. Foco em gerar lead, sustentado por autoridade e newsletter.
2. Começar orgânico; escalar os melhores posts como Thought Leader Ads.
3. Voz principal: perfil pessoal do Yan Szuchmacher; página institucional reforça.
4. Público estreito e qualificado (~8-15k), não amplo.
5. **(v2)** Todo post/anúncio menciona www.vixradar.com explicitamente. Gancho de abertura nunca é pergunta — sempre Story ou Statement. Preço nunca lidera a mensagem — vem depois da razão estrutural, reconhecendo primeiro a força do concorrente caro.

## Guardrails de compliance (valem para toda peça)

1. Conteúdo informativo, **não-recomendatório** (CVM 598/2018). Não é rating.
2. Números oficiais: **103 emissores, 13 setores**. Nunca inventar estatística de uso.
3. IA é **Anthropic Claude**. Nunca citar OpenRouter/Gemini/Perplexity.
4. **Não** vender análise preditiva como pronta (é roadmap).
5. LGPD: não expor dado de terceiro/cliente.
6. Emissor nomeado (ex.: Raízen no Post 6): sempre com disclaimer explícito, sempre fato já público.

## Como usar (ciclo semanal)

1. **Publicar orgânico** (3-5 posts/semana de `copy/posts_organicos.md`, no perfil do Yan). Publicação real feita via automação de navegador (Claude in Chrome) — ver primeiro registro em `conhecimento/ads-history.md`.
2. **Medir** quais posts engajaram (idealmente conectando o LinkedIn Pages ao Claude via MCP da Porter Metrics — só API oficial read-only, nunca scraping).
3. **Escalar** o melhor post como Thought Leader Ad; subir os anúncios de `copy/anuncios.md` conforme o estágio.
4. **Rodar 7 dias**, registrar impressões/cliques/CTR/CPL/leads no `conhecimento/ads-history.md`.
5. **Decidir**: manter / iterar / descartar. Aprendizado recorrente vira regra em `copy-rules.md` ou `pesquisa-mercado.md`.
6. Repetir. O CSV `planejamento_campanha.csv` é o ponto de partida operacional.

## Pré-requisitos antes de colocar verba (ver plano_campanha.md)

- Landing de captura da newsletter + double opt-in instrumentados.
- Página do VIX Radar/Szuchmacher no LinkedIn ativa.
- LinkedIn Insight Tag instalado em vixradar.com (Matched Audiences e conversão).
- Post e autorização do Yan para o Thought Leader Ad.

## Fora de escopo deste pacote

- Geração das artes finais (o briefing orienta; a criação é etapa seguinte).
- Configuração técnica da integração MCP de métricas.

## Fontes

Dossiê de produto e melhores práticas levantados em 2026-07-13. Base factual: `app/index.html`, `README.md`, `CLAUDE.md`, vault Obsidian VIX Radar. Referências externas (v1): método de operação de anúncios com IA (Luana Pereira), conexão LinkedIn Pages + Claude via MCP (Porter Metrics), benchmarks B2B/LinkedIn Ads 2025-2026. Pesquisa aprofundada (v2, mesma data): concorrentes reais de inteligência de crédito (9fin, Octus, Debtwire, Credit Benchmark, Moody's, Quantum, Economatica), frameworks de copywriting com exemplo verificável (PAS, StoryBrand, 4 U's, Hormozi), estudo real de engajamento por tipo de gancho (AuthoredUp, 309k posts), técnicas de prova social para produto novo, contraposicionamento de preço (April Dunford, casos reais de "alternativa acessível a Bloomberg"), e eventos/jargão reais de crédito privado brasileiro — ver `conhecimento/pesquisa-mercado.md` para todas as URLs.
