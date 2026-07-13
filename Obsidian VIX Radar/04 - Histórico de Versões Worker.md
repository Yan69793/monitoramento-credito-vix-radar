# Histórico de Versões Worker

**Notas:** Este arquivo centraliza o histórico detalhado de mudanças do Worker (CloudFlare) versões v4.5–v4.9. O CLAUDE.md slim faz referência a este documento.

---

## v4.9.153 → v4.9.154 (13/07/2026) — DEPLOYADO

**Validação de datas para fontes de rating que bloqueiam leitura (`validarDatasFontes`):**
- **Causa raiz:** downgrade real da S&P sobre a Cosan (08/07) foi descartado na ingestão. `validarDatasFontes` tenta confirmar a data da fonte via `extrairDataDaURL` ou `fetch` do HTML; quando ambos falham e não há data legível, descarta o evento (`else { continue }`). A S&P (`spglobal.com`) retorna **403 a qualquer robô** — testado com UA `VixRadar/2.0` e com UA de Chrome real, ambos 403 (bot detection Akamai). Fitch (`fitchratings.com`) responde 200 normalmente e não é afetada.
- **Fix:** novo `DOMINIOS_RATING_AGENCY_SET` (spglobal.com, fitchratings.com, moodyslocal.com.br, moodys.com, austinrating.com.br). No ramo de fonte inacessível, se o host é agência de rating **e** `data_evento` está na janela (`>= trintaDiasAtras && <= hoje`) e não é `nao_identificada`, o evento não é descartado: recebe `_data_fonte_bloqueada=true` e `_verif_forcar=true`, e é aceito para verificação. `deveVerificar` passa a honrar `if (ev._verif_forcar === true) return true;` como primeira condição, garantindo que vai para a fila adversarial (nunca auto-aprovado).
- **Garantia de data (requisito do operador):** a certeza da data vem da **reconfirmação independente do verificador adversarial**, não do aceite da `data_evento` gerada pela IA. Se o verificador não confirmar, o evento é rejeitado. Comportamento conservador: prefere perder um alerta a gravar data não confirmada.
- **Escopo/efeitos colaterais:** mudança isolada ao ramo `else` (fetch falhou) de `validarDatasFontes` — fontes acessíveis inalteradas; fontes não-rating bloqueadas mantêm descarte; Fitch inalterada. Log `[validarDatas][RATING_BLOQUEADO]` para auditoria.
- **Validação:** `node --check v4.9.154.js` OK; deploy `wrangler deploy v4.9.154.js --no-autoconfig`; health duplo curl local + Sprite `versao:v4.9.154 ok:true bindings kv/rate_limiter/telemetria true verificador_ok:true`. Version ID `eedc8a47-dfd0-44b8-ba1d-60296bba7893`.
- **Rollback:** `main = v4.9.153.js` no `wrangler.toml` + redeploy (arquivo preservado).
- **Correção-irmã (não-Worker):** `scripts/run_vixradar_matinal_claude.ps1` ganhou parser robusto (`Get-BatchOkEmissores` + `Get-BatchResumoOk`) contra o falso `silent_fail`/exit 6 quando os lotes `claude -p` formatam o relatório em markdown. Aplicada, sem deploy, vigora na próxima matinal.

---

## v4.5.0 → v4.5.1 (09/04/2026)

**Fix privacidade emails (BCC):** `enviarResend()` enviava todos os destinatários no campo `to`, expondo emails entre si. Corrigido para `to: ["boletim@vixradar.com"]` + `bcc: destArray`. Afeta alertas críticos e newsletter.

---

## v4.5.1 → v4.5.2 (10/04/2026)

