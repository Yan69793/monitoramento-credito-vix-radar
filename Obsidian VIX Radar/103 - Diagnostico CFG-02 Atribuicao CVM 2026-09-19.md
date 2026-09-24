# 103 - Diagnóstico CFG-02 — Atribuição CVM

**Data:** 2026-09-19 (madrugada)
**Origem:** investigação da prioridade declarada no fechamento operacional de 18/09 (`672e982`)
**Escopo declarado pelo operador:** diagnóstico com prova, sem tocar código. Cumprido.
**Status:** DIAGNÓSTICO FECHADO. Nenhuma correção aplicada, nenhum deploy, working tree limpo.

> [!warning] CORREÇÃO — leia o `104` antes deste
> Este documento conclui, na seção **Veredito** abaixo, que "o sistema não está quebrado", com base em `ok:true`, `painel_fresco:true` e `feed_fresco:true`. **Essa inferência é inválida e foi falsificada.**
>
> Nenhum desses três campos mede se alguma análise foi produzida. Em 18/09 a noturna analisou **0 de 104** emissores e a matinal **4 de 23**, com o health verde o tempo todo. O sistema **está** quebrado — ver `104 - Diagnostico Operacional Circuito de Custo e Cobertura 2026-09-19.md`.
>
> O que este documento afirma **sobre o CFG-02 continua correto e medido**: a métrica de atribuição CVM é artefato de relatório, a cobertura real do acervo é 100% e a quarentena real é 0. O erro está apenas na inferência sobre a saúde geral do sistema.

---

## Veredito

**Não existe regressão de atribuição da CVM.** A cobertura real do acervo é **100%** e a quarentena real é **zero**.

O `cvm_atribuicao_cobertura_pct = 13.3` e o `cvm_atribuicao_quarentena = 9943` que aparecem no health público são **fabricados por um adaptador** que funde duas populações diferentes e rotula uma delas com o nome de outra. O `9943` não é quarentena: é a contagem de documentos do portal ENET de **qualquer companhia aberta do Brasil** descartados na entrada por estarem fora do universo dos 103 — comportamento fail-closed correto e documentado desde 25/08.

**CFG-02 não é um problema de pipeline. É um problema de relatório.**

O achado secundário, este sim material, está na seção 5: o filtro de ingestão contradiz o próprio comentário que o explica, e a guarda criada para vigiar essa classe de falha é **cega por construção** — o `exit 0` dela não prova nada.

---

## 1. Evidência

### 1.1 Health público × verdade medida no KV

Medido em 2026-09-19T03:03Z, Worker `v4.9.258`:

| Campo | Health público | Verdade (KV ao vivo) | Situação |
|---|---:|---:|---|
| acervo (`cvm:documentos`) | *não exposto* | **774** | — |
| atribuídos por CNPJ | 769 | **441** | rótulo errado |
| atribuídos por nome | 750 | **333** | rótulo errado |
| quarentena | **9943** | **0** | **inventado** |
| sem dono | *fixo em 0* | **0** | escondido |
| cobertura | **13,3%** | **100%** | **invertido** |
| emissores dos 103 em quarentena | — | **0** | guarda exit 0 |
| CNPJ plausível fora da família | — | **nenhum** | guarda exit 0 |

### 1.2 Reprodutibilidade — os comandos exatos

Ambas as guardas são read-only e usam a **mesma régua de produção** (`_atribuirDocumentoCVM`, `CNPJ_FAMILIA_CVM`, `CNPJ_PRIMARIO_EMISSOR` importados de `api/src/worker.js`).

```powershell
cd "E:\Diretorio\Claude\Monitoramento de Credito"

node scripts/check-quarentena-emissores.mjs
# acervo=774 cobertura={"cnpj":441,"nome":333,"quarentena":0,"sem_dono":0} pct=100
#   entidades_em_quarentena=0 retornadas=0
# OK: nenhuma das 0 entidades (maior volume da quarentena) pertence a um dos 103 por CNPJ.
# ---EXIT: 0---

node scripts/check-cnpj-familia.mjs
#   CNPJs no indice: 715
#   ja declarados (primario + familia): 151
#   recusados com motivo: 2
# OK: nenhum CNPJ plausivel ficou fora da familia sem decisao.
# ---EXIT: 0---
```

O `check-quarentena-emissores.mjs` obtém a credencial via `api/Get-VixAdminCredential.ps1 -AsPlainText` (helper DPAPI, não imprime segredo) e lê o endpoint `admin_cvm_quarentena`, que recomputa o árbitro sobre o acervo real.

### 1.3 Conferência aritmética

O número do health fecha exatamente com a fórmula do adaptador, o que prova qual ramo executou:

```
portal.total = quarentena + nome = 9943 + 750 = 10693
total        = 769 + 750 + 9943 + 0        = 11462
pct          = (769 + 750) / 11462 × 100   = 13,25% → 13,3  ✓
```

---

## 2. Mecanismo — `api/src/worker.js:20648`

Existem **três** caminhos que escrevem `cvm:documentos` / `cvm:fonte_meta`, e eles gravam formatos diferentes:

| Caminho | Linha | Filtra sem dono? | Formato de `cobertura` |
|---|---|---|---|
| `syncCVMZipHistorico` (ZIP) | 8264 | **Sim** (8400) | plano: `{cnpj, nome, quarentena, sem_dono}` |
| `syncCVMAutomatico` (portal ENET) | 8566 | **Sim** (8581) | aninhado: `{portal:{...}, zip:{...}}` |
| `handleSyncCVM` (POST admin) | 6882 | **Não** | ausente |

O health lê `cvm:fonte_meta.cobertura` e, se encontrar a forma aninhada, aplica este adaptador:

```js
// api/src/worker.js:20648
if (_cvmCob.portal) _cvmCob = {
  cnpj:       _cvmCob.zip && _cvmCob.zip.resolvidos || 0,
  nome:       _cvmCob.portal.resolvidos || 0,
  quarentena: Math.max(0, (_cvmCob.portal.total || 0) - (_cvmCob.portal.resolvidos || 0)),
  sem_dono:   0
};
```

Quatro defeitos em uma linha:

1. **`quarentena` não é quarentena.** É `portal.total - portal.resolvidos`, que é exatamente `descartadosAllowlist` — documentos do portal ENET que falharam `_atribuirDocumentoCVM` por estarem **fora do universo monitorado**. O árbitro tem uma origem própria chamada `"quarentena"` (CNPJ presente e não declarado), semanticamente diferente. Dois conceitos distintos compartilham um nome.
2. **`nome` não é atribuição por nome.** É `portal.resolvidos`, ou seja, tudo que o portal resolveu (por CNPJ *ou* por nome). O bucket real de atribuição por nome é 333; o health diz 750.
3. **`cnpj` não é atribuição por CNPJ.** É `zip.resolvidos`, que como o caminho ZIP filtra na entrada, equivale ao **acervo inteiro** (769). O bucket real por CNPJ é 441.
4. **`sem_dono` é fixo em 0.** Qualquer documento genuinamente órfão fica invisível por construção.

E o `pct` (linha 20650) **divide dois universos diferentes**: numerador do ZIP (`zip.resolvidos`), denominador do portal (`portal.total`). A razão resultante não mede nada.

---

## 3. Por que o número mudou de significado

A semântica da métrica **depende de quem escreveu `cvm:fonte_meta` por último** — não-determinismo latente:

- `syncCVMZipHistorico` grava a forma **plana**, onde `quarentena` tem o sentido real do árbitro. Foi o que produziu os **36,1% de 01/09**, que batiam com a verdade.
- `syncCVMAutomatico` chama `syncCVMZipHistorico` (8590) e **depois sobrescreve o meta** com a forma aninhada (8621). Num ciclo completo, a forma aninhada sempre vence.

Logo: **36,1% e 13,3% medem coisas diferentes.** A "queda material em 17 dias" registrada em `PENDENCIAS.md:160` é uma **redefinição de métrica**, não uma perda de atribuição.

No mesmo período a cobertura **verdadeira subiu de 36,1% para 100%**. O health andou para o lado oposto da realidade.

---

## 4. O que de fato aconteceu no acervo

| | 01/09/2026 | 19/09/2026 |
|---|---:|---:|
| acervo total | 2252 | **774** |
| com dono | 813 | **774** |
| sem dono | 1439 | **0** |
| cobertura verdadeira | 36,1% | **100%** |

Os documentos **nossos** permaneceram estáveis (813 → 774, variação de janela). O que saiu foram os **1439 sem dono** — expirados pelo TTL de 30 dias (`CVM_DOCUMENTOS_TTL_SEG`) e, na entrada, barrados pelo filtro da linha 8400.

O acervo não encolheu em conteúdo útil. Ele **ficou limpo** — e a métrica do health moveu na direção contrária.

---

## 5. Achado secundário — a fila de revisão que não existe

**Este é o achado material desta investigação.** Não estava no escopo do CFG-02 e é independente dele.

`api/src/worker.js:8387-8396` documenta a decisão de projeto do SUBSTRINGDONO1 fase CNPJ:

> "Agora o filtro de entrada e so categoria e janela de data, que sao fatos do documento e nao juizo sobre ele. **A atribuicao virou etapa de LEITURA. Documento de CNPJ desconhecido fica gravado, sem dono, e alimenta a fila de revisao.** E a diferenca entre 'nao sei de quem e' e 'nunca vi'."

O código na linha seguinte (`8399-8400`) faz o oposto:

```js
const allow = _atribuirDocumentoCVM((cols[iCnpj] || "").trim(), (cols[iNome] || "").trim());
if (!allow.emissor) { descartadosAllowlist++; /* ... */ continue; }   // ← descarta antes de gravar
```

**O comentário e o código se contradizem, e a fila de revisão prometida não existe.**

Confirmado nas duas pontas automáticas:

- `syncCVMZipHistorico:8400` — `continue` antes do `docs.push`
- `syncCVMAutomatico:8581` — `filtrados = validos.filter(... allow.emissor ...)`
- `syncCVMAutomatico:8602` — `candidatos = merged = zipDocs.concat(docs)`, ambos já filtrados
- `syncCVMAutomatico:8618` — grava `candidatos` em `cvm:documentos`

**Consequência 1 — a quarentena do acervo é sempre 0 por construção.** Só a via manual (`handleSyncCVM`, POST admin) consegue inserir documento sem dono.

**Consequência 2 — `admin_cvm_quarentena` lê esse acervo, então a fila é vazia por construção**, não por saúde.

**Consequência 3 — `check-quarentena-emissores.mjs` só pode examinar documentos que sobreviveram ao filtro.** Ele é **incapaz de detectar a própria classe de falha que existe para pegar**. O `exit 0` desta madrugada **não é prova de que os 103 estão atribuídos** — é prova de que o acervo não contém nada que pudesse reprovar.

**Consequência 4 — a cegueira da CSN continua possível.** Um emissor novo ou renomeado tem os documentos **descartados na entrada, em silêncio**, em vez de aparecer na fila. O `descarte` é contado em `descartadosAllowlist` e detalhado em `descartadosAllowlistCategoria` (ambos no meta, **não expostos no health**), mas ninguém lê esses campos — e nada no CI falha quando um deles cresce.

Isto é literalmente a classe que o fechamento de 18/09 nomeou como *"guarda que ficou cega"* (`CACHE_VERSION`). Aqui ela está em estado mais grave: a guarda **não pode** acender.

### 5.1 Nuance importante, para não exagerar o achado

O estado **atual** dos 103 está correto. O `check-cnpj-familia.mjs` verifica a outra ponta e passa: dos 715 CNPJs do índice CVM, 151 já estão declarados e nenhum candidato plausível ficou de fora sem decisão. Não há emissor quebrado hoje.

O defeito é de **observabilidade futura**, não de estado presente. A pergunta que o sistema deixou de saber responder é: *"existe documento de uma companhia que deveria ser nossa e que eu joguei fora?"*

---

## 6. Mapa de saída — crons, e-mails e a armadilha das flags

Levantado porque o operador pediu para "parar o que sai para fora". Não foi executado nada.

### 6.1 Crons (`api/wrangler.toml:1531`)

| Cron UTC | BRT | Ramo | Envia e-mail? |
|---|---|---|---|
| `0 1 * * *` | 22:00 | `ehWatchdog` | Sim — health para `ADMIN_EMAIL` (interno) |
| `0 4 * * *` | 01:00 | `ehAgenda` | **Não** — só `agendaBuildPersistir` |
| `30 15 * * *` | 12:30 | `ehMatinal` | **Não** — sync CVM, anomalias, ANBIMA, preditivo |
| `30 21 * * *` | 18:30 | `ehNoturno` | **Sim** — newsletter + boletim diário para assinante |

A newsletter e o boletim vivem no ramo **noturno** (`worker.js:22500` e `22506`), não no matinal. O próximo envio a assinante é **19/09 às 18:30 BRT**.

### 6.2 As duas flags desligam de jeitos diferentes

```toml
# api/wrangler.toml:1505-1506
RELATORIO_DIARIO_ENABLED = "1"
EMAIL_ALERTAS_ENABLED    = "1"
```

| Flag | Teste no código | Desliga com | Armadilha |
|---|---|---|---|
| `RELATORIO_DIARIO_ENABLED` | `!== "1"` (13509) | `"0"` | funciona ✅ |
| `EMAIL_ALERTAS_ENABLED` | **truthy** (5381, 13064, 13512, 22375) | só `""` | **`"0"` mantém ligado** ⚠️ |

`"0"` é string não-vazia, portanto truthy. Quem colocar `"0"` nas duas acredita ter desligado tudo e desligou apenas o boletim.

