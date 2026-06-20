# PENDENCIAS.md — VIX Radar

**Gerado em:** 2026-06-10 | **Auditoria:** repeat-run (baseline: 2026-06-03, P01–P22)
**Base analisada:** Worker v4.9.102 (prod snapshot 15.635 linhas) + frontend v201.45 + CI + wrangler.toml + screenshots Playwright (desktop + mobile)
**Confiança nas linhas:** BAIXA para repo `api/v4.9.102.js` (artefato de build antigo, máquina `szuch`); ALTA para `docs/auditorias/prod-worker-2026-06-10.js` (snapshot live via Cloudflare MCP, 2026-06-10T21:24Z).

---

## Síntese executiva

1. **OpenRouter sem créditos (402) desde pelo menos 2026-06-10.** O provider principal da cascade está inoperante. O sistema está rodando exclusivamente em `claude-haiku-4-5-20251001` via Anthropic API. Qualidade e custo por análise estão alterados.
2. **CI 100% quebrado.** `.github/workflows/canonical-test.yml` faz POST anônimo que retorna 401 (autenticação obrigatória desde v4.9.x) e usa `EXPECTED_WORKER="4.9.100"` (prod é v4.9.102). Toda execução falha silenciosamente há semanas.
3. **Cron `0 2 * * *` roda pipeline noturno completo (100 emissores + newsletter) sem propósito documentado**, 2,5h após o cron principal `30 21 * * *`. Dobra o custo de API e o risco de duplicação de eventos.
4. **Afirmação do operador sobre migração para Opus é FALSA.** Cascade continua ativo com haiku + sonar. Anthropic API está integrada mas como tier 2 da cascade (haiku), não como provider único.
5. **Tarefa agendada `radar-analise-diaria-19h`** referenciada pelo operador **não existe** no ambiente — `mcp__scheduled-tasks__list_scheduled_tasks` retornou zero tasks.
6. **Worker em produção diverge do repo** (mesma versão v4.9.102, mas builds diferentes: prod foi rebuilt na máquina `User` com wrangler mais novo; repo tem o bundle da máquina `szuch`). Sourcemap no repo aponta para versão inexistente (`v4.9.99.js.map`).
7. **`CRITICIDADE_SETOR` usa 6 chaves de setor que não existem no `EMISSORES_MAP`**, degradando materialidade para 48 de 103 emissores — o multiplicador de enriquecimento cai para fallback 0.7 em vez do valor calibrado.
8. **METRICAS_CURADAS hardcodado** com dados de 4T25 (dez/2025) para 101 empresas. Sem pipeline de atualização, todo KPI exibido ao usuário tem 6+ meses de defasagem.
9. **ADMIN_EMAIL hardcoded** no bundle de produção (`szuchmacheryan@gmail.com`); qualquer pessoa com acesso ao repo conhece o vetor de acesso privilegiado.
10. ~~**CLAUDE.md do projeto tem paths incorretos**~~ **RESOLVIDO 2026-06-19** — `CLAUDE.md` enxuto (5 KB): paths `api/`/`app/`, vault `E:\Diretorio\Claude\...`, teste GET `/` (POST anônimo = 401 documentado). Histórico em `docs/archived/CLAUDE-HISTORICO.md`; `AGENTS.md` virou ponteiro.

---

## Tabela de afirmações do operador

| Afirmação | Evidência | Veredito |
|-----------|-----------|----------|
| Cascade substituído por **Claude Opus** via Anthropic API | `chamarClaudeAnalise` usa `claude-haiku-4-5-20251001`; `action=teste` confirma cascade tiers; sem `claude-opus` em nenhum arquivo | **FALSO** — é Haiku (tier 2 da cascade), não Opus |
| Guard de **8s** causa fallback nas LLMs | Timeout 8s é só `fetch` genérico de HTML (linha ~9160 repo); LLMs têm 55s próprios | **FALSO** — 8s não afeta LLMs |
| Tarefa `radar-analise-diaria-19h` com senha errada | `mcp__scheduled-tasks__list_scheduled_tasks` → 0 tasks | **NÃO ENCONTRADA** — não existe neste ambiente |
| Cron boletim `0 21 * * 1-5` (dias úteis) | `wrangler.toml` linhas 61-66: `30 21 * * *` (diário) | **INCORRETO** — cron é diário, não só dias úteis |
| POST / anônimo funciona (sem auth) | `POST /` → HTTP 401 `{"ok":false,"erro":"Autenticação necessária."}` | **FALSO** — requer JWT desde v4.9.x |
| WAF exige `User-Agent` de navegador (403 sem) | `GET /` com e sem UA → HTTP 200 em ambos | **FALSO** — sem bloqueio por UA |

---

## Modelo mental da arquitetura

O VIX Radar é composto por dois artefatos: **frontend monolítico** (`app/index.html`, v201.45, 5.157 linhas) no Cloudflare Pages (`vixradar.com`), e **Worker Cloudflare** (`radar-credito-api`, v4.9.102, 15.635 linhas no bundle de produção) em `api.vixradar.com` (custom domain sobre `*.workers.dev`).

