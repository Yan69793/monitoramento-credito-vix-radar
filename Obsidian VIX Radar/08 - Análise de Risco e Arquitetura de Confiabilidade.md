# 08 — Análise de Risco e Arquitetura de Confiabilidade

> Sintetizado em 2026-06-10 a partir do arquivo recuperado do pendrive SanDisk:
> - `doc-analise-risco-fallback-providers.txt` (documento de arquitetura, ~Abril 2026, era Worker v3.9.6)
>
> Nota: A maior parte destas recomendações foi implementada em v4.8.0+. Este documento preserva o raciocínio original e os critérios de design.

---

## 1. Matriz de risco original (versão v3.9.6)

| Risco | Probabilidade | Impacto | Esforço | Mitigação na época |
|---|---|---|---|---|
| Todos os providers falham sem fallback | Alta | Crítico | Médio | Nenhuma |
| KV sem validação de schema | Média | Crítico | Baixo | Nenhuma |
| METRICAS_CURADAS hardcoded | Alta | Alto | Médio | Nenhuma |
| DNS/SPF email bloqueado | Certeza | Alto | Baixo | Config DNS Resend |
| JWT sem rotação | Baixa | Médio | Médio | Nenhuma |
| Sem monitoramento externo | Certeza | Médio | Baixo | UptimeRobot/BetterUptime |

**Status de implementação (2026-06-10):** Circuit breaker por provider ✅, validação de schema ✅, DNS Resend ✅ (parcial — SPF ok, DMARC pendente), JWT rotação ✅ (PBKDF2), monitoramento externo ⚠️ (não confirmado).

---

## 2. Pipeline de validação em 3 estágios

Implementado a partir de v4.8.0. Cada payload retornado pelo cascade AI passa pelos 3 estágios antes de persistir no KV.

### Estágio 1 — Validação de schema
Campos obrigatórios e tipos:
- `empresa` (string, não vazio)
- `data` (string, formato YYYY-MM-DD)
- `classificacao` (enum: CRÍTICO/RELEVANTE/ECO/RUÍDO)
- `descricao` (string, mínimo 20 chars)
- `fonte` (string, não vazio)
- `tags` (array)

Payload rejeitado se qualquer campo obrigatório faltar ou tiver tipo errado.

### Estágio 2 — Regras de negócio
- Janela de 7 dias: eventos com `data_evento` anterior a 7 dias são descartados por padrão (exceto via `ARQUIVO_PRE`)
- Promoção/downgrade de classificação: RESEARCH_HOUSE não pode gerar CRÍTICO → downgrade automático para RELEVANTE
- Fontes desconhecidas em CRÍTICO → quarentena (não persistido, requer revisão manual)

### Estágio 3 — Consistência temporal
- Deduplicação: mesmo `empresa + titulo` dentro de 72h → descarta o mais antigo
- Detecção de regressão temporal: `data_evento` do novo resultado < `data_evento` do resultado armazenado → alerta
- Detecção de contradição: classificação oposta para o mesmo evento dentro de 48h → sinaliza para revisão

---

## 3. Observabilidade proativa

### Métricas técnicas — thresholds operacionais

| Métrica | Normal | Degradação | Crítico |
|---|---|---|---|
| Latência OpenRouter | 5–15s | >25s | >45s |
| Latência Gemini (via OR) | 3–8s | >20s | >35s |
| Latência Perplexity | 5–15s | >25s | >45s |
| Taxa de cascade trigger | <5%/h | >20%/h | >50%/h |
| Taxa de rejeição de schema por provider | <5% | >30% | >60% |
| Custo por execução | ~R$0,01 | >R$0,05 | >R$0,15 |

> **Taxa de cascade >20%/h em 1 hora = problema estrutural**, não pico pontual.
> **Rejeição de schema >30% para provider específico** = degradação qualitativa daquele provider.

### Métricas de negócio

