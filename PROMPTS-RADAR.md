# PROMPTS — RADAR DE CRÉDITO PRIVADO

Atualizado: 2026-07-22. Alinhado a: Worker **v4.9.170**, Frontend **v201.83**, `CLAUDE.md`, Obsidian `03 - Estado Atual.md` + `03b - Infraestrutura.md`, `.claude/SKILLS-ROUTER.md`, `PENDENCIAS.md`.

Mudanças desde a versão de 10/07 (v4.9.149/v201.74) refletidas em todos os prompts: **cascade OpenRouter/Gemini não está 100% morta** — `probeOpenRouterSonarPro` ainda chama Perplexity via OpenRouter em 4 pontos vivos, incluindo cron `0 1 * * *` e health diário (achado `OPENROUTERVIVO`, P3 aberto) — os prompts de diagnóstico e auditoria agora checam isso em vez de assumir cascade totalmente obsoleta; verificador roda em **`claude-sonnet-4-6`** (não 4.5) fixo em 100% da fila via `claude -p` sob OAuth, decisão deliberada documentada mesmo com custo medido (`VERIFMODEL1`); numeração de versão agora é **uma por deploy, nunca reaproveitada** (regra criada depois do incidente `VERSAO3X`, em que `v4.9.167` foi publicada três vezes com conteúdos diferentes sob o mesmo número); backlog vivo passou a ser tratado como **`Obsidian VIX Radar/PENDENCIAS.md`** (movido da raiz do projeto em 27/07/2026; o estado anterior a 26/07/2026 está congelado em `Obsidian VIX Radar/_Arquivo/PENDENCIAS (historico ate 2026-07-26).md`, que segue sendo a fonte de consulta para recorrência de bug), mais granular e atualizado com mais frequência que o snapshot do Obsidian — em caso de conflito de detalhe fino (não de fatos de produção), `PENDENCIAS.md` vence por ser a fonte mais recente.

---

## Prompt 1 — Auditoria Semanal Completa

Faça a auditoria semanal do Radar de Crédito Privado usando a skill local `/vix-radar-audit` (modo `--quick` por default; completo só se eu pedir). Siga esta ordem sem pular etapas: (1) leia o Obsidian primeiro — `00 - Índice (MOC).md` e `03 - Estado Atual.md` — para saber o estado registrado, e cheque `PENDENCIAS.md` no root do repo para o backlog granular mais recente; (2) busque o código real do Worker via Cloudflare MCP com `workers_get_worker_code("radar-credito-api")` e confirme a versão; (3) execute o health check duplo: curl local em `https://radar-credito-api.prospects-intel.workers.dev` (esperado: HTTP 200, `ok:true`, `telemetria:true`, `kv:true`, `verificador_ok:true`) + Sprite MCP `exec_command` → `sprite=site`, `command=sh health_vix.sh`; (4) verifique a `CACHE_VERSION` em produção via `curl -s https://vixradar.com/version.json`; (5) compare produção real com `CLAUDE.md`, `03 - Estado Atual.md` e `PENDENCIAS.md` e identifique qualquer drift — inclusive se algum item listado como "Resolvido" em `PENDENCIAS.md` já foi promovido no Obsidian, e vice-versa; (6) verifique a saúde das rotinas locais: últimos `logs/routines/vixradar-matinal_*.log` e `vixradar-noturno_*.log` (presença de `FIM:`, `auth_fail=0`, `silent_fail`), métricas `*_metrics_*.json` (atenção a metrics zerado sobrescrevendo run real em skip idempotente, padrão `METRICSZERO1`), e estado da fila `radar:verif_fila`; (7) confirme rapidamente se `OPENROUTER_API_KEY` segue configurado como secret do Worker e se os probes de `probeOpenRouterSonarPro` continuam vivos no cron `0 1 * * *` e no health diário — não é mais seguro assumir cascade 100% obsoleta; (8) registre a auditoria como nova nota `NN - Auditoria Completa YYYY-MM-DD.md` no Obsidian, atualize `03 - Estado Atual.md` e corrija drift no `CLAUDE.md` — sempre com dados reais coletados, nunca com suposições. Produza o resumo de achados (com evidência bruta) antes de qualquer atualização nos documentos.