O Worker é o núcleo: recebe POST autenticado com `{empresa, setor}`, executa cascade AI em 9 rodadas (OpenRouter tiers → Claude Haiku Anthropic → verificador Claude Sonnet), classifica eventos como CRITICO/RELEVANTE/ECO/RUIDO, persiste no KV particionado por semana ISO (`radar:estado:YYYY-WNN`). Quatro crons: matinal dias úteis (top-30 EWS), noturno diário (100 emissores), watchdog (22h BRT), e 4º trigger sem propósito documentado que replica o pipeline noturno.

O estado acumula por semanas. Endpoints de leitura usam `carregarEstadoMultiSemana(env, 5)` (correto). Auth: JWT HMAC-SHA256 12h, sem refresh token. Admin: `admin_senha` contra `env.ADMIN_PASSWORD`. Multi-tenant funcional com `vix_core` e `mirabaud`. Rate limiting via Durable Object (SQLite-backed, atômico).

O bundle não é código fonte hand-authored — é artefato gerado por `wrangler build`. A versão no repo é de build anterior (máquina `szuch`); a produção foi rebuilt em máquina diferente (`User`). Isso explica a divergência de 40KB entre o repo e o snapshot de produção.

**Cascade atual (OpenRouter 402 inoperante):**
```
R1: perplexity/sonar-pro (OpenRouter) → 402 → skip
R2: perplexity/sonar (OpenRouter)     → 402 → skip
...
Rk: claude-haiku-analise (Anthropic)  → OK
Verificador: claude-sonnet-4-5 (Anthropic) → OK
```

---

## Tabela de achados

