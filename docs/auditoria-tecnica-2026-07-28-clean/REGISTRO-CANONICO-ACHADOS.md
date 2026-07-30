# Registro Canônico de Achados — VIX Radar

Auditoria técnica completa, 2026-07-28/29.
Worker produção: v4.9.183, Frontend: v201.93, Health: HTTP 200, ok:true.
Base no repo: `main` (fdae5cb), wrangler.toml declara main = "v4.9.182.js".

Taxonomia de certeza: COMPROVADO (data, comando ou URL e saída registrada),
CORROBORADO (múltiplas fontes independentes, sem medição direta),
INFERÊNCIA (dedução lógica de código/documentação, sem observação de runtime),
LACUNA DE RUNTIME (condição que exige execução/consulta externa para fechar).

Rubrica: P0 (usuário vê dado errado com selo de certeza, ou sistema mente sobre
saúde), P1 (degrada operação ou cobertura), P2 (degrada confiabilidade ou
auditabilidade), P3 (higiene, conveniência, cosmético).

---

## 1. DEPLOY E DRIFT (família OPS)

### OPS-DRIFT-001: wrangler.toml aponta v4.9.182, produção roda v4.9.183

**Severidade**: P0
**Certeza**: COMPROVADO
**Família**: OPS

**Evidência**:
- `api/wrangler.toml:469`: `main = "v4.9.182.js"`
- Health público 2026-07-29T01:53:28.553Z: `"versao":"v4.9.183"`
- `api/v4.9.183.js` NÃO existe em `main`, só nos branches codex
- PROVENIENCIA-v4.9.183.md (commit 2bfe424): "Este commit não altera
  api/wrangler.toml, que segue declarando main = 'v4.9.182.js'. Enquanto essa
  linha não for corrigida para 'v4.9.183.js' com no_bundle = true, um deploy
  disparado a partir do repositório republica a v4.9.182 e reverte produção."

**O que um deploy de main reverteria**:
1. CAL-003: `op=calendario` deixaria de aplicar overrides de KV — datas
   corrigidas pelo admin somem do selo
2. VOL-001: `market_cap` volta a usar preço por ação com guarda `> 100`
   que aceita valores errados
3. VOL-003: SELIC hardcoded `0.1375` retorna, sem `as_of` e sem validação
4. CI fail-open corrigidos no codex (scan-emergencia exit 0 em ok:false,
   coleta engole LASTEXITCODE) voltam
5. Build reprodutível (`api/src/worker.js` + `build-worker.ps1`) deixa
   de existir — a fonte canônica não está em main
6. `.gitattributes` (CRLF/LF determinístico) não existe em main
7. Correções de encoding PowerShell 5.1 das rotinas são revertidas

**Causa raiz**: A preservação do artefato e a correção estrutural foram feitas
em branches codex (preservar-v4.9.183-producao, system-finalization-v4.9.183)
sem merge para main. O deploy real usou o branch codex, não main.