## Prompt 2 — Deploy de Nova Feature

Preciso implementar a seguinte feature no Radar de Crédito Privado: [DESCREVER AQUI]. Antes de escrever uma linha de código, execute obrigatoriamente: (1) leitura do Obsidian `03 - Estado Atual.md` e de `PENDENCIAS.md` (drift repo/prod e conflito com pendência já aberta na mesma área); (2) `workers_get_worker_code("radar-credito-api")` para confirmar o Worker real de produção contra o repo; (3) health check no endpoint (esperado `ok:true`, `telemetria:true`, `kv:true`, `verificador_ok:true`); (4) `CACHE_VERSION` atual via `curl -s https://vixradar.com/version.json`. Então declare explicitamente: o ponto exato de inserção da feature, quais funções existentes serão preservadas, quais serão adicionadas, e os riscos de regressão — incluindo as regras invioláveis do `CLAUDE.md`: endpoints multi-semana usam `carregarEstadoMultiSemana(env, 5)` com escrita só na semana corrente; binding `RADAR_USAGE_EVENTS` intocável no `api/wrangler.toml`; CSS `<strong>` sem `color` global. Se a feature tocar fila de verificação, KV de estado semanal, ou qualquer endpoint de escrita autenticado por `ROUTINE_KEY`, cheque `PENDENCIAS.md` por `VERIFQ-ORFAO1`, `DEDUPFILA1` e `ROUTINEKEY-PLAIN1` antes de decidir a abordagem — não duplicar problema já mapeado. Só depois escreva o código. Regras de artefato: não editar bundles `api/v4.9.*.js` in-place — nova versão do Worker = novo arquivo versionado apontado no `wrangler.toml`, com **número de versão nunca reaproveitado**, mesmo para hotfix do mesmo dia (ver incidente `VERSAO3X` — três deploys sob o mesmo número tornaram "voltar para v4.9.167" ambíguo); fonte viva do frontend é `app/index.html`, sincronizar `app/deploy_zip/` antes do deploy e regenerar `version.json`. Ordem de deploy: (a) Worker primeiro — `pwsh ./scripts/deploy-worker.ps1 -Version v4.9.XXX` (o script já aplica `--no-autoconfig`, obrigatório no Wrangler 4.x, valida produção e commita/pusha); (b) teste real do endpoint da feature + health; (c) Pages — `pwsh ./scripts/deploy-pages.ps1`; (d) bump de `CACHE_VERSION` validado em produção por último. Para alterações não triviais, delegar a revisão final ao subagente `code-reviewer` antes de declarar pronto — não substituir por releitura própria. Encerre com o pós-edição obrigatório: causa raiz/ponto de inserção confirmado, evidência objetiva, correção aplicada, validação em produção — e registre no Obsidian e em `PENDENCIAS.md` se algo ficou pendente.

## Prompt 3 — Diagnóstico de Incidente em Produção