### 6.3 Saídas que **não** passam por nenhuma das duas flags

- `enviarEmailRastreado` — transacionais de aprovação, rejeição, cadastro, unsubscribe (6267, 6310, 6435, 6551, 6592, 6963, 6980)
- Alertas internos para `ADMIN_EMAIL` — providers (18058), rotina requer atenção (21400, 21438)
- `Teste Radar` para a lista inteira (21490) — apenas por ação admin explícita

Um corte realmente completo de saída exige agir no provedor (rotação da chave Resend), não nas flags — e isso **destrói a chave atual**, exigindo emissão de nova no Resend.

---

## 7. O que NÃO foi feito

- Nenhuma alteração em código
- Nenhum deploy de Worker ou Pages
- Nenhuma alteração em `wrangler.toml`, `status/ESTADO.md`, `PENDENCIAS.md` ou qualquer flag
- Nenhuma rotação de credencial
- Working tree limpo (verificado: `git status --short` vazio)
- Nenhum desligamento de rotina, cron, e-mail ou frontend

Os dois scripts executados são read-only por construção.

---

## 8. Decisões pendentes para o operador

### 8.1 CFG-02 — corrigir a semântica da métrica

Conserto de **leitura**, não de pipeline. Recomendação: expor as duas populações **separadas**, em vez de fundi-las num ratio.

- `cobertura_acervo` — a que importa (hoje 100%)
- `descartes_portal` — diagnóstico do funil ENET (hoje 9943), com `descartados_allowlist_categoria` visível
- `sem_dono` — deixar de ser fixo em 0
- `cvm_atribuicao_cobertura_pct` — **sair do health**. Na forma atual ele só pode enganar.

Exige bump de versão + `pwsh scripts/deploy-worker.ps1` (a mudança é em `api/src/worker.js`, gera bundle novo).

### 8.2 Linha 8400 — filtro de ingestão

Decisão de arquitetura, não de métrica. Duas saídas honestas:

- **(a)** Remover o filtro. O acervo passa a guardar documento sem dono e a fila de revisão passa a existir de verdade. Custo: acervo maior (o teto `TETO_DOCS = 16000` já comporta), e a quarentena deixa de ser 0 — o que é o ponto.
- **(b)** Manter o filtro e **corrigir o comentário**, assumindo formalmente que o descarte acontece na entrada. Nesse caso é **obrigatório** criar outra guarda que enxergue o descarte — a atual não enxerga.

A opção (b) sem guarda nova deixa o sistema exatamente no estado que produziu a CSN sem fonte primária por meses.

### 8.3 Registro

Este diagnóstico **não foi registrado** em `PENDENCIAS.md` nem em `status/ESTADO.md`. O item `CFG-02` segue na fila com a descrição antiga ("cobertura 13,3% e quarentena 9.943"), que agora se sabe estar errada. A atualização desses dois arquivos é decisão do operador.

---

## 9. Correções sugeridas à fila

Para quando o operador decidir atualizar a documentação canônica:

- `PENDENCIAS.md:72` — "CFG-02 continua aberto e **piorou**... Cresce ~30 por hora" → **incorreto**. Não há crescimento de quarentena; há recomputação de um contador de descarte do portal.
- `PENDENCIAS.md:97` — "cobertura 13,3% e quarentena 9.943" → **incorreto**. Cobertura real 100%, quarentena real 0.
- `PENDENCIAS.md:160` — "Queda material em 17 dias" → **incorreto**. Comparação entre duas definições distintas de métrica. A cobertura verdadeira subiu.
- `status/ESTADO.md:3` — "CFG-02 continua ABERTO e piorando" → reclassificar: CFG-02 é defeito de **relatório**, e o achado material é o da seção 5 (filtro 8400 + guarda cega).

---

## Condição de Obsolescência

Cai quando qualquer um destes ocorrer:

1. `cvm_atribuicao_cobertura_pct` e `cvm_atribuicao_quarentena` saírem do health ou forem redefinidos com populações separadas (seção 8.1).
2. O filtro da linha 8400 for removido, ou o comentário em 8387-8396 for corrigido com a guarda correspondente (seção 8.2).
3. O acervo real divergir materialmente de 774 documentos atribuídos, ou alguma das duas guardas passar a reprovar.

Enquanto isso, **este documento é a leitura correta do estado da atribuição CVM** — e o health público, neste campo específico, não é.

---

**Investigação:** sessão de 2026-09-19 (madrugada), a pedido do operador.
**Método:** leitura de código-fonte + duas guardas read-only do próprio projeto + medição ao vivo de `https://api.vixradar.com/`.
**Nenhum artefato de produção foi alterado.**
