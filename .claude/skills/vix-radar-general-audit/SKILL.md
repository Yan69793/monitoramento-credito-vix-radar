---
name: vix-radar-general-audit
description: >
  Auditoria geral de engenharia do VIX Radar cobrindo backend Cloudflare Worker,
  frontend Pages/app/index.html, veracidade da UI (rotulo x formula), seguranca,
  auth/CORS, secrets, telemetria, performance, acessibilidade, confiabilidade,
  deploy, drift repo/producao, divida tecnica, IA generativa/cascade LLM e
  qualidade de codigo. Use quando o usuario pedir auditoria geral, audit geral
  backend e frontend, revisar arquitetura, varrer o projeto, encontrar riscos,
  revisar seguranca/performance do app, ou preparar um relatorio tecnico
  priorizado alem do health operacional. Use tambem quando desconfiar de numero,
  rotulo, card, percentual ou selo errado no dashboard, quando pedir para achar
  a causa raiz de um defeito recorrente, ou quando quiser garantir que um erro
  encontrado nao volte no futuro.
date: 2026-08-26
---

# VIX Radar General Audit

> **Governanca (2026-08-26).** Status: vigente. Data da versao alinhada a producao:
> Worker v4.9.221 e Frontend v202.33, medidos ao vivo em 26/08 no health publico
> (os dois dominios) e no version.json de vixradar.com, coincidindo com o repo
> (main = v4.9.221.js e CACHE_VERSION v202.33). Origem do registro: producao
> (health + version.json), depois Obsidian (03 - Estado Atual ainda registra
> v4.9.216 de 25/08, defasado), depois codigo (api/wrangler.toml main + changelog).
> Condicao de obsolescencia: revisar quando o main de api/wrangler.toml ultrapassar
> v4.9.221, ou quando surgir binding, fila, endpoint, rotina ou incidente novo que
> nenhuma secao desta skill alcance.

Auditoria ampla de engenharia para o VIX Radar. Esta skill complementa
`vix-radar-audit`: use `vix-radar-audit` para health operacional/producao e esta
skill para revisao de backend + frontend + qualidade do projeto.

## Antes de auditar

0. Seguir as 5 regras permanentes de auditoria do `CLAUDE.md` raiz (medir antes de planejar, numero sai de comando com saida citada, julgar por comportamento, separar artefato vivo de registro, prova de guarda de duas pontas). O projeto tem hook graphify antes de grep/read: orientar-se por `graphify query "<pergunta>"` antes de ler arquivo (CLAUDE.md raiz, secao "Grafo do codigo"). O grafo orienta pouco o Worker: simbolo de `api/src/worker.js`, ler o fonte direto apos a orientacao.
1. Ler `CLAUDE.md`, `.claude/SKILLS-ROUTER.md`, `Obsidian VIX Radar/00 - Índice (MOC).md` e `Obsidian VIX Radar/03 - Estado Atual.md` (antes se chamava `03 - Estado de Producao.md`; nao recriar o nome antigo).
2. Ler a matriz em `references/audit-matrix.md` (snapshot revisado em 2026-08-26).
3. Ler `references/glossario-dominio.md`. Sem o glossario carregado nao da para auditar a camada de veracidade da UI: e ele que define o que "cobertura", "critico" e "relevante" tem obrigacao de significar.
4. Cruzar com `Obsidian VIX Radar/PENDENCIAS.md` (canonico desde 2026-07-27; o `PENDENCIAS.md` da raiz foi arquivado) para nao reabrir achado ja classificado.
5. Carregar skills auxiliares conforme escopo:
   - `vix-radar-audit` para health, drift e evidencia de producao.
   - `workers-best-practices` para Cloudflare Worker.
   - `web-perf` quando medir frontend em navegador.
6. Manter modo readonly por padrao. Nao deployar, nao alterar secrets e nao fazer POST destrutivo sem pedido explicito.

### O que esta auditoria pode e nao pode afirmar

