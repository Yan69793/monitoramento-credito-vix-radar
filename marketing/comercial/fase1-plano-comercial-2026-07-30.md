# VIX Radar — Plano Comercial, Fase 1

Documento interno. Szuchmacher Consultoria Ltda. 30 de julho de 2026.

---

## Quadro de decisão

**Contratar agência agora.** Decisão do operador. A rota solo foi considerada e descartada. O caminho escolhido é contratação de agência para execução de ABM, outbound e mídia sobre a estratégia que já existe.

Essa decisão impõe três condições para o dinheiro não queimar:

1. **Cobrança funcionando antes do primeiro anúncio.** [P0] Se a agência gerar reunião e o prospect disser sim, precisa existir um caminho para ele pagar. Sem checkout, a agência entrega reunião que não vira receita.
2. **Orçamento calibrado ao que o mercado aceita.** [Fato] Agência full-service B2B estabelecida (Sabiá, Intelligenzia, Macfor) não opera na faixa de R$ 4.000/mês. O caminho realista nesse orçamento é boutique de outbound, consultor de ABM independente ou SDR terceirizado. Ver seção 6.
3. **Piloto de 90 dias com cláusula de saída.** Sem contrato longo antes de validar execução. Métrica de sucesso: reunião com decisor qualificado e cliente pagante convertido.

[Recomendação] Resolver os P0-1 (cobrança) e P0-3 (confirmar pagantes) antes de assinar com agência. O resto dos P0 pode ser paralelo. Se o orçamento real for menor que o estimado, descer para consultor independente em vez de agência.

---

## 1. Bloqueios P0 antes de qualquer verba de mídia

Ordem de prioridade. Nenhuma agência resolve os três primeiros.

| # | Bloqueio | Esforço | Quem resolve | Impacto se não resolver |
|---|---|---|---|---|
| P0-1 | Cobrança automatizada (Stripe/Pago) | 3 a 5 dias de desenvolvimento | Desenvolvedor | Cliente diz sim e não consegue pagar |
| P0-2 | Processo manual documentado de contrato, emissão e ativação | 1 dia para documentar | Yan | Ponte até o P0-1 ficar pronto |
| P0-3 | Confirmar número real de clientes pagantes | 30 minutos | Yan | Dimensiona (ou cancela) todo o resto |
| P0-4 | Remover case Mirabaud do material comercial | 2 horas | Yan + edição de HTML | Contraparte judicial citada como cliente |
| P0-5 | LinkedIn Insight Tag em vixradar.com | 30 minutos | Desenvolvedor | Sem retargeting, sem Matched Audiences |
| P0-6 | Página institucional VIX Radar no LinkedIn | 1 hora | Yan | Sem lastro para anúncios e Document Ads |
| P0-7 | Landing dedicada de captura da newsletter | 2 horas | Desenvolvedor | Topo de funil sem ponto de conversão |
| P0-8 | Reprocessar noturno 30/07 | Executar script manualmente | Yan | Dados de 30/07 sob deepseek-v4-flash |
| P0-9 | CRM definido e operacional | 2 a 4 horas | Yan | Sem tracking de funil |

**Pré-requisitos que já existiam como pendência em 13/07 e continuam não cumpridos:** Insight Tag (P0-5), página no LinkedIn (P0-6), landing de newsletter (P0-7), Sales Navigator (não listado como P0, mas é ferramenta de ABM essencial).

[Fato] Worker v4.9.183 com ok:true, verificador_ok:true em 30/07 21:55 UTC (18:55 BRT). Rotinas voltando ao normal após correção do OAuth.

---

## 2. Revisão crítica do posicionamento existente

O que está sólido e o que precisa de ajuste antes de virar campanha.

### Sólido (mexer só se for para melhorar marginalmente)

- **ICP com anti-ICP.** A definição está cirúrgica. Universo de 8 a 15 mil profissionais no LinkedIn Brasil é realista, não é limitação. Segmentação por Skill (Fixed Income OU Credit Risk combinado com Seniority Manager+) é o coração da segmentação. [Fato: icp.md]
- **Jobs-to-be-done.** Os quatro JTBD capturam a dor real. "Saber do evento de crédito antes do mercado precificar" e "parar de varrer CVM na mão" são frases que um gestor reconhece como dele. [Fato: icp.md]
- **Contraposicionamento de preço.** A ordem está correta: reconhecer a força do terminal caro, explicar a razão estrutural (escopo mais estreito), preço como consequência. "O concorrente real não é o terminal caro, é a planilha manual" está certo. [Fato: positioning.md, pesquisa-mercado.md]
- **Regras de copy.** Gancho de abertura Story/Statement (nunca pergunta), números exatos (103, não 100+), CTA por estágio de funil, preço nunca lidera a mensagem. Calibrado com dado real de engajamento (AuthoredUp, 309k posts). [Fato: copy-rules.md, pesquisa-mercado.md]
- **Plano de campanha de 8 semanas.** Cronograma, split de orçamento, CPL alvo calibrado ao ticket real. Razoável e testável. [Fato: plano_campanha.md]
- **Pesquisa de mercado.** Cobre concorrentes, frameworks de copy, dados de engajamento e jargão de crédito. Nível de fundamentação acima da média para produto early-stage. [Fato: pesquisa-mercado.md]
- **10 posts orgânicos + 3 anúncios.** Prontos e revisados com as regras de copy. [Fato: posts_organicos.md, anuncios.md]
- **Briefing visual.** Direção clara (dark luxury, navy + gold), alinhada com a identidade existente. [Fato: briefing_visual.md]

