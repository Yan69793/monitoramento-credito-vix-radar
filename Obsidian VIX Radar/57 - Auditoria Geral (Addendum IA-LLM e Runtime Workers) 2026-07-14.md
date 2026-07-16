# Auditoria Geral — Addendum IA/LLM + Runtime Workers (2026-07-14)

Re-execução de `/vix-radar-general-audit` no mesmo dia da nota [[56 - Auditoria Geral Backend Frontend 2026-07-14]], após a skill ganhar 2 seções novas (pesquisa externa: OWASP Top 10 for LLM Applications 2025 + guia oficial Cloudflare Workers Best Practices, publicado 2026-02-15). Este addendum cobre só o que a nota 56 não tinha — os achados dela (TOKENEST1, PRNG1, RACEKV1, token CF vivo, XSSEVT1, etc.) permanecem válidos e não foram reconferidos aqui.

## Drift de escopo (checagem da própria skill)

`git log --oneline -20` nos arquivos vivos desde a nota 56 mostra só o commit `a06cded` (v4.9.156, FIN1-4/DIV1-5/FIX2/5/6/7/8 — loop SKIP do setor financeiro). Nenhum subsistema novo (fila, binding, endpoint, integração) que exija checklist novo na matriz. Repo confirmado sem drift: `wrangler.toml main=v4.9.156.js` = produção (`curl` ao vivo: `versao:"v4.9.156" ok:true verificador_ok:true bindings kv/rate_limiter/telemetria true`).

## IA generativa / cascade LLM (mapeado ao OWASP LLM Top 10 2025)

| Risco OWASP | Achado | Evidência | Veredito |
|---|---|---|---|
| LLM01 Prompt Injection | Verificador adversarial trata todo evento como falso até prova (`buildVerifierSystemPrompt`) — mitigação por design contra alucinação, mas prompt não tem instrução explícita de "ignore instruções embutidas no texto da fonte". Prompt de **análise primária** (1º estágio) vive fora do Worker, em skills/markdown orquestrados por PowerShell (`run_vixradar_matinal_claude.ps1` etc.) — não auditado neste passo | `api/v4.9.156.js:9817-9882`; primary-prompt fora do bundle | **Lacuna** — checar guard de injeção nos arquivos `scripts/*.md`/batch skills em auditoria futura |
| LLM02 Sensitive Info Disclosure | Nenhum `console.log` de payload bruto de chamada Claude encontrado nas linhas de request Anthropic; `ANTHROPIC_API_KEY` só via `env` | grep `console.log` + contexto de `chamarClaudeAnalise`/`chamarClaudeVerificador` | OK |
| LLM03 Supply Chain | Modelo fixado por ID explícito, sem alias flutuante: `claude-haiku-4-5-20251001`, `claude-sonnet-4-6` | `v4.9.156.js:6855,9728-9729` | OK |
| LLM05 Improper Output Handling | `validarSchemaEvento`/`aplicarRegrasNegocio` corrigidos no commit `a06cded` (FIX6/FIX7: fallback `evento.data`→`data_evento`) — reduz classe de erro que gerava `sem_eventos:true` silencioso por schema divergente | `v4.9.156.js:13298,13324` | OK (corrigido nesta semana) |
| LLM06 Excessive Agency | Newsletter e ações de maior impacto seguem atrás de verificação/telemetria; achado independente de nota 56 (`ALRT1`/`401 mata sessão`) não é excessive agency de IA, é bug de app | — | Sem achado novo |
| LLM07 System Prompt Leakage | Sem endpoint que ecoe prompt de sistema em erro (não testado ao vivo, só lido por código) | leitura de código | **Lacuna** — validar em runtime com payload malformado |
| LLM09 Misinformation | Risco central do domínio; mitigação é o verificador adversarial + amostragem 20% RELEVANTE + `TOKENEST1` (aberto, nota 55) pode degradar cobertura, não a acurácia por evento | Obsidian nota 49, 55 | Sem achado novo — mitigação já mapeada |
| LLM10 Unbounded Consumption | Timeout 55s + `AbortController` nas chamadas Anthropic do Worker; detecção de HTTP 429; **health já detecta "credit balance is too low"** via `_verificadorRealOk` (`v4.9.156.js:15130`) — mais robusto do que os scripts PowerShell locais, que **não** detectam essa string (gap P2 conhecido, nota 48/49, não é achado novo) | `v4.9.156.js:6859-6865,15130` | OK no Worker; gap conhecido permanece só nas rotinas locais |

## Padrões de runtime Workers (guia oficial Cloudflare 2026-02)

| Item | Achado | Evidência |
|---|---|---|
| `ctx.waitUntil` destructuring | Nenhuma ocorrência de `const { waitUntil } = ctx` — sem risco de "Illegal invocation" | grep `v4.9.156.js` |
| `ctx.waitUntil` usage | Só 2 call sites, ambos com `.catch()` anexado, sem sinal de trabalho >30s | `v4.9.156.js:15937,15942` |
| Floating promises | Checagem heurística (grep por `fetch(` solto) não achou padrão óbvio; `no-floating-promises` lint não é viável no bundle minificado — recomendação: rodar contra fonte não-bundlada se existir, senão registrar como lacuna de tooling | — |
| Estado global de módulo | Variáveis `var`/`let` de topo de arquivo encontradas são todas polyfill/runtime (Node compat shim do próprio Wrangler), não estado de aplicação mutável por request | grep primeiras ~900 linhas |
| `compatibility_date` | `2026-06-16`, ~1 mês desatualizado frente a hoje (2026-07-14) — não crítico, mas revisar no próximo deploy para pegar fixes de runtime recentes | `wrangler.toml:205` |

## Novos itens P3 (não estavam na nota 56)

| Sev | Achado | Ação |
|---|---|---|
| P3 | `compatibility_date` ~1 mês atrás da atual | Atualizar no próximo deploy de rotina (não precisa deploy isolado) |
| P3 (lacuna) | Prompt de análise primária (1º estágio, fora do Worker) não teve guard de prompt injection verificado nesta sessão | Auditar `scripts/*.md`/batch skills numa sessão futura com esse escopo |
| P3 (lacuna) | System prompt leakage não testado em runtime (só leitura de código) | Testar com payload malformado numa auditoria operacional |

## Conclusão

Nenhum achado novo de severidade P0/P1 nesta passada — o reforço de escopo (IA/LLM + runtime Workers) não encontrou risco não coberto pela nota 56 além dos 3 P3/lacunas acima. Valida que a skill atualizada é aplicável ao sistema atual sem ruído. Próxima auditoria geral deve reconferir os P0 abertos da nota 56 (TOKENEST1, PRNG1, RACEKV1, token CF) que continuam sem evidência de correção nesta sessão.
