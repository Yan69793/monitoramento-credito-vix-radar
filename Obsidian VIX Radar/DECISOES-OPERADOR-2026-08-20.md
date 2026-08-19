# Decisões que dependem do operador — 2026-08-20

Bloco F da auditoria. Documento de decisão, nenhuma implementação feita.
Duas pendências que não são trabalho de engenharia, são escolha de produto. Cada uma
traz o que foi apurado, o que custa cada caminho, e uma recomendação com a razão.

Assinar embaixo com a decisão e a data. Enquanto não houver decisão escrita aqui, as
duas continuam abertas e o sistema segue no comportamento atual descrito em cada seção.

---

## 1. FONTELATENCIA1 — a fonte da CVM é semanal, isso é problema de negócio?

### O que foi apurado

O ramo `CIA_ABERTA/DOC` de `dados.cvm.gov.br` publica uma vez por semana, aos
domingos. Isso está declarado na própria página do dataset, campo "Frequência de
atualização: Semanal". Não é falha, é o desenho da fonte.

O caso que motivou a pergunta é a Casas Bahia. Fato relevante de recuperação judicial
protocolado em 16/08, comunicado em 18/08, e a última linha da companhia dentro do ZIP
baixado é de 10/08. Seis dias de defasagem no pior momento possível.

### O ponto que muda a decisão

A CVM não é o caminho de descoberta do produto. A rotina noturna roda todo dia e a
descoberta acontece por busca web (rodada R2, notícias de crédito), não por leitura da
CVM. Os documentos da CVM entram no plano já mastigados, como `cvm_documentos` e
`cvm_novos`.

Então a latência semanal atrasa duas coisas específicas, e não a descoberta:

Primeiro, a promoção do emissor para a fila aprofundada. O critério é `tier == FULL` e
(`ews_score >= 38` ou `cvm_novos > 0`). Um documento novo na CVM promove o emissor para
análise cara. Com o ZIP semanal, essa promoção pode chegar até sete dias atrasada.

Segundo, a disponibilidade do Fato Relevante como fonte primária. O gate de evento pede
que recuperação judicial, default e rebaixamento sejam confirmados contra a CVM antes de
fechar com imprensa. Sem o documento no ZIP, o evento fecha com fonte de imprensa, o que
o próprio gate já permite explicitamente.

Na prática o produto descobriu a Casas Bahia pela imprensa dentro da janela. O que ficou
pior foi a qualidade da fonte citada, não a existência do alerta.

### Os caminhos

**Não fazer nada.** Custo zero. A descoberta continua vindo da busca diária, a CVM
continua sendo confirmação e gatilho de promoção. O risco que sobra é um emissor que só
apareça em documento CVM e não em notícia nenhuma, cenário improvável para evento de
crédito material.

**Raspar o RAD interativo (`rad.cvm.gov.br`).** É a fonte de baixa latência de verdade,
publica no protocolo. Custo é scraping de ASPX com `__VIEWSTATE`, e algumas rotas pedem
captcha. Manutenção alta e frágil, quebra quando a CVM mexe no formulário. Já existe
chamada pontual ao RAD dentro do gate de evento, então a receita não seria do zero, mas
varrer 103 emissores todo dia é outra escala.

**Assinar a B3.** Publica fato relevante de listada com latência de horas. Cobertura
menor que a CVM, cobre só listadas, e boa parte do universo aqui é capital fechado.
Custo de assinatura, cobertura parcial.

### Recomendação

Não construir o scraping do RAD. O problema real medido é estreito, e a solução mais
cara do cardápio resolve a parte que menos dói.

Em vez disso, duas coisas de custo baixo que fecham o buraco específico:

Promover para fila aprofundada por sinal de imprensa, não só por `cvm_novos`. Se a
rodada R2 trouxe sinal crítico, o emissor sobe de fila no mesmo dia, sem esperar o ZIP
de domingo. Isso ataca o atraso de promoção, que é o dano concreto.

Manter a checagem pontual no RAD só onde ela já existe, no gate de evento de RJ, default
e rebaixamento. É consulta de um emissor por vez, quando já há suspeita, não varredura.

**Decisão do operador:** Recomendação aceita em 21/08/2026. Não construir o scraping do RAD. Promover para fila aprofundada por sinal de imprensa no mesmo dia, e manter a checagem pontual no RAD só no gate de evento de RJ, default e rebaixamento. Implementado na sessão de 21/08.
**Data:** 2026-08-21

---

## 2. DRIVERMORTO1 — o score declara seis drivers e entrega três

### O que foi apurado

Três dos seis drivers do Early Warning Score nunca produziram valor. Cada um está morto
por uma causa diferente, e isso importa porque o remédio de cada um é diferente.