### Precisa de ajuste

- **Case âncora Mirabaud.** [Fato] O diretório `E:\Diretorio\Claude\Processo Mirabaud` contém documentos de ação trabalhista "Yan Szuchmacher x Mirabaud Investimentos Ltda." É contraparte, não cliente. O `product.md` cita "Mirabaud (tesouraria/family office sem terminal caro)" como caso âncora. Isso precisa sair de `product.md`, da apresentação institucional, do deck Bradesco, dos posts orgânicos e de qualquer menção em copy futura. [Risco] Se já houve menção ao Bradesco BBI, verificar se o nome Mirabaud aparece no material enviado ao Igor.
- **Track record de usuários.** O deck cita 17 usuários sem separar pagantes de demo/cortesia. Com zero pagantes confirmados, o número 17 é enganoso. [Recomendação] Trocar por "X profissionais com acesso ao painel, Y em processo de validação comercial" ou simplesmente remover o número até ter dado real de faturamento.
- **Alegação de IA.** O `product.md:23` cita "Anthropic Claude (Haiku para triagem, Sonnet 4.6 para análise pesada e para a verificação adversarial)". O incidente de roteamento de 30/07 provou que essa alegação pode ser falsa sem que ninguém perceba. [Recomendação] Adicionar ao `product.md` e ao material comercial a distinção entre "arquitetura declarada" e "prova de execução". Não é para publicar, é defesa interna: se um dia um cliente fizer due diligence técnica, você consegue provar que o modelo que respondeu era o declarado.
- **Voz do Yan vs voz comercial.** O feedback registrado em `ads-history.md` (16/07) mostra que o operador rejeitou duas versões de copy por soarem "comerciais demais". Os 10 posts foram considerados com tom de pitch, não de analista. [Recomendação] Revisar `copy-rules.md` para adicionar guardrail de registro: evitar primeira pessoa de fundador com cadência de pitch, preferir voz de analista/observação técnica.
- **Newsletter como topo de funil.** A estratégia está certa, mas a landing dedicada não existe e o double opt-in não está instrumentado como página separada. Sem isso, tráfego pago para newsletter desperdiça verba. [Fato: positioning.md:41, plano_campanha.md:66]

---

## 3. Ofertas comercializáveis dentro da estrutura atual

### Oferta 1 — Essencial (R$ 119/mês)

O que entrega hoje: painel com 103 emissores, 13 setores, eventos ranqueados por materialidade, EWS, watchlist com alerta por e-mail, agenda CVM, relatório PDF white-label. Acesso por aprovação manual.

Público: analistas de crédito, gestores de asset média, family offices, profissionais de RI.

Pronto para vender? O produto está pronto. A cobrança não está. [Fato] O botão "Assinar" na landing abre formulário de cadastro, não checkout. Nenhuma integração de pagamento no Worker.

### Oferta 2 — Profissional (R$ 490/mês)

Mesmo produto base, adiciona briefing executivo, histórico estendido, múltiplos usuários.

Público: gestoras com mais de um analista, tesourarias corporativas, comitês de investimento.

Pronto para vender? Mesmo bloqueio de cobrança do Essencial.

### Oferta 3 — Newsletter gratuita (topo de funil)

Boletim semanal com os eventos mais materiais da semana, sem paywall. Double opt-in via Resend, one-click unsubscribe com HMAC.

Pronto para operar? O sistema de envio existe. A landing dedicada de captura não. [Fato: positioning.md:41]

### Oferta 4 — Tier institucional / RPPS (a construir)

[Fato] O segmento de RPPS (Regimes Próprios de Previdência Social) comprovadamente paga por ferramentas de monitoramento de crédito via licitação. Concorrentes como Quantum Axis cobram R$ 1.940 a 2.810 por licença/mês. [Fonte: contrato público de licitação verificado, citado no mapa competitivo da apresentação institucional]

O que esse tier exigiria que ainda não existe:

- CNPJ da Szuchmacher Consultoria com CNAE compatível com fornecimento para governo (verificar).
- Certidões negativas (federal, estadual, municipal, FGTS, trabalhista).
- Contrato social e documentos de habilitação jurídica.
- Atestado de capacidade técnica (precisa de pelo menos um contrato com RPPS ou órgão público).
- Proposta comercial em formato de licitação (não é landing page, é documento formal).
- Preço em reais com impostos discriminados, margem para desconto de órgão público (que pode exigir 10 a 30% sobre o preço de balcão).
- Prazo de contrato de 12 meses típico, possibilidade de renovação.

[Recomendação] Esse tier é a maior oportunidade de receita por conta, mas exige preparação documental que leva de 30 a 60 dias. Começar a reunir certidões agora, mesmo sem data de licitação definida. O preço pode ser posicionado entre R$ 1.500 e R$ 2.500/mês por licença, com desconto por volume de usuários. O custo é a documentação e o tempo do Yan, zero investimento financeiro.

[Validar] Se o CNPJ atual comporta venda para governo, ou se precisa abrir CNAE secundário.

---

## 4. Meta numérica do piloto de 90 dias

### Premissas (não validadas)

| Variável | Valor | Fonte |
|---|---|---|
| Clientes pagantes atuais | 0 (premissa) | [Validar] |
| Ticket médio mensal | R$ 250 (mix Essencial/Profissional) | landing |
| LTV estimado (12 meses, sem fidelidade) | R$ 1.800 (considerando churn) | estimativa |
| Capacidade de reuniões/semana | 4 | [Validar] |
| Orçamento total piloto 90 dias | R$ 15.000 a 30.000 | [Validar] |
| Custo de aquisição tolerável (CAC) | Até R$ 600 (3 meses de receita) | derivado do ticket |

