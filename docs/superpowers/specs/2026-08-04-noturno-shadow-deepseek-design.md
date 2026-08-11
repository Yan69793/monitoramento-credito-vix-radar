# Design: Noturno Shadow DeepSeek (Fase A)

**Data:** 2026-08-04  
**Status:** implementado (flag off por default)  
**Escopo:** comparação Claude vs DeepSeek no noturno, sem submit do barato

## Decisões

| Item | Escolha |
|------|---------|
| Produção Worker | só Claude (primary) |
| Shadow | DeepSeek oficial (`api.deepseek.com`) |
| Evidências | mesmas `fontes_consultadas` + CVM do Claude (sem WebSearch própria) |
| Ativação | `-ShadowDeepSeek` ou `VIXRADAR_NOTURNO_SHADOW_DEEPSEEK=1` |
| Chave | `DEEPSEEK_API_KEY` ou `VIXRADAR_DEEPSEEK_API_KEY` |
| Modelos | RAPIDA → `deepseek-v4-flash`; APROFUNDADA → `deepseek-v4-pro` |

## Fluxo

1. Noturno roda como hoje (SKIP PS1 + lotes Claude + submit Worker).
2. Após cada submit de emissor com RESULTADO real, se shadow ON:
   - monta prompt com slim do emissor + resultado Claude (fontes + eventos)
   - chama DeepSeek chat/completions
   - parse `RESULTADO|…`
   - compara classif, eventos, URL primaria, memos
   - append `logs/routines/noturno_shadow_deepseek_YYYYMMDD.jsonl`
3. No FIM: `noturno_shadow_summary_YYYYMMDD.json`

## O que NÃO faz

- Não chama `receber_analise` com DeepSeek
- Não altera plano, tiers, hard cap Claude
- Não substitui auth Claude
- Não é hybrid B (Flash liberando ECO/NENHUM)

## Métricas de promoção (2 semanas + adjudicação)

- parse_ok_pct
- classif_diverge / n
- critico_divergente (lista `pendente_adjudicacao`)
- deepseek_url_invalida_total vs Claude
- tokens_deepseek_total (custo sombra)

Só promover hybrid B se divergência em CRITICO for aceitável com revisão humana.

## Arquivos

- `scripts/lib/vixradar-noturno-shadow-deepseek.ps1`
- `scripts/run_vixradar_noturno_claude.ps1` (param + hook + summary)

## Como ligar

```powershell
[Environment]::SetEnvironmentVariable('VIXRADAR_DEEPSEEK_API_KEY', '<key>', 'User')
[Environment]::SetEnvironmentVariable('VIXRADAR_NOTURNO_SHADOW_DEEPSEEK', '1', 'User')
# ou pontual:
pwsh -File "E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_noturno_claude.ps1" -ShadowDeepSeek
```