**Correção proposta**: Merge do branch `codex/system-finalization-v4.9.183`
(PR #18) para main. Atualizar `api/wrangler.toml` main para v4.9.183.js.
Validar que `no_bundle = true` está ativo no deploy.

**Guarda**: `deploy-worker.ps1` deve comparar o SHA-256 do bundle local com o
módulo publicado em `/content/v2` ANTES de subir, e abortar se divergirem com
o wrangler.toml atual. Hoje o script só valida WORKER_VERSAO interno e health
pós-deploy.

---

### OPS-DRIFT-002: deploy-worker.ps1 não valida hash contra produção

**Severidade**: P2
**Certeza**: COMPROVADO
**Família**: OPS

**Evidência**: Leitura completa de `scripts/deploy-worker.ps1` (176 linhas).
O script verifica:
- WORKER_VERSAO interno bate com nome do arquivo (linhas 66-72)
- Health pós-deploy (linhas 107-128): versão viva, ok, kv, telemetria
NÃO verifica:
- SHA-256 do bundle local contra o módulo publicado em produção
- Se o deploy vai regredir produção (bundle local mais antigo que o publicado)

**Causa raiz**: O guard anti-drift atual é reativo (pós-deploy), não preventivo
(pré-deploy). O `canonical-test.yml` detecta drift depois do fato.

**Correção proposta**: Adicionar passo pré-deploy que lê o módulo atual de
`/content/v2`, calcula SHA-256 do bundle local (na mesma convenção CRLF/LF),
e aborta se o bundle local é mais antigo que o publicado ou se o hash local
diverge do remoto quando o wrangler.toml declara a mesma versão.

**Guarda**: O `build-worker.ps1` (introduzido no codex/system-finalization)
garante build reprodutível. Juntar com validação pré-deploy fecha o circuito.

---

## 2. SEGURANÇA (família SEC)

### SEC-FILE-001: recovery-codes.txt fora do .gitignore

**Severidade**: P2
**Certeza**: COMPROVADO
**Família**: SEC

**Evidência**:
- `recovery-codes.txt` existe na raiz, 107 bytes
- `git ls-files --others --exclude-standard` lista o arquivo (não ignorado)
- `.gitignore` não contém `recovery-codes.txt` nem padrão que o cubra
- NUNCA entrou no histórico git (`git log --all --oneline -- "recovery-codes.txt"` retorna vazio)
- Conteúdo NÃO foi lido (instrução explícita da auditoria)

**Causa raiz**: As regras de `.gitignore` cobrem `*TOKEN*.txt`, `*token*.txt`,
`*SECRET*`, mas `recovery-codes` não casa com nenhum desses padrões.

**Correção proposta**: Adicionar `recovery-codes.txt` ao `.gitignore`.
Verificar se o conteúdo ainda é válido ou se deve ser armazenado em cofre
segregado (1Password, vault do Windows).

**Guarda**: Incluir `*recovery*` e `*backup*codes*` nos padrões de
`.gitignore` já existentes para credenciais.

---

### SEC-FILE-002: Diretório .codex/system-final-stage/ com conteúdo extenso não versionado

**Severidade**: P2
**Certeza**: COMPROVADO
**Família**: SEC

**Evidência**: `git ls-files --others --exclude-standard` lista 44 arquivos em
`.codex/system-final-stage/`, incluindo:
- `.github/workflows/*.yml` (cópias dos workflows CI)
- `api/v4.9.*.js` (bundles antigos: .109 a .124, .182, .183)
- `api/wrangler.toml` (configuração de Worker)
- `app/index.html`, `app/deploy_zip/index.html` (frontend)
- `scripts/*.ps1` (scripts de deploy e rotinas)
- `CLAUDE.md`, `README.md`

O diretório `.codex/` está no `.vercelignore` mas NÃO no `.gitignore`.
A regra `.codex/*` no `.gitignore` NÃO cobre `.codex/system-final-stage/`
porque o padrão `*` não casa com `/` — precisa ser `**` para recursão.

**Risco**: Contém cópia do wrangler.toml e bundles que, se modificados e
executados por engano, poderiam afetar produção.

**Correção proposta**: Consolidar com os branches codex equivalentes ou
remover. Se for artefato de trabalho de agente, arquivar em `archive/`.
Garantir que `.codex/` inteiro está no `.gitignore` (usar `**`).

**Guarda**: Regra `.codex/` no `.gitignore`.

---

### SEC-FILE-003: scripts/setup-deploy-credential.ps1 versionado e potencialmente expõe credencial

**Severidade**: P2
**Certeza**: CORROBORADO
**Família**: SEC

**Evidência**:
- `scripts/setup-deploy-credential.ps1` (1643 bytes) está versionado (tracked)
- 2 commits no histórico: 361f096 e 201ebda
- O nome sugere que contém credencial de deploy hardcoded
- Conteúdo NÃO foi aberto (instrução da auditoria)

**Correção proposta**: Revisar o conteúdo. Se contiver credencial, removê-la
do histórico com BFG ou git filter-branch, mover para vault/cofre, e adicionar
ao `.gitignore` com padrão `scripts/setup-deploy-credential.ps1`.

---

### SEC-FILE-004: logs/monitor-tasks/ não coberto pelo .gitignore

**Severidade**: P3
**Certeza**: COMPROVADO
**Família**: SEC

**Evidência**: `.gitignore:153` cobre `logs/routines/` mas NÃO `logs/monitor-tasks/`.
`logs/monitor-tasks/erros_20260728.json` (4863 bytes) aparece como untracked.
Pode conter dados operacionais.

**Correção proposta**: Alterar a regra `logs/routines/` para `logs/` no `.gitignore`.

---

### SEC-FILE-005: package.json injetado por bot Vercel entrou no histórico git

**Severidade**: P3
**Certeza**: COMPROVADO
**Família**: SEC

**Evidência**:
- Commit 709409e (Vercel bot, 2026-07-21): adicionou package.json,
  package-lock.json, e modificou app/index.html
- package.json declara dependência `@vercel/analytics` v1.4.1
- O projeto NÃO é Node.js, NÃO usa npm — é vanilla JS servido por
  Cloudflare Pages
- `.gitignore` não lista `package.json` nem `package-lock.json`

**Risco**: Baixo imediato (não expõe segredo), mas polui o projeto com
dependência fantasma. A integração Vercel tem permissão de escrita no repo.

**Correção proposta**: Reverter o package.json e package-lock.json se não
forem necessários. Adicionar `package-lock.json` ao `.gitignore`. Remover
a integração Vercel ou restringir para leitura.

**Guarda**: `.gitignore` com `package-lock.json` e revisão de permissões
de integrações de terceiros no repo.

---

## 3. SUPERFÍCIE VERCEL (família OPS)

### OPS-VERCEL-001: Integração Vercel injetou tracking e tem branches remotos ativos

**Severidade**: P2
**Certeza**: COMPROVADO
**Família**: OPS

**Evidência**:
- Commit 93eaaa7 (Vercel bot, 2026-07-21): injetou Speed Insights em
  app/index.html e app/deploy_zip/index.html
- Commit 709409e (Vercel bot, 2026-07-21): injetou Web Analytics e criou
  package.json
- Commit 4211bbc (operador, 2026-07-28): criou `.vercelignore` como reação
  defensiva para impedir compilação de bundles Worker
- Branches remotos: origin/vercel/vercel-speed-insights-to-proje-q8158k,
  origin/vercel/vercel-web-analytics-to-projec-0z32qg
- PR #18 tem status check Vercel vermelho, mas o mesmo status falha em
  origin/main e na PR #17 (não é regressão desta entrega)

**O que a Vercel serve**: NADA. Confirmado por investigação completa do agente
Vercel: os branches `origin/vercel/vercel-speed-insights-to-proje-q8158k` e
`origin/vercel/vercel-web-analytics-to-projec-0z32qg` nunca foram mergeados para
main. Não há `vercel.json`, `.vercel/project.json`, webhook de deploy nem
integração ativa. Os snippets de script (`/_vercel/insights/script.js`,
`/_vercel/speed-insights/script.js`) NÃO existem em produção. Ambos os branches
estão 63 commits atrás de main.

**Como os scripts entraram no repo**: O bot Vercel (provavelmente via integração
GitHub + Vercel que o operador conectou e depois abandonou) criou dois branches
e dois commits em 21/07, injetando tags `<script>` em `app/index.html` e
`app/deploy_zip/index.html`. Nenhum dos dois branches foi mergeado, então as
tags NUNCA chegaram ao frontend servido por Cloudflare Pages.

**O `.vercelignore`**: Adicionado em 28/07 (commit 4211bbc) como medida
defensiva para impedir que, caso a integração seja reativada, a Vercel tente
compilar os bundles do Worker (`api/`) como funções serverless Node.js.

**Permissões**: O bot Vercel tem permissão de commit no repositório
(comprovado pelos commits de 21/07), mas não tem deploy hook ativo.

**Divergência vs Cloudflare Pages**: Nenhuma. A Vercel não publica nada.
O deploy oficial é exclusivamente Cloudflare Pages.

**Correção proposta**: Remover a integração Vercel do repo (Settings >
Integrations > GitHub). Os branches vercel podem ser deletados sem risco.
Limpar as tags de script de analytics dos branches caso ainda estejam no
index.html de main (verificar — o agente UI leu o index.html e não reportou
tags Vercel, sugerindo que já foram removidas ou nunca chegaram a main).

**Guarda**: Revisão periódica de integrações de terceiros com permissão de
escrita no repo.

---

## 4. CALENDÁRIO 2T26 (família CAL)

Nota: a auditoria de 28/07 (relatórios 00-04 na raiz do repo) mapeou
exaustivamente a família CAL. Os achados abaixo consolidam o que já estava
documentado e acrescentam o estado pós-v4.9.183.

### CAL-002: Bradesco e Vale com datas erradas exibidas como AGENDADO

**Severidade**: P0 (ativo em 28/07, contido em v4.9.183/v201.93)
**Certeza**: COMPROVADO
**Família**: CAL

**Evidência** (relatório 03, seção 3):
- Bradesco RI oficial: 05/08 após fechamento. Sistema: 28/07 AGENDADO.
  28/07 cai dentro do período de silêncio declarado pelo banco (22/07 a
  05/08). Data comprovadamente impossível.
  Fonte: `https://www.bradescori.com.br/informacoes-ao-mercado/agenda-2t26/`
  (HTTP 200, 66789 bytes, 2026-07-28T08:00Z)
- Vale RI oficial: 30/07 após fechamento. Sistema: "Última divulgação
  24/07". A data oficial ainda não ocorreu. O sistema exibe como fato
  pretérito um evento que nunca aconteceu.
  Fonte: `https://vale.com/pt/w/vale-divulga-as-datas-para-o-relatorio-de-desempenho-no-2t26`
- Petrobras: não confirmada. Data 28/07 exibida como AGENDADO sem fonte
  primária.

**Status pós-v4.9.183**: CORRIGIDO NA SUPERFÍCIE. O frontend v201.93
(CAL-002) não exibe mais data estimada com selo de certeza. O Worker
v4.9.183 (CAL-003) aplica overrides de KV no `op=calendario`. Mas as
datas no KV ainda não foram corrigidas — a contenção de dado (escrever
Bradesco 05/08 e Vale 30/07 no KV) depende de F0 e Gate C, não executada.

**Correção pendente**: Escrever overrides no KV com as datas oficiais.
As fontes já estão colhidas e registradas (relatório 03, seção 3).

**Guarda**: CAL-001 + CAL-004 implementados garantem que estimativa sem
fonte aparece como ESTIMADO e staleness é monitorada.

---

### CAL-001: Data estimada vira AGENDADO com selo de certeza

**Severidade**: P1 (contido em v201.93)
**Certeza**: COMPROVADO
**Família**: CAL

**Evidência**: `app/index.html:4869` — o colapso "não divulgado → AGENDADO"
tratava `status: "estimado"` como AGENDADO. `agendaBuildPersistir`
(`api/v4.9.182.js:10989-11001`) descarta `status`/`nota` ao montar a
agenda, herdando estimativa como fato.

**Status**: Contido em v201.93 (frontend) e v4.9.183 (Worker). Mas as
outras 18 estimativas 2T26 continuam sem verificação contra RI.

---

### CAL-003: op=calendario ignorava overrides de KV

**Severidade**: P2 (corrigido em v4.9.183)
**Certeza**: COMPROVADO
**Família**: CAL

**Status**: Corrigido. v4.9.183 aplica `calendario:overrides:v1` em
`op=state` e `op=calendario`.

---

### CAL-004: Calendário congelado em 2026-05-09, 20/103 emissores, fontes secundárias

**Severidade**: P2
**Certeza**: COMPROVADO
**Família**: CAL

**Evidência**: `CALENDARIO_RESULTADOS_V1.ultima_atualizacao: "2026-05-09"`
(80 dias atrás em 28/07). Cobertura 20/103. Fontes: InfoMoney, MoneyTimes
(secundárias). Apenas 1 de 40 registros usa fonte primária (RI da Gerdau,
1T26).

**Correção proposta**: Rotina de atualização com hierarquia de fontes
(RI > CVM/B3 > secundárias). Staleness visível em canal monitorado.

---

### CAL-005 (novo): Dois terços dos CNPJs mapeados com match=forte apontam para subsidiária errada

**Severidade**: P1
**Certeza**: COMPROVADO
**Família**: CAL (ou DATA — fronteira difusa, classificado CAL por afetar
diretamente o calendário e a reconciliação CVM)

**Evidência** (nota Obsidian 60, 2026-07-16):
- **Light**: mapeada para Light Energia S.A. (CNPJ 01.917.818/0001-36,
  subsidiária de geração). A holding em recuperação judicial é Light S.A.
  (CNPJ 03.378.521/0001-75). Altman Z''-EM = 4.71 (zona saudável) para
  uma empresa em RJ desde 2024. Falso negativo estrutural.
- **Raízen**: mapeada para Raízen Energia S.A. (CNPJ 08.070.508/0001-78,
  55 docs CVM). A holding que protocolou o plano de RE é Raízen S.A.
  (CNPJ 33.453.598/0001-23, 159 docs CVM). Os 6 Fatos Relevantes do
  plano vêm pelo CNPJ que o Radar não mapeia.
- **GPA, Dasa, Taesa, Rede D'Or**: sem CNPJ mapeado (entre os 22 de
  `cnpj_emissores.review.json`). GPA é CRÍTICO recorrente e tem piso 55
  no `_RJ_FLOOR`, mas a reconciliação CVM não o alcança.

