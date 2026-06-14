# Protocolo Operacional Permanente

## Memória canônica

A memória canônica do projeto é o Obsidian Vault **interno ao projeto**:

`E:\Diretorio\Codex\Monitoramento de Credito\Obsidian VIX Radar\`

(Atualizado 2026-06-13 — projeto consolidado em E:\Diretorio\Codex\Monitoramento de Credito\. Vault antigo em C:\Projetos Codex\Codex\Sistema de Credito\VixRadar\ pode ser arquivado. Comece sempre lendo `Obsidian VIX Radar\00 - Índice (MOC).md`.)

## Regra central

Nunca deixar informação crítica apenas no chat.
Toda informação operacional relevante deve ser lida do Obsidian no início do trabalho e registrada no Obsidian ao final de cada etapa relevante.

## Leitura obrigatória no início

Antes de iniciar qualquer tarefa relevante:

1. Ler o contexto já existente no Obsidian
2. Identificar incidentes, decisões, deploys, pendências e estado atual do projeto
3. Tratar o Obsidian como fonte de verdade documental

## Escrita obrigatória ao final

Antes de encerrar qualquer tarefa relevante:

1. Atualizar o Obsidian
2. Registrar o que foi feito
3. Registrar evidências e impacto
4. Registrar pendências e próximo passo
5. Nunca encerrar sem gravação documental quando houver mudança relevante

## Escopo obrigatório de registro

Registrar sempre:

- incidentes
- correções
- decisões
- deploys
- validações
- pós-incidentes
- mudanças arquiteturais
- riscos
- pendências
- marcos
- aprendizados
- estado atual real de produção

## Campos mínimos obrigatórios

Para incidentes e mudanças críticas, registrar sempre:

- causa raiz confirmada
- evidência objetiva
- correção aplicada
- validação

Para deploys, registrar sempre:

- versão
- ambiente
- data e hora
- arquivos alterados
- evidência pública ou técnica de publicação

Para decisões, registrar sempre:

- contexto
- decisão tomada
- motivo
- impacto

Para pendências, registrar sempre:

- item pendente
- bloqueio
- próximo passo
- responsável, se aplicável

## Proibição

É proibido:

- deixar incidentes só no chat
- concluir deploy sem registro
- concluir correção sem validação documentada
- apagar histórico útil
- sobrescrever contexto sem preservar rastreabilidade

## Comportamento esperado

Ao receber qualquer tarefa complexa:

1. Consultar primeiro o Obsidian
2. Executar a tarefa
3. Registrar tudo no Obsidian
4. Só então considerar a etapa encerrada

## Regra de prioridade

Se houver conflito entre chat e Obsidian, tratar o Obsidian como memória documental principal, salvo evidência nova mais forte a ser registrada imediatamente.

Falha em ler no início ou gravar no final deve ser tratada como tarefa incompleta.

---

# Padrão operacional global

Precisão acima de velocidade.
Nunca inventar dados.
Todo número deve ter fonte e data.
Separar fatos verificáveis, interpretação da fonte e síntese crítica própria.
Se houver lacuna, criar seção "Lacunas e Próximos Passos".
Português do Brasil.
Tom executivo, direto e sem redundância.

REGRA PERMANENTE DE PÓS-EDIÇÃO

Após qualquer edição de código, configuração, deploy, endpoint, Worker, Pages, integração, timeout, provider, autenticação, KV, DO, frontend ou backend, é obrigatório executar auditoria completa antes de encerrar.

Nenhuma edição pode ser considerada concluída sem entregar exatamente estes quatro blocos:
1. Causa raiz confirmada
2. Evidência objetiva
3. Correção aplicada
4. Validação em produção

Proibições obrigatórias
Não encerrar com narrativa sem artefato bruto.
Não tratar arquivo local, hipótese, editor ou ZIP como prova.
Não assumir que Pages publicado implica Worker publicado.
Não afirmar correção sem teste real em produção.

REGRA PERMANENTE DE CSS (inviolável)

A tag `<strong>` no index.html NÃO PODE ter `color` definido em regra global. O `<strong>` deve SEMPRE herdar a cor do elemento pai. Regra correta: `strong, .text-strong, [class*="strong"] { font-weight: 600; }` sem propriedade `color`. Motivo: o tema dark premium usa dezenas de tons de cinza e cores contextuais (muted, accent, crit, rel). Um `color` global no `<strong>` sobrescreve todas essas heranças e cria texto branco brilhante onde deveria haver cinza discreto, quebrando a hierarquia visual e a confiabilidade do layout. Elementos específicos que precisam de cor no bold (`.ews-disclaimer strong`, `.com-author-label strong`, inline styles) já possuem override próprio e não dependem da regra global. Se precisar de negrito com cor específica em algum lugar novo, criar regra CSS com seletor específico, NUNCA alterar a regra global do `<strong>`.

REGRA PERMANENTE DE DADOS MULTI-SEMANA (inviolável)

Os endpoints `op=state`, `op=ews`, `briefing_executivo`, `historico_emissor` e `comparar` DEVEM usar `carregarEstadoMultiSemana(env, 5)` para cobrir as últimas 5 semanas ISO (~35 dias). NUNCA usar `carregarEstadoCompartilhado` com semana única nesses endpoints. Motivo: o estado compartilhado é particionado por semana ISO no KV (`radar:estado:YYYY-WNN`). Quando uma nova semana começa (toda segunda-feira), o estado da semana corrente está vazio até o cron rodar. Sem lookback multi-semana, o dashboard perde todos os eventos históricos, o EWS mostra zero alertas, e o briefing executivo reporta "sem eventos". Apenas `persistirResultadoCompartilhado` deve gravar na semana corrente (escrita sempre pontual).

REGRA PERMANENTE DE TELEMETRIA (inviolável)

O binding `RADAR_USAGE_EVENTS` (Analytics Engine) DEVE estar declarado no `wrangler.toml` como `[[analytics_engine_datasets]]` com `binding = "RADAR_USAGE_EVENTS"` e `dataset = "radar_usage_events"`. NUNCA remover este binding. Motivo: o `wrangler deploy` sobrescreve os bindings do dashboard com o que está no `.toml`. Se o binding não estiver declarado no `.toml`, todo deploy subsequente o remove silenciosamente, e a função `tel()` falha sem gravar nenhum evento de uso, login ou consulta. Isso cega o painel admin de Engajamento (Retenção, Heatmap, Ranking, Overview) sem nenhum alerta visível. A perda de telemetria de 06/04 a 13/04/2026 (7 dias) foi causada exatamente por isso. O health check GET / expõe `telemetria: true/false`. O `executarHealthCheckDiario` emite alerta CRITICO quando o binding está ausente. Endpoint admin `action=tel_test` gera evento sintético para validação pós-deploy.

Checklist obrigatório pós-deploy Worker (adicional ao checklist geral)
1. Health check GET / deve retornar `telemetria: true`.
2. `action=tel_test` com admin_senha deve retornar `binding_presente: true` e `write_result.ok: true`.
3. Após ~60s, `action=uso visao=debug` deve mostrar o evento `tel_test_sintetico` nos últimos 20.

Checklist obrigatório pós-edição
Validar sintaxe e consistência lógica.
Validar nomes, paths, dependências, efeitos colaterais e regressão.
Separar explicitamente arquivo local, artefato gerado, Pages publicado e Worker publicado.
Coletar evidência bruta de produção.
Executar teste final obrigatório em produção quando a mudança tocar Worker, Pages, timeout, provider, integração ou interface.

Teste padrão obrigatório (health check público — não requer auth):
curl -s https://radar-credito-api.prospects-intel.workers.dev -w "\nHTTP:%{http_code} TEMPO:%{time_total}s"
# Esperado: HTTP 200, {"ok":true,"telemetria":true,"kv":true,...}
# ATENÇÃO: POST anônimo retorna 401 desde v4.9.x — usar GET / para validar saúde do Worker

Sem esse ritual, a tarefa está incompleta.

---

# ARQUITETURA DE IA ATUAL (atualizado 2026-06-14)

> **ATENÇÃO:** A cascade OpenRouter → Gemini → Perplexity está **OBSOLETA desde v4.9.108**. Não está em uso operacional.

## Fluxo atual

| Caminho | Modelo | Trigger |
|---|---|---|
| Pulso manual (análise individual) | `claude-haiku-4-5-20251001` via Anthropic API | Usuário dispara no frontend |
| Cobertura em lote (103 emissores) | Claude Opus via Claude Code Scheduled Tasks | `vixradar-matinal` (13h BRT dias úteis, top_n:15) + `vixradar-noturno` (17h30 BRT diário, top_n:103) |

## Sobre OpenRouter / Gemini / Perplexity

Referências a esses providers no bundle (`api/v4.9.109.js`), no health check `GET /`, ou em variáveis de ambiente no dashboard Cloudflare são **resíduos técnicos/históricos**. O health check pode reportar campos `openrouter`, `gemini`, `perplexity` como parte do schema herdado — isso não significa que estão em uso.

**Regra:** NUNCA reativar a cascade antiga (OR → Gemini → Perplexity) sem decisão explícita registrada no Obsidian (`Obsidian VIX Radar/03 - Estado de Produção.md`). A remoção foi motivada por saldo negativo do OpenRouter e pela decisão de consolidar em Claude como único provider de IA.

---

# ATUALIZAÇÃO 2026-06-01 — Auditoria completa + reconciliação de drift

> **Auditoria completa do site.** Confirmado via produção ao vivo + fetch do código via Cloudflare MCP.

## Versões reais de produção (confirmadas 2026-06-01)
| Componente | Versão | Evidência |
|---|---|---|
| Worker `radar-credito-api` | **v4.9.100** | `WORKER_VERSAO = "v4.9.100"` (linha 3486); `GET /` HTTP 200 |
| Frontend `vixradar.com` | **v201.43** | `version.json` deploy 2026-05-18; `CACHE_VERSION="v201.43"` |

## Achados e ações
1. **Drift de source control (reincidência) — RECONCILIADO.** Produção estava à frente do repo (Worker v4.9.100 vs `v4.9.99.js` não commitado; frontend v201.43 vs `index.html` v201.19). Ações: recuperado bundle do Worker via Cloudflare MCP → `worker/v4.9.100.js`; frontend v201.43 promovido para `index.html` (raiz + `deploy_zip`); `wrangler.toml main = "v4.9.100.js"`. Snapshot bruto em `_recuperacao_producao_2026-06-01/`. **`worker/v4.9.100.js` é o BUNDLE deployado, não fonte hand-authored.**
2. **Endpoint de análise exige JWT.** `POST /` → 401 `Autenticação necessária`. O teste padrão anônimo deste AGENTS.md (esperava HTTP 200) está **SUPERADO**. Validação end-to-end do cascade exige token autenticado.
3. **Headers de segurança.** Adicionados ao `_headers` (HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy). **CSP deliberadamente omitida** (HTML monolítico com scripts inline; quebraria o app sem teste em staging). Deploy do Pages PENDENTE de autorização.
4. **OK:** CORS allowlist correto, telemetria ativa, 3/3 providers, KV/DO up.

---

# ATUALIZAÇÃO 2026-05-07 — Estado atual de produção

> **Drift recuperado após 23 dias.** Repo Git ficou em v4.8.7 entre 14/04 e 06/05/2026. Sessão 2026-05-07 (`e3f1f9ce`) pushou v4.9.65 → v4.9.69 (commit `da7c3cb`) + workflow CI canonical-test (commits `8d96b72` e `a4cd065`). Bloco abaixo "(source of truth, 11/04/2026)" está **superado** mas mantido para histórico — leia esta atualização primeiro.

## Versões em produção (confirmadas 2026-05-07)

| Componente | Versão | Version ID / deploy | Notas |
|---|---|---|---|
| Worker `radar-credito-api.prospects-intel.workers.dev` | **v4.9.69** | `ea16b6aa-83f2-4510-9236-9412906d6152` (2026-05-07T03:35Z) | Matcher ANBIMA refatorado. Validação manual sync ANBIMA: 73 empresas (vs 66 com v4.9.68 = +7 emissores recuperados). Cascade 9 rodadas (R1-R8 + R4b). 5 classes de instrumento no payload (`instrumentos_ativos: [debenture, cri, cra, lf, fidc]`). |
| Frontend `vixradar.com` (Cloudflare Pages) | **v201.19** | 2026-05-06T19:53:18Z | `version.json` confirmado em produção. |

## Cron triggers ativos (confirmados via API CF 2026-05-07T07:14Z)

| Cron | UTC | BRT | Função |
|---|---|---|---|
| `30 15 * * 1-5` | 12:30 | 09:30 | Matinal dias úteis (sync_cvm + recalc + matinal + saldo) |
| `30 21 * * *` | 18:30 | 15:30 | Noturno diário (sync_cvm + recalc + sync_anbima + batch + newsletter + saldo + healthcheck) |
| `0 1 * * *` | 22:00 | 19:00 | Watchdog diário |
| `0 2 * * *` | 23:00 | 20:00 | Cron adicional (propósito a confirmar com operador) |

Triggers agora versionados em `worker/wrangler.toml` (`[triggers] crons = [...]`) — defesa em profundidade conforme regra inviolável de Telemetria do AGENTS.md.

## Roadmap v4.9.69 → v4.9.72

| Versão | Status | Escopo |
|---|---|---|
| v4.9.69-A | **DEPLOYADO 2026-05-07** | Matcher ANBIMA refatorado. SYNC_ALIAS_TO_EMPRESA expandido (14→100+), TOKENS_ROBUSTOS_ANBIMA, invariante de nome canônico, log `anbima:matching_quality:{data}`, dimensão `cobertura_anbima_matching` em observabilidade. |
| v4.9.69-B | **AUTORIZADO 2026-05-07** | B3 Boletim Diário público (BDI) + ANBIMA Taxas CRI/CRA HTML para CRI/CRA/LF (parcial). Fonte gratuita confirmada após pesquisa. UP2DATA pago descartado. ANBIMA Data API Sensedia descartada. |
| v4.9.70 | Pendente | Cron paralelo B3 BDI gravando em chave KV separada |
| v4.9.71 | Pendente | Schema KV `serie:v2:{empresa}` multi-instrumento |
| v4.9.72 | Pendente | Recalibração de anomalias por classe |

## Camadas multi-fonte — premissa atualizada

| Premissa anterior | Realidade descoberta 2026-05-07 |
|---|---|
| Pipeline Python local `src/ingestion/snd_context.py` cobre SND e duplica trabalho | **NÃO existe no repo** (`git log --all --full-history` confirma 0 commits). Provavelmente desenvolvido em outra máquina sem commit. Memórias `project_snd_*` foram marcadas `PREMISSA_INVALIDADA`. |
| ANBIMA Data API Sensedia é caminho disponível | Bloqueada há 26+ dias aguardando ativação. Operador descartou. |
| B3 UP2DATA é fonte natural de CRI/CRA/LF | É **serviço comercial pago** (Política Comercial 2.4.1). Operador escolheu alternativa gratuita: B3 BDI + ANBIMA Taxas. |
| 36 emissores frozen são "falta de fontes" | **28% (10/36)** são problema de matcher (recuperados em v4.9.69-A). 26 são genuinamente sem debênture (esperam v4.9.69-B). |

## Memória institucional

- **Vault Obsidian (canônico, interno):** `E:\Diretorio\Codex\Monitoramento de Credito\Obsidian VIX Radar\` — 7 notas: 00 Índice, 01 Jornada, 02 Organograma/Arquitetura, 03 Estado de Produção, 04 Versões do Worker, 05 Consolidação, 06 Inventário. Inclui `_contexto_usuario\yan-master.md`.
- **Histórico de sessões:** `E:\Diretorio\Codex\Monitoramento de Credito\_historico\` (gitignored).
- **Arquivo morto (reversível):** `D:\Diretorio\_ARQUIVO_MORTO_VIXRADAR_2026-05-29\` — clone git original, snapshot antigo, 9 pastas de sessão órfãs, e quarentena de segredos/PII (fora do git).
- **CI:** `.github/workflows/canonical-test.yml` ativo, valida `EXPECTED_WORKER` a cada 6h (atualizar p/ `4.9.99`).
- ⚠️ **Caminhos antigos `C:\Users\szuch\...` / `C:\Projetos Codex\...` estão MORTOS** — projeto consolidado em `E:\Diretorio\Codex\Monitoramento de Credito\`.

---

# Estado atual e próximo trabalho (source of truth, 11/04/2026 — SUPERADO 2026-05-07)

Bloco preservado para histórico. **Ver atualização acima para estado real de produção.**

## 1. Versões em produção (confirmadas 13/04/2026)

| Componente | Versão em prod | Version ID / deploy_at | Validação |
|------------|----------------|------------------------|-----------|
| Worker `radar-credito-api.prospects-intel.workers.dev` | **v4.8.4** | `ed5e22ee-8b0b-4e28-9a04-9125e443e304` (2026-04-13) | Dual-cron: matinal 12h30 BRT (top N por EWS, dias úteis) + noturno 18h30 BRT (100 emissores). Endpoint admin_executar_matinal. |
| Frontend `vixradar.com` (Cloudflare Pages) | **v132** | `version.json` com `deployed_at: 2026-04-13T12:25:14Z` | Removido color global do strong (fix texto branco). |

Qualquer referência a versões diferentes disso em docs Manus ou arquivos legados está errada.

**Stack de versões intermediárias desta sessão (11/04/2026), todas deployadas.**

| Worker | Feature |
|--------|---------|
| v4.6.3 | `listarUsuarios` reescrita para scan prefix `user:*` corrigindo bug do painel admin |
| v4.6.4 | `listarUsuarios` recebe `sem_cache: true` para forçar scan bypassando cache agregado |
| v4.6.5 | Endpoint admin `comentario_remover` com auth JWT, delete da chave `comentario:{empresa}:{ts}`, audit trail em `audit:comentario_remover:*` TTL 1 ano |
| v4.7.0 | Infra multi-tenant. `DEFAULT_TENANTS` com `vix_core` (features `[favoritos]`) e `mirabaud` (features `[favoritos, ews_filter]`). `TENANT_DOMAIN_MAP` resolve tenant pelo domínio do email no registro. `handleLogin` devolve `tenant_config`. JWT payload carrega `tenant`. Endpoint admin `tenant_config_get` para inspeção |
| v4.7.1 | `handleFavoritoListar` e `handleFavoritoToggle`. **Doc único por usuário** (`kvUserFavoritosKey` → `user_favoritos:{email}`), JSON array ordenado. `emailAut` vem exclusivamente do JWT, nunca do body, garantindo isolamento. Feature gate via `userHasFeature` |
| v4.7.2 | **Tentativa com KV falhou.** Rate limit v2 sliding window em doc único `rl:v2:u:{email}` ou `rl:v2:ip:{ip}`. Código corretíssimo na lógica mas read-modify-write em KV sofreu race condition sob requisições sequenciais rápidas. Mantido no repo para referência histórica; substituído por v4.7.3 antes de entrar em uso real |
| v4.7.3 | **Rate limit v2 definitivo via Durable Object.** Classe `RateLimiterDO` (SQLite-backed por exigência do free plan) com rotas internas `POST /check` e `GET /inspect`. `checkRateLimitV2` delega ao DO via `idFromName(identidade)`, que serializa requests por key e garante atomicidade. Endpoint público `GET ?action=rl_inspect` permite observar o próprio estado sem novo deploy. Headers IETF `X-RateLimit-Limit/Remaining/Reset` + `Retry-After` injetados no 429. Fail-open com flag `_bypass` se o DO estiver indisponível |
| v4.7.5 | Janelas de eventos ampliadas de 7 para 30 dias. `executarHealthCheckDiario` referenciado mas não implementado. Versão intermediária no repo, não chegou a produção sozinha |
| v4.8.0 | **Enrichment Layer + Intelligence Endpoints.** `enriquecerEvento()` adiciona bloco `_enriquecimento` (materialidade 0-100, confiança, playbook, cadeia causal, setor_criticidade) a cada evento. `enriquecerPayload()` ordena por materialidade desc e adiciona `_qualidade_sinal` (provider, tempo_ms, confianca_media, materialidade_max). 3 novos endpoints GET com JWT: `op=briefing_executivo` (top 10 materialidade, distribuição setorial, EWS, CVM), `op=historico_emissor&empresa=X` (memória completa do emissor com eventos enriquecidos, análise privada, comentários, anomalias, EWS, séries), `op=comparar&empresas=A,B,C` (side-by-side até 5 emissores). `executarHealthCheckDiario(env)` implementado (bindings, circuit breakers, estado semanal, saldos). Cascade e batch persistem `setor` no payload para enriquecimento posterior. Todos os campos novos usam prefixo `_` (backward compatible) |
| v4.8.3 | **Newsletter KV-only + salvar_prefs server-side + List-Unsubscribe + SPF fix.** Newsletter consome `carregarEstadoMultiSemana(env, 2)` em vez de cascade AI duplicada. `handleSalvarPrefs` persiste prefs em `user_prefs:{email}`. `enviarResend` injeta Reply-To, Precedence, X-Entity-Ref-ID e List-Unsubscribe. SPF atualizado com `include:send.resend.com`. |
| v4.8.4 | **Dual-cron: varredura matinal inteligente.** Segundo cron `30 15 * * 1-5` (12h30 BRT, dias úteis). `selecionarEmissoresPrioritarios` rankeia 100 emissores por `score_combinado = EWS*0.6 + materialidade_max*0.4`, top 30 com filtro score > 0. `executarVarreduraMatinal` roda cascade AI só nos prioritários. Pula feriados/fins de semana via `ehDiaPregaoB3`. Endpoint admin `admin_executar_matinal`. Resultado em KV `admin:ultimo_matinal`. |

**Arquitetura multi-tenant por feature flags.** Decisão de produto: um único código base serve VIX Radar e Mirabaud. Nenhum fork, nenhum subdomínio separado. A diferenciação é feita pela feature flag `tenant_config.features`, resolvida no momento do login a partir do email do usuário. Para o tenant `mirabaud` (domínios `mirabaud.com` e `mirabaud.ch`), features adicionais podem ser habilitadas sem afetar usuários de `vix_core`. Favoritos foi a primeira feature desenhada sob este modelo, habilitada nos dois tenants por decisão explícita ("bote favoritos para todo mundo"). Ver `worker/v4.7.0.js` linhas 32-80.

**Privacy by design dos favoritos.** JWT é a única fonte de identidade. Nenhum endpoint aceita email no body. Read e write usam a chave do próprio usuário, impossibilitando cross-user leakage, inclusive para admin (admin continua vendo apenas seus próprios favoritos). Filtro opt-in "Meus Favoritos" no painel de Configurações do frontend fica salvo em `localStorage` com chave por email (`radar_filtro_favoritos:{email}`), não contamina outras contas no mesmo browser.

## 2. Pendências Manus Fase 1 e Fase 2 já resolvidas nas sessões Cowork

Parte relevante do backlog dos documentos Manus já foi entregue e publicada em produção através das sessões de Cowork. Os docs originais do Manus não foram atualizados, portanto não refletem este progresso.

Itens resolvidos e em produção (data de resolução).

- **Fix CORS para `www.vixradar.com`** (10/04/2026). Dual-host topology, Worker aceita tanto apex quanto www. Page Rule revertida. Memória `feedback_cors_www_vixradar.md`.
- **Notificação WhatsApp de novos cadastros via Twilio Sandbox** (10/04/2026). Função `enviarWhatsAppAdmin()` no Worker v4.5.2. Latência ~1s.
- **Long-press no logo para acesso admin mobile** (10/04/2026, v109). 700ms com tolerância de 10px, vibração tátil.
- **Fix mobile header scroll horizontal** (10/04/2026, v109). `touch-action: pan-x` e scroll-snap no `#top-right`.
- **Sistema de auto-update cliente** (10/04/2026, v108). Polling de `version.json`, banner dourado, reload com cache-buster.
- **Fix privacidade emails via BCC** (09/04/2026, Worker v4.5.1). `to: boletim@` + `bcc: destArray`.
- **Fix aba Engajamento no Painel Admin** (10/04/2026, v107). Coerção `Number()` corrigindo concatenação de strings e comparação lexicográfica.
- **Disclaimer financeiro permanente e cookie banner LGPD** (10/04/2026, v106).
- **Remoção do admin_key auto-login e do bloqueio de devtools** (09/04/2026, v101). Teatro de segurança eliminado.
- **Dashboard Market Overview com setores clicáveis** (09/04/2026, v100-v102c).

