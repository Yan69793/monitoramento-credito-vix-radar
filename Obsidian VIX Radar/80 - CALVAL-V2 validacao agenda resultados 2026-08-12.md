---
data: 2026-08-12
tipo: feature
tags: [vix-radar, agenda, resultados, validacao-fonte, worker, frontend]
status: encerrado
---

# 80 - CALVAL-V2: validacao de fonte da Agenda de Divulgacao de Resultados (2026-08-12)

## Pedido

O Yan reportou datas erradas por dias ou ate meses na Agenda de Divulgacao de
Resultados e pediu correcao definitiva com 13 regras (fonte primaria obrigatoria,
nunca sobrescrever oficial com secundaria, cross-check, metadados, 5 status de
validacao, nao inferir datas, trimestre fiscal, aliases de empresa, revalidacao
automatica, gate de publicacao, auditoria, testes, menor impacto).

## Causa raiz

O modulo agenda nao tinha nenhuma validacao de fonte:

1. A rotina `vixradar-agenda-semanal` aceitava qualquer data de WebSearch sem
   distinguir RI/CVM/B3 de InfoMoney/Moneytimes/XP.
2. `mergeTrimestresCalendario` (worker.js:4030) fazia `Object.assign` cego:
   qualquer override substituia o anterior, de qualquer origem.
3. A base estatica `CALENDARIO_RESULTADOS_V1` (2026-05-09) carregava datas com
   `fonte: "estimado_historico"` e nota "Confirmar no RI" como fallback permanente.
4. `agendaBuildPersistir` emitia todo trimestre como evento `resultado` sem olhar
   fonte nem status. O overlay v201.23 nao renderizava status nenhum: data
   estimada aparecia visualmente identica a data oficial.

## O que foi implementado (Worker v4.9.192, frontend v202.7)

Funcoes novas no `api/src/worker.js` (bloco CALVAL-V2 apos `obterCalendarioEmpresa`):

- `classificarTierFonte`: `ri | cvm | b3 | corporativo | secundario | nenhum`,
  fail-closed (dominio desconhecido nunca vira oficial).
- `calcularStatusValidacaoTrimestre`: os 5 status, sempre computado no Worker,
  `status_validacao` vindo no POST e ignorado com console.warn.
  - sem data -> NAO_INFORMADO; estimado -> PENDENTE sempre
  - divulgado/agendado: oficial -> CONFIRMADO_OFICIAL; 2+ secundarias
    independentes -> CONFIRMADO_CROSSCHECK; 1 secundaria so -> PENDENTE
  - divergencia com fonte oficial -> DIVERGENTE (oficial vence, registrada)
  - divergencia so entre secundarias -> PENDENTE (regra 3 do pedido)
- `migrarTrimestreParaV2`: metadados completos (fonte primaria/secundaria + urls,
  fontes_secundarias, divergencias, data_ultima_verificacao, nivel_confianca,
  observacao_divergencia, antes_ou_depois_do_fechamento, trimestre_fiscal,
  data_divulgacao_confirmada, auditoria). Nunca muta a base estatica.
- `aplicarRegraNaoSobrescrever`: fonte oficial nunca e substituida por secundaria
  divergente; submeter sem data nao apaga data ja conhecida.
- `registrarAuditoriaMudancaData`: trilha {timestamp, data_anterior, data_nova,
  fonte, motivo}, cap 10 entradas.
- `AGENDA_ALIASES` + `resolverAliasAgenda`: AXIA Energia -> Eletrobras. Emissor
  desconhecido e rejeitado com 400 no `atualizar_calendario_emissor`.
- `confrontarDivulgacoesCVM`: datas passadas confrontadas com o documento efetivo
  no CVM (DFP/ITR em `cvm:documentos`), roda no cron diario da agenda (04:00 UTC)
  e no rebuild admin. So promove, nunca rebaixa.
- Gate em `agendaBuildPersistir`: evento `resultado` so sai `confirmado:true` com
  CONFIRMADO_*; PENDENTE/DIVERGENTE emitem com `confirmado:false` e NAO_INFORMADO
  nao gera evento. Cobertura ganhou `confirmados`/`pendentes`.
