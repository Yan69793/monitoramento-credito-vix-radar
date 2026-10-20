# 129 - VIX Intelligence Evolution, marco 1 (Livro de Propostas) 2026-10-19

Origem: plano de 18/10 elaborado no ChatGPT, nao versionado antes desta nota. Esta nota e o registro canonico do plano e do marco 1. Estado: LOCAL, nao deployado.

## Plano (resumo da especificacao do operador)
Camada permanente de evolucao do VIX Radar sobre a Cloudflare existente (Queues e Workflows como destino). Tres frentes: (1) aprendizado continuo com noticias, dados, historico e acerto/erro; (2) pesquisa externa periodica de emissores, setores, fontes, indicadores; (3) evolucao controlada de EWS, funcionalidades, UX/UI, seguranca, desempenho e custo. Requisitos: memoria persistente e versionada, deduplicacao, idempotencia, isolamento de tenants, limite de IA, protecao contra prompt injection, rastreabilidade, rollback. Descoberta e proposta podem ser automaticas. Inclusao operacional, alteracao critica, codigo e producao exigem validacao e aprovacao humana.

## Marco 1: Livro de Propostas de Evolucao
Menor peca sem duplicar nada existente: a memoria versionada e a trava de aprovacao, antes de qualquer coletor. Sem Queue nem Workflow ainda (exigem binding no wrangler.toml e deploy).
- `api/src/evolucao.mjs` (pura, KV injetado) e ponte `api/evolucao.mjs` para o bundle.
- Actions no Worker: `evolucao_propor` (admin ou routine_key), `evolucao_listar` e `evolucao_decidir` (so admin).
- KV `evolucao:{tenant}:p:{id}`. id = sha256(tipo|alvo|titulo normalizado), idempotente. Historico append-only, versao incremental, `reverter` devolve a decisao a `proposta`.
- Guardas: fonte https obrigatoria, tenant validado contra DEFAULT_TENANTS e isolado na chave, texto sanitizado, padrao de injecao marcado e aprovavel so com `ciente_suspeita`, teto de 50 propostas de IA por dia por tenant, teto de 200 pendentes, motivo obrigatorio na decisao. Nada executa: aprovar so autoriza planejar.
- Testes: `api/test/evolucao.test.mjs` (10, duas pontas). Suite completa 62 arquivos, 632/632.

## Proximos marcos (nao iniciados)
2. Coletor de erros e acertos: ler historico de EWS, verificacoes reprovadas e filas e gerar propostas `ews`/`indicador` (so propostas).
3. Descoberta externa periodica (emissor, fonte, setor) com Queue + Workflow, exige binding e autorizacao de deploy.
4. Painel admin para revisar o livro.

## Marco 2: coletor de erros (EVOLUCAO2, 2026-10-20). Estado: commitado local, SEM deploy
- `derivarPropostasDeErros` (pura, em `api/src/evolucao.mjs`) le os registros `radar:verif:attempt:*` e propoe so quando 3 ou mais itens DISTINTOS esgotaram as 3 tentativas de verificacao: uma proposta por fonte (host do id do item) e uma por emissor. Titulo sem contagem, entao o mesmo erro recorrente cai na mesma proposta.
- Action `evolucao_coletar` (admin ou routine_key). Padrao e simulacao, so devolve o que seria proposto. Com `aplicar:true` grava apenas no livro, origem `rotina`, estado `proposta`. Nao toca fila, estado, evento nem tentativa.
- Testes: `api/test/evolucao-coleta.test.mjs` (8). Suite completa 63 arquivos, 640/640.
- Fonte de erro ainda coberta: so verificacao esgotada. Acertos e erros do EWS (conferencia ews2) ficam para o marco 2b.

## Marco 2b: aprender com acertos e erros do EWS 2.0 (EVOLUCAO2B, 2026-10-20). Estado: commitado local, envio DESLIGADO
- Caminho decidido: o computador local deriva e manda so a proposta pronta; os arquivos da conferencia nao sobem. Sem deploy (usa `evolucao_propor`, ja em producao).
- `scripts/predictive/ews2/propor_evolucao.py` (puro, sem rede) le o relatorio da conferencia. Regra omissao: evento independente em emissor que o EWS 2.0 marcava `baixa`. Regra ranking: 3+ eventos com diferenca e EWS atual melhor na maioria. Sem link https oficial da CVM, nao ha proposta. A conferencia passou a carregar os links dos documentos do dia do evento (`links`).
- `run_vixradar_ews2_pacote.ps1` chama a derivacao depois da conferencia. Envio so com `VIXRADAR_EVOLUCAO_ENVIAR=1` (env User) E `-Publicar`; fora disso e simulacao e so loga `EVOLUCAO_PROPOSTA`. Falha aqui nunca muda o exit da rotina nem a flag do EWS.
- Testes: `test_propor_evolucao.py` 9/9, `test_conferencia.py` 24/24 (sem regressao), `scripts/test-evolucao-ews2.ps1` 8/8 no PowerShell 5.1 (duas pontas, com duble de rede, chave fora do log). Proposta derivada aceita pelo `normalizarProposta` do Worker. Lint de encoding OK.
- Para ligar o envio, depois de ver a primeira simulacao no log: `[Environment]::SetEnvironmentVariable('VIXRADAR_EVOLUCAO_ENVIAR','1','User')`.

- 20/10/2026: envio LIGADO por decisao do operador, sem esperar a primeira simulacao. `VIXRADAR_EVOLUCAO_ENVIAR=1` no escopo User, medido. Primeira execucao com envio: VIXRADAR-EWS2-Pacote em 26/10/2026 23:15. Desligar: apagar a variavel (`[Environment]::SetEnvironmentVariable('VIXRADAR_EVOLUCAO_ENVIAR',$null,'User')`).
