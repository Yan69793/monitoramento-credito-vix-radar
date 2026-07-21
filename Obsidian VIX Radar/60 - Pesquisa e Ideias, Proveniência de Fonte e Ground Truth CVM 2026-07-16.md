---
data: 2026-07-16
tipo: pesquisa
tags: [vix-radar, cvm, proveniencia, ground-truth, dados]
status: ativo
---
# 60 - Pesquisa e Ideias, Proveniência de Fonte e Ground Truth CVM, 2026-07-16

Pesquisa da rotação automática por projeto (skill `jarvis-project-researcher`, rodada 16/07). Lente escolhida a partir do incidente aberto mais recente, [[59 - Incidente RESEARCHDOWN1 (Oncoclinicas CRITICO rebaixado) 2026-07-15]]: o Radar decide severidade com heurísticas de nome e de domínio, escritas à mão, sem data de referência e sem fonte. A pesquisa anterior ([[51 - Pesquisa Preditivo v2 2026-07-11]]) cobriu o eixo quantitativo/preditivo e a [[50 - Análise Competitiva e Baseline SEO 2026-07-11]] cobriu o competitivo, então nenhum dos dois é repetido aqui.

O escopo virou, no meio do caminho, uma auditoria de dados: as verificações feitas para validar a recomendação principal encontraram três defeitos reais em produção, descritos abaixo com evidência bruta.

## Contexto consultado

`PENDENCIAS.md` (atualizado 13/07), notas [[51 - Pesquisa Preditivo v2 2026-07-11]], [[57 - Auditoria Geral (Addendum IA-LLM e Runtime Workers) 2026-07-14]], [[58 - Auditoria Completa 2026-07-15]] e [[59 - Incidente RESEARCHDOWN1 (Oncoclinicas CRITICO rebaixado) 2026-07-15]]; perfil do projeto no Jarvis (`data/projects/vixradar/context_summary.md`); código vivo `api/v4.9.160.js` e os artefatos de `scripts/predictive/`.

Estado de partida: **Worker v4.9.161 e Frontend v201.75 em produção, sem drift** (confirmado ao vivo em 16/07 21:45Z: `ok:true, verificador_ok:true`, `app/version.json` = `vixradar.com/version.json`). O fix do RESEARCHDOWN1 já foi deployado, ao contrário do que a nota 59 e a primeira versão desta nota registravam como "deploy pendente" — ver commits `a64ed21` e `fb1f732`. Pendências relevantes ao tema: PRED3 (22 emissores sem CNPJ, marcado P3), a pendência aberta do RESEARCHDOWN1 de varrer outros eventos rebaixados pelo mesmo motivo, e a recomendação 4 da nota 51 (labels de treino a partir de evento real).

## Achados

### 1. A CVM publica Fato Relevante como dataset estruturado, com lag de 5 dias

[Fato] O dataset `cia_aberta-doc-ipe` traz Fato Relevante e Comunicado ao Mercado com os campos `CNPJ_Companhia`, `Categoria`, `Assunto`, `Data_Entrega`, `Data_Referencia`, `Link_Download` e `Protocolo_Entrega`. URL estável, 1,24 MB, histórico desde 2003.

Verificação ao vivo em 16/07: `HEAD` do `ipe_cia_aberta_2026.zip` retornou `Last-Modified: Sun, 12 Jul 2026 10:00:14 GMT`, e o CSV baixado tem `Data_Entrega` máxima de **2026-07-11**. Volume de 2026: 27.686 documentos, dos quais **1.462 Fatos Relevantes**, ou 9,3 por dia útil no mercado inteiro.

Relevância: é ground truth regulatório de custo zero, no mesmo portal que o projeto já consome no `atualizar_altman_cvm.ps1`. Mas o lag semanal decide o uso correto: serve para **reconciliação, auditoria e rotulagem**, não para alerta em tempo real. A detecção em tempo real continua sendo o pipeline de LLM sobre imprensa.

### 2. O caminho de tempo real da CVM não é uma API