**`merton` está `null` nos 103 emissores**, em todos os exports desde 11/07. O gate em
`worker.js:14074` exige `market_cap`, e nenhuma das duas fontes disponíveis fornece.
O `fundamentals:altman:latest` é balanço puro vindo da DFP da CVM, zero ocorrências de
`market_cap` em 99 empresas. O `cotacoes:volatilidade:v1` se recusa a publicar preço por
ação como se fosse valor de mercado, e faz certo, porque não é.

**`momentum` exige `velocity_delta >= 2`** sobre a série `ews:hist:{empresa}`. As 103
chaves existem, mas a série é curta e plana. `ews:hist:oi` tem três pontos, 18, 19 e
20/08, os três com score 66. A série só começou a acumular em 18/08, quando o HISTFLAT2
consertou o casamento de chave em minúsculo.

**`mercado` exige `spread_score >= 10`**, que sai de `spreadScoreDeAnomalias` lendo
`mercado:anomalias:ativas`. Essa chave em produção tem quatro bytes, `{}`. O detector
que a alimentaria está desalinhado com o schema `anbima_publico` desde a troca de
provedor em abril, o que é o ANOMSCHEMA1.

### Por que isso é mais do que três campos vazios

Foi esse driver morto que produziu o ALERTAMERCADOFALSO1 fechado hoje. A tela dizia
"Nenhum alerta de mercado ativo (spread/volume) na janela" com o detector desligado, ou
seja, afirmava ausência de alerta quando o que existia era ausência de leitura. O
sintoma foi corrigido, a causa não.

A interface ainda carrega rótulos para seis drivers de anomalia de mercado
(`spread_abertura`, `spread_fechamento`, `volume_alto`, `volume_baixo`, `iliquidez`,
`concentracao`) que nunca podem aparecer enquanto a chave estiver vazia. Isso hoje é
código morto, não afirmação falsa, mas é a mesma raiz.

### Os caminhos, por driver

**`momentum` se resolve sozinho.** A série cresce um ponto por dia. Em algumas semanas
haverá janela suficiente para `velocity_delta` significar alguma coisa. Não fazer nada é
a resposta certa aqui, só marcar a data para conferir se acordou.

**`mercado` é trabalho de código conhecido**, o ANOMSCHEMA1. Realinhar o detector ao
schema `anbima_publico` e revalidar contra a série que já está no KV, 78 chaves em
`mercado:serie:*`. Escopo fechado, sem dependência externa, sem decisão de produto. É o
melhor retorno dos três.

**`merton` está bloqueado por TICKERPERIMETRO1** e não deve ser destravado antes dele.
O mapa `data/cotacoes/tickers_emissores.json` declara 94 emissores listados num universo
de 103, número alto demais para carteira de crédito privado, e o próprio arquivo se
contradiz: o `_descricao` diz "apenas emissores listados com capital aberto" e o `_nota`
diz "~68 dos 103 são listados". Há entradas apontando para entidade diferente da
emissora, `Compass Gás e Energia` para `CMPC3.SA`, `MRS Logística` para `MRSA6B.SA`,
`Itaúsa` para `ITSA4` quando quem emite dívida no grupo é o banco.

Coletar `market_cap` com esse mapa faz Merton medir equity da mãe contra dívida da
filha. O resultado é um número plausível e errado, que é pior que o `null` de hoje,
porque `null` não engana ninguém e número errado engana.

### Recomendação

Ordem: ANOMSCHEMA1 primeiro, `momentum` por decurso de prazo, Merton por último e só
depois da classificação manual das 94 entradas do mapa.

Enquanto os três não voltarem, decidir uma coisa sobre a apresentação: o score é
publicado como composto de seis fatores. Se a interface em algum ponto declara os seis
ao usuário, isso precisa dizer quantos estão ativos nesta leitura. Não foi encontrada
declaração explícita de "seis drivers" na tela, então isto é prevenção, não correção de
defeito achado.

**Decisão do operador:** Aceita em 21/08/2026. Ordem: ANOMSCHEMA1 primeiro, momentum por decurso de prazo, Merton depois do mapa TICKERPERIMETRO1 classificado. O mapa também foi ordenado nesta sessão. A apresentação do score deve dizer quantos drivers estão ativos na leitura quando for mexida.
**Data:** 2026-08-21

---

## Nota de método

Nenhuma das duas foi implementada. As recomendações acima são opinião técnica com a
evidência que as sustenta, não ordem de serviço. Ambas mudam comportamento visível ao
cliente, e a auditoria de hoje mostrou seis vezes que mudar comportamento visível sem
decisão explícita é como os defeitos entram.
