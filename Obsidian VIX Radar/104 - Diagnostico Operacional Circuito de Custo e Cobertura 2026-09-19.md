# 104 - Diagnóstico Operacional — Circuito de Custo e Cobertura de Análise

**Data:** 2026-09-19 (madrugada)
**Origem:** verificação do estado operacional após o relatório `103`. O relatório 103 concluiu, a partir do health, que "o sistema não está quebrado". **Essa conclusão estava errada** e este documento a corrige.
**Status:** diagnóstico fechado. Nenhuma correção aplicada.
**Relação com o 102:** confirma e detalha o **P0 já registrado** em `102 - Auditoria Operacional 2026-09-18.md` ("Fechar o buraco de cobertura"), com o mecanismo e os números de 18/09.

---

## Veredito

**O produto não está analisando os emissores.**

| Rotina de 18/09 | Analisados | Deferidos | Cap efetivo |
|---|---:|---:|---:|
| Matinal, 1ª execução (01:40) | **4 de 23** | 19 | 225.907 |
| Matinal, 2ª execução (10:06) | **0** | 0 | **0** |
| Noturna (18:05) | **0 de 104** | 78 (+26 skip) | **0** |

A noturna — a rotina principal, que cobre a carteira inteira — **executou 0 análises em 197 segundos**, gastou 0 tokens, fez 0 buscas, e **fechou o log com "OK"**.

O health público reportou `ok:true`, `painel_fresco:true` e `feed_fresco:true` durante todo o período. **Ele não estava mentindo sobre o que mede — estava medindo a coisa errada.** `painel_fresco` mede se o painel foi *escrito*; não mede se alguma análise *aconteceu*. Uma execução que defere 100% do plano e escreve o painel satisfaz o health perfeitamente.

---

## 1. Evidência — os números exatos

### 1.1 Noturna de 18/09 (`logs/routines/vixradar-noturno_20260918.log`)

```
2026-09-18 18:05:07  CAP_EFETIVO=0
   (cap_proprio=700000  gasto_dia=1445668  teto=1300000  reserva_outras=150000)

2026-09-18 18:05:07  CUSTO_DIA 20260918:
   matinal=685032  noturno=572973  verificacao=18405  sentinela=169258  agenda=0
   TOTAL_DIA=1445668   TETO=1300000   MARGEM=-145668   CIRCUITO_ABERTO

2026-09-18 18:05:07  CIRCUITO_ABERTO: margem do dia -145668 abaixo de 100000.
   Nenhum lote sera disparado; tudo que nao for SKIP sai como DEFERIDO.

2026-09-18 18:08:24  DEFERIDOS: ok=78 falha=0 total=78 motivo=cap_efetivo (0/0 realizados)
2026-09-18 18:08:24  FIM: noturno concluido. Total do dia 104/104
   (ledger analisados=0 skip=26 deferidos=78).
   analisados_execucao=0 skip_execucao=26 deferidos_execucao=78
   submits_aceitos=104 submit_ok=0 submit_fail=0
   tokens=0 cache_read=0 cap_efetivo=0 lotes=0 lotes_com_trabalho=0 buscas=0
   deferidos_cap=78 deferidos_auth=0 motivo_deferimento=cap_efetivo
   duracao_sec=197.4
```

Note a linha `(0/0 realizados)`: é uma razão sem significado, impressa porque o cap era zero.

### 1.2 Matinal de 18/09 (`logs/routines/vixradar-matinal_20260918.log`)

**Primeira execução, 01:40** — fez algum trabalho e saturou o próprio cap:

```
DEFERIDOS: ok=19 falha=0 total=19 motivo=cap_efetivo (194127/225907 realizados)
FIM: matinal concluido. Total do dia 23/23 (ledger analisados=4 skip=0 deferidos=19).
   analisados_execucao=4 deferidos_execucao=19 tokens=194127 cap_efetivo=225907
   buscas=12 lotes=1 duracao_sec=617.5
```

**Segunda execução, 10:06** — não fez nada, em 6,8 segundos:

```
FIM: matinal concluido. Total do dia 23/23 (ledger analisados=4 skip=0 deferidos=19).
   analisados_execucao=0 deferidos_execucao=0 tokens=0 cache_read=0 cap_efetivo=0
   lotes=0 buscas=0 duracao_sec=6.8
```

> Observação: o `ledger analisados=4 ... deferidos=19` da segunda execução é o **resíduo da primeira** — os contadores `_execucao` mostram a verdade daquela execução (`0/0`). O ledger não foi reprocessado porque o cap era zero.

