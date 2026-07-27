---
data: 2026-07-26
tipo: pesquisa
tags: [vix-radar, fable-5, ia, llm, otimizacao, compliance]
status: ativo
---

# 68 - Avaliação Claude Fable 5 para Otimização do Sistema (2026-07-26)

Sessão disparada por `/melhorar-e-executar`: examinar o repositório e o site em produção, pesquisar o modelo Claude Fable 5 e identificar oportunidades concretas de otimização, no front e no backend, executando diretamente o que for baixo risco e documentando como proposta o que exigir validação. Nenhum deploy foi feito. Nenhum bundle do Worker (`api/v4.9.*.js`) foi editado, conforme regra do projeto.

## Resumo executivo

Recomendação principal: não trocar nenhum modelo de produção por Claude Fable 5 agora. A decisão de manter Sonnet 4.6 no verificador já foi tomada, testada empiricamente e reafirmada pelo próprio time há 2 dias (item `DOCBILL1`, `PENDENCIAS.md`, 24/07/2026), com critério de reversão explícito e ainda não atingido. Esta sessão não encontrou evidência nova que altere essa conclusão.

O que muda com esta sessão: a premissa da tarefa original (cascade OpenRouter mais Gemini mais Perplexity) está desatualizada. O sistema real, verificado nesta sessão contra o código em produção, usa Claude (Haiku 4.5 e Sonnet 4.6) como único provedor de IA generativa desde a remoção do OpenRouter na v4.9.108. Essa correção de premissa, por si, já muda o que faz sentido pesquisar: a pergunta não é "vale trocar um provedor terceiro por Claude", é "vale usar um Claude mais caro e mais lento em algum ponto específico de um pipeline que já é 100% Claude".

Achado concreto executado nesta sessão: a Política de Privacidade pública ainda cita OpenRouter, Google Gemini e Perplexity como destinatários de dados, o que é factualmente incorreto e é um problema de compliance LGPD (a própria política cita artigos específicos de base legal e direitos do titular). Corrigido o texto em `app/index.html:3396` para citar Anthropic. Correção pronta localmente, aguardando deploy do Pages (ver seção "Executado").

Proposta de maior valor para validação: um piloto em modo sombra (shadow mode, sem bloquear nada em produção) usando Fable 5 como segunda opinião só nos eventos CRITICO que o verificador adversarial rejeita. Isso ataca exatamente o critério de reversão que a nota 49 definiu e que, 16 dias depois, ainda não foi testado (falta de eventos CRITICO reais reprovados para comparar). Detalhe completo na seção de propostas.

## Metodologia e limitações desta sessão

- Examinado: estrutura do repositório (`api/`, `app/`, `scripts/`, `Obsidian VIX Radar/`), o bundle do Worker `api/v4.9.181.js` (confirmado em produção via health check ao final da sessão), `api/wrangler.toml`, `app/index.html`, `PENDENCIAS.md`, e as notas do vault mais relevantes (`03 - Estado Atual`, `00 - Índice`, `03b - Infraestrutura`, `49 - Avaliação Fable 5`, `57 - Addendum IA-LLM`, `67 - Auditoria Geral 2026-07-25`).
- Navegado o site em produção (`https://vixradar.com`) via browser real, incluindo dashboard público, sidebar de 103 emissores, modais de configuração, painel administrativo (estrutura, sem autenticar), e o painel "Otimização de Prompts (ADR-029)" visível no admin.
- Bloqueio de ferramenta: `WebSearch`, `WebFetch` e o subagente `Explore` falharam consistentemente nesta sessão com o mesmo erro ("There's an issue with the selected model (deepseek-v4-flash)"), incluindo depois de fixar o modelo explicitamente como `sonnet` na chamada do agente. Isso significa que não foi possível fazer pesquisa externa nova sobre Claude Fable 5 (blog da Anthropic, notícias, benchmarks de terceiros) nesta sessão. Isso é uma limitação real, não uma omissão. A análise abaixo se apoia em duas fontes que considero mais confiáveis que uma varredura genérica de web teria sido: (a) conhecimento de skill já carregado nesta sessão (`claude-api`, dados com cache de 2026-06-24) e (b) a pesquisa e o teste empírico que o próprio time já fez internamente em 2026-07-10 e reafirmou em 2026-07-24, testando exatamente o prompt de produção. Se o usuário quiser a varredura externa, ela precisa rodar numa sessão em que essas ferramentas funcionem (reportar o erro de configuração de modelo do workspace, ele já afeta pelo menos três ferramentas distintas).
- Não fiz login no site (não tenho nem devo pedir credenciais); a inspeção do dashboard autenticado foi via leitura de código (`handleBriefingExecutivo`, `montarBriefingInterno`) e não via navegação logada.

