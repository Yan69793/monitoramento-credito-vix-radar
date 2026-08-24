---
data: 2026-08-24
tipo: auditoria-operacional
tags: [vix-radar, producao, auditoria, staleness, fuso]
status: saudavel-com-achado
---

# Auditoria Operacional — VIX Radar (2026-08-24)

Modo: `vix-radar-audit` completo. Produção v4.9.212, frontend v202.30.

## Síntese

Produção **saudável** (health `ok:true`, auth fail-closed, drift repo=prod zerado, guards
funcionando), **mas com um achado ALTO de confiabilidade no fuso**: o `_last_scanned_at`
gravado pela rotina noturna/matinal é **3h no passado do relógio real**, o que infla
`horas_stale` em 3h e faz o gate de 24h de cobertura disparar falso ALTO mesmo com a
rotina tendo coberto 103/103 no dia. O incidente de cobertura reportado hoje por este
mesmo gate é falso positivo por esse bug de relógio.

## Versões e drift

| Camada | Repo | Produção | Drift |
|---|---|---|---|
| Worker | `main = v4.9.212.js` | v4.9.212 (`ok:true`) | Não |
| Frontend | `v202.30` | version.json `v202.30` | Não |

Cabeçalho do `wrangler.toml` (linha 2) ainda imprime "main = v4.9.211" enquanto o atributo
`main` aponta para `v4.9.212.js` e o changelog abaixo registra v4.9.212. **Inconsistência
só de doc no cabeçalho**, o atributo de verdade está correto. P3/cosmética.

## Achados

### ALTO — RELOGIO3H1: `_last_scanned_at` gravado 3h no passado infla o gate de cobertura (falso incidente)

- **Evidência:** audit `audit-routine-staleness.ps1` reportou `ok:false`, `stale_24h_real:4`
  (Simpar 25.1h, SLC Agrícola 25.1h, Bradesco 24.9h, Totvs 24.9h), entretanto o log da
  noturna de 23/08 tem `FIM: noturno concluido. Total do dia 103/103` (18:33:29) e os 4
  emissores aparecem como `OK|FULL|...|true` naquele dia (18:19–18:33). As análises reais
  tinham ~22h, não 25h.
- **Causa raiz:** `obterAgoraBRT()` retorna `new Date(Date.now() - 3*36e5)` — desloca o
  **epoch** 3h para trás. Isso é válido para obter o **dia civil** BRT (`hoje`), mas na
  linha **17781** o `receber_analise` grava `_raSaneado._last_scanned_at = _raAgoraBRT.toISOString()`
  como se fosse o **instante da varredura**. Na leitura, `_parseHorasStale` (linha 9464)
  compara esse timestamp contra `Date.now()` cru, então toda varredura parece 3h mais
  velha do que é. Reproduzido num mini-teste: `horas_stale` de um dado recém-escrito = 3h.
- **Guarda faltante:** nenhuma — nenhum teste compara um `_last_scanned_at` gravado com o
  relógio real. `obterAgoraBRT` como "fuso" só foi tratado como helper de **data** para
  janelas (FUSOTESTE1, `cvm-frescor.test.mjs`), não como **instante** de `last_scanned_at`.
- **Correção (proposta):** gravar `_last_scanned_at` como `new Date().toISOString()` (UTC real)
  e usar `obterAgoraBRT()` apenas para derivar `_raSemana`/`_raHoje`/`_raJanelaInicio`
  dos objetos que não viram timestamp comparável. Alternativa: manter o deslocamento, mas
  gravar `_raAgoraBRT.getTime() + 3*36e5` no `_last_scanned_at`.
- **Impacto antes de corrigir:** o gate de cobertura (skill `vix-radar-audit`, severidade
  ALTO com `stale_24h_real>0`) e o `frescor-check` podem emitir incidente falso; o operador
  perde confiança no canal ou passa a tratar ALTO real como ruído.

### Confirmado — verificação do restante da frente NOMEMORTO1
(vistoria: commit e55d68d, guarda de duas pontas, 62 testes verdes, v4.9.211→212 no ar,
tabelas de alias + sem acento na ingestão e na leitura, `admin_documentos_cvm` read-only).

## Validação em produção