[Fato] `https://www.rad.cvm.gov.br/ENET/frmConsultaExternaCVM.aspx` responde HTTP 200 com `__VIEWSTATE` presente: é ASP.NET WebForms, dependente de postback e sessão. Scraping frágil, sem contrato estável.

Relevância: fecha a tentação de tentar tempo real pela CVM. Confirma que o desenho certo é assíncrono, o dataset semanal como camada de verdade posterior, e não como fonte de alerta.

### 3. O `_RJ_FLOOR` é uma tabela manual sem data e sem fonte, e já está stale

[Fato] `api/v4.9.160.js:12451` define `var _RJ_FLOOR = {...}` com 21 emissores e pisos de EWS entre 18 e 61. **Todos os 21 têm `as_of: null` e `fonte_url: null`**, apesar de o schema prever os dois campos. As descrições carregam números datados que envelhecem sozinhos (dívida, alavancagem, rating, e no caso da Azul até "Estrutura pos-reestruturacao 2 meses").

Staleness confirmada contra a fonte oficial: o `_RJ_FLOOR` descreve Kora Saúde como *"Avaliando recuperação extrajudicial"*, enquanto a CVM registra Fato Relevante de **2026-05-04, "Deferimento do processamento da RE da Companhia e suas controladas"**. O dado está aproximadamente 2,5 meses atrasado num emissor CRÍTICO recorrente.

[Fato] A CVM ainda entrega de graça um sinal estrutural determinístico: 27 companhias carregam o estado no próprio `Nome_Companhia` do cadastro, no formato `LIGHT S.A. - EM RECUPERAÇÃO JUDICIAL`, `OI S.A. - EM RECUPERAÇÃO JUDICIAL`, `AMERICANAS S.A. - EM RECUPERAÇÃO JUDICIAL`.

Relevância: o `_RJ_FLOOR` é a mesma classe de fragilidade do RESEARCHDOWN1 e do STATELEAK1, uma lista escrita à mão que decide severidade e envelhece em silêncio. Os campos `as_of` e `fonte_url` que estão `null` são exatamente `Data_Entrega` e `Link_Download` do IPE.

### 4. Dois emissores críticos estão mapeados para a subsidiária errada, com `match=forte`

Este é o achado mais grave, e é um defeito de dado em produção, não uma sugestão.

[Fato] **Raízen**: `cnpj_emissores.json` mapeia `Raízen` para `08.070.508/0001-78`, denominação `RAÍZEN ENERGIA S.A.`, `match=forte`. Mas na CVM existem duas entidades, e quem entrega o Plano de Recuperação Extrajudicial é a outra:

| CNPJ | Entidade | Docs em 2026 |
|---|---|---|
| 08.070.508/0001-78 | RAÍZEN ENERGIA S.A. (o que o Radar usa) | 55 |
| 33.453.598/0001-23 | RAÍZEN S.A. | **159** |

Os seis Fatos Relevantes mais recentes do Plano de RE da Raízen (Minuta, Protocolo, Plano, Petição, Atualização sobre adesão, entre 03/06 e 12/06) vêm **todos** pelo CNPJ `33.453.598/0001-23`, que o Radar não mapeia.

[Fato] **Light**: mapeada para `01.917.818/0001-36`, `LIGHT ENERGIA S.A.`, `match=forte`. A holding em recuperação judicial é `LIGHT S.A. - EM RECUPERAÇÃO JUDICIAL`, CNPJ `03.378.521/0001-75`, uma entidade distinta. Existem três entidades Light entregando documentos à CVM.

Consequência já materializada no dado publicado: `fundamentals_altman_latest.json` (gerado 11/07, 78 emissores) traz `Light` com **`z_em: 4.71`**, `ativo_total: R$ 3,11 bi`, `cnpj: 01.917.818/0001-36`, `aproximacoes: []`. Ou seja, o Altman da Light está medindo a subsidiária de geração, e devolve um score de zona saudável para um emissor **em recuperação judicial desde 2024**. Para comparação, na mesma tabela a Oncoclínicas tem `z_em: -2.59` e a Kora Saúde `3.88`. A Light aparece melhor que a Kora.