Ela reduz risco por cobertura sistematica; ela **nao prova ausencia de bug**. Entao:
nunca escrever "nenhum erro no sistema". Escrever o que foi coberto, com que
evidencia, e o que ficou como lacuna. "Sem achado na camada X com o metodo Y" e
uma afirmacao honesta; "sistema sem erros" nao e, e destroi a confianca no
relatorio seguinte quando o primeiro bug aparecer.

## Escopo padrao

Auditar estas camadas:

| Camada | Evidencia minima |
|---|---|
| Repo e governanca | `git status`, ultimo commit, arquivos untracked, artefatos legados, documentacao viva |
| Backend Worker | `api/wrangler.toml`, bundle ativo `api/v4.9.*.js`, bindings (KV, DO rate limit, DO estado semana, AE), routes, crons, auth, CORS, rate limit, telemetria |
| Frontend | `app/index.html`, `app/admin/*.js`, `app/deploy_zip/`, versionamento, cache, auth headers, estados vazios/erro, escape XSS em admin/PDF |
| **Veracidade da UI** | **Todo numero/rotulo/selo exibido: o rotulo bate com a formula? a cor acompanha o valor? a janela e a declarada? Ver `references/glossario-dominio.md` e rodar `scripts/audit-ui-metrics.mjs`** |
| Seguranca | ASVS/WSTG: secrets, hardcoded data, JWT, fail-open/fail-closed, inputs, headers, logs, admin actions, stored XSS em campos de usuario |
| Performance | Core Web Vitals, payload HTML/JS, bloqueio de main thread, cache headers, dependencias, assets |
| Acessibilidade | WCAG 2.2 AA pragmatica: teclado, foco, labels, contraste, estados, tabelas, dialogs |
| Confiabilidade | health real, verificador, ingestao, KV, DO, crons, retries, idempotencia matinal/noturna, metrics de rotina, observabilidade |
| IA generativa / cascade LLM | prompt injection, output handling, misinformation, excessive agency, custo/consumo, fila de verificacao, mapeado ao OWASP LLM Top 10 2025 |
| Preditivo / score | Merton DD e demais drivers do score (MERTONLIVE1), coleta de volatilidade, proveniencia e visibilidade de drivers |
| Produto/dominio | cobertura 103 emissores, materialidade, datas CVM, rotina matinal/noturna, UX de risco |

## Metodo

1. **Checagem de drift da propria skill:** rodar `git log --oneline -20 -- api/*.js api/wrangler.toml app/index.html app/admin` antes de auditar. Se aparecer subsistema, binding, fila ou integracao nova que a matriz nao cobre, tratar isso como lacuna da skill (nao so do sistema) e propor o checklist novo no relatorio — ver `references/audit-matrix.md` secao "Manutencao da skill".
2. **Inventario rapido:** listar estrutura relevante sem varrer diretorios legados em profundidade (`producao/`, `_historico/`, `archive/`, `vixradar/`).
3. **Mapa de versoes:** comparar repo vs producao para Worker e frontend. Se houver drift, classificar antes de qualquer conclusao tecnica.
4. **Leitura dirigida:** inspecionar os arquivos vivos, nao os bundles antigos. Worker vivo = `api/wrangler.toml main`. Frontend vivo = `app/index.html` e modulos em `app/admin/`.
5. **Checks automaticos baratos:** sintaxe, busca por padroes de risco (incluindo estado global entre requests e promises sem `await`/`waitUntil` — ver matriz), diff, tamanhos, headers publicos, health publico.
6. **Veracidade da UI (obrigatorio, nao pular):**
   ```powershell
   node "E:\Diretorio\Claude\.claude\skills\vix-radar-general-audit\scripts\audit-ui-metrics.mjs" "E:\Diretorio\Claude\Monitoramento de Credito\app\index.html"
   ```
   Exit 1 significa achado bloqueante. O bloco `[INVENTARIO]` **sempre** exige leitura humana: para cada rotulo marcado `TERMO RESERVADO`, confirmar que a expressao ao lado mede o que o glossario manda. O script detecta cor incoerente sozinho; rotulo mentiroso ele so expoe, quem julga e o auditor.
