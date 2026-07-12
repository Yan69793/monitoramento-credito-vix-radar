# AGENTS.md — Projeto "Oportunidades de Mercado"

Regras operacionais para qualquer agente de IA (Claude, GPT, Gemini, scripts autônomos) que consulte, gere ou atualize análises neste projeto. Este arquivo é agnóstico de modelo — `CLAUDE.md` traz o ajuste fino específico do Claude.

## Escopo do projeto

Screening e recomendação de ativos subvalorizados para compra/operação (curto, médio, longo prazo):
1. Renda variável — ações, ETFs, BDRs (B3 / NYSE / NASDAQ).
2. Crédito — títulos públicos (Tesouro Direto) e privados (debêntures, CDBs, CRIs, CRAs, corporate bonds).

## Fontes de dado autorizadas

B3, CVM, SEC, Bloomberg, Reuters, Tesouro Direto, ANBIMA, Status Invest, Fundamentus, Investidor10, RI das empresas. Qualquer agente que não tenha acesso direto a essas fontes deve declarar a limitação em vez de substituir por estimativa.

## Regras não negociáveis (aplicam-se a todos os agentes)

- **Sem dado real-time verificado, sem afirmação de preço/múltiplo/rating.** Formato de declaração de ausência: `"Dado não disponível em [fonte] (consulta: [data/hora])"`.
- **Sem extrapolação.** Números vêm de fonte citada ou não entram na análise.
- **Piso de liquidez**: ações/ETFs > R$ 1M/dia; crédito > R$ 500K/dia. Ativo abaixo do piso é excluído e o corte é explicitado.
- **Exclusões automáticas**: ativos em penhor/leilão/restrição (B3); empresas com prejuízo recorrente nos últimos 3 anos (CVM).
- **Toda saída cita fonte + timestamp da consulta**, não a data de publicação do dado subjacente.

## Critérios de filtro (referência única — não duplicar valores em outros arquivos)

**Princípio obrigatório: nenhum piso de renda variável ou crédito é um número absoluto fixo. Todo piso é um spread sobre Selic/CDI/soberano vigente**, recalculado a cada consulta. Números fixos (ex.: "P/L < 10") ficam obsoletos a cada ciclo de Copom e podem inverter a lógica do filtro — ver nota de revalidação abaixo.

| Categoria | Métrica | Regra |
|---|---|---|
| Renda variável (valuation) | Earnings yield (1/P/L) | > Selic vigente + 3 p.p. |
| Renda variável (valuation) | Dividend Yield | > CDI vigente − 3 p.p., piso absoluto 6% |
| Renda variável (valuation) | P/VP, EV/EBITDA, ROE, Payout, Dívida/EBITDA, Margem líquida, Free float | < 1,5 · < 8 · > 15% · < 80% · < 1,5 · > 10% · > 20% (fixos — não dependem de juros) |
| Renda variável (técnica) | Preço vs. média 200d, RSI(14), volume 20d, suporte | Abaixo da média · < 30 · crescente · próximo |
| Crédito público | NTN-B / NTN-F / LTN | Taxa de mercado vigente (são o próprio benchmark — sem spread a exigir) |
| Crédito privado — Debêntures | Rating ≥ AA-/A, sem sinal de deterioração | NTN-B vigente + 1 a 2 p.p. |
| Crédito privado — CDBs | Rating ≥ A, bancos top 10 | CDI vigente + 0,5 a 2 p.p. |
| Crédito privado — CRI/CRA | Rating ≥ AA- | NTN-B vigente + 1 p.p. |
| Risco de crédito | Duration, rating, garantia | < 5 anos · priorizar investment grade · priorizar lastro real |

## Nota de revalidação (última consulta: 09/07/2026, com evidência de mercado real via scans do Radar de Crédito Privado)

Selic 14,25% a.a. (Copom 17/jun/2026) · CDI ~14,78% a.a. · NTN-B soberana emitindo a IPCA+8% (jun/2026) · CDS Brasil 5a ~116 bps (mín. mai/2026, vs. 178 bps um ano antes).

**Achado inicial:** os pisos absolutos anteriores (debênture IPCA+8%, CRI/CRA IPCA+7%) ficaram em ou abaixo do soberano — spread de crédito zero ou negativo, o que não compensa risco de crédito/iliquidez. O screen de equity (P/L<10 isolado) não travava earnings yield contra a Selic, permitindo ações com yield abaixo do risco-free. Ambos corrigidos para spread/hurdle relativo.

**Calibração com dado real** (scans/*.json do Radar, jun/2026 — fonte primária: Fitch, CVM/RAD, agregadas pelo pipeline do próprio Radar):
- Vibra Energia (DL/EBITDA 2,0x, crédito sólido): VBBR14 a **CDI+1,45%** → valida o piso de debênture IG em 1-2 p.p.
- Aegea Saneamento (Fitch rebaixou BB-→B+ em 09/06, alavancagem ~5x): AEGP17 abriu de **CDI+2,42% para CDI+6,30%** no mês do downgrade → confirma que CDI+5%+ é preço de crédito já em junk, não de rating ≥A. **O piso antigo de CDB (CDI+5%) estava, na prática, calibrado para um emissor rebaixado — não para o rating ≥A/bancos top 10 que o filtro dizia exigir.**
- Kora Saúde (rating C(bra), recuperação extrajudicial): reperfilamento a CDI+2,8% — descartado como referência de mercado por ser taxa de renegociação forçada.

Revalidar a cada reunião do Copom (próxima: 05/08/2026), quando CDS Brasil variar >30 bps, ou quando o Radar sinalizar novo evento CRITICO de rating em nome relevante.

## Formato de output padronizado

Todo ativo recomendado é reportado com: identificação + preço/data, bloco fundamentalista, bloco técnico, bloco macro (setor, catalisador, risco), recomendação (entry/stop/take-profit/horizonte/peso), fontes com link. Agentes que gerarem output em formato diferente devem justificar o desvio.

## Padrão de comunicação exigido do agente

- Começar pela conclusão e pelos riscos, não pelo contexto.
- Classificar cada afirmação: `[CERTO]` (fato verificável), `[PROVÁVEL]` (inferência forte), `[HIPÓTESE]` (não validada), `[ESPECULAÇÃO]` (baixa confiança).
- Não validar teses do usuário por educação. Ao discordar: motivo objetivo + alternativa + risco da abordagem atual.
- Não inventar contraponto por reflexo de "advogado do diabo".
- Revisar posição só diante de evidência nova, nunca por insistência.

## Manutenção deste arquivo

Alterações nos filtros quantitativos (P/L, rating mínimo, piso de liquidez etc.) devem ser feitas aqui e refletidas em `CLAUDE.md` — este é o arquivo de referência única para não gerar divergência entre agentes.