Pendências Manus ainda em aberto estão listadas em `.auto-memory/pendencias_operacionais_2026_04.md`. Resumo: DNS Resend, preferências de notificação no Worker (persistência server-side), CNPJ formal para disclaimer, nomeação de DPO, backup KV automatizado.

## 3. Próximo trabalho. Risk Budgeting Layer 1 e Layer 2

A próxima frente de desenvolvimento não é continuação do backlog Manus, é uma funcionalidade nova motivada pelo paper Bruder e Roncalli (2012). O escopo e a matemática completa estão no spec abaixo.

**Documento de referência obrigatório.**
`specs/SPEC_Layer1_Layer2_RiskBudgeting_v1.docx`

Resumo das decisões confirmadas.

- **Layer 1.** Carteira ERC de Referência sobre os 100 emissores do universo Radar. Atualizada mensalmente no último pregão B3 via cron. Covariância por Ledoit-Wolf shrinkage com alvo constant correlation. Volatilidade ex-ante via DTS (Ben Dor et al 2007) quando série histórica for curta. Multiplicador idiossincrático calibrado em base 2018-2023 do IDA-DI, holdout 2024-2026 no ARQUIVO_PRE.
- **Layer 2.** Decomposição de Euler da carteira real do usuário. Upload XLSX ou CSV. Retorna contribuição percentual de risco por emissor, setor e rating. Alerta dispara quando qualquer emissor concentra mais de 10% do risco total (threshold de gestor profissional de fundo de crédito, não family office).
- **Layer 3.** Fora de escopo nesta versão por CVM 175. Layer 1 e 2 são descritivas, não prescritivas.