A Raízen no Altman traz ainda `dt_refer: "2025-03-31"`, contra `2025-12-31` da maioria, aproximadamente 9 meses mais velho, provavelmente por ano-safra.

Relevância: é um falso negativo estrutural silencioso, e o rótulo `match=forte` é uma falsa confiança, o mesmo padrão do RESEARCHDOWN1: heurística plausível, decisão silenciosa, sem `as_of`, sem fonte, errando justamente no emissor que mais importa.

### 5. PRED3 bloqueia justamente os emissores de maior risco

[Fato] Dos 21 emissores do `_RJ_FLOOR`, **4 não têm CNPJ mapeado**: Pão de Açúcar (GPA), Dasa, Taesa e Rede D'Or. Três deles (GPA, Dasa, Taesa) estão na lista dos 22 de `cnpj_emissores.review.json`, isto é, em PRED3.

GPA tem piso 55 no `_RJ_FLOOR`, é CRÍTICO recorrente nas rotinas noturnas, e está com deságio de até 90% em negociação com credores. É exatamente o emissor que a reconciliação não alcança hoje.

[Fato] Demonstração da fragilidade do match por nome: buscar `GPA` por substring no dataset retorna `COMPANHIA CELG DE PARTICIPAÇÕES - CELGPAR`, um falso positivo, e não retorna o Grupo Pão de Açúcar.

### 6. O join por CNPJ funciona, e cobre 73 dos 80 emissores mapeados

[Fato] Cruzando os 80 CNPJs de `cnpj_emissores.json` contra o IPE 2026: **1.078 documentos oficiais** (Fato Relevante mais Comunicado ao Mercado) casam por CNPJ, cobrindo **73 dos 80** emissores. Volume por emissor no topo: Vale 59, SLC Agrícola 58, Azul 52, Oncoclínicas 48, Brava Energia 45, Oi 36.

Relevância: a viabilidade técnica está provada end-to-end com dado real, não estimada. O gargalo não é o dataset, é a qualidade do mapa de CNPJ (achados 4 e 5).

### 7. Os players usam score contínuo, não gate binário

[Fato] RavenPack pontua cada item com Relevance, Novelty e Event scores de 0 a 100 sobre 40.000 fontes, e deixa o consumidor escolher o corte, em vez de suprimir a notícia na origem. Fonte: RavenPack News Analytics.

Relevância: contraste direto com o `sanitizarPayloadRadar`, que aplicava rebaixamento binário e irreversível antes de o verificador ver o evento, com efeito colateral de ocultar o item no toggle `vix_hide_research`. Um score de proveniência anexado ao evento preservaria a informação e moveria a decisão para o consumo. Conecta com a armadilha 6 da nota 51 (alert fatigue versus miss rate).

### 8. Detecção automática de alucinação continua não confiável

[Fato] "Evidence-Supported Credit Risk Report Generation Using News-Centric Financial Knowledge Graphs" (Jimenez-Villen et al., arXiv 2607.01023, 2026) reporta ganho de 19% a 34% sobre baselines ancorando geração em grafo de evidência, e conclui explicitamente que a detecção automática de alucinação **permanece não confiável**.

Relevância: o verificador adversarial do Radar é um detector automático. No RESEARCHDOWN1 ele **aprovou** o evento, com `confianca: 0.75`, citando a URL correta, e mesmo assim o gate determinístico rebaixou. Ancorar em evidência estruturada (protocolo CVM) é mais robusto que reforçar o verificador. Literatura relacionada: Tsai 2016 (J. Banking & Finance) mostra que notícia e disclosure oficial são complementares na precificação de risco de crédito, não substitutos.

## Recomendações acionáveis