7. **Amostragem manual profunda:** escolher fluxos criticos: login, `op=state`, `receber_analise`, admin, newsletter, briefing/comparar, pulso manual, cascade de IA (matinal/noturno/verificador).
8. **Classificacao:** separar bug confirmado, risco plausivel, divida tecnica e melhoria de produto.
9. **Evidencia:** cada achado precisa de arquivo+linha, comando/HTTP bruto, ou trecho de diff. Sem evidencia, registrar em "lacunas".
10. **Causa raiz e guarda:** nenhum achado fecha so com o patch. Ver secao abaixo.

## Causa raiz obrigatoria

Corrigir o sintoma sem matar a causa garante que o mesmo defeito volta com outro
nome. Todo achado confirmado sai do relatorio com tres campos, nao um:

| Campo | Pergunta |
|---|---|
| Correcao | O que conserta este caso especifico |
| Causa raiz | Por que ele existiu, e por que passou por revisao e deploy sem ninguem ver |
| Guarda sistemica | O que impede a proxima ocorrencia sem depender de alguem lembrar |

Guarda vale mais quanto menos depender de memoria humana. Ordem de preferencia:

1. Check automatizado que reprova (script, lint, teste, guard em script de deploy).
2. Item permanente nesta skill ou na matriz, que roda em toda auditoria.
3. Entrada em documento canonico (glossario, `CLAUDE.md`, vault).
4. Anotacao solta em PENDENCIAS — mais fraco, so quando 1 a 3 nao cabem.

Exemplo real, achado 2026-07-27 (card "Cobertura 62%"):

- **Correcao:** renomear para "Sem alertas" e derivar a cor do valor pelos mesmos limiares do selo.
- **Causa raiz:** o sistema nunca teve contrato de indicador. Rotulo, formula, janela e faixas viviam soltos no mesmo template minificado, e o termo "cobertura" ja significava outra coisa no backend. Nenhuma camada da auditoria comparava rotulo com formula, entao backend verde + deploy verde + health verde davam a impressao de sistema correto.
- **Guarda sistemica:** `references/glossario-dominio.md` (contrato de indicador com 5 campos) + `scripts/audit-ui-metrics.mjs` rodando em toda auditoria geral, com exit 1 no encoding incoerente e inventario obrigatorio de rotulo x formula.

Quando a mesma causa raiz aparecer em 2 auditorias, ela vira item permanente da
matriz (`references/audit-matrix.md`, secao "Manutencao da skill"). Redescobrir do
zero na proxima sessao e falha da skill, nao do sistema.

## Checks especificos VIX Radar

- Nao editar bundles antigos; a verdade de deploy e `api/wrangler.toml` (`main` + comentario de changelog no topo).
- Um numero de `WORKER_VERSAO` por deploy (VERSAO3X): se o mesmo numero foi publicado com builds diferentes, triangulacao por hash/commit, nao so por string de versao.
- Confirmar bindings vivos no `wrangler.toml` e no codigo: `RADAR_KV`, `RATE_LIMITER_DO`, `ESTADO_SEMANA_DO` (RACEKV1), `RADAR_USAGE_EVENTS`, route `api.vixradar.com`, crons.
- Confirmar que o health publico nao mascara falhas de verificador, ingestao ou telemetria.
- Confirmar que `receber_analise` nao aceita eventos e grava `sem_eventos:true` por erro de schema.
- Confirmar que endpoints multi-semana usam `carregarEstadoMultiSemana(env, N)` coerente com a janela de cada endpoint: a janela varia (N=2, 3 ou 5 no fonte atual). `montarPlanoRotina` usa 3 desde v4.9.218. Nunca assumir N=5 para todo endpoint.
- Confirmar regra CSS global: `strong` sem `color`, apenas `font-weight`.
- Confirmar que `app/deploy_zip/` esta sincronizado com `app/` antes de qualquer deploy Pages.
- **Veracidade da UI (UISEMANTICA1, 2026-07-27):**
  - Rotulo x formula: cada indicador exibido mede exatamente o que o rotulo diz, conforme `references/glossario-dominio.md`. Termo reservado usado com outro sentido e bug de produto, nao preferencia de estilo.
  - Cor semantica acompanha o dado: classe de severidade nunca literal sobre valor que atravessa faixas. Se o selo calcula a faixa e o numero nao, o card se contradiz.
  - Janela declarada e a janela usada: se a tela tem filtro de periodo (7D/30D), verificar quais indicadores obedecem e quais tem janela fixa. Indicador com janela fixa ao lado de um filtro precisa dizer isso.
  - Denominador explicito: todo percentual declara numerador e denominador. `62%` sem base e irrastreavel.
  - Rotulo sem fonte: numero na tela que nao tem formula localizavel no codigo e achado, nao detalhe.