O sistema Radar de Crédito Privado está apresentando o seguinte comportamento anômalo: [DESCREVER O SINTOMA EXATO]. Use OODA (Observe → Orient com ≥2 hipóteses → Decide ação reversível a ~70% de confiança → Act → re-Observe) e, se urgente, a skill `/ODDA`. Faça o diagnóstico em uma única passada, sem tentativa e erro. Primeiro, mapeie todas as camadas que podem estar envolvidas: frontend (Pages/cache/`CACHE_VERSION`), Worker, KV `RADAR_KV`, Durable Objects `RateLimiterDO` e `ESTADO_SEMANA_DO`, telemetria Analytics Engine, JWT/CORS, rotinas locais PS1 (matinal 10h, noturno 18h, verificação async 10h20), fila de verificação `radar:verif_fila`, Task Scheduler nativo (confirme se não há scheduled-task Claude Code duplicada rodando em paralelo — causa histórica de duplicatas), sessão OAuth do `claude -p` usado pelo verificador (as 3 rotinas removem `ANTHROPIC_API_KEY` do processo filho para forçar OAuth), e saldo/crédito da conta. Segundo, liste exaustivamente as causas possíveis, incluindo obrigatoriamente as já documentadas no histórico: `Credit balance is too low` (gap conhecido P2 — ainda não abortável pelas guardas, degrada silencioso), OAuth expirado mascarado como sucesso com exit 0 (guarda de auth-failure existe nas 3 rotinas desde 08/07, mas confirme que disparou), evento CRITICO preso na fila aguardando drenagem (invisível no painel até o próximo trigger, e sem sweep de pendentes órfãos além de 48h — `VERIFQ-ORFAO1`), merge rule de `sem_eventos` violada, deploy parcial (Worker sem Pages ou vice-versa, ou número de versão reaproveitado — `VERSAO3X`), drift `app/index.html` vs `deploy_zip/`, mojibake quebrando dedup ou leitura, `stop_reason:refusal` do classificador Fable 5 na fila (exit 8, métrica `refusals`), janela temporal em UTC em vez de UTC-3, e — se o sintoma envolver custo ou latência anômala — os probes vivos de `probeOpenRouterSonarPro` (`OPENROUTERVIVO`) ainda rodando fora do cascade principal. Terceiro, execute um único teste confirmatório: o teste padrão do `CLAUDE.md` (curl GET em `https://radar-credito-api.prospects-intel.workers.dev` com `-w` para HTTP status e tempo total; esperado HTTP 200, `ok:true`, `telemetria:true`, `kv:true`) — lembrando que POST anônimo retorna 401 por design desde v4.9.x e não é evidência de falha — e, se o sintoma envolver rotinas, leia o log e o `*_metrics_*.json` do dia, confirmando que o metrics não foi sobrescrito por um skip idempotente (`METRICSZERO1`). Só então apresente a causa raiz confirmada com evidência objetiva, a correção aplicada e a validação em produção. Registre o incidente no Obsidian `03 - Estado Atual.md` e, se virar pendência, em `PENDENCIAS.md` com um ID curto no padrão do projeto (ex: `NOMECURTO1`).

## Prompt 4 — Atualização de METRICAS_CURADAS

Preciso atualizar os dados estáticos de KPI do emissor [NOME DA EMPRESA] no objeto `METRICAS_CURADAS` do frontend. Os novos valores são: [listar os 4 cards com label, value, ref, status e note]. Antes de qualquer edição: (1) confirme a versão em produção via `curl -s https://vixradar.com/version.json` e verifique que `app/index.html` do repo (fonte viva do frontend) está alinhado — se houver drift, pare e me avise; (2) localize o bloco do emissor no objeto `METRICAS_CURADAS` em `app/index.html`; (3) aplique apenas as mudanças informadas, preservando todos os outros emissores intactos; (4) bumpe a `CACHE_VERSION` com um número novo — não reaproveitar versão já publicada, mesmo que pareça só uma correção pequena (ver `VERSAO3X`); (5) sincronize `app/deploy_zip/` a partir de `app/index.html` e regenere `version.json` com a `CACHE_VERSION` nova; (6) deploy via `pwsh ./scripts/deploy-pages.ps1`; (7) valide em produção: `curl -s https://vixradar.com/version.json` e `CACHE_VERSION` no HTML servido. Lembre que `METRICAS_CURADAS` é uma camada estática independente dos eventos da janela rolling e não chama o Worker — não há deploy de Worker envolvido.

## Prompt 5 — Varredura Final ao Encerrar Sessão