- Distribuição de classificações ao longo do tempo (deriva de % CRÍTICO indica mudança de qualidade do modelo)
- Taxa implícita de falso positivo (eventos CRÍTICO que somem da próxima análise sem resolução)
- Freshness por emissor (última análise com eventos vs. hoje)

### 3 níveis de alerta

| Nível | Ação |
|---|---|
| WARN | Incrementar counter KV (`warn:cascade:provider:X`) |
| ERROR | Email via Resend + ativar cache de último resort |
| CRITICAL | Flag `sistema_em_degradacao: true` em KV + banner para o usuário no frontend |

---

## 4. Governança de deploy

### Versionamento imutável
- Hash SHA-256 de cada artefato deployado
- Hash registrado em KV `deploy:history:{timestamp}`
- `CACHE_VERSION` gerado deterministicamente a partir do hash (não incrementado manualmente)

**Status atual (2026-06-10):** `CACHE_VERSION` ainda é incrementado manualmente. Hash imutável não implementado.

### Testes obrigatórios pré-deploy
1. Teste de endpoint: análise Sabesp (setor Saneamento) — valida cascade completo
2. Teste de autenticação: login + JWT válido
3. Health check GET `/`

### Trigger de rollback automatizado
- `kv: false` no health check após deploy → rollback imediato
- >10% HTTP 5xx nos 10 minutos pós-deploy → rollback imediato

### Checklist de integrações externas pré-deploy
- Saldo OpenRouter ≥ R$1,00
- Quota diária Gemini ≥ 500 requisições
- Validade da chave Perplexity confirmada

---

## 5. Cache de último resort

Implementado em v4.8.0+. Quando todos os providers falham:
- Worker serve último resultado válido armazenado em KV
- TTL: 24h
- Flag `_cache_ultimo_resort: true` no payload devolvido
- Não aciona novas tentativas de cascade

---

## 6. Circuit breaker por provider

Implementado em v4.8.0+. Estado por provider: `CLOSED` (normal) / `OPEN` (em falha) / `HALF_OPEN` (testando).

- Abre após N falhas consecutivas (threshold configurável)
- Permanece aberto por janela de tempo (backoff exponencial)
- Half-open: permite 1 requisição de teste para verificar recuperação
- Estado persistido em KV `circuit:provider:{nome}`

---

## 7. Protocolo de validação pós-deploy (do documento original)

O documento especificou o ritual que foi posteriormente formalizado no CLAUDE.md:

```bash
curl -s -X POST https://radar-credito-api.prospects-intel.workers.dev \
  -H "Content-Type: application/json" \
  -d '{"empresa":"Sabesp","setor":"Saneamento"}' \
  --max-time 120 \
  -w "\nTEMPO: %{time_total}s | HTTP: %{http_code}"
```

Esperado: HTTP 200, tempo <30s, payload com `eventos` e `_qualidade_sinal`.

> **Nota:** A partir de v4.9+ o endpoint `/` exige JWT (`Authorization: Bearer ...`). O teste anônimo retorna 401. Usar token autenticado para validação end-to-end.

---

## 8. Recomendações do documento ainda pendentes (2026-06-10)

| Recomendação | Status |
|---|---|
| Monitoramento externo (UptimeRobot/BetterUptime) | ⚠️ Não confirmado ativo |
| DMARC no DNS Resend | ⚠️ Pendente |
| Hash imutável de artefatos no deploy | ❌ Não implementado |
| Rollback automatizado por 5xx | ❌ Não implementado |
| Distribuição de classificações ao longo do tempo (métrica) | ❌ Não implementado |

---

## Fonte original do arquivo recuperado

| Arquivo | Origem provável | Era |
|---|---|---|
| `doc-analise-risco-fallback-providers.txt` | Documento de arquitetura gerado ~Abril 2026 | Worker v3.9.6 |

Recuperado do pendrive SanDisk via PhotoRec em 2026-06-10. Contém "Entrega 5 — Prompt Manus v3.9.6" (5 tasks: DNS email, circuit breaker + cache, pipeline de validação, endpoint de métricas, UptimeRobot) — a maior parte implementada em v4.8.0+.