## Arquitetura real de IA (verificada nesta sessão, não presumida)

A tarefa original descrevia "uma cascade de provedores LLM (OpenRouter, Gemini, Perplexity)". Isso está desatualizado. O que existe hoje, confirmado linha a linha contra `api/v4.9.181.js` (o bundle atualmente em working tree, ainda não deployado em produção no momento desta sessão, produção está em v4.9.180) e contra `api/wrangler.toml`:

- **OpenRouter removido desde a v4.9.108.** Comentário no próprio `wrangler.toml:421`: "OPENROUTER_API_KEY... obsoleto desde v4.9.108; saúde exige KV + telemetria + Resend + Anthropic". Confirmado também em `PENDENCIAS.md` (`OPENROUTERVIVO`, `OPENROUTER-DEAD`, ambos resolvidos em 24/07).
- **Funções `chamarOpenRouter` (`v4.9.181.js:6817`) e `chamarPerplexity` (`v4.9.181.js:6989`) ainda existem no bundle, mas sem nenhum call site nas cascades de análise.** Grep confirmou que os arrays de fallback (`v4.9.181.js:8109, 8112, 8305, 8308, 8770, 8773, 16526`) contêm apenas `["claude-haiku-analise", chamarClaudeAnalise, env.ANTHROPIC_API_KEY]`. São funções mortas, não uma cascade ativa. Prioridade baixa (P3) de limpeza, não fiz porque exigiria editar o bundle do Worker, o que a regra do projeto proíbe fazer diretamente.
- **Dois caminhos de IA generativa distintos, não um só:**
  1. **Verificador embutido no Worker** (`VERIFICADOR_CONFIG`, `v4.9.181.js:10106-10109`): `model_primary: "claude-haiku-4-5-20251001"` roda em todo evento do lote; se a confiança retornada for menor que `confianca_escalation: 0.7` (`v4.9.181.js:10489`), escala para `model_escalation: "claude-sonnet-4-6"` numa segunda chamada individual (`v4.9.181.js:10492`). Chamado via API direta da Anthropic (billing por token, secret do Cloudflare). Health check ao vivo desta sessão (ver seção de verificação) confirma `versao:"v4.9.181"` já em produção.
  2. **Rotinas externas via Claude Code CLI** (`scripts/run_vixradar_matinal_claude.ps1`, `run_vixradar_noturno_claude.ps1`, `run_vixradar_verificacao_async.ps1`), rodando no computador do operador, autenticadas por assinatura OAuth (não por API key desde a v4.9.152, ver `DOCBILL1` em `PENDENCIAS.md`). É aqui que o "verificador adversarial" propriamente dito (o que a nota 49 testou contra Fable 5) e as análises de matinal/noturno (Haiku 4.5 para triagem, Sonnet 4.6 para EWS alto ou 103/103 à noite) rodam.
  Não confirmei com certeza absoluta se o caminho 1 e o caminho 2 processam a mesma fila (`radar:verif_fila:{data}`) ou são etapas complementares. Recomendo o time confirmar isso antes de qualquer mudança, eu só li código, não tracei execução ao vivo.
- **Padrão de escalonamento por confiança já existe e já funciona** (Haiku primeiro, Sonnet só quando a confiança é baixa, com telemetria própria via `RADAR_USAGE_EVENTS.writeDataPoint({indexes: ["verif_escalation"], ...})`, `v4.9.181.js:10498-10503`). Isso é relevante porque é exatamente o formato de qualquer proposta de usar Fable 5 com responsabilidade: como uma terceira camada de escalonamento sobre uma minoria de casos de baixa confiança, não como substituição.
- **Briefing Executivo é agregação, não geração de texto nova.** `handleBriefingExecutivo` (`v4.9.181.js:15172-15186`) e `montarBriefingInterno` (`v4.9.181.js:15077-15171`) apenas contam e agrupam eventos já classificados pelas rotinas de matinal/noturno (por setor, por classificação CRITICO/RELEVANTE/ECO ao longo de 5 semanas). Não há chamada de LLM nova nesse endpoint. Isso é relevante para a Proposta 2 abaixo.
- **Existe uma iniciativa paralela e ativa de otimização de prompt** que não usa troca de modelo: "Otimização de Prompts (ADR-029)", visível no painel admin em produção, usando DSPy MIPROv2 e MLflow GEPA para compilar o prompt do classificador CRITICO/RELEVANTE/ECO/RUIDO, com critério de promoção definido (F1 maior ou igual a 0.85, sem degradar CRITICO) e aprovação registrada ("Aprovado Yan 2026-04-24"). Mencionado aqui só para não duplicar esforço: é uma frente diferente (otimizar o prompt do modelo atual) da que esta sessão foi pedida para avaliar (trocar de modelo).