---

## 2. Cadeia causal

### 2.1 O cálculo

`scripts/run_vixradar_varredura.ps1:1197-1211`:

```powershell
$custoCfg = Get-VixCustoConfig $LogDir
$custoDia = Get-VixCustoDia $LogDir $DateTag $custoCfg
$reservaOutras = [int64]$custoCfg.RESERVA_VERIFICACAO
if ($Perfil.reservaOutrasKey -eq 'RESERVA_NOTURNO') { $reservaOutras += [int64]$custoCfg.RESERVA_NOTURNO }
$TokenHardCap = [int64](Get-VixCapEfetivo ([int64]$Perfil.capProprio) $custoDia $custoCfg $reservaOutras)
...
if ($custoDia.circuito_aberto) {
    Write-Log ('CIRCUITO_ABERTO: ... Nenhum lote sera disparado; tudo que nao for SKIP sai como DEFERIDO.')
    $TokenHardCap = 0
}
```

`scripts/lib/vixradar-custo.ps1:131-139`:

```powershell
$disp = [int64]$Config.TETO_DIA - $gasto - $ReservaOutras
if ($disp -lt 0) { $disp = [int64]0 }
```

`scripts/lib/vixradar-custo.ps1:114-115`:

```powershell
$margem = [int64]$Config.TETO_DIA - $total
$aberto = ($margem -lt [int64]$Config.MARGEM_MINIMA)
```

**Há dois caminhos independentes para o cap virar zero:** a aritmética (`$disp` satura em 0) e o disjuntor explícito (`circuito_aberto` → `$TokenHardCap = 0`). Em 18/09 os dois coincidiram.

### 2.2 O que aconteceu em 18/09

1. O **matinal gastou 685.032** tokens — quase **2x a folga que o projeto lhe reserva** (ver 2.3).
2. Somado a `noturno=572973 + verificacao=18405 + sentinela=169258`, o dia fechou em **1.445.668** contra um teto de **1.300.000**.
3. `margem = -145.668`, abaixo de `MARGEM_MINIMA = 100.000` → **`CIRCUITO_ABERTO`**.
4. O cap da noturna foi forçado a **0**.
5. Noturna: 78 deferidos, 0 analisados, log "OK".

### 2.3 A aritmética estrutural

`logs/routines/custo-config.json` (real, não os defaults):

```json
{ "TETO_DIA": 1300000, "RESERVA_VERIFICACAO": 150000,
  "RESERVA_NOTURNO": 700000, "MARGEM_MINIMA": 100000 }
```

Com essas reservas, a folga **projetada** de cada rotina é:

| Rotina | Folga por projeto | Consumido em 18/09 |
|---|---:|---:|
| Matinal | `1.300.000 − 700.000 − 150.000 − 100.000` = **350.000** | **685.032** (196%) |
| Noturna | `1.300.000 − gastoDia − 850.000` = **≤ 450.000** | 0 (starved) |

O `RESERVA_NOTURNO = 700.000` consome 54% do teto diário. E a reserva é subtraída **duas vezes** no caso da noturna: ela reserva para si mesma (`$reservaOutras += RESERVA_NOTURNO`) e depois ainda é limitada pelo próprio `capProprio = 700.000`. O efeito prático é que a noturna só roda com o que sobra — e quando o dia estoura, sobra zero.

### 2.4 Histórico — não é um dia isolado

`TOTAL_DIA` por dia, lido dos logs:

| Data | TOTAL_DIA | Circuito |
|---|---:|---|
| 2026-09-16 | 516.134 | fechado |
| 2026-09-17 | 350.231 | fechado |
| **2026-09-18** | **1.445.668** | **ABERTO** (e mais 3 leituras acima do teto no mesmo dia: 1.276.410, 1.100.136, 1.100.136) |

O 102 já registrava a mesma falha em 16/09 (`vixradar-matinal_20260916.log` com `analisados=0 deferidos=23 deferidos_cap=23`) e o deferimento por `limite_sessao_assinatura` em 16/09. **18/09 é a repetição mais grave, não a primeira ocorrência.**

---

## 3. Por que nada alertou

**Esta é a parte mais importante do diagnóstico.**

