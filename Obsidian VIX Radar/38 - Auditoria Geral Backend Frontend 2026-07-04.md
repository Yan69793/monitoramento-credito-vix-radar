# Auditoria Geral — VIX Radar (2026-07-04)

`/vix-radar-general-audit`. Escopo: repo/governança, backend Worker v4.9.145, frontend v201.69, segurança/perf/a11y estática. Complementa [[37 - Auditoria Geral Backend Frontend 2026-07-03]] (auditoria de ontem) — foco em validar os 3 P1 de rotina abertos ontem e cobrir camadas não testadas (multi-semana 1:1, secrets, XSS estático, arquivos novos do working tree).

## Veredito

Saudável, sem P0 em produção. `verificador_ok:false` no health público é esperado e documentado (saldo Anthropic insuficiente, A1 em `PENDENCIAS.md`). Os 3 P1 de rotina de ontem (cleanup apagando artefato do dia, schema `resultado` não documentado, parser de tokens quebrado) foram **corrigidos hoje no working tree** (ainda não commitados). Único achado novo de severidade real: **secret (`routine_key`) em texto claro staged para commit** em `scripts/azul_payload.json`, fora do `.gitignore` — ainda não vazou (nunca foi commitado), mas vazaria no próximo commit/push se não for removido do staging antes.

## Top riscos

| Sev | Área | Achado | Evidência | Ação |
|---|---|---|---|---|
| **P1** | Repo / secrets | `scripts/azul_payload.json` contém `routine_key` real em texto claro, staged (`git add`), sem match em `.gitignore` (que só cobre `*SECRET*`, `.env*`) | `git check-ignore -v` vazio; `git log --all -- scripts/azul_payload.json` vazio (nunca commitado) | `git restore --staged scripts/azul_payload.json` + adicionar padrão ao `.gitignore` antes do próximo commit. Não precisa rotacionar a chave (nunca entrou no histórico) — mas rotacionar se acabar sendo commitado antes da correção |
| P2 | Frontend / XSS defesa-em-profundidade | `app/index.html:3871` (`anomalia-card-desc`) interpola `${a.descricao}` em `innerHTML` sem `esc()`, inconsistente com o resto do arquivo (3 usos de `esc()` em outros pontos) | `app/index.html:3871`; confirmado no backend (`api/v4.9.145.js:10712,10723,10725,10737,10743`) que `descricao` de anomalias é **sempre string template server-side** (spread/volume/iliquidez/concentração, nunca texto externo/usuário) | Não é XSS ativo hoje (sem path de dado não confiável confirmado) — reclassificado de P1 (achado do subagente) para P2. Aplicar `esc()` mesmo assim, é fix de 1 linha e remove risco futuro caso o campo passe a aceitar texto externo |
| P2 | Frontend / governança de artefato | `app/index.prod.html` é snapshot órfão do frontend (v201.65, sem os 5 módulos admin), documentado incorretamente como `# Prod build` em `FIGMA-INTEGRATION.md:781` — já sinalizado como risco baixo na nota [[35 - Auditoria Completa 2026-07-02]] e não resolvido | diff mostra só divergência de `CACHE_VERSION` e ausência dos `<script src="admin/vr-admin-*.js">` | Mover para `app/_arquivo/` (ou remover) e corrigir/remover a linha em `FIGMA-INTEGRATION.md:781` |
| P2 | Backend / modelo | `VERIFICADOR_CONFIG.model_escalation` (linha 9584) ainda hardcoded `"claude-sonnet-4-5-20250929"`, usado em chamada real de escalation (linha 9962) — não confirmado se a Anthropic aceita esse ID como alias válido ou se falha | `api/v4.9.145.js:9584,9962,12863` | Testar 1 chamada real de escalation contra a API Anthropic; se inválido, atualizar para o model ID correto em uso (Sonnet 4.6) |
| P3 | Repo / hygiene | `express`/`openai` em `api/package.json` dependencies sem uso no bundle (Worker é edge-only, chamadas via `fetch` direto) | `api/package.json`; reconfirmado desde 2026-06-22 | Remover as 2 dependências |
| P3 | Backend / segurança | Comparação de senha admin (`admin_senha !== env.ADMIN_PASSWORD`, 54 call sites) não é constant-time | grep — zero `timingSafeEqual` no bundle | Risco teórico baixo (atrás de rate limiter, HTTPS); baixa prioridade |
| P3 | Frontend / perf | `app/deploy_zip/version.json.deployed_at` (18/06) desatualizado frente ao campo `version` (v201.69, mais recente) | `app/deploy_zip/version.json` | Regenerar `version.json` completo a cada deploy, não só o campo `version` |
| Backlog | Backend / dados | `FERIADOS_B3_2028` ausente em `ehDiaPregaoB3` (só 2026/2027) | `api/v4.9.145.js:10181,10215,10247` | Adicionar antes do fim de 2027 — sem urgência |

