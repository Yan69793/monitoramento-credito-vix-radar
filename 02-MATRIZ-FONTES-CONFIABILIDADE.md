# 02 — Matriz de Fontes e Confiabilidade VIX Radar

Data: 2026-07-28. Base: SHA `fdae5cb`, bundle `api/v4.9.182.js`. Achados citados por ID, registro canônico em `00-AUDITORIA-SISTEMA-COMPLETA.md`.

Duas funções: inventariar o que o sistema usa hoje como fonte de cada dado, e fixar a hierarquia que passa a valer para validação, principalmente de calendário corporativo.

## 1. Hierarquia de fontes (regra adotada)

Para calendário corporativo e fatos societários:

1. RI da companhia (site de relações com investidores, calendário oficial de eventos).
2. Comunicado oficial em canal regulatório: CVM (fatos relevantes, comunicados) e B3 (agenda de eventos corporativos).
3. Fontes secundárias (InfoMoney, MoneyTimes, agregadores) apenas corroboram. Nunca decidem, nunca são a única fonte de um dado exibido como confirmado.

Toda evidência externa registra URL, data e hora da consulta e timezone (America/Sao_Paulo). Divergência entre fontes termina de um de dois jeitos: resolvida por fonte oficial, ou pendência explícita com ID e dono. Aplicada em 28/07, a regra fechou dois casos como divergência confirmada pelo primeiro nível da hierarquia (Bradesco e Vale, CAL-002, hoje P0) e manteve um como não confirmado (Petrobras).

Nota de método que vale para a próxima consulta: dentro do mesmo RI, a página genérica de calendário de eventos pode ser uma SPA sem dado no HTML, enquanto a página da agenda do trimestre traz a tabela. Foi a diferença entre não achar e achar no caso Bradesco.

Para dados de mercado e macro: fonte oficial primária quando existir (BCB SGS para taxas, CVM para demonstrações, ANBIMA para curvas e spreads). Provedores gratuitos não-oficiais (Yahoo Finance) são aceitáveis para preço/volatilidade com a limitação declarada no contrato do dado.

## 2. Matriz por tipo de dado

| Dado | Fonte usada hoje | Classe | Cobertura | Frescor real | Proveniência gravada | Confiabilidade avaliada | Achados |
|---|---|---|---|---|---|---|---|
| Eventos de crédito | WebSearch (rotinas LLM, 9 rodadas por tier) + verificador adversarial | Secundárias agregadas com verificação própria | 103/103 emissores, cobertura diária | Diário (matinal + noturno) | Alta: `fontes_consultadas[]` por emissor, tier, retratação | Alta no dado, frágil na medição da própria rotina | OPS-001 |
| Cotações (séries 2y) | Yahoo Finance v8, sem autenticação | Não-oficial gratuita | 94/103 com ticker, 73/103 com série válida (meta de 27/07: 21 falhas de fetch) | Diário 17h quando a rotina roda | `fetched_at` por série | Média: sem SLA, rate limit, 9 emissores sem ticker (privados) | OPS-002 |
| Volatilidade anualizada | Derivada das séries acima (RMS log-retornos, 252 pregões) | Derivado interno | 73/103 | Diário condicionado à coleta | `gerado_em` global, estimador não declarado | Média | VOL-002 |
| `market_cap` | Não existe: o campo carrega `regularMarketPrice` | — | — | — | Nenhuma, e o nome mente | Nula | VOL-001 |
| SELIC | Constante `0.1375` no script de upload e no fallback do bundle | Constante sem fonte | Global | Congelado e comprovadamente defasado | Nenhuma, sem `as_of` | Nula: 13,75% contra 14,25% (meta, SGS 432) e 14,15% (efetiva, SGS 1178) oficiais em 28/07, mais contradição interna com "SELIC a 15%" no bundle | VOL-003, DEC-001 |
| Fundamentals (Altman, dívidas, PL) | CVM Dados Abertos, DFP 2025 consolidado | Oficial primária | 99 empresas | Anual (dt_refer 2025-12-31), atualização manual | Boa: `fonte`, `dt_refer`, `aproximacoes[]` por empresa | Alta na origem, defasagem estrutural | — |
| Z-scores/spreads ANBIMA | ANBIMA (rotina produtora não rastreada nesta sessão) | Oficial primária | Parcial (papéis líquidos) | Não verificado | `desvio_padrao` da própria fonte | Não avaliada nesta sessão (lacuna) | — |
| Calendário de resultados | Hardcoded no bundle, validado em 2026-05-09 contra InfoMoney e MoneyTimes; 2T26 por extrapolação histórica; overrides manuais em KV | Secundárias e extrapolação, congeladas | 20/103 emissores | 80 dias sem revalidação, 2T26 inteiro estimado | `fonte` e `status` por trimestre na origem, descartados na exibição | Refutada empiricamente: 2 de 2 datas checadas contra RI divergiam (Bradesco, Vale) | CAL-001..004 |
| Entrega WhatsApp | Twilio sandbox, HTTP 201 | Aceite de API, não entrega | n/a | n/a | Falsa (201 gravado como sucesso) | Nula como prova de entrega | SEC-003 |
| Entrega e-mail | Resend, erro lança exceção, health valida chave | API com erro propagado | n/a | n/a | Telemetria de erro | Média-alta | SEC-001 (resolvido) |
| Saúde do sistema | Health público do Worker + telemetria AE | Runtime observado, mas autorreportado | Global | Tempo real | `ts` no payload | Alta para disponibilidade e configuração declarada; nula como prova de entrega, de identidade de bundle ou de correção de fluxo | — |

## 3. Violações da hierarquia hoje

1. Calendário exibido como AGENDADO sustentado apenas por secundárias de maio ou por extrapolação histórica (CAL-001, CAL-004). Pela regra da seção 1, nada disso poderia aparecer como confirmado, e a checagem de 28/07 mostrou que a desconfiança era justificada: as duas datas testadas estavam erradas (CAL-002).
2. SELIC sem fonte alguma, nem primária nem secundária (VOL-003). Constante com comentário datado não é fonte.
3. `market_cap` sem fonte porque o dado não existe no pipeline (VOL-001).

## 4. O que "confiabilidade" passa a exigir no contrato

Consequência prática de DATA-001, aplicável a cada campo novo ou corrigido:

1. `fonte` (URL ou identificador da origem primária).
2. `as_of` (data do dado, não da gravação).
3. Nível de confiança quando houver gradação (confirmado, estimado, corroborado), e o nível sobrevive até a exibição, nunca é colapsado por rótulo de UI.
4. Guarda que meça a distância entre nome e fonte: campo cujo valor vem de autodeclaração, constante ou nome de objeto não entra como métrica.

Critério de aceite da matriz: a próxima auditoria consegue preencher a coluna "Proveniência gravada" com "sim" em todas as linhas que alimentam decisão do usuário, ou o dado exibe o próprio grau de incerteza.
