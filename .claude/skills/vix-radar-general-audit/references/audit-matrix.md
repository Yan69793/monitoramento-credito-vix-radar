# Audit Matrix

> **Governanca (2026-08-26).** Status: vigente. Data da versao alinhada a producao:
> Worker v4.9.220 e Frontend v202.33, medidos ao vivo em 26/08 no health publico e
> no version.json, coincidindo com o repo. Origem do registro: producao, depois
> Obsidian, depois codigo (api/wrangler.toml main + changelog). Condicao de
> obsolescencia: revisar quando o main de api/wrangler.toml ultrapassar v4.9.220 ou
> surgir binding, fila, endpoint, rotina ou incidente novo que nenhuma secao alcance.

Referencia rapida para auditoria geral backend/frontend do VIX Radar.

## Fontes externas pesquisadas

- OWASP ASVS: usar como baseline de controles de seguranca de aplicacao. Fonte: https://owasp.org/www-project-application-security-verification-standard/ (ASVS 5.0.0 stable).
- OWASP WSTG: usar como guia de cenarios de teste de seguranca web. Fonte: https://owasp.org/www-project-web-security-testing-guide/ (stable v4.2; v5.0 em desenvolvimento).
- NIST SSDF SP 800-218: usar para governanca de desenvolvimento seguro e prevencao de vulnerabilidades no SDLC. Fonte: https://csrc.nist.gov/pubs/sp/800/218/final.
- Web Vitals: usar Core Web Vitals como foco de performance e UX, avaliando percentil 75 em mobile e desktop. Fonte: https://web.dev/articles/vitals.
- WCAG 2.2: usar como baseline de acessibilidade, priorizando criterios A/AA aplicaveis. Fonte: https://www.w3.org/TR/WCAG22/.
- Cloudflare Workers observability: usar docs oficiais para logs/erros/observabilidade em Workers. Fonte: https://developers.cloudflare.com/workers/observability/errors/ e https://developers.cloudflare.com/workers/observability/logs/workers-logs/.

## Backend Worker

> Producao em 2026-08-26: Worker v4.9.220 e Frontend v202.33, medidos ao vivo no
> health publico e no version.json, coincidindo com o repo (main = v4.9.220.js).
> Marcos pos v4.9.197 no changelog do wrangler.toml: v4.9.205 SPREADSERIE1,
> v4.9.209-210 CVMURL404/CVMDURA1, v4.9.214 EMAILSILENT1, v4.9.215 SUBSTRINGDONO1,
> v4.9.216 SENTINELA1, v4.9.217-219 DEFERGRUDA1/2/3, v4.9.220 STATUSGRUDA1.

Checklist:

- `api/wrangler.toml`: `main`, `compatibility_date`, route custom domain, KV, DO, Analytics Engine, observability, crons.
- Bundle ativo: `WORKER_VERSAO`, roteamento `fetch`, `scheduled`, auth, CORS, rate limit, newsletter, ingestao.
- Seguranca:
  - Secrets sempre via `env`, sem fallback inseguro para JWT/API keys.
  - Admin actions exigem senha/admin/JWT/routine key conforme risco.
  - POST anonimo deve retornar 401/403 em rotas protegidas.
  - CORS deve ter allowlist e fallback seguro.
  - Logs nao devem vazar segredo, senha, token, email sensivel desnecessario ou payload LGPD.
- Confiabilidade:
  - `ctx.waitUntil` para trabalho assicrono que nao pode bloquear response.
  - Operacoes longas devem ter idempotencia/dedup/status.
  - Falha de provider deve ser visivel no health/admin health, nao virar ACK falso.
  - `receber_analise` deve persistir eventos aprovados e diferenciar "sem eventos legitimo" de "verificador falhou".
- Dados:
  - Multi-semana em endpoints criticos.
  - Datas CVM nao podem cair em fallback "hoje" sem sinalizacao.
  - `EMISSORES_LISTA`/setores/materialidade devem estar coerentes.
  - Agenda de Resultados (CALVAL-V2, desde v4.9.192): tier de fonte (RI/CVM/B3/corporativo/secundario) fail-closed, oficial nunca sobrescrita por secundaria divergente (vira DIVERGENTE), gate de publicacao (`confirmado` so com CONFIRMADO_*), auditoria de mudanca de data, alias de empresa, confronto diario com publicacao CVM, `status_validacao` computado no Worker e exibido no frontend.
