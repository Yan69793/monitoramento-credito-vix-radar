# 50 - Análise Competitiva e Baseline SEO — 2026-07-11

Escopo: concorrentes do VIX Radar no nicho de monitoramento de crédito privado/renda fixa corporativa no Brasil — sites, preços, posições de ranking (SERP), espaços de mercado não ocupados e mecanismo de alerta mensal de ultrapassagem. Consultas realizadas em 2026-07-11 ~02h-02h30 BRT. Classificação das afirmações: [CERTO] fato verificado com fonte · [PROVÁVEL] inferência forte · [HIPÓTESE] não validada.

---

## Sumário executivo

1. [CERTO] **Nenhum concorrente comercial ocupa as SERPs das keywords de categoria do nicho.** Das 10 keywords medidas no Google BR, nenhuma tem produto rankeando no top 10 — as SERPs são dominadas por PDFs de políticas de compliance de gestoras e conteúdo educacional de corretoras. O espaço SEO transacional do nicho está vago.
2. [CERTO] **vixradar.com só rankeia na quase-marca**: #4 em "radar de crédito privado" (atrás de um podcast espanhol e de páginas de fundos com "Radar" no nome) e #1 na marca "vix radar". Ausente do top 10 nas 8 keywords restantes.
3. [CERTO] **Os concorrentes diretos vendem dados, não monitoramento**: Quantum Axis a R$ 1.940–2.810/mês por licença e Economatica na casa de R$ 2,8 mil/mês (contratos públicos) contra VIX Radar Essencial R$ 119 e Profissional R$ 490. Nenhum deles entrega monitoramento contínuo de eventos de crédito com IA e verificação adversarial.
4. [PROVÁVEL] **O espaço "monitoramento de eventos com IA por menos de R$ 500/mês" está estruturalmente vazio** — é o posicionamento do VIX Radar, sem incumbente direto identificado.
5. Ameaças reais: pivot IA/MCP da Economatica (2026), o relatório recorrente "Radar do Crédito Privado" da XP (colisão de nome na quase-marca) e o "Radar" da Uqbar em securitização.
6. **Mecanismo de alerta mensal implantado e validado**: task `VIXRadar-Ranking-Mensal` (dia 1, 11h30 BRT) mede as 10 keywords, compara com a baseline e alerta ultrapassagem por nota Obsidian + e-mail + toast. Baseline 2026-07 criada.

---

## Metodologia e instrumentos

- **Pesquisa qualitativa e preços:** Firecrawl search/scrape (proxy de Google BR, `location: Brazil`), incluindo contratos públicos de RPPS/órgãos (PNCP, prefeituras) como fonte primária de preço praticado.
- **Baseline SERP de referência (Tabela A):** Firecrawl `location: Brazil` — retrato mais próximo do Google BR real.
- **Baseline do monitor mensal (Tabela B):** `claude -p` + WebSearch (backend US) — instrumento que a rotina mensal usa. As comparações mês a mês são sempre feitas no mesmo instrumento; mudança de instrumento força rebaseline sem alerta (implementado no script).
- **Limitação declarada:** o WebSearch não reproduz o SERP do Google BR — ex.: vixradar.com é #4 em "radar de crédito privado" no Google BR, mas ausente no WebSearch. Consequência: alertas de "queda própria" são menos sensíveis (falso negativo possível); alertas de movimento de concorrente funcionam normalmente. Upgrade futuro, se precisão BR exata virar requisito: API de SERP dedicada (Serper/SerpAPI) — descartado por ora (exige conta/chave nova; decisão do operador em 11/07).

---

## Mapa competitivo