- **Providers no health (OPENROUTERVIVO, atualizado 2026-08-15):** nao tratar `openrouter`/`perplexity` como residuo de schema por padrao. Caminho vivo: `verificarSaldoOpenRouter` (funcao em api/src/worker.js, grep "async function verificarSaldoOpenRouter"; consulta saldo da conta OpenRouter usada para monitorar o Perplexity). Nao existe probe de health ativo do Perplexity: o call site `chamarOpenRouter` ficou orfao quando a funcao foi removida no v4.9.180 (ReferenceError engolido, status sempre `erro_desconhecido`, nivel >= amarelo com email falso de providers desde 30/07) e foi desligado na auditoria de 15/08 (OPENROUTER-ORFAO1): `perplexity` agora e constante `{status:"removido"}`. `probeOpenRouterSonarPro`/`probeOpenRouterExa` foram REMOVIDOS no v4.9.180 (OPENROUTER-DEAD, so resta o comentario no fonte), nao procurar por eles. OpenRouter nao esta no cascade de analise de credito (saiu no v4.9.108). Gemini permanece residuo de schema salvo evidencia nova de uso. Confirmar se `OPENROUTER_API_KEY` existe e se `verificarSaldoOpenRouter` gasta ou contamina sinal de saude.
- Confirmar que o verificador adversarial (`v4.9.146+`) segue no caminho critico de `receber_analise`, nao contornado; fila `radar:verif_fila:{data}` serializada via EstadoSemanaDO, claim atomico em `reservar_itens_fila` desde v4.9.196 (CONCORVERIF1, TTL 20min, fail-open documentado: conferir `protecao_ativa` na resposta, nunca assumir protecao; VERIFQ-ORFAO1 era pre-v4.9.196); teto/guarda contra `Credit balance is too low` e auth OAuth nas rotinas (cobranca via assinatura, nao metered `ANTHROPIC_API_KEY` no processo filho).
- **Idempotencia e metrics de rotina (METRICSZERO1):** matinal e noturna devem ter skip idempotente; no caminho de skip, metrics JSON nao pode zerar o run real do dia (preservar numeros ou gravar `skipped_idempotente:true`).
- **Preditivo Merton (MERTONLIVE1, premissa corrigida em 2026-08-20):** a redacao anterior afirmava que `calcMertonDD` / `scoreMertonToRisk` "movem score em producao". **Nao movem, e nunca moveram.** Auditoria de 20/08 (DRIVERMORTO1): `merton_dd` esta `null` nos 103 emissores em todos os exports desde 11/07/2026. O gate em api/src/worker.js (grep "const mktCap = altmanEmp") exige `mktCap`, que so pode vir de `fundamentals:altman:latest` (DFP da CVM, balanco puro, 0 ocorrencias de `market_cap` na chave) ou de `cotacoes:volatilidade:v1` (que se recusa a publicar preco por acao como market cap, de proposito). Nenhuma das duas fornece, entao o ramo nunca executou uma vez. Mitigante: `predictive_v1` e lab interno (`user_facing:false`), fora da tela do cliente. Auditar sempre com `scripts/check-drivers-preditivos.ps1`: ele mede cobertura de cada driver declarado em `scorePreditivoRuleV1` e reprova driver novo com cobertura zero. Em 20/08, 3 dos 6 estavam mortos (`merton`, `momentum`, `mercado`). Conferir tambem se `VIXRadar-Coleta-Volatilidade` roda (LastTaskResult 0) e se o modelo esta documentado no vault/PENDENCIAS.
- **TTL de chave KV alimentada por rotina diaria (VOLTTL1, 2026-08-20):** chave escrita 1x/dia com TTL de 86400 nao tem folga, uma unica falha de upload apaga o dado antes da tentativa seguinte. Foi o caso de `cotacoes:volatilidade:v1`: POST falhou em 19/08 17:02, a escrita de 18/08 expirou as 17:01 e a chave respondia 404 no dia seguinte, com o pipeline lendo por `.catch(() => null)` sem reclamar em lugar nenhum. Regra de auditoria: para toda chave gravada por rotina agendada, TTL >= 2x o intervalo de gravacao.
- **Wrapper de rotina que engole a saida do filho (VOLLOG1, 2026-08-20):** `run_*.ps1` que captura a saida do script chamado em variavel e loga apenas `exit=N` destroi o diagnostico do dia seguinte. Auditar todo wrapper: no `catch`, a saida capturada tem que ir para o log.
- **A fonte CVM `CIA_ABERTA/DOC` e SEMANAL, publica aos domingos (CVMCADENCIA1, 2026-08-20). LER ANTES DE ABRIR INCIDENTE DE FONTE.** Este fato ja foi redescoberto errado duas vezes, em 19/08 e em 20/08, e nas duas o veredito saiu como "a CVM parou de publicar". **Ela nao parou.** Evidencia canonica, nesta ordem de forca:
  1. A pagina do dataset declara `Frequencia de atualizacao: Semanal` e "os arquivos referentes ao ano corrente e anterior (A-1) serao atualizados semanalmente" (`dados.cvm.gov.br/dataset/cia_aberta-doc-ipe`).
  2. `ipe_cia_aberta_2026.zip` e `ipe_cia_aberta_2025.zip`, corrente e A-1, sao regerados no MESMO domingo com segundos de diferenca. Dois domingos consecutivos observados, 09/08 e 16/08.
  3. O portal esta vivo mesmo quando esse ramo parece parado: `FI/DOC/INF_DIARIO` e `CIA_ABERTA/CAD` regeneram todo dia de madrugada. Se so `CIA_ABERTA/DOC` estiver com data velha, e cadencia, nao incidente.
  4. A CVM segue recebendo protocolo. Documento de 17 ou 18/08 ausente do ZIP nao prova fonte parada, prova que o lote semanal ainda nao rodou.
  Corolario metodologico que vale alem da CVM: `Last-Modified`, SHA do arquivo, ETag e data maxima no conteudo sao **quatro provas da mesma coisa** (o arquivo nao foi regerado) quando vem do mesmo servidor. Nenhuma delas prova que a origem parou. Para separar as hipoteses, comparar com outro ramo do mesmo portal e com o sistema interativo.
  Fonte com 4 dias uteis no meio da semana e o comportamento normal dela. O gate hoje e `CVM_FONTE_MAX_CICLOS = 2` ciclos semanais, ou seja 14 dias corridos, e o sinal vive em `fonte_externa_ok`, nunca no `ok` agregado.
