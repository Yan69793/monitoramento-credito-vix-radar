---
data: 2026-07-28
tipo: auditoria
tags: [vix-radar, auditoria, tecnica-completa, registro-canonico, proveniencia]
status: ativo
---

# Auditoria Tecnica Completa, 2026-07-28

Consolidacao da auditoria tecnica ponta a ponta em cinco relatorios na raiz do repo, com registro canonico de achados por ID, taxonomia de certeza e rubrica P0-P3. Entrega documental pura: nenhum arquivo de codigo alterado, nenhuma mutacao de KV ou producao.

## Entregaveis

| Arquivo (raiz do repo) | Conteudo |
|---|---|
| `00-AUDITORIA-SISTEMA-COMPLETA.md` | Sumario executivo, taxonomia, rubrica, registro canonico (21 entradas), camadas, verificado-e-OK, lacunas |
| `01-MAPA-FLUXO-DADOS.md` | Sete fluxos ponta a ponta, tabela de proveniencia por dado |
| `02-MATRIZ-FONTES-CONFIABILIDADE.md` | Hierarquia de fontes (RI > CVM/B3 > secundarias) e matriz por tipo de dado |
| `03-RELATORIO-CALENDARIO-RESULTADOS.md` | Reconstrucao dos 20 emissores do calendario, casos Petrobras/Bradesco (hoje) e Vale (estimativa vencida) |
| `04-PLANO-CORRECAO-PRIORIZADO.md` | Fila de 18 itens, contencoes, pre-requisitos F0, ADR proposto de migracao de rotinas |

## Veredito em uma linha

Endpoint responde e se autorreporta saudavel (`ok:true`, v4.9.182, 0,75s, o que nao prova entrega, identidade de bundle nem correcao de fluxo) e o sistema esta doente em veracidade: a causa sistemica DATA-001 e o contrato de dados sem proveniencia nem confianca, que deixa rotulo e fonte se descolarem sem acusar. Um P0 ativo.

## O P0

**CAL-002**: as datas 2T26 de Bradesco e Vale no sistema divergem da fonte oficial, e o dashboard exibe as erradas com selo de certeza. RI do Bradesco informa 05/08 apos o fechamento (o sistema mostra 28/07 como AGENDADO, dia que cai dentro do periodo de silencio 22/07 a 05/08 declarado pelo proprio banco). Vale informa 30/07 apos o fechamento (o sistema mostra "Ultima divulgacao 24/07", fato que oficialmente ainda nao ocorreu; o evento de 21/07 era producao e vendas, nao resultado). Petrobras segue explicitamente nao confirmada. Fontes, horarios e saidas no relatorio 03 secao 3. Contencao recomendada no relatorio 04 secao 1, nada executado, correcao de dado e Gate C.

## Achados novos mais fortes (alem do que PENDENCIAS ja rastreava)

- **CAL-001 (P1)**: data estimada por padrao historico vira selo AGENDADO na UI (`app/index.html:4869`) e evento sem ressalva na agenda (`agendaBuildPersistir` descarta `status`/`nota`). E o mecanismo que transformou a extrapolacao errada de CAL-002 em afirmacao com selo de certeza, e que hoje faz o mesmo com as outras 18 estimativas do 2T26.
- **CAL-003 (P2)**: `op=calendario` ignora os overrides de KV que o admin salva, so a agenda le o merge. Correcao de data nao chega ao selo.
- **CAL-004 (P2)**: calendario congelado em 2026-05-09, cobertura 20/103, fontes secundarias, staleness sem consumidor. A checagem de CAL-002 mediu a taxa de erro dessa extrapolacao: 2 de 2 datas testadas estavam erradas.
- **VOL-001 (P2)**: campo `market_cap` do payload de volatilidade carrega preco por acao (o comentario do script admite), e a guarda de consumo `> 100` no Worker aceitaria exatamente os valores errados. Hoje o campo e 100% descartado e o Merton roda com patrimonio liquido contabil.
- **VOL-003 (P2)**: SELIC hardcoded 13,75% sem `as_of`, comprovadamente defasada contra o BCB em 28/07 (meta 14,25% na SGS 432, efetiva 14,15% na SGS 1178), com o proprio bundle contradizendo em "SELIC a 15%". As duas SELICs internas erradas em direcoes opostas. Decisao de produto DEC-001 antes de escolher serie SGS.
- **OPS-002 (P2)**: `run_coleta_volatilidade.ps1` engole falha dos processos filhos e ignora `$LASTEXITCODE`, cobertura ja caiu a 73/103 sem alerta.
- **CI-001/CI-002 (P2)**: secret ausente encerra os workflows de vigilancia com sucesso por design declarado, e o scan de emergencia sai limpo ate com `ok:false` (foi o paraquedas mudo de 24-27/07).

Ja rastreados em [[PENDENCIAS]] e agora com ID: OPS-001 (matinal autodeclarada, P1), OPS-003 (idempotencia), OPS-004 (monitor-tasks), SEC-002 (cadastro existente), SEC-003 (WhatsApp sem StatusCallback). Resolvidos com guarda e registrados: SEC-001 (ADMIN_EMAIL), ENC-001 (encoding/PS 5.1, ver [[70 - Incidente Encoding e Compatibilidade PowerShell 5.1 2026-07-27]]).

## Metodo

Reverificacao integral contra o repo no momento da escrita (comando e saida em cada evidencia do relatorio 00), health ao vivo colado, taxonomia COMPROVADO/CORROBORADO/INFERENCIA/LACUNA por achado, rubrica P0-P3 explicita. Base: SHA `fdae5cb`, worktree com 83 arquivos sujos de outros fluxos, caracterizados e preservados (secao 8 do relatorio 00). Contexto herdado de [[69 - Auditoria Geral 2026-07-27]] marcado como CORROBORADO, nunca promovido a verificacao atual.

## Lacunas desta sessao

KV nao inspecionado (valores reais de overrides, estado, volatilidade). Petrobras sem fonte primaria, nao confirmada. CVM e B3 nao consultadas (o primeiro nivel da hierarquia bastou nos dois casos fechados). Runs do GitHub Actions nao lidas, console Twilio nao acessado, bundle nao lido exaustivamente, acessibilidade e performance de campo nao medidas. Detalhe na secao 7 do relatorio 00.

Nota de metodo que vale guardar: a primeira tentativa no RI do Bradesco usou a pagina generica de calendario de eventos, que e SPA e nao traz o dado no HTML. A pagina da agenda do trimestre (`/informacoes-ao-mercado/agenda-2t26/`) traz a tabela inteira em HTML estatico. "Pagina do RI e ilegivel" era conclusao errada tirada da URL errada.

## Gates

Gate A (redigir estes documentos): executado nesta sessao. Gate B (commit, push, PR): bloqueado, exige autorizacao separada, com staging seletivo por allowlist de 8 caminhos e inspecao de conteudo de `git diff --cached -- "Obsidian VIX Radar/PENDENCIAS.md"`. Gate C (codigo, KV, calendario, producao): bloqueado, plano em `04-PLANO-CORRECAO-PRIORIZADO.md` com pre-requisitos F0.
