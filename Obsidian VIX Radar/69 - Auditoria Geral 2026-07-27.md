---
data: 2026-07-27
tipo: auditoria
tags: [vix-radar, auditoria, geral, backend, frontend, ui-semantica]
status: ativo
---

# Auditoria Geral, 2026-07-27

Primeira execucao da skill `vix-radar-general-audit` depois do hardening do mesmo dia
(camada de veracidade da UI, glossario de dominio, disciplina de causa raiz).

## Veredito

Sistema operacionalmente saudavel. Worker v4.9.181 com `ok:true`, bindings todos
verdes, verificador ok, providers 2/2. Frontend v201.92 recem-deployado, `deploy_zip`
identico a fonte viva, apex e www validados.

Cobertura desta rodada foi PARCIAL e por um motivo que precisa ficar registrado: a
infraestrutura de subagentes estava fora do ar (todos roteando para
`deepseek-v4-flash`, modelo inacessivel), entao as 5 fatias que seriam paralelas
foram feitas em serie pelo loop principal, com menos profundidade. Backend,
frontend, IA e performance receberam varredura dirigida por grep e leitura de
trechos; nao houve leitura exaustiva do bundle de 16k linhas. Ver "Cobertura" no fim.

## Adendo 13h40: a auditoria estava mirando no lugar errado

Escrito depois do relatorio abaixo, e ele merece ser lido com esta ressalva na frente.

A camada de "veracidade da UI" criada hoje parte de uma premissa boa (rotulo que afirma o
que o codigo nao apurou) e de uma implementacao estreita: o detector so le HTML. Nas horas
seguintes a mesma doenca apareceu duas vezes **fora** do HTML, e as duas mais graves que a
original:

| # | Onde | O que afirma | O que realmente apura |
|---|---|---|---|
| 1 | `app/index.html`, card "Cobertura 62%" | cobertura de varredura | emissores sem alerta em 30d |
| 2 | `scripts/monitor-tasks.ps1:158` | "Credit balance too low" | nada, deduz pelo **nome da task** |
| 3 | `scripts/run_vixradar_matinal_claude.ps1:421` | `buscas=<executadas>` | numero **autodeclarado pelo modelo** |

O caso 3 nao e teorico. Em 27/07 13:32 a matinal fechou com `buscas=12` num lote onde as 12
buscas retornaram "WebSearch indisponivel", e gravou 18 emissores em producao com zero
rodadas do protocolo, tres deles classificados CRITICO. Todos os indicadores de saude da
rotina ficaram verdes: `submit_fail=0`, `auth_fail=0`, `silent_fail=0`. Detalhe completo em
[[PENDENCIAS]], item P1 "A matinal reportou sucesso com 100% das buscas falhando".

**A generalizacao correta do achado do card nao e "auditar rotulo de HTML".** E:

> Toda metrica que o sistema exibe ou registra precisa ter uma fonte apurada. Se o numero vem
> de autodeclaracao (do modelo, do nome de um objeto, de uma constante), ele nao e metrica,
> e legenda. Auditar significa achar a distancia entre o nome e a fonte.

Aplicado a rotina, isso tem um teste barato: pegar cada contador que a rotina emite no `FIM:`
e perguntar quem produziu aquele numero. `tokens` vem do envelope JSON da CLI, apurado.
`submit_ok` vem da resposta do Worker, apurado. `buscas` vem do texto que o modelo escreveu,
**nao apurado**. Levou trinta segundos e nao estava no escopo da auditoria.

**Consequencia para a skill:** `audit-ui-metrics.mjs` cobre so o caso 1 e continua util, mas
a camada precisa de um irmao que varra scripts de rotina procurando contador cuja origem seja
saida de LLM ou constante, nao medicao. Sem isso a auditoria repete o erro de hoje: aprova o
sistema olhando os numeros que o proprio sistema escolheu contar.

## Achados

### P3, painel de anomalias pinta valor com sinal sempre de vermelho

`app/index.html:3974`. No bloco `anomalia-dado`, o campo "Variacao" usa
`class="anomalia-dado-val neg"` fixo, mas o valor e explicitamente com sinal:
`(n.delta_pp>0?"+":"")+n.delta_pp+" p.p."`. O proprio codigo formata o "+", ou seja
valores positivos ocorrem. O irmao ao lado, "Spread atual", ja calcula a direcao:
`${"abertura"===a.dados?.direcao?"neg":"warn"}`.

