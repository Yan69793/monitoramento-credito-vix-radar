# 98 - Auditoria Geral 2026-09-01

Data: 2026-09-01 (madrugada, ~00:45 BRT)
Skill: `/vix-radar-general-audit` (snapshot governança 2026-08-31)
Modo: readonly. Nenhum deploy, nenhum POST destrutivo.

## Veredito

Nenhum achado P0/P1/P2. Quatro achados P3/P4, todos menores. Saúde de
produção íntegra, veracidade da UI limpa, portão verde, CI verde.

## Mapa de versões (alinhado)

- Worker: repo `main = v4.9.227.js` = produção (health público `versao: v4.9.227`). Alinhado.
- Frontend: `CACHE_VERSION = v202.35` = `app/deploy_zip/version.json` = produção. Alinhado.
- Deploy_zip sincronizado com `app/`: todos os módulos JS batem por hash; só `index.html` difere, por CRLF (app) vs LF (deploy_zip), conteúdo idêntico. Não é drift.

## Portão de verificação (saída real, 01/09 ~00:10 BRT)

```text
HTTP:200 TEMPO:2.079s
ok:true fonte_externa_ok:true versao:v4.9.227 kv:true rate_limiter:true telemetria:true
providers "2/2" admin_email_ok:true sentry_ok:true verificador_ok:true
cvm_fonte_ok:true cvm_fonte_idade_du:2 cvm_fonte_proxima_prevista:2026-09-06
cvm_atribuicao_por_cnpj:813 por_nome:0 quarentena:1439 cobertura_pct:36.1 descartados_teto:0
```

`ok:true` com `fonte_externa_ok:true` e `verificador_ok:true`: nada mascarado.
Verificador entra no `ok` agregado refletindo staleness da fila (>20h derruba).
Fonte CVM separada em `fonte_externa_ok`, cadência semanal respeitada
(próxima prevista 06/09, domingo, CVMCADENCIA1).

## Achados

### P3-1 — Skill desatualizada (governança do /vix-radar-general-audit)