| Teste | Resultado | Evidência |
|---|---|---|
| `GET /` health | 200, `ok:true`, v4.9.212 | bruto coletado |
| POST anônimo `{}` | **401** (auth fail-closed) | `{"ok":false,"erro":"Autenticação necessária."}` |
| Frontend | index www 200, version.json 200 = v202.30 | — |
| Guarda `check-emissores-cadastro.mjs` | 103 casando, exit 0; réplica fake reprovou exit 1 | duas pontas |
| `listar_plano_rotina` | tool 103 emissores, 4 "stale" = falso positivo (RELOGIO3H1) | — |

## Lacunas

- ~~GitHub Actions runs do repo privado não auditáveis (API 404 anônima)~~ — **FECHADA na rodada de
  verificação:** `gh` autenticado via keyring; Worker Tests v4.9.213 success com log bruto provando
  `test/relogio-varredura.test.mjs (3 tests)` e `69 passed (69)`; Cadastro dos Emissores success;
  canonical-test success nos 3 últimos slots.
- Estado do `cvm:documentos` em produção pós-sync não verificado (endpoint exige senha admin).
- A prova de duas pontas da guarda foi reproduzida localmente, mas o `worker_fake.js` do CI se
  baseia em `perl` injetando em arquivo LF; no Windows com CRLF o perl não casa — o workflow
  roda em Linux, sem esse risco.

## Próximos passos

1. **P0:** corrigir `RELOGIO3H1` (linha 17781) + teste que falha com `horas_stale` de dado recém-gravado.
2. Re-rodar `audit-routine-staleness.ps1` após o deploy — esperado `ok:true`, `stale_24h_real:0`.
3. Atualizar cabeçalho `wrangler.toml` no próximo deploy.

---

## Atualização (mesmo dia, pós-loop de 1 min) — RELOGIO3H1 RESOLVIDO em produção

A auditoria achou RELOGIO3H1; o operador corrigiu, testou e deployou ainda no dia 24/08. Loop de 1 min do vix-radar-audit capturou o deploy ao vivo: c3 17:43 BRT `ver=v4.9.212` → c4 17:44 `ver=v4.9.213`, estável pós-deploy (todos sinais `True`).

**Correção (commit `2928a74`):** `_last_scanned_at` agora é `new Date().toISOString()` (UTC real) no `receber_analise` e no fallback de persistência; `obterAgoraBRT()` segue só para datas. Evento com diferença de interpretação: a evidência usada na auditoria (os 4 emissores "stale") **não era sintoma** — eles vieram `sem_eventos` e esse ramo já gravava UTC real; a medição do operador (Light/Aegea/CSN/Hapvida com evento `h_stale 3,40` vs Rumo/Simpar sem evento `0,40`, 17:17 BRT) isolou a assimetria entre os dois ramos. O defeito era real e estava só no ramo com evento.

**Nova guarda:** `api/test/relogio-varredura.test.mjs` (3 testes), com prova reversa da reinjeção do bug.

**Prova em produção v4.9.213 (`listar_plano_rotina`):** `total:103`, `max_horas:4.7`, `stale>=24h:0`; `Engie _last_scanned_at=2026-08-24T20:47 h_stale:0`.

*Registro completo: [[PENDENCIAS.md]] (RELOGIO3H1 RESOLVIDO EM PRODUÇÃO).*

---

## Atualização final (verificação das lacunas) — BRASKEMDETECT1

Rodada de verificação do que a auditoria não cobriu por completo (2026-08-24, fim de sessão):

- **Lacuna CI fechada** — via `gh` autenticado: Worker Tests v4.9.213 green, `69/69`, incluindo
  `test/relogio-varredura.test.mjs` (3/3); Cadastro dos Emissores green; canonical-test green.
- **Lacuna `cvm:documentos` segue aberta** — exige `ADMIN_PASSWORD`, não auditado.
- **Fonte CVM 404 = cadência semanal** (CVMCADENCIA1), não incidente.
- **Achado novo P1: BRASKEMDETECT1** — Braskem protocolou recuperação extrajudicial 24/08
  (US$ 10,9 bi reestruturados); sistema não pegou (ZIP CVM 404 tirou gatilho primário + imprensa
  sozinha não alcançou protocolo). Registrado como ABERTO em [[PENDENCIAS.md]] e em [[03 - Estado Atual.md]].
- **Drift de doc corrigido** — `status/ESTADO.md` apontava "detalhe em PENDENCIAS.md" sem a entrada
  existir; entrada criada. Também corrigida a linha "AGUARDANDO DEPLOY" do ESTADO (já era v4.9.213 no ar).