**Versões alvo do deploy.**

| Componente | Versão alvo | Principais adições |
|------------|-------------|--------------------|
| Worker | **v4.7.0** | Ledoit-Wolf JS, ERC solver JS, endpoint `/api/layer1/erc`, endpoint `/api/layer2/decompor`, cron mensal último pregão |
| Frontend | **v110** | Aba "Carteira ERC de Referência" com comparação IDA-DI, tela de upload Layer 2 com waterfall e heatmap |

**Estado da Fase 0.5 (preparatória, 11/04/2026).** Concluída e em produção como **v4.6.2**. Patch cirúrgico com 3 correções infraestruturais (slice 252, schema com `duration`, FERIADOS_B3_2027) que removem bloqueios estruturais mapeados em `auditorias/AUDITORIA_DADOS_LAYER1_2026-04-10.md`. **Fase 1 (Ledoit-Wolf JS) bloqueada até o KV ter dados reais** — aguardando resposta da ANBIMA ao pedido de credencial produção.

**Stack de implementação.** JavaScript ES6 no Worker. **Álgebra linear em JS puro (`Float64Array`) por default** — para n=100 a matriz de covariância é 100×100 e é trivialmente tratável sem dep externa. A primeira tarefa da Fase 1 é um benchmark protótipo puro antes de decidir sobre qualquer lib npm; `ml-matrix` só entra com justificativa numérica (latência, legibilidade), dado o orçamento de bundle e cold start do Cloudflare Worker. Validação numérica contra scripts Python de referência das skills `diversification` (PortfolioAnalyzer) e `asset-allocation` (RiskParity) em `.Codex/skills/`. Tolerância de comparação 1e-6.