| Sinal | O que mede | Estado em 18/09 |
|---|---|---|
| `ok` do health | plataforma de pé, bindings, providers | `true` |
| `painel_fresco` | o painel foi **escrito** nas últimas X horas | `true` |
| `feed_fresco` | chegou evento novo na fonte | `true` |
| `CIRCUITO_ABERTO` no log | orçamento estourado | **presente, e ninguém lê** |
| `analisados_execucao` | **quantas análises foram feitas** | **0 — não exposto em lugar nenhum** |

O health não tem nenhum campo que responda *"quantas análises foram feitas hoje?"*. Enquanto a rotina escrever o painel, `painel_fresco` fica verde mesmo com 0 análises.

O gate que vigia exatamente isso — **`EMISSORSTALE1`** em `.github/workflows/frescor-check.yml` — **está dormente**. Palavras do próprio 102:

> "**Só entra em vigor quando chegar em `main`, porque o agendado roda lá.**"

`origin/main` está **5 commits atrás** da produção. O gate que alertaria "75 de 104 emissores sem análise há mais de 24h" existe no repositório, foi testado contra produção real, e **não roda** — porque o agendado lê `main`.

É a mesma classe que o fechamento de 18/09 nomeou: *"guarda que ficou cega"*.

---

## 4. O que já estava registrado (e continua aberto)

Do `102 - Auditoria Operacional 2026-09-18.md`:

> "**75 de 104 emissores sem análise há mais de 24h**, o mais antigo em 2026-09-16 21:10. [...] Classificação geral: **degradado**, sem P0 de superfície."

> "**P0** Fechar o buraco de cobertura. O plano de 104 não fecha com o orçamento atual e a maior parte é deferida por cap ou por limite de sessão. Enquanto isso, o SLA de 24h por emissor não é atingível."

> "A rotina roda, a maior parte do plano é deferida, e **o plano de 104 não fecha em um dia com o orçamento atual**."

Gate `audit-routine-staleness.ps1`: `total=104`, `stale_24h_real=75`, `max_stale_hours=43.3`, mais antigo `2026-09-16T21:10`. Tiers: SKIP 4, LIGHT 40, FULL 60.

**Este documento não descobre o problema. Ele mede o mecanismo e confirma que o P0 segue aberto e piorando.**

---

## 5. Achado secundário — CI vermelho por higiene

O gate `scripts-tests` está **vermelho** em `main` e em `mva-provider-agnostic`:

```
REGRESSAO NOVA (nao esta no baseline):
  - test-m3-openrouter-search.ps1    (exit=2, 0.5s)
  - test-m3-reconciliacao.ps1        (exit=10, 0.6s)
```

**Não é regressão de código.** Rodei as duas localmente: **ambas passam com `exit 0`**. Elas exigem credencial — `ROUTINE_API_KEY` (produção) e `OPENROUTER_API_KEY` — que existe na máquina do operador e **não existe no CI**: `scripts-tests.yml` não tem uma única referência a `secrets.` nem bloco `env:`.

As duas foram commitadas em `4b30ba0` (2026-09-18, "test(m3): versiona suites de busca OpenRouter e reconciliacao"). São **instrumentos de investigação** — o próprio cabeçalho de `test-m3-openrouter-search.ps1` diz *"standalone, NAO ALTERA motor, provider, scheduler, Worker, frontend"* — e foram versionadas com prefixo `test-` em `scripts/`, onde o runner faz glob de `test-*.ps1` e compara contra `scripts/tests-baseline.json` (que tem exatamente 2 entradas, nenhuma delas as M3).

**Por que isso importa mais do que parece:** o deploy da **v4.9.258 subiu com esse gate reprovando**. Com o gate permanentemente vermelho, **qualquer regressão real em `scripts/` fica invisível** — é o "alarme que toca sozinho", o modo de falha que o próprio projeto documenta em vários lugares.

---

## 6. O que NÃO foi feito

- Nenhuma alteração em código, `custo-config.json`, `wrangler.toml`, flags, crons ou secrets
- Nenhum deploy de Worker ou Pages
- Nenhuma alteração em `status/ESTADO.md` ou `PENDENCIAS.md`
- Working tree limpo exceto pelos relatórios 103 e 104 (não commitados)
- Os únicos comandos com efeito colateral foram as duas suítes M3, que escrevem em `logs/routines/teste-miniaturaminimaxm3/` — artefato de teste, não de produção

---

## 7. Decisões pendentes

Nada aqui deve ser executado sem decisão explícita do operador.

### 7.1 P0 — cobertura (o item que importa)

