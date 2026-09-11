---
name: vixradar-noturno
description: >
  Rotina noturna VIX Radar. 103 emissores, diário 18h BRT.
  Caveman mode: 5 WebSearch rounds por emissor, zero fluff, mínimo de tokens.
---

# vixradar-noturno

Zero prosa. Só ação. Não explique nada — execute e log uma linha por emissor.

## Variáveis

```
WORKER=https://radar-credito-api.prospects-intel.workers.dev
KEY=$ROUTINE_API_KEY
PROVEDOR=claude-sonnet-routine
```

Se `$ROUTINE_API_KEY` vazio → tenta ler `~/.vixradar/routine_key.txt` → se ainda vazio, para com `ERRO: ROUTINE_API_KEY ausente`.

## Passo 1 — Lista

```bash
curl -s -X POST $WORKER \
  -H "Content-Type: application/json" \
  -d '{"action":"listar_todos_emissores","routine_key":"'$KEY'"}'
```

Extrai `emissores` (array `[{empresa, setor}]`). Se `ok:false` ou HTTP ≠ 200 → `ERRO: lista indisponível` e para.

## Passo 2 — Loop por emissor

Para CADA `{empresa, setor}` nos 103 emissores:

**a) Contexto histórico**

```bash
curl -s -X POST $WORKER \
  -H "Content-Type: application/json" \
  -d '{"action":"dados_para_analise","routine_key":"'$KEY'","empresa":"NOME","setor":"SETOR"}'
```

**b) 5 WebSearch rounds**

Execute as 5 buscas abaixo. Colete URLs + snippets relevantes. Não explique.

```
R1: "EMPRESA" rating rebaixamento upgrade outlook perspectiva 2026
R2: "EMPRESA" debênture spread emissão CRI CRA site:cvm.gov.br OR site:anbima.com.br
R3: "EMPRESA" fato relevante comunicado material 2026
R4: "EMPRESA" resultado fusão aquisição gestão crise 2026
R5: "SETOR" spread crédito Brasil inadimplência 2026
```

**c) Filtro de eventos**

Para cada sinal coletado:
- Classificação: `CRITICO` | `RELEVANTE` | `ECO` | `RUIDO`
- Descarta: `RUIDO`, sem URL verificável, data fora dos últimos 30 dias, duplicata do contexto histórico
- Mantém apenas `CRITICO` e `RELEVANTE`

**d) Envia resultado**

```bash
curl -s -X POST $WORKER \
  -H "Content-Type: application/json" \
  -d '{
    "action": "receber_analise",
    "routine_key": "'$KEY'",
    "empresa": "NOME",
    "setor": "SETOR",
    "_provedor": "'$PROVEDOR'",
    "sem_eventos": BOOL,
    "eventos": [
      {
        "data_evento": "YYYY-MM-DD",
        "titulo": "...",
        "classificacao": "CRITICO|RELEVANTE",
        "fonte_primaria": "https://...",
        "confianca": 0.0-1.0
      }
    ]
  }'
```

**e) Log inline** (uma linha, sem comentário):
- Sucesso: `✓ EMPRESA | N eventos`
- Falha: `✗ EMPRESA | HTTP_CODE`

## Passo 3 — Sumário final

Última saída obrigatória, nada mais após isso:

```
[NOTURNO] YYYY-MM-DD HH:MM BRT — X/103 ok | Y falhas
```