1. **Corrigir o CNPJ de Raízen e Light antes de qualquer coisa** (P0 de dados). Trocar `Raízen` para `33.453.598/0001-23` e `Light` para `03.378.521/0001-75` em `cnpj_emissores.json`, e reprocessar o `atualizar_altman_cvm.ps1`. Motivo: o Altman da Light está em zona saudável (4,71) medindo a subsidiária de um emissor em RJ, e o do Raízen mede a subsidiária que não entrega o Plano de RE. Conecta com o achado 4 e contamina qualquer consumidor do `fundamentals:altman:latest`, que já está publicado no KV desde 11/07 (PRED1). Validar entidade por `Nome_Companhia` da CVM, não por proximidade de nome curto, e rebaixar o rótulo `match=forte` desses dois casos, que provaram ser falsa confiança.

2. **Promover PRED3 de P3 para P1**. Motivo: deixou de ter um consumidor e passou a ter dois (Altman e reconciliação de eventos oficiais), e os 22 pendentes incluem GPA, Dasa e Taesa, que têm piso no `_RJ_FLOOR`, sendo o GPA um CRÍTICO recorrente com deságio de 90% em negociação. A justificativa antiga da pendência, "cobertura sobe de 69 para ~90 emissores", subestima o impacto real. Fazer o match por CNPJ contra o cadastro da CVM, nunca por substring de nome, conforme o falso positivo CELGPAR do achado 5.

3. **Construir o reconciliador CVM semanal** (`scripts/predictive/reconciliar_ipe_cvm.ps1`, task semanal após a atualização de domingo). Baixa o IPE, filtra Categoria em Fato Relevante e Comunicado ao Mercado, faz join por CNPJ contra os emissores, e compara com o que o Radar classificou naquela janela. Saída: emissores com Fato Relevante de RE, RJ, default, reestruturação ou inadimplência que **não** têm evento CRITICO correspondente no `radar:estado:{semana}`. Motivo: responde de forma determinística e barata a pendência que ficou aberta no RESEARCHDOWN1, "verificar se há outros eventos de outros emissores atualmente RELEVANTE que deveriam ser CRITICO", que hoje só teria como resposta uma varredura manual ou um `admin_sweep_revalidacao` caro. O reconciliador é a rede de segurança permanente contra a próxima heurística que falhar em silêncio, não só contra esta.

4. **Preencher `as_of` e `fonte_url` do `_RJ_FLOOR` a partir do IPE, e alertar quando divergir**. Motivo: os dois campos existem no schema e estão `null` nos 21 emissores, e a CVM entrega exatamente esses valores (`Data_Entrega` e `Link_Download`). Ganho imediato: a Kora Saúde passa de "avaliando RE" para "RE deferida em 2026-05-04" com link do protocolo. Complemento de custo quase zero: usar o marcador `EM RECUPERAÇÃO JUDICIAL` do `Nome_Companhia` como gate determinístico de piso, e emitir divergência quando a CVM declarar RJ para um emissor que não tem piso, ou vice-versa. Isso ataca a causa estrutural: a tabela deixa de ser memória manual e passa a ser derivada de fonte com data.

5. **Trocar o gate binário de proveniência por score anexado ao evento, com telemetria** (a fazer junto ou logo após o deploy do v4.9.161). Motivo: o v4.9.161 corrige o sintoma, separando imprensa de research, mas mantém a arquitetura de rebaixamento binário e silencioso, agora com uma segunda lista hardcoded para manter. O padrão dos players (achado 7) é score contínuo com decisão no consumo. Mínimo viável e barato: gravar `tipo_dado` e qualquer rebaixamento como campo do evento mais uma métrica de telemetria, para que a próxima ocorrência apareça em painel em vez de só em `console.log`. Conecta com LLM09 da nota 57 e com o efeito colateral do `vix_hide_research` documentado na nota 59.

6. **Usar o IPE como fonte de labels do preditivo v2**. Motivo: a recomendação 4 da nota 51 pedia rotular evento real como target de treino, e o `Assunto` do Fato Relevante com `Data_Entrega` é label datado, oficial e auditável, com histórico até 2003 para backtest. Alimenta `data/labels/eventos_credito.jsonl` e o proto-backtest de precision@k que a nota 51 definiu como gate de promoção do `spread_rel_setor` do shadow mode. Cuidado registrado: a data do Fato Relevante é a do protocolo, posterior ao vazamento na imprensa em parte dos casos, então serve como label de ocorrência, não como marco de lead time.