A própria skill e `references/audit-matrix.md` declaram "Worker v4.9.226, medido
em 31/08". Produção está v4.9.227 desde 31/08 (deploy BRASKEMDETECT1,
commit af2abb1). A condição de obsolescência da skill ("revisar quando o main
de api/wrangler.toml ultrapassar v4.9.226") disparou de fato, mas ninguém rodou
a revisão antes de usar.

- Correção: atualizar o bloco de governança da skill e da matriz para v4.9.227, data 01/09.
- Causa raiz: o deploy v4.9.227 aconteceu no mesmo dia do snapshot de governança, depois dele. Não existe mecanismo que compare a data do snapshot com a data do changelog.
- Guarda sistêmica: item permanente na própria skill (rodar a checagem de drift antes de auditar já cobre), e o mapa de versões do passo 3 detecta.

### P3-2 — Disjuntor de custo barra crons matinal/noturno que não gastam LLM

`_ehCronComLLM` (L19164-19167) aplica o disjuntor de custo diário nos dois crons.
Mas desde a delegação ao Claude Desktop, o Worker roda matinal/noturno sem LLM:
varredura marcada `pulado/delegado_claude_tiered_v2` (`varredura_cron_ai=false`),
o cron vira só housekeeping (sync CVM, anomalias, ANBIMA, pipeline preditivo,
newsletter, healthcheck diário). Se o teto de custo diário estourar (consumo das
rotinas locais), o disjuntor aborta o `sync_cvm` e o `healthcheck_diario`, os dois
sinais que o watchdog e o frescor usam. Risco plausível de silenciar a operação
num dia de gasto alto, exatamente quando o operador não está perto.

- Correção: estreitar o gate do disjuntor para os ramos que gastam LLM de verdade (hoje nenhum no Worker, ou só se `varredura_cron_ai=true`). Housekeeping nunca deve cair no disjuntor.
- Causa raiz: a delegação da varredura ao Claude Desktop não revisou o gate de disjuntor, que herdou a premissa de que matinal/noturno gastam LLM.
- Guarda sistêmica: checagem de auditoria "todo cron sob disjuntor gasta LLM de fato"; ou mover o gate para dentro do ramo de varredura.

### P3-3 — CLAUDE.md diz watchdog monitora 6 heartbeats, código monitora 7

`expectedAgents` (L19189) inclui `verificacao_async` (7). CLAUDE.md lista 6. Doc drift menor.

- Correção: CLAUDE.md lista 7.
- Causa raiz: adição do heartbeat `verificacao_async` não atualizou a doc.
- Guarda: item permanente da matriz.

### P4-1 — Oráculo de tempo invertido no login

`handleLogin` (L6315-6373): delay de 80-200ms só no caminho usuário-inexistente.
Senha errada de usuário existente responde imediatamente. Atacante distingue
existência de conta por timing (lento = não existe). Resposta de erro é genérica
("Credenciais inválidas", anti-enumeração textual), mas o timing vaza. Mitigado
pelo rate limit (`criticidade "auth"` no gate L18090).

- Correção: aplicar o mesmo delay no caminho de senha errada.
- Causa raiz: a intenção era uniformizar o tempo, mas o delay foi aplicado só num ramo.
- Guarda: anotação na matriz de segurança.

## Verificado bom (não-achados)

- Auth: JWT Bearer no header, sem Set-Cookie (COOKIE-CLEAR1/CSRF-COOKIE1), CORS allowlist `https://vixradar.com`, rate limit em auth (AUTHDISPO1 fail-open para login/registro, fail-closed para admin senha errada), admin senha correta pula o check (ADMINRL-FIX1).
- XSS dupla guarda: strip no write (`sanitizarPayloadRadar`, XSSV100-FIX1) + escape no render (`h()`/`x()`/`_escapeHtmlComentario`). `strong` sem `color` global, só selectors específicos.
- `receber_analise`: verificação assíncrona no caminho crítico, `sem_eventos:true` só por schema, self-healing `cvm_ids_analisados` (CVMNOVOSDEAD1), `protecao_ativa` exposto em `reservar_itens_fila`.
- TTLs: volatilidade 72h (VOLTTL1 ok, >= 2x intervalo diário), fallback 72h/48h, `cvm:documentos` 30d, audit keys 365d, alerta 10d.
- Preditivo: `merton` 0% morto conhecido (DRIVERMORTO1, `user_facing:false`), `check-drivers-preditivos.ps1` passa (evento 20.4%, momentum 8.7%, mercado 1%, recorrencia 14.6%, desagio 8.7%).
- CVM atribuição: cobertura 36.1% = 813/(813+1439), quarentena 1439 são companhias Cia Aberta fora dos 103 monitorados, comportamento esperado, excluído do `ok` de propósito.
- KV→DO: dual-write + read fallback com `console.warn` `[DO][dual-write]`/`[DO][read]`, 3 DOs + migration v3 presente.
- `montarPlanoRotina` usa `carregarEstadoMultiSemana(env, 3)`, bate com a doc.
- Sem estado global de módulo mutável entre requests.
- Veracidade da UI: `audit-ui-metrics.mjs` 0 bloqueantes; rótulos reservados conferidos; Market Overview com guarda `_semLeitura`, janela "· 30 dias" declarada, escape correto no heatmap e na timeline.
- Sentinela viva: log de 31/08 `FIM: sentinela sem gatilho. tokens=0`, só dias úteis.
- CI: Canonical Production Test, Frescor, Scan Emergencia, Worker Tests, Cadastro Emissores, Status Diario — todos success.

## Lacunas desta auditoria

- Suíte vitest não rodou local (devDeps ausentes no `node_modules` do fluxo de deploy); evidência é o CI `worker-tests` verde.
- Logs do Worker não inspecionados para padrões `[DO][dual-write]`/`[DO][read]` em produção (sem acesso ao painel nesta sessão). Presença do código confirmada, comportamento real não.
- Login não testado end-to-end (readonly).
- a11y WCAG e Core Web Vitals não medidos em navegador (sem web-perf).
- Rotinas CCD fora do repo (`%APPDATA%`) não lidas; idempotência METRICSZERO1 verificada indiretamente (Worker marca "pulado", preservando métricas).

## Próximos passos

1. Atualizar governança da skill `/vix-radar-general-audit` para v4.9.227 (P3-1).
2. Decidir estreitamento do disjuntor de custo para crons sem LLM (P3-2).
3. Corrigir CLAUDE.md watchdog 6→7 heartbeats (P3-3).
4. Delay uniforme no login (P4-1).
5. Abertos pré-existentes: CCDOFFLINE1 (toggle do operador), SENTINELA-SYNC1 (decisão do operador), PISODIFF1-ESTRUTURAL1 (escada de piso), TOKENCHAT1 (operador), FALLBACKTTL1 sem teste automatizado.

---

## Apêndice de fechamento (01/09, tarde) — fechamento dos 5 resíduos da sessão

Apêndice porque este corpo é o registro da auditoria readonly de 01/09 (regra 4
do CLAUDE.md: registro datado não se reescreve). Segue o fechamento, que mudou
produção para v4.9.232.

1. **PREVERIFSEC1 (Braskem/sec.gov, deploy v4.9.232).** O pré-verificador
   descartava o 6-K da SEC (evento CRÍTICO Braskem 31/08) com `ok:true` mas
   `n_eventos:0` — a SEC devolve 403 a User-Agent genérico e `sec.gov` não era
   fonte confiável. Fix distinto: `DOMINIOS_FONTE_OFICIAL_DOCUMENTOS` +
   `_ehFonteConfitavelBloqueada`; aceite só na janela de 30d e sempre com
   `_verif_forcar`. Guarda `api/test/pre-verificador-sec-gov.test.mjs` (8
   testes). O teste usa `_fetchOverride` (fetch injetável, só teste) para
   reproduzir fielmente o 403 do 6-K real.
2. **Cron da noturna:** frontmatter do SKILL.md corrigido de "18h" para "10h
   BRT"; `cronExpression="0 10 * * *"` intocado; scheduler vivo confirmado.
3. **SUBMITOK-ENGANOSO1:** ledger `OK|` ganhou 6º campo
   `SKIP|ANALISADO|DEFERIDO`; Passo 11 exige analisados/skip/deferidos/
   submits_aceitos. Guarda `scripts/check-ledger-noturno.ps1`.
4. **Cruzamento dos 1.439 sem dono = COMPORTAMENTO ESPERADO.** 383 entidades,
   cobertura 36,1%; nenhuma de maior volume pertence aos 103; 99/99 CNPJs
   primários dos 103 no cadastro CVM. Nenhuma correção de atribuição. Guarda
   `scripts/check-quarentena-emissores.mjs`.
5. **Fonte intradiária = LIMITAÇÃO ACEITA COM CONDIÇÃO DE REABERTURA.**
   Reabre com fonte confiável aprovada + credencial. Fora dos bugs.

Deploy `deploy-worker.ps1 -Version v4.9.232`; portão pós-deploy `ok:true
versao:v4.9.232 kv:true telemetria:true sentry_ok:true`. Suíte 23 arquivos /
196 testes. Commits `46f809c`, `d25d6c5`, `66b8b74`. Repo=produção, local=origin,
working tree limpa.