## Backend (v4.9.145)

- **Multi-semana 1:1 fechado** (lacuna de ontem): os 5 endpoints do CLAUDE.md (`op=state` L14634, `op=ews` L12461, `briefing_executivo` L14250, `historico_emissor` L14277, `comparar` L14389) usam `carregarEstadoMultiSemana(env,5)` — sem exceção. As demais 18 ocorrências com N=2/3 pertencem a rotinas internas de ingestão/diagnóstico, fora do escopo da regra.
- `receber_analise` (linha atual **15305**, não mais ~15244 — bundle cresceu) segue rejeitando com HTTP 400 quando `resultado` não é objeto, antes de qualquer persistência — não há caminho para `sem_eventos:true` silencioso por erro de schema.
- `RADAR_USAGE_EVENTS`: binding declarado e usado ativamente (20+ `writeDataPoint`, alerta explícito se ausente). Fail-open do rate limiter (fix v4.9.112) intacto, com `console.warn` nos 3 cenários de bypass.
- Nenhum fallback inseguro (`|| "valor"`) em `JWT_SECRET`/`ANTHROPIC_API_KEY`/`ROUTINE_API_KEY`/`OPENROUTER_API_KEY`.

## Frontend (v201.69)

- `app/index.html` == `app/deploy_zip/index.html` == produção, sem drift de conteúdo. `CACHE_VERSION` alinhado.
- F1 (senha admin `sessionStorage`) reconfirmado sem regressão, fonte e deploy_zip idênticos.
- Regra CSS `<strong>` global respeitada (sem `color`).
- Headers de auth (`_authHeaders`/`_authHeadersGet`) presentes e propagados corretamente em todas as chamadas autenticadas verificadas.
- Performance/a11y: revisão estática apenas (sem browser). HTML monolítico ~672KB, 27 scripts inline, Google Fonts com `display=swap`. A11y: presença de `aria-`/`role`/`tabindex` confirmada mas escassa frente ao volume de UI — lacuna para passe com browser/axe.

## Rotina (fixes de ontem, validados hoje)

Os 3 P1 da nota 37 foram corrigidos no working tree (não commitados ainda):

1. `cleanup-rotina-artifacts.ps1` — guarda estrutural por `LastWriteTime.Date` bloqueia remoção de qualquer item do dia corrente, inclusive diretórios com mtime antigo mas conteúdo novo. **RESOLVIDO.**
2. Schema `receber_analise` — solução mais robusta que só documentar: `run_vixradar_noturno_claude.ps1` (`New-BatchPrompt`/`Submit-Analise`) agora monta o payload centralizado no orquestrador; subagente só emite `RESULTADO|empresa|json`. **RESOLVIDO.**
3. Parser de tokens — `Parse-TokensFromOutput` (regex sobre texto livre) removido; substituído por parse de `--output-format json` lendo `usage.{input,output,cache_creation_input,cache_read_input}_tokens` nativo do CLI. Default `-1` explícito se parse falhar (nunca reporta 0 falso). **RESOLVIDO.**

Nota: `.claude/skills/vix-radar-audit/scripts/audit-routine-staleness.ps1` (novo) NÃO é o watchdog de heartbeat (P-WD) — é uma ferramenta separada de staleness de dados por emissor (via `listar_plano_rotina`). **P-WD permanece aberto.**

## Próximos passos