## Execução em 2026-07-16 (mesmo dia, autorizada pelo operador)

O operador autorizou corrigir o mapa inteiro e publicar uma vez só. Resultado:

**14 entidades corrigidas** em `cnpj_emissores.json` (`match` passou a `manual-cvm`), todas validadas contra o cadastro CVM mais DFP consolidado 2025:

| Emissor | De (subsidiária) | Para (entidade do risco) |
|---|---|---|
| Light | LIGHT ENERGIA S.A. | LIGHT S.A. - EM RECUPERAÇÃO JUDICIAL |
| Raízen | RAÍZEN ENERGIA S.A. | RAÍZEN S.A. |
| CSN | CSN MINERAÇÃO S.A. (colisão) | CIA SIDERURGICA NACIONAL |
| CEMIG | CEMIG DISTRIBUIÇÃO | CIA ENERG MINAS GERAIS - CEMIG |
| Copel | COPEL DISTRIBUIÇÃO | COMPANHIA PARANAENSE DE ENERGIA COPEL |
| Energisa | ENERGISA MATO GROSSO DO SUL | ENERGISA SA |
| EcoRodovias | ECORODOVIAS CONCESSÕES | ECORODOVIAS INFRAESTRUTURA E LOGÍSTICA |
| Localiza | LOCALIZA FLEET | LOCALIZA RENT A CAR |
| PRIO | PRIO FORTE | PRIO S.A. |
| Rumo | RUMO MALHA CENTRAL | RUMO S.A. |
| BRK Ambiental | REGIÃO METROPOLITANA DE MACEIÓ | BRK AMBIENTAL PARTICIPAÇÕES |
| Suzano | SUZANO HOLDING | SUZANO S.A. (emissora SUZB3) |
| Bradesco | BRADESCO LEASING | BANCO BRADESCO (financeiro, para reconciliação) |
| BTG Pactual | BTG COMMODITIES SERTRADING | BANCO BTG PACTUAL (idem) |

Mantidos deliberadamente: **Gerdau** (GERDAU S.A. é a operacional emissora GGBR, correta apesar de a Metalúrgica Gerdau ser marginalmente maior, isto é, "maior ativo" não é critério suficiente) e **VLI** (VLI MULTIMODAL é a única entidade no cadastro ativo).

**Efeito no Altman** (cobertura 69 para **73** calculados, total 78 para 82):