| ID | Categoria | Arquivo:Linha (prod snapshot) | Severidade | Esforço | Dimensão | Status | Descrição | Recomendação |
|----|-----------|-------------------------------|------------|---------|----------|--------|-----------|--------------|
| P05* | CI / Observabilidade | `.github/workflows/canonical-test.yml:24,56` | **Crítico** | P | 1,5 | AGRAVADO | CI quebrado em duas frentes: (1) POST anônimo linha 24 → 401 (auth obrigatória desde v4.9.x); (2) `EXPECTED_WORKER="4.9.100"` linha 56 (prod é v4.9.102). Job falha 100% toda execução a cada 6h. | Reescrever o step de teste: remover POST anônimo ou autenticar; atualizar `EXPECTED_WORKER="4.9.102"`. |
| N01 | Disponibilidade / Cascade | prod:8344; `action=teste` | **Crítico** | — | 17 | NOVO | OpenRouter retornou HTTP 402 (sem créditos) em todos os probes de 2026-06-10. Todos os tiers OpenRouter (sonar-pro, sonar, gemma-4) estão inoperantes. Sistema rodando exclusivamente em `claude-haiku-4-5-20251001` via Anthropic API. | Recarregar créditos OpenRouter OU elevar haiku para tier primário e adicionar Sonnet como fallback. Implementar alerta automático quando provider retorna 402 recorrentemente. |
| P15* | Cron / Custo | `api/wrangler.toml:61-66`; prod:15256-15260 | **Crítico** | P | 20 | AGRAVADO | 4º cron `0 2 * * *` (23h BRT) cai no handler do pipeline noturno completo (100 emissores + newsletter + healthcheck). Roda 2h30 após o noturno principal (`30 21 * * *`). Dobra custo de API, duplica potencialmente eventos no KV. | Documentar propósito ou remover do `[triggers]`. Se for watchdog tardio, adicionar handler explícito que só verifica estado, sem cascade AI. |
| P08 | Decadência / Bundle | prod:primeira linha; `api/v4.9.102.js:1` | Alto | G | 8 | ABERTO | Bundle tem `__name` × 9 variantes por função (`__name`, `__name2`, ..., `__name22222222`). Bundle de produção: 717KB / 15.635 linhas. Causa: múltiplas passadas de bundling. Cold start mais lento; deploy mais lento. | Mover para pipeline de build com uma única passada. Opção: `wrangler deploy` direto do source (não commitar bundle). |
| N02 | Drift / Artefato | `api/v4.9.102.js:5` vs prod:5 | Alto | P | 1,20 | NOVO | Bundle no repo foi gerado na máquina `szuch` (path `C:/Users/szuch/.../wrangler/...`). Produção tem bundle gerado na máquina `User` (path `Users/User/AppData/Local/npm-cache/_npx/.../unenv/...`). Mesma versão (v4.9.102) mas artefatos diferentes. Sourcemap repo: `v4.9.99.js.map` (errado); prod: `v4.9.102.js.map` (correto). | Substituir `api/v4.9.102.js` pelo snapshot de prod (`docs/auditorias/prod-worker-2026-06-10.js`). A partir daqui, sempre commitar o bundle após `wrangler deploy`. |
| P11 | Segurança | prod:4428 | Alto | P | 11 | ABERTO | `var ADMIN_EMAIL = "szuchmacheryan@gmail.com"` hardcoded no bundle deployado e versionado no repo. Qualquer pessoa com acesso ao repo sabe o email do admin. | Mover para `env.ADMIN_EMAIL`. Remover do bundle. |
| N03 | Segurança / Dados | `app/index.html:~3407` (legacy render) | Alto | P | 19 | NOVO | Legacy render usa `innerHTML` com nomes de empresas sem escaping. Se qualquer evento da cascade AI retornar `titulo` ou `classificacao` com `<script>` ou evento HTML, o XSS é injetado no DOM diretamente. A nova camada `_v201Esc` usa `textContent` (correto), mas o `anomalias-pre` e renders legados não foram migrados. | Substituir todos os `innerHTML = valor_externo` por `textContent` ou `sanitize()` nos renders legados. |
| P10 | Segurança | prod:~12800 (8 call sites) | Alto | P | — | ABERTO (AMPLIADO) | `admin_senha !== env2222.ADMIN_PASSWORD` é comparação de string ordinária em 8 call sites. Timing attacks são improváveis (latência de edge >> diferença de timing), mas violam padrão de segurança mínimo. | Substituir por `crypto.subtle.timingSafeEqual(new TextEncoder().encode(a), new TextEncoder().encode(b))` nos 8 pontos. |
| N04 | Observabilidade | prod:14442 | Médio | P | — | NOVO | `resultado.worker_version = "v4.8.5"` hardcoded no `executarHealthCheckDiario`. Health check retorna versão errada (prod é v4.9.102). Admin que verifica saúde do sistema vê dado incorreto. | Substituir por `resultado.worker_version = WORKER_VERSAO`. Uma linha. |
| N05 | Cron / Lógica | prod:15256; `api/wrangler.toml:60-66` | Médio | P | 20 | NOVO | Handler `ehAgenda` no `scheduled()` ativado quando `cronHora === 4 && cronMinuto === 0` (UTC). Nenhum cron `0 4 * * *` está declarado no `[triggers]`. O handler existe mas nunca será chamado — código morto ou trigger ausente. | Decidir: se `ehAgenda` é funcionalidade planejada, adicionar `"0 4 * * *"` ao `[triggers]`. Se for dead code, remover o handler. |
| N06 | Qualidade / Enriquecimento | prod:~12950; `api/v4.9.102.js:11951-11965` | Médio | P | 17,22 | NOVO | `CRITICIDADE_SETOR` usa 13 chaves de setor. Pelo menos 6 não batem com as chaves reais do `EMISSORES_MAP` (ex: `"Energia Elétrica"` vs `"Energia"`, `"Financeiro"` vs `"Bancos"`). 48 de 103 emissores caem no fallback 0.7 em vez do valor calibrado. Materialidade calculada incorretamente para ~47% do universo. | Alinhar chaves de `CRITICIDADE_SETOR` com as chaves exatas do `EMISSORES_MAP`. Adicionar teste de consistência. |
| N07 | Dados / Frontend | `app/index.html:~3406` | Médio | P | 22 | NOVO | `ARQUIVO_PRE` contém 2 eventos com `data_evento` anterior a 90 dias: Raízen (`2026-03-11`, 91 dias) e GPA (`2026-03-10`, 92 dias). Ficam visíveis no PDF mas fora do dashboard (filtro `dentroJanela`). Dado obsoleto apresentado em contexto premium. | Remover ou arquivar eventos com mais de 90 dias. Ou documentar explicitamente que ARQUIVO_PRE é memória histórica sem TTL. |
| N08 | Qualidade / Dados | `app/index.html:~3406` | Médio | P | 22 | NOVO | `METRICAS_CURADAS` tem 101 empresas com KPIs todos marcados como `"CVM · 4T25"` (dados de dez/2025, hoje com 6 meses de defasagem). Inconsistência em Aegea: nota interna diverge dos campos publicados. Nenhum pipeline de atualização existe. | Definir ciclo trimestral de atualização. Adicionar `data_referencia` por empresa (não global) para o usuário saber quando foi atualizado. |
| N09 | CLAUDE.md / Drift doc | `CLAUDE.md:projeto` | Médio | P | — | **RESOLVIDO 2026-06-19** | CLAUDE.md reescrito (62 KB → 5 KB): paths `api/`/`app/`, vault correto, teste GET `/`, histórico arquivado, AGENTS.md deduplicado. | — |
| P12 | Tratamento de erro | prod:14447-14450 | Médio | P | — | ABERTO | `__fixCorsResp` tem `catch(e) {}` vazio. Se a lógica de correção de CORS falhar, a exceção é silenciada e o response sai sem `Access-Control-Allow-Origin`. Diagnóstico impossível em produção. | Adicionar `console.error("[fixCors]", e)` no catch. |
| P13 | Débito técnico / KV | prod:~14100 (`handleHistoricoEmissor`) | Médio | P | — | ABERTO | `handleHistoricoEmissor` usa `RADAR_KV.list({prefix: "comentario:..."})` para leitura. `list()` tem eventual consistency (até 60s de lag). Mesmo padrão que causou bug em favoritos (v4.7.1). Comentário recém-adicionado pode não aparecer por ~60s. | Migrar para doc único `comentarios:{empresa}` (JSON array), padrão já estabelecido nos favoritos. |
| P18 | Decadência / Repo | `api/` (diretório) | Médio | G | 8 | ABERTO | Diretório `api/` acumula múltiplos bundles `.js` sem política de retenção (histórico visível no git). Bloat de repo e `git clone` lento. Fora do git: `archive/`, `docs/`, `research/`, `testing/`, `vixradar/` não rastreados. | Definir política: manter últimas 3 versões + versão em produção. Tags git para versões anteriores. |
| P22 | CORS / Consistência | prod:~7200 (`handleEmailAcao`) | Médio | P | — | ABERTO | `handleEmailAcao` retorna response HTML com `...CORS` (objeto estático com apex hardcoded) em vez de `...corsHeaders(request)`. Inconsistência com o fix do v4.9.102. | Substituir por `...corsHeaders(request)`. |
| N10 | Qualidade / Cascade | prod:~7548 (`chamarClaudeAnalise`) | Médio | P | 17 | NOVO | `chamarClaudeAnalise` usa model `claude-haiku-4-5-20251001` com tool `web_search_20250305` (max_uses: 10). Verifier usa `claude-sonnet-4-5-20250929`. Ambos são modelos de geração anterior. Modelos mais recentes disponíveis: `claude-haiku-4-5`, `claude-sonnet-4-6`. | Atualizar model IDs para versões correntes. Testar custo/qualidade antes de promover Sonnet para tier primário. |
| N11 | Qualidade / Cascade | prod:~7700 (`chamarPerplexity` legacy) | Baixo | P | 17 | NOVO | `chamarPerplexity` legacy (chamada direta, não via OpenRouter) ainda presente. Gemini foi removido em v4.9.71. Não está referenciado em nenhum tier ativo da cascade. Código morto. | Remover função e todos os call sites inivos. |
| P07 | Drift / Artefato | `api/v4.9.102.js:14431` | Baixo | P | — | PARCIAL | Repo tem `//# sourceMappingURL=v4.9.99.js.map` (versão errada). Produção tem `//# sourceMappingURL=v4.9.102.js.map` (correto). O `.map` em si não existe em nenhum dos dois — debug com source maps inoperante de qualquer forma. | Resolvido em prod. Para o repo: resolver ao substituir o bundle (ver N02). |
| P19 | Segurança / Config | `api/wrangler.toml:17,22` | Baixo | — | — | ABERTO | `account_id = "7ac79fb1030e4e81115ef33c21a9b070"` e KV `id = "c6805b8d8a7b468e9f854ab4f91fb93a"` hardcoded e versionados. Não são secrets (sem token não ativam nada), mas revelam infra identifiers. Adicionalmente, CLAUDE.md cita KV id diferente (`1af17e5e...`) — evidência de namespaces múltiplos ou doc desatualizado. | Mover para `.env.production` não versionado ou variável CI. Verificar qual KV id é o correto em produção. |
| P20 | Débito técnico | `api/package.json:3-4` | Baixo | P | — | ABERTO | `express ^5.2.1` e `openai ^6.33.0` em `dependencies`. Nenhum importado pelo Worker (usa CF fetch API). | Remover. Executar `npm audit` antes de qualquer próximo deploy. |
| N12 | Qualidade / Calendário | `api/v4.9.102.js:~9238` | Baixo | P | — | NOVO | `FERIADOS_B3_2028` não existe. `ehDiaPregaoB3` só cobre 2026 e 2027. Em 01/01/2028, feriados serão ignorados silenciosamente. | Adicionar `FERIADOS_B3_2028` antes do final de 2027. |
| N13 | Qualidade / Rate Limit | prod:~9400 | Baixo | — | — | NOVO | Headers `X-RateLimit-*` só são injetados nas respostas 429, não nas 200. Frontend não consegue mostrar "X de 25 pulsos restantes" sem chamar `rl_inspect` separado. | `rl_inspect` resolve por demanda. Se quiser UX inline, propagar headers nos 200 também. |
| P15-B | Cron / Watchdog | `api/wrangler.toml:64` (cron `0 1 * * *`) | Baixo | — | — | ABERTO | Cron watchdog `0 1 * * *` (22h BRT) não tem descrição de propósito no wrangler.toml além do comentário "watchdog diário". Função alvo não identificada no código (cai no handler noturno se `ehWatchdog` não for atendido). | Documentar propósito explícito no comentário do toml. |

