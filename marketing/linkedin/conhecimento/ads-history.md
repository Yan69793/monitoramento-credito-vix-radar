# ads-history.md — Histórico de experimentos

Planilha viva de tudo que foi testado. Sem isto, o ciclo semanal repete o que já falhou. Preencher a cada experimento encerrado. Uma linha por variação de anúncio/post por semana.

## Como usar

- Registre a **hipótese** antes de subir (ex.: "hook de dor específica converte melhor que hook de autoridade para público frio").
- No fim do ciclo (7 dias), preencha os resultados e a **decisão** (manter / iterar / descartar) e o **aprendizado**.
- Aprendizado que se repete vira regra em `copy-rules.md`.

## Tabela

| Data início | Semana | Estágio | Formato | Público | Peça (id/hook) | Hipótese | Gasto (R$) | Impressões | Cliques | CTR | Leads | CPL (R$) | Decisão | Aprendizado |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-07-13 | 1 | Awareness | Post orgânico (perfil Yan) | Rede orgânica do Yan | Post 1 v1 — "Você acompanha mais de 100 emissores..." (sem menção a www.vixradar.com) | Post sem link/menção ao produto não gera intenção de clique — testar se falta de CTA explícito prejudica conversão | 0 | — | — | — | — | — | Descartado (excluído pelo operador antes de coletar métrica) | Confirmado na prática: post sem menção ao site "não faz sentido" (feedback direto do operador) — todo post precisa citar www.vixradar.com |
| 2026-07-13 | 1 | Awareness | Post orgânico (perfil Yan) | Rede orgânica do Yan | Post 1 v2 — mesmo texto + linha "É esse trabalho que o VIX Radar automatiza... www.vixradar.com" | Menção explícita ao site gera card de link automático do LinkedIn e mantém o post publicável com CTA real | 0 | (a preencher) | (a preencher) | (a preencher) | (a preencher) | (a preencher) | Publicado (ativo) | LinkedIn gera automaticamente um card de link rico (título + descrição do site) ao detectar www.vixradar.com no texto — confirma que og:title/description do site estão configurados corretamente |
| 2026-07-16 | 1 | Awareness | Post orgânico (perfil Yan) | Rede orgânica do Yan | Post 2 v2 — reescrita a pedido do operador (registro base "O default não manda aviso prévio... EWS") para tom mais discreto/técnico e menos comercial: "Risco de crédito raramente se anuncia. Ele se acumula... www.vixradar.com" | Operador rejeitou duas versões anteriores por soarem comerciais demais para o posicionamento pretendido (produto não-commodity); versão final remove primeira pessoa de fundador ("desenvolvi"), remove qualquer cadência de pitch, mantém apenas EWS + 103 emissores + www.vixradar.com | 0 | (a preencher) | (a preencher) | (a preencher) | (a preencher) | (a preencher) | Publicado (ativo) | A pedir 2 revisões de tom antes de aprovar, o operador confirma que a voz-padrão dos 10 posts de `posts_organicos.md` é comercial demais para o registro que ele quer no perfil pessoal — considerar revisar `copy-rules.md` para adicionar guardrail de registro (evitar primeira pessoa de fundador/pitch, preferir voz de analista/observação técnica) antes de publicar os próximos posts do pacote |
| | | | | | | | | | | | | | | |

## Metas de referência (ver plano_campanha.md para o racional)

- CTR sponsored content: alvo acima de 0,5%; Thought Leader Ad: alvo acima de 1,5% (referência real de mercado: CTR mediano de TLA em torno de 2,68% — ver `pesquisa-mercado.md`).
- CPL topo (newsletter): alvo R$ 15-40.
- CPL fundo (solicitação de acesso, Essencial): alvo R$ 40-80 (acima disso, o funil do plano de R$ 119 fica no vermelho).
- CPL segmento Profissional (R$ 490) / ABM: tolera R$ 150-300.

## Log de aprendizados consolidados

- **2026-07-13:** todo post/anúncio precisa mencionar www.vixradar.com explicitamente — sem isso, o conteúdo não gera intenção de clique nem prova a existência do produto (feedback direto do operador após publicar o Post 1 sem essa menção). Regra incorporada em `copy-rules.md` e aplicada retroativamente a todo o pacote de copy (v2, 13/07/2026).
- **2026-07-13:** pesquisa de mercado (`pesquisa-mercado.md`) mostrou que gancho de abertura tipo pergunta tem o pior engajamento medido entre os tipos testados (dado real: AuthoredUp, 309k posts) — todos os 10 posts orgânicos foram reescritos para abrir com Story ou Statement, nunca pergunta.
