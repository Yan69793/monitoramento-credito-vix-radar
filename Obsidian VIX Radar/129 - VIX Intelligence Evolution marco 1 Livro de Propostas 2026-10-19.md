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
