---
data: 2026-06-18
tipo: referencia
tags: [vix-radar, metodo, auditoria, vistoria]
status: ativo
---
# Metodo de Vistoria Operacional — VIX Radar

Atualizado: 2026-06-18
Status: procedimento aprendido a partir das auditorias Claude Code e da skill `workers-best-practices`.

**Skill invocável:** `/vix-radar-audit` — `C:\Users\User\.claude\skills\vix-radar-audit\SKILL.md`

## Objetivo

Padronizar a vistoria do sistema para evitar conclusoes por impressao. Toda auditoria deve separar fato verificavel, interpretacao e acao recomendada, com evidencia bruta suficiente para reproducao.

## Fontes lidas antes da vistoria

1. `Obsidian VIX Radar/00 - Índice (MOC).md`
2. `Obsidian VIX Radar/03 - Estado de Produção.md`
3. Auditorias anteriores no vault, especialmente `09 - Auditoria 2026-06-10 (Pendências).md` e `12 - Auditoria Completa 2026-06-14.md`
4. Skill Claude Code `workers-best-practices`, incluindo `references/review.md` e `references/rules.md`

## Metodo consolidado

1. Confirmar estado documental antes de qualquer teste: versoes reais, incidentes abertos, pendencias, deploys recentes e regras inviolaveis.
2. Separar camadas auditaveis: Worker, Pages/frontend, wrangler/config, KV/DO/Analytics bindings, crons, auth/CORS, telemetria, rotinas Claude, CI e documentacao.
3. Para Worker Cloudflare, aplicar checklist da skill `workers-best-practices`: config, bindings, secrets, tipos, uso de `waitUntil`, promises, estado global, streaming, comparacao de segredo, observabilidade e consistencia entre codigo e config.
4. Cruzar repo contra producao. Nao assumir que versao local, bundle, `deploy_zip`, Pages publicado e Worker publicado sao a mesma coisa.
5. Tratar health check publico como sinal necessario, nao suficiente. Quando o risco envolver provider, verifier, Analytics Engine, KV ou rotina agendada, buscar prova especifica do componente.
6. Priorizar achados por impacto operacional: ingestao cega, perda de dados, drift repo/producao, credenciais, telemetria, custo duplicado, regressao de frontend.
7. Aceitar achado apenas com evidencia objetiva: arquivo+linha, diff, resposta HTTP, chave KV, output de ferramenta, screenshot ou documento de producao.
8. Registrar lacunas explicitamente quando uma prova nao foi coletada, por custo, credencial ou escopo.

## Formato minimo do relatorio

- Sintese executiva
- Versoes reais e drift
- Incidentes abertos
- Achados por severidade
- Evidencias brutas
- Causa raiz confirmada, quando houver incidente
- Correcao aplicada ou pendente
- Validacao em producao ou bloqueio
- Lacunas e proximos passos

## Aprendizados do acompanhamento 2026-06-16

- A auditoria boa nao se limita ao `GET /`: o incidente de 2026-06-15 mostrou `ok:true` no health check enquanto o verificador Haiku estava quebrado por `ANTHROPIC_API_KEY` invalida.
- Para ingestao, o teste relevante deve confirmar que eventos novos passam pelo verificador e persistem; ACK HTTP 200 com `n_eventos:0` pode mascarar falha silenciosa ou deduplicacao.
- O Obsidian deve receber o resumo operacional antes de encerrar a etapa. Sem registro, a vistoria fica incompleta.
- A habilidade reaproveitavel e uma combinacao de: protocolo Obsidian do projeto + auditoria viva de producao + checklist tecnico Cloudflare Workers + disciplina de evidencias.

## Proximo uso recomendado

Na proxima vistoria completa, usar esta ordem:

1. Ler Indice e Estado de Producao.
2. Coletar `git status`, versoes locais e arquivos alterados.
3. Validar producao: Worker health, Pages `version.json`, CORS, auth anonimo, telemetria quando autorizado.
4. Auditar config Worker: `wrangler.toml`, bindings, crons, secrets esperados e main version.
5. Auditar endpoints criticos contra regras permanentes: multi-semana, telemetria, verificador, rotinas Claude.
6. Registrar achados no vault com evidencia bruta e lacunas.

## Acompanhamento do plano Claude — 2026-06-16

Plano recebido: auditoria completa + destravar incidente `ANTHROPIC_API_KEY` invalida, com blocos A-E.

Pontos de atencao antes da execucao:

1. **Numeracao de notas:** o plano propunha criar `13 - Auditoria Completa 2026-06-16.md`, mas a nota 13 ja foi criada como metodo de vistoria. A auditoria viva deve usar uma nova nota, preferencialmente `14 - Auditoria Completa 2026-06-16.md`, para nao sobrescrever o metodo.
2. **Reproducao do 401:** disparar analise autenticada antes da rotacao pode engrossar a quarentena. Se for necessario reproduzir, usar payload minimo/controlado e registrar request_id; caso a evidencia KV ja seja suficiente, evitar gerar novos eventos presos.
3. **`wrangler secret put`:** tratar como escrita critica de producao, mesmo sem alteracao de bundle. Exigir validacao posterior do Worker e do verificador.
4. **Replay:** antes de re-submeter eventos quarentenados, confirmar formato real das chaves KV e caminho de ingestao no bundle `api/v4.9.111.js`. Nao reconstruir evento por inferencia.
5. **Version drift:** conferir separadamente `app/index.html`, `app/version.json`, `app/deploy_zip/version.json`, apex e www. `producao/` e standalone-worker sao legado e nao devem contaminar a auditoria.
6. **Regra 6:** fechar lacuna da auditoria anterior verificando explicitamente `<strong>` global sem `color`.

## Credenciais por endpoint (auditoria 24 — P2)

Não confundir `routine_key` (rotinas Claude: `listar_*`, `dados_para_analise`, `receber_analise`) com `admin_senha` (painel admin e telemetria).

| Endpoint / action | Credencial | Observação |
|---|---|---|
| `tel_test` | **`admin_senha`** | Escrita sintética no Analytics Engine; **não** aceita `routine_key` (403) |
| `admin_health_check` | `admin_senha` | Estado interno, providers, KV |
| `admin_verificar_evento` | `admin_senha` | Smoke do verificador Haiku |
| `action=uso` (`visao=debug`) | `admin_senha` | Confirmar `tel_test_sintetico` ~60s após `tel_test` |
| `listar_emissores_prioritarios` | `routine_key` | Rotina matinal/noturna |
| `dados_para_analise` / `receber_analise` | `routine_key` | Ingestão scheduled-tasks |

**Ritual pós-deploy (telemetria):** `POST {action:"tel_test", admin_senha:"..."}` → aguardar ~60s → `POST {action:"uso", admin_senha:"...", visao:"debug"}` e buscar evento `tel_test_sintetico`. Ver `AGENTS.md` regra de telemetria.
