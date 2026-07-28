# 05 — Plano de Configuração do Claude Code (VIX Radar)

Data: 2026-07-28. SHA-base: `fdae5cb14b854415f27d9f17333d57812d347f25`. Documento de planejamento, nenhuma configuração foi criada, alterada, habilitada, desabilitada ou removida na sessão que o produziu.

Este é o nono caminho documental da sessão, separado da entrega da auditoria técnica (`00..04` mais os três artefatos do vault). A allowlist de commit daquela entrega continua com oito caminhos, este arquivo é o nono e pode ser commitado junto ou à parte, decisão do Gate B.

Todo o inventário abaixo foi obtido por leitura direta nesta sessão, com o comando ao lado de cada afirmação. Onde a fonte é declaração de arquivo e não observação de runtime, isso está dito.

---

## 1. Estado atual

### 1.1 MCPs, inventário efetivo

Fonte: `claude mcp list` executado em 2026-07-28, saída completa. O inventário anterior desta sessão, baseado só em `.mcp.json`, estava errado por omissão: `.mcp.json` do projeto declara apenas `higgsfield`, e o efetivo são sete servidores configurados localmente mais oito conectores claude.ai.

**Sete MCPs configurados localmente (todos conectados):**

| # | Servidor | Transporte | Escopo | Capacidade | Origem |
|---|---|---|---|---|---|
| 1 | `filesystem` | stdio, `npx -y @modelcontextprotocol/server-filesystem C:\Users\User E:\Diretorio` | Global (usuário) | **Leitura e escrita** em duas árvores inteiras | Oficial MCP reference server |
| 2 | `cloudflare` | stdio, `node .../@itunified.io/mcp-cloudflare/dist/index.js` | Global | Leitura, escrita, deploy, secrets, KV, DNS, WAF | **Comunitário** (`@itunified.io`) |
| 3 | `higgsfield` | HTTP, `mcp.higgsfield.ai/mcp` | Projeto (`.mcp.json`) | Geração de mídia, upload, publicação externa | Terceiro |
| 4 | `tradingview` | stdio, `node C:\Users\User\Documents\tradingview-mcp\src\server.js` | Global | Controle de chart local, Pine, alertas | Local, não empacotado |
| 5 | `sprite` | stdio, `node C:/Users/User/.grok/mcp-servers/sprite-mcp-server/dist/index.js` | Global | VM remota, `exec_command`, push/fetch de arquivo | Local, não empacotado |
| 6 | `lovable` | HTTP, `mcp.lovable.dev` | Global | Cria e faz deploy de projetos, query de banco | Terceiro |
| 7 | `claude-design` | HTTP, `api.anthropic.com/v1/design/mcp` | Global | Escrita de arquivos em projeto de design, sharing | Anthropic |

**Conectores claude.ai, não efetivos neste contexto.** O mesmo comando lista oito entradas `claude.ai` (Context7, Cloudflare Developer Platform em `bindings.mcp.cloudflare.com/mcp`, Canva, Notion, Google Calendar, Gmail, Google Drive, S&P Global), com marcações de conectado ou de autenticação pendente. **Essas marcações não descrevem o estado efetivo do CLI.** No contexto atual os conectores claude.ai estão desabilitados, porque `ANTHROPIC_API_KEY` ou outra fonte de autenticação tem precedência sobre a sessão claude.ai. O inventário efetivo do CLI são os sete servidores da tabela acima, e só eles.

Se o Claude Desktop exibir estado diferente, isso é estado daquela interface, não MCP efetivo universal. Qualquer plano que dependa de conector claude.ai precisa declarar em qual interface roda, e nenhuma automação de linha de comando ou rotina agendada deste projeto pode assumir que eles existem.

### 1.2 Achado P0 — `filesystem` global com acesso amplo

`npx -y @modelcontextprotocol/server-filesystem C:\Users\User E:\Diretorio` concede leitura **e escrita** sobre:

