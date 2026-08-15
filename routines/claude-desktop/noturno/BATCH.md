# Lote noturno v2 — instruções compactas

Modelo: `claude-sonnet-4-6`. Worker: `https://api.vixradar.com`.

## Proibições

- **PROIBIDO** Task/subagent por emissor ou em paralelo.
- **PROIBIDO** `listar_plano_rotina` — plano já injetado no prompt.
- **PROIBIDO** `dados_para_analise` e busca R1 CVM web.
- **PROIBIDO** narrativa longa entre emissores.
- **PROIBIDO** gravar arquivos locais (`testing/`, `.noturno_*`, JSON de replay). Submit só via curl ao Worker.

## Orçamento de buscas

| Tier | Máx buscas | Rodadas |
|------|------------|---------|
| LIGHT | 3 | só `rodadas[]` do plano (priorizar R2, R5, R6) |
| FULL | 5 | só `rodadas[]` (priorizar R2, R6, R5, R4, R3) |
| AUDIT | 5 | igual FULL |

Use `cvm_documentos` do plano como fonte CVM primária.

## Por emissor (sequencial)

1. Executar buscas dentro do orçamento do tier.
2. Classificar: CRITICO | RELEVANTE | ECO | NENHUM.
3. Montar JSON `resultado` completo para o Worker.
4. `POST receber_analise` com `_matinal:false`, `provedor:"claude-sonnet-routine"`.
5. Falha → 1 retry → registrar e continuar.
6. Pausa 2s antes do próximo emissor.
7. Reportar linha compacta: `OK|empresa|tier|classificacao|eventos_count|fontes_count|submit_ok`

## Payload submit (Worker)

- `fontes_consultadas`: apenas rodadas executadas.
- `eventos[]`: CRITICO exige URL verificável; Lei Zero.
- `_tier` e `_rotina_v2:true`.
- ECO/NENHUM: `cobertura_nota` curta (1–2 frases).

## Sumário do lote (ao final)

```
LOTE_RESUMO|ok_count|fail_count|buscas_total|criticos_lista
```