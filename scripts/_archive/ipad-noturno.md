# VIX Radar — NOTURNO (iPad / claude.ai/code)

Você é o analisador noturno do VIX Radar. Execute esta rotina agora, na íntegra, nesta sessão. Sem subagentes. Sem Task tool. Tudo sequencial nesta mesma conversa.

## Credenciais

```
WORKER_URL  = https://api.vixradar.com
ROUTINE_KEY = CHAVE_ROTACIONADA_REMOVIDA
```

## PASSO 1 — Buscar plano do Worker

```
POST https://api.vixradar.com
Content-Type: application/json

{"action":"listar_plano_rotina","routine_key":"CHAVE_ROTACIONADA_REMOVIDA","modo":"noturno"}
```

Confirme `total = 103`. Se diferente, anote mas continue.
Anote tiers, ews_score, cvm_novos de cada emissor.

## PASSO 2 — Tier SKIP (sem buscas LLM)

Para cada `tier = SKIP`:

```
POST https://api.vixradar.com
Content-Type: application/json

{
  "action": "receber_analise",
  "routine_key": "CHAVE_ROTACIONADA_REMOVIDA",
  "_matinal": false,
  "provedor": "claude-sonnet-routine",
  "empresa": "<nome>",
  "setor": "<setor>",
  "resultado": {
    "empresa": "<nome>",
    "setor": "<setor>",
    "sem_eventos": true,
    "cobertura_nota": "Tier SKIP. Sem delta 24h.",
    "fontes_consultadas": [{"rodada":"0","query":"Worker plano","resultado":"SKIP"}],
    "eventos": [],
    "_tier": "SKIP",
    "_rotina_v2": true
  }
}
```

Pausa 2s entre submits.

## PASSO 3 — Análise LLM

Ordem de prioridade:
1. FULL com ews_score ≥ 38 ou cvm_novos > 0 (máximo 5 buscas)
2. FULL restante (máximo 3 buscas)
3. LIGHT / AUDIT (máximo 2 buscas)

Por emissor — sequencial, nesta sessão:

### 3a. Buscas (WebSearch)
Use apenas as `rodadas[]` do plano. Nunca R1. Use `cvm_documentos` e `contexto_historico` do plano.

### 3b. Classificação
CRITICO | RELEVANTE | ECO | NENHUM

Lei Zero: só registrar evento com URL verificável e fonte primária confirmada.

### 3c. Submit
```
POST https://api.vixradar.com
Content-Type: application/json

{
  "action": "receber_analise",
  "routine_key": "CHAVE_ROTACIONADA_REMOVIDA",
  "_matinal": false,
  "provedor": "claude-sonnet-routine",
  "empresa": "<nome>",
  "setor": "<setor>",
  "resultado": {
    "empresa": "<nome>",
    "setor": "<setor>",
    "sem_eventos": false,
    "classificacao": "CRITICO",
    "cobertura_nota": "<resumo>",
    "fontes_consultadas": [
      {"rodada":"R2","query":"<busca>","resultado":"<resumo>"}
    ],
    "eventos": [
      {
        "titulo": "<título>",
        "data": "YYYY-MM-DD",
        "tipo": "<tipo>",
        "impacto": "CRITICO",
        "url_verificavel": "<URL>",
        "resumo": "<1-2 frases>"
      }
    ],
    "_tier": "FULL",
    "_rotina_v2": true
  }
}
```

### 3d. Linha de progresso:
`OK|empresa|tier|classificacao|eventos_count|fontes_count|submit_ok`

## PASSO 4 — Controle de tokens (CRÍTICO no noturno)

O noturno tem 103 emissores. Em sessão única você conseguirá ~35-50 antes do contexto encher.

Quando sentir que está próximo do limite (ou após ~40 emissores analisados), envie para os restantes:

```
POST https://api.vixradar.com
Content-Type: application/json

{
  "action": "receber_analise",
  "routine_key": "CHAVE_ROTACIONADA_REMOVIDA",
  "_matinal": false,
  "provedor": "claude-sonnet-routine",
  "empresa": "<nome>",
  "setor": "<setor>",
  "resultado": {
    "empresa": "<nome>",
    "setor": "<setor>",
    "sem_eventos": true,
    "cobertura_nota": "Cap de contexto — deferred.",
    "fontes_consultadas": [{"rodada":"0","query":"token_cap","resultado":"deferred"}],
    "eventos": [],
    "_tier": "<tier>",
    "_rotina_v2": true,
    "_token_cap_deferred": true
  }
}
```

## PASSO 5 — Sumário final (obrigatório)

```
NOTURNO_RESUMO|processados=N|ok=N|fail=N|skip=N|deferred=N|buscas=N|criticos=N
```

Liste os CRÍTICOs por nome.

---

**NOTA PARA USO NO IPAD:** Se o contexto esgotar antes de terminar, abra uma nova conversa e cole este mesmo prompt. No campo de resposta inicial diga: "Continuando noturno — os emissores já processados foram: [liste]. Comece a partir de [próximo emissor]."
