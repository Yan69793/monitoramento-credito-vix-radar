---
data: 2026-08-14
tipo: pendencia
tags: [vix-radar, backlog, acoes]
status: ativo
---

# Pendencias — VIX Radar

Fila de acoes abertas. Prioridade: P1 (critico, trava operacao), P2 (alto, degrada cobertura ou seguranca), P3 (medio, melhoria ou conveniencia), P4 (baixo, cosmetico ou futuro).

---

## 24/08 (sexta rodada) — RESOLVIDO: falha de envio de e-mail transacional era invisível por construção (EMAILSILENT1)

> **Status:** RESOLVIDO e DEPLOYADO. Worker v4.9.214 em produção desde 24/08 21:54 BRT, commit `db2842e`, merge `5768c3c`. Validado no portão (`ok:true`, `kv:true`, `telemetria:true`, `sentry_ok:true`) e por sonda sem efeito colateral, `admin_email_envios` sem senha devolve 403 em produção, onde o código antigo devolvia 401. CI `Worker Tests` verde em `db2842e`, 12 arquivos
> **Data da Versão:** 2026-08-24
> **Origem do Registro:** `joao.tavano@mirabaud.com.br` foi aprovado, o painel exibiu "João Tavano aprovado", e não havia forma interna de saber se o e-mail de aprovação chegou. A única fonte autoritativa era o painel da Resend, fora do sistema
> **Condição de Obsolescência:** perde validade se `enviarResend` deixar de devolver o `id` da Resend, ou se o rastro migrar de KV para DO na migração v5

Aprovar alguém devolvia `ok:true` tivesse a mensagem saído ou não. O admin lia "aprovado" e não tinha como distinguir aprovado-com-aviso de aprovado-sem-aviso. Recusa por domínio corporativo do destinatário é o desfecho mais provável e o mais invisível, porque acontece do lado de lá e nunca virava exceção aqui dentro.

**Causa raiz.** Quatro `catch {}` literalmente vazios em volta da chamada à Resend (`handleAdminAprovar`, `handleAdminRejeitar` e os dois ramos de `handleEmailActionConfirm`), mais um `console.error` solto em `handleSolicitarReset`. A informação para diagnosticar já existia e era descartada: `enviarResend` monta e devolve o `id` que a Resend gera, e nenhum dos 16 call sites de produção lia esse retorno. O único que aproveitava era `newsletter_teste`, que devolvia `resend_id` na resposta HTTP e não persistia.

**Medido.** Varredura dos 16 call sites de `enviarResend`, não a lista da auditoria. A lista original tinha dois erros: apontava `handleSolicitarReset` como `catch {}` vazio quando ele já tinha `console.error`, e não citava `handleAdminRejeitar`, que tinha o defeito idêntico. Corrigidos os cinco caminhos cujo destinatário é o usuário final.

**Correção.** `enviarEmailRastreado` centraliza os cinco envios e nunca lança, porque a ação primária (aprovar, rejeitar, gerar token) já aconteceu e continua valendo. Quatro canais, cada um com papel distinto: `console.error` para `wrangler tail`, Sentry para alerta que alcança o operador sem ninguém consultar nada, Analytics Engine para agregação, e KV para o rastro por destinatário. As respostas de aprovar e rejeitar ganharam `email_enviado`, `email_erro` e `resend_id`, com tri-estado deliberado (`null` é "não tentou", `false` é "tentou e falhou").

**Exceção deliberada em `solicitar_reset`.** A resposta continua idêntica nos dois desfechos. Contar ao chamador que o envio falhou revelaria que a conta existe e está aprovada, que é exatamente o que a mensagem genérica protege. Anti-enumeração vale mais que a conveniência do aviso, e o sinal de falha sai pelos canais do operador.

**LGPD.** A chave `email_envio:{email}:{ts}` usa o endereço em texto puro de propósito. Ele já está no mesmo namespace em `user:{email}` e `bounce:{email}:{ts}`, então hash não reduziria identificabilidade, só quebraria a correlação com bounce e a consulta por prefixo. O controle real é retenção, TTL de 90 dias igual ao do bounce, para que entrega e devolução expirem juntas. Não grava corpo da mensagem, IP nem user agent. Para a Sentry, que é terceiro, o endereço vai redigido e só o domínio segue como tag, preservando o bloco `dataCollection` fechado a dedo no SENTRY-PII1.

**Guarda sistêmica.** `api/test/email-falha-silenciosa.test.mjs`, 7 testes, roda no CI por `worker-tests.yml`. Prova de duas pontas medida: contra o código pré-correção os 7 falham, contra o corrigido os 7 passam. O determinismo vem de um `outboundService` em `vitest.config.mts` que intercepta só `api.resend.com` e decide pelo campo `to` do payload, porque este pacote (`@cloudflare/vitest-pool-workers` v0.20.x) não exporta mais `fetchMock` de `cloudflare:test`, só o tipo `MockAgent` sobrou no `.d.ts` sem implementação em `dist/`. Efeito colateral bom, a suíte parou de bater em `api.resend.com` de verdade a cada rodada de CI.

**Consulta.** Action admin `admin_email_envios` responde "o e-mail chegou?" por destinatário, cruzando os envios com os registros de bounce e complaint que o webhook da Resend já gravava. Devolve `retencao_dias` explícito porque lista vazia tem duas leituras, nunca enviamos ou o TTL levou, e confundir silêncio com ausência é o erro que abriu esta auditoria.

**Deixado aberto de propósito, P3.** Os dois envios de notificação ao admin (`handleRegistrar`, o de cadastro novo e o de reenvio com dedup de 24h) não passam pelo helper. Não são silenciosos, já têm `console.log` mais evento de Analytics Engine, e a audiência é outra, se falharem o admin simplesmente não vê a solicitação. Ficam sem rastro por destinatário e sem alerta na Sentry. Segundo item, `enviarResend` devolve o objeto único quando `resultados.length === 1`, então um lote de 2 em que 1 falhou retorna forma indistinguível de envio único bem-sucedido. Não afeta os cinco caminhos corrigidos, que são todos de 1 destinatário, mas engana quem for instrumentar os call sites de lote.

---

## 24/08 (quinta rodada) — RESOLVIDO (Marco 1): carteira trocada só no backend deixou a Braskem sem card de métrica (CURADORIA1)

> **Status:** Marco 1 resolvido e deployado. Marco 2 (recuração dos 101) ABERTO P2
> **Data da Versão:** 2026-08-24
> **Origem do Registro:** print do operador mostrando os quatro cards de risco da Braskem vazios no dia do protocolo de recuperação extrajudicial. Investigação mediu `EMISSORES_LISTA` (`api/src/worker.js:3798`), `METRICAS_CURADAS` e `EMISSORES` (`app/index.html`), e comparou contra produção
> **Condição de Obsolescência:** perde validade quando o Marco 2 fechar e os 103 emissores tiverem `as_of`/`source_date`/`metric_type`, ou se `METRICAS_CURADAS` deixar de ser tabela curada à mão e passar a ser servida pelo Worker

O operador viu os cards de Alavancagem, Rating, Cobertura e EBITDA da Braskem com traço e "Pendente", no mesmo dia em que ela protocolou recuperação extrajudicial de US$ 10,9 bi, e leu como falha de coleta ligada ao evento. Não era. Esses cards nunca dependeram de evento, rotina, LLM ou CVM.

**Causa raiz.** `METRICAS_CURADAS` é objeto literal escrito à mão dentro de `app/index.html`, e o commit `b13b605` (`feat(carteira): AES Brasil sai, Braskem entra`, CARTEIRA-24AGO1) alterou `api/src/worker.js`, `api/wrangler.toml` e `scripts/check-emissores-cadastro.mjs` sem tocar em `app/index.html`. A carteira mudou só no backend. Nada no projeto comparava as três tabelas que precisam concordar, então a lacuna era silenciosa por construção. Mesma família do NOMEMORTO1, onde eram três tabelas de alias sem nada forçando concordância.

**Medido.** Carteira 103, curadas 101, menu 103 mas com o conjunto errado. Sem card: Braskem, Tupy, Itaú Unibanco. Órfã: AES Brasil, que também seguia no menu. Braskem não aparecia no menu em lugar nenhum. Produção idêntica ao repo (`CACHE_VERSION` v202.30).

**Defeitos de segunda ordem, achados na mesma medição.** (1) O placeholder exibia "Cobertura · ICSD", e "Cobertura" tem zero ocorrências como rótulo nos 101 curados, ou seja, o card vazio prometia métrica que o sistema não produz para ninguém. (2) A idade do dado não era legível por máquina, vivia dentro do texto livre de `fonte` tipo `"CVM · 4T25"`, e 257 das 404 células declaravam 4T25 em agosto de 2026, sem qualquer sinal de idade no painel. (3) Três cards do Vamos não tinham campo `fonte` nenhum, e ao buscar a fonte do Rating apareceu que o valor exibido estava factualmente errado, AAA(bra) com perspectiva estável quando a Fitch rebaixou para AA+(bra) com perspectiva negativa em 28/08/2024.

**Correção (Marco 1).** Braskem, Tupy e Itaú Unibanco ganharam os quatro cards com número de fonte primária (release 2T26 da Braskem de 14/08, ITR da Tupy de 06/08, 6-K do Itaú na SEC de 04/08, ações de rating da Fitch e da S&P). AES Brasil saiu do menu e do curado. Braskem entrou no menu em Petróleo, Gás e Combustíveis, que é onde o backend a coloca. Schema ganhou `as_of`, `source_date` e `metric_type`. Placeholder virou aviso honesto. Painel passou a exibir a idade do dado, e card sem datação exibe "idade não declarada" em vez de exibir nada. Rating do Vamos corrigido para AA+(bra).

**Guarda sistêmica.** `scripts/check-metricas-curadas.mjs`, offline, lê só `api/src/worker.js` e `app/index.html`, roda no CI em `.github/workflows/emissores-cadastro.yml`. Cinco checagens: cobertura de métrica (inclui órfã), cobertura de menu, integridade do trio de campos, fonte obrigatória, e frescor por tipo de métrica. Três pontas provadas no CI, reprova emissor sem card, reprova card com `as_of` vencido, e aceita o repo como está, porque guarda que reprova tudo passaria nas duas negativas parecendo sadia.

**Limite declarado da guarda, de propósito.** Ela não consegue reprovar "card velho porque saiu rating novo" nem "porque saiu evento crítico novo", já que lê arquivos estáticos. O único candidato a oráculo no repo, `data/labels/eventos_credito.jsonl`, foi medido e não serve, parou em 2026-07-31 e tem zero registros de Braskem, então aprovaria em silêncio justamente o caso que originou a guarda. Frescor ficou por prazo fixo por tipo, e a cláusula "imediato" é revisão manual, registrada no cabeçalho do script.

**Marco 2, aberto.** Os 101 emissores herdados seguem sem os três campos e aparecem como pendência declarada na saída da guarda (400 cards). Não reprovam ainda. A régua de ITR reprovaria todos eles hoje, o trimestre exigido é 2026-03-31 e eles carregam 4T25.

**Adendo 24/08, verificação independente da entrega.** Até aqui o fechamento do Marco 1 valia pela palavra da sessão que entregou. Medido de novo em `main` (`54030f2`) por outra sessão, sem editar nada, rodando a própria guarda e reextraindo as tabelas do disco. Confere. `check-metricas-curadas.mjs` sai `EXIT=0` com `Carteira (EMISSORES_LISTA): 103 | Com card (METRICAS_CURADAS): 103 | No menu (EMISSORES): 103` e 400 cards de pendência declarada. Total de 412 cards, que fecha em 103 × 4 e em 400 pendentes mais 12 datados. Zero card sem fonte, zero label "Cobertura". Trio de campos em 12 cards, distribuição `{"itr":9,"evento_credito":1,"rating":2}`. Braskem e Tupy presentes na carteira e no curado, AES Brasil ausente nos dois. Valores conferidos no literal, Braskem 6,74x `breach` e Rating `RD` com fonte `Fitch 17/08 · RE 24/08/2026`, Tupy 4,14x `warn` e `brAA` S&P mar/2026, Itaú Basileia 12,3% `ok` e ROE 24,3%. "idade não declarada" presente 2 vezes em `app/index.html`.

**Ressalva de leitura sobre a prova de CI, achada nessa verificação.** O run que falhou é o `cc39280`, o commit que introduziu a guarda, e a falha foi mesmo o passo do cadastro CVM (`ERRO: fetch failed`, `exit code 2`), download transitório. Só que naquele run **todas** as etapas de guarda ficaram `skipped`, não passaram, porque o passo anterior abortou o job. Então o commit da guarda não prova nada sobre ela. A prova está no run do v202.32 (`235f739`), onde as três rodaram com `success`, `Guarda tem que reprovar emissor sem card de metrica`, `Guarda tem que reprovar card com as_of vencido para o tipo` e `Guarda tem que aceitar o repo como esta`. O mérito não muda, a guarda está provada, mas quem ler rápido pode confundir "o CI do commit da guarda falhou" com "a guarda foi exercitada ali". Não foi.

**Armadilha para o próximo que auditar esta tabela.** `EMISSORES_LISTA` guarda o nome com escape unicode, `Ita\xFA Unibanco`, e `METRICAS_CURADAS` guarda `Itaú Unibanco` cru. Comparar os dois sem desescapar acusa o Itaú como órfão da carteira, divergência que não existe. A guarda faz certo, tem `desescapar()` em `scripts/check-metricas-curadas.mjs:53`. Script de conferência ad hoc que copie só o recorte e esqueça o desescape reproduz o falso positivo, e foi o que aconteceu na primeira passada desta verificação. Mesma família do ACENTOMATCH1, acento quebrando comparação de nome, agora do lado de quem audita em vez do lado do sistema.

---

## 24/08 (quarta rodada) — ABERTO P1: Braskem protocolou recuperação extrajudicial e o sistema não pegou (BRASKEMDETECT1)

> **Status:** ABERTO, mas ver adendo de 24/08 ao final da entrada
> **Data da Versão:** 2026-08-24
> **Origem do Registro:** auditoria operacional de 24/08 ([[91 - Auditoria Operacional 2026-08-24]]), comparando o protocolo do dia contra o que a noturna das 16h trouxe
> **Condição de Obsolescência:** perde validade quando existir fonte de Fato Relevante independente do ZIP `ipe_cia_aberta_2026.zip`, ou quando a CVM repuser o arquivo e a ingestão voltar a disparar por protocolo

A Braskem protocolou recuperação extrajudicial em 24/08, US$ 10,9 bi reestruturados. A noturna analisou a Braskem às 16h e trouxe o rebaixamento da Fitch de 17/08, não o protocolo do mesmo dia. O painel segue com 20/08 como fato mais recente. Contraexemplo confirmado: falha de detecção, não ausência de fato.

**Causa raiz (duas, somadas).** (1) O ZIP `ipe_cia_aberta_2026.zip` da CVM está em 404 desde 23/08 (CVMURL404), o que tirou o gatilho primário de evento. (2) A busca de imprensa sozinha não alcançou o protocolo. A detecção depende demais de uma fonte só, e o fallback não cobre protocolo de recuperação judicial/extrajudicial fora do IPE.

**Impacto.** Cliente pago não vê o evento de crédito mais grave do dia.

**Correção.** Fonte alternativa para Fato Relevante/protocolos (MZiQ, avaliado na frente 2) ou fallback de busca que cubra recuperação judicial/extrajudicial. Decisão pendente do operador.

**Guarda sistêmica.** Não existe ainda. Proposta: gatilho de detecção para eventos de recuperação judicial/extrajudicial a partir de fonte que não dependa do ZIP da CVM; teste com contraexemplo fixo (protocolo da Braskem de 24/08).

**Status:** ABERTO. Depende da decisão de fonte alternativa.

**Adendo 24/08 19h48, sem apagar o diagnóstico acima.** O print do operador, tirado às 19h48 na sessão do CURADORIA1, mostra o protocolo na timeline da Braskem: card CRÍTICO, "Conselho aprova pedido de recuperacao extrajudicial para reestruturar US$ 10,9 bilhoes", `IMPRENSA`, data 2026-08-24, fonte `braziljournal.com`, com o cabeçalho "Analisado às 15:09" e 2 eventos identificados. Ou seja, o evento entrou por imprensa em alguma rodada posterior à noturna das 16h que originou este registro, e o painel deixou de estar cego para ele. Isso **não fecha** a pendência: a causa raiz continua de pé, a detecção segue dependendo do ramo de imprensa porque o ZIP da CVM está em 404 (CVMURL404), e não há guarda que garanta a captura na próxima vez. O que muda é o enunciado "o sistema não pegou", que era verdade na hora da auditoria e não é mais. Não foi possível confirmar pelo servidor nesta sessão, `op=state` exige autenticação e devolveu HTTP 401. Confirmar com o operador antes de reclassificar.

---

## 24/08 (auditoria operacional) — RESOLVIDO EM PRODUÇÃO (v4.9.213): `_last_scanned_at` gravado 3h no passado infla o gate de cobertura (RELOGIO3H1)

Achado da auditoria operacional de 24/08 ([[91 - Auditoria Operacional 2026-08-24]]). O gate de cobertura apareceu ALTO com 4 emissores "stale" (Simpar 25.1h, SLC Agrícola 25.1h, Bradesco 24.9h, Totvs 24.9h), mas o log da noturna de 23/08 tem `FIM: ... 103/103` (18:33:29) e os 4 foram cobertos naquele dia (OK|FULL). Ou seja: falso incidente.

**Causa raiz.** `obterAgoraBRT()` retorna `new Date(Date.now() - 3*36e5)` — desloca o epoch 3h para trás. Isso é correto para derivar o **dia civil** BRT (`hoje`), mas no `receber_analise` (worker.js:17781) o `_last_scanned_at` é gravado com `_raAgoraBRT.toISOString()` como se fosse o **instante da varredura**. Na leitura `_parseHorasStale` (worker.js:9464) compara contra `Date.now()` cru, então toda varredura parece 3h mais velha. Reproduzido: dado recém-gravado reporta `horas_stale` = 3h.

**Correção.** Gravar `_last_scanned_at` como `new Date().toISOString()` (UTC real) e usar `obterAgoraBRT()` apenas para `_raSemana`/`_raHoje`/`_raJanelaInicio` (objetos que não viram timestamp comparável). Alternativa: `new Date(_raAgoraBRT.getTime() + 3*36e5).toISOString()`.

**Guarda sistêmica (falta hoje).** Teste que falha se `horas_stale` de um dado recém-gravado via `receber_analise` não for `0`. Nenhum teste hoje compara `_last_scanned_at` com o relógio real; `obterAgoraBRT` foi tratado como fuso só no caminho de **data** (FUSOTESTE1), não como instante de varredura. Proposta de revisão de skill: o checklist da matriz passa a incluir "todo timestamp gravado que será comparado com o relógio real deve ser UTC puro".

**Correção aplicada (24/08 17h, commit `2928a74`).** `_last_scanned_at` passa a ser `new Date().toISOString()` no `receber_analise`, e o fallback de `persistirResultadoCompartilhadoInterno` deixa de herdar `payload.timestamp` e usa o instante real de persistência. O `timestamp` continua em BRT de propósito, porque dele sai o dia civil da janela. A distinção que faltava é essa: data e relógio não são a mesma coisa.

**Correção ao diagnóstico acima, sem apagá-lo.** O defeito é real e foi confirmado, mas os quatro emissores citados como evidência provavelmente não eram sintoma dele. Simpar e os demais vieram `sem_eventos` na varredura, e esse ramo do `persistirResultadoCompartilhado` sempre gravou UTC real. Os 25,1h deles são cadência diária honesta, não os 3h. A assinatura verdadeira só aparece comparando os dois ramos lado a lado, e é o que mantinha o defeito invisível: metade da carteira sempre reportou certo.

**Medição de produção, antes da correção, 24/08 17:17 BRT.** Mesma rodada noturna, três minutos entre os submits:

| Emissor | Evento na rodada | `horas_stale` |
|---|---|---|
| Light, Aegea, CSN, Hapvida | com evento | 3,40 |
| Rumo, Simpar | sem evento | 0,40 |

**Guarda sistêmica (existe agora).** `api/test/relogio-varredura.test.mjs`, 3 testes. Prova reversa executada: com o bug reinjetado os testes 1 e 3 falham com `expected 3 to be less than 0.5` e o 2, do emissor sem evento, passa nos dois. O terceiro teste prende a simetria entre os dois ramos, não só os valores, porque foi a assimetria que escondeu o defeito.

