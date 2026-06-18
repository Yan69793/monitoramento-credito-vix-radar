---
name: ODDA
description: >
  Framework OODA (Observe-Orient-Decide-Act) de John Boyd — decisão sob pressão
  com ciclo rápido em ~70% de confiança. Invocado como /ODDA ou OODA.
  Use em incidentes, debugging urgente, trade-offs com tempo limitado,
  ou quando o usuário pedir OODA loop.
---

# /ODDA — Loop OODA

**Princípio:** agir com ~70% de confiança em ações reversíveis, re-observar, repetir. Velocidade do loop > plano perfeito tardio.

## Quando usar

- Incidente, outage, degradação em andamento
- Debug com alvo móvel
- Decisão time-sensitive com informação incompleta

## Quando NÃO usar

- Situação estática com tempo — análise deliberada é melhor
- Ação irreversível/alto blast radius — coletar mais dados antes
- Causa localizável barato (diff, log) — ir direto à hipótese

## As quatro fases

### 1. OBSERVE — estado atual, rápido

- Métricas, logs, alertas, taxa de erro
- O que mudou (deploy, config, tráfego)
- Feedback da última ação
- Time-box: não observar para sempre

### 2. ORIENT — sentido

- ≥2 hipóteses concorrentes — não fixar na primeira
- Padrões conhecidos vs evidência nova
- Atualizar modelo mental se dados contradizem

### 3. DECIDE — ação sob incerteza

- Ação + hipótese que ela testa
- 70% agora > 90% tarde (se reversível)
- Definir o que observar nos próximos 2 min para confirmar/refutar

### 4. ACT — executar e re-observar

- Executar decisão
- Voltar imediatamente a OBSERVE
- Repetir até estável ou pedido resolvido

## Formato de resposta

```markdown
## OBSERVE
[fatos agora]

## ORIENT
[hipóteses + padrão]

## DECIDE
[ação + critério de sucesso em 2 min]

## ACT
[execução + próxima observação]
```

## Falhas comuns

| Falha | Correção |
|-------|----------|
| Paralisia na decisão | Deadline; agir em 70% |
| Uma hipótese só | Forçar segunda explicação |
| Agir sem re-observar | Observar resultado antes do próximo passo |
| Overload de dados | Filtrar sinais de maior valor |

Execute a tarefa do usuário (tudo após `/ODDA`) estruturando cada ciclo neste formato. Em tarefas longas, explicite em qual fase do loop está a cada passo.