**Causa raiz**: Match por nome de emissor é frágil. O campo `match=forte`
é falso positivo — a heurística parece boa mas erra nos casos de maior
risco (empresas com múltiplas entidades CVM, holdings com subsidiárias
operacionais).

**Correção proposta**: Revisar os 22 CNPJs de `cnpj_emissores.review.json`
contra o cadastro CVM, priorizando os 4 sem CNPJ e os 2 com match errado.
Incluir `match=forte` apenas quando confirmado por `Nome_Companhia` exato
no cadastro CVM.

**Guarda**: Script `reconciliar_ipe_cvm.ps1` deve emitir warning quando o
CNPJ do emissor não casa com nenhum documento no IPE do trimestre (hoje
ele já detecta ausência, mas não diagnostica causa).

---

## 5. CI FAIL-OPEN (família CI)

### CI-001: scan-emergencia.yml sai com exit 0 quando health retorna ok:false

**Severidade**: P1
**Certeza**: COMPROVADO
**Família**: CI

**Evidência**: `.github/workflows/scan-emergencia.yml:81-86`:
```bash
if echo "$HC" | jq -e '.ok == false' >/dev/null 2>&1; then
    echo "::warning::admin_health_check retornou ok:false..."
    echo "prosseguir=false" >> "$GITHUB_OUTPUT"
    exit 0  # <-- DEVERIA SER exit 1
fi
```

