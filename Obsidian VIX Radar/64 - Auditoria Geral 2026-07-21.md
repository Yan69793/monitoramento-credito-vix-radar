---
data: 2026-07-21
tipo: auditoria
tags: [vix-radar, auditoria-geral, seguranca, frontend, backend, confiabilidade, llm]
status: ativo
---

# Auditoria Geral, VIX Radar, 2026-07-21

Rodada da skill `/vix-radar-general-audit` em 4 camadas paralelas (backend Worker,
frontend com perf e a11y, segurança com cascade LLM mapeado ao OWASP LLM Top 10,
governança com confiabilidade e produto). Modo leitura, sem deploy. Os agentes
foram instruídos a não re-reportar o que já entrou no `PENDENCIAS.md` de manhã.

## Veredito

Produção saudável no núcleo, Worker v4.9.167 (build `5af9b39`) em ~107 ms, 103/103
emissores cobertos, JWT e senha sólidos, CORS fail-closed. Mas a auditoria abriu
**dois P1 que não estavam no radar de ninguém**: um stored XSS que rouba a sessão
do admin, explorável hoje, e uma tarefa de coleta que falha em toda execução e
alimenta justamente o Merton que passou a mover score anteontem.

## Top riscos

| Sev | ID | Achado | Ação |
|-----|-----|--------|------|
| P1 | ADMINXSS1 | Stored XSS na lista de usuários do painel: `app/index.html:3718` interpola `nome`/`email`/`empresa` crus via `innerHTML`, e o Worker grava esses campos só com `.trim()` (`v4.9.167.js:5584`). Cadastro com `empresa=<img onerror=…>` executa JS na sessão do admin, com `radar_jwt` no localStorage. | `esc()` no front + sanitizar no Worker. Deploy Pages + Worker |
| P1 | VOLTASK1 | `VIXRadar-Coleta-Volatilidade` com aspas `\"` literais na Action, `LastTaskResult 0x41303` (nunca rodou). Alimenta o `calcMertonDD`, vivo no score (MERTONLIVE1). NextRun hoje 17h. | Recriar a Action sem `\"`. Ação de sistema, deadline 17h |
| P2 | VERIFQ-ORFAO1 | Fila de verificação sem lock nem GC; evento persistido otimista com `_pendente_verificacao:true` é servido por `op=state` sem filtro, e o front não conhece o flag. Dreno parado = CRITICO alucinado público sem retratação. | Rotear pelo `EstadoSemanaDO` ou sweep de órfãos. Deploy Worker |
| P2 | VERIFINJ1 | Prompt do verificador adversarial interpola campos de evento crus (`:10131`), sem cerca. Fonte envenenada injeta veredicto no verificador (LLM01). | Delimitar dado não confiável + schema no veredicto. Deploy Worker |
| P2 | ROUTINEKEY-PLAIN1 | Chave de escrita do Worker em texto plano no `SKILL.md` da tarefa noturna (fora do repo, fora do gitignore). | Mover pra secret, remover o valor do arquivo |
| P2 | PDFXSS1 | Mesmo XSS no gerador de PDF (`document.write` same-origin). | Escapar no template do PDF. Deploy Pages |
| P2 | METRICSZERO1 | Skip idempotente da noturna zera o `metrics.json` do dia, apagando o run real. Replica na matinal amanhã (MATIDEM1). | Não regravar metrics no skip. Script local |

## Confirmações desta sessão (não são achado)

- Build em produção = `5af9b39` (terceiro deploy da v4.9.167), triangulado por
  histórico do wrangler, hash do bundle local e presença do Merton + guard.
- Merton DD vivo: 65/103 com `merton_dd`, 22 com score movido, driver visível em
  só 2 (ver [[63 - Recovery e Deploy 2026-07-20]] e MERTONLIVE1 no PENDENCIAS).
- Reconciliação CVM (P-CVM) e idempotência da matinal (MATIDEM1) corrigidas e
  validadas hoje de manhã (commits `7c371b6`, `7043645`).

## Drift de documentação corrigido nesta sessão

- `CLAUDE.md:91`: verificador não é metered, remove `ANTHROPIC_API_KEY` e usa OAuth.
  A nota 49 (não migrar pra Fable) foi decidida sobre aritmética metered irreal, reavaliar.
- `README.md`: matinal é Haiku, não Opus; comando de deploy do Worker corrigido pro canônico.
- `TECH_DEBT_AUDIT.md`: F003, F004, F006, F015 marcados como resolvidos com data.
- `PENDENCIAS.md`: header e síntese reconciliados (v4.9.167 no ar, vault commitado).

## Manutenção da própria skill (lacunas descobertas)

A skill `vix-radar-general-audit` tem três instruções desatualizadas, a corrigir
no `SKILL.md` e na `references/audit-matrix.md`:
1. Manda ler `03 - Estado de Produção.md`, renomeado pra `03 - Estado Atual.md` em 20/07.
2. Manda tratar OpenRouter/Gemini/Perplexity no health como resíduo de schema; a
   auditoria provou que OpenRouter/Perplexity têm chamada viva no cron e no health
   (OPENROUTERVIVO), só Gemini é resíduo de fato.
3. A matriz não cobre o pipeline preditivo v2 (Merton DD), que move score em produção.

## Próximos passos (ordem)

1. VOLTASK1 antes das 17h (deadline, alimenta o Merton).
2. ADMINXSS1: fix front + backend, deploy coordenado.
3. VERIFQ-ORFAO1 e VERIFINJ1 no próximo deploy do Worker (robustez do cascade LLM).
4. ROUTINEKEY-PLAIN1: mover a chave pra secret.
5. Lote de higiene: PDFXSS1, a11y (TOGGLEA11Y1, CONTRASTMUTED1), CATCH60, F013 residual.