---

## Top 5 prioridades absolutas

### 1. OpenRouter 402 — N01

**Sistema de cascade parcialmente inoperante.** OpenRouter (`sonar-pro`, `sonar`, `gemma-4`) retornando 402 em todos os probes. Todas as análises estão sendo feitas exclusivamente por `claude-haiku-4-5-20251001`. Custo por análise e qualidade diferentes do que foi calibrado.

```bash
# Confirmar status atual (1x, não dispara análise real):
curl -s "https://radar-credito-api.prospects-intel.workers.dev?action=teste" \
  -H "User-Agent: Mozilla/5.0" | python3 -m json.tool
# Esperado após recarga de créditos: openrouter status 200
```

**Ação:** Verificar painel OpenRouter e recarregar créditos. OU elevar haiku para tier primário e adicionar Sonnet como fallback de qualidade.

---

### 2. CI 100% quebrado — P05*

**Nenhum alerta de drift funciona.** Job falha em toda execução há semanas sem que ninguém perceba. O único sistema de detecção automática de divergência entre repo e produção está morto.

```yaml
# .github/workflows/canonical-test.yml — diff sketch

# REMOVER o step que faz POST anônimo (linha ~24):
- name: Test worker endpoint          # ← REMOVER ou autenticar
  run: |
    curl -f -X POST $WORKER_URL ...   # ← retorna 401, quebra job

# ATUALIZAR versão esperada (linha 56):
  EXPECTED_WORKER: "4.9.102"          # era "4.9.100"
  #                  ↑
  # Atualizar a cada deploy do Worker
```