**Notificação WhatsApp de novos cadastros (Twilio Sandbox):**
- Função `enviarWhatsAppAdmin()` chamada em `handleRegistrar()` após tentativa de email Resend.
- Envia mensagem formatada com nome, email, empresa, hora BRT e link direto `vixradar.com/admin?highlight=<email>`.
- Usa Twilio REST API (Basic Auth com SID+Token).
- Destino atual: sandbox `+1 415 523 8886` → `whatsapp:+5521981088992`.
- Latência ~1s.
- Secrets: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_WHATSAPP_FROM`, `ADMIN_WHATSAPP_TO`.
- Code join sandbox: `join spent-negative` (renovar a cada 72h de inatividade).
- Version ID: `13cd3ae6-0982-4526-9a69-87f2c1e8b919`

---

## v4.6.1 → v4.6.2 (11/04/2026) — Fase 0.5 Risk Budgeting (preparatória)

Patch cirúrgico, puramente infraestrutural. **Não contém Ledoit-Wolf, ERC nem Euler.** Apenas remove bloqueios estruturais identificados na auditoria `auditorias/AUDITORIA_DADOS_LAYER1_2026-04-10.md` antes da Fase 1 de Risk Budgeting (que sairia como v4.7.0).

1. **`salvarSerie` — cap de retenção 30 → 252 registros** (`worker/v4.6.2.js:1931`).
   - O `slice(0, 30)` descartava qualquer dado além dos últimos 30 registros.
   - Tornava impossível acumular os 252 dias úteis exigidos por Ledoit-Wolf (T > N com N=100).
   - **TTL permanece em 90 dias** (`expirationTtl: 60*60*24*90` na linha 1933) — a retenção foi de quantidade, não de tempo.
   - Nota: 252 dias úteis ≈ 1 ano calendário ≈ 357 dias corridos, então o TTL de 90d pode podar a série antes de atingir 252 registros se houver hiato de ingestão. Reavaliar TTL na Fase 1 quando dados reais ANBIMA fluírem.

2. **Schema persistido ganha campo `duration`**
   - `parsearCSVMercado` reg (`worker/v4.6.2.js:2087`)
   - `COL_MAP` com aliases `duration`/`duracao`/`duracao_media`/`duration_macaulay`/`duration_modificada` (`:2031`)
   - `tentarSyncANBIMA` extrai de `Duration`/`duration`/`DuracaoMacaulay`/`DuracaoMedia`/etc do payload ANBIMA (`:2289`)
   - Agrega por emissor no `porEmissor[nome].durations` e escreve coluna `duration` no CSV intermediário
   - Sem `duration` não há DTS (`vol ≈ k · duration · spread`) nem fallback para emissores com série curta.

3. **`FERIADOS_B3_2027` adicionado** (`worker/v4.6.2.js:1871-1910`).
   - `ehDiaPregaoB3` agora consulta ambos os sets (2026 e 2027).
   - Não era bloqueante para 2026 mas viraria bug silencioso em 01/01/2027.

**Validação:** Deploy em 2026-04-11T02:31:34Z via `npx wrangler deploy` a partir de `worker/wrangler.toml` apontando `main = "v4.6.2.js"`. Health check `GET /` OK em 93ms (openrouter, gemini, perplexity, resend, kv todos `true`).

**Gate de dados para prosseguir à Fase 1 (Risk Budgeting v4.7.0):**
- Credencial ANBIMA produção liberada (email enviado para `dados@anbima.com.br`, APP `2r1Gywm4kZTM` — **aguardando resposta**).
- Após secret `ANBIMA_API_TOKEN` colocado, forçar `sync_anbima` e backfill histórico (se ANBIMA aceitar `?date=` retroativo).
- Critério de entrada: ≥60% dos 100 emissores com ≥252 registros reais, `duration` populado em ≥80% dos registros recentes, `?action=status_mercado` mostrando `com_anomalias > 0`.

---

## v4.6.4 → v4.6.5 (11/04/2026) — Endpoint admin de remoção de comentário

**Endpoint `comentario_remover`** protegido por JWT admin.
- Delete da chave `comentario:{empresa}:{ts}` no KV.
- Audit trail em `audit:comentario_remover:${Date.now()}` com TTL de 1 ano, guardando quem removeu, o quê e quando.
- Utilizado para sanear comentários de teste que restaram de sessões anteriores.

---

## v4.6.5 → v4.7.0 (11/04/2026) — Infra multi-tenant por feature flags

Preparação de terreno para customizações do Mirabaud sem forkar o código base. **Nenhum comportamento novo para o usuário final.** Features novas passam a ser gated por tenant.

**Constantes globais:**
```js
var DEFAULT_TENANT_ID = "vix_core";
var TENANT_DOMAIN_MAP = { "mirabaud.com": "mirabaud", "mirabaud.ch": "mirabaud" };
var DEFAULT_TENANTS = {
  vix_core: { id: "vix_core", nome: "VIX Radar", features: ["favoritos"] },
  mirabaud: { id: "mirabaud", nome: "Mirabaud", features: ["favoritos", "ews_filter"] }
};
```

**Mudanças:**
1. `resolverTenantPorEmail(email)` → lê domínio após `@`, consulta `TENANT_DOMAIN_MAP`, cai em `DEFAULT_TENANT_ID` se não encontrar.
2. `handleRegistrar` → seta `user.tenant = resolverTenantPorEmail(email)` no objeto salvo em KV.
3. `handleLogin` → carrega `tenantConfig` via `getTenantConfig`, adiciona `tenant` ao payload do JWT, devolve `tenant_config` no body da resposta para o frontend gate-ar features.
4. `handleAdminAutoLogin` → seta `tenant: DEFAULT_TENANT_ID` ao criar admin; se admin já existe sem `tenant`, migra para `vix_core`.
5. `handleTenantConfigGet` → endpoint admin para inspeção.
6. `getTenantConfig(env, tenantId)` → primeiro checa `DEFAULT_TENANTS[tenantId]`, depois KV `tenant_config:{id}`, cai em `DEFAULT_TENANTS.vix_core` como fallback.

**Filosofia:** Um único código base, features por tenant, nenhum fork. Primeira feature construída sobre essa infra é `favoritos` (universal em ambos tenants). Features exclusivas Mirabaud virão via campo `features` em `DEFAULT_TENANTS.mirabaud`.

---

## v4.7.0 → v4.7.1 (11/04/2026) — Favoritos privados por usuário

Primeira feature construída sobre a infra multi-tenant. Universal nos dois tenants (`vix_core` e `mirabaud`). **Doc único por usuário**, não scan prefix.

1. **`kvUserFavoritosKey(email)`** → chave KV `user_favoritos:${email.toLowerCase().trim()}`. Valor é um JSON array de objetos `{empresa, marcado_em}` ordenado alfabeticamente por `empresa`.
2. **`lerFavoritosDoUsuario(env, email)`** → `env.RADAR_KV.get(chave, "text")`. Read direto da chave do usuário, sem scan.
3. **`escreverFavoritosDoUsuario(env, email, favoritos)`** → sort + `put`. Read-after-write na mesma chave é consistente no KV, diferente do `list()`.
4. **`handleFavoritoListar(body, env, request)`** → verifica JWT via `verificarJWT`, checa `userHasFeature(env, user, "favoritos")`, retorna `{ok: true, favoritos: [...]}`.
5. **`handleFavoritoToggle(body, env, request)`** → verifica JWT, checa feature, lê array atual, modifica em memória (add se não existe, remove se existe), escreve de volta. Retorna `{ok, empresa, marcado: bool, favoritos: [...]}`.
6. **`userHasFeature(env, user, feature)`** → carrega `tenant_config` via `getTenantConfig` e checa se feature está na lista.
7. **Isolamento absoluto.** `emailAut = payload.email` vem do JWT, nunca do body. Nenhum usuário consegue ler ou escrever favoritos de outro.

**Por que doc único e não chaves individuais + scan prefix?** A primeira implementação usou `favorito:{email}:{empresa}` + `list({prefix})`. Deployada, testada, bugada. Cloudflare KV `list()` tem eventual consistency, o read-after-write pode levar até 60 segundos. Resultado: após `put` de uma chave, o `list()` subsequente retornava vazio, e a resposta mostrava `marcado: true` mas `favoritos: []`. **Read-after-write na mesma chave (`get` após `put`) é consistente** dentro da mesma região, então o doc único resolveu.

**Validação em produção (11/04/2026):** Bateria de 7 testes: listar inicial vazio, toggle Auren, toggle Sabesp, listar (2 items), desmarcar Auren, listar final (1 item), sem token 401. Todos OK. Version ID: `d89ac737-ea9e-4412-978d-62b8107f495e`.

---

## v4.7.1 → v4.7.2 (tentativa abortada, sem uso real)

Rate limit v2 via KV sliding window em doc único `rl:v2:u:{email}` ou `rl:v2:ip:{ip}`. Código logicamente correto mas falhou no teste de 4 requisições sequenciais rápidas. Causa provável: race condition em read-modify-write sob consistência eventual do KV quando puts de uma request ainda não propagaram ao get da próxima. **Substituído pela v4.7.3 sem passar por uso em produção real**, apenas o próprio teste de validação. Arquivo `worker/v4.7.2.js` mantido para referência histórica.

---

## v4.7.2 → v4.7.3 (11/04/2026) — Rate limit via Durable Object

**Contexto:** O usuário pediu um limitador de varreduras por usuário em janela de 30 minutos, para permitir compartilhar o acesso à plataforma sem expor o custo de API ao abuso. A v4.7.2 falhou em produção por race condition. Rollback imediato via substituição pela arquitetura definitiva v4.7.3.

**Arquitetura definitiva:**

1. **`RateLimiterDO`** é um Durable Object SQLite-backed (exigido pelo free plan via `new_sqlite_classes` na migration). A classe expõe duas rotas internas no fetch: `POST /check` (faz o gating atomic, push de timestamp se allowed) e `GET /inspect` (retorna snapshot do storage para observabilidade). O storage guarda uma única chave `timestamps` com um JSON array de `Date.now()` dos últimos eventos.

2. **`idFromName(identidade)`** determina o DO instance. Identidade é `u:{email}` quando autenticado, ou `ip:{CF-Connecting-IP}` quando anônimo. Cada identity mapeia para um único DO, que serializa requests por key. Esta é a propriedade que elimina a race condition da v4.7.2.

3. **Três camadas** verificadas em uma única passada atomic: `burst` (3/60s), `session` (10/1800s = 30 min), `daily` (30/86400s). A camada mais apertada viola primeiro. Contadores session e daily só incrementam quando a requisição é allowed, nunca em bloqueios.

4. **Limites por tenant** via `RATE_LIMITS_POR_TENANT`. `vix_core` usa `{burst:[5,60], session:[25,1800], daily:[150,86400]}`. `mirabaud` usa `{burst:[10,60], session:[50,1800], daily:[300,86400]}`. Anônimo usa `RATE_LIMITS_ANONIMO` = `{burst:[3,60], session:[10,1800], daily:[30,86400]}`, o mais restritivo.

5. **Headers IETF** em 429: `X-RateLimit-Limit-{camada}`, `X-RateLimit-Remaining-{camada}`, `X-RateLimit-Reset-{camada}` (epoch seconds), `Retry-After`. Body retorna `{ok:false, erro, _rate_limit:{camada, retry_after_sec, tenant, autenticado, limites}}`.

6. **Fail-open com instrumentação.** Se o DO estiver indisponível ou lançar erro, `checkRateLimitV2` retorna `allowed:true` com flag `_bypass:"do_erro"` ou `_bypass:"do_binding_ausente"`. Prefere disponibilidade sobre proteção em caso de falha de infra.

7. **`GET ?action=rl_inspect`** é público mas só retorna snapshot da **própria identidade** do requisitante (resolvida via JWT ou IP). Útil para debug sem precisar de novo deploy, e para o frontend eventualmente mostrar ao usuário quantas varreduras restam.

**Validação em produção (11/04/2026 17:45 UTC):** Bateria de 5 requisições anônimas sequenciais sem Authorization no endpoint `POST /`:
- R1 Auren: 13.43s, 200, Cascade completa via OpenRouter
- R2 Auren: 6.44s, 200, OpenRouter
- R3 Auren: 5.53s, 200, OpenRouter
- R4 Auren: 0.65s, **429**, Camada burst violada, retry_after 36s
- R5 Auren: 0.66s, **429**, Camada burst violada, retry_after 35s

Fast-fail (<1s) nos 429 confirma que o DO resolve antes do cascade AI, protegendo o orçamento OpenRouter/Gemini/Perplexity. Contadores de session (7 remaining = 10-3) e daily (27 remaining = 30-3) confirmam que só requisições allowed consomem quota.

**Limitação conhecida:** Headers `X-RateLimit-*` só são injetados nas respostas 429, não nas 200. Item de melhoria futura, não bloqueante.

---

## v4.7.3 → v4.8.0 (12/04/2026) — Enrichment Layer + Intelligence Endpoints

**Enrichment Layer e Intelligence Endpoints.** Backend-only, sem mudança no frontend. Todos os campos novos usam prefixo `_` e são aditivos, o frontend existente os ignora sem quebrar.

1. **Enrichment Layer (`enriquecerEvento`, `enriquecerPayload`):**
   - Pós-processamento de cada evento da cascade AI.
   - Adiciona bloco `_enriquecimento` com: `materialidade` (0-100, calculada por `MATERIALIDADE_POR_TAG` × `CRITICIDADE_SETOR` × multiplicador de classificação), `confianca` (herdada do verificador ou 0.5 default), `playbook_tipo` e `playbook_acoes` (ações de monitoramento recomendadas por tag, ex: rating → "Verificar outlook completo", "Comparar com pares"), `cadeia_causal` (inferida da tag), `setor_criticidade` (peso do setor, Bancos 0.95, Tech 0.6).
   - `enriquecerPayload` ordena eventos por materialidade desc e adiciona `_qualidade_sinal` (provider, tempo_ms, eventos_total, eventos_verificados, confianca_media, materialidade_max).

2. **`op=briefing_executivo` (GET, JWT):** Agrega estado semanal de todos os emissores no KV, enriquece eventos, retorna: top 10 por materialidade, distribuição setorial (quantas empresas, quantos eventos críticos/relevantes por setor), resumo EWS (anomalias ativas), contagem de docs CVM sincronizados.

3. **`op=historico_emissor&empresa=X` (GET, JWT):** Memória completa do emissor: eventos da semana (enriquecidos), análise privada do usuário, comentários, anomalias, score EWS, resumo de séries históricas (última data, total registros), cache de último resort.

4. **`op=comparar&empresas=A,B,C` (GET, JWT):** Side-by-side de até 5 emissores com: eventos da semana, materialidade máxima, anomalias ativas, score EWS. Para construção futura de dashboards comparativos.

5. **`executarHealthCheckDiario(env)` implementado:** v4.7.5 declarava a chamada no cron mas a função não existia. Agora verifica: bindings (RADAR_KV, RATE_LIMITER_DO, secrets), circuit breakers ativos, estado semanal (total emissores com dados, mais recente), saldos via `verificarSaldoProviders`. Grava resultado em KV `admin:healthcheck:diario` com TTL 48h.

6. **Cascade e batch persistem `setor` no payload:** `saneado.setor = setor` injetado em 3 pontos (cascade principal, guard confirmation, batch cron) para que o enriquecimento posterior encontre o setor do emissor.

7. **Constantes de materialidade:**
   - `MATERIALIDADE_POR_TAG` (10 tags, rating=90, mercado=45)
   - `CRITICIDADE_SETOR` (13 setores, Bancos=0.95, Tech=0.6)
   - `PLAYBOOKS` (10 tipos com 4-5 ações cada).

**Validação:** Health check OK (5 serviços true), análise Auren HTTP 200 em 6.99s com `_enriquecimento` e `_qualidade_sinal` presentes, `briefing_executivo` HTTP 200 em 0.43s, `historico_emissor` HTTP 200, `comparar` HTTP 200. Version ID: `baaa7a1e-506d-41c8-9f5d-34183040699a`. Base: v4.7.5.js + ~370 linhas novas.

---

## v4.8.3 → v4.8.4 (13/04/2026) — Dual-cron: varredura matinal inteligente

**Dual-cron: varredura matinal inteligente por prioridade EWS.**

1. **Segundo cron `30 15 * * 1-5` (12h30 BRT, seg a sex):** O `scheduled()` detecta qual cron disparou via `event.scheduledTime` (hora UTC 15 = matinal, 21 = noturno) e roteia para a função correta.

2. **`selecionarEmissoresPrioritarios(env, topN)`** carrega estado multi-semana (5 semanas) + anomalias, calcula EWS para os 100 emissores, gera `score_combinado = EWS * 0.6 + materialidade_max * 0.4`, ordena desc e retorna top N. Emissores com score zero são filtrados.

3. **`executarVarreduraMatinal(env)`** executa a cascade AI apenas nos emissores prioritários. Verifica `ehDiaPregaoB3()` no início, pula silenciosamente em feriados e fins de semana. Flag `_matinal: true` no payload persistido. Resultado gravado em KV `admin:ultimo_matinal` com TTL 48h.

4. **Cron matinal executa:** `syncCVMAutomatico` → `recalcularTodasAnomalias` → `executarVarreduraMatinal` → `verificarSaldoProviders`. Sem newsletter e sem sync ANBIMA (reservados para o noturno).

5. **Cron noturno mantém:** pipeline completo original (100 emissores) + newsletter + health check diário + sync ANBIMA.

6. **Endpoint admin `admin_executar_matinal`** para disparo manual com `admin_senha`.

7. **Constantes:** `MATINAL_TOP_N = 30` (cap máximo), `MATINAL_EWS_MINIMO = 0` (corte mínimo de score).

**Validação em produção (13/04/2026):** Matinal via admin: 11 emissores prioritários selecionados (score > 0), 11 sucesso, 0 falha, 83.8s. Top 3: Energisa (EWS 32), Embraer (22), Aegea (22). Health check OK (7 bindings true). Teste padrão Auren HTTP 200 em 5.91s. Version ID: `ed5e22ee-8b0b-4e28-9a04-9125e443e304`. Crons ativos: `30 15 * * 1-5` + `30 21 * * *`.

---

## Versões intermediárias v4.5–v4.8 (stack consolidado)

**Stack de versões intermediárias desta sessão (11/04/2026), todas deployadas:**

| Worker | Feature |
|--------|---------|
| v4.6.3 | `listarUsuarios` reescrita para scan prefix `user:*` corrigindo bug do painel admin |
| v4.6.4 | `listarUsuarios` recebe `sem_cache: true` para forçar scan bypassando cache agregado |
| v4.7.5 | Janelas de eventos ampliadas de 7 para 30 dias. `executarHealthCheckDiario` referenciado mas não implementado. Versão intermediária no repo, não chegou a produção sozinha |

---

## Arquitetura multi-tenant por feature flags

**Decisão de produto:** um único código base serve VIX Radar e Mirabaud. Nenhum fork, nenhum subdomínio separado. A diferenciação é feita pela feature flag `tenant_config.features`, resolvida no momento do login a partir do email do usuário. Para o tenant `mirabaud` (domínios `mirabaud.com` e `mirabaud.ch`), features adicionais podem ser habilitadas sem afetar usuários de `vix_core`. Favoritos foi a primeira feature desenhada sob este modelo, habilitada nos dois tenants por decisão explícita ("bote favoritos para todo mundo").

**Privacy by design dos favoritos:** JWT é a única fonte de identidade. Nenhum endpoint aceita email no body. Read e write usam a chave do próprio usuário, impossibilitando cross-user leakage, inclusive para admin (admin continua vendo apenas seus próprios favoritos). Filtro opt-in "Meus Favoritos" no painel de Configurações do frontend fica salvo em `localStorage` com chave por email (`radar_filtro_favoritos:{email}`), não contamina outras contas no mesmo browser.

---

## Status de features

| Feature | Status |
|---------|--------|
| Cascade AI (OpenRouter → Gemini → Perplexity) | ❌ OBSOLETO desde v4.9.108 — ver CLAUDE.md "Arquitetura de IA Atual" |
| Análise inline (claude-haiku-4-5-20251001 via Anthropic API) | ✅ |
| Análise em lote (matinal Opus + noturno Sonnet via Claude Code Scheduled Tasks) | ✅ |
| Circuit breaker por provider | ✅ (resíduo no bundle — não ativo) |
| Cache de último resort | ✅ |
| Pipeline verdade graduada | ✅ |
| Calendário B3 (ehDiaPregaoB3) | ✅ |
| Provider monitoring (status_providers) | ✅ |
| JWT auth + PBKDF2 | ✅ |
| CORS allowlist | ✅ |
| Email BCC (privacidade) | ✅ |
| Newsletter cron (Resend) | ✅ (DNS pendente) |

---

**Nota:** Este arquivo é canônico para histórico do Worker. O CLAUDE.md slim refere-se a este documento para detalhes de mudanças passadas. Manter atualizado conforme novos deploys ocorrem.

Informações de estado atual de produção: Ver `03 - Estado de Produção.md`.