- **CSN: 5,06 para 3,91**, passa para zona de distress. Antes carregava o Altman da CSN Mineração por colisão de CNPJ. Agora o Altman **concorda** com o `_RJ_FLOOR` (piso 42, Moody's B2, CreditWatch negativo), quando antes o contradizia.
- **Light: 4,71 para 3,51**, distress, coerente com RJ desde 2024.
- Raízen 4,47 para 4,32; Suzano 5,29 para 5,61; Localiza 4,97 para 4,66; PRIO 4,71 para 5,16; EcoRodovias 4,79 para 4,69.
- Ganharam cobertura (o CNPJ antigo não tinha DFP consolidado ou colidia): BRK Ambiental 4,48, Energisa 4,97, Rumo 4,62, CEMIG 5,40, Copel 4,98, CSN Mineração 5,06.

**Dois defeitos adicionais achados e corrigidos no mesmo passo:** o payload publicado em 11/07 servia `Itaú Unibanco` com `z_em 38,27` e `Itaúsa` com `10,48`, apesar de o script declarar setor financeiro incompatível com Altman. Causa raiz: a lista `$Financeiros` do `atualizar_altman_cvm.ps1` estava com mojibake (`ItaÃºsa`), então o filtro `-contains` nunca casava, e o script ainda gravava as duas versões mojibake com `z_em: null` no fim, gerando quatro entradas em vez de duas. Ambos agora são `null` corretamente e não há mais chave com mojibake no payload.

**Validação cruzada:** os quatro emissores em RJ/RE com Altman calculado (Azul -7,32, Oncoclínicas -2,59, Light 3,51, Kora Saúde 3,88) caem todos em distress, junto com a CSN (3,91). Faixa geral de -7,32 a 9,47, sem valor implausível. Distribuição: 11 distress, 41 cinzenta, 21 seguro.

**Correção de um item da própria pesquisa:** o `dt_refer: 2025-03-31` da Raízen, levantado acima como possível defeito, é o exercício social correto (ano-safra abril a março), não staleness. Ambas as entidades Raízen usam 31/03.

**Impacto em produção: nenhum no score.** O `altman_z_em` está em shadow com peso zero, confirmado lendo `scorePreditivoRuleV1` e `scorePreditivoLogisticV2` inteiras (`api/v4.9.160.js`): nenhuma das duas consome o campo. O dado errado afetou o `predictive_v1` exposto e o export diário para `data/historico/` desde 11/07, isto é, cinco dias de dataset de treino contaminado.

**Publicado e validado em produção (2026-07-16 18:31 BRT).** O `wrangler kv key put` foi bloqueado pelo classificador de auto-mode (escrita em produção) e executado pelo operador. Validação por leitura de volta do KV (`wrangler kv key get --remote`): 53,2 KB íntegros, `gerado_em 2026-07-16 18:31:14`, `total 82`, 73 calculados, **zero chaves com mojibake**. Confirmados ao vivo: Light `3,51` (cnpj 03.378.521/0001-75), CSN `3,91` (33.042.730/0001-04), CSN Mineração `5,06` (08.902.291/0001-15, colisão desfeita), Raízen `4,32` (33.453.598/0001-23), Itaú Unibanco e Itaúsa `null`.

## Guard da regeneração (2026-07-16, mesma sessão)

Risco original: o `atualizar_altman_cvm.ps1` só usava o mapa se o arquivo existisse. Apagar `cnpj_emissores.json` fazia a heurística regenerar e **reintroduzir as 14 entidades erradas em silêncio**, porque `denom.StartsWith(alvo + ' ')` (`:96`) casava "LIGHT ENERGIA" com "Light" antes de "LIGHT S.A.", e o rótulo `match=manual-cvm` era documental, sem efeito no código. Todo o trabalho de hoje dependia de um arquivo não ser apagado.

Corrigido com **duas camadas**, porque uma só não bastava:

1. **Desempate por ativo total** (`atualizar_altman_cvm.ps1`, seção 3): coleta todos os candidatos fortes em vez de `break` no primeiro, e escolhe o de maior ativo consolidado entre os que têm DFP. O `break` adotava a ordem do CSV da CVM como critério de verdade. Exigiu mover o download do DFP para antes do mapa (seção 2), já que o desempate precisa do ativo. Resolve 8 dos 14: Light, Raízen, Energisa, EcoRodovias, Localiza, PRIO, Rumo, BRK.
2. **`cnpj_emissores.overrides.json`** (novo, seção 3b): aplicado **sempre** por cima, inclusive na regeneração do zero. Cobre o que o desempate não resolve: (a) a denominação social não contém o nome curto, então não há candidato algum (CSN → "CIA SIDERURGICA NACIONAL"; CEMIG, Copel, Bradesco, BTG, todos porque `Normalizar` remove "CIA"/"COMPANHIA"/"BANCO" do início); (b) **o desempate escolheria a errada** (Suzano: a Holding tem R$ 167,979 bi contra R$ 167,935 bi da operacional SUZB3, que é a emissora). Cada entrada carrega o motivo por escrito.

**Teste dos três fluxos:**

| Fluxo | Esperado | Resultado |
|---|---|---|
| Mapa apagado (cenário de risco real) | 14 entidades corretas | 8 pelo desempate, 6 pelo override, mapa regenerado idêntico ao corrigido à mão |
| Mapa existente e correto | aplica e não regrava | 14 aplicados, hash do arquivo inalterado |
| Overrides ausente | avisa, não quebra | `AVISO: ... roda SEM guard de entidade`, 73 calculados |

**15º erro achado pelo próprio guard:** na regeneração, o desempate divergiu do mapa corrigido à mão em **Iguatemi**, escolhendo `IGUATEMI S.A.` (60.543.816/0001-93, R$ 9,5 bi) em vez de `IGUATEMI EMPRESA DE SHOPPING CENTERS` (51.218.147/0001-93, R$ 7,6 bi). Investigado: o desempate estava certo e a varredura manual tinha passado batido. A reorganização de 2021 incorporou as ações da IGTA3 na Jereissati Participações, que foi renomeada Iguatemi S.A. (IGTI11), e a Empresa de Shopping Centers virou subsidiária integral (fontes: RI da Iguatemi, circular B3 142/2021-PRE). Altman: 6,40 para 6,55, ambos em zona segura, impacto marginal, mas o CNPJ agora aponta para a holding listada. Não precisou de override, o desempate basta.

**Divergência conhecida com o KV:** o payload publicado às 18:31 tem Iguatemi `6,40` com o CNPJ da subsidiária. O arquivo local tem `6,55` com o CNPJ correto. Republicar é opcional (Altman é trimestral e está em shadow com peso zero); o próximo ciclo normaliza.

## Limites desta pesquisa

- O lag de 5 dias do IPE foi medido uma vez (Last-Modified 12/07, dado até 11/07). A página declara atualização semanal, mas a cadência exata não foi observada ao longo do tempo. [Validar] em duas ou três semanas antes de fixar o agendamento da task.
- Só o ano de 2026 foi baixado e cruzado. A cobertura histórica (2003 em diante) foi lida da documentação, não verificada.
- O universo cruzado foi o dos 80 CNPJs mapeados, não os 103 emissores. Os 23 restantes (22 de PRED3 mais Rede D'Or) não puderam ser avaliados, o que é a própria recomendação 2.
- ~~Não auditei se outros emissores, além de Light e Raízen, apontam para subsidiária errada~~ **HIPÓTESE CONFIRMADA e resolvida no mesmo dia**: a varredura do mapa inteiro contra o cadastro CVM achou 12 casos além dos 2 originais, sendo o pior a CSN (colisão de CNPJ com CSN Mineração). Ver seção de execução acima.
- A varredura automática por token de nome gera falso positivo (o token "BANCO" casa com todos os bancos) e falso negativo (o token "CSN" não casa com "CIA SIDERURGICA NACIONAL"). O critério "maior ativo total" também não basta, como o caso Gerdau mostra. A decisão final foi manual, caso a caso, com o cadastro CVM e o DFP como evidência.
- Os 22 emissores de PRED3 seguem sem CNPJ, então não foram auditados. A recomendação 2 continua de pé.
- Alterações desta rodada: `cnpj_emissores.json` (14 entidades), `fundamentals_altman_latest.json` (reprocessado), esta nota e o índice. Nenhuma mudança em código do Worker, e o KV de produção não foi tocado.

## Fontes

- CVM Dados Abertos, dataset IPE (Documentos Periódicos e Eventuais): https://dados.cvm.gov.br/dataset/cia_aberta-doc-ipe
- Arquivo usado: https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_2026.zip
- Dicionário de campos: https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/META/meta_ipe_cia_aberta.txt
- CVM, consulta externa RAD (ASP.NET WebForms, não é API): https://www.rad.cvm.gov.br/ENET/frmConsultaExternaCVM.aspx
- Jimenez-Villen, Xu, Chen, Araque, Ichise (2026), Evidence-Supported Credit Risk Report Generation Using News-Centric Financial Knowledge Graphs: https://arxiv.org/abs/2607.01023
- Ahbali et al. (2022), Identifying Corporate Credit Risk Sentiments from Financial News, NAACL Industry Track: https://aclanthology.org/2022.naacl-industry.40.pdf
- Tsai (2016), The impact of news articles and corporate disclosure on credit risk valuation, J. Banking & Finance: https://ideas.repec.org/a/eee/jbfina/v68y2016icp100-116.html
- RavenPack News Analytics (relevance, novelty, event scores): https://www.ravenpack.com/products/edge/data/news-analytics