---

### 3. Cron duplo noturno — P15*

**Custo dobrado e risco de eventos duplicados.** Cron `0 2 * * *` roda 2h30 depois do noturno principal `30 21 * * *`, executando o pipeline completo (100 emissores + newsletter + sync ANBIMA + health check). Se não houver propósito documentado, é pure waste.

```js
// api/v4.9.102.js — handler scheduled() — diff sketch
// Linha ~15256 no prod snapshot

// ANTES: cron 0 2 cai no else (pipeline noturno completo)
if (ehMatinal) { ... }
else if (ehWatchdog) { ... }
else if (ehAgenda) { ... }   // nunca ativado (cron 0 4 ausente)
else { /* 21h30 E 02h00 caem aqui! */ await executarCronNoturno(env) }

// DEPOIS (opção A — documentar):
else if (cronHora === 2 && cronMinuto === 0) {
  // 2º cron noturno: propósito X (healthcheck only, sem cascade)
  await executarHealthCheckDiario(env)
}
// DEPOIS (opção B — remover do wrangler.toml se for redundante):
// [triggers] crons = ["30 15 * * 1-5", "30 21 * * *", "0 1 * * *"]
//                                                                  ↑ remover "0 2 * * *"
```

---

### 4. CRITICIDADE_SETOR mismatch — N06

**~47% do universo com materialidade errada.** 6 das 13 chaves de setor no `CRITICIDADE_SETOR` não batem com as chaves reais do `EMISSORES_MAP`. Resultado: `enriquecerEvento()` usa fallback 0.7 para empresas como Energisa, Sabesp, Petrobras, Embraer — todos setores com peso calibrado diferente.

```js
// prod-worker-2026-06-10.js — diff sketch CRITICIDADE_SETOR
var CRITICIDADE_SETOR = {
  // ERRADO → CORRETO (chave real no EMISSORES_MAP)
  "Energia Elétrica": 0.9,   // key real: "Energia"
  "Saneamento": 0.85,        // key real: "Saneamento Básico"
  "Financeiro": 0.95,        // key real: "Bancos"
  "Petróleo e Gás": 0.8,     // key real: "Petróleo & Gás"
  "Telecomunicações": 0.7,   // key real: "Telecom"
  "Transporte": 0.75,        // key real: "Transporte & Logística"
  // ... restantes: verificar chaves exatas antes de corrigir
}
// Adicionar teste: Object.keys(CRITICIDADE_SETOR).forEach(k =>
//   console.assert(Object.values(EMISSORES_MAP).includes(k), "setor ausente: "+k))
```

---

### 5. ADMIN_EMAIL hardcoded — P11 (N09 resolvido 2026-06-19)

**N09 fechado:** CLAUDE.md enxuto com paths corretos. **P11 permanece:** ADMIN_EMAIL hardcoded expõe vetor de ataque em repo público.

```js
// Worker — diff sketch P11
// var ADMIN_EMAIL = "szuchmacheryan@gmail.com";   // ← REMOVER
var ADMIN_EMAIL = env2222.ADMIN_EMAIL ?? "szuchmacheryan@gmail.com"; // fallback seguro
// Adicionar ADMIN_EMAIL como secret no Cloudflare Dashboard
```

```markdown
<!-- CLAUDE.md — diff sketch N09 -->
<!-- LINHA ATUAL: teste padrão POST anônimo esperando HTTP 200 -->
curl -s -X POST https://radar-credito-api.prospects-intel.workers.dev \
  -H "Content-Type: application/json" \
  -d '{"empresa":"Auren Energia","setor":"Energia Elétrica"}' ...
<!-- CORRIGIR: POST anônimo retorna 401 desde v4.9.x -->
<!-- Substituir por: GET / health check (não precisa de auth) -->
curl -s https://radar-credito-api.prospects-intel.workers.dev | python3 -m json.tool
```