- **Grandeza x unidade x rotulo, os tres tem que bater (SPREADUNIDADE1, 2026-08-20).** Achado P0 real: o card do painel dizia "Spread ANBIMA" e carimbava " bps" sobre `taxa_indicativa` da ANBIMA, publicada em percentual ao ano. Petrobras aparecia como "6,98 bps" para o cliente pago, erro de fator 100 sob um nome que nem era o da grandeza. A causa estava na ingestao: o parser grava `spread_bps` a partir da coluna de taxa indicativa (api/src/worker.js, grep "idx.spread_bps", ~L13154), e desde v4.9.205 (SPREADSERIE1) o nome canonico da serie no KV e `taxa_indicativa_pct`, com `spread_bps` mantido como alias do mesmo valor so para compatibilidade. Auditar sempre: para todo numero na tela, conferir os TRES, o que a fonte publica, em que unidade, e o que o rotulo promete. O `audit-ui-metrics.mjs` pega rotulo x formula, nao pega unidade. Unidade e conferencia humana, e comeca no parser, nao no template.
- **Alerta que nao nomeia a causa (HEALTHWATCH3, 2026-08-20):** vigia que le so o agregado `ok` e reemite "ok=false" a cada 15 min treina o operador a ignorar. O `watch-vixradar-health.ps1` passou 3 dias assim com a fonte da CVM parada. Auditar: todo alerta automatico tem que citar qual campo especifico ficou vermelho.
- Grep por estado global de request (`let`/`const` de modulo mutado dentro de `fetch`/`scheduled`) e por chamada async sem `await`/`return`/`ctx.waitUntil` (floating promise) no bundle ativo.
- XSS admin/PDF: campos de usuario e de evento em `innerHTML` / `document.write` devem passar por escape (`h()`/`esc()`); registro no Worker deve rejeitar caracteres HTML em nome/empresa (ADMINXSS1/PDFXSS1).

