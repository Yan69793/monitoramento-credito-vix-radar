# CAL-002: Comandos de Correção do Calendário 2T26

Data: 2026-07-29. Worker: v4.9.183. Status: v4.9.183 merged em main, wrangler.toml atualizado.

## Resultados da verificação contra RI oficial

| Emissor | Data no Sistema | Data Oficial (RI) | Divergência | Fonte |
|---|---|---|---|---|
| Bradesco | 28/07 | **05/08** após fechamento | 8 dias | https://www.bradescori.com.br/informacoes-ao-mercado/agenda-2t26/ |
| Vale | 24/07 | **30/07** após fechamento | 6 dias | https://vale.com/pt/w/vale-divulga-as-datas-para-o-relatorio-de-desempenho-no-2t26 |
| Gerdau | 29/07 | **04/08** após fechamento | 6 dias | https://ri.gerdau.com/ (popup Divulgação de Resultados) |
| Suzano | 30/07 | **12/08** após fechamento | 13 dias | https://ri.suzano.com.br/ |
| Petrobras | 28/07 | N/D | N/D | Não encontrada em fonte primária |
| Itaúsa | 29/07 | N/D | N/D | Calendário de eventos vazio no RI |
| Embraer | 30/07 | N/D | N/D | Central de resultados sem dados 2026 |

Taxa de erro: 4/4 datas verificadas estão erradas (100%).

## Comandos de correção

O endpoint `atualizar_calendario_emissor` aceita POST com `routine_key`.
Substitua `<ROUTINE_API_KEY>` pela chave ativa (nunca comitar este arquivo).

### 1. Corrigir Bradesco: 05/08

```bash
curl -s -X POST https://api.vixradar.com/ \
  -H "Content-Type: application/json" \
  -d '{
    "action": "atualizar_calendario_emissor",
    "routine_key": "<ROUTINE_API_KEY>",
    "empresa": "Bradesco",
    "trimestres": [
      {
        "periodo": "2T26",
        "data_prevista": "2026-08-05",
        "status": "agendado",
        "fonte": "https://www.bradescori.com.br/informacoes-ao-mercado/agenda-2t26/",
        "fonte_tipo": "ri_primario",
        "nota": "Após fechamento B3 e NYSE. Videoconferência 06/08 10h30 BRT. Período de silêncio 22/07 a 05/08."
      }
    ]
  }' | jq .
```

### 2. Corrigir Vale: 30/07

```bash
curl -s -X POST https://api.vixradar.com/ \
  -H "Content-Type: application/json" \
  -d '{
    "action": "atualizar_calendario_emissor",
    "routine_key": "<ROUTINE_API_KEY>",
    "empresa": "Vale",
    "trimestres": [
      {
        "periodo": "2T26",
        "data_prevista": "2026-07-30",
        "status": "agendado",
        "fonte": "https://vale.com/pt/w/vale-divulga-as-datas-para-o-relatorio-de-desempenho-no-2t26",
        "fonte_tipo": "ri_primario",
        "nota": "Após fechamento. Relatório de produção e vendas foi 21/07 (evento distinto, não resultado)."
      }
    ]
  }' | jq .
```

### 3. Corrigir Gerdau: 04/08

```bash
curl -s -X POST https://api.vixradar.com/ \
  -H "Content-Type: application/json" \
  -d '{
    "action": "atualizar_calendario_emissor",
    "routine_key": "<ROUTINE_API_KEY>",
    "empresa": "Gerdau",
    "trimestres": [
      {
        "periodo": "2T26",
        "data_prevista": "2026-08-04",
        "status": "agendado",
        "fonte": "https://ri.gerdau.com/",
        "fonte_tipo": "ri_primario",
        "nota": "Após fechamento B3 e NYSE. Videoconferência 05/08 12h BRT."
      }
    ]
  }' | jq .
```

### 4. Corrigir Suzano: 12/08

```bash
curl -s -X POST https://api.vixradar.com/ \
  -H "Content-Type: application/json" \
  -d '{
    "action": "atualizar_calendario_emissor",
    "routine_key": "<ROUTINE_API_KEY>",
    "empresa": "Suzano",
    "trimestres": [
      {
        "periodo": "2T26",
        "data_prevista": "2026-08-12",
        "status": "agendado",
        "fonte": "https://ri.suzano.com.br/",
        "fonte_tipo": "ri_primario",
        "nota": "Após fechamento do mercado."
      }
    ]
  }' | jq .
```

## Rollback

Para reverter um override, deletar a entrada do emissor no KV. Não há endpoint DELETE,
então é necessário reescrever o documento sem o emissor. O snapshot do documento atual
deve ser capturado antes da primeira escrita:

```bash
# Snapshot antes de qualquer mutação
npx wrangler kv key get --binding=RADAR_KV --remote "calendario:overrides:v1" > calendario_overrides_snapshot_$(date -I).json
```

## Validação pós-correção

```bash
# Confirmar que op=calendario reflete as novas datas
curl -s -X POST https://api.vixradar.com/ \
  -H "Content-Type: application/json" \
  -d '{"action":"calendario","empresa":"Bradesco"}' | jq '.trimestres'

# Health check
curl -s https://radar-credito-api.prospects-intel.workers.dev | jq .
```