- XSS write-path (XSSV100-FIX1, desde v4.9.193): `sanitizarPayloadRadar` faz strip de tags HTML em `titulo`/`empresa` no caminho de gravacao. Confirmar que todo novo caminho de ingestao chama o sanitizador e que o strip nao e a unica defesa (render continua escapando).
- Fila de verificacao com reserva atomica (CONCORVERIF1, desde v4.9.196): acao `reservar_itens_fila` faz claim via `EstadoSemanaDO` (`op:"reservar"`, `this.state.storage`, TTL 20min) antes de gastar verificacao adversarial num item, evitando que poller Local e Remote processem o mesmo evento em paralelo. Fail-open documentado: se o DO falhar, `protecao_ativa:false` e o lote inteiro e tratado como reservado sem protecao real. Confirmar que todo caller (local e remote) checa `protecao_ativa` na resposta em vez de assumir protecao silenciosamente.
- Credencial escopada para poller remoto (CHAVEESCOPO1, desde v4.9.197): secret `REMOTE_VERIFICACAO_KEY` autentica só as 3 acoes de verificacao (`listar_fila_verificacao`, `confirmar_verificacao`, `reservar_itens_fila`); toda outra acao do contrato exige `ROUTINE_API_KEY`. Ao revisar acao nova dessas 3, replicar o aceite dual (`routine_key !== ROUTINE_API_KEY && routine_key !== REMOTE_VERIFICACAO_KEY`); qualquer acao fora do grupo que aceite `REMOTE_VERIFICACAO_KEY` e escopo vazando.
- Heartbeat de agente remoto (HEARTBEATVERIF1, desde v4.9.196): `verificacao_async` entra no `expectedAgents` do watchdog cron (limite 16h). Todo agente/rotina remota nova precisa entrar nesta lista, senão fica invisivel ao watchdog mesmo publicando heartbeat.
- Atribuicao CVM por CNPJ (SUBSTRINGDONO1, desde v4.9.215): `_donoDocumentoCVM` arbitra com ancora de inicio de palavra e termo mais longo vencendo; `CNPJ_PRIMARIO_EMISSOR` (ITR/balanco) e `CNPJ_FAMILIA_CVM` (holding + subsidiarias) separados de proposito para a familia nao vazar no primario. Nome e excecao (entidade estrangeira). Sem-match vai a `admin_cvm_quarentena`. Health expoe `cvm_atribuicao_por_cnpj`/`por_nome`/`quarentena`/`cobertura_pct`/`descartados_teto`, fora do `ok` agregado. Conferir que emissor renomeado nao fica cego.
- Email rastreado (EMAILSILENT1, desde v4.9.214): todo envio ao usuario final passa por `enviarEmailRastreado`, que nunca lanca (a acao primaria continua valendo). Respostas de aprovar/rejeitar carregam `email_enviado`/`email_erro`/`resend_id` (tri-estado). Rastro em KV `email_envio:{email}:{ts}` (TTL 90d, igual bounce). Conferir que call site novo le o retorno.
- Fonte CVM (CVMURL404/CVMDURA1, desde v4.9.209-210): 404 do ZIP `ipe_cia_aberta_*.zip` repergunta o catalogo CKAN; falha DURA derruba `fonte_externa_ok` na hora (nao usa a tolerancia semanal de `CVM_FONTE_MAX_CICLOS`). Campos novos no health: `cvm_fonte_falha_dura`, `cvm_fonte_degrada_servico`, `cvm_fonte_ultimo_sync_ok_em`, `cvm_fonte_falhas_consecutivas`. TTL de `cvm:documentos` e 30 dias desde o v4.9.210. Conferir que alerta nenhum le so o agregado `ok`.
- Sentinela pontual (SENTINELA1 v4.9.216, DEFERGRUDA1/2/3 v4.9.217-219, STATUSGRUDA1 v4.9.220): modo "pontual" em `montarPlanoRotina`/`listar_plano_rotina` com teto `ROTINA_PONTUAL_TETO=8` e excedente declarado em `pontual_candidatos`/`pontual_excedente`; gatilho so por fato novo (protocolo ausente de `radar:cvm_vistos:{empresa}`) ou divida (`_token_cap_deferred`), nunca por inconclusivo (v4.9.219). `_status` descreve a ULTIMA VARREDURA, nao o acervo. Conferir que a pontual converge, que a bandeira `_token_cap_deferred` e gravada E apagada nos 5 ramos, e que a leitura multi-semana nao ressuscita bandeira apagada.