**Status:** RESOLVIDO EM PRODUÇÃO. Deploy v4.9.213 validado ao vivo por loop de 1 min (vix-radar-audit): c3 17:43 BRT `ver=v4.9.212`, c4 17:44 `ver=v4.9.213`, estável pós-deploy. `listar_plano_rotina` em v4.9.213: `total:103`, `max_horas:4.7`, `stale>=24h:0`; `Engie _last_scanned_at=2026-08-24T20:47 h_stale:0` (dado recém-gravado reporta 0, não 3h). Timestamps antigos gravados com a 212 (rodada das ~16h, ramo sem_eventos) tinham valor honesto, dentro do limite — não estouram mais o gate.

---

## 24/08 (quarta rodada) — RESOLVIDO: documento do Assaí aparecendo no Pão de Açúcar (SENDASGPA1)

A própria rotina noturna anotou o sintoma no meio da varredura: `Docs CVM do emissor Pão de Açúcar (GPA) têm empresa_cvm=SENDAS DISTRIBUIDORA S.A.`. Sendas é a razão social do Assaí (ASAI3), cindido do GPA (PCAR3) em 2021, e os dois estão na carteira como emissores separados.

**Causa raiz.** `SYNC_ALIAS_TO_EMPRESA` tinha três chaves quase iguais, `SENDAS DISTRIB` e `SENDAS DISTRIBUIDORA S/A` para o Assaí e `SENDAS DISTRIBUIDORA` para o GPA. A do meio está errada desde sempre, mas ficou dormente porque os consumidores antigos varrem a tabela com `for..in` e param no primeiro match, e `SENDAS DISTRIB` vem antes. O resultado saía certo por ordem de inserção, não por acerto. A derivação `SYNC_EMPRESA_TO_ALIASES` do NOMEMORTO1, do mesmo dia, coleta todos os aliases de cada emissor e não tem essa proteção. Foi ela que acordou a contradição.

Na mesma varredura apareceram duas chaves mortas na tabela privada do leitor, a duplicata `ISA Energia Brasil`, e o ACENTOMATCH1 outra vez: as chaves `Itau Unibanco` e `Itausa` estavam sem acento contra emissor acentuado, e o lookup é por chave exata. O fallback sem acento salvava `ITAU UNIBANCO`, mas `BANCO ITAU` ficava perdido.

**Guarda sistêmica.** `scripts/check-alias-coerencia.mjs` reprova alias contido em outro alias apontando para emissor diferente, alias apontando para emissor fora da carteira, e chave do leitor que não é nome de emissor. Entrou em `emissores-cadastro.yml` com injeção do bug real. Prova das duas pontas executada nos três casos.

A lição que passa dos aliases: numa tabela consultada por substring, duas chaves onde uma está contida na outra só podem apontar para o mesmo destino. Se apontam para destinos diferentes, o resultado depende da ordem de iteração de quem consulta, e cada consumidor novo é um sorteio.

**Status:** RESOLVIDO EM PRODUÇÃO, commit `2928a74`, deploy `acf920d` (v4.9.213), validado por loop de 1 min.

---

## 24/08 (quarta rodada) — RESOLVIDO: três defeitos no script da noturna, achados observando a rodada rodar

**CALIB3, calibragem de token 4x alta.** A CALIB2 da manhã de 24/08 saiu da linha `CUSTO:` do log de 23/08, escrita pela sessão do Claude Desktop, que mede o contexto inteiro do subagente. O `$stats.tokens_total` do script mede outra coisa. Comparar número de duas réguas diferentes deferiu 15 emissores à toa às 16h24. Números novos, medidos na régua do próprio script resolvendo o sistema com os dois lotes aprofundados de hoje: Sonnet 11.500 por emissor e boot 14.469, que confirma de forma independente os 15.000 já usados. Haiku 3.800, cobrindo o pior lote observado. A rodada fechou em 390.287 contra teto de 700.000, então o teto não precisa subir. Corrige o que eu havia dito antes, que faltava orçamento.

**ORDEMRAPIDA1, fila rápida não era ordenada por risco.** O comentário do CAPRESERVA1 afirmava que ela já vinha ordenada por EWS desc. Era falso, só a aprofundada tinha `Sort-Object`. Enquanto o cap nunca cortava a rápida ninguém notou, mas no momento em que cortou o corte caiu em quem calhou de estar no meio da lista. Agravante: o cap usava `continue`, então pulou o lote de 15 e deixou passar o de 13 logo atrás. Agora as duas filas ordenam pelo mesmo critério e o cap defere toda a cauda da fila, por fila e não global.

**SHADOWFALSOVERDE1, `parse_fail` lido como concordância.** O `divTag` só distinguia DIVERGE de match, e sem classificação do DeepSeek não há divergência a detectar, então ausência de comparação saía rotulada `match`. Foram 22 de 70 na rodada de hoje, quase um terço do lote. Ausência de comparação agora tem rótulo próprio, `sem_comparacao`.

**Status:** RESOLVIDO, commit `2928a74`. Vale na próxima execução da noturna, não precisa de deploy.

---

## 24/08 (quarta rodada) — ABERTO: fato relevante da Braskem de 24/08 não foi detectado

A Braskem protocolou recuperação extrajudicial em 24/08, reestruturação de US$ 10,9 bilhões, com 90 dias de proteção contra execuções. É o evento de crédito mais material do dia na carteira. A noturna analisou a Braskem às 16h e trouxe o rebaixamento da Fitch para RD de 17/08, não o protocolo de hoje.

Consequência prática: o painel continua com 20/08 como fato mais recente. O intervalo 21 a 24/08 é sexta, fim de semana e hoje, dois dias úteis, mas a ausência não é honesta, é falha de detecção com contraexemplo confirmado.

**Duas causas somadas.** O `ipe_cia_aberta_2026.zip` da CVM está em 404 desde 23/08 (CVMURL404), então o gatilho primário de fato relevante não existe. E a busca de imprensa da rotina, sozinha, não alcançou o protocolo do mesmo dia. A Braskem entrou na carteira horas antes da rodada, com `contexto_historico` vazio.

**Status:** ABERTO. Liga direto na decisão pendente sobre fonte alternativa de fato relevante, Dados de Mercado (token pago, API viva) ou adaptador MZiQ (grátis, cobertura não provada).

---

## 24/08 (terceira rodada) — RESOLVIDO: carteira corrigida, AES Brasil sai e Braskem entra (CARTEIRA-24AGO1)

Fechamento das decisões que a guarda de cadastro levantou, mais uma correção de cobertura que apareceu na varredura de fontes.

**AES Brasil saiu.** Foi incorporada pela Auren Energia, que já estava nos 103. Manter as duas contava o mesmo risco de crédito duas vezes e deixava um emissor permanentemente sem evento, porque não existe mais nada para achar. Nenhum registro AES está ativo na CVM, `AES TIETÊ ENERGIA S.A` consta CANCELADA por elisão por incorporação desde 2021. O histórico das semanas antigas fica intacto, ela só deixa de ser varrida daqui pra frente. Os aliases órfãos saíram de `SYNC_ALIAS_TO_EMPRESA` e de `TOKENS_ROBUSTOS_ANBIMA`, e a exceção saiu da guarda.

**Braskem entrou.** `BRASKEM S.A.`, CNPJ 42.150.391/0001-70, ATIVO na CVM. Protocolou fato relevante de pedido de recuperação extrajudicial aprovado pelo Conselho hoje, 24/08 às 09h38, e estava fora da carteira justamente no dia do evento mais material do ano dela. Foi declarada nas três pontas de alias de uma vez, mais o mapa de setor em `Petróleo, Gás e Combustíveis`, que é a lição do NOMEMORTO1 aplicada na entrada do emissor em vez de descoberta nove meses depois.

Total segue 103. Worker em v4.9.212, commit `b13b605`.

**Os outros três ficam, com motivo escrito.** Banco Pan e Banco Votorantim fecharam capital e seguem emissores de dívida sem protocolo IPE. Nexa Resources é de Luxemburgo, listada via BDR, e nunca foi companhia aberta na CVM. Continuam nos 103 e continuam como exceção declarada em `scripts/check-emissores-cadastro.mjs`. Evento deles só vem de imprensa e rating, o que é piso de cobertura conhecido, não falha de ingestão.

### Como a Braskem foi achada, que é o ponto que interessa

Não foi auditando o código. Apareceu enquanto eu media se a Dados de Mercado tinha fato relevante mais novo que o nosso, e o primeiro item da lista pública deles era a Braskem de hoje. Ou seja, a lacuna de cobertura só ficou visível porque olhei uma fonte externa e comparei com a nossa. Vale como método, não como acaso: comparar a carteira contra um agregador de mercado de vez em quando encontra emissor faltando de um jeito que nenhuma varredura interna encontra, porque internamente tudo parece consistente.

---

## 24/08 (segunda varredura) — RESOLVIDO: emissor renomeado ficava cego nove meses (NOMEMORTO1)

Nasceu de uma pergunta do operador. Depois de eu fechar o diagnóstico dizendo que não havia o que fazer do nosso lado, ele insistiu que sempre pegou os dados na CVM e que tinha que ter solução. Refiz a varredura e ele estava certo: parte do buraco nunca foi da CVM.

**O achado.** A Eletrobras virou AXIA ENERGIA em 10/11/2025, tickers ELET3/ELET5/ELET6 para AXIA3/AXIA5/AXIA6. Os documentos dela **estavam gravados** em `cvm:documentos` como `AXIA ENERGIA S.A.` e `AXIA ENERGIA NORDESTE S.A.`, e `buscarDocumentosCVM("Eletrobras")` devolvia zero. Nove meses de emissor exibido com `sem_eventos`, que na tela do cliente se lê como ausência de fato.

**Causa raiz.** Três tabelas de alias que precisavam concordar e não concordavam. `SYNC_ALIAS_NOMES_CVM` decidia se a linha da CVM entrava no KV, `SYNC_ALIAS_TO_EMPRESA` decidia de qual emissor era, e `buscarDocumentosCVM` tinha cópia própria e incompleta para decidir o que procurar. O documento entrava pela primeira, era atribuído pela segunda e sumia na terceira. A Auren só escapou porque alguém lembrou de repetir `CESP` nas três.

**Segundo bug, mesma família (ACENTOMATCH1).** O alias da Sabesp está escrito `CIA SANEAMENTO BASICO ESTADO SAO PAULO` e a CVM publica `CIA SANEAMENTO BÁSICO ESTADO SÃO PAULO`. `String.includes` é literal, então o documento ficava órfão, sem nenhum emissor reclamando.

**Terceiro achado, cruzando os 103 com `cad_cia_aberta.csv`.** Nem `CCR` nem `OMEGA` têm registro na CVM, nem cancelado. Quem existe e está ATIVO é a sucessora: `MOTIVA INFRAESTRUTURA DE MOBILIDADE S.A.` (mesmo CNPJ 02.846.056/0001-97) e `SERENA ENERGIA S.A.`. Nenhum alias declarado para as duas.

**Medido contra o `cvm:documentos` de produção, antes e depois:**

```
Eletrobras        0 -> 28 documentos
Sabesp            0 -> 11 documentos
documentos órfãos 2 ->  1
```

### Correção (Worker v4.9.211, commit `e55d68d`)

- O leitor deriva os termos de `SYNC_ALIAS_TO_EMPRESA` (novo `SYNC_EMPRESA_TO_ALIASES`) em vez de manter cópia. Alias novo passa a valer nas três pontas de uma vez, sem ninguém precisar lembrar.
- Comparação de nome de empresa contra fonte externa é sempre sem acento, dos dois lados, na ingestão e na leitura.
- Aliases novos para MOTIVA e SERENA.
- `admin_documentos_cvm`, somente leitura, responde o que o sistema enxerga para um emissor e com quais aliases. É a observabilidade cuja falta deixou o bug durar nove meses.

### Guarda sistêmica

`scripts/check-emissores-cadastro.mjs` confere os 103 contra o cadastro vivo da CVM. Exceção precisa ser declarada com motivo e data, senão reprova. Roda toda segunda em `.github/workflows/emissores-cadastro.yml`, na nuvem, deliberadamente fora da máquina local, porque o vigia local equivalente foi desligado em 21/08 e a fonte ficou escura quatro dias sem ninguém ver.

O próprio workflow prova as duas pontas. Isso não é zelo decorativo: a primeira versão da guarda **aprovou** um emissor inventado chamado "Ferrovia Fantasma Renomeada", porque o casamento por prefixo de 8 caracteres batia no meio de `FERROVIA CENTRO-ATLANTICA`. Sem a prova do lado ruim, ela teria entrado no repo parecendo funcionar.

### Aberto, decisão do operador

Quatro emissores sem registro ativo na CVM, hoje tolerados com motivo declarado. Nenhum gera documento IPE, então evento deles só pode vir de imprensa e rating. É piso de cobertura conhecido, não falha de ingestão.

- **AES Brasil**, incorporada pela Auren Energia. Fundir com Auren ou remover dos 103.
- **Banco Pan**, fechou capital, `BANCO PAN SA` consta CANCELADA.
- **Banco Votorantim**, sem registro como companhia aberta.
- **Nexa Resources**, companhia de Luxemburgo listada via BDR, nunca foi companhia aberta na CVM. Exceção permanente.

Fica também a pergunta de cobertura levantada na primeira varredura: a Braskem pediu recuperação extrajudicial em 24/08 e não está nos 103.

---

## 24/08 — RESOLVIDO: painel travado em 20/08, fonte da CVM morta em silêncio (CVMURL404)

Sintoma que o operador viu: o painel não mostrava nenhum fato, notícia ou evento depois de 20/08, com hoje sendo 24/08.

**As rotinas não pararam.** Rodaram nos dias 21, 22 e 23, varreram os 103 emissores em todas as noites (`_last_scanned_at: 2026-08-23` nos 103) e submeteram normalmente. O estado da semana W34 em produção tem 154 eventos, 0 pendentes de verificação, e o `data_evento` mais novo é `2026-08-20`. O painel estava dizendo a verdade.

**A causa é a fonte.** Em 23/08 a CVM removeu `ipe_cia_aberta_2026.zip` do servidor. Medido na auditoria: `HTTP 404` no arquivo do ano corrente, listagem do diretório indo só até `2025.zip`, e o catálogo CKAN ainda anunciando o recurso com `last_modified 2026-08-17T08:01:16`. O portal está vivo (`CAD` regenerado em 24/08 04:21 GMT, `ipe_cia_aberta_2025.zip` regenerado em 24/08 08:01). Não é o caso CVMCADENCIA1 de cadência semanal, é queda do arquivo do ano corrente, do lado da CVM. O zip de 2025 não carrega linha de 2026, então não havia fallback pronto em A-1.

Consequência: `cvm:documentos` congelou em `Data_Entrega 2026-08-15`, as rotinas perderam o gatilho primário de evento e a análise passou a reciclar o mesmo acervo de imprensa já conhecido. O volume decaiu antes de zerar, 68 eventos datados de 12 a 14/08 contra 17 datados de 18 a 20/08.

**Por que ninguém viu.** Três camadas falharam ao mesmo tempo. `avaliarFrescorCVM` tratava um 404 duro com a tolerância de 2 ciclos semanais (14 dias) criada para cadência, então `ok` agregado ficou `true` e o `canonical-test` verde. O caminho de erro de `gravarFonteCVMMeta` sobrescrevia a meta inteira e apagava `max_data_entrega`, então o health devolvia `cvm_fonte_idade_dias:null` e nem dava para saber há quanto tempo a fonte estava escura. E o `VIXRadar-Health-Watch`, único canal que alertava em `fonte_externa_ok`, está `Disabled` desde 21/08, um dia depois da fonte congelar. O gate de evento do `frescor-check.yml` só acusaria em 26/08, porque o fim de semana não conta dia útil e o limite é 2.

**Contribuinte secundário.** O cap de token da noturna deferiu a fila APROFUNDADA inteira em 22/08 (19 emissores, entre eles Oncoclínicas, Oi, Raízen, GPA, Light, CSN, Hapvida, Dasa) e 31 emissores em 23/08. Custo real medido em 23/08 é 25,2k por emissor na aprofundada e 12,3k na rápida, contra 13k e 9,5k calibrados. A fila rápida consumia 673k dos 700k e a aprofundada não disparava.

### Correção (Worker v4.9.209 e v4.9.210, commits `c0167cd`, `1572279`)

- **CVMURL404**: o ano do ZIP sai do relógio BRT em vez de cravado no código, que também consertava um bug latente de virada de ano, e em 404 a URL é reperguntada ao catálogo CKAN. Não resolvendo em nenhuma via, motivo `fonte_ausente_no_catalogo`.
- **CVMMETAWIPE1**: `gravarFonteCVMMeta` faz merge no caminho de erro, preserva `max_data_entrega` e `last_modified_iso`, e passa a contar `falhas_consecutivas` e `ultimo_sync_ok_em`. Como o wipe do incidente aconteceu antes do fix subir, o v4.9.210 acrescentou fallback que deriva a idade de `cvm:documentos` quando a meta de falha não tem data nenhuma.
- **CVMDURA1**: falha dura (`http_4xx/5xx`, exceção, arquivo ausente, ZIP inválido) derruba `fonte_externa_ok` na hora e escala para o `ok` agregado após `CVM_FONTE_MAX_FALHAS = 4` syncs falhos seguidos, ou seja 2 dias de crons. `CVM_FONTE_MAX_CICLOS` continua sendo o dono do caso "arquivo presente e velho".
- **VOLTTL1** aplicado a `cvm:documentos`: TTL de 14 para 30 dias, porque a chave só é reescrita em sync bem-sucedido e o lote útil da CVM é semanal.
- **CAPRESERVA1 e CALIB2** em `run_vixradar_noturno_claude.ps1`: reserva de orçamento para a fila aprofundada calculada antes do primeiro token, e calibragem pelo custo medido. A fila rápida continua rodando primeiro, porque inverter a ordem já zerou o Haiku em 09/07, mas agora bate num cap reduzido.
- **Alerta**: `frescor-check.yml` passa a checar a fonte e nomear o campo específico (HEALTHWATCH3), rodando na nuvem sem depender do Health-Watch local.

### Causa raiz e guarda

Causa raiz: o sistema tratava "fonte respondeu velho" e "fonte não respondeu" como o mesmo evento, medidos pela mesma régua de 14 dias. A régua estava certa para o primeiro caso e cega para o segundo. Somado a isso, o único alerta que cobria a fonte tinha sido desligado 2 dias antes por outra razão, e o caminho de erro destruía a evidência necessária para diagnosticar.

Guarda sistêmica: 8 testes novos em `api/test/cvm-frescor.test.mjs` travando o contrato nas duas pontas, falha dura reprovando e sync bom aceitando; bloco novo no `frescor-check.yml` que roda diário na nuvem e cita o campo; escalada automática para o `ok` agregado, que reacende `canonical-test` e `daily-status-email` sem depender de máquina ligada.

### Aberto, decisão do operador

A CVM ainda não repôs `ipe_cia_aberta_2026.zip`. Enquanto não repuser, a ingestão de Fato Relevante segue parada e os eventos dependem só de imprensa e RAD. Escopo decidido nesta sessão: **não construir fonte de ingestão nova**, detectar e alertar. Quando a CVM repuser, o sync volta sozinho. Se passar de 4 syncs falhos, o `ok` agregado cai e o alerta dispara.

---

## 24/08 (continuação) — RESOLVIDO: 2 fixes órfãos em worktree resgatados (WORKTREE12)