Ao final desta sessão de desenvolvimento no Radar de Crédito Privado, execute a varredura final obrigatória: (1) busque o Worker real via `workers_get_worker_code("radar-credito-api")` e confirme a versão deployada; (2) verifique a `CACHE_VERSION` em produção via `curl -s https://vixradar.com/version.json`; (3) compare o que foi entregue nesta sessão com o que está efetivamente em produção e aponte qualquer divergência — inclusive drift `app/index.html` vs `deploy_zip/` e número de versão reaproveitado; (4) liste o que mudou em relação à sessão anterior (funções adicionadas, bugs corrigidos, versões bumpeadas, commits); (5) se houve deploy nesta sessão, rode o health duplo (curl + Sprite `sh health_vix.sh`); (6) registre no Obsidian: atualize `03 - Estado Atual.md` e crie nota de auditoria/incidente se aplicável — nunca deixar informação crítica só no chat; (7) atualize `PENDENCIAS.md` (mova itens resolvidos para a seção "Resolvido desde", com data e evidência, e adicione novos itens com ID curto e severidade) e confirme se `CLAUDE.md`, `.claude/SKILLS-ROUTER.md` ou alguma skill local em `.claude/skills/` ficou desatualizada em relação ao estado real — se sim, corrija ou liste exatamente o que precisa de correção manual. Só declare sessão encerrada após esses 7 passos.

## Prompt 6 — Anti-Erro Sistemático: Injeção de Padrões de Falha Conhecidos

Antes de escrever qualquer código ou diagnóstico nesta sessão, leia e internalize esta lista de erros que já ocorreram neste projeto e que são proibidos de se repetir:

ERROS PROIBIDOS — HISTÓRICO DO RADAR:

1. Versão fantasma: assumir versão do Worker/frontend pela memória sem checar produção (MCP + curl) e Obsidian primeiro.
2. Deploy parcial: entregar Worker atualizado sem Pages, ou Pages sem Worker; ou assumir que Pages publicado = Worker publicado.
3. Template literal: usar `${}` dentro de string com aspas comuns ao invés de backtick.
4. Drift de deploy_zip: deployar Pages sem sincronizar `app/deploy_zip/` a partir de `app/index.html` e sem regenerar `version.json`.
5. Wrangler sem `--no-autoconfig`: no Wrangler 4.x, sem essa flag o deploy detecta projeto errado (`E:\Diretorio\Claude\dashboard`) e ignora o `wrangler.toml`. Os scripts `deploy-worker.ps1`/`deploy-pages.ps1` já passam a flag — deployar na mão sem ela é o erro.
6. Editar bundle in-place: modificar `api/v4.9.*.js` deployado diretamente — bundles são artefatos Wrangler auditáveis no repo (`api/v4.*.js` saiu do `.gitignore` em `a2e7d84`); nova versão = novo arquivo versionado, **número nunca reaproveitado** (ver `VERSAO3X`: mesmo número publicado 3x com conteúdo diferente, "voltar para v4.9.167" virou ambíguo).
7. Merge rule violada: deixar `sem_eventos: true` sobrescrever KV que já tinha eventos.
8. `nao_identificada` em campo de data: `sanitizarPayloadRadar` descarta, evento some silenciosamente.
9. Falha mascarada como sucesso: `catch(e) {}` vazio (ainda há ~60 no bundle ativo, maioria telemetria — mas 5-6 pontos merecem log real, ver `CATCH60`), ou rotina PS1 terminando exit 0 com `tokens=0` (OAuth expirado, `Credit balance is too low` — este último ainda **não é abortável** pelas guardas, gap conhecido P2) sem alarme.
10. UTC ao invés de UTC-3: janela temporal incorreta, eventos aparecem no dia errado.
11. Gatilho duplicado: rotina agendada em Task nativa E scheduled-task Claude Code ao mesmo tempo, ou dois scripts de registro divergentes cobrindo a mesma task (`register-vixradar-tasks.ps1` vs `register-all-routines-scheduler.ps1` — ainda não consolidado, `REGDRIFT1` aberto).
12. CSS `<strong>` com `color` global: só `font-weight`; cor por seletor específico.
13. Código omitido com "// ... resto igual": entregar incompleto é proibido.
14. Múltiplos testes para descobrir erro: proibido. Um teste serve para confirmar, não para explorar.
15. Injeção de prompt via campo de evento: interpolar `titulo`/`evento`/`fonte_primaria` crus no prompt do verificador sem delimitador — esses campos vêm de notícia lida na web, fonte hostil pode carregar instrução disfarçada (`VERIFINJ1`, aberto).
16. Secret em texto plano fora do `.gitignore`: chave de autenticação de rotina (`ROUTINE_KEY`/`ROUTINE_API_KEY`) documentada em texto plano num `SKILL.md` local em vez de env var/secret (`ROUTINEKEY-PLAIN1`, aberto).