Mesma classe do bug do card "Cobertura" corrigido hoje: dentro do mesmo painel um
elemento sabe calcular severidade e o vizinho ignora. Severidade menor porque e
painel de detalhe, nao KPI de topo, e porque no contexto de anomalia quase tudo e
ruim mesmo. Mas o encoding continua mentindo sobre a direcao.

**Causa raiz:** mesma do achado original, ausencia de contrato de indicador. O
glossario criado hoje ja cobre isso (campo "Faixas"), mas foi escrito depois deste
codigo.
**Guarda:** o detector deveria ter pego e nao pegou, ver achado seguinte.

### P3, o detector de veracidade da UI tem janela curta demais (gap na propria guarda)

`scripts/audit-ui-metrics.mjs`. O check bloqueante pareia slots de severidade dentro
de uma janela de 260 caracteres. No painel de anomalias o slot dinamico e o literal
estao a **570 caracteres** de distancia, medido, entao o par passou batido. O caso
acima foi achado por leitura manual, nao pela ferramenta.

Testei subir a janela para 700: **nao resolveu** (o pareamento morre antes, por slot
intermediario) e **introduziu falso positivo**, casando o chip do card "Criticos" com
o `mo-pulse` do cabecalho, que sao componentes distintos. Revertido para 260 em vez
de entregar um detector pior.

**Correcao de verdade:** trocar janela por caracteres pela fronteira real do elemento,
ou seja parse de DOM em vez de regex sobre string.
**Consequencia operacional imediata, ja anotada no script:** `exit 0` NAO significa
"UI toda coerente", significa "nenhum par proximo incoerente". A auditoria nao pode
usar o exit code como prova de ausencia.

### P2, 33 blocos `<script>` inline, nenhum com `defer` ou `async`, em HTML de 700 KB

`app/index.html`. Todo o JS e inline e bloqueante. Impacto direto em LCP. E divida
estrutural conhecida (a mesma razao pela qual o `_headers` documenta explicitamente
nao aplicar CSP restritiva), nao regressao nova.
**Lacuna:** nao medido. LCP/INP/CLS em ms exigem lab real, nao foram coletados.

### P3, 3 imagens sem `width`/`height` declarados

Risco de CLS. Baixo volume.

### P3, `exit` em vez de `return` nos scripts de rotina

`scripts/run_vixradar_verificacao_async.ps1` usa `exit` em 7 pontos (404, 411, 419,
422, 434, 441, 644). O `CLAUDE.md` global proibe `exit` em script PowerShell. Hoje
funciona porque as rotinas rodam em processo proprio via Scheduler, mas quebra se
alguem dot-source ou chamar de outro script.

## Checado e OK

