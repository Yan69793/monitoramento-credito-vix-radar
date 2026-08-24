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

- GitHub Actions runs do repo privado não auditáveis (API 404 anônima) — guarda do CI vista
  só no commit, não o run.
- Estado do `cvm:documentos` em produção pós-sync não verificado (endpoint exige senha admin).
- A prova de duas pontas da guarda foi reproduzida localmente, mas o `worker_fake.js` do CI se
  baseia em `perl` injetando em arquivo LF; no Windows com CRLF o perl não casa — o workflow
  roda em Linux, sem esse risco.

## Próximos passos

1. **P0:** corrigir `RELOGIO3H1` (linha 17781) + teste que falha com `horas_stale` de dado recém-gravado.
2. Re-rodar `audit-routine-staleness.ps1` após o deploy — esperado `ok:true`, `stale_24h_real:0`.
3. Atualizar cabeçalho `wrangler.toml` no próximo deploy.

*Registrar também em [[PENDENCIAS.md]].*