**Cronograma estimado.** 11 dias úteis, distribuídos em 8 fases descritas no spec. Item de maior risco é Ledoit-Wolf em JS (implementação manual, ~50 linhas, sem biblioteca npm equivalente).

**Protocolo de deploy.** O mesmo protocolo do projeto. Diagnóstico único completo antes de executar, validação em produção com o curl padrão (`--max-time 120`, `-w "TEMPO: %{time_total}s | HTTP: %{http_code}"`), proibido iterar por tentativa e erro.

---

# Deploy do Frontend (Cloudflare Pages)

> **Referência completa e atualizada em Obsidian.** Ver `Obsidian Vault/VIX Radar - Deploy Cloudflare Pages.md`. A nota documenta onde mora o token (variáveis de ambiente do Windows na máquina do usuário, NUNCA no sandbox), comando PowerShell pronto, script de build do deploy_zip, validação pós-deploy e histórico de tokens revogados. **Consultar essa nota antes de pedir credenciais ao usuário.**

## Versão atual em produção: v112 (deploy 10/04/2026 19:25 UTC)

**Fonte de verdade:** `index.html` na raiz do projeto. O `deploy_zip/` é gerado a partir dele pelo script abaixo. Se a raiz e o deploy_zip divergirem, **a raiz vence** — sincronizar antes de deployar para não regredir produção.

## Worker em produção: v4.8.0

## Comando de deploy via API Token
```bash
# Token e Account ID devem estar configurados como variáveis de ambiente do sistema.
# NUNCA hardcode tokens em arquivos do repositório.
# Configurar via: export CLOUDFLARE_API_TOKEN=<novo-token> e export CLOUDFLARE_ACCOUNT_ID=<account-id>
npx wrangler pages deploy ./deploy_zip --project-name=radar-credito --branch=main
```

**CLOUDFLARE_ACCOUNT_ID é obrigatório.** Sem ele, o wrangler tenta GET /memberships que falha com tokens de escopo limitado. Com o Account ID explícito, essa chamada é pulada.

## Token ativo
- **Token anterior foi comprometido (exposto em repositório) e deve ser rotacionado.**
- Rotacionar em: https://dash.cloudflare.com/profile/api-tokens
- ID do token antigo (para revogar): `a49f56bfd7dc2d172ad19fa902c9594d`
- Escopos necessários: Pages Edit, Workers Scripts Read/Edit, Account Settings Read, User Details Read
- Após rotação, configurar como variável de ambiente do sistema (nunca em arquivo)

## Permissões mínimas do token
- Account > Cloudflare Pages > Edit
- Account > Account Settings > Read
- User > User Details > Read

## Deploy do Pages (4 arquivos, SEMPRE)
```
index.html    (~450 KB)
_headers      (no-cache em /, /index.html, /version.json, /api/*)
_routes.json  (57 bytes, routing config)
version.json  (gerado automaticamente a partir do CACHE_VERSION)
```

**CRÍTICO:** O `version.json` DEVE ser regenerado a cada deploy com a versão atual. Se ele ficar desatualizado, o detector de auto-update no cliente não vai disparar e os usuários continuarão vendo a versão antiga até fazerem Ctrl+Shift+R.

## Script de build do deploy_zip (copiar e colar)
```bash
cd "/sessions/clever-cool-ride/mnt/Sistema de monitoramento de crédito com IA"
cp -f index.html deploy_zip/index.html
cp -f _headers deploy_zip/_headers
cp -f _routes.json deploy_zip/_routes.json
VER=$(grep -oP "const CACHE_VERSION = '\K[^']+" index.html | head -1)
printf '{"version":"%s","deployed_at":"%s"}\n' "$VER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > deploy_zip/version.json
```

## Sistema de auto-update no cliente (v108+)
Detector implementado no final do `index.html` (IIFE `autoUpdateDetector`) que:
1. Faz polling de `/version.json` a cada 3 minutos
2. Verifica também no retorno da aba (visibilitychange) e no bfcache (pageshow)
3. Quando detecta versão diferente, mostra banner dourado no topo com countdown de 5 min
4. Botões: "Atualizar agora" (reload imediato) e "Depois" (adia 10 min)
5. Após 5 min sem ação, recarrega automaticamente com cache-buster (`?_v=timestamp`)

Nenhum usuário precisa mais apertar Ctrl+Shift+R. A nova versão chega sozinha em no máximo 3 minutos.

## Validação pós-deploy (obrigatória)
```bash
# 1. Versão do HTML
curl -s https://vixradar.com | grep -o "CACHE_VERSION = '[^']*'"
# Esperado: CACHE_VERSION = 'v112'

# 2. Endpoint de versão
curl -s https://vixradar.com/version.json
# Esperado: {"version":"v112","deployed_at":"..."}

# 3. Headers anti-cache no version.json
curl -sI https://vixradar.com/version.json | grep -i cache-control
# Esperado: cache-control: no-cache, no-store, must-revalidate
```

---

# Mudanças Worker v4.8.3 → v4.8.4 (13/04/2026)

**Dual-cron: varredura matinal inteligente por prioridade EWS.**