---

## Ganhos rápidos (< 30 min cada)

| # | Achado | Ação | Arquivo |
|---|--------|------|---------|
| 1 | N04 — `worker_version = "v4.8.5"` | Substituir por `WORKER_VERSAO` | prod:14442 |
| 2 | P20 — express/openai não usados | `npm uninstall express openai` | `api/package.json` |
| 3 | P05* — `EXPECTED_WORKER` desatualizado | Atualizar para `"4.9.102"` | `.github/workflows/canonical-test.yml:56` |
| 4 | P12 — `catch(e){}` vazio | Adicionar `console.error` | prod:14447 |
| 5 | ~~N09 — CLAUDE.md paths errados~~ | **FEITO 2026-06-19** | `CLAUDE.md` |
| 6 | N07 — ARQUIVO_PRE com eventos expirados | Remover Raízen e GPA | `app/index.html:~3406` |

---

## Parece ruim mas está OK

1. **`persistirResultadoCompartilhado` lógica complexa (prod:~7136-7223).** A função só sobrescreve o estado KV com `sem_eventos:true` quando coverage ≥8/9 E o estado anterior não tem eventos válidos. Parece overengineered, mas protege corretamente o histórico de eventos durante semanas novas (segunda-feira, KV ainda vazio). Está correto.

2. **Timeouts LLM de 55s.** O timeout de 8s é só para fetches genéricos de HTML. Todos os call sites de LLM (OpenRouter, Anthropic, Perplexity) usam 55s explicitamente. Não causa os fallbacks mencionados pelo operador. Correto por design para modelos de análise pesada.

3. **`__name` × 9 por função.** É artefato do bundler wrangler em múltiplas passadas, não bug do código fonte. O código funciona corretamente. O problema é de build (P08), não de lógica.

4. **`rl_inspect` endpoint público sem auth.** Retorna apenas dados do próprio requisitante (resolvido via JWT ou IP). Não expõe dados de outros usuários. O design de "cada um só vê o próprio rate limit" é correto.

5. **Bundles versionados em `api/`.** Parece bloat, mas serve como rastro auditável de versões deployadas. Permite recuperação rápida em caso de rollback sem dependência do histórico Cloudflare. Política de retenção (3 últimas) é suficiente — o problema é a ausência dessa política (P18), não a existência dos arquivos.

6. **Multi-tenant `ews_filter` habilitado para Mirabaud mas sem implementação visível no frontend.** A feature está no `DEFAULT_TENANTS.mirabaud.features` mas o frontend não a renderiza diferente. Não é um bug — é uma feature gate sem implementação frontend ainda. Não quebra nada para nenhum tenant.

7. **`workers_dev: true` no wrangler.toml.** Mantém o domínio `*.workers.dev` ativo em paralelo ao custom domain. Necessário para o CI validar a URL sem depender do DNS do custom domain. Intencional.

---

## Perguntas abertas (requerem decisão do operador)

1. **Cron `0 2 * * *` (P15*):** qual é o propósito? Manter com handler específico ou remover?
2. **`ehAgenda` (N05):** a funcionalidade de "agenda" está planejada? Se sim, qual cron `0 4 * * *` deve disparar?
3. **OpenRouter créditos (N01):** recarregar créditos ou migrar cascade para Anthropic-only com Haiku → Sonnet?
4. **Modelo ID (N10):** atualizar para `claude-haiku-4-5` e `claude-sonnet-4-6` agora, ou aguardar testes?
5. **METRICAS_CURADAS (N08):** pipeline trimestral de atualização manual ou automatizar via KV?
6. **`api/v4.9.102.js` (N02):** substituir pelo snapshot de prod agora? Ou aguardar próximo deploy e commitar então?
7. **`ADMIN_EMAIL` (P11):** confirmar se `szuchmacheryan@gmail.com` pode ser removido do repo ou se há objeção ao log histórico.

---

## Oportunidades de Melhoria

### Técnicas (impacto × esforço)