## Contexto operacional recente (pos 2026-08-20)

Incidentes e rotinas novos que a matriz ainda nao detalha. Cada tag aponta o que
conferir, nao resumo; a semantica de cada tag esta no changelog do `api/wrangler.toml`
e o detalhe no vault (`Obsidian VIX Radar/PENDENCIAS.md`).

- **SENTINELA1 (v4.9.216) e a varredura por gatilho:** modo "pontual" em `montarPlanoRotina`/`listar_plano_rotina`, teto `ROTINA_PONTUAL_TETO=8` e excedente declarado em `pontual_candidatos`/`pontual_excedente`, nao cortado em silencio. O gatilho so dispara por FATO NOVO (documento CVM que ninguem olhou, identidade por protocolo ausente de `radar:cvm_vistos:{empresa}`) ou DIVIDA (analise barrada pelo teto de tokens). EWS e staleness nao entram de proposito, ja sao cobertos pelas passadas diarias. O corte por data ficou estrito (dt < since); `_cvmNovosDesde` por `YYYY-MM-DD` morreu no v4.9.216. Conferir a rotina `VIXRadar-Sentinela` (Seg-Sex, :25/:55, teto 120k tokens) e que a execucao sai em 0 token na maioria das vezes.
- **DEFERGRUDA1/2/3 (v4.9.217-219):** a bandeira `_token_cap_deferred` ligava e nunca desligava, e a leitura multi-semana ressuscitava a bandeira que a escrita ja tinha apagado. Sintoma em producao: emissor deferido voltava em toda execucao pontual e virava FULL permanente na noturna (backlog de 34 medido em 25/08). Depois do v4.9.219, "inconclusivo" saiu do gatilho da pontual (analise Haiku nao atingia `_coberturaMin` e fabricava o proprio trabalho). Conferir que a pontual converge, que nao reapresenta emissor ja submetido, e que `_token_cap_deferred` e gravado e apagado nos 5 ramos de persistencia.
- **STATUSGRUDA1 (v4.9.220):** `_status` descreve a ULTIMA VARREDURA ("concluiu"/"nao concluiu"), nao o acervo de eventos. O ramo multi-semana "semana nova sem evento, semana velha com evento" devolve o objeto da semana velha para nao perder conteudo, mas `_status`/`_motivo` sao sempre da semana corrente. Conferir que o `inconclusivo_stale_breakout` do plano noturno enxerga emissores com `_status:"INCONCLUSIVO"` e que nenhuma tela mostra `_status` da semana velha ao lado de evento da corrente.
- **SUBSTRINGDONO1 (v4.9.215):** atribuicao de documento CVM agora e por CNPJ. `_donoDocumentoCVM` (api/src/worker.js, ~L7655) arbitra com ancora de inicio de palavra e termo mais longo vencendo; `CNPJ_PRIMARIO_EMISSOR` (ITR/balanco) e `CNPJ_FAMILIA_CVM` (holding + subsidiarias) sao separados de proposito para a familia nao vazar no primario. Nome vira excecao (entidade estrangeira). Sem-match vai a `admin_cvm_quarentena`. Health expoe `cvm_atribuicao_por_cnpj`/`por_nome`/`quarentena`/`cobertura_pct`/`descartados_teto`, fora do `ok` agregado. Conferir que emissor renomeado nao fica cego.
- **CVMURL404 / CVMDURA1 (v4.9.209-210):** 404 do ZIP `ipe_cia_aberta_*.zip` repergunta o catalogo CKAN (ano do ZIP pelo relogio BRT com fallback pelo catalogo). Falha DURA de sync derruba `fonte_externa_ok` na hora, sem usar a tolerancia semanal de `CVM_FONTE_MAX_CICLOS`. Campos no health: `cvm_fonte_falha_dura`, `cvm_fonte_degrada_servico`, `cvm_fonte_ultimo_sync_ok_em`, `cvm_fonte_falhas_consecutivas`, `cvm_fonte_ciclos_perdidos`. TTL de `cvm:documentos` e 30 dias desde o v4.9.210. Conferir que alerta nenhum le so o agregado `ok`.
- **EMAILSILENT1 (v4.9.214):** todo envio ao usuario final passa por `enviarEmailRastreado`, que nunca lanca (a acao primaria continua valendo). Quatro canais: `console.error`, Sentry, Analytics Engine e KV `email_envio:{email}:{ts}` (TTL 90d, igual bounce). Respostas de aprovar/rejeitar carregam `email_enviado`/`email_erro`/`resend_id` (tri-estado). Conferir que todo caminho novo de envio ao usuario usa o helper e que nenhuma resposta de admin mente sobre envio.
- **SPREADSERIE1 (v4.9.205):** o nome canonico da serie da ANBIMA no KV passou a ser `taxa_indicativa_pct`; `spread_bps` ficou como alias com o mesmo valor, so para nao quebrar consumidor antigo. Conferir que leitores novos usam `taxa_indicativa_pct` e que nenhum card carimba " bps" sobre percentual ao ano.
- **Scheduler real (INVERSAO-CD1):** as rotinas Claude Desktop (matinal, noturno, verificacao async) agendam no CCD store `%APPDATA%\Claude\claude-code-sessions\<conta>\<device>\scheduled-tasks.json`, lido pelo app so na ativacao. As tasks homonimas no Windows Task Scheduler ficam `Disabled` de proposito, guarda anti-duplicata. Ao validar rotinas, conferir o CCD store e a linha `FIM:` no log em `logs/routines/`, nunca o `LastTaskResult`.