Comandos uteis:

```powershell
git status --short
git diff -- api/wrangler.toml app/index.html app/deploy_zip/index.html
rg -n "JWT_SECRET|ADMIN_EMAIL|ROUTINE_API_KEY|ANTHROPIC_API_KEY|OPENROUTER|Math.random|sem_eventos|receber_analise|carregarEstadoMultiSemana|RADAR_USAGE_EVENTS" api app
curl.exe -s https://api.vixradar.com/ -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
```

## Camada de persistência (migração KV→DO v5)

A migração é incremental e fail-open. KV ainda é a fonte da verdade.

Bindings ativos: `RADAR_KV`, `ESTADO_SEMANA_DO`, `EMISSOR_DO`, `USUARIO_DO`, `CONFIG_DO`. Todos em `api/wrangler.toml` com migration v3 (`new_sqlite_classes` para os 3 DOs de domínio).

O que checar em auditoria:

- `wrangler.toml`: os 5 bindings declarados, migration v3 presente.
- `wrangler secret list`: DOs não precisam de secrets, mas confirmar.
- Health check: `ok:true` confirma que KV está vivo. DOs não têm campo público no health ainda — um DO quebrado silencia em `console.warn` sem derrubar `ok`.
- Dual-write: padrão `_rotearPara{Emissor,Usuario,Config}DO` com fallback KV. Se o DO falha na escrita, `console.warn("[DO][dual-write] ...")` e o KV segue atualizado. Na leitura, tenta DO primeiro, cai para KV.
- Sinal de estagnação: ausência prolongada de `[DO][dual-write]` nos logs do Worker NÃO significa que a migração completou — pode significar que os DOs nunca foram exercitados. Ausência de `[DO][read]` com fallback KV também não é garantia de que o DO está servindo leitura.
- Risco: a migração pode estar parada sem ninguém ver porque todo o fallback é silencioso. Não há métrica de cobertura DO vs KV, taxa de acerto de leitura DO, nem aging de dual-write.

## Watchdogs locais de rotina (novo, 2026-08-18)

Desde a migracao das rotinas para sessoes agendadas do Claude Desktop (que podem cair em
idle no meio do cascade sem deixar rastro), existe uma camada extra de watchdog puramente
local: `scripts/retry-vixradar.ps1` (Task Scheduler `Szuchmacher-RetryVixNoturno`/
`RetryVixMatinal`), que relanca a rotina via `run_claude_routine.ps1` quando o log do dia
nao tem linha `FIM:` valida.

O que checar:

- O regex de parsing de `FIM:` deste script e o de `scripts/monitor-tasks.ps1` (bloco de
  leitura de status) precisam aceitar exatamente as mesmas variantes de texto que as
  rotinas realmente escrevem. Ja bateu uma vez (17/08, commit `ad06ad4`): um regex aceitava
  `N/N processados` mas nao `N/N emissores processados`, causando retry falso (sessao
  Claude Desktop queimada a toa). Ao mudar a redacao de qualquer linha `FIM:` em qualquer
  rotina, atualizar os dois arquivos juntos e testar contra o log real.
- Lock/mutex contra duplicata: o watchdog tem que respeitar o mesmo lock que a rotina usa
  (ex.: mutex de 3h da skill, ou `Global\<nome>` .NET Mutex), nunca relancar por cima de
  uma execucao ainda viva.
- `$VixRoot` e caminhos hardcoded no script: confirmar que apontam para o caminho fisico
  canonico do projeto (nao para um junction legado), especialmente apos qualquer inversao
  de junction como a de 2026-08-18.
- O agendamento das rotinas Claude Desktop (matinal, noturno, verificacao async) vive no
  CCD store `%APPDATA%\Claude\claude-code-sessions\<conta>\<device>\scheduled-tasks.json`
  (INVERSAO-CD1), nao so no Task Scheduler. As tasks homonimas ficam `Disabled` de
  proposito, guarda anti-duplicata. Ao validar rotinas, conferir a entrada no CCD store e
  a linha `FIM:` no log em `logs/routines/`, nunca o `LastTaskResult`.