- `listarEmissoresCalendarioStale`: motivos novos `confirmar_divulgacao`,
  `revalidar_proximo`, `sem_data_oficial` + `trimestres_alvo`. Prioridade:
  confirmar_divulgacao > revalidar_proximo > sem_calendario > sem_data_oficial
  > stale_Nd (sem isso os ~80 emissores sem calendario escondiam a revalidacao
  dentro do limite de 30).

Frontend `app/index.html` (v201.7 badge, v201.24 overlay, CACHE_VERSION v202.7):
selo de status_validacao no badge do painel e no overlay da agenda, nao
confirmado em ambar, DOM API apenas (LEI ZERO preservada).

Rotina: `C:\Users\User\.claude\scheduled-tasks\vixradar-agenda-semanal\SKILL.md`
atualizado: ordem obrigatoria RI -> CVM -> B3/comunicado -> secundarias so para
cross-check, campos de metadados no POST, sem data publicada envia periodo sem
`data_prevista`, trimestre fiscal verbatim, priorizar motivos novos do stale.

## Testes

- `api/test/agenda-validacao.test.mjs` (vitest, CI `worker-tests.yml`): 9 casos
  cobrindo as 6 categorias pedidas + gate + stale. Verde no commit `989b7b9`.
- Harness local `tests/system-final-regressions.mjs` estendido (Node puro, roda
  na maquina): tier de fonte, migracao, merge protegido, auditoria, aliases,
  cvmDocConfirmaDivulgacao, regressao da contagem dupla de secundaria.
  `REGRESSION_OK calendario_overrides calval_v2 merton_inputs selic_source build_contract`.
- CI pegou 3 defeitos reais durante o desenvolvimento: rebuild via GET
  (dispatch de op e GET-only), prioridade do stale escondendo revalidacao, e
  contagem dupla de fonte secundaria (1 fonte virava "2 fontes" e CROSSCHECK).

## Deploy

- Worker v4.9.192 (Version ID 1106b33b) via `deploy-worker.ps1`. A validacao
  final do script acusou `verificador_ok:false`: 5 itens da fila de verificacao
  enfileirados em 2026-08-11T23:33Z cruzaram o SLA de 20h (VERIFSLA1) as 19:33Z
  de 12/08, durante a janela do deploy. Backlog pre-existente (o dreno async
  diario deixou 16 itens por teto de token), sem relacao com CALVAL. Worker
  validado manualmente: versao viva, kv/rate_limiter/telemetria ok, providers
  2/2, admin_email_ok e sentry_ok true, zero excecoes no Observability apos o
  deploy.
- Frontend v202.7 via `deploy-pages.ps1` (validado: version.json apex, CACHE_VERSION,
  asset byte a byte). Gates pegaram 2 desalinhamentos de cache-buster que seriam
  deployados errados (index.html e modulos admin com ?v=202.6).

## Efeito esperado e honesto

As datas herdadas da base estatica (2026-05-09, `estimado_historico`) passam a
aparecer como NAO CONFIRMADO (PENDENTE) ate a rotina semanal revalidar com fonte
primaria. A cobertura aparente de "Resultados" cai no curto prazo: e o
comportamento exigido pelas regras, nao regressao. O cron 04:00 UTC de 13/08
reconstroi `agenda:eventos:v1` ja com os campos novos.

## Pendencias registradas

- Fila de verificacao com 5 itens >20h derrubando `verificador_ok` (pre-existente).
  O dreno async de 13/08 (10:20 BRT) deve zerar; se o teto de token persistir,
  revisar o chunk/teto no `run_vixradar_verificacao_async.ps1`.
- ~25 `.ps1` de rotina modificados (paths FREQUENTE + BOM) continuam sem commit:
  o lint-staged reprova 12 deles (sintaxe PS 6/7 em scripts 5.1 e BOM removido
  na sessao de 11/08). Precisa de sessao dedicada, nao entra no escopo CALVAL.
- Token `CLOUDFLARE_API_TOKEN` sem permissao Cloudflare Pages: Edit (deploy de
  Pages caiu para OAuth do wrangler, aviso do proprio script).
- Backlog: aumentar frequencia da rotina local agenda-semanal para 2x/semana
  (Dom+Qua) para cumprir plenamente a revalidacao diaria da regra 9.
- Backlog: `postAdmin` enviar `Authorization: Bearer` (pendencia da nota 79).