Este foi o mecanismo que deixou o alarme mudo entre 24 e 27 de julho.
O ADMIN_EMAIL estava ausente, o health retornava ok:false, e o scan de
emergência — que é o paraquedas quando o feed desktop congela — respondia
com warning e saída limpa.

**Status**: Corrigido no branch codex/system-finalization-v4.9.183.

**Correção proposta**: Merge do codex. A linha foi alterada para `exit 1`.

**Guarda**: CI-003 (automatizar/verificar secrets do GitHub) impede que
o problema primário (secret faltando) aconteça sem alerta.

---

### CI-002: scan-emergencia.yml e frescor-check.yml saem com exit 0 quando ADMIN_PASSWORD ausente

**Severidade**: P2
**Certeza**: COMPROVADO
**Família**: CI

**Evidência**:
- `scan-emergencia.yml:53-58`: `exit 0` quando `ADMIN_PASSWORD` ausente
- `frescor-check.yml:39-43`: `exit 0` quando secret ausente
- `daily-status-email.yml:69-71`: `exit 0` quando `ADMIN_PASSWORD` ausente
- Todos documentam "Saindo limpo (sem falha)" como decisão de design

**Decisão de política pendente**: Run agendada sem secret deve falhar
(notificar operador) ou abrir issue automática? A prática atual de
"avisar no log e sair limpo" é falha silenciosa para todos os efeitos
práticos: ninguém lê log de workflow que passou verde.

