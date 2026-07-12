# 49 - Avaliação Claude Fable 5 + Guards de Refusal no Verificador (2026-07-10)

Sessão: avaliação de encaixe do modelo `claude-fable-5` no VIX Radar, testes comparativos reais contra o verificador adversarial, pesquisa de riscos operacionais e implementação de guards preventivos em `scripts/run_vixradar_verificacao_async.ps1`. Nenhum deploy; nenhuma escrita em produção; `$ModelVerificador` permanece `claude-sonnet-4-6`.

## Perfil do modelo (fontes oficiais Anthropic, lidas 2026-07-10)

- `claude-fable-5`: modelo mais capaz em disponibilidade geral (classe Mythos), lançado 2026-06-09. Não é modelo de "narrativa" — o nome engana.
- Maior pontuação de qualquer modelo no benchmark financeiro da Hebbia (raciocínio sobre documentos, gráficos, tabelas). Vantagem sobre Opus 4.8 cresce com tamanho/complexidade da tarefa.
- Contexto 1M tokens, saída até 128k, adaptive thinking sempre ligado (`--effort` controla profundidade; low/medium/high/xhigh/max — confirmado no `claude -p --help` local).
- Preço API: USD 10/M entrada, USD 50/M saída (2x Opus 4.8).
- Retenção de dados obrigatória de 30 dias (Covered Model) — incompatível com contas ZDR. Conta desta operação NÃO tem ZDR (prova empírica: os testes rodaram e retornaram resultado).
- Classificadores de segurança podem recusar com `stop_reason:"refusal"` (HTTP 200, não erro). Categorias: `cyber`, `bio`, `frontier_llm`, `reasoning_extraction`. Histórico: modelo foi suspenso em 12/06 (jailbreak descoberto por pesquisadores da Amazon — geração de código de exploit), reabilitado com classificador retreinado (>99% de bloqueio da técnica, redirect para Opus 4.8). Anthropic admite que o classificador novo flagga requisições benignas com mais frequência.
- Fallback: API tem parâmetro `fallbacks` (beta, header `server-side-fallback-2026-06-01`) e SDK middleware. CLI local tem `--fallback-model`, descrito no help como fallback para "overloaded or not available" — NÃO confirmado se cobre refusal de classificador. Lacuna aberta.

## Testes comparativos (2 rodadas, 2026-07-10)

Metodologia: prompt real do verificador (`buildVerifierSystemPrompt` de `api/v4.9.149.js:9695` + user prompt no formato de produção), evento sintético, `claude -p` com as mesmas flags de produção exceto `--permission-mode auto` (produção usa `bypassPermissions` — divergência declarada; classificador de auto-mode bloqueou corretamente o bypass em sessão interativa). Fila real estava vazia (`total_fila=0` nas duas checagens) — não havia evento real para reaproveitar.

### Rodada 1 — evento fake autodeclarado (empresa "Ficticia Participacoes Testeira S.A.", com avisos "EVENTO FABRICADO" no texto)

| | Fable 5 (`--effort high`) | Sonnet 4.6 (baseline produção) |
|---|---|---|
| Veredicto | REPROVADO conf 0.0 (correto) | REPROVADO conf 0.0 (correto) |
| Buscou web | Sim (2 buscas via executor Haiku interno) | NÃO (0 buscas — reprovou pelo texto) |
| Duração | 31,3s | 7,0s |
| Custo real | USD 0,424 | USD 0,098 |

### Rodada 2 — evento ambíguo sem autodenúncia ("Trovao Manguezal Participacoes S.A.", comunicado de atraso de juros plausível, fonte `.invalid`)

| | Fable 5 (`--effort high`) | Sonnet 4.6 (baseline) |
|---|---|---|
| Veredicto | REPROVADO conf 0.0 (correto; citou ausência em CVM/ANBIMA/B3 + TLD `.invalid`) | REPROVADO conf 0.0 (correto; idem, mais verboso) |
| Buscou web | Sim (2) | Sim (3) |
| Duração | 27,4s | 42,1s |
| Custo real | USD 0,381 | USD 0,165 |

Custo total dos testes: ~USD 1,07 (cobrado na chave API do registro).

### Interpretação

- O "Sonnet pula busca" da rodada 1 era artefato do evento autodenunciado — na rodada 2 (caso justo) Sonnet buscou 3x e fundamentou bem. Sem evidência de relaxamento do Sonnet em evento real.
- Fable não encontrou nada que Sonnet perdeu. Custo 2,3x-4,3x maior por chamada, sem ganho de qualidade demonstrado.
- Nenhum refusal disparou em nenhum teste — evento de crédito privado BR não caiu em nenhuma categoria de classificador (n=2, amostra pequena).
- Formato de saída de ambos (``` ```json [...] ``` ```) compatível com `Get-BalancedJson`/`Get-VeredictosArray` sem ajuste.
- Limitação central da metodologia: ambos os casos eram "deve reprovar". O caso decisivo — evento real bem evidenciado que deve ser APROVADO — não foi testado. Fable rígido demais reprovando evento real seria erro pior que o que se tentaria resolver.