## Perfil do Claude Fable 5

Fontes: skill `claude-api` (cache de 2026-06-24) e a pesquisa que o próprio time já fez em 2026-07-10 (nota 49), com os mesmos números batendo entre as duas fontes, o que dá confiança de que não mudou material nesse intervalo, mesmo sem poder confirmar via web nesta sessão.

- Modelo mais capaz da Anthropic em disponibilidade geral, para raciocínio profundo e trabalho agêntico de longo horizonte. Não é um modelo de "narrativa" (apesar do nome), é o topo da linha em capacidade.
- Contexto de 1M tokens, saída até 128k, thinking adaptativo sempre ligado (não dá para desligar, controla-se profundidade via `effort`).
- Preço: USD 10 de entrada e USD 50 de saída por milhão de tokens (2x o Opus 4.8). Sob cobrança por token, é caro. Sob assinatura Claude Code (OAuth), o custo marginal de uso é efetivamente zero, o que muda o cálculo, mas não elimina os outros riscos (ver abaixo).
- Retenção de dados obrigatória de 30 dias (não funciona em conta com Zero Data Retention). A conta usada aqui não tem ZDR, então não é um bloqueador para este projeto especificamente.
- Classificadores de segurança podem recusar a resposta com `stop_reason: "refusal"` (HTTP 200, não é erro). O modelo já foi suspenso uma vez (12/06) por um jailbreak encontrado por pesquisadores da Amazon, e foi reabilitado com um classificador retreinado que, segundo a própria Anthropic, recusa com mais frequência conteúdo legítimo do que antes. Isso é o risco central para um pipeline não supervisionado como o deste sistema (roda sozinho, de madrugada, sem humano olhando cada resultado).
- Existe parâmetro de fallback automático (`fallbacks`, beta) e middleware de SDK para reagir a uma recusa chamando outro modelo na mesma call. Não está confirmado se a flag `--fallback-model` da CLI local cobre especificamente recusa de classificador (distinto de "modelo sobrecarregado ou indisponível", que é como a documentação da CLI descreve o fallback). Essa lacuna já estava registrada na nota 49 e continua aberta.

## O que já existia (para não duplicar)

- **Nota 49** (`Obsidian VIX Radar/49 - Avaliação Fable 5 e Guards Refusal 2026-07-10.md`): teste comparativo real, 2 rodadas, prompt idêntico ao de produção (`buildVerifierSystemPrompt`), Fable 5 contra Sonnet 4.6. Nas duas rodadas os veredictos bateram (ambos corretamente reprovaram eventos fabricados/ambíguos), Fable custou de 2.3x a 4.3x mais e não achou nada que o Sonnet tivesse perdido. Decisão registrada: manter Sonnet 4.6, com critério de reversão explícito.
- **`DOCBILL1`** (`PENDENCIAS.md`, resolvido 24/07/2026, ou seja, há 2 dias): reavaliação da decisão considerando que o custo marginal é zero sob assinatura, e mesmo assim mantida a decisão de não trocar, agora apoiada em três pilares que não são de custo: risco de recusa imprevisível num pipeline sem supervisão humana, ausência de ganho de qualidade demonstrado em evento real, e o histórico de suspensão do modelo.
- **Guards já implementados** em `run_vixradar_verificacao_async.ps1` (nota 49): detecção de `stop_reason: "refusal"`, código de saída 8 dedicado, métrica `refusals` no relatório diário, e a variável `$ModelFallback` já existe no script (hoje inerte, porque `$ModelVerificador` e `$ModelFallback` apontam para o mesmo modelo).

## Achados desta sessão, classificados por risco e esforço