Agora declare, para a tarefa atual: qual destes padrões tem maior probabilidade de ser ativado? Qual a contramedida específica que você vai aplicar? Só então prossiga com o trabalho.

## Prompt 7 — Underground: Adversarial Self-Critique para Inteligência Máxima

Para a tarefa a seguir, você vai operar em três vozes simultâneas antes de produzir qualquer output final. Não me entregue o output intermediário, a não ser que eu peça explicitamente. Execute internamente:

VOZ 1 — Executor: resolve o problema da forma mais direta e tecnicamente correta possível. Não se preocupe com crítica ainda.

VOZ 2 — Adversário: tente quebrar a solução da Voz 1. Encontre o caso em que ela falha. Assuma que eu vou testar em produção com Sabesp, Sabesp sem eventos, Sabesp com KV vazio, com a conta Anthropic sem crédito (`Credit balance is too low`, ainda não abortável), com a sessão OAuth do `claude -p` expirada, e com a fila `radar:verif_fila` presa com item órfão há mais de 48h — simultaneamente. Onde exatamente a solução colapsa? Qual o cenário mais improvável que, se ocorrer, expõe um bug silencioso?

VOZ 3 — Árbitro: receba o diagnóstico da Voz 2 e decida se a solução da Voz 1 deve ser entregue como está, corrigida, ou se precisa de informação adicional que não está disponível neste contexto. Se falta informação, liste exatamente o que falta em vez de assumir.

Só após esse ciclo interno de três vozes, entregue o output final. Se o Árbitro identificou que falta informação de produção, pare e me peça antes de escrever código.

A tarefa é: [DESCREVER AQUI]

## Prompt 8 — Pre-Mortem Invertido: Assuma que Já Falhou

Vamos fazer um pre-mortem desta tarefa antes de escrever uma linha de código.

Assuma que já é segunda-feira de manhã e a feature ou correção que vou pedir agora foi deployada na sexta, quebrou produção no sábado, e passou o domingo inteiro offline. Usuários pagantes (Mirabaud, tesourarias) não conseguiram acessar o Radar durante todo o fim de semana. As rotinas matinal e noturna rodaram o fim de semana inteiro contra um sistema quebrado. Eu estou agora tentando entender o que aconteceu.

Sua tarefa: escreva o post-mortem dessa falha hipotética. Seja específico para o stack atual — Worker v4.9.170, Frontend v201.83, verificador adversarial `claude-sonnet-4-6` via `claude -p` sob OAuth, KV `RADAR_KV`, Durable Objects `RateLimiterDO` e `ESTADO_SEMANA_DO`, fila `radar:verif_fila`, Task Scheduler nativo (matinal 10h, noturno 18h, verificação async 10h20). Quais foram as 7 causas mais prováveis que levaram a esse colapso? Qual das 7 é a que eu, Yan, teria menor chance de ter antecipado sozinho? Qual é a que o próprio Claude teria alucinado em silêncio sem me avisar?

