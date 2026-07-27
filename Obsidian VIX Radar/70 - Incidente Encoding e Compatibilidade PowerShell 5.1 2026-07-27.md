---
data: 2026-07-27
tipo: incidente
tags: [vix-radar, incidente, powershell, encoding, deploy, guarda, causa-raiz]
status: ativo
---

# Incidente Encoding e Compatibilidade PowerShell 5.1, 2026-07-27

## Resumo

O deploy quebrou com erro de parse porque `scripts/deploy-pages.ps1` estava em UTF-8
sem BOM contendo travessoes. Ao investigar, o encoding se revelou metade do problema:
a outra metade e sintaxe exclusiva de PowerShell 7 em scripts executados pelo 5.1, que
estava a poucas horas de derrubar a rotina de volatilidade em producao.

## Causa raiz

Os scripts sao escritos assumindo `pwsh` 7, mas quem os executa (Task Scheduler,
deploys, hooks) e o `powershell.exe` 5.1. Nada verificava essa premissa, entao a
divergencia so aparecia como falha em producao. Duas classes de quebra saem do mesmo
buraco, e a segunda engana:

**1. Encoding.** Arquivo sem BOM e lido pelo 5.1 como ANSI/CP1252. O byte `0x94` do
travessao (U+2014) vira aspa curva U+201D, que o parser do PowerShell aceita como
delimitador de string. Por isso o travessao so quebra quando cai **dentro de string**;
em comentario e inofensivo. Foi o que derrubou o deploy.

**2. Sintaxe PS 6/7.** Ternario, `??`, `?.`, `-MaximumRetryCount`, `-RetryIntervalSec`,
`ConvertFrom-Json -AsHashtable`. Nao tem relacao com BOM e passa batido por qualquer
checagem de encoding.

**Causa raiz mais funda:** o `lint-encoding.ps1` existia desde 16/07 e teria pego o
caso do deploy, mas nunca rodou. Nao estava em hook, nem em CI, nem no Scheduler, nem
nos scripts de deploy: nasceu orfao no proprio commit que o criou. Tinha ainda dois
defeitos que o tornavam inutilizavel: caminhos absolutos fixos, que deixavam `api/tools/`
e `.claude/skills/` fora da varredura, e um cabecalho que se documentava com
`pwsh lint-encoding.ps1`, interpretador que ate hoje nao existia nesta maquina.

## A quase-falha das 17h00

Sequencia que quase derrubou a coleta de volatilidade sem ninguem ver:

| Quando | O que |
|---|---|
| ate 27/07 12h36 | `run_coleta_volatilidade.ps1` chamava o coletor via `pwsh` 7, onde o ternario da linha 164 e valido. Logs de 21 a 23/07 mostram `sucesso=73`, tudo normal |
| 27/07 12h36 | commit `37f0b62` troca `pwsh` por `powershell.exe`, correto quanto ao PATH do Scheduler, mas o script continuou escrito em PS7 |
| 27/07 17h00 | disparo previsto. `collect_cotacoes.ps1` **e** `upload_volatilidade_kv.ps1` falhariam no parse |
| 27/07 ~13h20 | corrigido antes do disparo |

O agravante e que a falha seria **silenciosa**. O `try/catch` de
`run_coleta_volatilidade.ps1` (linhas 28 a 34) nao captura falha de processo filho: o
coletor morre no parse, nao produz saida, o `Select-String "Sucesso: (\d+)"` nao casa,
e a rotina loga e segue para a etapa 2 como se nada tivesse acontecido.

## Corrigido

- `collect_cotacoes.ps1`: ternario da linha 164 virou `if/else`; `-MaximumRetryCount`
  e `-RetryIntervalSec` (PS 6.1+) substituidos por laco de retry equivalente, para nao
  perder a resiliencia contra rate limit do Yahoo em 103 tickers.
- `register-vixradar-tasks.ps1`: `?.` trocado por teste explicito.
- BOM UTF-8 e remocao de travessao e box-drawing nos demais.
- `sync-version-docs.ps1` recebeu **apenas BOM**. Suas setas e acentos estao dentro de
  regex que casa o conteudo real de `README.md:24` (`← bundle Worker em produção`).
  Remover os nao-ASCII ali quebraria a sincronizacao de versao em silencio. Este e o
  contraexemplo que prova que "so tirar os nao-ASCII" nao e politica universal.