**Correção proposta**: `exit 1` ou `gh issue create` quando secrets
obrigatórios faltam em run agendada. Workflow dispatch manual pode
continuar aceitando input.

---

### CI-003: frescor-check.yml CORRETO no tratamento de ok:false

**Verificado**: Diferente do scan-emergencia, o frescor-check.yml:88-92
emite `::error::` e `exit 1` quando health retorna ok:false. Este
comportamento é o correto e deve ser o padrão para todos os workflows.

---

## 6. ROTINAS AGENDADAS (família OPS)

### OPS-ROT-001: Três Scheduled Tasks recriadas com histórico zerado

**Severidade**: P2
**Certeza**: COMPROVADO
**Família**: OPS

**Evidência** (nota 03 - Estado Atual, 27/07 13h30):
- VIXRadar-Coleta-Volatilidade: recriada, LastRunTime 1999, 0x41303
- VIXRadar-Export-Historico: recriada, LastRunTime 1999, 0x41303
- VIXRadar-Reconciliacao-CVM: recriada, LastRunTime 1999, 0x41303

0x41303 = SCHED_S_TASK_HAS_NOT_RUN. Recriar task zera o histórico do
Scheduler. Os logs em `logs/routines/` mostram execuções reais até 23/07
(Coleta), 22/07 (Export) e 21/07 (Reconciliacao), mas o Scheduler não
sabe disso.