| Player | Categoria | Foco | Preço observado | IA | Monitoramento de eventos de crédito |
|---|---|---|---|---|---|
| **Comdinheiro (Nelogica)** | Dados multi-asset | Ações, fundos, renda fixa, consolidação de carteiras; forte em RPPS/consultorias | Basic+ **R$ 249,90/mês** (homepage, 11/07) [CERTO]; Pro/institucional sob consulta | Não anunciada | Não [PROVÁVEL] |
| **Quantum Finance (Axis/Portfólio)** | Dados multi-asset | Fundos + renda fixa; gestão de carteiras; RPPS via licitação | **R$ 1.940 / 2.450 / 2.810 por mês/licença** (contrato BERTPREV, PDF público; corroborado por ItuPrev 2023, PAULIPREV 2019, IPERGS) [CERTO como evidência documental; vigência atual: PROVÁVEL] | Atom Expert System (regras, não LLM) | Não — blog educacional sobre análise de debêntures, sem produto de alertas [CERTO na SERP] |
| **Economatica** | Dados enterprise | 40 anos de histórico; Platform, Terminal, Excel, Data Feed, **APIs e MCP**; reposicionada 2026 como "dados para humanos e agentes de IA" | Funpresp 2014: **R$ 2.801/mês** [CERTO histórico]; hoje sob consulta | **Sim — infraestrutura para agentes (MCP)** [CERTO posicionamento] | Não — vende o dado, não o sinal |
| **ANBIMA Data / debentures.com.br** | Dados oficiais | Base gratuita de debêntures/CRI/CRA, documentos e preços | **Gratuito** [CERTO] | Não | Não — consulta passiva |
| **Uqbar** | Inteligência de securitização | CRI/CRA/FIDC/FII; anuários, cursos, plataforma com "**Radar personalizado**" | Assinatura (valor não público) | Não anunciada | Parcial — indicadores de mercado, não eventos por emissor corporativo |
| **XP Research (conteudos.xpi.com.br)** | Research sell-side | Relatórios de renda fixa; publica o recorrente "**Radar do Crédito Privado**" | Gratuito com conta XP | n/a | Não é monitoramento de carteira — é relatório periódico genérico |
| **BRITech** | Tech de portfólio | Plataforma enterprise para gestoras/wealth; produz conteúdo sobre crédito privado | Enterprise sob consulta | Parcial | Não — workflow de portfólio, não sinal de crédito |
| **Mais Retorno** | Dados retail | Fundos e conteúdo educacional | Freemium | Não | Não |
| **Agentes fiduciários (Oliveira Trust, Vórtx, etc.)** | Serviço regulatório | Monitoram covenants por emissão, ex-officio | Embutido na emissão | Não | Sim, mas **ex-post, por emissão, não como SaaS de carteira** [PROVÁVEL] |
| **In-house (ex.: JGP)** | Build interno | Gestoras grandes constroem base proprietária de crédito | Custo interno | Sim | Sim — mas inacessível ao mercado [CERTO pela página institucional da JGP] |

Leitura do mapa: o eixo preço vai de gratuito (dado bruto/research genérico) a R$ 2-3 mil/mês por licença (dado profissional). O eixo funcional vai de "dado passivo" a "sinal acionável". O quadrante **sinal acionável + preço acessível** tem um único ocupante identificado: VIX Radar (R$ 119/490).

---

## Baseline SERP — Tabela A (Google BR via Firecrawl, 11/07/2026)