1. **Segundo cron `30 15 * * 1-5` (12h30 BRT, seg a sex).** O `scheduled()` detecta qual cron disparou via `event.scheduledTime` (hora UTC 15 = matinal, 21 = noturno) e roteia para a função correta.
2. **`selecionarEmissoresPrioritarios(env, topN)`** carrega estado multi-semana (5 semanas) + anomalias, calcula EWS para os 100 emissores, gera `score_combinado = EWS * 0.6 + materialidade_max * 0.4`, ordena desc e retorna top N. Emissores com score zero são filtrados.
3. **`executarVarreduraMatinal(env)`** executa a cascade AI apenas nos emissores prioritários. Verifica `ehDiaPregaoB3()` no início, pula silenciosamente em feriados e fins de semana. Flag `_matinal: true` no payload persistido. Resultado gravado em KV `admin:ultimo_matinal` com TTL 48h.
4. **Cron matinal executa:** `syncCVMAutomatico` → `recalcularTodasAnomalias` → `executarVarreduraMatinal` → `verificarSaldoProviders`. Sem newsletter e sem sync ANBIMA (reservados para o noturno).
5. **Cron noturno mantém:** pipeline completo original (100 emissores) + newsletter + health check diário + sync ANBIMA.
6. **Endpoint admin `admin_executar_matinal`** para disparo manual com `admin_senha`.
7. **Constantes:** `MATINAL_TOP_N = 30` (cap máximo), `MATINAL_EWS_MINIMO = 0` (corte mínimo de score).

**Validação em produção (13/04/2026).** Matinal via admin: 11 emissores prioritários selecionados (score > 0), 11 sucesso, 0 falha, 83.8s. Top 3: Energisa (EWS 32), Embraer (22), Aegea (22). Health check OK (7 bindings true). Teste padrão Auren HTTP 200 em 5.91s.

Version ID: `ed5e22ee-8b0b-4e28-9a04-9125e443e304`. Crons ativos: `30 15 * * 1-5` + `30 21 * * *`.

---

# Mudanças Worker v4.7.3 → v4.8.0 (12/04/2026)

**Enrichment Layer e Intelligence Endpoints.** Backend-only, sem mudança no frontend. Todos os campos novos usam prefixo `_` e são aditivos, o frontend existente os ignora sem quebrar.

1. **Enrichment Layer (`enriquecerEvento`, `enriquecerPayload`).** Pós-processamento de cada evento da cascade AI. Adiciona bloco `_enriquecimento` com: `materialidade` (0-100, calculada por `MATERIALIDADE_POR_TAG` × `CRITICIDADE_SETOR` × multiplicador de classificação), `confianca` (herdada do verificador ou 0.5 default), `playbook_tipo` e `playbook_acoes` (ações de monitoramento recomendadas por tag, ex: rating → "Verificar outlook completo", "Comparar com pares"), `cadeia_causal` (inferida da tag), `setor_criticidade` (peso do setor, Bancos 0.95, Tech 0.6). `enriquecerPayload` ordena eventos por materialidade desc e adiciona `_qualidade_sinal` (provider, tempo_ms, eventos_total, eventos_verificados, confianca_media, materialidade_max).
2. **`op=briefing_executivo` (GET, JWT).** Agrega estado semanal de todos os emissores no KV, enriquece eventos, retorna: top 10 por materialidade, distribuição setorial (quantas empresas, quantos eventos críticos/relevantes por setor), resumo EWS (anomalias ativas), contagem de docs CVM sincronizados.
3. **`op=historico_emissor&empresa=X` (GET, JWT).** Memória completa do emissor: eventos da semana (enriquecidos), análise privada do usuário, comentários, anomalias, score EWS, resumo de séries históricas (última data, total registros), cache de último resort.
4. **`op=comparar&empresas=A,B,C` (GET, JWT).** Side-by-side de até 5 emissores com: eventos da semana, materialidade máxima, anomalias ativas, score EWS. Para construção futura de dashboards comparativos.
5. **`executarHealthCheckDiario(env)` implementado.** v4.7.5 declarava a chamada no cron mas a função não existia. Agora verifica: bindings (RADAR_KV, RATE_LIMITER_DO, secrets), circuit breakers ativos, estado semanal (total emissores com dados, mais recente), saldos via `verificarSaldoProviders`. Grava resultado em KV `admin:healthcheck:diario` com TTL 48h.
6. **Cascade e batch persistem `setor` no payload.** `saneado.setor = setor` injetado em 3 pontos (cascade principal, guard confirmation, batch cron) para que o enriquecimento posterior encontre o setor do emissor.
7. **Constantes de materialidade.** `MATERIALIDADE_POR_TAG` (10 tags, rating=90, mercado=45), `CRITICIDADE_SETOR` (13 setores, Bancos=0.95, Tech=0.6), `PLAYBOOKS` (10 tipos com 4-5 ações cada).

Version ID: `baaa7a1e-506d-41c8-9f5d-34183040699a`. Base: v4.7.5.js + ~370 linhas novas. Deploy via `wrangler.toml` apontando `main = "v4.8.0.js"`. Validação: health check OK (5 serviços true), análise Auren HTTP 200 em 6.99s com `_enriquecimento` e `_qualidade_sinal` presentes, `briefing_executivo` HTTP 200 em 0.43s, `historico_emissor` HTTP 200, `comparar` HTTP 200.

---

# Mudanças v111 → v112 (10/04/2026 19:25 UTC)

Renomeação semântica e refino visual do fluxo de monitoramento manual. **Sem mudança de comportamento ou endpoint** — só linguagem e CSS do botão principal.

1. **Renomeação "Varredura" → "Pulso" em toda a UI do emissor.** Botão principal `⚙ Varredura…` → `⚙ Novo Pulso…` (linha ~2039). Modal `⚡ Configurar Varredura` → `⚡ Novo Pulso` com subtítulo "Leitura instantânea do emissor selecionado" (linha ~6093). Estados de loading/erro/empty no painel do emissor: "Aguardando varredura" → "Aguardando pulso", "Sinais desta varredura" → "Sinais deste pulso", "Varredura privada" → "Pulso privado", `Minha Varredura` → `Meu Pulso`, etc.
2. **Mensagem de cron atualizada:** "varredura completa é automática (8h e 19h)" → "pulso completo é automático (18h30 BRT, pós-fechamento B3)". Reflete o cron real do Worker (`30 21 * * *` UTC = 18h30 BRT).
3. **Botão "Capturar Pulso" com estilo refinado:** padding 12px, font 13px peso 800, uppercase, box-shadow dourada, hover com elevação. Antes era `⚡ Iniciar Monitoramento`.
4. **Empty-state do emissor selecionado redesenhado:** card com border-left colorido pelo setor, badge `◆ {SETOR}` em uppercase, nome do emissor destacado. Antes era texto plano `Empresa selecionada: ...`.
5. **METRICAS_CURADAS notas:** "Varredura completa." → "Pulso completo." em duas entradas (Sabesp BB-BI, evento CVM RAD).
6. **CACHE_VERSION:** v111 → v112.

---

# Mudanças v110 → v111 (10/04/2026)

Remoção definitiva do seletor de escopo da UI. **Decisão de produto:** o usuário só dispara análise por emissor individual; varredura completa de todas as empresas roda exclusivamente via cron noturno.

1. **Removida UI de "scope tabs"** ("Esta empresa | Por setor | Todas · auto ⏰") do modal Novo Pulso. O modal sempre opera no modo `empresa`.
2. **Variável `setoresSelecionados` removida** e função `toggleSetor()` deletada. Estado simplificado para sempre `scopeMode = 'empresa'`.
3. **`renderEscopo()` simplificada:** só dois ramos — "emissor selecionado" (card colorido) ou "nenhum emissor selecionado" (alerta vermelho pedindo seleção na sidebar).
4. **`contarEmpresasSelecionadas()` reduzida** para `return selecionada ? 1 : 0`.
5. **`executarVarreduraSelecionada()` simplificada:** `const empresas = selecionada ? [selecionada] : [];` (antes era branch por modo).
6. **CACHE_VERSION:** v110 → v111.

---

# Mudanças v109 → v110 (10/04/2026)

Primeiro passo da remoção do seletor de escopo. Comentário no código: *"v110: removido seletor de setor. O usuário só dispara varredura por emissor individual. Varredura completa de todas as empresas roda automaticamente 1x/dia às 18h30 BRT."*

1. **Removida lógica multi-empresa do scopeMode "setores"** em `renderEscopo`/`executarVarreduraSelecionada`. Setores deixaram de ser acionáveis manualmente.
2. **Cron único noturno** assumido como única fonte de varredura completa. UI ainda mostrava as três tabs (a remoção visual veio em v111).
3. **CACHE_VERSION:** v109 → v110.

---

# Mudanças v108 → v109 (10/04/2026)