- `C:\Users\User\.claude\` inteiro, incluindo `settings.json`, `settings.local.json`, `agents/`, `skills/`, `plugins/`, `memory/`, `history.jsonl` e os transcripts de todas as sessões de todos os projetos;
- `C:\Users\User\.ssh\`, `.aws\`, `.gitconfig`, blobs DPAPI e qualquer credencial no perfil;
- `E:\Diretorio` inteiro, ou seja os 20 e poucos projetos do portfólio, incluindo `Juridico`, `Financas-Pessoais`, `Processo Mirabaud` e `Pessoal`.

Três consequências que elevam a severidade. Primeira, o servidor pode reescrever a própria configuração que o autoriza, incluindo hooks e allowlists, o que quebra qualquer garantia de contenção construída dentro do `.claude`. Segunda, o escopo cruza a fronteira LGPD do workspace, dado pessoal de terceiro em `Juridico` e `Pessoal` fica acessível a qualquer sessão de qualquer projeto. Terceira, o Claude Code já tem Read, Write e Edit nativos com o mesmo alcance de disco, então o servidor não adiciona capacidade, adiciona um segundo caminho de acesso que não passa pelos mesmos controles de permissão da ferramenta nativa.

Classificação: **P0 por exposição, P1 por urgência operacional**, porque não há incidente conhecido e a mitigação exige decisão do dono. Não é achado de código do VIX Radar, é achado de configuração do ambiente, e por isso não entra no registro canônico da auditoria técnica (`00-AUDITORIA-SISTEMA-COMPLETA.md`), fica aqui.

Item 6 da sua diretriz manda não instalar Filesystem MCP porque o Claude Code já tem capacidade equivalente. O mesmo raciocínio se aplica ao que já está instalado, e é o argumento mais forte para remoção: não se perde função, só se perde superfície.

### 1.3 Cloudflare comunitário versus oficial

Estão em jogo três coisas distintas que a auditoria anterior tratou como uma só.

**O que está conectado hoje** é `@itunified.io/mcp-cloudflare`, pacote npm de terceiro rodando por stdio a partir de `node_modules` global. Expõe cerca de 100 ferramentas, entre elas `worker_deploy`, `worker_delete`, `worker_secret_set`, `worker_secret_delete`, `kv_write`, `kv_delete`, `dns_delete`, `waf_create_custom_rule` e `zt_*`. É token-based, usa a credencial Cloudflare do ambiente, e a conta inteira fica ao alcance, não só o zone do VIX Radar. Código de terceiro com poder de deploy e de manipular secrets é a combinação de maior risco do inventário depois do `filesystem`.

**O conector claude.ai "Cloudflare Developer Platform"** (`bindings.mcp.cloudflare.com/mcp`) é oficial da Cloudflare, remoto e autenticado por OAuth, mas **não está operacional no CLI** pelo motivo da seção 1.1: os conectores claude.ai estão desabilitados neste contexto. Ele aparece na listagem e não pode ser tratado como substituto já disponível do comunitário. Quem quiser contar com ele precisa primeiro resolver a precedência de autenticação, e isso é decisão separada.

**Os servidores oficiais propostos** (Docs, Observability, Builds, Browser) são remotos, `*.mcp.cloudflare.com`, OAuth, e cada um cobre um recorte. Nenhum deles é o `bindings`, e nenhum precisa do pacote comunitário.

Conclusão de método: a proposta de adicionar MCPs oficiais da Cloudflare não é aditiva, é substitutiva, mas a substituição precisa ser construída, não herdada. Hoje não existe caminho oficial operante no CLI, o único Cloudflare efetivo é o comunitário com poder de deploy e secrets. Adicionar os oficiais e manter o comunitário deixaria o pior caminho aberto e ainda duplicaria ferramenta, então a ordem correta é instalar os oficiais, comprovar cobertura e só então desabilitar o comunitário.

### 1.4 Plugins

Fonte: `plugins/installed_plugins.json` mais `enabledPlugins` em `~/.claude/settings.json` e `~/.claude/settings.local.json`.

Nove plugins de marketplace instalados, todos com `scope: user`:

| Plugin | Marketplace | Versão |
|---|---|---|
| `cloudflare` | cloudflare | 1.0.0 |
| `security-guidance` | claude-plugins-official | 2.0.6 |
| `superpowers` | superpowers-dev | 5.1.0 |
| `auto-memory` | severity1-marketplace | 0.9.2 |
| `prompt-improver` | severity1-marketplace | 0.6.0 |
| `this-little-wiggy` | severity1-marketplace | 0.1.0 |
| `nz-akahu-mcp` | severity1-marketplace | 0.1.4 |
| `windsor-ai` | claude-plugins-official | 1.0.0 |
| `frontend-design` | claude-plugins-official | unknown |

`enabledPlugins` é `null` nos dois arquivos de settings, ou seja **nenhum dos nove está ativo**. O único plugin habilitado no ambiente é `pdf-design`, que não consta desta lista de instalados por marketplace.

Isso corrige três afirmações da auditoria anterior. Os plugins `cloudflare`, `security-guidance` e `superpowers` estão instalados em disco e **não estão ativos**, então nada do que eles trazem está em uso. O `superpowers` estar inativo muda inteiramente a análise das skills da seção seguinte, porque não existe a duplicação em runtime que eu havia inferido. E `nz-akahu-mcp` (integração bancária da Nova Zelândia) instalado neste ambiente é ruído que merece revisão de propósito, ainda que inativo.

### 1.5 Skills

29 diretórios em `.claude/skills/`, sendo 28 com `SKILL.md` válido e `shared/` sem `SKILL.md`. 114 skills globais em `~/.claude/skills/`.

Quatorze nomes coincidem com skills do pacote `superpowers` 5.1.0 em cache. Comparação byte a byte de cada par:

| Skill | Bytes projeto | Bytes superpowers | Resultado |
|---|---|---|---|
| `brainstorming` | 10594 | 10634 | diverge |
| `dispatching-parallel-agents` | 6829 | 6441 | diverge |
| `executing-plans` | 2670 | 2469 | diverge |
| `finishing-a-development-branch` | 7073 | 7061 | diverge |
| `receiving-code-review` | 6595 | 6314 | diverge |
| `requesting-code-review` | 2929 | 2808 | diverge |
| `subagent-driven-development` | 22065 | 12546 | diverge |
| `systematic-debugging` | 10181 | 9884 | diverge |
| `test-driven-development` | 10265 | 9867 | diverge |
| `using-git-worktrees` | 7674 | 7983 | diverge |
| `using-superpowers` | 6020 | 5421 | diverge |
| `verification-before-completion` | 4340 | 4201 | diverge |
| `writing-plans` | 7266 | 6100 | diverge |
| `writing-skills` | 27541 | 22624 | diverge |

**Zero cópias byte a byte.** Em 13 dos 14 pares a versão do projeto é maior, e a amostragem do diff mostra que a diferença é conteúdo local acrescentado, não deriva de versão: `subagent-driven-development` tem 418 linhas exclusivas do projeto, `writing-plans` tem 174 (incluindo uma seção inteira de "Task Right-Sizing" que não existe no upstream), `verification-before-completion` tem 139.

Conclusão que inverte a recomendação anterior: essas 14 não são cópias obsoletas para deletar, são forks adaptados. Removê-las em favor do plugin destruiria trabalho local, e ainda por cima o plugin está desabilitado. A classificação correta por diff semântico é a seguinte, e nenhuma remoção é proposta neste plano:

- **Fork enriquecido, manter** (11): `brainstorming`, `dispatching-parallel-agents`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `writing-plans`, `writing-skills`.
- **Divergência pequena, revisar se vale reconciliar com upstream** (3): `executing-plans` (+201 bytes), `finishing-a-development-branch` (+12 bytes), `using-git-worktrees` (o único menor que o upstream, −309 bytes, pode ser corte deliberado ou versão antiga).
- **Ambiguidade real de roteamento** (1 par): `execute-plan` e `executing-plans` coexistem no projeto e só a segunda tem correspondente upstream. Vale confirmar qual é a canônica no `SKILLS-ROUTER.md`.
- **Higiene** (1): `shared/` sem `SKILL.md` não é skill, é diretório de apoio, e pode estar poluindo a descoberta.

### 1.6 Permissões

Dois níveis, e a análise depende de como o modo auto trata cada regra.

**Semântica do modo auto.** Conforme a documentação oficial do Claude Code para a versão em uso, ao entrar em auto as regras de permissão amplas demais para execução são **descartadas**, não herdadas: ferramentas de execução inteiras como `Bash` e `PowerShell`, interpretadores com curinga e comandos amplos de gerenciador de pacote. Regras estreitas **sobrevivem** e resolvem antes do classificador, ou seja executam sem passar por avaliação. O que não é resolvido por regra estreita vai ao classificador, cujo ruleset foi lido nesta sessão via `claude auto-mode config` (exceções ALLOW, SOFT BLOCK e HARD BLOCK). O dump do classificador não descreve o tratamento das regras de permissão, então a semântica de descarte vem da documentação e não daquela saída.

Isso inverte a conclusão preliminar que eu havia registrado. Não é correto dizer que `Bash` e `PowerShell` estão irrestritos, nem que as 226 entradas do projeto são decorativas. O risco real está no oposto do que a intuição sugere: **as regras amplas de execução são as inofensivas, porque caem; as estreitas são as que executam.**

**Global** (`~/.claude/settings.json`): `permissions.allow` é `["Edit", "Write", "Bash", "PowerShell"]` com `defaultMode: "auto"`. As duas de execução, `Bash` e `PowerShell`, são ferramentas inteiras e caem em auto. `Edit` e `Write` são de natureza diferente e não recebem o mesmo tratamento aqui: em auto, edição normal de arquivo dentro do workspace já é aprovada, e a proteção que permanece é sobre caminhos protegidos. Ou seja, listá-las não amplia o que a sessão já faz, e removê-las não protege o que já está protegido.

**Projeto** (`.claude/settings.local.json`, 51,7 KB): 226 entradas em `allow`, sem `defaultMode` próprio. Distribuição por ferramenta: Bash 123, WebFetch 63, PowerShell 25, Skill 5, MCP 6, Read 2, outras 2.

**Reclassificação pelas regras efetivas.** Nenhuma contagem de quantas sobrevivem é dada abaixo. A resolução real de cada regra depende do motor de permissões e não foi comprovada programaticamente nesta sessão, então classifico por forma e por capacidade, e sinalizo o que precisaria de teste.

*Descartadas em auto, por serem amplas demais para execução:*

1. `Bash(npx wrangler:*)` — comando amplo de gerenciador de pacote com curinga. Se sobrevivesse, cobriria `wrangler deploy`, `secret put`, `secret delete`, `kv key delete` e `d1 execute`, contradizendo o `CLAUDE.md` do projeto.
2. `Bash(python -c ":*)` — interpretador com curinga.
3. `Bash` e `PowerShell` inteiros, do global.

*Estreitas, sobrevivem e resolvem antes do classificador:* os comandos literais totalmente especificados de Bash e PowerShell (`curl` com argumentos exatos, `git status`, `gh auth status`), as entradas `WebFetch(domain:...)`, `Read`, `Skill` e as de MCP. Entre elas estão as 21 que carregam a `ROUTINE_API_KEY` morta `mXE26...`, que executam sem avaliação e só não causam dano porque a chave retorna 403. Se a chave fosse viva, seriam 21 chamadas autenticadas a produção resolvidas antes de qualquer gate.

*Estreitas que carregam capacidade real, portanto exigem deny explícito ou remoção.* São cinco de capacidade local, quatro de deploy mais uma de rotina, e a elas se somam as 21 da chave morta e as três de MCP da tabela adiante:

1. `PowerShell(& "E:\Diretorio\Claude\Monitoramento de Credito\scripts\deploy-pages.ps1"*)` — o curinga incide sobre o argumento, não sobre o interpretador nem sobre um verbo amplo de gerenciador de pacote. O script está fixado por caminho absoluto, então a regra é estreita e **sobrevive**. Deploy do frontend de produção com qualquer argumento, resolvido antes do classificador.
2. `PowerShell(& "...\scripts\deploy-pages.ps1")` — a mesma coisa sem curinga. Sobrevive pelo mesmo motivo.
3. `PowerShell(& "...\deploy-worker.ps1" -Version v4.9.166)` e a variante `-SkipValidation` — literais, sobrevivem, disparam deploy de Worker numa versão hoje obsoleta.
4. `PowerShell(pwsh -File "...\run_vixradar_verificacao_async.ps1")` — literal, sobrevive, dispara rotina que grava em produção.
5. As 21 entradas com a chave morta, por higiene e porque a mesma forma voltaria a ser perigosa numa futura rotação.

Correção de leitura registrada: eu havia classificado o item 1 como descartado por ter curinga. Está errado. O que a documentação descarta é interpretador com curinga e comando amplo de gerenciador de pacote, não invocação de script com caminho fixo e argumento livre. As quatro regras de deploy pertencem ao mesmo grupo da regra de rotina, e as cinco sobrevivem.

*Regras de MCP, classificadas por capacidade efetiva, não por presunção de leitura.* Todas as seis nomeiam a ferramenta inteira, sem restrição de argumento. Para ferramenta cujo propósito é execução arbitrária, nomear a ferramenta equivale a conceder o curinga.

| Regra | Capacidade efetiva | Avaliação |
|---|---|---|
| `mcp__sprite__exec_command` | **Execução arbitrária de shell em VM remota.** Sem restrição de comando | O mais grave do inventário de MCP. Funcionalmente equivalente a `Bash(*)`, apenas roteado por nome de MCP. Se a forma "ferramenta MCP inteira" não for alcançada pela regra de descarte, isto é shell irrestrito sobrevivendo em auto |
| `mcp__claude-in-chrome__browser_batch` | **Escrita** no Chrome real do usuário, com as sessões autenticadas dele. Lote de cliques, digitação, navegação e submissão de formulário | Não é leitura. Alcança qualquer serviço em que o usuário esteja logado, e a diretriz de segurança desta sessão exige aprovação por ação para envio, publicação e submissão de formulário |
| `mcp__Claude_Preview__preview_start` | **Cria processo local**, sobe servidor de desenvolvimento | Não é leitura. Efeito colateral persistente além da chamada |
| `mcp__plugin_yan-web-stack_firecrawl__firecrawl_search` | Leitura externa, com egresso de rede e ingestão de conteúdo de terceiro | Leitura, mas traz conteúdo não confiável para o contexto. Tratar retorno como dado, nunca como instrução |
| `mcp__claude-in-chrome__tabs_context_mcp` | Leitura, lista abas por origem | Baixo risco |
| `mcp__scheduled-tasks__list_scheduled_tasks` | Leitura, lista tarefas agendadas | Baixo risco |

As três primeiras entram na lista de deny explícito ou remoção junto com as de deploy. A `mcp__sprite__exec_command` é a de maior prioridade do documento inteiro depois do `filesystem` da seção 1.2, porque concede execução remota irrestrita por uma regra que parece específica só por ter nome longo.

Deny explícito é a contenção necessária para todo este grupo, porque regra estreita nem chega ao classificador. Remover as entradas é equivalente e mais simples que negá-las, e é o que a seção 2.5 propõe. A lacuna de comprovação **não será fechada invocando essas regras**, pelo motivo do princípio de teste da seção 5: a verificação é estática, por ausência da regra antiga, presença do `deny` e conferência de origem em `/permissions` após reinício da sessão.

**Dois curingas de Skill, categoria distinta:** `Skill(claude-api:*)` e `Skill(humanizer:*)` são redundância de roteamento, não capacidade. As duas skills já constam sem curinga, e invocar skill não concede poder além do que a sessão já tem. São higiene, não risco, e não pertencem ao mesmo balde das três de execução nem das quatro que exigem deny.

**Outros resíduos:** 21 entradas contêm a `ROUTINE_API_KEY` morta `mXE26...` (rotacionada em `dfa6854`, retorna 403, já rastreada como P3 em `PENDENCIAS.md`), e há vazamento cruzado de projetos com `WebFetch(domain:...)` de kiwify, blog de psicologia e apostilas, mais `Read(//e/Site/**)` e `Read(//tmp/**)`.

### 1.7 Agentes

Dois no projeto, `code-reviewer` e `revisor`, ambos com `tools: Read, Grep, Glob, Bash`. `Bash` não é read-only, então nenhum dos dois é de fato um revisor sem efeitos colaterais.

Seis globais. Três deles (`coding-agent`, `reasoning-agent`, `light-agent`) declaram modelos de terceiro: `deepseek/deepseek-v4-flash`, `deepseek/deepseek-v4-pro` e `z-ai/glm-4.7-flash`. Os dois primeiros estão inoperantes hoje, ver 1.9.

### 1.8 Hooks

`PreToolUse` no `settings.json` do projeto, dois matchers (`Bash` e `Read|Glob`) chamando o binário externo `graphify.EXE hook-guard`. `Stop` no `settings.local.json`, chamando `.claude/hooks/verificar-antes-de-parar.ps1`, que bloqueia encerramento com código quebrado e tem guarda anti-loop de 3 bloqueios por sessão.

Nenhum hook `PreToolUse` de negação existe hoje. Essa é a peça que falta para a seção 2.4.

### 1.9 Modelo global DeepSeek, regressão ativa

`~/.claude/settings.json` contém `"model": "deepseek-v4-pro[1m]"`. O bloco `env` de roteamento está removido (o `env` global é `{}`), então as rotinas que chamam `claude -p --model claude-sonnet-4-6` seguem protegidas. Mas o modelo default da sessão voltou a apontar para DeepSeek.

`PENDENCIAS.md` registra que em 27/07 ~13h **tanto o bloco `env` quanto a chave `model` foram removidos**, com backup em `settings.json.bak-20260727`. A chave `model` está de volta em 28/07. É regressão, não estado remanescente.

Efeito medido nesta sessão, três ocorrências: o classificador de segurança do modo auto falhou com `deepseek-v4-pro[1m] is temporarily unavailable, so auto mode cannot determine the safety of Bash`, bloqueando chamadas de `curl` ao BCB por duas tentativas; e o `WebFetch` falhou com `There's an issue with the selected model (deepseek-v4-flash)`, o que me levou a concluir erradamente que a página do RI do Bradesco era ilegível. A conclusão errada foi corrigida depois por `curl` direto, mas o custo já tinha sido pago.

Isto **não entra na sequência principal deste plano**. É mudança em arquivo global que afeta todos os projetos do portfólio, e tem gate próprio (ver 4.1).

---

## 2. Estado desejado

### 2.1 Oito skills novas

Todas em `.claude/skills/<nome>/SKILL.md`, frontmatter com `name` e `description`, sem `allowed-tools` (skill instrui, não concede). Nenhuma altera permissão.

| Skill | O que codifica | Origem do conteúdo |
|---|---|---|
| `evidence-first-audit` | Taxonomia COMPROVADO / CORROBORADO / INFERÊNCIA / LACUNA DE RUNTIME, rubrica P0–P3, exigência de comando e saída por evidência, proibição de promover evidência histórica a confirmação atual | Exercitada em `00-AUDITORIA-SISTEMA-COMPLETA.md` |
| `financial-data-provenance` | Todo dado carrega `fonte` e `as_of`, nível de confiança sobrevive até a exibição, métrica autodeclarada não é métrica | DATA-001, `02-MATRIZ-FONTES-CONFIABILIDADE.md` |
| `official-source-verification` | Hierarquia RI da companhia, depois CVM/B3, depois secundárias só corroboram. URL, data-hora e timezone por consulta. Nota de método sobre página SPA versus página com tabela em HTML | Aplicada em CAL-002 |
| `earnings-calendar-validation` | Protocolo específico de calendário de resultados, incluindo checagem contra período de silêncio e distinção entre relatório de produção e resultado financeiro | Pegou os erros de Bradesco e Vale |
| `regression-gate` | Gates A/B/C, o que cada um autoriza, proibição de generalizar aprovação | Este plano e o da auditoria |
| `selective-git-gate` | SHA-base, allowlist, staging por arquivo e por hunk, validação de `--name-status` mais inspeção de conteúdo do diff staged de arquivo já sujo | Método usado na entrega de 28/07 |
| `incident-root-cause` | Todo achado fecha com correção, causa raiz e guarda automatizada que impeça repetição | Regra do projeto, memória `feedback_causa_raiz_e_guarda` |
| `cloudflare-production-audit` | Health como autorreporte e não prova, verificação de bindings, drift por `--dry-run` e não por comparação direta | Ver ressalva abaixo |

Ressalva sobre a oitava: `vix-radar-audit` e `vix-radar-general-audit` já cobrem parte relevante do escopo de `cloudflare-production-audit`. Recomendo criá-la apenas se o objetivo for uma skill genérica reaproveitável em outros projetos Cloudflare do portfólio. Se o objetivo é o VIX Radar, o custo-benefício favorece estender as duas existentes. A decisão é sua e está registrada como aberta.

### 2.2 Cinco subagentes read-only

Todos em `.claude/agents/<nome>.md`.

| Agente | `tools` proposto | Shell? | Função |
|---|---|---|---|
| `auditor-readonly` | `Read, Grep, Glob` | Não | Varredura de código e documentos, produz achados com taxonomia |
| `financial-data-verifier` | `Read, Grep, Glob, WebFetch` | Não | Confere dado do sistema contra fonte oficial externa |
| `test-reviewer` | `Read, Grep, Glob` | Não | Revisa cobertura e qualidade de teste sem executar |
| `production-observer` | `Read, Grep, Glob, Bash` | **Sim, restrito** | Health, endpoints públicos, leitura de log |
| `gatekeeper` | `Read, Grep, Glob, Bash` | **Sim, restrito** | Valida allowlist e diff staged antes do Gate B |

Os três primeiros não recebem shell e por isso são genuinamente read-only por construção. Os dois últimos precisam de shell e recebem o tratamento da seção 2.4. Note que a allowlist proposta para eles é composta de regras estreitas, exatamente o formato que sobrevive em auto, então ela resolveria sem avaliação e não pode ser a única barreira. Daí o hook.

### 2.3 MCPs, classificação e proposta

Classificação de cada servidor proposto pelos quatro eixos exigidos:

| MCP | Leitura | Escrita | Deploy | Acesso externo | Autenticação | Veredito |
|---|---|---|---|---|---|---|
| Cloudflare **Docs** (`docs.mcp.cloudflare.com`) | Sim, pública | Não | Não | Sim, docs Cloudflare | Nenhuma | Instalar, risco nulo |
| Cloudflare **Observability** (`observability.mcp.cloudflare.com`) | Sim, logs e Analytics Engine | Não | Não | Sim, conta Cloudflare | OAuth | Instalar, alto valor, fecha a lacuna de telemetria da auditoria |
| Cloudflare **Builds** (`builds.mcp.cloudflare.com`) | Sim, histórico de build | Não | **Sim, pode disparar build** | Sim, conta | OAuth | Instalar só se o escopo OAuth permitir negar disparo. Caso contrário, adiar |
| Cloudflare **Browser** (`browser.mcp.cloudflare.com`) | Sim, renderiza páginas | Não local | Não | **Sim, navega para qualquer URL** | OAuth | Instalar, útil para SPA de RI (o caso Bradesco). Trata conteúdo externo como dado, nunca instrução |
| **Playwright** (Microsoft, `@playwright/mcp`) | Sim, DOM local | Não | Não | Sim, navega | Nenhuma | Instalar, cobre verificação de UI que hoje é feita por leitura de HTML |
| **GitHub** (`api.githubcopilot.com/mcp`) | Sim, runs, issues, PR | **Sim, se o token permitir** | Não | Sim | OAuth ou PAT | Instalar com PAT fine-grained read-only neste repo, fecha a lacuna de Actions |
| **Sentry** | — | — | — | — | — | **Fora.** `grep -ril sentry` no repo retornou vazio, não há instrumentação. Seu próprio critério exclui |

Fora por decisão sua, registrado: Git MCP e Filesystem MCP (capacidade nativa equivalente), e qualquer MCP comunitário de CVM, B3, BCB, Cloudflare ou GitHub (o BCB respondeu direto por HTTP nesta sessão, é fonte oficial e não precisa de intermediário).

Princípio de menor privilégio a aplicar em todos: OAuth com o menor conjunto de escopos que satisfaz a função, preferência por escopo de leitura, e toda mutação exige aprovação explícita na sessão, nunca entra em allowlist. Nenhum dos MCPs propostos deve receber entrada em `permissions.allow`.

### 2.4 Contenção dos subagentes com shell

`permissionMode` no frontmatter do agente **não é garantia**. Quando o processo pai roda em modo auto, como é o caso aqui (`defaultMode: "auto"` no settings global), o `permissionMode` do subagente é ignorado e não impede a execução. Tratar `permissionMode: read-only` como contenção seria repetir o erro que a própria auditoria nomeou, confiar num rótulo que o sistema não apura.

A contenção real é hook `PreToolUse` deny-by-default. Proposta para `production-observer` e `gatekeeper`, com allowlist exata:

`production-observer` pode executar apenas:
```
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev*
curl.exe -s https://api.vixradar.com*
curl.exe -s https://vixradar.com*
```

`gatekeeper` pode executar apenas:
```
git status --short
git status
git diff --cached --name-status
git diff --cached -- <caminho>
git diff -- <caminho>
git rev-parse HEAD
git log --oneline -<n>
```

Tudo que não casar exatamente é negado, e a negação é o default, não a exceção. O hook precisa validar o comando completo, não prefixo, para não deixar passar encadeamento (`;`, `&&`, `|`, substituição de comando).

Alternativa de menor esforço e maior garantia, que eu recomendo considerar: retirar `Bash` dos dois. O `gatekeeper` perde pouco, a validação de allowlist pode ser feita pelo loop principal. O `production-observer` perde a função inteira, então para ele o hook é necessário se a função for desejada.

### 2.5 Higiene de permissões

Sem remover nada agora, o alvo é:

1. Projeto, prioridade máxima: remover as entradas estreitas que **sobrevivem em auto e carregam capacidade real**. São cinco regras de capacidade local, quatro de deploy mais uma de rotina (as duas de `deploy-pages.ps1`, com e sem curinga, as duas de `deploy-worker.ps1` em v4.9.166, e a de `run_vixradar_verificacao_async.ps1`), mais as três de MCP com capacidade de execução ou escrita (`mcp__sprite__exec_command`, `mcp__claude-in-chrome__browser_batch`, `mcp__Claude_Preview__preview_start`), mais as 21 com a chave morta. Executam sem passar por avaliação.
2. Projeto, higiene: remover os dois curingas amplos de execução (`npx wrangler:*` e `python -c ":*`, que caem em auto mas voltam a valer se o modo mudar) e o vazamento cruzado de domínios `WebFetch` e caminhos `Read` de outros projetos.
3. Global: revisar `allow: ["Edit","Write","Bash","PowerShell"]`. `Bash` e `PowerShell` caem em auto, então a correção é de formato, para o caso de a sessão sair de auto. `Edit` e `Write` não mudam o comportamento em auto, que já aprova edição normal no workspace e mantém proteção sobre caminho protegido. Baixa urgência, gate próprio junto com a do modelo (4.1).
4. Os dois curingas de Skill podem ficar, são redundância inofensiva. Removê-los é opcional.

---

## 3. Riscos

| # | Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|---|
| R1 | Remover `filesystem` quebra fluxo existente que dependa dele sem que se saiba | Média | Médio | Desabilitar antes de remover, operar uma semana, só então remover |
| R2 | Remover o Cloudflare comunitário quebra automação que use suas ferramentas | Média | Alto | Inventariar chamadas `mcp__cloudflare__*` no histórico antes, e só então desabilitar |
| R3 | Oito skills novas num contexto com 143 disponíveis pioram a descoberta | **Alta** | Médio | Atualizar `SKILLS-ROUTER.md` no mesmo commit, obrigatório, não opcional |
| R4 | OAuth dos MCPs Cloudflare adiciona um quarto destino de credencial | Alta | Médio | A rotação já tem histórico de destino esquecido (CI-003). Incluir os MCPs no checklist de `apply-security-rotation.ps1` |
| R5 | Hook `PreToolUse` mal escrito bloqueia trabalho legítimo ou deixa passar encadeamento | Média | Alto | Alimentar o hook com JSON sintético cobrindo `;`, `&&`, `\|`, `$()` e um caso legítimo, antes de ativar. Nunca com ferramenta real do outro lado |
| R6 | Playwright MCP baixa navegador, dependência pesada | Alta | Baixo | Aceitar ou adiar |
| R7 | GitHub MCP com PAT amplo demais | Média | Alto | Fine-grained, read-only, escopo de um repo, sem `workflow` |
| R8 | Cloudflare Builds dispara build sem intenção | Baixa | Alto | Não instalar até confirmar que o escopo OAuth separa leitura de disparo |
| R9 | Mexer no settings global quebra outros projetos do portfólio | Média | Alto | Gate próprio, backup datado, janela sem rotina agendada |

---

## 4. Ordem de execução

Nada nesta seção foi executado. A numeração é de dependência, não de urgência.

### 4.1 Fase 0, separada e com autorização própria

Duas mudanças em `~/.claude/settings.json`, que afetam **todos os projetos do portfólio** e por isso não pertencem à sequência do VIX Radar:

- **0a.** Remover `"model": "deepseek-v4-pro[1m]"`. Regressão ativa, já quebrou esta sessão três vezes, mesma família do incidente de 27/07.
- **0b.** Revisar `permissions.allow: ["Edit","Write","Bash","PowerShell"]` com `defaultMode: auto`. Prioridade menor que a 0a e que a Fase 1, porque `Bash` e `PowerShell` amplos são descartados em auto e `Edit`/`Write` não alteram o que a sessão já faz. É correção preventiva contra mudança de modo.

A 0a é pré-requisito técnico do resto: subagente novo criado enquanto o default aponta para modelo inacessível nasce inoperante. Se você não autorizar a Fase 0, a recomendação é **não criar os cinco subagentes**, porque não haverá como validá-los.

### 4.2 Fase 1, higiene do projeto

Limpeza de `.claude/settings.local.json` conforme 2.5 item 2. Não depende de nada, reduz superfície antes de adicionar componente.

### 4.3 Fase 2, MCPs, em duas etapas

Etapa A, adicionar os oficiais de baixo risco: Docs, Observability, Browser, Playwright, GitHub read-only. Operar e confirmar que cobrem o que o comunitário cobria.

Etapa B, só depois da A comprovada: desabilitar o Cloudflare comunitário e o `filesystem`. Desabilitar primeiro, remover depois de uma semana sem regressão.

### 4.4 Fase 3, skills

Oito skills mais atualização obrigatória do `SKILLS-ROUTER.md`. Nenhuma remoção das 14 sobrepostas, que são forks enriquecidos.

### 4.5 Fase 4, subagentes

Três sem shell primeiro. Os dois com shell só depois do hook `PreToolUse` escrito e testado.

### 4.6 Comandos de instalação, para referência, não executados

```bash
claude mcp add --transport http cloudflare-docs https://docs.mcp.cloudflare.com/mcp
claude mcp add --transport sse cloudflare-observability https://observability.mcp.cloudflare.com/sse
claude mcp add --transport sse cloudflare-browser https://browser.mcp.cloudflare.com/sse
claude mcp add playwright -- npx -y @playwright/mcp@latest
claude mcp add --transport http github https://api.githubcopilot.com/mcp
```

```bash
claude mcp remove filesystem
claude mcp remove cloudflare
```

O transporte de cada servidor Cloudflare deve ser confirmado na documentação oficial no momento da instalação, `http` e `sse` variam por servidor e por versão. As linhas de remoção estão aqui para completude do plano e não devem ser executadas antes da Etapa B da Fase 2.

---

## 5. Backup, rollback e testes

**Backup antes de cada fase:**

| Fase | Copiar para `.bak-AAAAMMDD` |
|---|---|
| 0 | `~/.claude/settings.json` |
| 1 | `.claude/settings.local.json` |
| 2 | saída de `claude mcp list` gravada em arquivo |
| 3 | `.claude/SKILLS-ROUTER.md` |
| 4 | diretório `.claude/agents/` |

Existe precedente de backup correto neste projeto, `settings.json.bak-20260727`, e ele é o que permite afirmar que o `model` DeepSeek é regressão e não estado antigo.

**Rollback por fase:** restaurar o arquivo do backup e reiniciar a sessão. Para MCP, `claude mcp add` com os parâmetros registrados na saída salva. Todo rollback é local e não toca produção do VIX Radar em nenhuma fase.

**Princípio de teste, vale para toda a bateria abaixo.**

> **A proteção nunca será testada provocando a ação que pretende impedir.**

Testar uma barreira de deploy tentando deployar, ou uma barreira de shell remoto tentando executar remotamente, faz da falha do teste exatamente o dano que ele deveria prevenir. Um teste que só é seguro quando passa não é teste, é aposta. Toda verificação de contenção aqui é estática (arquivo, schema, origem da regra) ou feita alimentando o hook com entrada sintética, nunca chamando o alvo real.

Isto corrige um erro de versão anterior deste documento, que propunha invocar cada regra estreita de capacidade para observar se pedia permissão. Se a regra tivesse sobrevivido, o "teste" teria feito deploy de produção.

**Testes de aceitação:**

| Fase | Teste | Critério |
|---|---|---|
| 0a | `claude -p --model claude-sonnet-4-6 "ok"` em shell limpo | exit 0 |
| 0a | Chamada de `WebFetch` numa URL pública | Retorna conteúdo, sem erro de modelo |
| 1 | Parse JSON e validação de schema de `settings.local.json` e `settings.json` | Válidos, sem chave desconhecida |
| 1 | `grep -c mXE26 .claude/settings.local.json` | 0 |
| 1 | Busca literal pelas cinco regras de capacidade local e pelas três de MCP removidas | Zero ocorrências |
| 1 | Busca pelas entradas `deny` correspondentes | Presentes, uma por regra removida |
| 1 | Reiniciar a sessão e conferir em `/permissions` a origem de cada regra que restou | Nenhuma regra de deploy, rotina ou execução remota listada, e a origem de cada uma restante é a esperada (projeto ou global) |
| 4 | Alimentar o hook `PreToolUse` com JSON sintético contendo comando de deploy | Exit de bloqueio |
| 4 | Idem com comando de shell remoto | Exit de bloqueio |
| 4 | Idem com encadeamento (`;`, `&&`, `\|`, `$()`) tentando escapar da allowlist | Exit de bloqueio |
| 4 | Idem com comando legítimo da allowlist | Exit de liberação, sem falso positivo |
| 2A | `claude mcp list` | Novos servidores conectados como MCP local, não como conector claude.ai |
| 2A | Observability retorna evento de telemetria real | Fecha a lacuna da auditoria |
| 2B | Rotinas do dia seguinte, execução já agendada e não provocada pelo teste | exit 0, sem dependência do MCP removido |
| 3 | Invocar cada skill nova | Carrega e o router aponta certo |

Em nenhum ponto desta bateria o script de deploy é chamado, `wrangler deploy` é executado ou o MCP remoto é acionado. Os testes de hook usam JSON sintético entregue ao hook diretamente, que é o mesmo caminho que o Claude Code usa, sem que exista ferramenta real do outro lado.

Os quatro testes de hook da Fase 4 são os que importam. Se o comando de deploy, o shell remoto ou o encadeamento passarem em vez de serem bloqueados, a contenção não existe e os agentes com shell não devem ser usados. O quarto está lá porque hook que bloqueia tudo também é hook quebrado, só que de um jeito que passa despercebido até alguém precisar trabalhar.

**Teste funcional real fica fora desta bateria.** Confirmar que um deploy ainda funciona depois da limpeza, ou que o MCP substituto cobre o caso de uso, é Gate C ou D separado, e exige alvo descartável ou modo dry-run comprovado antes de qualquer execução. Não é pré-requisito da Fase 1.

---

## 6. Gates de autorização

| Gate | Autoriza | Estado |
|---|---|---|
| A | Redigir os oito documentos da auditoria técnica | Executado em 28/07 |
| A' | Redigir este plano | Executado agora, nono caminho documental |
| **B** | Commit, push e PR dos documentos | **Bloqueado** |
| **C** | Alterar código, KV, calendário ou produção do VIX Radar | **Bloqueado** |
| **D** | Fases 1 a 4 deste plano, configuração local do Claude Code | **Bloqueado, não solicitado** |
| **E** | Fase 0, settings global, afeta todos os projetos | **Bloqueado, autorização separada de D** |

D e E são distintos de propósito. Autorizar a configuração deste projeto não autoriza mexer no global, e é o global que hoje roteia o modelo default para DeepSeek, além de manter uma allowlist em formato amplo que não tem efeito em auto mas passaria a ter em outro modo.

---

*Documento produzido em 2026-07-28. Inventário por leitura direta (`claude mcp list`, `claude auto-mode config`, `installed_plugins.json`, `settings.json`, `settings.local.json`, comparação byte a byte das skills). A semântica de permissões em modo auto (seção 1.6) segue a documentação oficial do Claude Code para a versão em uso, e não é observável nas saídas acima. A resolução efetiva de cada regra não foi comprovada programaticamente e não será comprovada por invocação, ver o princípio de teste da seção 5. Nenhuma configuração criada, alterada, habilitada, desabilitada ou removida. Nenhum staging.*