## Severidade

| Nivel | Criterio |
|---|---|
| P0 Critico | Perda de dados, auth fail-open, secret exposto, ingestao cega, prod quebrada, drift perigoso |
| P1 Alto | Telemetria ausente, verificador degradado, admin inseguro, frontend derruba sessao, cron inconsistente |
| P2 Medio | Divida tecnica com risco claro, cache/version drift, a11y/perf com impacto real, testes faltando em fluxo critico |
| P3 Baixo | Limpeza, organizacao, docs, melhorias de DX, refatoracao sem impacto imediato |

## Saida esperada

Entregar relatorio curto e acionavel:

```markdown
# Auditoria Geral — VIX Radar (YYYY-MM-DD)

## Veredito
[saudavel / degradado / critico em 2-4 frases. Nunca "sem erros": dizer o que foi coberto e com que metodo]

## Top riscos
| Sev | Area | Achado | Evidencia | Correcao | Causa raiz | Guarda sistemica |

## Backend
[achados confirmados, lacunas]

## Frontend
[achados confirmados, lacunas]

## Veracidade da UI
[saida do audit-ui-metrics.mjs + conferencia manual dos termos reservados]

## Seguranca, perf e a11y
[achados confirmados, lacunas]

## IA generativa / cascade LLM
[achados confirmados mapeados ao OWASP LLM Top 10, lacunas]

## Cobertura desta auditoria
| Camada | Coberta | Metodo | Lacuna |
[dizer explicitamente o que NAO foi verificado e por que]

## Proximos passos
[P0/P1/P2 em ordem]
```

Ao final de auditorias relevantes, registrar resumo e pendencias no Obsidian, conforme `CLAUDE.md`. Se a auditoria produziu guarda sistemica nova (script, item de checklist, termo de glossario), registrar tambem qual arquivo da skill mudou.