| Achado | Risco de agir | Esforço | Valor | Status nesta sessão |
|---|---|---|---|---|
| Política de Privacidade cita provedores de IA errados (OpenRouter, Gemini, Perplexity) | Baixo (texto estático, reversível, sem lógica) | Baixo (uma frase) | Alto (compliance LGPD, a própria política cita artigos de base legal) | **Executado**: `app/index.html:3396` corrigido para citar Anthropic. Falta deploy do Pages, ação do usuário |
| Piloto Fable 5 como segunda opinião em CRITICO rejeitado (shadow mode) | Médio (toca script de produção agendado, mesmo que sem bloquear nada) | Baixo a médio (poucas linhas, reaproveita guards já existentes da nota 49) | Alto (única forma concreta de gerar a evidência que o critério de reversão da nota 49 exige) | **Proposta**, não implementada. Ver detalhe abaixo |
| Narrativa executiva gerada por IA no Briefing Executivo (hoje é só agregação) | Baixo a médio (endpoint novo ou adicional, não substitui nada existente) | Médio (decisão de produto: vale a pena para o plano Profissional, como testar qualidade) | Médio a alto, mas incerto sem validação de produto | **Proposta**, não implementada |
| Funções mortas `chamarOpenRouter`/`chamarPerplexity` no bundle | Impossível para mim agir (exigiria editar bundle do Worker, proibido) | Baixo | Baixo (só higiene de código) | **Não executado, nota apenas** |
| Trocar verificador, matinal ou noturno para Fable 5 | Alto (pipeline de produção sem supervisão, histórico de recusa do modelo) | N/A | Não demonstrado (nota 49 testou e não achou ganho) | **Não recomendado** |

## Executado nesta sessão

1. `app/index.html:3396`: corrigida a frase da Política de Privacidade que citava OpenRouter, Google Gemini e Perplexity como destinatários de consultas de IA, para citar Anthropic (o provedor real desde a remoção do OpenRouter). Mudança de texto puro, sem alteração de lógica. **Ainda não está em produção**: como qualquer mudança em `app/index.html`, precisa passar por `pwsh ./scripts/deploy-pages.ps1` (que sincroniza `app/deploy_zip/`) e bump de `CACHE_VERSION`, conforme o próprio `CLAUDE.md` do projeto. Não rodei o deploy porque isso exige aprovação explícita.
2. Este documento (`Obsidian VIX Radar/68 - ...md`), registrado no índice do vault (ver próxima seção).

## Propostas para validação (não implementadas)

### Proposta 1: piloto em modo sombra, Fable 5 como segunda opinião em CRITICO rejeitado

**Objetivo**: gerar, com risco e custo mínimos, a evidência real que o critério de reversão da nota 49 pede ("teste com eventos CRITICO reais da fila em que Fable pegue erro que Sonnet deixou passar"), sem apostar em produção.

**Como eu desenharia**: quando o verificador (caminho que for, Worker ou rotina externa, a confirmar com o time) rejeita um evento classificado como CRITICO, disparar uma chamada adicional ao Fable 5 em paralelo, só para logging (índice de telemetria novo, por exemplo `verif_fable_shadow`, no mesmo padrão de `writeDataPoint` que já existe em `v4.9.181.js:10498-10503`), sem que o resultado do Fable altere o veredicto real. Depois de 2 a 4 semanas, ou de um número mínimo de casos (o volume de CRITICO rejeitado é baixo, então pode levar um tempo para juntar amostra), comparar: quantas vezes Fable discordou do Sonnet, e nesses casos, qual dos dois estava certo (checagem manual, já que é a exceção, não a regra).

**Por que shadow mode e não uma troca real**: elimina o risco de recusa do Fable quebrar produção (se ele recusar, o log fica vazio para aquele evento, e o veredicto real do Sonnet continua valendo normalmente). Também evita o risco de o time "descobrir" que Fable é mais rigoroso demais e reprovar eventos reais que deveriam ser aprovados, o que a própria nota 49 já sinalizou como o caso decisivo que nunca foi testado.

**Arquivo(s) afetados**: provavelmente `scripts/run_vixradar_verificacao_async.ps1` (onde `$ModelFallback` já existe, hoje inerte) ou o trecho do Worker em `v4.9.181.js` próximo a `:10489-10503`, dependendo de qual caminho o time decidir usar como ponto de entrada. Recomendo fortemente que o time (não eu, nesta sessão) decida isso, porque exige saber com certeza qual dos dois caminhos processa a fila real de eventos CRITICO em produção, algo que só li em código e não confirmei em execução ao vivo.

**Custo estimado**: sob assinatura Claude Code, marginal próximo de zero (mesma lógica do `DOCBILL1`). Se o ponto de entrada escolhido for o caminho do Worker (API paga por token), estimar volume esperado de CRITICO rejeitado por dia antes de ativar, para não surpreender a fatura.

**Risco residual**: ainda existe o risco de recusa do classificador do Fable, mas em modo sombra isso só gera um log vazio, não um incidente. Risco de esforço de engenharia desperdiçado se, ao final do piloto, a conclusão for a mesma da nota 49 (nenhum ganho).

