# 07 — Evolução do Sistema de Classificação e Prompts

> Sintetizado em 2026-06-10 a partir de dois arquivos recuperados do pendrive SanDisk:
> - `prompt-analista-senior-credito-privado.txt` (era Worker ~v4.6)
> - `prompt-classificacao-eventos-ruido-eco.txt` (era Worker ~v4.8–v4.9)

---

## 1. Linha do tempo da evolução

| Versão lógica | Tiers de classificação | ECO | nivel_conviccao | chamarGemini() |
|---|---|---|---|---|
| ~v4.6 (arquivo 1) | 3: CRÍTICO / RELEVANTE / RUÍDO | Não | Não | Direto via Gemini API |
| ~v4.8–v4.9 (arquivo 2) | 4: CRÍTICO / RELEVANTE / ECO / RUÍDO | Sim | Sim | Via OpenRouter (`google/gemini-2.5-flash:online`) |

---

## 2. O tier ECO — motivação e regras

### PRINCÍPIO DE COBERTURA (inviolável)
> O Radar deve capturar tudo que o IR da empresa publica. ECO é a categoria para eventos que existem mas não impactam crédito.

**Casos típicos de ECO:**
- Aprovação de dividendos / JCP
- Resultados trimestrais sem surpresa negativa
- Emissões de ações (diluição, não alavancagem)
- AGO / AGE de pauta rotineira
- Mudanças de nome / rebranding
- Novas subsidiárias sem impacto em covenant

**Memo para ECO (curto):**
```
memo_acontecimento: [o que é o evento, 1 frase]
memo_importancia_credito: "Evento sem impacto direto no perfil de crédito."
```

**Memo para CRÍTICO/RELEVANTE (completo):**
```
memo_acontecimento: [narrativa factual, sem julgamento]
memo_importancia_credito: [mecanismo de impacto no crédito]
memo_monitorar: [o que observar nas próximas semanas]
memo_acao_sugerida: [ação recomendada ao analista]
```

---

## 3. Sistema de tags EWS

### Tags negativas (acionam alerta de deterioração)
```
recuperacao-judicial, default, inadimplencia, waiver, cross-default,
assembleia-debenturistas, covenant, downgrade, reestruturacao,
liquidez, rating, venda-ativos, resultado-negativo, caixa,
investigacao, auditoria, regulatorio
```

### Tags positivas (acionam sinal de melhora)
```
captacao-sucesso, resultado-positivo, rating-upgrade, renovacao-credito,
amortizacao-antecipada, covenant-melhora, liquidez-melhora, upgrade
```

---

## 4. Protocolo de busca em 6 rodadas