- `apply-security-rotation.ps1`: senha antiga em texto puro removida do fonte.
- Repo `Site`: BOM nos 5 scripts, mais dois defeitos que o encoding escondia, ver abaixo.

Fora do inventario original, encontrados porque a varredura passou a cobrir a raiz do
repo: 3 arquivos em `api/tools/`, 1 em `.claude/skills/`, e `register-vixradar-tasks.ps1`.

Dois defeitos no repo `Site` que nenhuma checagem de encoding acharia, so o parser:
`deploy-all.ps1:11` tinha `&amp;` (entidade HTML) no lugar do operador de chamada `&`,
ou seja, o deploy do szuchmacher.com.br nao rodava, e o arquivo e **ASCII puro**;
`reenviar-emails-stripe.ps1:66` usava `??`.

## A guarda

`scripts/lint-encoding.ps1` deixou de checar BOM e passou a **reprovar pelo parser do
5.1**, unico criterio que cobre as duas classes. Tres correcoes de projeto:

1. Varre `git ls-files '*.ps1'` em vez de diretorio. A primeira versao acusou 23
   arquivos, dos quais 21 eram do outro worktree e de pastas de historico. Detector
   ruidoso e detector ignorado, que foi como a versao anterior morreu.
2. Resolve a raiz via git, entao funciona em worktree, clone novo e CI.
3. **Delega a checagem ao `powershell.exe` quando invocado pelo `pwsh`.** Sem isso o
   ternario parseia sem erro e o detector daria verde no exato bug que o motivou.

Ligado ao `pre-commit` (`scripts/hooks/` mais `scripts/install-hooks.ps1`, que instala
em `.git/hooks`, compartilhado com os worktrees). Gate dentro do deploy nao serviria:
`deploy-pages.ps1` quebrou no parse, antes de executar qualquer linha propria.

**Validado contra o caso que o motivou**, criterio de [[13 - Metodo de Vistoria Operacional]]:
reprova as 4 versoes pre-correcao recuperadas do git; com **apenas BOM** aplicado, que
era tudo que o linter antigo fazia, ainda reprova `collect_cotacoes.ps1` pelo ternario;
reprova igual quando rodado sob `pwsh` 7; bloqueia e libera um commit de teste real.

## Lacunas conhecidas

- O repo `Site` ficou **sem** a guarda, porque o linter mora no repo do VIX Radar.
- A senha antiga saiu do fonte mas **continua no historico do git**.
- `scripts/_archive/` (10 arquivos) fica fora da varredura por desenho.
- A edicao de `run_vixradar_verificacao_async.ps1` durante o dia **removeu o BOM** do
  arquivo, que o tinha no commit `ccd61c3`. Algum editor em uso salva sem BOM, e essa
  e a fonte contínua desta classe de bug. Vale identificar qual.

## Validacao

`powershell.exe -NoProfile -File scripts/lint-encoding.ps1` retorna `RISCO : 0` sobre
50 rastreados, e 51 incluindo nao-rastreados de `api/` e `scripts/`. Repo `Site`: 36 de
36. Cadeia da rotina das 17h00 (`run_coleta_volatilidade`, `collect_cotacoes`,
`upload_volatilidade_kv`) com `parse_erros=0`. Health em producao HTTP 200,
`ok:true`, `kv:true`, `telemetria:true`, v4.9.181.

Commits: `642e599`, merge `184f53a`, `cc2a589` (VIX Radar, em `origin/main`);
`26376c7` (Site, em `origin/master`).

Ver [[03b - Infraestrutura]], [[PENDENCIAS]] e memoria `project_powershell_5_1_e_pwsh7`.
Relacionado: [[69 - Auditoria Geral 2026-07-27]], cujo achado P3 sobre `exit` em vez de
`return` e da mesma familia (script de rotina que so funciona pelo contexto em que roda).