- **Bindings**: `RADAR_KV`, `RATE_LIMITER_DO`, `ESTADO_SEMANA_DO`, `RADAR_USAGE_EVENTS` todos declarados no `wrangler.toml` e vivos no health. Route `api.vixradar.com` presente. `nodejs_compat` presente. `compatibility_date` 2026-06-16, ~6 semanas, dentro do aceitavel.
- **VERSAO3X**: `main = "v4.9.181.js"` bate com o health (`versao: v4.9.181`).
- **Floating promises**: zero ocorrencias do padrao `fetch(...).then` solto.
- **`ctx.waitUntil`**: 2 usos, ambos com `.catch` ou IIFE async. Nenhuma desestruturacao `const { waitUntil } = ctx` (evita "Illegal invocation").
- **Estado global entre requests**: `aplicarConfigRuntime` muta `ADMIN_EMAIL` e `NEWSLETTER_DESTINATARIOS` (escopo de modulo) dentro de `fetch` e `scheduled`. **Nao e o bug critico**: os valores derivam de `env`, que e identico para todas as requests do mesmo Worker, entao nao ha vazamento de dado entre usuarios. Registrado aqui para nao ser relevantado como P0 na proxima auditoria. O fallback `env2222.ADMIN_EMAIL || ADMIN_EMAIL` (linha 5166) e redundante, nao perigoso.
- **Secrets**: nenhum literal hardcoded. `ADMIN_EMAIL` migrado para secret em 24/07. `ROUTINE_API_KEY` lida de `$env:` em todos os 4 scripts de rotina, com `throw` se ausente, nunca literal.
- **`sem_eventos`**: bem defendido. Prompt exige `cobertura_nota` provando as 9 rodadas, e o Worker distingue `INCONCLUSIVO` (cobertura rasa) de ausencia comprovada, preservando estado anterior em vez de sobrescrever com falso negativo.
- **Model IDs**: `claude-haiku-4-5-20251001` e `claude-sonnet-4-6` pinados literalmente.
- **Sync frontend**: `app/index.html` identico a `app/deploy_zip/index.html`. Modulos admin sincronizados.
- **CSS `strong`**: `app/index.html:2798` declara so `font-weight: 600`, sem `color`. Regra do projeto respeitada.
- **Headers de seguranca**: HSTS com preload, X-Frame-Options DENY, nosniff, Referrer-Policy, Permissions-Policy. `index.html` com `no-cache, must-revalidate`.
- **Shadow mode Fable 5** (codigo novo, sem auditoria previa): guards bem feitos. Teto proprio de 300k tokens, dedup por hash intra-dreno, `-NoFallback` para nao virar Sonnet-vs-Sonnet, try/catch isolando excecao para nunca derrubar o lote, tratamento explicito de `refusal` e de auth failure. Cobre LLM10 adequadamente.
- **Verificacao async**: mutex global contra dreno concorrente, hard cap medido PRE-lote (defere em vez de estourar), cache VERIFCACHE1 economizando ~35k tokens por evento repetido, extrator de JSON balanceado (corrige o bug historico do `LastIndexOf(']')`).
- **Merton**: `scoreMertonToRisk` em `v4.9.181.js:13132`, driver `merton` empurrado sempre que `_mPts > 0`, nao so quando `dd < 1.5`. MERTONLIVE1 continua correto.
- **Debounce**: presente no filtro de busca.

## Cobertura desta auditoria

| Camada | Coberta | Metodo | Lacuna |
|---|---|---|---|
| Repo e governanca | Sim | `git status`, `git log`, drift de versao | — |
| Backend Worker | Parcial | grep dirigido + leitura de trechos | Sem leitura exaustiva das 16k linhas. Auth/CORS por endpoint nao testado com request real |
| Frontend | Sim | diff sync, grep, detector automatizado | — |
| Veracidade da UI | Parcial | `audit-ui-metrics.mjs` + revisao manual | Detector com gap de janela documentado acima. Indicadores em `admin/*.js` nao inventariados |
| Seguranca | Parcial | grep de secrets, headers, escape | Sem teste dinamico. POST anonimo em rota protegida nao exercitado |
| Performance | Estatica | contagem de scripts, tamanho, imagens | **LCP/INP/CLS nao medidos**, exigem lab real |
| Acessibilidade | Nao | — | **Nao coberta nesta rodada** (queda dos subagentes) |
| IA / LLM | Parcial | OWASP LLM Top 10 contra codigo + shadow novo | LLM01/LLM07 nao exercitados com payload adversarial real |
| Preditivo | Parcial | Merton driver + pinning | Efeito em cascata da coleta de volatilidade parada nao rastreado ate o payload |

## Proximos passos

1. P2, avaliar `defer` nos blocos de script ou extrair JS para arquivo versionado. Ataca o LCP e e pre-requisito para CSP algum dia.
2. P3, corrigir o `anomalia-dado-val neg` para calcular direcao como o irmao ja faz.
3. P3, reescrever o pareamento do detector por fronteira de elemento em vez de janela de caracteres.
4. P3, trocar `exit` por `return` nos scripts de rotina.
5. Repetir esta auditoria com subagentes quando a infraestrutura voltar, cobrindo acessibilidade e o backend em profundidade.

---

*Auditoria executada em 2026-07-27 pelo loop principal, sem paralelismo de subagentes. Health colado no relatorio da sessao. Skill usada: `vix-radar-general-audit`, versao pos-hardening do mesmo dia.*