1. **P1** — Despachar `scripts/azul_payload.json` do staging + `.gitignore` antes do próximo commit.
2. **P2** — Aplicar `esc()` em `anomalia-card-desc` (`app/index.html:3871`).
3. **P2** — Mover/remover `app/index.prod.html`; corrigir `FIGMA-INTEGRATION.md:781`.
4. **P2** — Testar `model_escalation` (`claude-sonnet-4-5-20250929`) contra API Anthropic real.
5. **P3** — Remover `express`/`openai` de `api/package.json`.
6. Após 1-5: commitar os fixes de rotina (cleanup, schema, parser) já validados nesta auditoria.

## Lacunas

- Performance/a11y não medidas com browser real (Lighthouse/axe) — só revisão estática.
- P-WD (watchdog heartbeat `stale_count:1`) não investigado nesta rodada.
- Endpoints admin autenticados (`admin_health_check`, `admin_verificar_evento`) não testados (fora do escopo readonly sem senha).

## Addendum — verificação do painel de notícias (mesma sessão, login autenticado via Playwright)

Login real no dashboard (`vixradar.com`, usuário admin) autorizado explicitamente pelo operador nesta sessão. Feed cronológico inspecionado + `fetch('op=state')` direto para isolar se a corrupção é de renderização (frontend) ou de dado armazenado (backend/KV).

**Atualização:** sem eventos novos após **02/07** (Engie Brasil Energia, AGE incorporação Jirau) — 2 dias sem novo evento no momento da checagem (04/07, sábado). **Não é bug novo** — consistente com `verificador_ok:false` (A1, saldo Anthropic insuficiente) já documentado; sem 03/07 no feed apesar de dia útil.

**3 defeitos confirmados nos dados armazenados (não no frontend):**

| Sev | Achado | Evidência |
|---|---|---|
| P2 | Valores monetários truncados em parte dos registros: padrão `R$<dígito>` vira `R,<dígito>`/`Rbi` em alguns eventos (ex.: "R$1,24bi"→"R,24bi", "(~R$1bi)"→"(~R)", "R$100mi"→"R00mi"), mas **intacto em outros registros da mesma dezena de dias** (293 ocorrências corretas de `R$<dígito>` vs 158 corrompidas na mesma resposta) — inconsistência confirma defeito **pontual de ingestão** (lote/agente específico), não falha sistêmica de render ou do Worker | `fetch(op=state)` bruto contém literalmente `"R,24bi"` sem o `"R$1,24"` correspondente; mesma informação (resgate Vibra VBBR14 ~R$779mi) aparece correta em um evento (04/jun) e corrompida em outro (17/jun) |
| P2 | Mojibake (UTF-8 duplamente codificado) em subconjunto de eventos mais antigos: "Kora Sa�de", "proje��o", "participa��o", "est�vel" etc. | Confirmado no JSON bruto (`Sa�de` presente), não é artefato de exibição. Mitigação prospectiva já entrou hoje (ver corpo desta nota — normalização de acentuação em `noturno-batch-*.md`), mas registros históricos ficam corrompidos até saírem da janela de 30 dias ou serem reprocessados |
| P3 | Campo `fonte` grava literalmente a string `"nao_identificada"` quando não há URL de origem, virando link quebrado (`href="nao_identificada"`) no card do evento | Confirmado no JSON bruto (`"nao_identificada"` presente) e no DOM renderizado (`link "fonte" → /url: nao_identificada`) em eventos de Aegea (26/jun), Kora Saúde (23/jun, 17/jun, 05/jun) |

**Causa raiz não aprofundada** (fora do escopo desta verificação): qual execução específica do batch matinal/noturno gerou os registros corrompidos — precisaria cruzar `testing/noturno_*.json` por data. Recomendado como próximo passo se o operador quiser corrigir os registros já persistidos (reprocessamento) além da prevenção prospectiva.

**Próximos passos adicionais:**
1. **P2** — Ocultar o link "fonte" no frontend quando o valor for `"nao_identificada"` (ou o Worker não deveria gravar esse literal — preferir omitir o campo).
2. **P2** — Investigar por que alguns registros de um mesmo período têm `R$<dígito>` íntegro e outros corrompido (mesmo lote/agente? script de submissão?).
3. **P3** — Avaliar reprocessamento dos eventos históricos com mojibake, ou aceitar que saem da janela de 30 dias naturalmente.