## Decisão: NÃO trocar o modelo do verificador

`$ModelVerificador` permanece `claude-sonnet-4-6`. Critério de reversão (o que mudaria a decisão):
1. Teste com eventos CRITICO reais da fila em que Fable pegue erro que Sonnet deixou passar; ou
2. Caso real de falso-positivo/falso-negativo do Sonnet em produção documentado.

Sem isso, troca = custo 2-4x sem prova de ganho + exposição a modelo com histórico de suspensão recente e refusals imprevisíveis em pipeline não supervisionado.

## Guards implementados em `run_vixradar_verificacao_async.ps1` (sem troca de modelo)

1. **Detecção de refusal**: `Invoke-ClaudeBatch` extrai `stop_reason`/`stop_details` do envelope JSON do CLI. Refusal → log `AVISO` com categoria/explicação (se presentes), contagem de eventos do lote, rawout salvo em `verifasync_rawout_refusal_*.txt` (evidência mesmo se `stop_details` vier ausente — campo nunca observado no envelope do CLI, leitura defensiva), item fica na fila, script CONTINUA para o próximo lote (refusal é por conteúdo, não por sessão — diferente de auth-failure que aborta tudo).
2. **Exit code 8** novo: refusal sem erro de parse. Precedência: parse (6) > refusal (8). Consumidores (matinal/noturno invocam o dreno como processo filho) apenas logam o exit — sem branch por código, seguro.
3. **Métrica `refusals`** no JSON de métricas diário (conta lotes recusados, não eventos individuais — contagem de eventos vai no log).
4. **`$ModelFallback`** + `--fallback-model` condicional: flag só entra quando `$ModelVerificador != $ModelFallback` (hoje iguais = flag inerte, zero mudança de comportamento). Ativa sozinha numa troca futura para Fable. Guard de nulidade incluído (função copiada sem a variável no escopo não quebra o `claude -p`).
5. Comentário de topo do script corrigido: com `ANTHROPIC_API_KEY` no registro (User), o dreno roda COBRADO POR TOKEN, não por assinatura/limite semanal — consistente com o incidente das 10h de 10/07 ("Credit balance is too low" na matinal, ver callout no `03`).

Validação: sintaxe `ParseFile` 0 erros; lógica de refusal testada isolada com 3 envelopes sintéticos (com `stop_details`, sem, `end_turn` normal — todos corretos); guard de nulidade testado nos 3 cenários (null=0 args, Fable→Sonnet=2, Sonnet=Sonnet=0). Execução end-to-end do script NÃO rodada (bloqueada corretamente pelo classificador — pipeline real; guards serão exercitados no próximo scheduled run).

## Limitações conhecidas / backlog

- Lote recusado re-tenta a cada run até sair da janela de releitura da fila (3 dias × 2 runs/dia ≈ 6 tentativas idênticas). Com `ChunkSize=4`, um evento problemático segura os outros 3 do lote nesse período. Mitigação futura (só se refusal real ocorrer): re-tentar em chunks de 1 para isolar o evento.
- `--fallback-model` cobre refusal de classificador? Não confirmado. Se um refusal real disparar e o fallback não pegar, o guard novo mostra a causa exata no log.
- Testes usaram `--permission-mode auto`; produção usa `bypassPermissions`. Buscas rodaram nos testes, mas não é réplica exata.

## Achados colaterais (doc drift corrigido nesta sessão)

- `CLAUDE.md` do projeto dizia "Opus matinal (top 15) + Sonnet noturno" — FALSO. Scripts reais: matinal = Haiku 4.5 + Sonnet 4.6 (top 15 por EWS, Sonnet para EWS>=38); noturno = Haiku 4.5 + Sonnet 4.6 (103/103). Nenhum Opus em nenhum script. Corrigido.
- `CLAUDE.md` dizia verificador "via Claude Code (assinatura)" — impreciso hoje: chave API no registro → metered. Corrigido.
- `CLAUDE.md` dizia "matinal em correção separada" (guards de auth) — stale: matinal já corrigida em 08/07 (commits `01c6441`+`447c111`). Corrigido.
- Drenagem da fila tem 3 gatilhos hoje, não 1: cron `20 10,18 * * *` + dreno inline pós-matinal + dreno inline pós-noturno (ambos nos PS1 desde v4.9.150-scripts). Corrigido no CLAUDE.md.