### Cenário com agência (rota escolhida)

Piloto de 90 dias com agência executando ABM, outbound e mídia. Capacidade máxima: 16 reuniões/mês, 48 no trimestre. Custo total: R$ 21.390 (ver tabela na seção 10).

| Mês | Ação | Meta |
|---|---|---|
| Mês 1 | Setup CRM, listas ABM, início outbound, primeiros anúncios LinkedIn | 12 reuniões, 5 oportunidades, 2 contratos |
| Mês 2 | Otimização de campanha, nutrição, follow-up | 14 reuniões, 7 oportunidades, 3 contratos |
| Mês 3 | Escala do que funcionou, referral, renovação | 16 reuniões, 8 oportunidades, 4 contratos |

Meta 90 dias: 9 clientes pagantes, receita recorrente ~R$ 2.250/mês.

Custo total: R$ 21.390. CAC efetivo: R$ 2.377.

[Fato] Com ticket de R$ 119 a 490, o CAC de R$ 2.377 é viável para o plano Profissional (recupera em 5 meses) mas inviável para o Essencial (precisaria de 20 meses). A operação precisa mirar o ticket de R$ 490 ou o tier RPPS para fechar a conta.

### Cenário solo (referência, não recomendado pelo operador)

Yan opera o funil sobre a rede pessoal. Custo: R$ 390 em 90 dias (Sales Navigator), ver tabela na seção 10.

| Mês | Ação | Meta |
|---|---|---|
| Mês 1 | Networking + LinkedIn orgânico + follow-up com contatos existentes | 8 reuniões, 3 oportunidades, 1 contrato |
| Mês 2 | Continua + convite para newsletter para contatos frios | 8 reuniões, 4 oportunidades, 2 contratos |
| Mês 3 | Continua + referral dos primeiros clientes | 8 reuniões, 5 oportunidades, 2 contratos |

Meta 90 dias: 5 clientes pagantes, receita recorrente ~R$ 1.250/mês. CAC: R$ 78.

### Custo por oportunidade qualificada (limite de viabilidade)

| Ticket | CPL máximo para não operar no vermelho |
|---|---|
| Essencial (R$ 119/mês) | R$ 40 a 80 (confirmado em plano_campanha.md) |
| Profissional (R$ 490/mês) | R$ 150 a 300 |
| Mix (R$ 250 médio) | R$ 100 a 180 |

[Fato] Esses números já estavam calibrados em `plano_campanha.md`. A pesquisa de agências confirma que CPL de LinkedIn no mercado financeiro brasileiro fica entre US$ 45 e 65 (~R$ 225 a 325), acima do limite do Essencial. Isso reforça que o Essencial não comporta mídia paga, só orgânico e ABM direto.

[Recomendação] A meta do piloto, qualquer que seja a rota, não é número de reunião. É cliente pagante com cobrança recorrente ativa. Se em 90 dias não houver pelo menos 3 clientes pagantes, parar e resolver produto antes de colocar mais dinheiro.

---

## 5. Agências qualificadas

Pesquisa limitada pelo bloqueio de WebSearch/WebFetch na data da coleta (30/07, incidente de roteamento). Dados complementados com busca manual. Duas das cinco agências mencionadas no briefing (BRSA, Seja Mais) não retornaram resultado verificável algum. Seguem as que foi possível avaliar.

---

### 5.1 Intelligenzia

