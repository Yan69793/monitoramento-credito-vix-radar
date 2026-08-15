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
---

# VIX Radar General Audit

Auditoria ampla de engenharia para o VIX Radar. Esta skill complementa
`vix-radar-audit`: use `vix-radar-audit` para health operacional/producao e esta
skill para revisao de backend + frontend + qualidade do projeto.

## Antes de auditar

1. Ler `CLAUDE.md`, `.claude/SKILLS-ROUTER.md`, `Obsidian VIX Radar/00 - Indice (MOC).md` e `Obsidian VIX Radar/03 - Estado Atual.md` (antes se chamava `03 - Estado de Producao.md`; nao recriar o nome antigo).
2. Ler a matriz em `references/audit-matrix.md` (snapshot revisado em 2026-07-27).
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
   node "E:\Diretorio\Claude\.claude\skills\vix-radar-general-audit\scripts\audit-ui-metrics.mjs" "E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito\app\index.html"
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
- Confirmar que endpoints multi-semana usam `carregarEstadoMultiSemana(env, 5)`.
- Confirmar regra CSS global: `strong` sem `color`, apenas `font-weight`.
- Confirmar que `app/deploy_zip/` esta sincronizado com `app/` antes de qualquer deploy Pages.
- **Veracidade da UI (UISEMANTICA1, 2026-07-27):**
  - Rotulo x formula: cada indicador exibido mede exatamente o que o rotulo diz, conforme `references/glossario-dominio.md`. Termo reservado usado com outro sentido e bug de produto, nao preferencia de estilo.
  - Cor semantica acompanha o dado: classe de severidade nunca literal sobre valor que atravessa faixas. Se o selo calcula a faixa e o numero nao, o card se contradiz.
  - Janela declarada e a janela usada: se a tela tem filtro de periodo (7D/30D), verificar quais indicadores obedecem e quais tem janela fixa. Indicador com janela fixa ao lado de um filtro precisa dizer isso.
  - Denominador explicito: todo percentual declara numerador e denominador. `62%` sem base e irrastreavel.
  - Rotulo sem fonte: numero na tela que nao tem formula localizavel no codigo e achado, nao detalhe.
- **Providers no health (OPENROUTERVIVO, atualizado 2026-08-15):** nao tratar `openrouter`/`perplexity` como residuo de schema por padrao. Caminho vivo: `verificarSaldoOpenRouter` (worker.js ~13886, consulta saldo da conta OpenRouter usada para monitorar o Perplexity). Nao existe probe de health ativo do Perplexity: o call site `chamarOpenRouter` (~14015) ficou orfao quando a funcao foi removida no v4.9.180 (ReferenceError engolido, status sempre `erro_desconhecido`, nivel >= amarelo com email falso de providers desde 30/07) e foi desligado na auditoria de 15/08 (OPENROUTER-ORFAO1): `perplexity` agora e constante `{status:"removido"}`. `probeOpenRouterSonarPro`/`probeOpenRouterExa` foram REMOVIDOS no v4.9.180 (OPENROUTER-DEAD, worker.js:7486), nao procurar por eles. OpenRouter nao esta no cascade de analise de credito (saiu no v4.9.108). Gemini permanece residuo de schema salvo evidencia nova de uso. Confirmar se `OPENROUTER_API_KEY` existe e se `verificarSaldoOpenRouter` gasta ou contamina sinal de saude.
- Confirmar que o verificador adversarial (`v4.9.146+`) segue no caminho critico de `receber_analise`, nao contornado; fila `radar:verif_fila:{data}` sem lock (VERIFQ-ORFAO1); teto/guarda contra `Credit balance is too low` e auth OAuth nas rotinas (cobranca via assinatura, nao metered `ANTHROPIC_API_KEY` no processo filho).
- **Idempotencia e metrics de rotina (METRICSZERO1):** matinal e noturna devem ter skip idempotente; no caminho de skip, metrics JSON nao pode zerar o run real do dia (preservar numeros ou gravar `skipped_idempotente:true`).
- **Preditivo Merton (MERTONLIVE1):** `calcMertonDD` / `scoreMertonToRisk` movem score em producao. Checar se driver `merton` aparece quando o score muda, se a coleta `VIXRadar-Coleta-Volatilidade` roda (LastTaskResult 0), e se o modelo esta documentado no vault/PENDENCIAS.
- Grep por estado global de request (`let`/`const` de modulo mutado dentro de `fetch`/`scheduled`) e por chamada async sem `await`/`return`/`ctx.waitUntil` (floating promise) no bundle ativo.
- XSS admin/PDF: campos de usuario e de evento em `innerHTML` / `document.write` devem passar por escape (`h()`/`esc()`); registro no Worker deve rejeitar caracteres HTML em nome/empresa (ADMINXSS1/PDFXSS1).

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
