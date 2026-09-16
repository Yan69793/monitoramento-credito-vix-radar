# 2026-09-15 — Hermes Kanban: lane de review e auto-revisão

Status: **canonico (readonly append)**. Neste arquivo, nada foi modificado por outra ferramenta.
Escopo: apenas o comportamento da lane de review do Hermes. CVMSTITCH1, rotinas e deploy nao tocados.

## Conclusao em uma linha

A lane de review funciona, mas `review_dispatch=true` **nao impede auto-revisao**.
O unico mecanismo que garante revisor independente e `--reviewer` explicito em
`request-review`. Hoje a lane esta desligada (`false`) por decisao do operador.

## O que foi medido (nao deduzido)

- `hermes config get kanban review_dispatch` -> `false` (valor atual, perfil `default`).
- Valor padrao do proprio Hermes e `true`: `hermes_cli/config_defaults.py:1737`.
- Gateway lera a lane em `kanban_db_dispatch.py:1784` — `review_rows` so e enumerado quando
  `review_dispatch_enabled()` retorna `true`. Com `false`, a lane fica parada.
- `kanban_db_dispatch.py:1844`: o dispatcher inicia `row["assignee"]`. **Nao escolhe revisor.**
- `kanban_db.py:3084-3092`: quando `reviewer=None`, cai em `_prior_reviewer`, que em primeira
  revisao retorna `None` — e o assignee permanece o implementador.

## Prova de duas pontas (smoke test, descartado)

Cartoes criados e arquivados: `t_2930acf5`, `t_4fc78164`, `t_5c6791c7`, `t_f0fe5358`.

Ponta ruim — `request-review` sem `--reviewer`:
```
hermes kanban request-review t_4fc78164 --force
-> status: review | assignee: code      <- implementador e o revisor
```

Ponta boa — `request-review` com `--reviewer verificador`:
```
hermes kanban request-review t_5c6791c7 --reviewer verificador --force
-> status: review | assignee: verificador
```

O `--reviewer` reescreve o assignee no proprio `request_review` (antes do dispatch),
entao nao depende de `review_dispatch` ligado. A transicao `running->review` e nativa do kernel.

## Correcao estrutural recomendada (nao aplicada)

`request-review` **sempre** com `--reviewer verificador` para cartoes cujo assignee seja
`code`/`cto`. Mantenha `review_dispatch=false` como guarda — e o estado seguro.
A lane automatica em `true` so e segura se houver uma regra que proiba o implementador
de ser revisor, e essa regra nao existe no codigo.

## O que NAO foi alterado

- `config.yaml` byte a byte igual ao backup `config.yaml.backup-pre-smoketest-20260915-045350`
  exceto `model.default` (`deepseek-v4-pro` -> `muse-spark-1.3-contributor-free`), que e
  escolha do gateway, não deste trabalho. `review_dispatch` continua `false`.
- Nenhum arquivo do repositorio modificado. `git status --porcelain` mostra os mesmos
  arquivos pre-existentes da frente MVA e do PR #26.
- Nenhum cartao real criado ou alterado. Os quatro de smoke test foram `complete` + `archive`.
- `t_c7cf798e` permanece `scheduled`, agendado para `2026-09-15T09:40:00-03:00`.
- `t_2ca0d7d3` permanece `done` (verificador, run 18).

## Proximo passo

Quando `t_2ca0d7d3` fechar com veredito, aplicar a correcao estrutural acima como
decisao do operador — nao automaticamente. A lane de review e a unica parte da
arquitetura que ainda e semi-automatica.