## Frontend Pages

Checklist:

- `app/index.html` e `app/deploy_zip/index.html`: versions/cache alinhados.
- `app/admin/*.js` e `app/deploy_zip/admin/*.js`: modulos sincronizados.
- Auth:
  - Requests autenticados usam `Authorization: Bearer`.
  - 401 em endpoint secundario nao deve derrubar sessao sem contexto.
  - Senha admin nao deve ir em URL quando houver alternativa POST.
- UX:
  - Loading, empty, error e retry para state, briefing, comparar, admin e pulso.
  - Estados de dados atrasados devem ser explicitos.
  - Tabelas e cards precisam caber em mobile sem overflow critico.
- CSS:
  - Regra global `strong` sem `color`.
  - Evitar mudancas que quebrem contraste ou hierarquia.
- Market Overview (marcador "MARKET OVERVIEW MODULE v100" em app/index.html, grep pelo marcador, nao fixar linha): campos de LLM (`titulo`, `empresa`) escapados no render (`x()`/`h()`), chips e cores derivados do mesmo valor com os mesmos limiares (>=90 saudavel, >=70 atencao, <70 critico), rotulos reservados ("Emissores", "Criticos", "Relevantes", "Sem alertas") conferidos contra o glossario.

## Performance

Priorizar:

- LCP: hero/conteudo inicial, HTML enorme, CSS/JS bloqueante.
- INP: handlers pesados, render de listas grandes, filtros/sorts no main thread.
- CLS: imagens/paineis sem dimensao, toasts/modais que empurram layout.
- Cache: `version.json` no-store, HTML coerente com estrategia de deploy, assets com nomes/versoes.

Limiares praticos:

- Core Web Vitals devem ser avaliados no percentil 75 por mobile e desktop.
- Quando nao houver lab/browser, registrar lacuna e fazer revisao estatica: tamanho do HTML, scripts inline, imagens, fontes, handlers globais.

## Acessibilidade

Amostra minima:

- Navegacao por teclado em login, dashboard, modais, admin e comparar.
- Foco visivel, fechamento de modal por Esc, trap de foco em dialogs.
- Labels em inputs, botoes com nome acessivel, status messages para loading/erro.
- Contraste de texto, badges e estados criticos.
- Tabelas com cabecalhos semanticos quando aplicavel.

## Relatorio

Cada achado deve incluir:

- Severidade.
- Area.
- Evidencia reproduzivel.
- Impacto.
- Acao recomendada.
- Se e bug confirmado ou risco a validar.

Evitar listas gigantes. Entregar top riscos primeiro e anexar lacunas.

## Manutencao da skill

A skill envelhece junto com o sistema. Toda auditoria geral deve verificar se a
matriz ainda cobre o que esta em producao. Se aparecer subsistema, binding, fila
ou integracao nova que nenhuma secao da matriz alcanca, isso e achado da auditoria
tambem — propor o checklist novo no relatorio e atualizar este arquivo.

Itens que disparam revisao da matriz:

- Binding novo no `wrangler.toml` (DO, KV, R2, Analytics Engine, Queue).
- Classe nova de Durable Object com roteamento proprio.
- Endpoint novo no Worker (rota `if (url.pathname === "/...")`).
- Provider novo de IA ou email/sms.
- Campo novo no health check publico.
- Script novo de rotina ou task nova no Scheduler.
- Padrao de risco novo encontrado em auditoria (ex: fail-open silencioso, dual-write
  sem metrica de progresso, janela cega entre duas constantes).

Quando a matriz for atualizada, conferir se o `SKILL.md` tambem precisa de ajuste
— caminho de script, comando de exemplo, referencia a secao nova.

A habilidade existe em UMA fonte: a copia do workspace (`.claude/skills/` dentro do
repo). As copias globais `E:\Diretorio\Claude\.claude\skills\vix-radar-general-audit`
e `C:\Users\User\.claude\skills\vix-radar-general-audit` sao JUNCTIONS para a do
workspace (verificado 2026-08-26). Editar o workspace atualiza as tres; comandos de
script funcionam pelo caminho do workspace ou da junction indistintamente.