Só depois de me entregar esse post-mortem hipotético você tem permissão para propor a solução. A solução deve neutralizar explicitamente cada uma das 7 causas identificadas. Se não neutralizar alguma, declare qual e por quê.

A tarefa é: [DESCREVER AQUI]

## Prompt 9 — Step-Back: Forçar Abstração Antes do Código

Antes de resolver qualquer coisa técnica no Radar hoje, pare e responda em uma única passagem o seguinte.

Qual é o princípio mais fundamental do Radar que a tarefa que estou propondo toca? Não é sobre o Worker, não é sobre o KV, não é sobre as rotinas de IA. É sobre uma regra invariável do sistema, uma das que se violada quebram a proposta de valor para o gestor de fundo.

Exemplos de princípios fundamentais do Radar: "a janela rolling nunca é substituída por calendário fixo"; "`sem_eventos: true` nunca sobrescreve dados no KV"; "evento CRITICO só fica visível após verificação adversarial — credibilidade antes de velocidade"; "leitura é multi-semana (`carregarEstadoMultiSemana(env, 5)`), escrita é sempre na semana corrente"; "número de versão de deploy nunca é reaproveitado, mesmo em hotfix do mesmo dia"; "produção é a única fonte de verdade, nunca a memória de sessão nem o `SKILL.md`"; "falha de rotina tem que ser barulhenta — exit 0 com zero tokens é mentira, e ainda há um gap conhecido (`Credit balance is too low`) que não dispara essa barulheira"; "o sistema chega ao gestor, o gestor não caça informação".

Identifique qual princípio está em jogo nesta tarefa. Depois, derive a solução a partir dele, de cima para baixo. Se a solução técnica viola o princípio mesmo que marginalmente, você tem obrigação de recusar a abordagem e propor outra que respeite o invariante. Não aceite trade-off silencioso.

A tarefa é: [DESCREVER AQUI]

## Prompt 10 — Tree of Thoughts: Três Caminhos, Um Vencedor

Para a decisão técnica que vou propor abaixo, você está proibido de me entregar uma única solução. Proceda assim.

Galho A, Conservador: a solução que minimiza risco de regressão, reusa o máximo de código existente do Worker atual, e mantém a superfície de API inalterada. Declare custo, prazo de implementação e limitação que essa escolha impõe no futuro.

Galho B, Agressivo: a solução tecnicamente mais correta, mesmo que exija refatorar estrutura do KV, adicionar endpoint, mexer nas rotinas PS1, ou bumpar `CACHE_VERSION` com potencial de invalidar sessões. Declare o ganho de capacidade e o custo operacional de mudar.

Galho C, Hedge: a solução intermediária que resolve o problema imediato mas deixa uma porta aberta para migrar para B depois, sem compromisso. Declare explicitamente o que fica "para depois" e o risco de isso virar dívida técnica permanente — como aconteceu com o próprio backlog atual (vários P2/P3 em `PENDENCIAS.md` são débito técnico conhecido há semanas, não descoberta nova).

Avalie os três galhos sob quatro critérios: risco de quebrar vixradar.com em produção, tempo até o Mirabaud poder ver a mudança, preservação do princípio "produção é a única fonte de verdade", e alinhamento com o backlog crítico atual (`PENDENCIAS.md`, seção "Pendências abertas", ordenado por severidade).

Só depois dessa avaliação, recomende um dos três. Se os três têm mérito real, diga que a escolha é minha e explique o critério de corte que você usaria no meu lugar.

A decisão é: [DESCREVER AQUI]

## Prompt 11 — Chain of Verification: Dossiê de Evidências Antes de Qualquer Código

Para esta tarefa, você está proibido de escrever uma única linha de código, diff ou recomendação operacional sem antes montar um dossiê de evidências. Execute as 4 etapas em ordem e me mostre o resultado de cada uma antes da próxima.