Das 6 worktrees do Claude Code, 4 eram checkout parado (BOM removido + caminho revertido para o legado `FREQUENTE\`, mesmo commit `e7f70d1` nas 4, sem nada de valor, removidas). As outras 2 tinham trabalho real nunca commitado, extraído a mão porque os arquivos-base já tinham divergido de `main` desde que as worktrees pararam de ser atualizadas.

### RETRY-PROP1 — validação pós-deploy falso-negativa em propagação lenta da borda

`deploy-worker.ps1` abortava com sleep fixo de 4s + tentativa única quando a propagação da Cloudflare demorava mais que isso. Incidente real no deploy do v4.9.196: produção já respondia a versão nova ~8s depois do script já ter abortado com `wrangler.toml` sujo e sem commit. Corrigido na worktree `quizzical-nightingale-0c534b` (base `6011d9a`), que não conhecia os gates HEALTHSPLIT1/CVMCADENCIA1 que entraram em `main` depois (`9b017af`). Fundido a mão em cima do `main` atual, não copiado por cima, os dois pontos não se sobrepõem no arquivo. Retry com backoff (60s, passo de 5s) substitui o sleep fixo, e `Fail-PosDeploy` documenta o caminho de recuperação explícito (commit manual ou `git checkout` do toml) em todo ponto de falha depois do passo 4 já ter tido sucesso, inclusive nos gates HEALTHSPLIT1/CVMCADENCIA1. Parse PS 5.1 e `lint-encoding.ps1` limpos. Commit `604c600`.

### ROTINA_RESUMO — 2 rotinas que faltavam no retrofit de 21/08 (ORF3D593D6)

O cherry-pick de 21/08 (ver `RESOLVIDO 21/08 (ORF3D593D6)` no `ESTADO.md`) trouxe a linha `ROTINA_RESUMO` pra matinal/noturno/coleta-volatilidade/export-historico/reconciliação-cvm, mas o commit original (`3d593d6`) tinha working tree com mais 2 arquivos nunca commitados: `run_vixradar_ranking_mensal.ps1` e `run_vixradar_verificacao_async.ps1`, esta última ainda ativa no Task Scheduler do Claude Desktop. Extraído da worktree `interesting-brahmagupta-4a7254`, reaplicado a mão porque `main` tinha divergido nos dois arquivos desde então (`82f5a0d`, migração de caminho canônico, 1 linha cada, sem sobreposição com os pontos de inserção do log). Parse PS 5.1 e `lint-encoding.ps1` limpos.

Achado no caminho, **não corrigido** por estar fora do escopo desta extração: `run_vixradar_ranking_mensal.ps1` linha 20 usa `$ErrorActionPreference = 'Stop'`, o mesmo anti-padrão que o `CLAUDE.md` documenta como causa de perda silenciosa de exit code no Task Scheduler (`adc9dbf`, `run-daily-scan.ps1`). Risco reduzido, a tabela de rotinas do `CLAUDE.md` marca `VIXRadar-Ranking-Mensal` como **OBSOLETO**, task não existe mais no Scheduler, então não há disparo agendado pra engolir o erro. Fica como pendência caso a rotina volte a ser agendada.

As duas worktrees removidas depois do commit. `3d593d6` (branch `claude/interesting-brahmagupta-4a7254`) e `2317dcd` (branch `claude/quizzical-nightingale-0c534b`) seguem alcançáveis pelos branches, só o diretório de trabalho saiu.

---

## 24/08 — RESOLVIDO: auditoria geral readonly, nucleo sem achado

Auditoria `vix-radar-general-audit` (`[[90 - Auditoria Geral 2026-08-24]]`). Portão de produção 200 com `ok:true` completo. Veracidade da UI batendo com o glossário nos 3 termos reservados (Emissores/Críticos/Relevantes + Sem alertas com janela declarada). Auth fail-closed nos 3 probes (state 401, receber_analise 403, login 401 genérico). Drift zero: prod v4.9.208/v202.30 = HEAD, os 317 arquivos "modificados" são só CRLF (`git diff -w` = 0). Nenhum P0/P1/P2 novo.

Observações (não reprovam o portão):
- **Fonte `CVM CIA_ABERTA/DOC` intermitente** — `fonte_externa_ok:false`, `cvm_fonte_motivo:ultimo_sync_falhou:http_404`, `ciclos_perdidos:null`. É fonte SEMANAL (domingos), domínio CVMCADENCIA1. 24/08 = segunda pós-domingo sem lote pode ser cadência, não incidente. Confirmar contra ramos `INF_DIARIO`/`CAD` antes de abrir qualquer coisa.
- **`main` local ahead 2 de `origin`** — só os `chore(data): historico 2026-08-22/23`. Push na próxima sessão.

---

## 22/08 (madrugada BRT) — RESOLVIDO: auditoria geral readonly e fechamento dos achados

Auditoria `vix-radar-general-audit` completa (detalhe: [[89 - Auditoria Geral 2026-08-22]]). Núcleo sem achado: auth fail-closed, veracidade da UI batendo com o glossário, drift zero, health verde completo. Itens novos abaixo.

### P3 — DATAATUALIZACAO1: painel confundia último evento com atualização da base — RESOLVIDO 22/08

Em 22/08, a tela declarava “Evento mais recente 20 de agosto”, embora a rotina de 21/08 tivesse concluído 103/103. A ausência de fato novo em 21/08 era legítima, mas o painel não dizia quando a base havia sido atualizada. **RESOLVIDO 22/08, deploy v202.30.** O carimbo agora mostra “Painel atualizado em [data e hora BRT]” e preserva a data independente do último evento.

### P3 — WRCGL1: changelog do wrangler.toml parado em v4.9.195 — RESOLVIDO 22/08

O cabeçalho do `api/wrangler.toml` declara `main = v4.9.195` na linha 2 e a última entrada de changelog é v4.9.195. O `main` real é `v4.9.208.js`. Zero entradas para v4.9.196 a v4.9.208. A verdade do deploy (main + bundle) está certa, mas o changelog-como-verdade que a skill de auditoria usa não registra 13 versões. Evidência: `rg "v4\.9\.20[0-9]" api/wrangler.toml` retorna 1, só o main. O `deploy-worker.ps1` não tem nenhuma menção a changelog, ou seja, nada reprova subir versão sem entrada. **RESOLVIDO 22/08, commit `9b017af`.** Treze entradas escritas, reconstruidas dos commits de git e desta fila. Gate novo no `deploy-worker.ps1` reprova deploy sem entrada de changelog para a versao que sobe.

### P3 — PULSOEVENTO1: pulso do Market Overview chama emissor de evento — RESOLVIDO 22/08

`app/index.html:4173`. O ramo crítico do pulso diz "Mercado com N emissores sob atenção crítica" (certo), o ramo relevante diz "N eventos relevantes em acompanhamento" contando `relevantesAtivos`, que é Set de EMISSORES. Termo reservado do glossário com grandeza trocada, irmão pequeno do ROTULOEVENTO1. **RESOLVIDO 22/08, deploy v202.29.** Pulso agora diz "N emissores em acompanhamento", confirmado no HTML servido em producao.

### P3 — JANELACARD1: card "Sem alertas" sem declaração de janela — RESOLVIDO 22/08

`app/index.html:4181`. O sub declara denominador ("X de Y emissores") mas não a janela fixa de 30 dias. O glossário manda declarar, ainda mais por estar ao lado do toggle 7D/30D que não o afeta. O fix de 14/08 (v202.9) dizia incluir "· 30 dias" e a string final não tem. **RESOLVIDO 22/08, deploy v202.29.** Sub do card diz "X de Y emissores · 30 dias", confirmado em producao.

### P3 — ESTADOSTALE1: seção "Versoes" do 03-Estado Atual parada em v4.9.194/v202.9 — RESOLVIDO 22/08

`03 - Estado Atual.md:159-161`. Topo do arquivo já declara v4.9.208/v202.28. Mesmo padrão de rodapé que não acompanha, reconciliado em 11/08 e voltou. **RESOLVIDO 22/08.** Seção atualizada para v4.9.208/v202.29/git `02c2157`.

### P3 — WORKTREE22: working tree sujo da sessão de 21/08 — RESOLVIDO 22/08

MOC + ESTADO modificados, notas [[87 - Fechamento Rotinas 2026-08-21]] e [[88 - Sessao Frontend Mobile 2026-08-21]] untracked, `main` ahead 1 de `origin/main` (`50384b3`, dado do historico). **RESOLVIDO 22/08.** Commits `9b017af`, `afbdc46`, `69a64dd`, `02c2157` enviados, main em sincronia com origin/main.

### P3 — DEPLOGGATE-JSON1: falha em gate do deploy-pages deixa version.json carimbado — RESOLVIDO 22/08

Observado em 22/08: gate 3.2 reprovou o deploy, mas `app/version.json` ficou com `deployed_at` do passo 2 sobre uma publicação que não aconteceu. **RESOLVIDO 22/08.** O passo 2 agora grava `deployed_at:null` durante o sync e todos os gates. O carimbo real nasce somente no passo 4, imediatamente antes do Wrangler. Se o envio falhar, DEPLOYTS1 volta o valor para `null`.

### Observação de design, não achado — DPA2SEMANAS1

`dados_para_analise` usa `carregarEstadoMultiSemana(env2222, 2)` (`worker.js:17473`). O contexto histórico entregue à rotina cobre só 2 semanas, eventos de 15 a 30 dias ficam invisíveis para o modelo. A dedup do Worker (data_evento|empresa|fonte_base) mitiga re-narração. Registrar, não mudar sem decisão do operador.

---

## 20/08 (19h20 BRT) — RESOLVIDO: 2 P1 de segurança, 6 P1 de perf/a11y, dívida de docs

Segunda janela do dia, depois da reabertura para clientes. Auditoria dos blocos D,
E e F mais a rotina noturna. Nada foi deployado, decisão do operador: mudança de
autenticação sobe com ele presente. Commits `810dc2c`, `6d657f8`, `806f2c7`.

**REGISTRO-ADMIN1 (P1, corrigido).** `handleRegistrar` derivava autoridade do
e-mail no corpo da requisição, que nunca é verificado. `isAdmin` comparava com
`ADMIN_EMAIL` e a conta nascia `aprovado` + `white_label`, e como `handleLogin`
calcula `roleFinal` pelo mesmo e-mail, quem soubesse o endereço do admin
registrava com senha própria e recebia JWT de admin sem nunca saber a
`ADMIN_PASSWORD`.

A contenção era acidental. Só o early return de `status === "aprovado"` barrava o
`putUser`. Com a conta ausente, ou com status `rejeitado`, que não tem early return
e cai no `putUser` sobrescrevendo o `senha_hash`, o vetor abria. Lido no KV de
produção: a conta existe como `aprovado` desde 04/04, então estava fechado por
estado e não por código.

Registro passa a nascer sempre pendente. A via legítima não muda,
`handleAdminAutoLogin` segue criando e aprovando a conta admin, gateado por
`admin_senha === env.ADMIN_PASSWORD`. A autoridade saiu do e-mail e ficou no
secret. Teste de regressão em `api/test/registro-admin.test.mjs`, provado nos dois
sentidos: com asserts do comportamento antigo, os dois falham, login devolve 401
em vez de 200.

**RATELIMIT-FAILOPEN1 (P1, corrigido) e AUTHDISPO1 (decisão do operador).** Os
três bypass de `checkRateLimitV2` devolviam `allowed:true`, então a queda do
binding apagava o rate limit de tudo, inclusive varredura que gasta LLM por
chamada. Criticidade agora é explícita, default `"critica"` fail-closed.

O `AUTHDISPO1` é a parte que exigiu decisão. Fechar tudo trocaria brute force por
indisponibilidade de login para cliente pagante, e o `catch` de `do_erro` pega
qualquer exceção, inclusive timeout transitório. O gate de auth separa os dois
casos que cobre: senha admin errada fecha (o operador com a senha certa pula o
check antes), login de cliente comum abre com `console.error` e telemetria
`rl_bypass_auth`, para o incidente ser curto e visível.

**A11YCONTRASTE1 e mais 5 P1 de frontend (corrigidos).** Contraste WCAG com três
substituições sistemáticas, `#6b7280` e `#64748B` para `#94A3B8`, `#374151` para
`#7C8C9E`. O pior valor antigo era 1,74:1 em texto de 9 a 14 px, contra o mínimo
de 4,5:1. As cores novas dão 5,57:1 e 6,17:1 calculados pela fórmula. Junto:
guard de aba oculta nos timers (o `_v201Poll` batia na API a cada 60 s para
sempre em segundo plano), debounce nos dois filtros de texto, navegação por
teclado nos clicáveis que eram `div` com `onclick`, informação não cromática no
`sev-dot` da sidebar, e `aria-live` onde não havia nenhum.

**Dívida de documentação (corrigida).** A causa raiz do "vitest não roda" estava
errada há tempo: culpava Smart App Control bloqueando `workerd.exe`. Medido,
`VerifiedAndReputablePolicyState=0`, SAC desligado, nenhum evento de CodeIntegrity
menciona workerd. A causa real é `npm ci --omit=dev` no deploy apagando as
devDeps. Com `npm ci` em `api/`, a suíte roda: 8 arquivos, 44 testes.

Junto: `worker.js` tem 18.597 linhas e não 17k, a migração v3 não está em
`wrangler.toml:561`, o gate de working tree confere 4 arquivos e não a árvore
inteira, o ponteiro do `AGENTS.md` apontava para arquivo não versionado, e a regra
de `.gitignore` para `setup-deploy-credential.ps1` era ilusória porque o arquivo é
trackeado desde `201ebda`.

### Abertos desta janela

**MANIFESTOFRAGIL1 (P3).** O `status/allclear-manifesto.json` indexa cada frase de
ausência junto com o HTML e o estilo inline. Trocar `color:#6b7280` por `#94A3B8`
fez duas frases idênticas aparecerem como NOVAS e reprovarem a guarda. Falso
positivo de segurança, mas fragilidade real: qualquer mudança de CSS quebra o
manifesto e obriga atualização manual. **Pronto quando** a chave for derivada só do
texto visível, sem estilo nem tag.

**DEDUPON2 e FEEDRERENDER1 (P2, diagnosticados, fora de escopo de propósito).** O
`_isDupSemantico` deduplica O(n²) sobre todos os eventos, no boot e em todo
refresh, com `normalize('NFD')` mais cascata de regex por evento. E o
`_v201Refresh` reconstrói 30 dias de feed a cada evento novo, cada card com cerca
de 13,8 KB de string HTML. Os dois são reais e medidos, mas exigem refactor com
risco de regressão. **Pronto quando** houver janela dedicada, não colada no fim de
outra.

**ORF3D593D6 (P2).** O commit `3d593d6`, que padroniza a linha `ROTINA_RESUMO` em 5
rotinas locais, nunca chegou ao remoto. Vive só na branch
`claude/interesting-brahmagupta-4a7254`. Testado: aplica limpo nos 5 scripts,
conflita apenas em `status/ESTADO.md:75`, porque 13 commits desde 18/08 reescreveram
o parágrafo vizinho. O trabalho segue relevante, o `ESTADO.md:262` registra o
retrofit como P2 aberto. **Pronto quando** o cherry-pick for feito e a branch
apagada.

**SACFALSA-RESIDUO (P3).** **RESOLVIDO 24/08.** Correção: a causa falsa do Smart App Control foi substituída pela causa real nos 3 arquivos vivos que a carregavam, `api/test/agenda-validacao.test.mjs:8`, `scripts/test-frescor-cvm.mjs:3` e `status/ESTADO.md:292` (que contradizia a própria linha 321, já refutada por medição em 20/08). Causa raiz: a crença de que o vitest não rodava por Smart App Control nasceu sem medição e gerou artefatos de código e de documentação que se propagaram por comentários, teste e estado vivo; a medição de 20/08 (VerifiedAndReputablePolicyState=0, nenhum evento CodeIntegrity cita workerd) refutou a premissa, mas a correção havia sido aplicada só no `worker-tests.yml` e numa linha do ESTADO, deixando resíduos. O `test-frescor-cvm.mjs` foi mantido porque cobre o cálculo de dias úteis em Node cru (31 casos) sem subir Worker. Guarda: gate no `scripts/hooks/pre-commit` reprova o blob em staging contendo "Smart App Control" fora de `Obsidian VIX Radar/` e `docs/archived/`. As notas de auditoria datadas (82, 85) e entradas antigas deste arquivo ficam intactas como registro histórico.

**WORKTREE12 (P3).** Doze worktrees registradas, incluindo de Codex e Traycer, e
seis commits nunca empurrados. Cinco são duplicata ou ancestral já absorvido, um é
o ORF3D593D6 acima. É a fábrica de commit órfão do projeto. O Bloco E propôs um
hook `pre-push` que aborta quando `HEAD..origin/main` não está vazio, o que pegaria
o caso do commit sanduichado de hoje. **Pronto quando** o hook existir e as
worktrees mortas forem podadas.

### Rotina noturna do dia

103/103 no ledger, zero falha de submit, zero silent fail, zero faltante de parse,
1 degradado para INCONCLUSIVO pela guarda de cobertura (B3 S.A., zero buscas
efetivas). Distribuição: 43 NENHUM, 27 ECO, 27 RELEVANTE, 5 CRÍTICO.

### Deploy do dia, com o operador presente

Subiu em 21/08 01h35: Worker v4.9.207 (REGISTRO-ADMIN1, RATELIMIT-FAILOPEN1,
AUTHDISPO1) e Pages v202.20 (contraste, aba oculta, debounce, teclado, aria-live).
O gate 3.4 reprovou duas vezes antes de publicar, desalinhamento do `?v=` nos
módulos admin (o CACHEBUMP1 de novo) e version.json sujo de tentativa anterior, e
abortou sem publicar nas duas. Validação pós-deploy colada no ESTADO.md.

### AUTONOMIAOFF1, decisão do operador

O operador mandou remover toda verificação autônoma do frontend que não esteja
cadastrada no sistema. Em 21/08 01h40 saíram os quatro timers que consultavam o
servidor: rate meter a cada 2 min, auto-update a cada 3 min, anomalias a cada 30
min e status da ribbon a cada 60 s. Também saiu o loop do watchdog local, que era
stub vazio. Restaram só timers locais sem rede (relógio, merge de anomalias
pre-carregadas, contagem regressiva), a carga inicial e os gatilhos de evento do
usuário (visibilitychange, pageshow, clique). Frontend em v202.21. A regra foi
escrita no CLAUDE.md para não voltar num refactor.

Críticos: Hapvida (cautelar da ANS barrando reajuste e rescisão em 947 mil
contratos), Oncoclínicas (recuperação extrajudicial deferida), Oi (gestor judicial
alerta caixa de R$ 19,6 milhões), Kora Saúde (AGDs reestruturam escritura da 2ª
emissão), CSN (Fitch rebaixa para CCC+).

A rodada R7, que entrou como cobertura preventiva sem caso comprovado, produziu o
primeiro achado real: Cade aprovando a aquisição de 30% da Copasa pela Equatorial,
mudança de controle em saneamento, vocabulário que R2 e R6 não alcançam.

Anotação de conformidade: 3 emissores da fila aprofundada (Rumo, Simpar, Dasa)
vieram ECO com 1 evento, e a skill especifica `eventos=[]` para ECO e NENHUM.
Direção segura, evento registrado com classificação conservadora. Zero casos do
inverso, que seria CRÍTICO ou RELEVANTE sem evento.

---

## 20/08 (21h15 BRT) — RESOLVIDO: janela de manutenção, 7 P0/P1 de veracidade de UI + SPREADSERIE1

Continuação da auditoria de 17h00. Worker foi de v4.9.203 a v4.9.206, frontend de
v202.12 a v202.19, 30 commits. Achados e correções, do mais grave ao mais leve:

**SPREADSERIE1 (P1).** A série `mercado:serie:*` atravessa uma troca de provedor
em abril sem tratamento: pontos legados em ponto-base (Oi 8873) misturados com
pontos `anbima_publico` em percentual (Oi 9,75) no mesmo cálculo estatístico.
`anbima:zscores` saía com 71 dos 73 emissores no mesmo `z_spread` de -0,55, sinal
sem sentido. Corrigido com corte por `fonte` antes de qualquer estatística
histórica, aplicado em `calcularZScoresANBIMA`, `handleSerie` e
`detectarAnomaliasEmpresa`. Campo renomeado para `taxa_indicativa_pct`, com
`spread_bps` mantido como alias por leitura dupla. Confirmado: não chega à tela
do cliente nem a e-mail, é lab interno.

**ZEROINDISPONIVEL1 (P0), a classe de bug do dia.** Cinco superfícies diferentes
tratavam "não consegui ler o dado" como "medi zero", afirmando saúde da carteira
sem nunca ter lido a base:
- painel EWS da home pública dizia "Todos os emissores monitorados estão dentro
  dos parâmetros normais" com `ewsRankingCache === null`;
- pulso do monitor operacional ficava verde com "Mercado em estabilidade" com
  `resultados` vazio;
- briefing e painel de eventos diziam "Nenhum alerta de mercado ativo" a partir
  de um detector que nunca dispara (ANOMSCHEMA1, ver abaixo);
- painel ANBIMA tinha check verde "Nenhuma anomalia detectada" mesmo com zero
  debêntures analisadas na amostra;
- os 5 `mo-card` do monitor (Críticos, Relevantes, Sem alertas) calculavam
  `(103-0-0)/103*100 = 100%` com chip verde quando `resultados` vazio, mesmo
  depois do pulso ao lado já ter sido corrigido para dizer "sem leitura".

Todos os cinco corrigidos com a guarda `_semLeitura` (ou equivalente no Worker,
`detector_operacional`), confirmados ao vivo em produção via CDP numa sessão
autenticada real. Achado real medido nessa sessão: 6 a 7 eventos críticos e
42 a 54 relevantes em 25 emissores na janela de 7 dias úteis, muito longe do
"tudo normal" que a home pública afirmava até esta rodada.

**SPREADUNIDADE1 (P0, rodada anterior, confirmado ao vivo nesta).** Card do
painel do emissor dizia "Spread ANBIMA ... bps" sobre taxa indicativa em % a.a.
Confirmado com dado real em produção: Oi mostrando "9.75% a.a." depois do fix,
não mais "9,75 bps".

**BANNERMORTO1 (P3).** Os 6 tipos de aviso ao usuário (erro_worker,
erro_conexao, dados_desatualizados, sem_chaves, sem_perplexity, sem_gemini)
nunca renderizavam, `style="display:none"` inline vencia a regra de CSS.
Corrigido, os 6 provados um a um em produção com prova de DOM (`display:block`,
altura 30px).

**ROTULOEVENTO1 (P2).** Cabeçalho do painel dizia "6 críticos" contando EVENTO
ao lado de "25 emissores com sinal" contando EMISSOR, mesmo termo do glossário
("Críticos") usado com grandeza diferente lado a lado. Corrigido para "N eventos
críticos (7d)".

**MOJIBAKEORIGEM1 (P3, rodada anterior).** `Get-Content` sem `-Encoding` no
`collect_cotacoes.ps1` corrompia nome acentuado, escondido em produção pelo
`Repair-Mojibake` do uploader mas causava diff falso em auditoria.

**Guarda sistêmica desta rodada.** `scripts/check-frontend-allclear.mjs`
substituiu a versão de 3 frases fixas por varredura de toda frase de ausência do
arquivo (57 encontradas), com manifesto versionado
(`status/allclear-manifesto.json`) e guardas amarradas por regex a frase
específica, não OR cego. Provado nos dois sentidos com 3 cenários de regressão
sintética. `scripts/audit-ui-live.mjs` substitui a inspeção por regex
(`audit-ui-metrics.mjs`, que só via 5 métricas) por inventário do DOM ao vivo via
CDP contra sessão autenticada real, com baseline versionado
(`status/ui-baseline.json`, 62 superfícies). Foi essa ferramenta que achou o
ROTULOEVENTO1.

**Rollback.** `_backup-janela-20260820/ROLLBACK.md` documenta o procedimento e
tem export de 6 chaves KV + 78 séries de mercado, tirado antes da janela. Não
versionado, fica só no disco local.

**Não executado nesta sessão, ordem original do operador previa isso para depois
da reabertura:** Bloco D (segurança do Worker, performance, acessibilidade,
OWASP LLM Top 10), Bloco E (TICKERPERIMETRO1 classificado, ANOMSCHEMA1
corrigido, CACHEBUMP1 automatizado, varredura do CLAUDE.md, revisão do commit
`a4a0b47` de sessão paralela), Bloco F (documento de decisão FONTELATENCIA1 e
DRIVERMORTO1, sem implementar). Seguem na fila abaixo, sem mudança de status.

---

## 20/08 (17h00 BRT) — ABERTO: fila da auditoria geral, com tag e critério de pronto

Tudo que a auditoria de 20/08 diagnosticou e **não** consertou. Cada item fecha com
o critério de pronto explícito, para a próxima sessão não precisar redescobrir o
escopo. Os itens resolvidos na mesma sessão estão na entrada de baixo.

### P1 — TICKERPERIMETRO1: mapa de tickers com perímetro errado, bloqueia market_cap

`data/cotacoes/tickers_emissores.json` declara 94 emissores listados para um universo
de 103, número alto demais para uma carteira de crédito privado. O próprio arquivo se
contradiz, o `_descricao` diz "Apenas emissores listados com capital aberto" e o
`_nota` diz "~68 dos 103 emissores são listados". Uma das duas está velha.

Pior que a contagem, há entradas apontando para entidade diferente da emissora.
`Compass Gás e Energia` aponta para `CMPC3.SA`, que é de outra companhia. `MRS
Logística` usa `MRSA6B.SA`, papel de balcão sem liquidez de tela. `Itaúsa` com
`ITSA4` é holding pura, enquanto quem emite dívida no grupo é o banco. `Compass` é
subsidiária da Cosan, que já tem `CSAN3` no mesmo mapa. Não fiz a classificação
completa das 94 entradas e não afirmo contagem que não apurei.

Isso é **pré-requisito bloqueante** de qualquer coleta de `market_cap` para Merton.
Com perímetro trocado, Merton mede equity da mãe contra dívida da filha e entrega
número plausível e errado, que é pior que o `null` de hoje.

**Pronto quando:** as 94 entradas estiverem classificadas uma a uma como emissora
própria, controladora ou relacionada, com a fonte da classificação registrada; as
relacionadas removidas ou marcadas como inelegíveis para Merton; e o `_nota`
reconciliado com o `_descricao`.

**RESOLVIDO 21/08, commit `bae552b`.** As 95 entradas (94 mais a Cielo, que faltava)
estão classificadas uma a uma com fonte no próprio arquivo. 91 elegíveis, 4
inelegíveis. Correções apuradas: Compass usa PASS3 desde o IPO de maio/2026 e não
CMPC3, MRS é balcão sem liquidez, Itaúsa é holding, Omega virou Serena e deslistou,
Iguá não negocia. Coleta de `market_cap` para Merton fica destravada, mas o pipeline
de coleta em si continua sendo o próximo passo do DRIVERMORTO1.

### P2 — DRIVERMORTO1: 3 dos 6 drivers do score nunca produziram valor

Diagnóstico real de cada um, corrigindo o que a sessão anterior tinha suposto.

`merton` está `null` nos 103 emissores em todos os exports desde 11/07/2026. O gate
em `worker.js:14074` exige `mktCap`, e nem `fundamentals:altman:latest` (DFP da CVM,
balanço puro, 0 ocorrências de `market_cap` em 99 empresas) nem
`cotacoes:volatilidade:v1` (que se recusa a publicar preço por ação como market cap,
de propósito e com razão) fornecem. Bloqueado por TICKERPERIMETRO1.

`momentum` exige `velocity_delta >= 2` sobre a série `ews:hist:{empresa}`. As 103
chaves existem, mas o conteúdo é raso e plano. `ews:hist:oi` tem 3 pontos, 18, 19 e
20/08, todos com score 66. A série só começou em 18/08, quando o HISTFLAT2 consertou
o casamento de chave em minúsculo. Duas causas somadas, série curta demais para
janela de 7 dias e score preso no piso estrutural.

`mercado` exige `spread_score >= 10`, que vem de `spreadScoreDeAnomalias` lendo
`mercado:anomalias:ativas`. Essa chave em produção tem 4 bytes, `{}`. Não é falta de
código nem de dado, ver ANOMSCHEMA1 logo abaixo.

Atenuante que baixa a severidade, `predictive_v1` é lab interno (`user_facing:false`)
e não chega à tela do cliente.

**Pronto quando:** cada um dos 3 estiver com fonte de dado no ar e cobertura maior
que zero medida por `scripts/check-drivers-preditivos.ps1`, **ou** removido do
`scorePreditivoRuleV1` e da lista `DRIVERS_DECLARADOS` do mesmo script. Driver
declarado que nunca dispara faz o modelo parecer mais rico do que é.

### P2 — ANOMSCHEMA1: detectores de anomalia desalinhados com o schema anbima_publico

`recalcularTodasAnomalias` tem escritor, tem 8 call sites e roda por cron
(`worker.js:17751` e `17800`). A entrada existe, 78 chaves `mercado:serie:*` frescas.
Ainda assim o resultado é `{}`, e são dois motivos empilhados.

Três dos quatro detectores são estruturalmente impossíveis com a fonte atual. O de
volume exige `ultimo.volume != null`, o de iliquidez lê `negocios` e `volume`, o de
concentração lê `maior_negocio`. Nenhum desses campos existe no registro
`anbima_publico`. Existiam na fonte antiga, o export de série ainda mostra registros
de março de 2026 com `volume:2628917` e `negocios:16`. A fonte trocou de provedor e
os detectores nunca foram adaptados.

O quarto, de spread, morre por unidade. O código faz
`deltaPP = Math.abs(ultimo.spread_bps - media) / 100` contra `SPREAD_LIMIAR_PP: 1`.
Com Aegea variando de 4,51 para 4,53, o delta é 0,0002 pontos percentuais contra
limiar de 1. Precisaria de variação de 100 unidades de um dia para o outro. E como o
SPREADUNIDADE1 mostrou, o campo carrega percentual, não ponto-base, então o `/100`
está errado por construção.

**Pronto quando:** os 3 detectores sem campo estiverem desligados explicitamente ou
reescritos para o schema `anbima_publico`; o de spread recalibrado para a unidade
real; e existir teste que reprove se `mercado:anomalias:ativas` ficar `{}` por N dias
consecutivos com séries frescas no KV.

**RESOLVIDO 21/08, commit `5283636`, em produção v4.9.208.** Os três detectores sem
campo ficaram marcados como desligados de propósito, o de taxa indicativa compara em
ponto percentual direto, sem o `/100` herdado do provedor antigo. Teste novo em
`api/test/anomalias-schema.test.mjs` semeia a série no formato real da fonte e exige
que um salto de 2,75 p.p. dispare, o que falharia contra o código antigo. A parte do
vigia que faltava, alertar `mercado:anomalias:ativas` vazio com séries frescas, fica
registrada como MELHORIA futura no `check-drivers-preditivos.ps1`, não bloqueia.

### P2 — SPREADUNIDADE1 (resíduo): renomear o campo e corrigir os consumidores restantes

A parte P0 foi corrigida hoje, ver entrada de baixo. Sobra o que é migração.

O campo no KV continua se chamando `spread_bps` guardando taxa indicativa em % a.a.
Renomear é migração de chave em 78 séries mais o parser mais o endpoint `op=serie`.
O card de anomalia do frontend ainda concatena `spread_atual_bps + " bps"`, hoje
inócuo porque `mercado:anomalias:ativas` é `{}`, mas volta a mentir junto com o
ANOMSCHEMA1. O dataset de DEMO tem `spread_atual_bps:387` e `612`, valores em bps
reais e internamente coerentes, que ficam como estão.

**Pronto quando:** o campo tiver nome que diga a grandeza e a unidade, todos os
consumidores acompanharem, e o card de anomalia não puder ressuscitar com o sufixo
errado.

### P2 — PUBDATA1: data_publicacao_fonte nunca foi populado

Medido nos 74 eventos vivos do estado da semana W34: `data_evento` preenchido em
74/74, `data_publicacao_fonte` preenchido em **0/74**. O campo existe no schema desde
sempre e nunca recebeu valor. Sem ele não dá para ordenar por "apareceu agora", só
por data do fato, que é outra coisa.

**Pronto quando:** o pipeline preencher o campo no `receber_analise` e a taxa de
preenchimento passar de 80% numa amostra de 30 dias.

### P3 — FEEDNOVIDADES1: aba Novidades, parada por decisão

Aprovada em conceito e adiada de propósito. Depende de PUBDATA1, senão a aba nasce
ordenando por data do fato com cara de ordenar por novidade. A ordenação atual do
feed é severidade primeiro e data só como desempate
(`{CRITICO:0,RELEVANTE:1,ECO:2}` e `localeCompare` no desempate), o que prende o topo
da tela no cluster de resultados do 2T26 até ele sair da janela de 30 dias.

**Pronto quando:** PUBDATA1 fechar e o aviso de frescor (entregue hoje) tiver rodado
uma semana em produção sem reclamação.

### P3 — FONTELATENCIA1: fonte de baixa latência é decisão de produto

O ramo `CIA_ABERTA/DOC` da CVM é semanal e publica aos domingos. Isso é lento demais
para monitoramento de crédito, e o caso Casas Bahia prova a defasagem: fato relevante
de recuperação judicial protocolado em 16/08, comunicado em 18/08, e a última linha
da companhia dentro do ZIP é de 10/08.

Alternativas com custo. RAD interativo (`rad.cvm.gov.br`) é a fonte de baixa latência
real, custo é scraping de ASPX com viewstate e captcha em algumas rotas, manutenção
alta. B3 publica fatos relevantes de listadas com latência de horas, cobertura menor
que a CVM. Nenhuma das duas é recomendada antes de o operador decidir se a latência
semanal é problema de negócio ou só incômodo.

**Pronto quando:** o operador decidir, e a decisão estiver escrita aqui com a razão.

**RESOLVIDO 21/08, decisão assinada no `DECISOES-OPERADOR-2026-08-20.md`, commit
`5283636`, em produção v4.9.208.** Recomendação aceita: sem scraping do RAD. O Worker
promove para FULL com motivo `imprensa_recente_7d` emissor com evento
CRITICO/RELEVANTE dos últimos 7 dias, e a skill da noturna manda esse motivo para a
fila aprofundada. A checagem pontual no RAD continua só no gate de evento de RJ,
default e rebaixamento.

### P3 — BANNERMORTO1: o banner de aviso nunca pintou para ninguém

`<div id="banner" style="display:none">` tem estilo inline, e a regra
`#banner.visible { display: block }` é de folha de estilo, que perde para inline.
Verificado ao vivo em produção: a classe `visible` está aplicada, o texto está no
elemento, `computed display` é `none` e a altura é 0. Removendo o inline via console,
o elemento aparece com 31px.

Consequência dupla. O falso "Serviço temporariamente indisponível" nunca chegou ao
cliente, que é a boa notícia. E os avisos legítimos (`erro_conexao`,
`dados_desatualizados`, `sem_chaves`) também nunca chegaram, que é a ruim.

Religar exige cuidado de ordem: o gatilho já foi corrigido hoje para depender só de
liveness, mas os outros 5 tipos de aviso nunca foram vistos por usuário nenhum.

**Pronto quando:** os 6 tipos de aviso tiverem sido revisados um a um quanto a texto
e gatilho, o inline `display:none` sair, e existir teste de DOM que confirme
visibilidade real.

### P3 — CACHEBUMP1: alinhamento manual do `?v=` a cada deploy Pages

Terceira vez seguida. Os commits `01ff325` e `4276504` do v202.12 fizeram o mesmo, e
hoje o gate 3.4 do `deploy-pages.ps1` reprovou duas vezes até os 4 módulos admin
serem alinhados à mão. O bump do `CACHE_VERSION` no `index.html` não propaga sozinho
para os imports em `app/js/`.

**RESOLVIDO 24/08.** Dado o `bump-cache-version.ps1` (o script existe e altera os
pontos de cache), o foco virou os TRÊS defeitos de comportamento da `Replace-InFile`
que ele carregava, que o tornavam perigoso num `index.html` de 700 KB:
(1) trocava `"v<n>.<n>"` entre aspas em QUALQUER lugar (copy/UI/changelog), sem âncora;
(2) colisão de substring — versão `v202.3` casava dentro de `?v=202.30` e produzia
`?v=203.10`; (3) a substituição do caso `?v=v<n>.<n>` usava `$newRe` (o valor JÁ
[regex]::Escape()'d) em vez do literal `$New`, o que inseriria `v203\.1` com barra
invertida na saída. Correção em `scripts/bump-cache-version.ps1`: troca genérica de
aspas removida (CACHE_VERSION muda só via regex ancorada no prefixo
`CACHE_VERSION="`), `?v=` com negative lookahead `(?![0-9])` (sem prefixo de outra
versão), e substituição do caso `?v=v<n>.<n>` passou a usar `$New` literal (só o lado
PADRÃO escapa; o lado SUBSTITUIÇÃO usa o valor). `$newRe`/`$newNumRe` removidas por
ficarem órfãs. **Causa raiz (ampliada):** o defeito (3) nasceu de acreditar que
substituição de [regex]::Replace exige o mesmo escape do padrão — não exige — e
passou porque o teste só cobria a instância (`?v=202.30`), nunca a classe (barra
invertida na saída via variável escapada). **Guarda:** `scripts/test-bump-cache-version.ps1`
roda o real numa bancada isolada (`scripts/_tmp_bump_test/bump2`, criada e limpa pelo
próprio teste) e agora também asserta (a) `?v=v202.3` → `?v=v203.1` sem barra e
(b) a saída NÃO contém NENHUMA barra invertida — asserção que fecha a classe do
erro, não só a instância. Validado: parse PS 5.1 (`lint-encoding.ps1` OK 1/RISCO 0 p/
ambos), BOM único, teste verde exit 0 (8x OK, incl. `?v=v202.3⇒?v=v203.1 (sem barra)`
e `saida sem nenhuma barra invertida`).

---

## 20/08 (17h00 BRT) — RESOLVIDO: CVMCADENCIA1, HEALTHSPLIT1, SPREADUNIDADE1, MOJIBAKEORIGEM1

**CVMCADENCIA1 (P1).** A premissa "a CVM parou de publicar", escrita em 19/08 e
repetida por mim duas vezes em 20/08, é falsa. O ramo `CIA_ABERTA/DOC` tem cadência
**semanal declarada** na página do dataset e publica aos domingos. Evidência:
`ipe_cia_aberta_2026.zip` e o de 2025, corrente e A-1, regerados no mesmo domingo
16/08 com 1 minuto de diferença, e o domingo anterior também. O portal segue vivo,
`FI/DOC/INF_DIARIO` e `CIA_ABERTA/CAD` foram regerados em 20/08 de madrugada. E a CVM
segue recebendo protocolo, Casas Bahia protocolou em 16 e 18/08.
*Correção:* `CVM_FONTE_MAX_DU = 2` virou regra de ciclo perdido, alerta só após dois
ciclos semanais sem publicar, ou seja 14 dias corridos. *Causa raiz:* medir fonte de
cadência 7 dias com régua de 2 dias úteis fazia o health ir a vermelho toda quarta ou
quinta, previsivelmente. *Guarda:* 3 testes novos em `cvm-frescor.test.mjs` (4 dias
passa, 13 dias passa com 1 ciclo perdido, 14 dias reprova) e o fato da cadência
registrado na skill `vix-radar-general-audit`.

**HEALTHSPLIT1 (P1).** Frescor de fonte de terceiro saiu do `ok` agregado e foi para
`fonte_externa_ok`. *Causa raiz:* `ok` tem 13 consumidores que o tratam como
liveness, entre eles `rotate-routine-key.ps1` que **aborta** a rotação da chave,
`scan-emergencia.yml` que dispara varredura, 4 workflows de CI e o banner da tela.
Nenhum tem ação útil diante de "a CVM publica aos domingos". *Guarda:* canal de
alerta próprio no `watch-vixradar-health.ps1` com reenvio de 48h, e o inventário dos
13 consumidores registrado no `CLAUDE.md`.

**SPREADUNIDADE1 (P0).** O card do painel do emissor dizia "Spread ANBIMA" e
carimbava " bps" num valor que é taxa indicativa em % a.a. Medido em produção:
Petrobras aparecia como "6,98 bps", CSN como "20,08 bps", Aegea como "4,53 bps". Erro
de fator 100 na unidade sob nome que nem era o da grandeza. *Causa raiz:*
`worker.js:12584` empurra `r.taxa_indicativa`, coluna 6 do arquivo público de
debêntures da ANBIMA, para dentro de um campo chamado `spread_bps`. Nome do campo
mentindo desde a ingestão, e a tela repetindo a mentira. *Correção:* rótulo virou
"Taxa indicativa ANBIMA", valor recebe "% a.a." e o delta " p.p.". Resíduo de
migração fica no SPREADUNIDADE1 acima.

**MOJIBAKEORIGEM1 (P3).** `collect_cotacoes.ps1` lia `tickers_emissores.json` sem
`-Encoding`, e o 5.1 usa a página ANSI por padrão. Arquivo UTF-8 sem BOM virava
mojibake e era carimbado em `meta_volatilidade.json`. *Causa raiz:* a rede
(`Repair-Mojibake` no uploader) escondeu o problema por meses, produção nunca viu
nome errado. O custo aparecia em outro lugar, comparação por nome entre os dois
arquivos errava em silêncio, e um diff da auditoria acusou 33 falhas onde o número
real era 21. *Guarda:* `-Encoding UTF8` nos dois `Get-Content` do script, artefato em
disco reparado, e `Repair-Mojibake` mantido como rede, não como conserto.

---

## 20/08 (15h50 BRT) — PARCIAL: por que o feed parece congelado, e o que estava quebrado por baixo

Pergunta de origem: "o sistema nao foi atualizado". Investigacao encontrou uma causa externa e
tres defeitos internos que ninguem tinha visto, dois deles corrigidos nesta sessao.

**A causa do feed parado nao e bug nosso.** O arquivo bulk da CVM parou de ser publicado:
`Last-Modified: Sun, 16 Aug 2026 10:00:36 GMT` no
`https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_2026.zip`, 4 dias uteis
atras. O `cvm_fonte_ok:false` no health publico esta certo e derrubando o `ok` agregado de
proposito. As rotinas rodaram normalmente: matinal 20/20 hoje as 10h21, verificacao-async 16
eventos submetidos as 10h37, evento mais novo em producao de 18/08 (`idade_du:2`, no limite).
O que o usuario ve como "parado" e a soma do apagao da CVM com a lacuna de produto ja registrada
em 19/08 (o feed mostra o evento mais material da janela de 30 dias, nao o delta do dia).

**VOLTTL1 (P2, corrigido).** A chave `cotacoes:volatilidade:v1` sumiu de producao. O upload de
19/08 17:02 falhou (`upload_volatilidade_kv.ps1 exit=1`, `LastTaskResult 1` na
`VIXRadar-Coleta-Volatilidade`) e o TTL era 86400, exatamente o intervalo entre duas execucoes.
A escrita de 18/08 expirou as 17:01 e a chave passou a responder 404 no
`wrangler kv key get --remote`. O pipeline preditivo le com `.catch(() => null)`, entao rodou o
dia inteiro sem volatilidade, sem log e sem alerta.
*Correcao:* chave republicada agora (`UPLOAD_OK`, 73 emissores, Selic 0,139 as_of 2026-08-19) e
TTL para 259200. *Causa raiz:* TTL igual ao intervalo de gravacao nao deixa folga para uma unica
falha. *Guarda:* item permanente na skill `vix-radar-general-audit` exigindo TTL >= 2x o intervalo
de gravacao para toda chave alimentada por rotina agendada.

**VOLLOG1 (P2, corrigido).** O `run_coleta_volatilidade.ps1` capturava a saida do uploader em
`$uploadOutput` e no `catch` logava so `ERRO upload: ... exit=1`. As linhas `AVISO:` com o motivo
real eram descartadas, entao a falha de 19/08 ficou sem diagnostico possivel. *Correcao:* o
`catch` agora despeja a saida capturada no log. *Guarda:* item permanente na skill para auditar
todo wrapper de rotina que chame script filho.

**HEALTHWATCH3 (P3, corrigido).** O `watch-vixradar-health.ps1` so lia `ok`, `verificador_ok` e
`versao` do health. O e-mail e o log diziam `ok=False verificador_ok=True` e nada mais, por 3 dias
seguidos de 15 em 15 minutos, sem citar `cvm_fonte_ok`. *Correcao:* o snapshot passou a carregar
`kv`, `telemetria`, `sentry_ok`, `admin_email_ok` e `cvm_fonte_ok` + motivo, e o alerta nomeia o
campo vermelho. Testado ao vivo: `DEGRADADO: ok=False versao=v4.9.203 CAUSA: cvm_fonte_ok=false
(fonte_parada_ha_4_dias_uteis)`. *Guarda:* item permanente na skill exigindo que alerta automatico
nomeie o campo, nunca so o agregado.

**DRIVERMORTO1 (P2, diagnosticado, decisao do operador pendente).** 3 dos 6 drivers declarados em
`scorePreditivoRuleV1` nunca produziram nada em producao. `merton_dd` esta `null` nos 103
emissores em **todos** os exports desde 11/07/2026 (checado em 2026-07-11, 07-12, 07-13, 08-13,
08-16, 08-18, 08-19 e no snapshot ao vivo de hoje). O gate em `worker.js:14074` exige `mktCap`, e
as duas fontes possiveis nao tem esse campo: `fundamentals:altman:latest` vem da DFP da CVM
(balanco, 0 ocorrencias de `market_cap` em 99 empresas) e `cotacoes:volatilidade:v1` se recusa a
publicar preco por acao como market cap, de proposito e com razao. `momentum` e `mercado` tambem
ficam em zero (`velocity_delta` 0 com `tem_serie:false`, `spread_score` 0). Isso contradiz a
premissa MERTONLIVE1 da skill de auditoria, que afirmava que Merton movia score em producao.
*Mitigante:* `predictive_v1` e lab interno (`user_facing:false`), nao chega na tela do cliente.
*Guarda ja aplicada:* `scripts/check-drivers-preditivos.ps1` mede cobertura por driver no export
diario, reprova driver novo com cobertura zero, e foi ligado no
`run_vixradar_export_historico.ps1`. A premissa errada foi corrigida na skill.
*Decisao pendente do operador:* ou entra uma fonte de `market_cap` (acoes em circulacao x preco,
dado que hoje nao e coletado) e os 3 drivers passam a valer, ou eles saem do codigo. Manter
driver declarado que nunca dispara faz o modelo parecer mais rico do que e.

---

## 19/08 (09h15 BRT) — RESOLVIDO: RETRYCFG1, as duas tasks de retry nasceram sem as guardas do projeto

Achado pela varredura de pendencias do workspace (`/resolver-pendencias`), nao por incidente novo.

O monitor acusava `Szuchmacher-RetryVixMatinal` com `LastTaskResult 2147946720` desde 18/08. Esse
codigo e `0x800710E0` (ERROR_REQUEST_REFUSED), e tanto o codigo quanto a remediacao ja estavam
documentados em `AI_OPERATING_SYSTEM/06_RISCOS_E_DIVIDAS_TECNICAS.md:72` (extraido de dentro do
repo do Jarvis para a raiz do workspace em 20/08/2026)
("condicao de energia / maquina suspensa, flags de bateria + `StartWhenAvailable`"). O mesmo fix ja
tinha sido aplicado em 09/08 no `Szuchmacher-MacroCron` e no `Szuchmacher-AgendaAgent`.

A sessao da madrugada de hoje acertou a causa por evidencia (evento 153, maquina desligada das 03h42
as 16h14, gatilho das 13h30 perdido) mas parou antes de aplicar a correcao.

**Causa raiz.** As duas tasks de retry nasceram em 17/08 criadas a mao. Sao as **unicas** do projeto
sem script de registro: as outras nove tem, e todas as nove setam `StartWhenAvailable`. Fix aplicado
a instancias, nao ao padrao, entao a task criada depois nasceu sem ele.

**Tres defeitos, nao um** (o dump da configuracao expos os outros dois):

| Configuracao | Estava | Agora | Por que importa |
|---|---|---|---|
| `StartWhenAvailable` | `False` | `True` | Disparo perdido era descartado em silencio |
| `DisallowStartIfOnBatteries` / `StopIfGoingOnBatteries` | `True` / `True` | `False` / `False` | Em bateria a task recusa iniciar, e morre se a energia cai no meio |
| `ExecutionTimeLimit` | `PT72H` | `PT4H` | 72h com `MultipleInstances IgnoreNew`: uma instancia travada bloquearia os 3 dias seguintes de retry sem ninguem ver. Toda irma no projeto usa minutos ou poucas horas |

**Guarda sistemica:** `scripts/register-retry-tasks.ps1`, que faltava. Reproduz as duas tasks com a
configuracao correta e **verifica o resultado no fim**, saindo 1 se qualquer campo divergir. XML das
duas versoes antigas salvo em `%TEMP%\retrytasks_bk_20260819-091356\` antes de mexer.

**Prova (saida real do script):**
```
Szuchmacher-RetryVixMatinal
  StartWhenAvailable         = True  (esperado True)
  DisallowStartIfOnBatteries = False  (esperado False)
  StopIfGoingOnBatteries     = False  (esperado False)
  ExecutionTimeLimit         = PT4H  (esperado PT4H)
  NextRunTime                = 19.ago.2026 13:30:00
Szuchmacher-RetryVixNoturno
  ... idem, NextRunTime = 19.ago.2026 21:30:00
OK: as duas tasks estao com StartWhenAvailable, tolerancia a bateria e teto de 4h.
```

**O alerta do monitor continua vermelho ate 13h30 de hoje, e isso esta certo.** Re-registrar nao zera
`LastTaskResult`, so uma execucao bem-sucedida zera. Rodar a task agora (09h15) seria pior: a matinal
so roda as 10h, o retry nao acharia linha `FIM` do dia e relancaria a rotina uma hora antes da hora,
gastando cota e colidindo com a sessao agendada. O bloco `<!-- AUTO-MONITOR-START -->` do backlog
central e regenerado pelo `monitor-tasks.ps1`, entao nao adianta riscar a linha la a mao.

**Nao confundir com um quarto item:** `Szuchmacher-RetryVixNoturno` estava com `LastTaskResult 0`, ou
seja nunca falhou, mas carregava exatamente os mesmos tres defeitos de configuracao. Foi corrigido
junto por isso, nao por ter dado erro.

---

## 19/08 (08h30-09h00 BRT) — ABERTO: feed segue em 14/08, causa e apagao da CVM + cegueira de frescor

Usuario reportou que, mesmo apos os fixes DEDUP1 e HISTFLAT1+2 da madrugada, o Painel de Eventos
continua parando em 14/08. Auditoria geral (`vix-radar-general-audit`) provou que **o painel esta
correto** e o problema e de dado, nao de renderizacao.

### Prova, varredura nos 103 emissores canonicos via `dados_para_analise`
```
MAX data_entrega CVM  (103 emissores) = 2026-08-15
MAX data_evento estado (103 emissores) = 2026-08-14
emissores sem doc CVM na janela 30d = 26
emissores sem evento no estado      = 44
```
Script em `scratchpad/probe-frescor.ps1`, detalhe por emissor em `scratchpad/frescor-por-emissor.txt`.

### CAUSA RAIZ 1 (externa) — a CVM parou de publicar em 16/08
```
CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_2026.zip   Last-Modified: Sun, 16 Aug 2026 10:00:36 GMT
CIA_ABERTA/DOC/FRE/DADOS/fre_cia_aberta_2026.zip   Last-Modified: Sun, 16 Aug 2026 10:03:19 GMT
CIA_ABERTA/DOC/ITR/DADOS/itr_cia_aberta_2026.zip   Last-Modified: Sun, 16 Aug 2026 10:46:07 GMT
CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv            Last-Modified: Wed, 19 Aug 2026 04:15:42 GMT
```
IPE, FRE e ITR parados ha 3 dias no servidor da propria CVM. So o CAD (cadastro) segue atualizando.
Baixado o ZIP real e rodado o mesmo parser do Worker contra ele (`scratchpad/test-cvm-zip.mjs`):
```
descomprimido OK: 13290631 bytes
MAX Data_Entrega no arquivo da CVM: 2026-08-16
linhas por Data_Entrega >= 13/08: {"2026-08-14":332,"2026-08-13":358,"2026-08-15":6,"2026-08-16":4}
```
Zero entrega em 17 e 18/08, dias uteis. **O parser de ZIP do `syncCVMAutomatico` esta correto**, nao
e ZIP64, nao tem data descriptor, `compSize` do local header bate, descompressao limpa em 1,1s.
Hipotese de estouro de CPU no laco `String.fromCharCode` tambem descartada, 670ms local.

### CAUSA RAIZ 2 (interna) — nenhuma guarda mede frescor de dado, todas medem se o escritor rodou
- `heartbeat:sync_cvm` = `{"status":"ok","ts":"2026-08-18T21:30:56.564Z"}`. Verde durante o apagao.
- `api/src/worker.js:17506` e `:17550` fazem `await syncCVMAutomatico(env)` e carimbam `"ok"` **sem
  checar o retorno**. A funcao devolve `{ok:false}` (nao lanca) em fetch !ok, arquivo nao-ZIP e
  metodo nao-Deflate. Buraco latente, nao foi o caminho de hoje, mas mascararia falha real.
- `.github/workflows/frescor-check.yml` valida `estado_semanal.updated_at` e
  `empresas_com_dados >= 50`. Os dois ficam verdes com conteudo reciclado porque a rotina escreve
  todo dia. Nunca olha idade do evento mais novo nem idade da fonte.

### Consequencia observada — a rotina recicla fato velho
Log `logs/routines/vixradar-noturno_20260818.log`:
```
2026-08-18 18:17:13 ANOTA_rapida_1: CEMIG|Duas emissoes novas em 14/08/2026, 16a da Cemig D e 13a da Cemig GT...
2026-08-18 18:17:16 OK|CEMIG|FULL|RELEVANTE|1|true
```
Rodou em 15, 17 e 18/08, submeteu 1 evento cada vez, e a CEMIG segue com 2 eventos, o mais novo de
14/08. A dedup do Worker funciona. O que ela deduplica e o modelo re-narrando a mesma noticia porque
o `cvm_documentos` entregue a ele tambem parou em 14/08.

### Veracidade da UI — 2 achados novos
- **"Atualizado em 19 de agosto de 2026"** e `new Date()` do navegador (`app/index.html`, funcao de
  relogio do dashboard), nao timestamp de dado. Nunca pode ficar velho, por definicao.
- **Tira de fontes do rodape e decoracao pura.** `st-cvm`, `st-anbima`, `st-b3`, `st-fitch`,
  `st-moodys` aparecem **uma unica vez cada** no arquivo, dentro do HTML estatico com
  `class="status-item ok"` fixo. Nenhum codigo le ou altera em runtime. "CVM RAD" ficou verde
  durante 3 dias de apagao real da CVM.
- Script obrigatorio `audit-ui-metrics.mjs`: `0 bloqueante(s), 9 informativo(s)`.

### Achado menor
`heartbeat:cascade_analise` nao existe no KV. E o `stale_count:1` que o `watchdog_diario` reportou
em `2026-08-19T01:00:51.106Z`.

### As duas P0 — RESOLVIDAS e em producao (v4.9.201 depois v4.9.202)

**P0-1 CVMFRESCOR1, a idade da fonte entra no health.** `syncCVMAutomatico` passou a
carimbar `cvm:fonte_meta` com o `Last-Modified` do servidor da CVM e a maior `Data_Entrega`
do arquivo INTEIRO, medida antes de qualquer filtro de emissor (se medisse so os 103, um dia
em que a CVM publicou normalmente mas nenhum emissor nosso protocolou pareceria fonte
parada). `avaliarFrescorCVM` decide por dias uteis, fim de semana nao conta, limite de 2 du.
Fail-closed: meta ausente, ilegivel, sem data ou de sync que falhou nao conta como fresca.
`cvm_fonte_ok` entrou no `_okHealth` pelo mesmo criterio do SECRETMISS1 e do SENTRY1.

**P0-2, os crons passam a checar o retorno.** `worker.js` linhas do bloco matinal e noturno
so verificavam se `syncCVMAutomatico` explodiu. A funcao devolve `{ok:false}` sem lancar em
fetch !ok, arquivo nao-ZIP e metodo nao-Deflate, entao a CVM poderia devolver HTML de erro
por uma semana com heartbeat verde. Agora o retorno decide o heartbeat, e o heartbeat de
sucesso carrega `documentos`, `last_modified` e `max_data_entrega`.

**CVMFRESCOR1b, falha do proprio fix, achada na primeira leitura em producao.** Com o gate
valendo e nenhum cron tendo rodado, o motivo vinha `sem_meta` e o health ficaria vermelho por
ate 12h a CADA deploy. Alarme falso recorrente treina quem olha a ignorar o alarme, que e o
mecanismo por tras dos 5 dias congelados. Corrigido derivando a idade de `cvm:documentos`,
que ja existia, com backfill gravado uma unica vez e marcado `origem:"backfill_documentos"`.
Precedencia testada: meta real sempre ganha do backfill, porque o backfill mede so os 103
emissores e o `Last-Modified` mede o arquivo inteiro.

**Efeito colateral tratado, `deploy-worker.ps1`.** O passo 5 fazia `Fail` em `ok=false`.
Com o gate novo, todo deploy durante apagao da CVM abortaria com o codigo ja no ar e o repo
declarando a versao velha, que e o drift que esse passo existe para impedir. Agora ele
distingue health degradado por falha do deploy de health degradado por fonte externa. Provado
na saida real do v4.9.202: `AVISO: ok=false causado SOMENTE por cvm_fonte_ok=false. Fonte CVM
parada ha 3 dias uteis. Prosseguindo com o commit.`

**Efeito colateral tratado, `canonical-test.yml`.** A mensagem de erro nomeava
`admin_email_ok`, `sentry_ok` e `verificador_ok`, todos true, mandando quem investigasse
procurar secret quebrado. Agora le `cvm_fonte_ok`, `cvm_fonte_idade_du` e `cvm_fonte_motivo`,
nomeia o fator caido e, quando ele e o unico, manda conferir o `Last-Modified` do
`ipe_cia_aberta` antes de mexer em codigo. Guarda extra: se o campo sumir do health, o run
falha, o que pega tanto remocao do gate quanto deploy regredido.

`frescor-check.yml` foi conferido e NAO quebra: ele chama `admin_health_check`, que roda
`executarHealthCheckDiario` com `ok` proprio, independente do `_okHealth`.

**Prova em producao (v4.9.202, 2026-08-19T12:07:37Z):**
```
{"ok":false,"versao":"v4.9.202","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},
"admin_email_ok":true,"sentry_ok":true,"verificador_ok":true,"cvm_fonte_ok":false,
"cvm_fonte_idade_du":3,"cvm_fonte_motivo":"fonte_parada_ha_3_dias_uteis"}
```
```
cvm:fonte_meta = {"ok":true,"max_data_entrega":"2026-08-15","documentos":715,"origem":"backfill_documentos"}
```
`ok:false` aqui e o comportamento pretendido, nao regressao. A fonte esta parada de verdade,
e agora o sistema diz isso em vez de fingir saude.

**Guardas:** `api/test/cvm-frescor.test.mjs` (12 casos, CI verde, 35 testes no total) e
`scripts/test-frescor-cvm.mjs` (31 casos, roda local porque o Smart App Control bloqueia
`workerd` nesta maquina). Os dois exercitam codigo extraido do `worker.js` real, nunca copia.
Endpoints novos `admin_sync_cvm_auto` e `admin_frescor_cvm`, porque ate aqui nao havia como
rodar nem auditar o `syncCVMAutomatico` fora dos dois crons.

### As tres P1/P2 — RESOLVIDAS e em producao (Worker v4.9.203, frontend v202.12)

**Achado de investigacao, antes de listar as correcoes.** A busca das rotinas NAO
esta quebrada. Amostra do noturno de 18/08 mostra achado real, variado, com data
e numero (Engie Fitch elevou IDR em 10/08, Energisa vendeu 5 transmissoras em
12/08, Auren prejuizo R$ 379,1mi no 2T26), e classificacao com distribuicao
normal entre os dias (3-6 CRITICO, 16-26 RELEVANTE). O problema real: o pipeline
responde "qual o evento mais MATERIAL da janela de 30 dias", nao "o que mudou
desde ontem". Para a maioria dos emissores isso e o resultado do 2T26,
divulgado 12-14/08, entao o modelo reporta a mesma coisa corretamente todo dia
ate aparecer algo maior, e a dedup do Worker colapsa as repeticoes no feed. A
CVM parada tirou a unica fonte que traria fato novo com data nova; as duas
causas juntas produziram o congelamento. Item 5 (materialidade vs delta) fica
registrado como mudanca de produto, nao aplicado, ver abaixo.

**EVENTOFRESCOR1, health diario mede idade do evento (P1).** Novo
`checks.evento_mais_novo` em `executarHealthCheckDiario`: data do evento mais
recente entre os 103 emissores, idade em dias uteis, total de eventos, veredicto
`fresco`. Mesmo limite de 2 du da fonte CVM. Reusa `_cvmDiasUteisApos` em vez de
reimplementar calendario.

**`frescor-check.yml` gateia o campo novo (P1).** O Action so validava
`updated_at` (hora da GRAVACAO) e `empresas_com_dados`, os dois ficam verdes com
conteudo reciclado porque a rotina escreve todo dia. Foi por isso que ele passou
verde a semana inteira do incidente. Agora aborta se `idade_du > limite_du`, com
mensagem mandando conferir `cvm_fonte_ok` do health publico antes de cacar bug,
porque quando os dois estao vermelhos a causa e a mesma.

Validacao sem credencial: simulado localmente em node contra o formato real de
resposta (`scratchpad/simula-frescor.mjs`), 4 casos incluindo o caso real do
incidente (escritor fresco, evento de 3 du) abortando como esperado. O
`workflow_dispatch` manual falhou por `ADMIN_PASSWORD` vazio no disparo via
`gh workflow run`, mas o secret existe no repo desde 13/08 (`gh secret list`) e
o `schedule` de hoje 02h42 UTC ja tinha rodado verde com ele antes deste fix.
Anomalia pontual do disparo manual, nao do secret nem do codigo; nao investigada
a fundo por ser tangencial. Confirmar no proximo `schedule` (diario 01:37 UTC).

**FONTESFAKE1, tira de 7 fontes removida (P1).** Era HTML estatico com
`class="status-item ok"` fixa, cada id (`st-cvm`, `st-anbima`, `st-b3`,
`st-fitch`, `st-sp`, `st-moodys`, `st-austin`) aparecia uma unica vez no arquivo
inteiro, nenhum codigo lia ou escrevia em runtime. Nao virou dinamica: das 7 o
sistema so tem sinal real de 2 (CVM via `cvm_fonte_ok`, ANBIMA via heartbeat
`sync_anbima` com `data_arquivo`), as outras 5 nao tem integracao monitorada.
Duas reais ao lado de cinco decorativas continuaria enganando. Confirmado ao
vivo via DOM: `status-left` com 0 filhos, `getElementById("st-cvm")` retorna
null em producao.

**CARIMBOFAKE1, "Atualizado em" mostra idade do dado (P2).** Era
`new Date().toLocaleDateString(...)`, relogio do navegador, nunca podia ficar
velho por definicao. Nova funcao `_vixCarimboDeDados` calcula local no
frontend (sem round-trip ao Worker) a data do `data_evento` mais recente em
`resultados` e a idade em dias uteis: "Evento mais recente 14 de agosto de 2026
(3 dias uteis atras)". Sem dado carregado (home publica), so declara a janela,
nao inventa carimbo — confirmado ao vivo, `dash-data` mostra so
`"Janela: 30 dias"` na home sem sessao.

**Efeito colateral tratado: GATE 3.4 achou drift de `?v=` em 4 camadas.**
Bump do `CACHE_VERSION` para v202.12 exigiu alinhar nao so o
`admin-bootstrap.js` (memoria conhecida, DEDUP1 ja tinha esse padrao) mas
tambem os 3 submodulos que ele reexporta (`engajamento.js`, `metricas.js`,
`modules.js` importam `shared.js` com querystring propria). Corrigido em
commit separado depois que o gate reprovou pela segunda vez, varredura final
cobriu TODO `app/`, nao so os arquivos que o gate apontou.

**Prova em producao:**
```
{"ok":false,"versao":"v4.9.203",...,"cvm_fonte_ok":false,"cvm_fonte_idade_du":3,
"cvm_fonte_motivo":"fonte_parada_ha_3_dias_uteis"}
```
```
version.json = {"version":"v202.12","deployed_at":"2026-08-19T12:36:04Z"}
DOM: status-left innerHTML="" children=0 stCvmExiste=false
DOM (home, sem sessao): dash-data.textContent="Janela: 30 dias"
```

### Ainda aberto

| Sev | Item | Nota |
|---|---|---|
| Decisao de produto | Materialidade vs delta: o feed hoje mostra "evento mais material da janela de 30d", nao "o que mudou desde ontem". E a causa de fundo do congelamento, junto com o apagao da CVM. Separar as duas perguntas no prompt das rotinas e mudanca de produto, nao bug — nao aplicado sem decisao do operador | Ver secao acima |
| Investigacao, maior esforco | Dependencia do arquivo batch `ipe_cia_aberta_2026.zip` da CVM, que provou atrasar 3 dias. Portal RAD e superfice em tempo real, caminho alternativo nao investigado | Abrir como item separado |
| P3 | `heartbeat:cascade_analise` nao existe no KV, e o `stale_count:1` do watchdog | Investigar se o agente foi renomeado ou morreu |

### Lacuna honesta
Nao foi provado que houve evento de credito material em 17 ou 18/08 que o sistema perdeu. A busca
web nao devolveu nada datado desses dias. O que esta medido e que **nenhum evento posterior a 14/08
entrou no estado**. Nao ha evidencia de que o WebSearch das rotinas esteja quebrado.

### Estrutura de pastas, resolvido na mesma sessao
- Junction legada `E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito` **removida**. Preflight
  confirmou 0 tarefas agendadas, 0 worktrees e `lint-legacy-path.ps1` com 70/70 OK antes de mexer.
  Alvo validado depois, 44923 arquivos e 1799312500 bytes identicos ao baseline, HEAD `fa191b5`
  preservado, working tree limpo. `FREQUENTE\` continua intacta com os outros 13 projetos.
- As 5 skills `vix-radar-*` estavam duplicadas: stubs de 250 a 325 bytes em
  `C:\Users\User\.claude\skills\` apenas apontando texto para o conteudo real em
  `E:\Diretorio\Claude\.claude\skills\`. Isso quebrou de verdade nesta sessao, o
  `audit-ui-metrics.mjs` falhou com `MODULE_NOT_FOUND` na primeira chamada porque o diretorio-base
  anunciado era o do stub. Stubs trocados por junctions apontando para o conteudo real.

---

## 19/08 (01h35-03h10 BRT) — RESOLVIDO: painel de eventos parado em 14/08 + historico de EWS achatado

Usuario reportou o Painel de Eventos em vixradar.com mostrando 14/08 como a data mais recente do
feed cronologico, apesar do cabecalho "atualizado em 19 de agosto" e da janela de 7 dias uteis
(11-19/08) exibindo 38 relevantes / 7 criticos / 24 emissores com sinal. Investigacao (01h35)
achou a causa provavel do feed sem prova direta e, de passagem, um segundo problema no bloco
preditivo (hist_len sempre 1). Sessao de fix (/caveman, 02h30-03h10) provou, corrigiu, testou e
deployou os dois. Hierarquia de verdade aplicada: producao (version.json + comportamento real)
antes de Obsidian: as duas hipoteses do achado inicial precisaram de correcao a luz da prova, ver
secoes "correcao sobre o achado inicial" abaixo de cada bug.

### Confirmado — infraestrutura saudavel agora
Portao de verificacao: `ok:true kv:true telemetria:true sentry_ok:true verificador_ok:true`, v4.9.198.

### Confirmado — 3 falhas de cobertura entre 13 e 16/08, nenhuma documentada antes desta sessao
- **13/08 (quinta), blackout total.** Nenhum log de matinal nem de noturno existe para essa data
  em `logs/routines/`. Nao e log malformado, e ausencia completa, a rotina nao deixou rastro.
- **14/08 (sexta), matinal ausente.** O noturno de 14/08 rodou completo (log com conteudo real,
  CRITICO em Oncoclinicas/Oi/Raizen, `DEFERIDOS=13 FALHA=0 TOTAL=13`), mas nao ha log de matinal
  nesse dia, apesar de ser dia util com agendamento 10h BRT.
- **16/08 (sabado), noturno morreu no meio.** `vixradar-noturno_20260816.log` tem 1,3KB contra
  6-17KB dos demais dias: processou 15 de 103 emissores (LOTE R3), parou em "Aguardando R4 R5 R6
  R7" sem escrever `FIM:`, e deixou `vixradar-noturno_20260816.lock` sem limpar. A linha `HEALTH`
  no inicio do log ja mostrava `verificador_ok=false`, consistente com o modo de falha conhecido
  da fila de verificacao (SLA de 12h). 88 de 103 emissores ficaram sem qualquer analise no dia.

Nos dias entre essas falhas (15/08, 17/08, 18/08) o noturno rodou 103/103 com saida substantiva,
nao vazia, entao o pipeline nao ficou morto o periodo inteiro.

### DESCARTADO — cache do navegador
Usuario reabriu em aba anonima (sessao limpa, login refeito) e o feed continua parando em 14/08.
Nao e cache stale nem estado de sessao.

### DESCARTADO — rotina parada como causa
As rotinas de 15, 17 e 18/08 rodaram e submeteram com sucesso. A matinal de 18/08 fechou
`FIM: matinal 20/20 processados. CRITICO=2 RELEVANTE=13 ECO=5 ... submits_falhos=0`, com
`OK|Oi|FULL|CRITICO|1|true`, `OK|Oncoclinicas|FULL|RELEVANTE|1|true`, `OK|CSN|LIGHT|CRITICO|1|true`
entre outros. O noturno de 18/08 fechou `Total do dia 103/103`. Ou seja, o pipeline entregou
conteudo nesses dias e mesmo assim nada disso aparece no feed.

### CONFIRMADO — evento novo existe no dado depois de 14/08
Comparacao dos snapshots diarios de `data/historico/*/predictive.json` (gravados pela rotina de
export, 20h45) entre 14/08 e 18/08: 37 emissores mudaram `event_count`, sendo 20 com aumento —
Pao de Acucar (GPA) 10->13, CSN 11->14, Hapvida 2->5, Eneva 6->9, Dasa 4->6, JBS 4->6, CEMIG 1->2,
entre outros. Soma total de eventos 245 -> 254. O contador tem janela rolante (alguns cairam), mas
aumento so acontece com evento entrando. Logo, ha evento posterior a 14/08 gravado no estado.

Corroboracao externa: o Term Sheet das novas debentures do GPA foi aprovado por credores em
13/08 e o resultado 2T26 da Oncoclinicas saiu em 14/08 (prejuizo de R$ 475,7 mi), consistente com
o aumento de `event_count` desses dois nomes. Braskem, que teve rating cortado para RD pela Fitch
nessa janela, **nao** e emissor monitorado (zero ocorrencias em `api/src/worker.js`), entao nao
conta como perda de cobertura.

### P0-1 RESOLVIDO — DEDUP1, dedup semantica do frontend colapsava saga continua

**Correcao sobre o achado das 01h35:** a hipotese original ("qualquer titulo parecido dentro de
45 dias colide") era forte demais. Teste executavel com a funcao real extraida do arquivo (nao
reescrita, ver `scripts/test-dedup-eventos.mjs`) mostrou que manchetes de capitulo novo de uma
mesma saga normalmente NAO colidem, so 2 de 6 casos construidos colidiam de fato: republicacao
identica (esperado, dedup correta) e uma nota de analista template repetida verbatim, ou um par
onde a UNICA diferenca era a palavra "nova" (que a normalizacao removia por design). O mecanismo
real e mais estreito que o suspeitado, mas real: qualquer atualizacao cuja unica marca textual de
novidade seja "novo/nova", ou cuja redacao de analista se repita quase verbatim (comum neste
sistema, ver `ANOTA_rapida` nos logs de rotina), colide e o evento novo e descartado.

`_isDupSemantico`/`_normTituloDedup` (`app/index.html`, bloco minificado do `<head>`) tratavam
como duplicata qualquer titulo normalizado igual dentro de 45 dias, e a normalizacao removia
`novo|nova|novos|novas` (sinal temporal) alem de truncar em 70 caracteres.

**Fix (commits `60234fa`, `d818780`, `ae57327`, `32fcdb6`):**
- `novo/nova/novos/novas` nao e mais removido da normalizacao.
- Truncamento de 70 caracteres eliminado (compara string normalizada inteira).
- Identidade de duplicata agora prioriza `fonte_primaria` (URL sem query) quando disponivel;
  senao exige MESMO `data_evento` (dia exato, nao mais janela de 45 dias) + titulo normalizado
  igual.
- `_v201Coletar` ordena por `data_evento` desc antes de dedupar: numa colisao real, sobrevive o
  evento mais novo, nao o primeiro que chegou.
- `CACHE_VERSION` v202.10->v202.11, e as 15 referencias `?v=202.10` em `app/js/admin-bootstrap.js`
  + 3 submodulos alinhadas (pego pelo GATE 3.4 do proprio `deploy-pages.ps1`, nao verificado a
  mao).

**Teste:** `scripts/test-dedup-eventos.mjs` (nao ha suite para `app/`, script standalone que
extrai a funcao DIRETO do `index.html` real, nunca copia solta). 8 casos + ordenacao, verde:
republicacao real / mesma fonte / intradia matinal+noturno continuam deduplicando; capitulo de
saga, comunicado com "nova", rating novo, restatement em dia diferente, empresas distintas
passam a sobreviver.

**Prova em producao (v202.11, 2026-08-19T06:04:51Z):** `curl vixradar.com/` contem literalmente
o `_isDupSemantico` novo, `CACHE_VERSION="v202.11"` ao vivo, `admin-bootstrap.js` servindo
`shared.js?v=202.11`. Prova do dado real do usuario (evento que ANTES sumia agora aparecendo no
feed autenticado) nao foi possivel nesta sessao: exige sessao logada do usuario, que este agente
nao tem e nao deve simular. Se quiser fechar 100%, `JSON.stringify(resultados)` no console do
painel logado confirma.

### P0-2 RESOLVIDO — HISTFLAT1+2, historico de EWS nunca acumulava

Nos 8 snapshots de `data/historico/*/predictive.json` (11 a 18/08), `hist_len` era **1 para os
103 emissores, todos os dias**, zerando `velocity_delta`, `direction` (`sem_historico`) e
`confianca_nivel` (`muito_baixa`) no universo inteiro. Duas causas independentes, achadas em
sequencia porque a primeira sozinha nao resolveu (prova em producao pos-deploy 1 ainda mostrava
hist_len=1, o que forcou a segunda rodada de diagnostico):

**HISTFLAT1** (`api/src/worker.js:13804` `executarPipelinePreditivo`): a LEITURA de
`ews:hist:{empresa}` ficava atras do mesmo gate `persistHist` que decide se um ponto NOVO e
gravado. O unico caller com `opts` (`admin_executar_predictive`, usado por
`scripts/smoke-preditivo-lab.ps1`) chama com `skip_hist_persist:true`, entao pulava a leitura
inteira: historico tratado como vazio SO NESSA CHAMADA. Esse payload achatado ia para
`predictive_v1:latest`, a MESMA chave que os crons matinal/noturno (`scheduled()`, sem opts)
escrevem 2x/dia com ponto real, entao uma chamada admin/smoke depois do ultimo cron do dia
sobrescrevia o snapshot correto. Fix: leitura roda sempre, so `persistirHistEwsBatch` (escrita de
ponto novo) continua condicionada a `persistHist` (commit `297841e`, deploy v4.9.199).

**HISTFLAT2**, achada pela prova em producao do fix acima (hist_len continuava 1 apos o deploy):
`kvEwsHistKey` (`worker.js:13539`) grava a chave com `empresa.toLowerCase().trim()`. `histMap` e
populado decodificando essa mesma chave (fica minusculo), mas era lido com `histMap[empresa]`
usando o case original de `EMISSORES_LISTA` (ex. "Oncoclínicas", com maiuscula). Miss de lookup
silencioso: `histRaw` sempre `[]`, em QUALQUER chamador, inclusive os crons que sempre leram
(HISTFLAT1 nunca afetava esse caminho). Esta era a causa real por tras dos 8 dias observados, o
HISTFLAT1 era necessario mas nao suficiente. A escrita nunca teve esse bug, ela normaliza
internamente. Fix: lookup usa a mesma normalizacao da escrita (commit `53f2930`, deploy v4.9.200).

**Teste:** `api/test/predictive-hist.test.mjs`, integracao via `SELF.fetch`/`env` (CI, Miniflare
bloqueado localmente pelo Smart App Control) + formula pura de acumulacao validada em Node puro
(dia N->1, N+1->2, N+2->3, reprocessar N+2 continua 3 sem duplicar, dia anterior intacto,
ordenacao cronologica, gap de um dia nao apaga serie). A primeira versao do teste seedava a chave
`ews:hist:` com o case ORIGINAL da empresa (nao com `kvEwsHistKey` real) e por isso teria passado
mesmo com o HISTFLAT2 presente, mascarando o bug — corrigido para seedar exatamente como o codigo
real grava antes de confiar nele.

**Prova em producao (v4.9.200):** `smoke-preditivo-lab.ps1 -ExpectWorker v4.9.200` -> `SMOKE
PASSED` (7/7). Consulta direta pos-deploy: `hist_len` uniforme **2** para os 103 emissores
(antes: uniforme 1), `direction` `sem_historico` -> `estavel`. O "2" (nao um numero maior) reflete
que so ha 1 ponto real persistido ate agora (a serie so volta a crescer daqui pra frente, dia a
dia, com os proximos crons; nao existe historico retroativo para reconstruir com seguranca, entao
nenhum foi inventado).

### Achado menor — export ainda grava pelo caminho legado
`vixradar-export_20260818_204501.log` fecha com `3 arquivos em E:\Diretorio\Claude\FREQUENTE\
Monitoramento de Credito\data\historico\2026-08-18`, o caminho da junction legado. Nao quebra
porque a junction resolve, mas e sobrevivente da migracao de 18/08 e o `lint-legacy-path.ps1` nao
pegou, provavelmente por ser string montada em runtime e nao literal no `.ps1`.

## 19/08 (00h20 BRT) — auditoria de retries, watchdogs e monitoramento

Escopo fechado: só retry/watchdog/monitor. Produção como fonte de verdade (Task Scheduler ao vivo,
event log `Microsoft-Windows-TaskScheduler/Operational`, logs reais, execução real dos scripts).

### FATO NOVO — o event log do Task Scheduler está HABILITADO

`Get-WinEvent -ListLog` retorna `IsEnabled:True`, 16.676 registros. O `03 - Estado Atual.md`
(bloco de 27/07) afirma o contrário, que o log estava `IsEnabled=False` e que por isso a
investigação de quem removeu tasks entre 23 e 24/07 estava "encerrada por impossibilidade, não
por conclusão". Essa premissa não vale mais. Não reabri o caso de julho (fora do escopo desta
auditoria), mas fica registrado que hoje **é apurável** por evento 141.

### RESOLVIDO — causa exata do `Szuchmacher-RetryVixMatinal` recusado em 18/08 16:23

Não foi falha de execução nem do script. Evidência direta, evento **153** às 16:23:38: "o
Agendador não iniciou a tarefa porque não tinha sua agenda". Cadeia completa, toda medida:
a máquina desligou 18/08 03:42:14 (evento 13) e só voltou 16:14:33 (evento 12); o gatilho do
watchdog é 13h30 seg-sex, com a máquina desligada; a task **não** tem `StartWhenAvailable`,
então o agendador recusou o disparo atrasado e gravou `0x800710E0` (ERROR_REQUEST_REFUSED).
Não houve evento 201 para ela nesse dia, confirmando que nunca executou.

**Impacto real: zero.** A janela das 10h da matinal também caiu com a máquina desligada, e a
matinal só rodou às 16h34 (catch-up da própria sessão agendada do Claude Desktop, 20 min depois
do retry recusado), entregando 20/20 às 16h50. E mesmo se o watchdog tivesse rodado às 13h30,
não faria nada: sem log do dia ele sai por `SEM LOG ... fora do alcance deste watchdog`.

`monitor-tasks.ps1` classificar isso como erro **está correto**, não é ruído: em dia útil, um
watchdog que não disparou merece olhar. Ele pediu investigação, a investigação foi feita, a causa
é externa e benigna. Nada a corrigir aqui.

### Limitação conhecida (não é bug, decisão do usuário) — cobertura do watchdog com máquina desligada

Dia de máquina desligada na janela inteira não tem cobertura de watchdog nenhuma, por dois
motivos somados: (1) sem `StartWhenAvailable`, o disparo atrasado é recusado; (2) o próprio
script declara `SEM LOG → fora do alcance deste watchdog` quando a rotina nunca começou. Ligar
`StartWhenAvailable` **não** teria mudado o 18/08 (cairia em SEM LOG do mesmo jeito). Quem cobre
esse cenário hoje é o catch-up da sessão do Claude Desktop, que foi o que de fato salvou o dia.
Mudança não aplicada de propósito, não havia bug e a correção não resolveria o cenário.

### RESOLVIDO — parser de `FIM:` da matinal, 4o formato não reconhecido (causa raiz fechada)

Teste controlado aplicando o parser real contra os 14 logs reais de matinal/noturno disponíveis
achou 3 que produziriam retry falso. Dois são a P2 já aberta (11/08 e 14/08, noturno completo sem
escrever `FIM:`). O terceiro é novo: matinal 15/08 escreveu `FIM: 19 emissores processados`, sem
denominador, e nenhum dos 4 padrões casava.

Causa raiz: assimetria entre as duas skills. Depois do incidente de 17/08 o `SKILL.md` do noturno
passou a **exigir** o formato exato da linha `FIM:`; o da matinal nunca ganhou essa exigência.
Resultado, três formatos em quatro dias (`19/19 emissores processados`, `20/20 processados`,
`19 emissores processados`). Corrigir só o regex seria perseguir sintoma.

Correção: Passo 12 do `SKILL.md` da matinal agora exige `FIM: matinal <N>/<TOTAL> processados.`,
igual ao Passo 11 do noturno, nas duas cópias (versionada e viva fora do repo). Guarda: o
denominador virou opcional no 3o padrão do cascade, em `retry-vixradar.ps1` e `monitor-tasks.ps1`,
cobrindo log já escrito e drift futuro.

Teste real, ponta a ponta, com o script de produção: log de teste com a forma exata do 15/08 →
`OK: log do dia tem FIM valido, entrega feita`, exit 0 (antes daria retry falso). Controle
negativo com contador 3, abaixo do mínimo 12 → não entrou no ramo de entregue, caiu na guarda de
frescor. Log de teste removido. Regressão: `monitor-tasks.ps1` segue lendo noturno 103 e matinal
20 de 18/08.

### RESOLVIDO 19/08 (00h30 BRT) — P2 `monitor-tasks.ps1` não detectava rotina completa sem linha `FIM:`

Fallback por contagem de nome único implementado nos dois arquivos que leem o mesmo sinal
(`monitor-tasks.ps1` e `retry-vixradar.ps1`), não só no primeiro. Faltar nos dois teria deixado
o monitor avisar corretamente enquanto o retry ainda relançava a rotina inteira à toa, exatamente
o incidente caro de 17/08 se repetindo por outro caminho.

Calibragem: conferido contra os 14 logs reais de matinal/noturno disponíveis em 19/08, em todo
log onde o contador do `FIM:` parseava, ele batia exatamente com a contagem de nome único
(19=19, 103=103, 20=20). O fallback mede a mesma coisa por uma evidência mais confiável, o ledger
`OK|` é escrito por emissor logo após cada submit confirmado, não depende do modelo lembrar de
fechar o log.

Dia resgatado pelo fallback não vira `OK` mudo no `monitor-tasks.ps1`: vira aviso (novo código
`9003`), porque a linha `FIM:` ausente continua sendo defeito real de alguma execução, mesmo com
o dia entregue.

Testado com o script de produção real via cópia com `$VixRoot` redirecionado para sandbox (não
mock, o mesmo código, só a raiz trocada): 3 cenários no `monitor-tasks.ps1` (sem `FIM:` e ledger
suficiente → aviso 9003 dia OK; sem `FIM:` e ledger insuficiente → 9001 erro real; `FIM:` presente
sem contador reconhecível e ledger suficiente → aviso 9003). E 2 controles no
`retry-vixradar.ps1` com log real (não sandbox, arquivo de teste criado e removido em seguida):
positivo, 103 no ledger sem `FIM:` → não relança, exit 0; negativo, 15 no ledger (mínimo 90) → não
confirma entrega, não sai pelo ramo de sucesso. Regressão contra os logs reais de 18/08
(`FIM:` presente e válido nos dois): resultado idêntico ao de antes da mudança, `submit_ok=103`
noturno e `20` matinal, fallback nem é exercitado.

---

## 18/08 (23h50 BRT) — auditoria geral (skill vix-radar-general-audit, pos-FASE 2)

Auditoria readonly focada no que mudou apos as notas 85/86 e a inversao da junction (mesma
noite). Escopo: drift de codigo/rotina de hoje, veracidade da UI (script obrigatorio), governanca
de artefatos. Nao re-derivou seguranca/frontend/perf/a11y (sem mudanca desde a nota 85 desta
manha, confirmado por `git log --since` em `app/`). Detalhe completo pedido ao agente na sessao;
resumo dos achados novos abaixo.

### RESOLVIDO 19/08 (00h10 BRT) — P1 migracao da junction nos scripts e SKILL.md

Inventario refeito por busca direta (nao so o achado da auditoria): 24 `.ps1` + 2 `SKILL.md`
versionados (`matinal`, `noturno`) + os mesmos 2 `SKILL.md` vivos fora do repo em
`C:\Users\User\.claude\scheduled-tasks\vixradar-{matinal,noturno}\` (achado novo, nao estava no
inventario original, e o SKILL.md que a sessao agendada do Claude Desktop realmente le).
`register-all-routines-scheduler.ps1` e `monitor-tasks.ps1` tinham linhas adicionais com
`FREQUENTE\relatorio-diario-szuchmacher\...` e `FREQUENTE\Morning Call\...`, de outros projetos,
deixadas intocadas de proposito. `gen-dashboard.ps1` (root, gitignorado, fora do repo) corrigido
tambem, script local sem rastreamento git. Frase do `noturno/SKILL.md:109` que mandava "usar
sempre o caminho FREQUENTE" reescrita nos dois lugares (versionado e vivo) para citar o caminho
antigo sem soletra-lo por extenso (evita falso-positivo no lint novo).

Teste real, nao so parse: `lint-encoding.ps1` 66/66 OK. `monitor-tasks.ps1` executado ao vivo,
achou os logs de 18/08 no caminho canonico e leu `submit_ok=103` (noturno) e `submit_ok=20`
(matinal) corretamente, prova que o `$VixRoot` corrigido resolve de verdade. `retry-vixradar.ps1`
executado ao vivo para as duas rotinas, resolveu o caminho do log do dia 19/08 corretamente (log
ainda nao existe, rotina de hoje nao comecou, comportamento esperado). Achado incidental do teste,
sem relacao com este fix: `Szuchmacher-RetryVixMatinal` foi recusado pelo Task Scheduler
(`ERROR_REQUEST_REFUSED`) as 18/08 16:23, dia util, mas a matinal completou normal no horario
certo, sem impacto real. Nao investigado a fundo, fora do escopo deste item.

Guarda nova: `scripts/lint-legacy-path.ps1`, Gate 5 do pre-commit (`scripts/hooks/pre-commit`,
hooks reinstalados com `install-hooks.ps1 -Force`), reprova qualquer `.ps1` ou `SKILL.md` de
`routines/claude-desktop/*/` que reintroduza o caminho legado, com `$Allowlist` explicita para
excecao documentada. So cobre o repo, nao os `SKILL.md` vivos fora dele, limitacao conhecida e
registrada no proprio script. `references/audit-matrix.md` da skill de auditoria ganhou secao
"Watchdogs locais de rotina" cobrindo o padrao.

Junction NAO removida nesta rodada, como pedido: continua existindo, so passa a nao ter mais
nenhum consumidor operacional conhecido puxando por ela.

---

### P1 (fechado acima) — Migracao da junction (18/08 a noite) nao alcancou 26 scripts nem 2 SKILL.md das rotinas

A inversao da junction (`status/ESTADO.md`, 18/08 noite) reapontou a Action das 12 tarefas do
Task Scheduler para o caminho fisico canonico `E:\Diretorio\Claude\Monitoramento de Credito`, e
fechou dizendo "nenhuma tarefa, worktree ou metadado do git depende mais" do `FREQUENTE`. Isso e
verdade so para Action/worktree/git. Por dentro, 26 arquivos `.ps1` (incluindo
`run_claude_routine.ps1`, todos os `run_vixradar_*.ps1`, todos os `register-*-task.ps1` e o
proprio `monitor-tasks.ps1`) continuam com `$ProjectRoot`/`$VixRoot` hardcoded no caminho
`FREQUENTE\Monitoramento de Credito`. Nao quebra hoje porque a junction ainda existe e resolve, mas
e exatamente o cenario que a doc de fechamento convida alguem a criar (achar que nada depende mais
dela e remover). Se isso acontecer, praticamente toda a camada operacional cai ao mesmo tempo,
incluindo os watchdogs que deveriam acusar a falha.

Agravante: `routines/claude-desktop/noturno/SKILL.md:109` instrui ativamente o sentido errado hoje
("o caminho antigo `E:\Diretorio\Claude\Monitoramento de Credito` ainda funciona por junction, mas
e fragil - usar sempre o caminho FREQUENTE") — verdade antes da inversao de hoje, invertido agora.
`matinal/SKILL.md` tem a mesma referencia ao caminho FREQUENTE. `verificacao-async/SKILL.md` (FASE
1, referencia de qualidade) nao tem esse problema.

CLAUDE.md e README.md (raiz do projeto) nao mencionam FREQUENTE, o problema fica contido na camada
de scripts/rotina, nao vazou para a documentacao mais lida.

**Correcao:** atualizar os 26 `$ProjectRoot`/`$VixRoot` para o caminho canonico e reescrever a
linha 109 de `noturno/SKILL.md` (e a equivalente em `matinal/SKILL.md`) para parar de recomendar
FREQUENTE. Nao aplicado nesta auditoria (readonly, mudanca abrange a camada operacional inteira,
decisao de quando/como fica com o usuario).
**Causa raiz:** a migracao teve um passo para Action de tarefa e um para worktree/git, mas nenhum
passo varreu o conteudo interno dos scripts nem os SKILL.md pela mesma string de caminho — uma
quarta superficie que ninguem cobriu porque a junction mascarava o sintoma.
**Guarda sistemica proposta:** check automatizado (candidato a pre-flight ou lint, molde de
`lint-encoding.ps1`) que reprova qualquer `.ps1` versionado ou `SKILL.md` de rotina Claude Desktop
com `FREQUENTE\Monitoramento de Credito` hardcoded fora de allowlist explicita. Nao implementado
ainda, proposta registrada aqui e no `references/audit-matrix.md` da skill de auditoria.

### P3 — Saida de dry-run do Ranking-Mensal (descontinuado) ficou untracked sem padrao de .gitignore

`Obsidian VIX Radar/SEO/Ranking SEO 2026-08 (dryrun).md` e `scripts/seo/ranking_state.dryrun.json`
(ambos gerados 18/08 22h22, claramente durante a propria investigacao que decidiu descontinuar
`VIXRadar-Ranking-Mensal`) sao untracked. O projeto ja tem o padrao para isso (`data/reconciliacao/
dryrun/`, `data/historico/.dryrun/` no `.gitignore`), so nao foi generalizado para este caminho —
primeira vez que esta rotina roda em modo dry-run. Como o script fica em quarentena (nao apagado),
qualquer novo teste manual repete o ruido. **Correcao:** adicionar `scripts/seo/*.dryrun.json` e
o padrao equivalente em `Obsidian VIX Radar/SEO/*(dryrun)*.md` ao `.gitignore`, ou apagar os dois
arquivos (zero valor operacional, decisao de descontinuar ja documentada em local com evidencia
melhor). Nao aplicado nesta auditoria, fica para o usuario escolher.

### Confirmado (sem achado novo) — subsistemas de hoje

`CHAVEESCOPO1` (`REMOTE_VERIFICACAO_KEY` existe como secret vivo em producao, confirmado via
`wrangler secret list`, escopo restrito as 3 acoes de verificacao confirmado por leitura direta do
codigo), `CONCORVERIF1` (reserva atomica, fail-open documentado e correto) e `HEARTBEATVERIF1`
(agente `verificacao_async` no watchdog, limite 16h) auditados por leitura de diff + evidencia de
producao em `status/ESTADO.md`. Nenhum binding novo em `wrangler.toml` hoje. `references/
audit-matrix.md` da skill `vix-radar-general-audit` (revisao anterior 27/07, defasada) atualizado
com os 3 subsistemas + secao nova "Watchdogs locais de rotina" cobrindo o par
`retry-vixradar.ps1`/`monitor-tasks.ps1` e o risco de regex de `FIM:` divergente entre os dois
(mesma causa do retry falso de 17/08, ja corrigido, commit `ad06ad4`). Script obrigatorio de
veracidade de UI (`audit-ui-metrics.mjs`) rodado: exit 0, 0 bloqueante, 3 termos reservados
conferidos manualmente contra o glossario, todos batendo.

---

## 18/08 — execução: rotação da routine_key + envelope + limpeza (detalhe: [[86 - Rotacao routine_key e envelope noturno 2026-08-18]])

### RESOLVIDO 18/08 — P1 rotação da routine_key

Chave rotacionada nos 3 destinos (GitHub Actions criado, Worker, env User). Validação: 200 com a nova, 403 com inválida. Guarda nova ROTA1: os 3 scripts de rotina hidratam a chave do registro User sempre, processo longevo não manda mais chave morta. O secret nunca existiu no GitHub (C2 confirmado com evidência: repo tinha só ADMIN_PASSWORD), portão do script ajustado para criar.

### RESOLVIDO 18/08 — P2 envelope da noturna (recalibração, sem deploy)

Estimativa do envelope recalibrada para o custo medido (9,5k/emissor na rápida) na skill viva e na cópia versionada. Regra dura anti-replay de subagente adicionada (o vazamento de 142k do 17/08). Efeito real será medido no noturno de 18/08.

### RESOLVIDO 18/08 — P3 graphify-out versionado

`graphify-out/` no .gitignore + `git rm -r --cached`. Working tree sem o ruído da ferramenta.

### RESOLVIDO 18/08 — Pre-flight: 4 scripts vivos com P0

gen-dashboard (BOM), cf-token-status e build-worker (Stop→Continue + exit), collect_cotacoes (Stop→Continue, roda no Task Scheduler).

### RESOLVIDO 18/08 — Drift das skills do Desktop

Noturno e matinal sincronizadas da viva para a versionada. Verificacao-async em dia.

### P2 — ANTHROPIC_API_KEY continua ausente no GitHub Actions

O scan-emergencia usa `secrets.ANTHROPIC_API_KEY` no passo que faz a varredura real, e esse secret também não existe no repo. ROUTINE_API_KEY foi criada na rotação, mas o fallback de emergência segue morto de fato: morreria no primeiro fetch de LLM exatamente no dia em que precisasse rodar. Decidir: criar o secret com a chave paga local, ou remover o passo LLM do workflow.

### P3 — ~20 scripts de ferramenta com ErrorActionPreference Stop

register-*, deploy-pages, lint-encoding, check-drift, check-vault-drift, dry-run, verify-rotinas-v2, atualizar_altman_cvm, seed_labels, install-hooks, skills-audit, push-health, criar-token-dns, unificar-cf-token, apply-security-rotation, disable-vixradar-noturno-task, register-coleta/export/monitor/ranking/reconciliacao, run_vixradar_ranking_mensal, fix_task_coleta_volatilidade, skills-verify-tokens. Nenhum roda no Task Scheduler (os que rodam foram corrigidos: collect_cotacoes, matinal, noturno, verificacao). Correção em lote com parse PS 5.1 de cada um, sessão dedicada.

### P4 — Worktrees órfãos de outras ferramentas poluem o pre-flight recursivo

`git worktree list` mostra 1 do Codex (C:\Users\User\.codex\worktrees), 5 do Traycer e 4 do Claude no caminho antigo (E:\Diretorio\Claude\Monitoramento de Credito\.claude\worktrees, que agora é junction para FREQUENTE). Os .ps1 dessas cópias entram no scan recursivo do pre-flight e geram P0 fantasma. Remover os sem mudança (`git worktree remove`) ou excluir paths de worktrees do scan.

### P4 — check-desktop-orquestrador-drift.ps1 não alertou o drift das skills

O drift noturno (19,4k vs 15,6k bytes) e o da matinal estavam lá há dias sem alerta. Rever por que o check não pegou (agendamento? comparação por hash errado?).

### RESOLVIDO nesta sessão de auditoria — Merton DD 0/103 (ver [[85 - Auditoria Geral e Preditiva 2026-08-18]])

Não resolvido na execução, permanece P2 com o plano de correção descrito na nota 85. Listado aqui para não se perder entre os blocos.

---

## 18/08 — auditoria geral + preditiva (readonly, detalhe: [[85 - Auditoria Geral e Preditiva 2026-08-18]])

### P2 — Merton DD nunca roda em producao (0/103 emissores)

`predictive_v1:latest` (run 17/08): `merton_dd` null em todos os emissores, driver `merton` nunca aparece. Causa: `market_cap` vazio no Altman e na volatilidade (nenhuma coleta preenche; o gate do codigo exige `market_cap > 0` de proposito). Codigo do modelo correto, Fase A de dados incompleta. Correcao: coletar market cap (cotacao x n. de acoes) ou declarar Merton em stand-by. Guarda: contador `com_merton` no payload do pipeline.

### P3 — graphify-out versionado sem .gitignore

Cache de tooling gerando 14 entradas de ruido no working tree a cada execucao. Adicionar `graphify-out/` ao .gitignore.

### P3 — email do admin hardcoded no frontend (app/index.html:4079)

Revelacao do item "Painel Admin" no cmdk por comparacao literal com o email. O JWT ja carrega `role:admin`; trocar a comparacao pelo role.

### P3 — divs clicaveis sem role/tabindex no Market Overview

mo-table-row e mo-heatmap-row nao sao alcancaveis por teclado. Adicionar role="button" + tabindex + handler de teclado, ou trocar por `<button>`.

### P3 — card "Sem alertas" sem declaracao de janela no proprio card

O indicador tem janela fixa de 30 dias ao lado do toggle 7D/30D do grafico; o glossario manda declarar. Trocar o sub para "X de Y emissores · 30 dias".

---

## 17/08 — sessão de custo/benefício e limpeza de fila (sem deploy)

### RESOLVIDO 17/08 — P2 express/openai órfãos no package.json (C3)

Zero import ou require de `express`/`openai` em todo o `api/`. Removidos com `npm uninstall`, `api/package.json` fica só com `@sentry/cloudflare` em dependencies. `npm ci` revalidado, árvore com os 3 pacotes esperados. Efeito só na próxima publicação, nada em produção mudou.

### RESOLVIDO 17/08 — P2 ~25 .ps1 sem commit, 12 reprovados no lint

Pendência estava vencida. `lint-encoding.ps1` varreu 63 arquivos, 63 OK, 0 risco, e o working tree não tem `.ps1` modificado. Foi fechado pelo commit `9764a3d` (18 arquivos regravados com BOM) e ficou aberto na fila por falta de reconciliação.

### RESOLVIDO 17/08 — P3 listar_plano_rotina devolveu 19 para top_n=15

Não é bug. `selecionarEmissoresPrioritarios` corta em `topN` e depois o mínimo por setor do v4.9.157 (`api/src/worker.js:8953`) adiciona emissores dos setores sem cobertura, senão setor com EWS perto de zero nunca entra no top-N. Na matinal de 15/08 isso somou 4. Contrato descreve `top_n` como se fosse teto, e ele é piso. Corrigir a redação do contrato, não o código.

### RESOLVIDO 17/08 — FIMRUN21, alerta 9001 falso do monitor desde 13/08

`monitor-tasks.ps1` lia só a última linha `FIM:` do log da rotina. O noturno de 15/08 escreveu duas, run-1 com `FIM: noturno 103/103 processados` e run-2 com `FIM: noturno run-2 11/11 emissores DEFERRED ... Total do dia 103/103 com analise real`. A segunda não casava com nenhum padrão de contador, `submit_ok` caía para -1 e disparava 9001 mesmo com o dia entregue inteiro. Vermelho crônico desde 13/08 escondendo sinal verdadeiro. Fix varre todas as linhas `FIM:` do dia e fica com o maior contador, mais padrão novo para `Total do dia N/M`. Validado contra o log real de 15/08, resultado `submitOk=103`, sem alerta.

### RESOLVIDO 17/08 — Portão de verificação saía verde com o sistema doente

A task do VS Code chamava `curl.exe -s` direto, que sai com código 0 mesmo quando o health responde `ok:false`. Novo `scripts/portao-verificacao.ps1` parseia o JSON e sai com 1 se qualquer flag obrigatória não vier `true`, cobrindo os 4 do CLAUDE.md mais `rate_limiter`, `admin_email_ok` e `verificador_ok`. Achado durante o próprio teste: `kv` e `telemetria` moram dentro de `bindings`, não na raiz, a primeira versão reprovava um health saudável. Portão virou build task padrão, Ctrl+Shift+B. `.vscode/tasks.json` ganhou verificar rotinas local e live, monitor de tasks, lint de encoding e drift do vault, que eram o braço do agendador faltando.

### P2 — Envelope da noturna, agora é a alavanca única de custo

Com plano Max a rotina local é flat, trocar modelo dela economiza zero. Dólar real só aparece quando a assinatura estoura o limite semanal e a execução cai na chave paga `VIXRADAR_ANTHROPIC_API_KEY`. O cap de 700k estourando toda noite (~70% acima do desenho) é o que consome a folga semanal. Recalibrar o envelope ou fixar modelo da fila rápida deixa de ser afinação e vira o item de maior retorno da fila inteira.

### P2 — ROUTINE_API_KEY do scan-emergencia continua não validada

Workflow verde nas 4 últimas noites (última 16/08 23:45), mas o log mostra só a checagem de idade do estado (`Idade do estado: 2h`) e saída pelo caminho no-op. A chave nunca é exercitada, então o verde não prova nada. Falharia exatamente no dia em que o fallback precisasse rodar. Validar por `workflow_dispatch` forçado ou junto da rotação.

---

## Abertas (15/08 — auditoria geral profunda)

Detalhe: [[83 - Auditoria Geral 2026-08-15]]. Plano completo: `C:\Users\User\.claude\plans\graceful-soaring-hopper.md`.

### RESOLVIDO 15/08 — Deploy v4.9.195 + v202.10 (correções locais da auditoria)

Worker v4.9.195 e frontend v202.10 no ar e validados em produção (commits `f4b8780`..`5175a97`). Health verde com todos os sub-checks, providers com perplexity "removido" e nivel normal, drift zerado, CI Worker Tests verde no push. Fecha OPENROUTER-ORFAO1 (alerta falso desde 30/07) e LLMXSS1 em produção.

### P1 — Rotação da routine_key (bloqueio de PAT pode ter caído em 17/08, não testado)

Chave redigida em 15/08 de `~/.claude/scheduled-tasks/gen_workflow.py` + `vixradar-noturno-v2.js` (com backup), mas cópias históricas em backups/transcripts seguem existindo e a chave não foi rotacionada. `rotate-routine-key.ps1` cobre os 3 destinos (Worker secret, GitHub Actions secret, env User da máquina). Bloqueava porque o `GH_TOKEN` ativo era um PAT fine-grained sem permissão de Secrets. Em 17/08, resolvendo um bloqueio parecido no `git push` (ver item abaixo), achamos que existe uma credencial OAuth já autenticada no keyring do Windows com escopo `repo` clássico, que inclui gerenciar secret de repositório, e que `GH_TOKEN` (mesmo vazio) segue tendo prioridade sobre ela. Não tentamos rodar `rotate-routine-key.ps1` ainda com esse keyring ativo, mas é candidato forte a destravar sem precisar mexer em PAT nenhum. Ao concluir, reiniciar o Claude Desktop antes da noturno 18:00 para a sessão absorver o env novo.

### RESOLVIDO 17/08 — P1 push de 3 commits bloqueado por credencial (regressão do incidente já documentado em 13/08)

`git push` reprovava com 403, PAT fine-grained sem escopo Contents. Ajustar a permissão do token pelo GitHub não bastou, e no meio da correção o usuário rodou `[Environment]::SetEnvironmentVariable('GH_TOKEN', ...)` duas vezes com erro, primeiro gravando o placeholder literal `cole-o-token-aqui`, depois esvaziando a variável, e colou o valor completo de um token fine-grained em texto puro no chat ao tentar corrigir. Achado real: a trava nunca foi permissão, `GH_TOKEN`, mesmo quebrado, tinha prioridade sobre uma credencial OAuth já autenticada e guardada no keyring do Windows (escopo `repo`, `read:org`, `gist`, `workflow`), suprimindo ela. Limpar `GH_TOKEN` (`$null` em escopo User) destravou o push na hora, sem gerar token novo. Os 3 commits (`960b56c`, `ed40757`, `2fc9216`) estão em `origin/main`, working tree limpo, `0 0` de diferença.

### P3 — Token fine-grained "Token name" exposto em texto puro no chat

Durante a correção acima, o valor completo desse token (o mesmo que teve a permissão Contents ajustada para Read/write) foi colado no chat pelo usuário. Não está mais em uso, `GH_TOKEN` foi removido e o push passou a usar o keyring, mas o valor ficou exposto no histórico da conversa. Regenerar ou apagar esse token específico por higiene quando for conveniente, sem urgência operacional.

### P2 — monitor-tasks.ps1 não detecta rotina completa sem linha FIM:

Achado na medição de cobertura de 17/08 (ver `03 - Estado Atual.md`, callout 05h10): 08/11 e 08/14 fecharam 103 de 103 emissores sem nunca escrever `FIM:` no log, um caminho de conclusão legítimo que o FIMRUN21 não cobre. Hoje isso cai em "sem linha FIM, execução não chegou ao fim" mesmo com o trabalho completo. Fix recomendado, ainda não implementado: quando não achar `FIM:`, `monitor-tasks.ps1` fazer fallback pra a mesma contagem por nome único de emissor usada na medição manual, antes de declarar 9001. Código puro, sem custo de token.

### P3 — routines/README.md descreve top_n como teto, e ele é piso

Achado junto do item RESOLVIDO do `top_n=15` devolvendo 19 (ver acima). O comportamento está correto, `selecionarEmissoresPrioritarios` garante mínimo por setor depois do corte. A correção pendente é só de redação em `routines/README.md`, ainda não editada.

### P2 — Orçamento da noturna (A1)

Cap de 700k estoura toda noite (~70% acima do desenho). Recalibrar envelope ou fixar modelo da fila rápida. A recuperação mecânica do defer (P1-2) foi RESOLVIDA nesta meta (DEFERREDREC1 com persistência real do flag nos 5 ramos).

### P2 — Validar ROUTINE_API_KEY do scan-emergencia no GitHub (C2)

Chave possivelmente morta desde 03/08; se morta, o fallback de emergência falha exatamente quando deveria rodar. Coberto junto da rotação.

### P2 — express/openai do package.json (C3)

Remover dependências não usadas no próximo ciclo de deploy.

### P3 — listar_plano_rotina devolveu 19 emissores para top_n=15 solicitado (matinal 15/08)

Plano da matinal de 15/08 trouxe `total=19` em vez dos 15 esperados pelo contrato (0 SKIP, 10 LIGHT, 9 FULL, 0 AUDIT). Rotina prosseguiu processando os 19 sem erro. Verificar se `top_n` está sendo respeitado na composição do plano no Worker, ou se a contagem por tier ignora o limite quando não há SKIP suficiente para completar a diferença. Detalhe: [[84 - Rotina Matinal 2026-08-15]].

### RESOLVIDO nesta meta (aguardando deploy): P1 matinal sem alarme, P1 governança do orquestrador, P2 REGDRIFT1, P2 timeouts de cron, P2 falso-verde CI

ROTINAGAP1 no watch-vixradar-health (alerta por rotina faltante com dedup por nome), 7 arquivos do Claude Desktop versionados em `routines/claude-desktop/` + `check-desktop-orquestrador-drift.ps1`, guarda dura nos 2 registradores legados + Disabled reproduzido no register-all, AbortSignal.timeout nos 6 fetches de cron, canonical-test fail-closed no rate_limiter.

---

## Abertas (13/08 — auditoria geral + execução)

### P0 — PARCIALMENTE RESOLVIDO: cascade de IA (AUTHWEEK1). Assinatura no limite semanal, chave paga recarregada

**Estado:** OAuth 429 "weekly limit, resets Aug 15, 8am" segue valendo para a assinatura. Chave paga `VIXRADAR_ANTHROPIC_API_KEY` **recarregada pelo operador 13/08 15h12** e validada (sonda exit 0). Dreno de 13/08 15h16-15h27 rodou por pay-per-token (11 eventos, 9 aprovados, 2 rejeitados, 223k tokens), health voltou a `ok:true`. Rotinas funcionam via chave paga até o reset de 15/08 08h BRT.

**Causa raiz:** três drenos de verificação em 12/08 (~2M tokens) + noturno completo estouraram o limite semanal da assinatura. A pendência de 04/08 ("recarregar crédito da chave paga") ficou 9 dias aberta.

**Guarda proposta:** notificação quando a sonda detectar 429 de limite semanal (a sonda já detecta, falta notificar).

### P1 — RESOLVIDO: secret ADMIN_PASSWORD do GitHub Actions (GHWL1)

**Estado:** gh reautenticado via OAuth (escopos repo/read:org/gist) após autorização do operador no device flow. Secret `ADMIN_PASSWORD` atualizado no GitHub Actions com a credencial recuperada do DPAPI local. Validação: run manual do frescor-check. Guarda nova: `scripts/check-gh-actions-health.ps1` (commit `f82872d`) + aviso reforçado no `apply-security-rotation.ps1`.

### P1 — RESOLVIDO: push bloqueado por credencial

**Estado:** origem era o token fine-grained sem Contents write (403). OAuth novo resolveu. Merge do `cbda7d1` (sessão paralela) feito, conflito do PENDENCIAS resolvido mantendo as duas visões. Push completo após este commit.

### P1 — FECHADO: BOM UTF-8 nos scripts

35 .ps1 varridos, 18 regravados com BOM byte a byte, parse PS 5.1 64/64 OK. Commit `9764a3d`. Pre-flight confirmou 0 EM DASH sem BOM nos scripts vivos.

### P2 — FECHADO e DEPLOYADO: XSS Market Overview (frontend + worker)

Frontend v202.8 no ar (escape nos 4 pontos do módulo v100). Worker **v4.9.193 no ar** com strip de HTML em `titulo`/`empresa` no `sanitizarPayloadRadar`. Deploy validado: `ok=true kv=true telemetria=true sentry_ok=true`, versão viva v4.9.193.

### Solicitações de acesso

1 nova solicitação 13/08 15h12 (WhatsApp admin enviado 1s depois, sem erro de email), já aprovada. KV: 34 usuários, 0 pendentes.

Detalhe completo: [[81 - Auditoria Geral e incidentes 2026-08-13]].

---

## Abertas (13/08 — pos v4.9.192 / CALVAL-V2, sessão paralela)

### Status geral

Reconciliado nesta sessao (checkout estava ~40 commits atras, atualizado via `git pull`). Todo o bloco anterior (04/08 a 11/08, ver "Fechadas — bloco 04-11/08" abaixo) esta **RESOLVIDO**. Rastreamento de pendencias havia migrado informalmente para notas de auditoria avulsas (77, 79, 80) sem consolidacao central; este bloco reconsolida os 6 itens reais em aberto hoje.

### P2 — ~25 scripts `.ps1` de rotina modificados sem commit, 12 reprovados pelo lint-staged

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. Paths FREQUENTE + BOM alterados na sessao de 11/08 — sintaxe PS 6/7 em scripts que rodam sob PS 5.1 e BOM removido. Fora do escopo do CALVAL-V2, precisa sessao dedicada.

### P2 — canonical-test.yml: fix do post-mortem 77 nunca implementado

**Origem:** post-mortem 77 (05/08, verificador_ok). Correcao proposta para o workflow ficou em backlog aberto (item Jarvis), nao entrou no repo.

### P2 — Fila de verificacao >20h no fechamento do deploy CALVAL-V2 (12/08 23:33Z) — validar

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. 5 itens enfileirados 11/08 23:33Z cruzaram o SLA de 20h (VERIFSLA1) as 19:33Z de 12/08, derrubando `verificador_ok` no fechamento do deploy. Backlog pre-existente da fila (teto de token), sem relacao com CALVAL. O dreno async de 13/08 10:20 BRT deveria ter zerado — **nao confirmado em log ainda**. Conferir.

### P3 — CLOUDFLARE_API_TOKEN sem permissao Pages:Edit

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. Deploy de Pages caiu para OAuth do wrangler (aviso do proprio `deploy-pages.ps1`). Adicionar a permissao Cloudflare Pages: Edit ao token.

### P3 — Rotina agenda-semanal rodando 1x/semana, regra pede 2x

**Origem:** [[80 - CALVAL-V2 validacao agenda resultados 2026-08-12]]. Regra 9 do CALVAL-V2 exige revalidacao 2x/semana (Dom+Qua) para cumprir plenamente. Aumentar frequencia da task local.

### P3 — postAdmin sem Authorization: Bearer

**Origem:** [[79 - Incidente ADMINRL-FIX1 429 painel admin 2026-08-12]]. Backlog registrado, ainda nao implementado.

---

## Fechadas (14/08 — execução das pendências da auditoria)

Worker v4.9.194 e frontend v202.9 no ar, commits `f8bcf7c`..`08e2557` pushed.

### RESOLVIDO — P0 AUTHWEEK1: guarda de notificação implementada

Novo `action=notificar_rotina` no Worker (auth routine_key, email ao admin via Resend) + `Send-VixRoutineAlert` na lib `vixradar-claude-auth.ps1`, chamado nos 3 pontos de abort por auth (matinal, noturno, verificacao-async) e validado no `Assert-VixLibFunctions`. Probe em producao: 403 com chave invalida, fail-closed confirmado. O reset da assinatura (15/08 08h) segue como evento externo; a partir de agora qualquer estouro de limite semanal notifica o admin na hora.

### RESOLVIDO — P2 canonical-test.yml: fix ja estava implementado

A pendencia estava errada. `canonical-test.yml:58-60` ja le `admin_email_ok`/`sentry_ok`/`verificador_ok` individuais (commits `15feb31` e `870b29f`) e as linhas 111-117 nomeiam o fator que caiu. Nada a implementar, item fechado por evidencia.

### RESOLVIDO — P3 agenda-semanal 2x/semana (CALVAL-V2 regra 9)

Task `VIXRadar-AgendaSemanal` atualizada no Scheduler: de Monday para Sunday+Wednesday 22h00 (DaysOfWeek=9), proximo disparo 16/08. `register-all-routines-scheduler.ps1` atualizado junto para a re-registracao nao reverter.

### RESOLVIDO — P3 postAdmin sem Authorization: Bearer

`app/admin/vr-admin-shared.js` agora usa `authHeaders()` (Bearer quando ha JWT local) + `admin_senha` no body. Deployado em v202.9.

### RESOLVIDO — P3 "Cobertura ANBIMA" terceiro sentido

Termo "Cobertura ANBIMA" adicionado ao `glossario-dominio.md` como termo qualificado proprio (disponibilidade da serie no arquivo de precos diario ANBIMA para um emissor), com a regra de nunca usar "Cobertura" simples para esse sentido.

### RESOLVIDO — P3 disjuntor de custo catch mudo (CUSTOBRAKE1)

`verificarDisjuntorDiario` agora loga `console.error` quando a leitura do KV falha, em vez de engolir. Deployado em v4.9.194.

### RESOLVIDO — P3 card "Sem alertas" sem denominador

Card do Market Overview agora declara "X de Y emissores". Deployado em v202.9.

### RESOLVIDO — P3 diretorios untracked

`Operacoes-Recorrentes/` (Trading View, repo proprio) movido para `FREQUENTE\Operacoes-Recorrentes\`, posicao de irmao dos projetos. `docs/entrevista-ff/` (material Financial Finesse) movido para `FREQUENTE\Emprego (1)\Finance\entrevista-ff\`. Working tree limpo.

---

## Abertas (14/08 — execução das pendências da auditoria)

### P3 — CLOUDFLARE_API_TOKEN sem Pages:Edit

Verificado em 14/08: token ativo mas `pages/projects` devolve Authentication error. A API do Cloudflare nao cria nem edita permissoes de token existente (dashboard-only). Passo manual: em https://dash.cloudflare.com/profile/api-tokens, criar token novo com "Cloudflare Pages: Edit" (zona/account `7ac79fb1030e4e81115ef33c21a9b070`) e gravar como `CLOUDFLARE_API_TOKEN` no registro User. Enquanto isso o deploy-pages segue funcional pelo fallback OAuth do wrangler (usado no deploy de hoje).

---

## Fechadas — bloco 04-11/08 (P0/P1/P2), RESOLVIDO

**Marcado resolvido em:** 13/08. Todos os itens abaixo foram superados por deploys subsequentes (Worker v4.9.186 -> v4.9.192, frontend v201.9x -> v202.7). Ja constavam RESOLVIDO individualmente no corpo original desta nota; consolidados aqui como historico, sem status ativo.

- **P0 — Verificador async quebrado por call sites orfaos (05/08):** corrigido 06/08, `Assert-VixLibFunctions` no ar.
- **P0 — Guarda ambiental bloqueando verificador async (04/08):** corrigido 06/08.
- **P1 — VERIFSLA1/VERIFSLA2, lookback do health 2 -> 7 dias:** deploy v4.9.190, 11/08.
- **P3 — Senha demo rotacionada:** 11/08.
- **P0 — Painel admin morto em producao desde 03/08 (modulos ES truncados):** deploy publicado 09/08 (v202.6), superado por v202.7.
- **P1 — Worker v4.9.187 (VALIDFIX1) aguardando deploy:** publicado, Worker avancou ate v4.9.192.
- **P0 — Credito zerado API Anthropic, rotinas paradas (04/08):** rotinas normalizadas a partir de 06/08, guardas estruturais no ar.
- **P1 — settings.json DeepSeek causando exit=1 no `claude -p` (27/07):** corrigido, guarda de ambiente permanente.
- **P2 — Probe pre-voo `Invoke-ClaudeBatch`:** 02/08.
- **P3 — Chaves ROUTINE_API_KEY mortas:** 03/08.
- **P1 — Matinal reportava sucesso com buscas falhando:** 02/08, 4 guardas aplicadas.
- **P2 — VIXRadar-Reconciliacao-CVM (bug PS 5.1):** 03/08.
- **P3 — VIXRadar-Coleta-Volatilidade:** 02/08.
- **P2 — VIXRadar-Export-Historico (token KV):** 02/08.
- **P2 — Guard em register-all-routines-scheduler.ps1:** 03/08.
- **P2 — monitor-tasks.ps1 inventava causa de falha:** 02/08.
- **P2 — Probe CLI antes da Noturno 18:00:** 02/08.
- **P3 — SHADOW1 (Fable 5):** 03/08, Sonnet mantido, shadow encerrado.
- **P3 — VIXRadar-Ranking-Mensal:** 03/08, decisao: remover.
- **P2 — Frescor da Ingestao / ADMIN_PASSWORD desatualizado no GitHub (27/07):** 27/07 16h45.
- **P2 — ADMIN_EMAIL ausente 3 dias, so telemetria viu:** 27/07 19h57, 2 guardas aplicadas (SECRETMISS1).
- **P2 — Cadastro de conta existente nao notificava admin:** 03/08.

---

## Fechadas (historico recente)

### P2 - Verificar se AgendaSemanal e Matinal se repetem sem erro apos falha da AgendaSemanal 27/07 03:00

**Fechado em:** 27/07 12:09.
**Descricao:** Confirmado: Matinal 10:00 repetiu o mesmo padrao de falha. Ambas morreram ao invocar `claude -p` com exit=1, log truncado, stderr vazio. Substituido pelo P1 "Investigar e corrigir causa raiz do exit=1".

### P2 - Verificar primeiro disparo da Matinal (27/07 10:00)

**Fechado em:** 27/07 12:09.
**Descricao:** Task disparou as 10:00 conforme previsto. Porem falhou com exit=1 (mesmo padrao da AgendaSemanal). Log `vixradar-matinal_20260727.log` com 8 linhas, truncado em "Lote sonnet-1". 0 emissores processados. Substituido pelo P1 de investigacao de causa raiz.

### Consolidar os dois PENDENCIAS.md

**Fechado em:** 27/07 (commit `76720a7`).
**Descricao:** Opcao A executada. `PENDENCIAS.md` da raiz (31 KB, fila aberta zero, conferido antes de mover) movido via `git mv` para `Obsidian VIX Radar\_Arquivo\PENDENCIAS (historico ate 2026-07-26).md`, com aviso de congelamento no topo. `Obsidian VIX Radar\PENDENCIAS.md` (este arquivo) passou a ser o canonico rastreado no git. `README.md` e `PROMPTS-RADAR.md` corrigidos, a linha 5 deste ultimo dizia que o arquivo da raiz vencia o Obsidian em conflito, isso teria virado instrucao falsa se nao corrigido.

### Monitor-Tasks — Registrador criado, task recriada e primeiro disparo validado

**Fechado em:** 27/07 07:04.
**Descricao:** `scripts\register-monitor-tasks.ps1` criado e executado. Task Ready no Scheduler, trigger diario 07:00. Primeiro disparo real confirmado: rodou 27/07 07:00:00, exit=7, `logs\monitor-tasks\monitor_20260727.log` (1863 bytes) e `erros_20260727.json` (4344 bytes) gerados. Exit 7 nao e falha do vigia, e a contagem de 7 tasks de terceiros (Szuchmacher-*, nao VIX Radar) com LastTaskResult nao-benigno que ele escaneou e reportou corretamente, exatamente a funcao para a qual foi recriado. Escaneou 12 tasks no total, 3 OK, 7 erros, 2 warnings (incluindo o achado novo da AgendaSemanal, ver P2 acima). `Get-ScheduledTaskInfo` confirma proxima execucao 28/07 07:00:00.

### SHADOW1 — Implementacao do piloto shadow mode Fable 5

**Fechado em:** 26/07.
**Descricao:** `Invoke-FableShadow` implementado em `scripts/run_vixradar_verificacao_async.ps1`. Primeira execucao real em 26/07 pos-noturno. Encerrado 03/08 (ver bloco acima) — Sonnet mantido.

### LOGLOCK1-REC — Lock de arquivos de log pelo OneDrive

**Fechado em:** 24/07.
**Descricao:** `FILE_ATTRIBUTE_PINNED` em 6177 itens do OneDrive causava falha de escrita nos logs. Resolvido com remocao do flag + `NOT_CONTENT_INDEXED` em `logs/` + fallback file por PID.

### DOCBILL1 — Criterio de evidencia para troca de modelo

**Status:** Encerrado 03/08. Shadow Fable 5 avaliado (8 comparacoes, 0 falso-negativo do Sonnet capturado) — criterio nao atingido, Sonnet mantido como modelo primario.

---

*Atualizado em 2026-08-13 (reconciliacao pos-checkout: bloco 04-11/08 fechado, consolidados 6 itens reais em aberto vindos das notas 77/79/80).*

*Anterior: 2026-08-06 02h45 BRT (incidente 04-06/08 encerrado, fila drenada).*

*Anterior: 2026-08-04 12h BRT (auditoria geral: P0 do painel admin e P1 do Worker corrigidos no repo, os dois aguardando deploy).*

*Anterior: 2026-08-03 18h30 BRT (fila ZERADA: 4 P2 + 1 P4 + 2 P3 resolvidos. Shadow encerrado, Sonnet mantido. Ranking-Mensal: remover. Sessao SESSION-CLEANUP1 concluida.)*