**Fonte:** [intelligenzia.com.br](https://intelligenzia.com.br), [Semrush](https://agencies.semrush.com/zh/intelligenzia/), [SignalHire](https://www.signalhire.com/companies/intelligenzia-brasil)

Fundação: 2012. São Paulo. 10 a 50 funcionários. Faturamento estimado: US$ 10M a 50M (não verificado).

Serviços: marketing digital B2B, inbound, mídia paga (Google, LinkedIn), SEO, inside sales, integração de CRM (HubSpot), automação de marketing. Oferece inteligência de vendas com prospecção e qualificação de leads.

Cases declarados: Atech, Access, Genesys, Zeiss. NPS 98%. Publica pesquisa "O Estado do Marketing B2B no Brasil".

**Avaliação para VIX Radar:**

A Intelligenzia é uma das agências B2B mais estabelecidas do Brasil. O ponto forte é a integração entre marketing e vendas com CRM, que é exatamente o que falta no VIX Radar. O ponto fraco: não há nenhum case no mercado financeiro entre os clientes declarados (Atech é defesa/aeroespacial, Access é RH, Genesys é contact center, Zeiss é óptica industrial). Todos são setores de indústria e tecnologia, nenhum de crédito ou finanças.

[Fato] Oferece inside sales e prospecção. [Não verificado] Se a prospecção cobre ABM com contas nomeadas ou se é inside sales genérico. [Não verificado] Se aceita piloto de 90 dias. [Não verificado] Se parte de estratégia pronta ou exige diagnóstico.

Nota preliminar: 6/10. Sólida em B2B, zero evidência em mercado financeiro.

---

### 5.2 Next4

**Fonte:** [SignalHire](https://www.signalhire.com/companies/agencia-next4), [TopSEO](https://www.topseobrands.com/br/best-ppc-firms-in-brazil)

Fundação: 2005. São Paulo. 10 a 50 funcionários. CEO: Gustavo Buonnacorso.

Serviços: vendas B2B (inbound, outbound, inside sales, field sales), inteligência comercial, prospecção ativa, estruturação de funil em Y, implementação de CRM, Google AdWords, SEO, e-mail marketing, social selling. Case de SEO: ICTQ saltou de 7 mil para 570 mil visitas mensais.

**Avaliação para VIX Radar:**

A Next4 tem um perfil mais próximo do que o VIX Radar precisa: outbound, prospecção ativa, CRM. O case de SEO é concreto e verificável. Mas o perfil parece ser mais growth digital do que ABM e venda consultiva complexa. O case de 570 mil visitas é de uma empresa de educação (ICTQ), não B2B financeiro.

[Fato] Tem serviços de outbound e prospecção. [Não verificado] Se tem metodologia de ABM ou se o outbound é volume. [Não verificado] Se tem experiência em mercado financeiro. [Não verificado] Se aceita piloto de 90 dias.

Nota preliminar: 5/10. Perfil de growth digital, não de venda consultiva B2B complexa.

---

### 5.3 Conversa.tech

**Fonte:** [Convoy PR Group](https://www.rlyl.com/uk/convoy-latam-partners/), podcast Conversa B2B

Agência de marketing B2B com foco em ABM e outbound. Parceira do Convoy PR Group (grupo global de PR para tech B2B) desde março de 2024. Mantém o podcast "Conversa B2B" apresentado por Guilherme Sboarim.

Serviços declarados: geração de leads, ABM, criação de conteúdo digital. Atende empresas de tecnologia, engenharia e energia.

**Avaliação para VIX Radar:**

O foco declarado em ABM é o ponto mais alinhado com a necessidade do VIX Radar. A parceria com o Convoy PR Group sugere algum nível de validação internacional. Mas: não há site oficial acessível (conversa.tech não retornou página verificável na busca), não há cases nominais, não há CNPJ ou headcount confirmado, e os setores atendidos (tecnologia, engenharia, energia) não incluem mercado financeiro.

[Fato] Foco declarado em ABM. [Não verificado] Site, CNPJ, cases, clientes, headcount, faturamento, metodologia. [Não verificado] Se aceita piloto.

Nota preliminar: 4/10 (não por demérito, por falta de informação verificável). Mais dados podem subir ou descer essa nota.

---

### 5.4 Sabiá (Agência Sabiá)

**Fonte:** [agenciasabia.com.br](https://agenciasabia.com.br), [BBN International](https://bbn-international.com/location/bbn-sabia-brazil-sao-paulo/), [E3 Network](https://www.e3network.com/members/sabia/)

São Paulo. 16+ anos. Full-service B2B. Membro da BBN (The World's B2B Agency) e E3 Network.

Serviços: ABM, demand generation, gestão de marca, conteúdo, eventos B2B, channel marketing, field marketing. Quatro pilares declarados: Brand Management, Conteúdo e Criatividade, Conexão e Vendas, Cultura e Engajamento.

Cases verificados:
- **Atlassian:** hub de marketing para Brasil e LATAM. Evento "ITSM Transformation" gerou 471 inscrições, 237 participantes (6x a meta). "Atlassian for Teams" com 460 inscrições, 200 participantes, maior evento da Atlassian na América Latina. Golden Bee B2B Awards 2024 (Best Agency-Client Integration).
- **FECAP Corporate:** campanha de geração de leads B2B. 105 mil pessoas impactadas, 1.000 acessos ao site, 150 leads qualificados em menos de 30 dias no LinkedIn.
- **New Relic:** evento "Future Stack" em São Paulo.

**Avaliação para VIX Radar:**

É a agência com os cases B2B mais concretos e verificáveis entre todas as pesquisadas. O case FECAP é diretamente relevante: geração de leads qualificados em LinkedIn com métrica real. O método de trabalho (reuniões quinzenais, fluxo contínuo de informação, curadoria de conteúdo) sugere senioridade de execução. Pertencer à BBN e E3 indica padrão internacional.

Ponto fraco: o foco é tecnologia/SaaS. Atlassian, New Relic, FECAP — todos são tech, nenhum é mercado financeiro ou crédito. A pergunta relevante é se a metodologia de ABM e geração de leads B2B transfere para o nicho estreito de crédito privado, ou se a falta de familiaridade com o setor gera curva de aprendizado às custas do piloto.

[Fato] Cases B2B verificados com métrica real. [Fato] Membro BBN e E3. [Não verificado] Se aceita piloto de 90 dias. [Não verificado] Se partiria do posicionamento pronto ou exigiria diagnóstico.

Nota preliminar: 7/10. Melhor case B2B, mas sem experiência em mercado financeiro.

---

### 5.5 Macfor

**Fonte:** [HubSpot Ecosystem](https://ecosystem.hubspot.com/marketplace/explore/solutions-partners), [RemoteRocketShip](https://www.remoterocketship.com/ca/company/macfor-br/jobs/sdr-outbound-worldwide-remote/)

Fundação: 2011. 51 a 200 funcionários. HubSpot Solutions Partner.

Serviços: prospecção outbound multicanal (e-mail, LinkedIn, WhatsApp, telefone, eventos presenciais), ABM, qualificação e agendamento de reuniões com C-level, marketing digital data-driven. Atende grandes contas com ciclos de vendas consultivos e longos.

**Avaliação para VIX Radar:**

O modelo multicanal com ABM e foco em ciclos longos é o desenho certo para o VIX Radar. A escala (51-200 funcionários) sugere estrutura, mas também pode significar que o piloto de R$ 15 mil é pequeno demais para receber atenção sênior. O risco de agência grande é o time A vender e o time C executar.

[Fato] ABM e outbound multicanal declarados. [Fato] HubSpot Partner. [Não verificado] Cases nominais em mercado financeiro. [Não verificado] Se aceita piloto enxuto. [Não verificado] Senioridade de quem executaria.

Nota preliminar: 6/10. Metodologia alinhada, risco de piloto pequeno receber time júnior.

---

### 5.6 Growth Gorilla (Reino Unido, case Brasil)

**Fonte:** [growthgorilla.co.uk](https://www.growthgorilla.co.uk/case-studies-page/how-we-helped-finbits-launch-and-elevate-a-b2b-lead-gen-campaign)

Agência baseada no Reino Unido. Case direto com a Finbits (plataforma brasileira de gestão financeira): 285 leads em 3 meses, redução de 66% no CPL, campanha de LinkedIn Ads com thought leadership.

**Avaliação para VIX Radar:**

O case Finbits é a evidência mais próxima de "agência que entende B2B financeiro brasileiro" entre todas as pesquisadas. Mas: é uma agência do Reino Unido, o que introduz custo em libra, fuso horário, e distância do mercado local. Para um piloto de R$ 15 a 30 mil, o custo de coordenação com agência estrangeira provavelmente inviabiliza.

Nota preliminar: 5/10. Case relevante, localização inviabiliza piloto enxuto.

---

### Agências não encontradas

- **BRSA:** Nenhum resultado verificável em múltiplas buscas. Não considerada.
- **Seja Mais:** Nenhum resultado verificável. Não considerada.

---

## 6. Ranking das agências e o problema do orçamento

A decisão está tomada: vai contratar. O desafio agora é achar quem entrega execução de ABM e outbound no orçamento disponível.

As três melhores agências por critério técnico são Sabiá (7/10), Intelligenzia (6/10) e Macfor (6/10). Mas **nenhuma das três opera na faixa de R$ 4.000/mês.** Sabiá atende Atlassian e New Relic, é membro da BBN e E3. Intelligenzia fatura dezenas de milhões. Macfor tem mais de 50 funcionários. O orçamento do cenário 2 (R$ 21.390 em 90 dias) paga um mês e meio de fee dessas agências, não três. Se uma agência qualificada cobrar R$ 8.000/mês, o piloto vai para R$ 30 a 35 mil, estourando o teto da Premissa C.

Elas foram contatadas mesmo assim? Só se o orçamento real for maior que o estimado. Caso contrário, a recomendação é ir direto nos formatos alternativos abaixo.

| Posição | Agência | Nota | Motivo |
|---|---|---|---|
| 1 | Sabiá | 7/10 | Cases B2B concretos e verificados, ABM e geração de leads com métrica real (FECAP: 150 leads em 30 dias), padrão internacional (BBN/E3), metodologia de trabalho transparente. [Risco] Orçamento provavelmente incompatível. |
| 2 | Intelligenzia | 6/10 | Agência B2B estabelecida, integração marketing+vendas+CRM, inside sales. [Risco] Orçamento provavelmente incompatível. |
| 3 | Macfor | 6/10 | ABM e outbound multicanal, HubSpot Partner. [Risco] Orçamento provavelmente incompatível e piloto pequeno tende a receber time júnior. |

As demais saem por:
- **Next4:** Perfil de growth digital, não de venda consultiva B2B.
- **Conversa.tech:** Informação insuficiente para avaliação.
- **Growth Gorilla:** Agência estrangeira, custo em libra.
- **BRSA e Seja Mais:** Não encontradas.

### Caminho realista para o orçamento disponível

Na faixa de R$ 4.000 a 6.000/mês, três formatos com fornecedores concretos identificados na pesquisa de 30/07:

---

### 6.7 Consultores de ABM/outbound independentes

Profissionais seniores que montam processo, listas, sequências e operam CRM. O Yan mantém a voz pública e fecha. Custo típico: R$ 3.000 a 6.000/mês por meio período.

**William Tadeu — Prospecção 10X**
- Fonte: [alsona.com](https://alsona.com/linkedin-experts/william-tadeu)
- 11 anos de experiência em prospecção no LinkedIn. Metodologia em três pilares: posicionamento, prospecção estratégica, gestão de vendas. Clientes relatam 20+ reuniões qualificadas por mês. Atende tanto profissionais independentes quanto equipes corporativas.
- [Não verificado] Preço, site oficial, cases nominais, experiência em mercado financeiro.

**Vanessa Carvalho — Demand Consultoria**
- Fonte: [intch.org](https://intch.org/p/16728253)
- Demand Generation Specialist. Experiência em ABM, inbound, outbound, automação de marketing. Trabalhou no Efí Bank (2024-2025) coordenando definição de ICP e estratégias de marketing digital para captação de contas estratégicas. Sócia-fundadora da Demand Consultoria.
- [Fato] Experiência em instituição financeira (Efí Bank). [Não verificado] Cases, preço, disponibilidade.

**Gustavo A. (Upwork)**
- Fonte: [Upwork](https://www.upwork.com/services/product/marketing-sales-marketing-consultation-1861744935517332582)
- 16+ anos em marketing e vendas B2B, 23 anos em vendas. Especialista em entrada no mercado brasileiro para empresas globais. Consultoria a US$ 60/sessão.
- [Não verificado] Se aceita contrato de 90 dias, se tem experiência em crédito.

**joaoluciano98 (Freelancer)**
- Fonte: [Freelancer.com](https://www.freelancer.com/u/joaoluciano98)
- LinkedIn Outbound e Lead Gen B2B. US$ 18/hora. Já fechou US$ 30M+ em contratos B2B. Clientes: Hilton, Marriott, Four Seasons, Philips, W Hotels. Métricas: taxa de aceitação, reply rate, reuniões agendadas.
- [Fato] Cases com marcas globais. [Não verificado] Se atende projetos no Brasil, se tem experiência em mercado financeiro.

---

### 6.8 Boutiques de outbound B2B

Agências menores, sem o overhead de BBN/E3/HubSpot Partner. Custo típico: R$ 4.000 a 8.000/mês.

**OUTMarketing Brasil**
- Fonte: [outmarketing.com.br](https://outmarketing.com.br), [SignalHire](https://www.signalhire.com/companies/outmarketing-brasil-marketing-para-empresas-de-tecnologia-da-informacao)
- São Paulo (Brooklin). Fundada em 2012. 10-50 funcionários. Serviços: outbound marketing, ABM, geração de leads, inbound, CRM, Google AdWords, RD Station. Tel: +55 11 3443-7705.
- [Fato] Serviços alinhados (ABM + outbound + CRM). [Não verificado] Preço, cases em mercado financeiro, se aceita piloto de 90 dias. [Risco] Receita estimada em US$ 10M-50M sugere que pode ser grande demais para o orçamento.

**HyTrade**
- Fonte: [cbinsights.com](https://www.cbinsights.com/company/hytrade), [bouncewatch.com](https://www.bouncewatch.com/explore/startup/hytrade-marketing-vendas-b2b)
- São Paulo (Parque Continental). Fundada em 2011. Serviços: prospecção outbound de vendas, inbound marketing, alinhamento marketing e vendas, marketing data-driven. Tel: +55 11 3765-3003.
- [Não verificado] Porte, cases, preço, experiência em mercado financeiro.

**Sales Boutique**
- Fonte: [salesboutique.io](https://www.salesboutique.io)
- Agência de outbound B2B. Serviços: identificação e verificação de leads, campanhas multicanal (e-mail, LinkedIn, telefone, mala direta), fluxo previsível de reuniões. Atua em múltiplos idiomas com IA para refinamento de leads.
- [Não verificado] Preço, cases, se opera no Brasil, se tem experiência em mercado financeiro.

---

### 6.9 SDR as a Service

SDR terceirizado que faz prospecção, qualificação e agendamento de reunião. Metodologia menos sofisticada que ABM puro, mas custo cabe no orçamento.

**Techsho Solutions**
- Fonte: [techshosolutions.com](https://techshosolutions.com/hire-remote-sales-reps/)
- SDR terceirizado a partir de US$ 800/mês por representante (~R$ 4.000). Ativação em 7 dias úteis. Representante dedicado, fully managed, tech stack incluso. Foco em B2B outbound. Playbook específico para expansão de SaaS no Brasil.
- [Fato] Preço público, dentro do orçamento. [Não verificado] Experiência em mercado financeiro/crédito, qualidade do SDR alocado.

**Erah**
- Fonte: [cbinsights.com](https://www.cbinsights.com/company/erah), [crustdata.com](https://crustdata.com/profiles/company/erah)
- São Bento do Sul/SC. Fundada em 2019. ~24 funcionários. Seed stage. Especialidade: prospecção B2B, pré-vendas, SDR e sales outsourcing. Participou dos aceleradores Google for Startups e Endeavor Brazil.
- [Não verificado] Site oficial, preço, cases, clientes.

**Sales 3**
- Fonte: [crustdata.com](https://profiles.crustdata.com/company/sales-3)
- Campinas/SP. Terceirização de prospecção e consultoria estratégica em vendas.
- [Não verificado] Site oficial, preço, cases, clientes, porte.

---

### 6.10 Recomendação de abordagem

A pesquisa confirma que o orçamento de R$ 4.000/mês acessa consultores independentes e SDR as a Service, não agências full-service estabelecidas.

[Recomendação] Começar pelos consultores independentes com experiência em mercado financeiro (Vanessa Carvalho pelo Efí Bank, William Tadeu pela metodologia de 20+ reuniões/mês). Se nenhum estiver disponível ou o fit não for bom, testar Techsho para SDR terceirizado a ~R$ 4.000/mês.

As boutiques (OUTMarketing, HyTrade) ficam como segunda opção, dependendo de confirmação de preço. O risco é descobrir na primeira conversa que o fee é R$ 8.000+, não R$ 4.000.

---

## 7. Roteiro de abordagem

### Texto do primeiro contato (enviar por e-mail ou LinkedIn, após aprovação explícita)

```
[Nome],

Somos a Szuchmacher Consultoria. Operamos o VIX Radar, sistema de inteligência de
crédito privado brasileiro que monitora 103 emissores em 13 setores com IA, todo dia
útil após o fechamento da B3.

Estamos montando o piloto comercial e buscamos agência de execução B2B para ABM,
outbound e geração de reunião com decisor de asset, family office e tesouraria.

Temos o posicionamento pronto, o ICP definido com anti-ICP e tamanho real de público
(8 a 15 mil profissionais), mapa competitivo com preço verificado em contrato público,
plano de campanha de 8 semanas, copy e anúncios escritos, e briefing visual.

O que precisamos é de execução. ABM sobre contas nomeadas, outbound, CRM, funil, mídia
segmentada sobre público estreito, e métrica de verdade — reunião com decisor, não
impressão.

O piloto é de 90 dias, orçamento definido. Sem contrato longo antes de validar execução.

Se isso faz sentido para vocês, que dados do nosso lado ajudariam a preparar uma
conversa?

Yan Szuchmacher
Szuchmacher Consultoria Ltda.
```

### Perguntas de triagem (fazer na primeira conversa, antes de qualquer proposta)

1. Qual foi o último projeto de ABM que vocês executaram para uma empresa de nicho estreito (público abaixo de 20 mil pessoas)? Pode mostrar métrica de reunião gerada, não de impressão?

2. Vocês têm algum case em mercado financeiro, crédito, asset ou fintech B2B? Se não, como adaptam a metodologia para um setor que não conhecem?

3. Quem executaria o piloto no dia a dia? Qual a senioridade dessa pessoa? Eu vou falar com ela na segunda reunião, não na entrega.

4. Nós já temos posicionamento, ICP, anti-ICP, mapa competitivo, plano de campanha, copy pronta e briefing visual. A proposta de vocês parte desse material ou vocês refazem tudo como etapa de diagnóstico? Se for refazer, quanto custa e quanto tempo leva?

5. Qual a menor estrutura de piloto que vocês aceitam operar? Existe um piso de orçamento ou de prazo abaixo do qual vocês recusam?

6. Métrica de sucesso do piloto para vocês é o quê? Se em 90 dias não houver reunião com decisor, o que acontece?

7. Vocês têm cláusula de saída sem penalidade após o piloto? Em quantos dias?

8. Como vocês cobram? Fee fixo, fee + variável por reunião, ou só variável? Qual a proporção?

---

## 8. Briefing padronizado para as finalistas

Extraído para arquivo próprio e limpo, pronto para enviar: `briefing-agencia-vix-radar-2026-07-30.md`.

Este arquivo contém o briefing completo (produto, preço, público, posicionamento, escopo, restrições, métricas, modelo de contratação, anexos) sem as informações internas do restante do documento (ação trabalhista, premissa de zero pagantes, avaliação crítica das agências, incidente de roteamento).

Entregar junto com os anexos listados no briefing, após a primeira conversa.

---

## 9. Grade de comparação de propostas (em branco)

Preencher conforme as propostas chegarem.

| Critério | Sabiá | Intelligenzia | Macfor |
|---|---|---|---|
| **Contrato** ||||
| Prazo mínimo ||||
| Cláusula de saída (dias) ||||
| Aceita piloto de 90 dias? ||||
| **Escopo** ||||
| ABM com contas nomeadas ||||
| Outbound (canais) ||||
| CRM e funil ||||
| Mídia paga LinkedIn ||||
| Geração de reunião com decisor ||||
| Nutrição e follow-up ||||
| Relatórios e métricas ||||
| Exige diagnóstico/workshop? ||||
| **Financeiro** ||||
| Fee mensal ||||
| Fee de setup ||||
| Variável por reunião ||||
| Variável por contrato fechado ||||
| Mídia (investimento sugerido) ||||
| Ferramentas (custo adicional) ||||
| Total 90 dias ||||
| **Execução** ||||
| Senioridade do time do piloto ||||
| Quem é o ponto focal ||||
| Frequência de reporte ||||
| **Cases e referências** ||||
| Case B2B financeiro ||||
| Case ABM com métrica de reunião ||||
| Referência de cliente para contato ||||
| **Metodologia** ||||
| Como seleciona contas ABM ||||
| Como mede sucesso ||||
| O que acontece se a meta não for atingida ||||

---

## 10. Orçamento estimado total

### Cenário 1 — Piloto com agência (rota escolhida)

ABM, outbound e mídia operados por agência ou consultor. Yan atende as reuniões geradas.

| Item | Mensal | 90 dias | Premissa |
|---|---|---|---|
| Fee de agência/consultor | R$ 4.000 | R$ 12.000 | Fee mensal, sem setup |
| Mídia LinkedIn | R$ 2.500 | R$ 7.500 | ~R$ 83/dia, público estreito |
| Sales Navigator | R$ 130 | R$ 390 | 1 licença |
| CRM (HubSpot starter) | R$ 200 | R$ 600 | Se não usar gratuito |
| Ferramentas (Apollo/Clay) | R$ 300 | R$ 900 | Enriquecimento de leads |
| **Total** | **R$ 7.130** | **R$ 21.390** | |

Custo por reunião qualificada: ~R$ 445 (48 reuniões em 90 dias). CAC: R$ 2.377.

[Fato] O fee de R$ 4.000/mês é o teto para este orçamento. Se o fornecedor escolhido cobrar mais, a conta não fecha sem aumentar o investimento total.

### Cenário 2 — Agressivo (agência full-service)

| Item | Mensal | 90 dias |
|---|---|---|
| Fee de agência (full service) | R$ 8.000 | R$ 24.000 |
| Mídia LinkedIn | R$ 5.000 | R$ 15.000 |
| Sales Navigator (2 licenças) | R$ 260 | R$ 780 |
| CRM + ferramentas | R$ 800 | R$ 2.400 |
| SDR terceirizado (meio período) | R$ 3.000 | R$ 9.000 |
| **Total** | **R$ 17.060** | **R$ 51.180** |

Só ativar quando houver cobrança funcionando, clientes pagantes e receita que comporte o investimento.

### Cenário 3 — Venda solo (referência)

| Item | Mensal | 90 dias |
|---|---|---|
| Agência | R$ 0 | R$ 0 |
| LinkedIn orgânico (perfil Yan) | R$ 0 | R$ 0 |
| CRM (HubSpot free) | R$ 0 | R$ 0 |
| Sales Navigator (opcional) | R$ 130 | R$ 390 |
| **Total** | **R$ 130** | **R$ 390** |

Zero agência. Yan opera o funil sobre rede pessoal. CAC ~R$ 78.

---

## Riscos

1. **[Risco] Clientes pagantes = 0.** Se confirmado, a recomendação de vender sozinho primeiro fica ainda mais forte. O material comercial que cita 17 usuários sem separar pagante de demo precisa ser corrigido antes de qualquer contato com agência ou prospect. [Impacto: reescrever deck e landing na seção de track record.]

2. **[Risco] Mirabaud como contraparte.** O diretório `Processo Mirabaud` contém ação trabalhista. Se for isso mesmo, o nome Mirabaud precisa sair de `product.md`, de toda apresentação e de todo post orgânico que o mencione. [Impacto: perder o único case âncora com nome de instituição conhecida. O produto volta a não ter case público.]

3. **[Risco] Noturno 30/07 processado sob deepseek-v4-flash.** 103 emissores analisados com modelo não-Anthropic. A alegação de verificação adversarial para esse dia é falsa (Haiku e Sonnet colapsaram no mesmo modelo). [Impacto: se um cliente acessar eventos de 30/07, está vendo dado de proveniência não declarada. Reprocessar.]

4. **[Risco] Falta de chave Anthropic no ambiente.** A chave atual tem prefixo sk-ant- e 108 caracteres, compatível com o formato Anthropic, mas não foi possível verificar se é a chave original rotacionada ou uma nova gerada após o incidente. Se o Task Scheduler não herdar a variável, a matinal de 31/07 falha. [Impacto: rotina parada. Validar antes das 10h de 31/07.]

5. **[Risco] Sales Navigator não contratado.** ABM sem Sales Navigator é prospecção cega. O custo é baixo (R$ 130/mês), mas precisa ser ativado antes de qualquer campanha de outbound.

---

## O que depende de você para destravar a Fase 2

1. Confirmar ou corrigir as cinco premissas (clientes pagantes, Mirabaud, orçamento, capacidade de reuniões, prazo).
2. Executar ou delegar os bloqueios P0-1 a P0-9 na ordem listada.
3. Contratar Sales Navigator se a decisão for por ABM.
4. Aprovar ou rejeitar o texto do primeiro contato com agências (seção 7).
5. Dizer se sigo para a Fase 2 (envio dos contatos) ou se ajusto algo na Fase 1.

---

## Testes

### 1. Três afirmações do relatório com fonte

- "O universo real de crédito privado no LinkedIn Brasil é de 8 a 15 mil profissionais." → **Fonte:** `marketing/linkedin/conhecimento/icp.md`, seção "Tamanho real do público".
- "Worker v4.9.183 com ok:true, verificador_ok:true." → **Fonte:** curl health check em 30/07 21:55 UTC (18:55 BRT), resposta `{"ok":true,"versao":"v4.9.183","verificador_ok":true}`.
- "Mirabaud é contraparte judicial, não cliente." → **Fonte:** diretório `E:\Diretorio\Claude\Processo Mirabaud` contém "Dossie Caso Yan Szuchmacher x Mirabaud.pdf", "INICIAL/", "Calculo_Verbas_Base48k.pdf".

### 2. O que muda se o ticket cair pela metade

Com ticket de R$ 60 (Essencial) e R$ 245 (Profissional), o CPL máximo tolerável cai para R$ 20 a 40 no Essencial. Isso inviabiliza completamente mídia paga (CPL real de LinkedIn no mercado financeiro brasileiro é R$ 225 a 325). A operação inteira migra para orgânico e ABM direto sem verba de mídia. O cenário com agência some, porque o CAC não fecha em nenhuma hipótese. O produto precisaria de volume (centenas de assinantes) para justificar o investimento, e o público é de 8 a 15 mil pessoas.

### 3. O que muda se o orçamento cair pela metade

Com R$ 7.500 a 15.000 totais, o cenário com agência some. Só cabe venda solo com ferramentas básicas. O piloto com agência já era apertado em R$ 21.390, na metade disso não paga nem o fee de três meses de nenhuma agência qualificada.

### 4. O que muda se clientes pagantes forem zero

A recomendação de vender sozinho primeiro, que já é a recomendação principal, fica absoluta. Contratar agência com zero clientes pagantes e sem cobrança automatizada é queimar dinheiro. Também obriga a revisão imediata de todo material comercial que cita "usuários" sem especificar que são demo/cortesia.

### 5. O que não foi possível verificar e o impacto

- **Cases financeiros de qualquer agência.** Nenhuma das agências pesquisadas apresentou case verificável em mercado financeiro, crédito ou fintech B2B no Brasil. [Impacto: qualquer contratação carrega o risco de a agência aprender o setor às custas do piloto.]
- **Aceite de piloto de 90 dias.** Nenhuma agência foi contatada, portanto não se sabe se aceitam piloto curto sem contrato longo. [Impacto: pode ser que as três finalistas recusem o modelo e seja preciso buscar agências menores ou freelancers.]
- **Preço real de agência para o escopo descrito.** Os valores do orçamento são estimativas de mercado, não proposta real. [Impacto: o orçamento pode estar subdimensionado. Se uma agência qualificada cobrar R$ 8.000/mês, o piloto sobe para R$ 30-35 mil.]
- **Existência e qualificação de Conversa.tech, BRSA e Seja Mais.** As duas últimas não foram encontradas, a primeira tem informação insuficiente. [Impacto: o universo de agências pode ser menor do que o briefing presumia.]

---

*Documento produzido em 30/07/2026. Fase 1 concluída conforme escopo. Fase 2 (contato com agências) bloqueada aguardando aprovação do usuário.*