1. **Fix mobile header scroll horizontal:** O `#topbar` mobile (max-width 768px) virou `display: flex`. O `#top-right` recebeu `flex: 1 1 0`, `min-width: 0`, `overflow-x: auto`, `touch-action: pan-x`, `-webkit-overflow-scrolling: touch`, scrollbar escondida e `scroll-snap-type: x proximity`. Agora os botões Relatório PDF, Configurações e Sair deslizam lateralmente com o dedo quando não cabem todos na tela.
2. **Long-press no logo para acesso admin mobile:** Antes só havia `Ctrl+Shift+A` (teclado), inacessível no celular. Adicionado handler IIFE dentro do módulo admin que detecta touch/mouse press de 700ms no `#topbar .logo`. Tolerância de 10px de movimento (evita disparo em scrolls acidentais). Vibração tátil de 40ms se disponível. Reusa `abrirAdmin()`/`fecharAdmin()`. Título do logo: "Pressione e segure para abrir o painel admin".
3. **CACHE_VERSION:** v108 → v109.

**Validação em produção v109:** HTTP 200, version.json `{"version":"v109","deployed_at":"2026-04-10T16:16:26Z"}`, Cache-Control `no-cache, no-store, must-revalidate`, 4 ocorrências de `longPressFired` no HTML, 1 ocorrência de `touch-action: pan-x`, teste end-to-end de cadastro + notificação WhatsApp + aprovação pelo celular validado com usuário real (+55 21 98108-8992).

---

# Mudanças v107 → v108 (10/04/2026)

1. **Sistema de auto-update do cliente:** Usuários não precisam mais apertar Ctrl+Shift+R ao publicar nova versão. Implementado detector (IIFE `autoUpdateDetector` no final do `index.html`) que faz polling de `/version.json` a cada 3 min, também reage a `visibilitychange` e `pageshow` (bfcache). Quando detecta versão nova, mostra banner dourado no topo da tela com countdown de 5 min. Botões "Atualizar agora" e "Depois" (adia 10 min). Após 5 min sem ação, reload automático com cache-buster `?_v=timestamp`.
2. **version.json:** Novo arquivo no deploy_zip, gerado automaticamente do `CACHE_VERSION` do `index.html`. Contém `{"version":"v108","deployed_at":"..."}`. Tamanho ~56 bytes. Configurado no `_headers` com `no-cache, no-store, must-revalidate` para nunca ser cacheado.
3. **Meta tags anti-cache no `<head>`:** Defesa em profundidade (`Cache-Control`, `Pragma`, `Expires` via `<meta http-equiv>`), complementando os headers HTTP que já estavam corretos.
4. **CACHE_VERSION:** v107 → v108, também exposto como `window.CACHE_VERSION` para o detector acessar.

---

# Mudanças v106 → v107 (10/04/2026)

1. **Fix crítico Painel Admin — aba Engajamento (antes "Analytics de Uso"):** O Worker retorna `consultas` (string) no ranking, `total` (string) no overview e `eventos` (string) no heatmap. Frontend lia `d.total` no ranking (campo inexistente → todas empresas "undefined"), somava strings concatenando no overview ("196"+"9"="1969"), e comparava lexicograficamente no heatmap ("2">"51" = false). Corrigidos os 4 renderizadores (`usoHtmlRanking`, `usoHtmlOverview`, `usoHtmlHeatmap`, `usoHtmlRetencao`) com coerção via `Number()` e mapeamento correto do campo `consultas`.
2. **Ranking enriquecido:** Cabeçalho mostra total de consultas absoluto. Tooltip de cada linha mostra o share (%) do total geral.
3. **Rename da aba:** "Analytics de Uso" → **"Engajamento"** no botão da navegação e no título da seção.
4. **CACHE_VERSION:** v106 → v107

---

# Mudanças v105 → v106 (10/04/2026)

1. **Disclaimer financeiro permanente:** Barra no rodapé do app (visível quando logado) com texto informativo sobre natureza não-recomendatória do conteúdo. Links para Termos e Privacidade.
2. **Cookie banner LGPD:** Banner com aceite de cookies essenciais. Registra consentimento em localStorage. Exibido apenas na primeira visita (ou até aceitar).
3. **CACHE_VERSION:** v105 → v106

---

# Mudanças v104 → v105 (10/04/2026)

1. **Botão "Configurações" no header desktop:** Adicionado ao lado do botão "Sair". Abre painel de preferências do usuário.
2. **Mobile bottom nav 3→4 abas:** Dashboard, Mercado (Visão Geral), Análise, Config. Removida duplicação (2 botões iam para o mesmo lugar).
3. **Botão "← Painel de Eventos" na Visão Geral:** Permite voltar ao dashboard sem navegar pela sidebar.
4. **Painel de Configurações do usuário:** Perfil, preferências de notificação (email toggle, frequência), seção "sobre", opção de cancelar emails (unsubscribe). Prefs salvas em localStorage por email.
5. **CACHE_VERSION:** v104 → v105

---

# Mudanças v103 → v104 (10/04/2026)

1. **Fix contagem arquivados no dashboard:** `renderDashboard()` calculava `todosEventos` apenas de `resultados` (live). Eventos do `ARQUIVO_PRE` fora da janela (Raízen, GPA) não eram contados como arquivados. Corrigido com merge `resultados` + `ARQUIVO_PRE` com dedup. Agora o card "Arquivados por Empresa" reflete a realidade.
2. **CACHE_VERSION:** v103 → v104

---

# Mudanças v102c → v103 (10/04/2026)

1. **Fix contagem Market Overview:** `analisarEventosGlobais()` lia apenas `ARQUIVO_PRE` (0 relevantes). Card "Relevantes Ativos" mostrava 0 enquanto dashboard principal mostrava 2. Corrigido para mergear `resultados` (live/KV) + `ARQUIVO_PRE`, com deduplicação por empresa+titulo. Agora ambas as views usam mesma base de dados.
2. **CACHE_VERSION:** v102c → v103

---

# Mudanças v101 → v102 (09/04/2026)

1. **CSS do Market Overview movido para stylesheet principal:** Os estilos `.mo-*` estavam presos dentro da template literal do PDF export (`htmlContent`), não no DOM do app. Resultado: Visão Geral renderizava sem nenhum estilo visual (sem cards, grid, heatmap, timeline). Corrigido injetando o bloco CSS completo no `<style>` principal.
2. **CACHE_VERSION:** v101 → v102

### Subversões v102b e v102c
- **v102b:** Fix scroll da Visão Geral. `#main` tem `overflow: hidden`. Adicionado `overflow-y: auto`, `flex: 1`, `min-height: 0` ao `#mo-content`.
- **v102c:** Setores clicáveis no Market Overview. Cada setor no heatmap expande/colapsa lista de empresas. Clique na empresa abre painel (chama `selecionar(nome)`). Novos elementos: `.mo-heatmap-group`, `.mo-emp-list`, `.mo-emp-item`, chevron animado, dots de status por empresa.

---

# Mudanças v100 → v101 (09/04/2026)

1. **Remoção admin_key auto-login:** Eliminado fluxo de login automático via query parameter `?admin_key=`. Risco de segurança para ambiente de produção.
2. **Remoção bloqueio devtools:** Removido script que bloqueava Ctrl+U, Ctrl+Shift+I, F12 e menu de contexto. Teatro de segurança sem valor real.
3. **CNPJ pendente removido:** Rodapé LGPD agora exibe "VIX Radar · Lei 13.709/2018 (LGPD)" sem menção a CNPJ pendente.
4. **CACHE_VERSION:** v100 → v101

---

# Mudanças v99 → v100 (09/04/2026)