| # | Melhoria | Impacto | Esforço | Componente |
|---|----------|---------|---------|------------|
| T1 | **Pipeline de build CI/CD:** `wrangler deploy` direto do source no GitHub Actions, sem commitar bundle. Elimina drift de artefato e o risco de bundle de máquina errada. | Alto | M | Worker |
| T2 | **Refresh token JWT:** 12h de expiração sem refresh força logout. Adicionar endpoint `action=refresh` que valida JWT próximo do vencimento e emite novo. | Alto | M | Worker + Frontend |
| T3 | **CSP em report-only:** adicionar `Content-Security-Policy-Report-Only` no `_headers` com endpoint de report para mapear inline scripts antes de implementar CSP hard. Caminho para fechar o maior gap de segurança sem quebrar o app. | Alto | P | Pages (_headers) |
| T4 | **Alerta automático de créditos de provider:** quando provider retorna 402 em 3 probes consecutivos, enviar WhatsApp admin. Evita o cenário de sistema degradado por dias sem que o operador perceba. | Alto | P | Worker |
| T5 | **KV backup semanal:** snapshot dos prefixos críticos (`radar:estado:*`, `user:*`) para R2 ou arquivo externo. Disaster recovery hoje depende exclusivamente do KV sem backup. | Médio | M | Worker (cron) |
| T6 | **Constante-time comparison para admin_senha:** substituir `!==` por `crypto.subtle.timingSafeEqual` nos 8 call sites. Uma refatoração de helper que resolve todos de uma vez. | Médio | P | Worker |
| T7 | **Rate limit headers em respostas 200:** propagar `X-RateLimit-Remaining` nas respostas OK para o frontend mostrar feedback em tempo real sem call extra ao `rl_inspect`. | Baixo | M | Worker |
| T8 | **Return-Path/bounce handling:** configurar SMTP Return-Path e processar bounces via webhook Resend. Hoje emails bounced são silenciosos — lista de usuários pode ter endereços inválidos acumulando. | Baixo | P | Worker + Resend |
| T9 | **Remover Gemini + chamarPerplexity legado:** limpeza cirúrgica de ~200 linhas de código morto que reduz superfície de manutenção e tamanho do bundle. | Baixo | P | Worker |
| T10 | **`FERIADOS_B3_2028` preventivo:** adicionar antes do final de 2027 para evitar bug silencioso de dia de pregão mal identificado em 01/01/2028. | Baixo | P | Worker |
| T11 | **Cache inteligente de análise recente:** chave `radar:analise:{empresa}` com TTL 4–6h; pulso manual serve cache se fresh, com flag `_cache_recente` e idade no payload. Corta custo de API e latência de ~7-13s para <1s em repetições. *(2026-06-11)* | Alto | M | Worker |
| T12 | **Dedup de requisições concorrentes:** lock leve em KV/DO por empresa durante cascade em voo; segunda requisição aguarda e recebe o mesmo resultado. Hoje 2 usuários pedindo a mesma análise disparam 2 cascades pagas. *(2026-06-11)* | Médio | M | Worker |
| T13 | **Custo por análise logado:** tokens + USD estimado por provider em cada análise (dimensão extra no `tel()` + agregado diário em KV `radar:custo:detalhe:{data}`). Disjuntor diário passa a ter base real; pré-requisito de pricing por tenant. *(2026-06-11)* | Alto | M | Worker |
| T14 | **Feedback progressivo de análise (pseudo-streaming):** SSE ou polling de status da cascade (provider em uso, rodada N/9, eventos encontrados) em chave KV efêmera. Streaming token-a-token é incompatível com `sanitizarPayloadRadar`; status progressivo reduz latência percebida sem quebrar validação. *(2026-06-11)* | Médio | G | Worker + Frontend |
| T15 | **Backoff + timeout por provider na cascade:** timeout individual e backoff exponencial com jitter entre tiers (hoje retry sequencial fail-fast). *(2026-06-11)* | Médio | P | Worker |

### Produto (impacto × esforço)

| # | Melhoria | Impacto | Esforço | Componente |
|---|----------|---------|---------|------------|
| P1 | **Status de providers no painel admin:** card visual com uptime/latência de cada provider (OpenRouter, Anthropic, Resend). Hoje o operador só descobre falha via `action=teste` manual. | Alto | P | Frontend (admin) |
| P2 | **Créditos OpenRouter visíveis:** exibir saldo de créditos no health check admin. API OpenRouter tem endpoint de saldo. | Alto | P | Worker + Frontend |
| P3 | **Funil de entrada / landing page:** o produto não tem página pública com pricing, CTA e onboarding. Usuários chegam direto no login sem contexto. Impede crescimento orgânico. | Alto | G | Frontend (nova rota /) |
| P4 | **METRICAS_CURADAS com data de referência por empresa:** exibir ao usuário quando foram atualizados os KPIs de cada emissor. Hoje parece dado live mas é 4T25 estático. | Médio | P | Frontend |
| P5 | **Feedback de rate limit na UI:** banner discreto "Você usou X de 25 pulsos hoje" usando `rl_inspect` pós-análise. Reduz frustração quando usuário atinge limite sem aviso. | Médio | P | Frontend |
| P6 | **ARQUIVO_PRE com TTL automático:** eventos de arquivo com `data_evento > 90d` expiram automaticamente ao renderizar (não ficam visíveis no PDF). Hoje: 2 eventos expirados mostrados no PDF. | Médio | P | Frontend |
| P7 | **Newsletter opt-in por setor:** frequência ou filtro por setor de interesse, não só on/off. Usuário de infraestrutura não quer receber alertas de bancos todo dia. | Médio | M | Worker + Frontend |
| P8 | **CNPJ e Termos formais:** disclaimer sem CNPJ e sem advogado reduz credibilidade com gestoras profissionais e family offices em due diligence. | Médio | — | Jurídico + Frontend |
| P9 | **Onboarding guiado (primeiro login):** wizard de 3 passos — selecionar setores de interesse, fazer primeiro "Pulso", entender o dashboard. Taxa de ativação provavelmente baixa hoje por falta de contexto. | Médio | G | Frontend |
| P10 | **Análise de emissor com contexto histórico visível:** painel de emissor mostra só eventos da semana atual. Adicionar timeline compacta dos últimos 3 meses (via `op=historico_emissor`). Backend já existe, só falta o frontend. | Alto | M | Frontend |
| P11 | **Alertas por emissor (watchlist com alertas):** favorito ganha opt-in "alertar evento crítico" → email imediato (Resend) no pipeline de persistência; prefs em `user_prefs:{email}`. Infra de favoritos + email já existe, falta o vínculo. Maior valor percebido para gestor profissional. *(2026-06-11)* | Alto | M | Worker + Frontend |
| P12 | **UI de comparação de emissores:** tela side-by-side (até 5) consumindo `op=comparar` já pronto no backend desde v4.8.0 — zero consumidores no frontend (Grep confirma). Quick win. *(2026-06-11)* | Alto | P/M | Frontend |
| P13 | **Briefing executivo na UI:** card/tela "Briefing do dia" consumindo `op=briefing_executivo` já pronto (top 10 materialidade, distribuição setorial, EWS). Endpoint órfão — única menção no frontend é tooltip (linha ~3408). *(2026-06-11)* | Alto | P/M | Frontend |
| P14 | **Gráfico de série temporal por emissor:** spread/EWS/anomalias ao longo do tempo a partir das chaves `serie:` do KV (sparkline no painel do emissor). Dado existe mas não é visualizado. *(2026-06-11)* | Médio | M | Frontend |
| P15 | **Histórico estendido na timeline (3 meses):** ampliar janela da timeline do emissor via `op=historico_emissor` — reclassificação do P10 como prioridade; mudança só de frontend. *(2026-06-11)* | Médio | P | Frontend |