O plano de 104 emissores **não cabe** em 1.300.000 tokens/dia com as reservas atuais. Três caminhos, não mutuamente exclusivos:

> **O comportamento está correto e tem cobertura de teste verde.** As três suítes que exercitam o cap e o deferimento passam integralmente, medidas em 2026-09-19:
>
> | Suíte | Resultado |
> |---|---|
> | `scripts/test-quota-esgotada-failclosed.ps1` | `ok=64 falha=0` |
> | `scripts/test-idempotencia-janela.ps1` | `31/31 asserts OK` |
> | `scripts/test-varredura-defeitos.ps1` | `pass=44 fail=0` |
>
> **139 asserts verdes.** O disjuntor e o deferimento fazem exatamente o que foram construídos para fazer. **Não há bug a caçar aqui.** O defeito não está no mecanismo — está em o plano não caber no orçamento, e isso é decisão de orçamento (ou de tamanho de plano), não de código. Um conserto no cap seria consertar o que está funcionando.

- **(a) Subir o `TETO_DIA`.** É um arquivo editável (`logs/routines/custo-config.json`), sem deploy. Exige saber qual é o orçamento real disponível — decisão de negócio, não técnica.
- **(b) Reequilibrar as reservas.** `RESERVA_NOTURNO = 700.000` (54% do teto) somado ao `capProprio = 700.000` da própria noturna é redundante e estrangula o matinal a 350.000, que ele estourou por 2x.
- **(c) Reduzir o custo por emissor.** O 102 já aponta que o produto do trabalho é o que estoura. Reduzir `batch_size`, cortar `LIGHT`/`SKIP`, ou reduzir o universo por ciclo.

**Enquanto isso não for decidido, a rotina continua rodando, deferindo a maior parte do plano e fechando "OK".**

### 7.2 Guarda que não pode acordar

- `EMISSORSTALE1` existe e está testado, mas **não roda** porque `origin/main` está 5 commits atrás da produção. Enquanto isso, o sinal que alertaria o P0 acima fica desligado.
- `audit-routine-staleness.ps1` (skill) é manual e vive em `.claude/skills/vix-radar-audit/scripts/audit-routine-staleness.ps1` (não em `skills/`). É o instrumento que responde "quantos emissores estão fora do SLA de 24h" — rode-o agora e ele deve mostrar o mesmo `stale_24h_real` de 18/09 ou pior.
- Recomendação: um campo de **cobertura de análise** no health (`analisados_execucao` do dia, ou `emissores_analisados_24h`), porque hoje o health é estruturalmente incapaz de distinguir "rodou e analisou" de "rodou e deferiu tudo".

### 7.3 CI

Tirar as duas M3 de `scripts/` (mover para `scripts/diagnostico/` ou similar), ou adicioná-las ao baseline com motivo escrito, ou dar credencial ao job. Recomendação: **mover**, porque elas não são testes — são instrumentos.

---

## 8. Correção ao relatório 103

O `103 - Diagnostico CFG-02` está **correto no que afirma sobre o CFG-02**: a métrica de atribuição CVM é um artefato de relatório, a cobertura real é 100% e a quarentena real é 0.

Mas ele abre dizendo que "o sistema não está quebrado" com base em `ok:true`, `painel_fresco` e `feed_fresco`. **Essa inferência é inválida** — nenhum desses três campos mede se alguma análise foi produzida. O sistema está quebrado, e o defeito está neste documento, não naquele.

A lição operacional, para registro: **o health do VIX Radar não é um indicador de saúde do produto.** É um indicador de saúde da plataforma mais frescor de escrita. A pergunta "os emissores foram analisados?" não tem resposta em nenhum endpoint.

---

## Condição de Obsolescência

Cai quando qualquer um destes ocorrer:

1. `analisados_execucao` da noturna voltar a ser > 0 de forma sustentada, e o `stale_24h_real` do gate cair abaixo de 104.
2. Um campo de cobertura de análise for exposto no health (seção 7.2).
3. `EMISSORSTALE1` entrar em vigor em `main` e passar a alertar.
4. O `TETO_DIA` / reservas forem reequilibrados e o circuito deixar de abrir.

---

**Investigação:** sessão de 2026-09-19 (madrugada).
**Método:** leitura dos logs de rotina reais (`logs/routines/`), do motor `run_vixradar_varredura.ps1`, da lib `vixradar-custo.ps1`, do config de custo, do CI via `gh run`, e execução local das duas suítes M3.
**Nenhum artefato de produção foi alterado.**