| Keyword | vixradar.com | Quem domina o top 10 | Natureza da SERP |
|---|---|---|---|
| monitoramento de crédito privado | ausente | PDFs de políticas de gestoras (RJI, DSK, RBR, Eagle, Vinci, Absoluto, HIX, G5, Prisma) | Compliance — zero produto |
| monitoramento de debêntures | ausente | ANBIMA Data, debentures.com.br, blog Quantum (#3), BTG, Oliveira Trust, XP | Educacional — zero produto |
| radar de crédito privado | **#4** | Podcast ES (#1), fundo Gorila (#2), fundo Capitânia RADAR 90 (#3), **XP "Radar do Crédito Privado" (#5)** | Mista — diluição do termo "radar" |
| eventos de crédito renda fixa | ausente | Inter, XP "Eventos de Pagamentos" (#2), BB, FGV, gov.br | Educacional — zero produto |
| monitoramento de emissores de renda fixa | ausente | BB, XP research, blog Quantum (#3), BTG, Empiricus, Mais Retorno | Educacional — zero produto |
| plataforma de crédito privado para gestoras | ausente | Private credit internacional (GS, JPM, UBS, DB) em ES | Termo sem dono em PT-BR |
| alerta de downgrade debêntures | ausente | Fitch (ações de rating), NeoFeed, PDFs de emissores | Notícias/regulatório — zero produto |
| ferramenta risco de crédito debêntures carteira | ausente | Acadêmicos (SSRN, SciELO), blog Quantum (#4), calculadora Carteira Perfeita (#7) | Acadêmica — quase zero produto |
| análise de crédito privado com IA | ausente | Vendors de concessão de crédito PF/PJ (Soliduz, Dimensa, Neurotech) | **Intenção errada** — SERP é de concessão, não buy-side |
| monitoramento de carteira de renda fixa | (não medida neste instrumento — entra no ciclo mensal) | — | — |

## Baseline do monitor — Tabela B (WebSearch, instrumento do mecanismo, 11/07/2026)

Gerada pela primeira execução real da rotina — fonte: `SEO/Ranking SEO 2026-07.md` e `scripts/seo/ranking_state.json`.

| Keyword | vixradar | Concorrente mais bem posicionado |
|---|---|---|
| monitoramento de crédito privado | - | - |
| monitoramento de debêntures | - | quantumfinance.com.br (#1) |
| radar de crédito privado | - | - |
| eventos de crédito renda fixa | - | conteudos.xpi.com.br (#1) |
| monitoramento de emissores de renda fixa | - | quantumfinance.com.br (#8) |
| plataforma de crédito privado para gestoras | - | - |
| alerta de downgrade debêntures | - | - |
| ferramenta risco de crédito debêntures carteira | - | quantumfinance.com.br (#2) |
| análise de crédito privado com IA | - | - |
| monitoramento de carteira de renda fixa | - | - |

---

## Diagnóstico SEO

- [CERTO] vixradar.com está **fora do jogo orgânico** em todas as keywords de categoria — mas os adversários dessas SERPs são PDFs estáticos e posts educacionais, o tipo de conteúdo mais fácil de superar com página otimizada.
- [CERTO] A quase-marca "radar de crédito privado" está diluída: XP publica relatório recorrente com esse exato nome (#5, um degrau abaixo do vixradar), Uqbar tem feature "Radar", Capitânia e Gorila têm fundos "Radar". Risco real de a XP tomar a posição — é exatamente o cenário que o monitor mensal alerta.
- [PROVÁVEL] "análise de crédito privado com IA" traz intenção errada (concessão de crédito, não buy-side). Kit mensal mantém o termo por ora; candidata a substituição por "ia para renda fixa" ou "ia para análise de debêntures" na revisão de agosto.
- **Recomendações (não executadas — decisão de produto):**
  1. Uma página/landing por keyword de categoria (começar por "monitoramento de debêntures" e "monitoramento de crédito privado") com conteúdo institucional + demo do card de evento.
  2. Página "alertas de downgrade" — SERP sem nenhum produto, aderência total à proposta do Radar.
  3. Conteúdo comparativo de preço (R$ 119 vs R$ 2-3k/seat dos incumbentes) para as buscas de fundo de funil.

---

## Espaços de mercado não ocupados (gaps)

1. **Monitoramento de eventos com IA no segmento R$ 100–500/mês** — [PROVÁVEL] vazio estrutural: incumbentes vendem dado caro por seat; research é gratuito mas genérico e não monitora a carteira do cliente; fiduciário é ex-post e por emissão; build interno só para gestora grande. Único ocupante identificado: VIX Radar.
2. **SEO transacional do nicho** — [CERTO] nenhuma keyword de categoria tem dono comercial. Custo de entrada baixo, retorno composto.
3. **RPPS via licitação** — [PROVÁVEL] segmento comprovadamente pagante (ItuPrev, BERTPREV, PAULIPREV, IPERGS contratando Quantum/Economatica a R$ 2-3k/mês, PDFs públicos). Um tier institucional do Radar a R$ 490 com monitoramento de eventos seria proposta agressiva. Exige adequação a processo licitatório (documentação, CNPJ, possivelmente pregão) — esforço comercial, não técnico.
4. **Tesourarias corporativas e family offices sem Bloomberg** — [PROVÁVEL] já é o ICP do Radar (caso Mirabaud); nenhum incumbente atende esse bolso com sinal acionável.
5. **Alertas de downgrade tempestivos e acessíveis** — [CERTO na SERP] nem as agências de rating oferecem push acessível local; o gap aparece literalmente na busca sem produto.
6. **Sinal de crédito para agentes de IA (API/MCP)** — [HIPÓTESE de produto] a Economatica validou a demanda de "dados para agentes"; o Radar poderia expor os eventos verificados via MCP/API como diferencial para gestoras que estão montando seus próprios agentes.

## Ameaças

- **Economatica IA/MCP** (movimento 2026 confirmado): reduz a distância entre "ter o dado" e "ter o sinal" para clientes tecnicamente sofisticados.
- **XP na quase-marca**: publica recorrentemente "Radar do Crédito Privado"; pode consolidar a posição orgânica acima do vixradar.
- [HIPÓTESE] Incumbente (Quantum/Comdinheiro/Nelogica) acoplando camada de alertas com LLM sobre a base existente — o custo deles para copiar a feature é menor que o custo do Radar para copiar a base de dados.
- **Limitação do instrumento**: o monitor mensal usa WebSearch (US) — queda própria no Google BR pode não ser detectada de imediato (falso negativo). Mitigação: medição pontual via Firecrawl nas revisões trimestrais.

---

## Mecanismo de alerta mensal — implantado e validado 2026-07-11

| Item | Valor |
|---|---|
| Task | `VIXRadar-Ranking-Mensal` — dia 1 de cada mês, 11h30 BRT (fora da janela matinal 10h00/10h20), `IgnoreNew`, limite 30 min. Registrada via XML (`Register-ScheduledTask -Xml`); próxima execução **01/08/2026 11:30** |
| Script | `scripts/run_vixradar_ranking_mensal.ps1` (`-DryRun`, `-Quiet`, `-Model`; default `claude-haiku-4-5-20251001`) |
| Config | `scripts/seo/keywords.json` — 10 keywords, 8 domínios concorrentes, destinatário do alerta (editável) |
| Estado/histórico | `scripts/seo/ranking_state.json` (última medição) + `logs/seo/ranking_history.jsonl` (série) |
| Saída mensal | Nota `Obsidian VIX Radar/SEO/Ranking SEO YYYY-MM.md` + log `logs/routines/vixradar-ranking_*.log` + `vixradar-ranking_metrics_*.json` |
| Gatilhos de alerta | **Ultrapassagem** (concorrente que não estava à frente passou à frente), **queda própria ≥ 2 posições ou saída do top 10**, **entrada de concorrente no top 10** em keyword onde o Radar está ausente |
| Canais | Nota Obsidian (sempre) + e-mail via Resend (requer `RESEND_API_KEY` env User — sem ela degrada com aviso no log) + toast Windows (o push do app Claude não existe em execução headless local; toast é o substituto) |
| Guards | exit 7 auth-fail, exit 8 refusal, exit 1 medição inválida (nunca exit 0 silencioso), mutex `Global\vixradar-ranking-mensal`, UTC-3, encoding UTF-8 nos 2 sentidos do pipe (contramedida mojibake OEM850 — o 1º run real reproduziu o bug histórico; corrigido e re-executado limpo), pareamento keyword→resultado com fallback por índice |
| Validação executada | dry-run baseline (exit 0) · dry-run com estado adulterado → 20 alertas detectados (ultrapassagem + queda), degradação sem Resend avisada · 2 runs reais (1º com mojibake → corrigido; 2º limpo, 39-69s, baseline criada) · XML da task conferido (`ScheduleByMonth/Day=1`) |
| Reversão | `Unregister-ScheduledTask -TaskName 'VIXRadar-Ranking-Mensal' -Confirm:$false` |
| Custo | ~1 execução/mês de `claude -p` Haiku com 10 WebSearches (centavos de dólar por ciclo se rodar por token; nesta validação rodou via assinatura — `ANTHROPIC_API_KEY` não visível no shell filho) |

## Pendências derivadas

- [ ] **SEO1 — Setar `RESEND_API_KEY` (User)** para ativar o canal de e-mail do alerta: `[Environment]::SetEnvironmentVariable('RESEND_API_KEY','re_...','User')` — chave em resend.com/api-keys (mesma conta da newsletter). Sem ela: nota + toast apenas.
- [ ] Revisão do kit de keywords em agosto (trocar "análise de crédito privado com IA"?; conferir se vixradar entra no top 10 do instrumento).
- [ ] (Opcional, produto) Executar as 3 recomendações SEO da seção Diagnóstico.
- [ ] (Opcional, infra) Migrar medição para API SERP dedicada se precisão Google BR exata virar requisito.

## Fontes (consulta 2026-07-11)

- Comdinheiro Basic+ R$ 249,90/mês: https://www.comdinheiro.com.br/ (title da homepage)
- Quantum Axis R$ 1.940/2.450/2.810: https://bertprev.sp.gov.br/arquivos/contratos/integra/quantum/contrato.pdf · corroboração: https://ituprev.sp.gov.br/wp-content/uploads/2023/08/20230814-20--pa-00213-2023-aquisio-de-software-para-carteira-inv--e-mercado.pdf · https://pauliprev.sp.gov.br/wp-content/uploads/2019/08/contrato-quantum.pdf
- Economatica R$ 2.801/mês (2014): https://www.funpresp.com.br/wp-content/uploads/2020/07/CONTRATO-no-02-2014-Economatica-Software.pdf · posicionamento IA/MCP: https://www.economatica.com/
- Quantum institucional: https://quantumfinance.com.br/
- Uqbar plataforma/Radar: https://uqbar.com.br/plataforma-institucional/
- ANBIMA Data (gratuito): https://data.anbima.com.br/ · https://www.debentures.com.br/
- XP "Radar do Crédito Privado": https://conteudos.xpi.com.br/renda-fixa/relatorios/radar-do-credito-privado-licoes-do-1t26-e-expectativas-para-o-2t26/
- JGP base proprietária: https://www.jgp.com.br/credito/
- SERPs completas: resultados Firecrawl arquivados nesta sessão (transcript 11/07); baseline do monitor em `scripts/seo/ranking_state.json`