1. **Dashboard de Mercado ("📊 Visão Geral"):** Nova seção na sidebar com visão executiva consolidada. Cards de resumo, mapa de calor por setor (13 setores), timeline de eventos recentes, quick stats.
2. **Refino visual:** Tipografia Inter, glassmorphism nos cards, animações fade-in/scale, badges polidos, hover states, espaçamentos profissionais.
3. **ARQUIVO_PRE atualizado:** Reduzido de 9 para 5 eventos. CSN promovido para CRÍTICO (downgrade Moody's). Removidos JBS, Petrobras, Embraer, Hapvida (expirados >7d). Mantidos Raízen e GPA (RE fundamentais para PDF/Arquivo).
4. **CACHE_VERSION:** v99 → v100

## Correções herdadas (v97-v99)
- Raízen data_evento corrigida para 2026-03-11
- Badge "fora da janela do painel" no PDF
- Nota de escopo no PDF
- MutationObserver fix para anomalias "relevante" (v94)
- Anomalias PRE com merge protegido (v93)
- Cache no-store headers (v90)

## Divergência documentada (by design)
O PDF (exportar()) inclui TODOS os eventos do ciclo sem filtro de janela. O dashboard aplica dentroJanela() com 30d para todos os eventos (janela única). Isso é intencional.

---

# Estruturas críticas do index.html (v100)

| Estrutura | Linha aprox. | Função |
|-----------|-------------|--------|
| EMISSORES | ~1794 | Objeto com 13 setores, 100 empresas |
| SETOR_DE | ~1850 | Mapa auto-gerado empresa→setor |
| METRICAS_CURADAS | ~2040 | KPIs estáticos por empresa (4 cards cada) |
| ARQUIVO_PRE | ~2179 | 5 eventos CRÍTICOS pré-carregados |
| ANALISE_V100 | ~2271 | Nota de análise da sessão 09/04/2026 |
| dentroJanela() | ~2975 | Filtra eventos por janela rolling |
| exportar() | ~3879 | Gera PDF (sem filtro de janela) |
| anomalias-pre | ~6133 | Script de anomalias de mercado pré-carregadas |
| Market Overview | ~7375 | Dashboard de Visão Geral de Mercado |

---

# Estado do Worker (v4.8.0)

## Mudança v4.7.5 → v4.8.0 (12/04/2026) — Enrichment Layer + Intelligence Endpoints

Documentado acima na seção "Mudanças Worker v4.7.3 → v4.8.0".

## Mudança v4.7.2 → v4.7.3 (11/04/2026) — Rate limit via Durable Object

**Contexto.** O usuário pediu um limitador de varreduras por usuário em janela de 30 minutos, para permitir compartilhar o acesso à plataforma sem expor o custo de API ao abuso. A v4.7.2 tentou resolver com sliding window em KV (doc único por owner), que funcionou na lógica mas **falhou em produção** no teste de 4 requisições sequenciais rápidas por race condition em read-modify-write sob consistência eventual. Rollback imediato via substituição pela arquitetura definitiva v4.7.3.

**Arquitetura definitiva.**

1. **`RateLimiterDO`** é um Durable Object SQLite-backed (exigido pelo free plan via `new_sqlite_classes` na migration). A classe expõe duas rotas internas no fetch: `POST /check` (faz o gating atomic, push de timestamp se allowed) e `GET /inspect` (retorna snapshot do storage para observabilidade). O storage guarda uma única chave `timestamps` com um JSON array de `Date.now()` dos últimos eventos.
2. **`idFromName(identidade)`** determina o DO instance. Identidade é `u:{email}` quando autenticado, ou `ip:{CF-Connecting-IP}` quando anônimo. Cada identity mapeia para um único DO, que serializa requests por key. Esta é a propriedade que elimina a race condition da v4.7.2.
3. **Três camadas** verificadas em uma única passada atomic: `burst` (3/60s), `session` (10/1800s = 30 min), `daily` (30/86400s). A camada mais apertada viola primeiro. Contadores session e daily só incrementam quando a requisição é allowed, nunca em bloqueios.
4. **Limites por tenant** via `RATE_LIMITS_POR_TENANT`. `vix_core` usa `{burst:[5,60], session:[25,1800], daily:[150,86400]}`. `mirabaud` usa `{burst:[10,60], session:[50,1800], daily:[300,86400]}`. Anônimo usa `RATE_LIMITS_ANONIMO` = `{burst:[3,60], session:[10,1800], daily:[30,86400]}`, o mais restritivo.
5. **Headers IETF** em 429: `X-RateLimit-Limit-{camada}`, `X-RateLimit-Remaining-{camada}`, `X-RateLimit-Reset-{camada}` (epoch seconds), `Retry-After`. Body retorna `{ok:false, erro, _rate_limit:{camada, retry_after_sec, tenant, autenticado, limites}}`.
6. **Fail-open com instrumentação.** Se o DO estiver indisponível ou lançar erro, `checkRateLimitV2` retorna `allowed:true` com flag `_bypass:"do_erro"` ou `_bypass:"do_binding_ausente"`. Prefere disponibilidade sobre proteção em caso de falha de infra.
7. **`GET ?action=rl_inspect`** é público mas só retorna snapshot da **própria identidade** do requisitante (resolvida via JWT ou IP). Útil para debug sem precisar de novo deploy, e para o frontend eventualmente mostrar ao usuário quantas varreduras restam.

**Validação em produção (11/04/2026 17:45 UTC).** Bateria de 5 requisições anônimas sequenciais sem Authorization no endpoint `POST /`:

| Req | Tempo | HTTP | X-RL-Remaining | Observação |
|-----|-------|------|----------------|------------|
| R1 Auren | 13.43s | 200 | headers ausentes no allowed path (limitação cosmética) | Cascade completa via OpenRouter |
| R2 Auren | 6.44s | 200 | idem | OpenRouter |
| R3 Auren | 5.53s | 200 | idem | OpenRouter |
| R4 Auren | 0.65s | **429** | burst=0, session=7, daily=27 | Camada burst violada, retry_after 36s |
| R5 Auren | 0.66s | **429** | burst=0, session=7, daily=27 | Camada burst violada, retry_after 35s |

Fast-fail (<1s) nos 429 confirma que o DO resolve antes do cascade AI, protegendo o orçamento OpenRouter/Gemini/Perplexity. Contadores de session (7 remaining = 10-3) e daily (27 remaining = 30-3) confirmam que só requisições allowed consomem quota, conforme esperado.

**Limitação conhecida.** Headers `X-RateLimit-*` só são injetados nas respostas 429, não nas 200. A resposta de sucesso percorre múltiplos branches (cache fallback, cascade AI, diferentes providers) e propagar os headers em todos os caminhos exigiria refatoração mais invasiva. Para o frontend mostrar "restam X varreduras" em tempo real, usar `GET ?action=rl_inspect` que retorna o snapshot completo sob demanda. Item de melhoria futura, não bloqueante.

**Próximo passo potencial.** Expor o estado do rate limit no frontend (banner discreto "Você usou 3 de 25 varreduras nesta sessão"), usando `action=rl_inspect` em intervalo discreto ou após cada varredura. Prioridade baixa até receber feedback real de usuários sobre se os limites são apertados ou confortáveis.

## Mudança v4.7.1 → v4.7.2 (tentativa abortada, sem uso real)

Rate limit v2 via KV sliding window em doc único `rl:v2:u:{email}` ou `rl:v2:ip:{ip}`. Código logicamente correto mas falhou no teste de 4 requisições sequenciais rápidas. Causa provável: race condition em read-modify-write sob consistência eventual do KV quando puts de uma request ainda não propagaram ao get da próxima. Substituído pela v4.7.3 sem passar por uso em produção real, apenas o próprio teste de validação. Arquivo `worker/v4.7.2.js` mantido para referência histórica.

## Mudança v4.7.0 → v4.7.1 (11/04/2026) — Favoritos privados por usuário

Primeira feature construída sobre a infra multi-tenant. Universal nos dois tenants (`vix_core` e `mirabaud`). **Doc único por usuário**, não scan prefix.

1. **`kvUserFavoritosKey(email)`** → chave KV `user_favoritos:${email.toLowerCase().trim()}`. Valor é um JSON array de objetos `{empresa, marcado_em}` ordenado alfabeticamente por `empresa`.
2. **`lerFavoritosDoUsuario(env, email)`** → `env.RADAR_KV.get(chave, "text")`. Read direto da chave do usuário, sem scan.
3. **`escreverFavoritosDoUsuario(env, email, favoritos)`** → sort + `put`. Read-after-write na mesma chave é consistente no KV, diferente do `list()`.
4. **`handleFavoritoListar(body, env, request)`** → verifica JWT via `verificarJWT`, checa `userHasFeature(env, user, "favoritos")`, retorna `{ok: true, favoritos: [...]}`.
5. **`handleFavoritoToggle(body, env, request)`** → verifica JWT, checa feature, lê array atual, modifica em memória (add se não existe, remove se existe), escreve de volta. Retorna `{ok, empresa, marcado: bool, favoritos: [...]}`.
6. **`userHasFeature(env, user, feature)`** → carrega `tenant_config` via `getTenantConfig` e checa se feature está na lista.
7. **Isolamento absoluto.** `emailAut = payload.email` vem do JWT, nunca do body. Nenhum usuário consegue ler ou escrever favoritos de outro.

**Por que doc único e não chaves individuais + scan prefix?** A primeira implementação usou `favorito:{email}:{empresa}` + `list({prefix})`. Deployada, testada, bugada. Cloudflare KV `list()` tem eventual consistency, o read-after-write pode levar até 60 segundos. Resultado: após `put` de uma chave, o `list()` subsequente retornava vazio, e a resposta mostrava `marcado: true` mas `favoritos: []`. **Read-after-write na mesma chave (`get` após `put`) é consistente** dentro da mesma região, então o doc único resolveu. Ver memória `feedback_kv_list_vs_get_consistency.md`.

Version ID: `d89ac737-ea9e-4412-978d-62b8107f495e`. Bateria de 7 testes em produção: listar inicial vazio, toggle Auren, toggle Sabesp, listar (2 items), desmarcar Auren, listar final (1 item), sem token 401. Todos OK.

## Mudança v4.6.5 → v4.7.0 (11/04/2026) — Infra multi-tenant por feature flags

Preparação de terreno para customizações do Mirabaud sem forkar o código base. Nenhum comportamento novo para o usuário final. Features novas passam a ser gated por tenant.

1. **Constantes globais.**
```js
var DEFAULT_TENANT_ID = "vix_core";
var TENANT_DOMAIN_MAP = { "mirabaud.com": "mirabaud", "mirabaud.ch": "mirabaud" };
var DEFAULT_TENANTS = {
  vix_core: { id: "vix_core", nome: "VIX Radar", features: ["favoritos"] },
  mirabaud: { id: "mirabaud", nome: "Mirabaud", features: ["favoritos", "ews_filter"] }
};
```
2. **`resolverTenantPorEmail(email)`** → lê domínio após `@`, consulta `TENANT_DOMAIN_MAP`, cai em `DEFAULT_TENANT_ID` se não encontrar.
3. **`handleRegistrar`** → seta `user.tenant = resolverTenantPorEmail(email)` no objeto salvo em KV.
4. **`handleLogin`** → carrega `tenantConfig` via `getTenantConfig`, adiciona `tenant` ao payload do JWT, devolve `tenant_config` no body da resposta para o frontend gate-ar features.
5. **`handleAdminAutoLogin`** → seta `tenant: DEFAULT_TENANT_ID` ao criar admin; se admin já existe sem `tenant`, migra para `vix_core`.
6. **`handleTenantConfigGet`** → endpoint admin para inspeção.
7. **`getTenantConfig(env, tenantId)`** → primeiro checa `DEFAULT_TENANTS[tenantId]`, depois KV `tenant_config:{id}`, cai em `DEFAULT_TENANTS.vix_core` como fallback.

Filosofia: um único código base, features por tenant, nenhum fork. Primeira feature construída sobre essa infra é `favoritos` (universal em ambos tenants). Features exclusivas Mirabaud virão via campo `features` em `DEFAULT_TENANTS.mirabaud`.

## Mudança v4.6.4 → v4.6.5 (11/04/2026) — Endpoint admin de remoção de comentário

Endpoint `comentario_remover` protegido por JWT admin. Delete da chave `comentario:{empresa}:{ts}` no KV. Audit trail em `audit:comentario_remover:${Date.now()}` com TTL de 1 ano, guardando quem removeu, o quê e quando. Utilizado para sanear comentários de teste que restaram de sessões anteriores.

## Mudança v4.6.1 → v4.6.2 (11/04/2026) — Fase 0.5 Risk Budgeting (preparatória)

Patch cirúrgico, puramente infraestrutural. **Não contém Ledoit-Wolf, ERC nem Euler.** Apenas remove bloqueios estruturais identificados na auditoria `auditorias/AUDITORIA_DADOS_LAYER1_2026-04-10.md` antes da Fase 1 de Risk Budgeting (que sairá como v4.7.0).

1. **`salvarSerie` — cap de retenção 30 → 252 registros** (`worker/v4.6.2.js:1931`). O `slice(0, 30)` descartava qualquer dado além dos últimos 30 registros, tornando impossível acumular os 252 dias úteis exigidos por Ledoit-Wolf (T > N com N=100). **TTL permanece em 90 dias** (`expirationTtl: 60*60*24*90` na linha 1933) — a retenção foi de quantidade, não de tempo. Nota: 252 dias úteis ≈ 1 ano calendário ≈ 357 dias corridos, então o TTL de 90d pode podar a série antes de atingir 252 registros se houver hiato de ingestão. Reavaliar TTL na Fase 1 quando dados reais ANBIMA fluírem.
2. **Schema persistido ganha campo `duration`** — `parsearCSVMercado` reg (`worker/v4.6.2.js:2087`), `COL_MAP` com aliases `duration`/`duracao`/`duracao_media`/`duration_macaulay`/`duration_modificada` (`:2031`), e `tentarSyncANBIMA` extrai de `Duration`/`duration`/`DuracaoMacaulay`/`DuracaoMedia`/etc do payload ANBIMA (`:2289`), agrega por emissor no `porEmissor[nome].durations` e escreve coluna `duration` no CSV intermediário. Sem `duration` não há DTS (`vol ≈ k · duration · spread`) nem fallback para emissores com série curta.
3. **`FERIADOS_B3_2027` adicionado** (`worker/v4.6.2.js:1871-1910`). `ehDiaPregaoB3` agora consulta ambos os sets (2026 e 2027). Não era bloqueante para 2026 mas viraria bug silencioso em 01/01/2027.

Version ID: `3c866818-f402-4457-bc40-baf7bc6049be`. Deploy em 2026-04-11T02:31:34Z via `npx wrangler deploy` a partir de `worker/wrangler.toml` apontando `main = "v4.6.2.js"`. Health check `GET /` OK em 93ms (openrouter, gemini, perplexity, resend, kv todos `true`).

**Gate de dados para prosseguir à Fase 1 (Risk Budgeting v4.7.0):**
- Credencial ANBIMA produção liberada (email enviado para `dados@anbima.com.br`, APP `2r1Gywm4kZTM` — **aguardando resposta**).
- Após secret `ANBIMA_API_TOKEN` colocado, forçar `sync_anbima` e backfill histórico (se ANBIMA aceitar `?date=` retroativo).
- Critério de entrada: ≥60% dos 100 emissores com ≥252 registros reais, `duration` populado em ≥80% dos registros recentes, `?action=status_mercado` mostrando `com_anomalias > 0`.

## Mudança v4.5.1 → v4.5.2 (10/04/2026)
1. **Notificação WhatsApp de novos cadastros (Twilio Sandbox):** Função `enviarWhatsAppAdmin()` chamada em `handleRegistrar()` após tentativa de email Resend. Envia mensagem formatada com nome, email, empresa, hora BRT e link direto `vixradar.com/admin?highlight=<email>`. Usa Twilio REST API (Basic Auth com SID+Token). Destino atual: sandbox `+1 415 523 8886` → `whatsapp:+5521981088992`. Latência ~1s. Secrets: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_WHATSAPP_FROM`, `ADMIN_WHATSAPP_TO`. Code join sandbox: `join spent-negative` (renovar a cada 72h de inatividade). Version ID: `13cd3ae6-0982-4526-9a69-87f2c1e8b919`.

## Mudança v4.5.0 → v4.5.1 (09/04/2026)
1. **Fix privacidade emails (BCC):** `enviarResend()` enviava todos os destinatários no campo `to`, expondo emails entre si. Corrigido para `to: ["boletim@vixradar.com"]` + `bcc: destArray`. Afeta alertas críticos e newsletter.

| Feature | Status |
|---------|--------|
| Cascade AI (OpenRouter → Gemini → Perplexity) | ❌ OBSOLETO desde v4.9.108 — ver seção "Arquitetura de IA Atual" |
| Análise inline (claude-haiku-4-5-20251001 via Anthropic API) | ✅ |
| Análise em lote (Claude Opus via Claude Code Scheduled Tasks) | ✅ |
| Circuit breaker por provider | ✅ (resíduo no bundle — não ativo) |
| Cache de último resort | ✅ |
| Pipeline verdade graduada | ✅ |
| Calendário B3 (ehDiaPregaoB3) | ✅ |
| Provider monitoring (status_providers) | ✅ |
| JWT auth + PBKDF2 | ✅ |
| CORS allowlist | ✅ |
| Email BCC (privacidade) | ✅ |
| Newsletter cron (Resend) | ✅ (DNS pendente) |

## Health check
```bash
curl -s https://radar-credito-api.prospects-intel.workers.dev | python3 -m json.tool
# Esperado: ok=true, telemetria=true, resend=true, kv=true
# NOTA: campos openrouter/gemini/perplexity são resíduos históricos no schema de resposta.
# Sua presença NÃO indica uso ativo — esses providers foram removidos em v4.9.108.
```