| Rodada | Foco |
|---|---|
| R1 | Fatos CVM (RAD, ITR, DFP, FRE, Comunicado) |
| R2 | Ações de rating (S&P, Moody's, Fitch, SR) |
| R3 | Resultados trimestrais |
| R4 | Emissões de dívida (debêntures, CRI, CRA) |
| R5 | Estresse financeiro |
| R6 | Regulatório setorial |

---

## 5. Campos JSON do payload de saída

### Campos base (desde ~v4.6)
```json
{
  "empresa": "",
  "data_analise": "YYYY-MM-DD",
  "sem_eventos": false,
  "cobertura_nota": "",
  "fontes_consultadas": [],
  "eventos": [
    {
      "classificacao": "CRÍTICO|RELEVANTE|ECO|RUÍDO",
      "titulo": "",
      "evento": "",
      "impacto_credito": "",
      "contexto": "",
      "monitorar": "",
      "lente_setorial": "",
      "regulador_focus": "",
      "fonte_primaria": "",
      "fonte_tipo": "",
      "data_evento": "YYYY-MM-DD",
      "tags": []
    }
  ]
}
```

### Campos adicionados na versão 4-tier (~v4.8+)
```json
{
  "data_publicacao_fonte": "YYYY-MM-DD",
  "data_aproximada": false,
  "nivel_conviccao": "baixa|media|alta",
  "memo_acontecimento": "",
  "memo_importancia_credito": "",
  "memo_monitorar": "",
  "memo_acao_sugerida": ""
}
```

---

## 6. fonte_tipo — enum e classificação automática

### Enum de valores
```
CVM_RAD, B3, ANBIMA, RATING_AGENCY, IMPRENSA_OFICIAL,
RESEARCH_HOUSE, IMPRENSA
```

### Função `classificarTipoDadoFonte(fonte_primaria)`
Deriva `fonte_tipo` do hostname da URL.

**`DOMINIOS_OFICIAIS_SET`** → mapeia para `CVM_RAD` / `B3` / `ANBIMA`:
- `cvm.gov.br` → `CVM_RAD`
- `b3.com.br` → `B3`
- `anbima.com.br` → `ANBIMA`
- Agências regulatórias gov.br → `IMPRENSA_OFICIAL`

**`DOMINIOS_RESEARCH_SET`** → mapeia para `RESEARCH_HOUSE`:
- `spglobal.com`, `moodys.com`, `fitchratings.com`, `sr-rating.com`
- `xpinvestimentos.com.br`, `btgpactual.com`, `itau.com.br` (research)

**Regra crítica:** fontes `RESEARCH_HOUSE` **nunca** classificam evento como `CRÍTICO`. Classificação máxima permitida é `RELEVANTE`.

---

## 7. Cascade AI — evolução do roteamento

### Versão ~v4.6 (arquivo 1)
```
chamarGemini()      → Google Gemini API direta
chamarOpenRouter()  → OpenRouter (sonar-pro / Perplexity)
chamarPerplexity()  → Perplexity API direta
```
Ordem: Gemini → OpenRouter → Perplexity

### Versão ~v4.8+ (arquivo 2) — mudança crítica
```
chamarGemini()      → OpenRouter usando model "google/gemini-2.5-flash:online"
chamarOpenRouter()  → OpenRouter (sonar-pro)
chamarPerplexity()  → Perplexity API direta
```
**Gemini passou a rotear pelo OpenRouter** — unificação do billing e do circuit breaker. A função `chamarGemini()` mudou internamente sem alterar a interface do cascade.

Adicionado: `_gIncrementarCounter()` — counter KV para rastreamento de uso da API Gemini por emissor.

---

## 8. 7 regras invioláveis do memo

Documentadas nos prompts do sistema (buildSystemPrompt):

1. Nunca inventar dados — LEI ZERO
2. Todo número deve ter fonte e data
3. Separar fatos verificáveis de inferências (sinalizar explicitamente)
4. `nivel_conviccao: baixa` quando a fonte é única ou indisponível
5. Se a fonte for RESEARCH_HOUSE, classificação máxima = RELEVANTE
6. Eventos sem data precisa usam `data_aproximada: true`
7. ECO não gera memo longo — apenas `memo_acontecimento` + nota de não-impacto

---

## 9. Persistência KV

Chave de escrita: `dashboard:semana:{semanaKV}`

Lógica de overwrite: só sobrescreve se o novo resultado tiver **mais eventos** que o armazenado. Proteção contra degradação por retry.

Lookback multi-semana: `carregarEstadoMultiSemana(env, 5)` — cobre 5 semanas ISO (~35 dias). **Nunca usar semana única** nos endpoints `op=state`, `op=ews`, `briefing_executivo`, `historico_emissor`, `comparar`.

---

## 10. Função de newsletter

`buildSystemPromptNewsletter()` — variante do prompt principal para geração de conteúdo editorial. Presente desde ~v4.8. Consume estado multi-semana do KV (não replica cascade AI). Enviada via Resend com List-Unsubscribe e Reply-To.

---

## Fontes originais dos arquivos recuperados

| Arquivo | Origem provável | Era |
|---|---|---|
| `prompt-analista-senior-credito-privado.txt` | Bundle Worker extraído ~v4.6 | Abril 2026 |
| `prompt-classificacao-eventos-ruido-eco.txt` | Bundle Worker extraído ~v4.8–v4.9 | Abril–Maio 2026 |

Ambos recuperados do pendrive SanDisk via PhotoRec em 2026-06-10. Conteúdo já incorporado ao Worker de produção (v4.9.101).