Etapa 1 — Evidência de Produção: busque o Worker real via `workers_get_worker_code("radar-credito-api")` e cole as 20 linhas ao redor da função que a tarefa toca. Confirme a versão real do Worker via `GET /` (campo `versao`) e a `CACHE_VERSION` real do frontend via `curl -s https://vixradar.com/version.json`. Se a tarefa tocar rotinas, cole também o trecho relevante do PS1 e do último log. Se a tarefa tocar algo já mapeado em `PENDENCIAS.md` (fila de verificação, dedup, secrets, coleta de volatilidade), cole a entrada correspondente inteira — ela já tem linha de código e causa raiz confirmadas em muitos casos, não redescubra do zero. Sem esse dossiê, etapa 2 é proibida.

Etapa 2 — Afirmações Derivadas: liste em bullets numerados cada afirmação que você vai fazer na solução. Ao lado de cada uma, escreva entre parênteses a fonte: "confirmado pela Etapa 1", "Obsidian/CLAUDE.md", "PENDENCIAS.md", "inferência minha, não confirmado", ou "vindo da conversa anterior". Qualquer afirmação marcada como inferência não pode entrar no código final sem ser convertida em "confirmado pela Etapa 1" ou removida.

Etapa 3 — Lacunas: liste tudo que falta para a tarefa ser resolvida com rigor. Se falta alguma confirmação de produção, pare e me peça antes de seguir.

Etapa 4 — Solução: agora sim, proponha o código ou diagnóstico, com cada decisão amarrada a um bullet numerado da Etapa 2. Decisão sem amarração a um bullet é proibida. Se a mudança não for trivial, sinalize que vai passar pelo `code-reviewer` antes de ser dada como concluída.

A tarefa é: [DESCREVER AQUI]

## Prompt 12 — Self-Consistency: Três Claudes Independentes Votam

Para a tarefa a seguir, simule internamente três passadas independentes antes de me responder. Cada passada começa do zero, sem conhecimento das outras, como se fossem três engenheiros diferentes recebendo o mesmo problema em salas separadas.

Passada 1 — O Cético: começa assumindo que o código atual do Worker está correto e o bug está em outra camada (frontend, KV, cache do Cloudflare, rotinas PS1 locais, fila de verificação, sessão OAuth/saldo do `claude -p`, probes residuais de `probeOpenRouterSonarPro`, browser do usuário). Onde você procuraria primeiro?

Passada 2 — O Pragmático: começa assumindo que já houve um bug parecido antes, documentado em `PENDENCIAS.md` (seções "Pendências abertas" e "Resolvido desde 2026-07-13") ou nas notas de auditoria do Obsidian (`NN - Auditoria*`). Procure padrões — o projeto tem histórico denso de recorrência (ex: `LOGLOCK1` reincidiu, `VOLTASK1` teve o disparo corrigido mas a coleta em si seguiu quebrada como `VOLCOLETA1`). Qual a hipótese mais barata de testar primeiro?

Passada 3 — O Arquiteto: começa assumindo que o bug é sintoma de uma falha estrutural que vai se repetir até ser corrigida na raiz (exemplos reais do histórico: dependência de máquina local ligada/estável para as 3 rotinas locais; dois scripts de registro de task divergentes sem canônico definido — `REGDRIFT1`; ausência de lock na fila de verificação). Qual a falha estrutural candidata?

Após as três passadas, compare os diagnósticos. Se os três convergem para a mesma causa raiz, me entregue com alta confiança. Se divergem, me entregue as três hipóteses ranqueadas por custo de teste, e diga qual você testaria primeiro se fosse você no meu lugar. Proibido escolher a hipótese mais interessante em vez da mais provável.

O problema é: [DESCREVER AQUI]

## Prompt 13 — Sales-Ready Mode: Every Pixel Sells

Antes de executar qualquer tarefa no Radar, ative o modo Sales-Ready. Esse modo é inegociável e se aplica a toda saída visível de agora em diante, independente de a tarefa ser frontend, backend, documentação, email de resposta, ou fix de bug.