**Risco**: Baixo. As rotinas têm logs independentes. Mas o monitor-tasks.ps1
lê `LastTaskResult` do Scheduler, e para estas três tasks o dado é "nunca
rodou", o que pode gerar falso alerta ou ausência de alerta.

**Correção proposta**: Aguardar primeira execução real pós-recriação e
validar exit 0. Confirmar que monitor-tasks.ps1 interpreta 0x41303
corretamente (já trata como benigno).

---

### OPS-ROT-002: monitor-tasks.ps1 NÃO inventa causa de falha

**Verificado**: Ao contrário da premissa da auditoria, `monitor-tasks.ps1`
categoriza falhas por código de erro numérico do Windows Task Scheduler
(0x80070002 = arquivo não encontrado, 0x1 = erro genérico, 0x7 = contagem
de erros encontrados). As heurísticas são documentadas e específicas.
A premissa "inventa causa a partir do nome da task" é FALSA.

---

## 7. HIGIENE DE BRANCHES (família OPS)

### OPS-BRANCH-001: Sete branches codex, com uma duplicata confirmada

**Severidade**: P3
**Certeza**: COMPROVADO
**Família**: OPS

**Evidência**:
- `codex/verificacao-agenda-pos-cal-002` e `codex/cal002-agenda-verificacao`
  têm diff IDÊNTICO (3 arquivos, 31 inserções, 123 deleções)