**Como validar antes de aprovar**: pedir ao time para confirmar qual caminho (Worker ou rotina externa) processa a fila real, e decidir o volume mínimo de amostra que tornaria o resultado do piloto conclusivo o suficiente para revisitar a decisão do `DOCBILL1`.

**Classificação**: sensível (toca script/código de produção, ainda que sem mudar comportamento do usuário final), esforço baixo a médio, precisa de aprovação explícita antes de qualquer implementação.

### Proposta 2: síntese narrativa executiva no Briefing Executivo

**Contexto**: o "Briefing do dia" (feature paga, mencionada na landing como diferencial do plano Profissional a R$490/mês) hoje é só contagem estruturada por setor e classificação ao longo de 5 semanas (`montarBriefingInterno`), sem nenhuma síntese em texto corrido. Fable 5 é bom exatamente no tipo de tarefa que esse recurso não faz hoje: sintetizar muitos eventos já classificados, de várias semanas e setores, em uma leitura executiva coerente, com o volume de chamadas baixo (uma vez por sessão de usuário ou, melhor, uma vez por dia com cache, não por evento).

**Por que é diferente da Proposta 1**: aqui não existe uma decisão anterior para contestar, é um recurso novo, então é decisão de produto (vale para o usuário pagante, como testar se a qualidade da prosa é boa o suficiente), não uma correção de rota técnica.

**O que eu não fiz**: não implementei nada disso. Envolve decisão de produto (o que o usuário pagante quer ver), custo a modelar (mesmo com volume baixo, precisa estimar tokens de entrada dado que sintetiza várias semanas de dados), e mais superfície de teste (qualidade da prosa gerada, não só corretude de classificação).

**Classificação**: risco baixo a médio (endpoint novo, não substitui nada), esforço médio, valor incerto até validar com o usuário final se o formato narrativo é o que o plano Profissional realmente precisa.

## O que eu não recomendo, e por quê

Trocar Sonnet 4.6 ou Haiku 4.5 por Fable 5 em qualquer rotina de produção (verificador, matinal, noturno) agora. Motivos, na ordem que considero mais forte:

1. Já foi testado com o prompt real de produção e não mostrou ganho de qualidade (nota 49).
2. O risco não é mais de custo (a assinatura absorve isso), é de confiabilidade: recusa de classificador imprevisível, num pipeline que roda de madrugada sem ninguém olhando, é um jeito novo do sistema falhar silenciosamente que hoje não existe.
3. Histórico de suspensão recente do modelo (12/06) é um sinal de que o comportamento do classificador de segurança ainda está sendo ajustado pela própria Anthropic, o que pesa contra apostar nele num sistema não supervisionado sem primeiro ter uma malha de segurança testada (é exatamente o que a Proposta 1 constrói, antes de qualquer troca real).

## Riscos ocultos identificados nesta sessão

- **Compliance**: a Política de Privacidade desatualizada (corrigida nesta sessão, pendente de deploy) é um risco real, não hipotético, porque o documento cita artigos específicos da LGPD sobre transparência de tratamento de dados.
- **Lacuna de conhecimento**: não está confirmado se a flag `--fallback-model` da CLI Claude Code cobre recusa de classificador (distinto de indisponibilidade). Isso é relevante para qualquer piloto futuro que use Fable 5 fora de modo sombra.
- **Ambiguidade de arquitetura**: não confirmei com certeza se o caminho de verificação embutido no Worker (`VERIFICADOR_CONFIG`) e o caminho externo via CLI (que a nota 49 testou) processam a mesma fila ou são etapas distintas do pipeline. Isso precisa ser esclarecido pelo time antes de qualquer mudança no verificador, inclusive antes da Proposta 1 acima.
- **Ferramental desta sessão**: `WebSearch`, `WebFetch` e o agente `Explore` falharam com erro de modelo (`deepseek-v4-flash`) mesmo depois de eu fixar o modelo explicitamente na chamada do agente. Vale reportar isso separadamente da tarefa de negócio, porque limita qualquer sessão futura que dependa de pesquisa externa ou de subagentes.

## Registrar

Adicionada entrada desta nota em `00 - Índice (MOC).md` (seção "Auditorias recentes" e "Pesquisas e análises").

---

*Sessão executada em 2026-07-26 via `/melhorar-e-executar`. Modo de leitura e análise, uma edição de texto local aplicada (`app/index.html`), sem deploy. Pesquisa externa via web bloqueada por falha de ferramenta (ver seção de metodologia). Portão de verificação rodado ao final: `curl.exe -s https://radar-credito-api.prospects-intel.workers.dev` retornou HTTP 200 em 0,133s, `{"ok":true,"versao":"v4.9.181","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","verificador_ok":true}`.*