> **Nota de disambiguação:** os IDs T1–T15 / P1–P15 desta seção são das tabelas de Oportunidades de Melhoria e independem dos achados de auditoria (P01–P22, N01–N13) da tabela de achados. Itens T11–T15 e P11–P15 adicionados em 2026-06-11 (levantamento de oportunidades; análise completa em `Obsidian VIX Radar/10 - Oportunidades de Melhoria (2026-06-11).md`). Priorização top 5 por valor÷esforço: P12, P13, P11, T11, T13.

---

## Comparação com baseline (2026-06-03)

| Métrica | Baseline (P01–P22) | Esta auditoria |
|---------|-------------------|----------------|
| Total de achados | 22 | 40 |
| Resolvidos | — | 12 (P01–P04, P06, P09, P14, P16, P17, P21) |
| Agravados | — | 2 (P05→CI 100% broke; P15→double-run confirmado) |
| Abertos do baseline | — | 9 (P07 parcial, P08, P10, P11, P12, P13, P18, P19, P20, P22) |
| Novos nesta auditoria | — | 18 (N01–N13 + P15-B + variantes) |
| Críticos ativos | — | 3 (N01 cascade, P05* CI, P15* double-run) |

---

## Evidências brutas de produção (2026-06-10)

```
GET / health:
{"ok":true,"versao":"v4.9.102","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"3/3"}
HTTP 200

GET /version.json (apex):
{"version":"v201.45","deployed_at":"2026-06-07T08:16:04Z"}
HTTP 200

GET /version.json (www):
{"version":"v201.45","deployed_at":"2026-06-07T08:16:04Z"}
HTTP 200

POST / anônimo:
{"ok":false,"erro":"Autenticação necessária."}
HTTP 401

GET ?action=teste (providers):
openrouter: {status: 402, error: "..."} — SEM CRÉDITOS
anthropic/haiku: OK
resend: configured:true

GET ?action=tel_test (admin_senha=***):
{"ok":true,"binding_presente":true,"write_result":{"ok":true}}
HTTP 200

OPTIONS (CORS apex, Origin: vixradar.com):
Access-Control-Allow-Origin: https://vixradar.com
HTTP 204

OPTIONS (CORS www, Origin: www.vixradar.com):
Access-Control-Allow-Origin: https://www.vixradar.com
HTTP 204

OPTIONS (CORS inválido, Origin: evil.com):
[sem Access-Control-Allow-Origin]
HTTP 204

SPF: v=spf1 include:_spf.mx.cloudflare.net include:amazonses.com include:send.resend.com ~all
DMARC: v=DMARC1; p=none; rua=mailto:dmarc@vixradar.com

Drift prod vs repo:
PROD: 717.241 bytes / 15.635 linhas / SHA256: 3178C341...
REPO: 676.385 bytes / 14.431 linhas / SHA256: 0FE5D44A...
VEREDITO: DIVERGENTE (mesmo v4.9.102, builds diferentes)
```

---

*Gerado por auditoria automatizada em 2026-06-10. Credenciais admin redigidas como `***`. Nenhum dado pessoal de terceiros exposto.*