- `codex/system-finalization-2026-07-28`: 0 commits ahead de main (vazio)
- `codex/preservar-v4.9.183-producao`: 1 commit (preservação do artefato)
- `codex/system-finalization-v4.9.183`: 1 commit (correções estruturais,
  PR #18, 23 arquivos)
- `codex/selective-git-gate`: 1 commit (skill nova)
- `codex/cal002-pages-v20193`: 1 commit (fix frontend CAL-002)

**Proposta de consolidação** (sem force-push):
1. Merge `codex/system-finalization-v4.9.183` → main (PR #18, já aberta)
2. Merge `codex/cal002-pages-v20193` → main (fix frontend)
3. Merge `codex/selective-git-gate` → main (skill nova)
4. Deletar `codex/system-finalization-2026-07-28` (vazio)
5. Deletar `codex/verificacao-agenda-pos-cal-002` (duplicata, substituído
   por `codex/cal002-agenda-verificacao`)
6. Manter `codex/preservar-v4.9.183-producao` como registro histórico até
   o merge para main estar completo
7. `codex/cal002-agenda-verificacao`: absorvido pelo system-finalization
   (contém o mesmo diff do item 5)

---

## 8. VERDADE DA UI (família DATA)

### DATA-UI-001: ALERTA e ATENÇÃO colapsados como RELEVANTE no renderEventoCard

**Severidade**: P1
**Certeza**: COMPROVADO
**Família**: DATA

**Evidência**: `app/index.html:~3706` (função renderEventoCard):
```js
const n = "CRITICO" === e.classificacao,
      s = "ECO" === e.classificacao,
      i = n ? "crit" : s ? "eco" : "rel",
      r = n ? "CRÍTICO" : s ? "ECO" : "RELEVANTE"
```
Ternário trata 3 valores. ALERTA e ATENÇÃO caem no else e viram "RELEVANTE"
com badge laranja, indistinguíveis de RELEVANTE verdadeiro.

---

### DATA-UI-002: _v201SevCfg mapeia ALERTA para cor e label de ECO

**Severidade**: P1
**Certeza**: COMPROVADO
**Família**: DATA

**Evidência**: `app/index.html:4195-4199`:
```js
function _v201SevCfg(s) {
  if (s === "CRITICO")   return { cor: "#DC2626", label: "CRITICO",   aria: "Critico" };
  if (s === "RELEVANTE") return { cor: "#EA580C", label: "RELEVANTE", aria: "Relevante" };
  if (s === "ATENCAO")   return { cor: "#CA8A04", label: "ATENCAO",   aria: "Atencao" };
  return { cor: "#6B7280", label: "ECO", aria: "Eco" };  // ALERTA cai aqui
}
```
`_v201Sev("ALERTA")` retorna "ALERTA" (correto), mas `_v201SevCfg("ALERTA")`
retorna cinza de ECO. No feed v201, evento ALERTA tem borda cinza e
aria-label "Evento Eco de ...".

---

### DATA-UI-003: Toggle "ocultar research" não funciona nos cards v201

**Severidade**: P2
**Certeza**: COMPROVADO
**Família**: DATA

**Evidência**: `app/index.html:3177`:
```css
body.vix-hide-research .ev-card[data-tipo-dado="research"] { display: none !important; }
```
Cards v201 usam classe `.v201-card`, não `.ev-card`. O seletor CSS não
os alcança. O toggle no localStorage (`vix_hide_research`) esconde cards
do sistema antigo mas ignora o feed mais recente.

---

### DATA-UI-004: cardEvento (PDF) colapsa ECO/ALERTA/ATENÇÃO como RELEVANTE

**Severidade**: P2
**Certeza**: COMPROVADO
**Família**: DATA

**Evidência**: `app/index.html:6401-6404` — ternário único:
CRITICO ou "qualquer outra coisa vira RELEVANTE". Relatórios exportados
inflam severidade de eventos não-CRÍTICO.

---

## 9. ACHADOS ADICIONAIS DAS NOTAS OBSIDIAN

### DATA-RJ-001: _RJ_FLOOR é tabela manual sem as_of e já estava stale em 16/07

**Severidade**: P2
**Certeza**: COMPROVADO (já corrigido em v4.9.160 com campos as_of/fonte_url,
mas os 21 emissores continuam com valores null)

**Fonte**: Nota 60, seção 3. Kora Saúde descrita como "Avaliando recuperação
extrajudicial" quando CVM já registrava deferimento desde 2026-05-04.

---

### DATA-CNPJ-001: 4 de 21 emissores do _RJ_FLOOR sem CNPJ mapeado

**Severidade**: P2
**Certeza**: COMPROVADO
**Família**: DATA

**Fonte**: Nota 60, seção 5. GPA, Dasa, Taesa e Rede D'Or bloqueados do
pipeline preditivo e da reconciliação CVM por falta de CNPJ.

---

### VOL-003: SELIC hardcoded 13,75% sem as_of (corrigido em v4.9.183)

**Severidade**: P2 (corrigido)
**Certeza**: COMPROVADO
**Família**: VOL

**Fonte**: Relatório 03, Nota 72. v4.9.183 passou a ler SGS 1178 do BCB
com validação de faixa e staleness.

---

## 10. MATRIZ DE FONTES CONSOLIDADA

| Frente | Fontes |
|---|---|
| Deploy/Drift | wrangler.toml (main), PROVENIENCIA-v4.9.183.md, health público, git log |
| Segurança | .gitignore, git ls-files, git log --all, .vercelignore |
| Vercel | git log --grep=vercel, commits 93eaaa7/709409e/4211bbc, .vercelignore |
| Calendário | RI Bradesco, RI Vale, CALENDARIO_RESULTADOS_V1, relatório 03 |
| CI | scan-emergencia.yml, frescor-check.yml, daily-status-email.yml, canonical-test.yml |
| Rotinas | Get-ScheduledTask (27/07 13h30), logs/routines/, monitor-tasks.ps1 |
| Branches | git branch -a, git diff main..<branch> --stat |
| UI | app/index.html (leitura direta), 8 divergências documentadas |
| Dados | Nota Obsidian 60 (CNPJ, _RJ_FLOOR, CVM IPE), nota 72 (v4.9.183) |

---

## 11. FILA DE CORREÇÃO PRIORIZADA

Pré-requisitos F0 (qualquer mutação de KV/calendário):
1. Snapshot das chaves KV afetadas
2. Lista exata das mutações
3. Rollback testável
4. Fontes oficiais anexadas (URL, data-hora, timezone America/Sao_Paulo)
5. Comparação antes/depois dos endpoints
6. Verificação nas três superfícies (UI, endpoint, email)

| # | ID | Sev | Ação | Dependência |
|---|---|---|---|---|
| 1 | OPS-DRIFT-001 | P0 | Merge codex/system-finalization-v4.9.183 → main, atualizar wrangler.toml | PR #18 review |
| 2 | CAL-002 | P0 | Corrigir datas Bradesco/Vale no KV, validar 18 restantes | F0 |
| 3 | DATA-UI-001 | P1 | Adicionar ALERTA/ATENÇÃO ao renderEventoCard e _v201SevCfg | — |
| 4 | DATA-UI-002 | P1 | Adicionar case "ALERTA" em _v201SevCfg | — |
| 5 | CI-001 | P1 | scan-emergencia: ok:false → exit 1 | Já no codex |
| 6 | CI-002 | P2 | Definir política de secret ausente (exit 1 ou issue) | Decisão |
| 7 | CAL-005 | P1 | Corrigir CNPJ Light (holding) e Raízen (holding) | F0 |
| 8 | DATA-UI-003 | P2 | Estender seletor "ocultar research" para .v201-card | — |
| 9 | OPS-DRIFT-002 | P2 | Validação de hash pré-deploy no deploy-worker.ps1 | Merge do codex |
| 10 | SEC-FILE-001 | P2 | Adicionar recovery-codes.txt ao .gitignore | — |
| 11 | SEC-FILE-003 | P2 | Revisar setup-deploy-credential.ps1, remover credencial se houver | — |
| 12 | SEC-FILE-002 | P2 | Remover/arquivar .codex/system-final-stage/ (38 arquivos, 12,7 MB) | — |
| 13 | OPS-VERCEL-001 | P2 | Remover integração Vercel do repo GitHub | Decisão |
| 14 | CAL-004 | P2 | Rotina de atualização do calendário com hierarquia de fontes | CAL-003 |
| 15 | DATA-RJ-001 | P2 | Preencher as_of + fonte_url dos 21 emissores do _RJ_FLOOR | F0 |
| 16 | SEC-FILE-004 | P3 | Ampliar regra logs/routines/ para logs/ no .gitignore | — |
| 17 | OPS-BRANCH-001 | P3 | Consolidar 7 branches codex em main + deletar duplicatas/vazios | — |
| 18 | SEC-FILE-005 | P3 | Reverter package.json/package-lock.json se desnecessários | — |
