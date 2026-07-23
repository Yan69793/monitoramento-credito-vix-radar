---
data: 2026-07-23
tipo: referencia
tags: [vix-radar, producao, estado-atual]
status: ativo
---

# Estado Atual — VIX Radar

> [!success] 21/07 — Worker v4.9.170 + frontend v201.83. Preditivo lab interno, gate unificado, UI limpa. Ver [[66 - Preditivo lab interno 2026-07-21]].
> [!success] 23/07 — Frontend v201.84: preview de link agora mostra cartão com imagem no WhatsApp e redes. Adicionadas as tags `og:image` (mais `secure_url`/`type`/`width`/`height`/`alt`), `twitter:card=summary_large_image` e `twitter:image` no `index.html`, servindo `og-vix-radar.jpg` (1200x630, 52 KB, composto com a identidade do site) na raiz do Pages. Higgsfield foi descartado por falta de crédito; card feito por composição HTML→Edge headless. Deploy validado (imagem HTTP 200 image/jpeg, HTML com as tags, `CACHE_VERSION=v201.84`), commit `425196b` pushado, sem drift.
> [!success] 23/07 — Worker v4.9.171 em produção (deploy entre 21/07 e 23/07, health confirma `versao:v4.9.171`). Sem drift repo/prod.
> [!info] 23/07 08h30 — **Diagnóstico: dashboard mostra eventos até 21/07 por falta de notícias novas, não por falha de ingestão.** Verificado: Worker saudável, 103/103 emissores com `_last_scanned_at` de 22-23/07, briefing executivo gerado hoje (162 eventos, 44 críticos), distribuição de `data_evento` no KV confirma que o evento mais recente é de 21/07 (Raízen: venda Usina Caarapó; Kora Saúde: assembleia de debenturistas). Noturnas de 21-22/07 e matinal de 23/07 processaram todos os emissores mas não acharam eventos com data 22/07 ou 23/07. Sistema operando normalmente — ausência de notícias corporativas novas no período.

## Versões

| Componente | Versão | Health |
|---|---|---|
| Worker | **v4.9.172** | `ok:true`, kv/telemetria/verificador ok. DEDUPFILA1 fix |
| Frontend | **v201.85** | `CACHE_VERSION=v201.85`, focus-trap 8 dialogs |
| Git | `cf1bffe` (frontend) + worker deploy | prod alinhada |

## Cobertura

| Métrica | Valor |
|---|---|
| Emissores | 103 (universo) |
| Matinal 23/07 | submit_ok=15 (top 15 por EWS), 5 críticos, 150.912 tokens, dreno verif ok |
| Matinal 22/07 | submit_ok=13, 7 críticos, 132k tokens (atrasada, StartWhenAvailable) |
| Noturno 22/07 | submit_ok=92 + 11 SKIP = 103/103, 5 críticos, 468.045 tokens, dreno verif ok |
| Noturno 21/07 | submit_ok=103/103 (SKIP=0), 9 críticos, dreno verif ok |
| Eventos ativos (briefing 23/07 11:14Z) | 162 total, 44 críticos, 111 relevantes, 13 setores. Evento mais recente: 21/07 |
| Criticos ativos (matinal 23/07) | Oncoclínicas, Kora Saúde, Oi, Cosan, Rumo |

## Tasks Scheduler

| Task | Trigger | Status recente |
|---|---|---|
| VIXRadar-Matinal | 10h seg-sex | 23/07 04:39 Result 0 (disparo antecipado via recovery); 22/07 13:16 Result 0 (StartWhenAvailable) |
| VIXRadar-Noturno | 18h diario | 22/07 18:00 Result 0 (submit_ok=92+11 SKIP=103); proximo 23/07 18:00 |
| VIXRadar-Coleta-Volatilidade | ~17h | 22/07 17:02 Result 0; cotacoes sucesso=0 persiste (VOLCOLETA1, ver PENDENCIAS.md) |
| VIXRadar-Verificacao-Async | 10:20 | 23/07 05:03 Result 0 (dreno pos-matinal); 22/07 18:51 Result 0 (dreno pos-noturno) |
| VIXRadar-Export-Historico | 20:45 diario | 22/07 20:47 Result 0; 23/07 previsto 20:45 |

## Infra

| Binding | Status |
|---|---|
| RADAR_KV | ok |
| RATE_LIMITER_DO | ok |
| RADAR_USAGE_EVENTS | ok |
| ESTADO_SEMANA_DO | declarado + usado no bundle (nao exposto no health publico) |
| Providers | 2/2 (Resend + Anthropic) |

## Pendências ativas (topo)

Ver [[PENDENCIAS.md]]. Topo pos auditoria 21/07:

| P | Item |
|---|---|
| P1 | VOLCOLETA1 — coleta sobe com objeto vazio e reporta sucesso (causa raiz isolada, fix pendente) |
| P1 | MONITORCEGO1 — monitor classifica falha da coleta como benigna |
| P2 | METRICSZERO1, VERIFQ-ORFAO1, VERIFINJ1, DEDUPFILA1, ROUTINEKEY-PLAIN1, SPF1, FOCUSTRAP1, REGDRIFT1 |
| P3 | OPENROUTERVIVO (gasto diario recorrente com provider obsoleto), DOCBILL1 (nota 49 sob OAuth) |

## Checklist pós-rotina

Após cada noturna (ou evento de produção significativo), verificar:

- [ ] `03 - Estado Atual.md` — atualizar tabelas de Cobertura e Tasks com dados da execução recém-concluída
- [ ] `03a - Changelog.md` — entrada para deploy, incidente ou resultado anormal da rotina
- [ ] `03b - Infraestrutura.md` — se houve mudança de binding, cron, task ou versão
- [ ] `00 - Índice (MOC).md` — versões de Worker e Frontend batem com o health ao vivo
- [ ] `CLAUDE.md` — tabela de Produção atual reflete os dois componentes

Script de drift: `pwsh ./scripts/check-vault-drift.ps1` compara vault contra health ao vivo e reporta divergências. Execute após cada deploy ou se suspeitar de desalinhamento.

---

*Snapshot gerado em 2026-07-23 06:45 BRT (health ao vivo + logs de rotina). Changelog: [[03a - Changelog]]. Infra: [[03b - Infraestrutura]].*
