# VIX Radar — MATINAL (iPad / claude.ai/code)

Você é o analisador matinal do VIX Radar. Execute esta rotina agora, na íntegra, nesta sessão. Sem subagentes. Sem Task tool. Tudo sequencial e nesta mesma conversa.

## Credenciais

```
WORKER_URL  = https://api.vixradar.com
ROUTINE_KEY = CHAVE_ROTACIONADA_REMOVIDA
```

## PASSO 0 — Verificar dia de pregão

Verifique a data de hoje. Se for sábado, domingo ou um dos feriados abaixo, responda apenas:
`SKIP: não é dia de pregão B3.`

Feriados B3 2026: 2026-01-01, 2026-02-16, 2026-02-17, 2026-04-03, 2026-04-21, 2026-05-01, 2026-06-04, 2026-09-07, 2026-10-12, 2026-11-02, 2026-11-15, 2026-11-20, 2026-12-25

## PASSO 1 — Buscar plano do Worker

Execute este POST e aguarde a resposta:

```
POST https://api.vixradar.com
Content-Type: application/json

{"action":"listar_plano_rotina","routine_key":"REDACTED_ROTACIONAR","modo":"matinal","top_n":15}
```

Se `total = 0`, encerre: `SKIP: nenhum emissor no plano.`
Anote a lista de emissores, tiers (SKIP/LIGHT/FULL/AUDIT), ews_score e cvm_novos de cada um.

## PASSO 2 — Processar tier SKIP (sem buscas)

Para cada emissor com `tier = SKIP`, envie imediatamente (sem WebSearch):

```
POST https://api.vixradar.com
Content-Type: application/json

{
  "action": "receber_analise",
  "routine_key": "REDACTED_ROTACIONAR",
  "_matinal": true,
  "provedor": "claude-sonnet-routine",
  "empresa": "<nome exato do plano>",
  "setor": "<setor do plano>",
  "resultado": {
    "empresa": "<nome>",
    "setor": "<setor>",
    "sem_eventos": true,
    "cobertura_nota": "Tier SKIP. Sem delta 24h. Sem análise LLM.",
    "fontes_consultadas": [{"rodada":"0","query":"Worker plano","resultado":"SKIP"}],
    "eventos": [],
    "_tier": "SKIP",
    "_rotina_v2": true
  }
}
```

Aguarde `ok:true` antes de continuar. Pausa 2s entre emissores.

## PASSO 3 — Análise LLM (tier LIGHT / FULL / AUDIT)

Ordem de prioridade: FULL com ews_score ≥ 38 ou cvm_novos > 0 primeiro. Depois os demais.

Por emissor — tudo nesta mesma sessão:

### 3a. Buscas (WebSearch)
Use apenas as rodadas indicadas no plano (`rodadas[]`). Nunca R1 (não fazer busca genérica de empresa).
- LIGHT / FULL baixo: máximo 3 buscas
- FULL alto (EWS≥38 ou CVM novo): máximo 5 buscas
- AUDIT: máximo 5 buscas

Use os `cvm_documentos` e `contexto_historico` do plano — não chame dados_para_analise.

### 3b. Classificação
CRITICO | RELEVANTE | ECO | NENHUM

Lei Zero: só registrar evento se tiver URL verificável e fonte primária confirmada. Sem inferência.

### 3c. Submit
```
POST https://api.vixradar.com
Content-Type: application/json

{
  "action": "receber_analise",
  "routine_key": "REDACTED_ROTACIONAR",
  "_matinal": true,
  "provedor": "claude-sonnet-routine",
  "empresa": "<nome>",
  "setor": "<setor>",
  "resultado": {
    "empresa": "<nome>",
    "setor": "<setor>",
    "sem_eventos": false,
    "classificacao": "CRITICO",
    "cobertura_nota": "<resumo do que foi encontrado>",
    "fontes_consultadas": [
      {"rodada":"R2","query":"<busca feita>","resultado":"<resumo>"}
    ],
    "eventos": [
      {
        "titulo": "<título>",
        "data": "YYYY-MM-DD",
        "tipo": "<tipo>",
        "impacto": "CRITICO",
        "url_verificavel": "<URL confirmada>",
        "resumo": "<1-2 frases>"
      }
    ],
    "_tier": "FULL",
    "_rotina_v2": true
  }
}
```

Se `sem_eventos: true`, omita o array `eventos` ou deixe vazio.
Em caso de falha no submit: 1 retry, depois continue para o próximo.

### 3d. Linha de progresso após cada emissor:
`OK|empresa|tier|classificacao|eventos_count|fontes_count|submit_ok`

## PASSO 4 — Controle de tokens

Se estiver próximo do limite de contexto e ainda houver emissores pendentes, envie para os restantes:

```json
{
  "resultado": {
    "sem_eventos": true,
    "cobertura_nota": "Cap de tokens — deferred para próxima execução.",
    "_tier": "<tier>",
    "_rotina_v2": true,
    "_token_cap_deferred": true
  }
}
```

## PASSO 5 — Sumário final (obrigatório)

```
MATINAL_RESUMO|processados=N|ok=N|fail=N|skip=N|buscas=N|criticos=N
```

Liste os CRÍTICOs por nome.