Premissa operacional: assuma que hoje, sem aviso, às 14h, a Mirabaud vai abrir vixradar.com na frente de um comitê de investimento de 8 pessoas. Assuma também que amanhã, às 9h, um family office que o Yan ainda não conhece vai entrar no site via indicação. Assuma por fim que a qualquer momento você pode receber uma ligação pedindo demo para uma tesouraria corporativa. O site precisa estar sempre em estado de venda, nunca em estado de obra.

Padrão visual inegociável (frontend): minimalismo institucional no padrão Bloomberg e Addepar. Densidade de informação alta, mas sem poluição. Cada elemento na tela tem uma razão de existir. Paleta Radar preservada estritamente: fundo `#001020` e `#001830`, dourado `#B7985D` `#C9A96E` `#A8894A`, borda `#0D2438` `#0A1C30`, texto `#EDE8D8` `#D8D0C0` `#8896A0`, vermelho crítico `#EF4444` sobre `#120606`, âmbar relevante `#D97806` sobre `#0A0D00`, verde positivo `#34D399`. Proibido introduzir cor fora desse set. Regra inviolável de CSS: `<strong>` sem `color` global — só `font-weight`; cor por seletor específico. Tipografia: Cormorant Garamond para display, Inter para UI, IBM Plex Mono para números e labels. Espaçamento generoso. Skeleton loaders em vez de spinners. Empty states que sugerem capacidade, não ausência. Zero emoji, zero iconografia decorativa, zero gradientes gratuitos. Dourado como acento, nunca como fundo. Antes de fechar qualquer entrega visual, confirme que não introduziu regressão de acessibilidade conhecida (foco de modal, contraste de texto muted, `aria-*` em toggles) — há débito técnico aberto nessas frentes; não piorar.

Padrão comercial inegociável (backend, mesmo invisível): latência percebida abaixo de 15 segundos em análise completa. As rotinas de IA (Haiku/Sonnet + verificador adversarial `claude-sonnet-4-6`) nunca expõem ao usuário final qual modelo rodou, artefato de verificação, ou métrica interna de rotina. Graceful degradation obrigatória — o usuário nunca vê "fallback", "fila", "refusal" ou nome de provider. Nenhum endpoint retorna 500 sem JSON estruturado com `erro_usuario` em pt-BR e `erro_tecnico` separado para logs. Se um evento ainda está `_pendente_verificacao` na fila, o usuário não pode ver isso como se fosse um evento já confirmado — trate como gap de produto real, não só de estilo.

Checklist pré-entrega — obrigatório antes de fechar qualquer tarefa:

1. Se um prospect entrar agora, essa mudança o deixa mais ou menos propenso a contratar? Se igual ou menos, refazer.
2. Um fundador da Mirabaud veria isso e pensaria "isso parece caro"? Se não, refazer.
3. A mudança quebrou o tom minimalista institucional em algum ponto? Se sim, refazer.
4. Alguma mensagem técnica, código de erro, ou artefato de debug está exposto ao usuário? Se sim, refazer.
5. A feature está bonita em mobile? Se quebra em tela pequena, refazer.
6. O copy está em tom institucional brasileiro, não traduzido do inglês, não informal, não genérico? Se está errado, refazer.
7. Um evento não verificado pode aparecer como se fosse confirmado? Se sim, é bloqueante, não só estético.

Regra de bloqueio final: se a tarefa pedir algo que viola o padrão Sales-Ready em troca de velocidade de entrega, você tem obrigação de apontar o conflito antes de executar. Proibido entregar algo menos do que vendável sob pretexto de "foi o que o usuário pediu". Yan pode estar distraído com o aspecto técnico e esquecendo que o site precisa vender a cada pixel. Sua função é lembrar.

A tarefa atual é: [DESCREVER AQUI]
