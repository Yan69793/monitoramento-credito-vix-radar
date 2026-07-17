# PENDENCIAS.md — VIX Radar

**Atualizado:** 2026-07-17 ~17:00 BRT | **Produção:** Worker v4.9.164, Frontend v201.76, health ok, verificador_ok true

## Síntese executiva

1. **Sistema operacional, sem drift.** Worker v4.9.164, Frontend v201.76, health `ok:true`, bindings todos true, verificador_ok true. Drift repo/prod zerado (canonical-test verde desde 15/07).
2. **Crise de staleness monitorada:** 79/103 emissores stale >48h (última varredura 13/07). Causa: matinal cobre só top 15 EWS, noturna de 16/07 processou 103/103 (submit_ok=103) mas timestamps de emissores SKIP/null não foram atualizados. Noturna 17/07 (16:35 BRT, 0 SKIP) deve resolver.
3. **Rotinas ativas:** Matinal 17/07 OK (19 emissores, 5 CRITICO, hard cap 180k). Noturna 17/07 em execução (103 emissores, 0 SKIP). Verificador async operacional com mutex + token budget (commit d329510).
4. **Monitor-TaskScheduler:** Falso positivo 0x41301 corrigido (commit 37e7e2f).
5. **VIXRadar-AgendaSemanal:** Desabilitada desde 13/07 (credit balance too low). Aguarda decisão do operador.
6. **Working tree:** Limpo (commits d329510, e6d1261, 37e7e2f). Só bundles legacy não trackeados em `api/`.

---

## Pendências abertas

| ID | Sev | Área | Achado | Ação |
|----|-----|------|--------|------|
| RACEKV1 | P1 | Backend / dados | Escrita concorrente sem lock em `radar:estado:{semana}` (KV sem CAS). Design pronto (DO write-serializer ou chave por empresa). | Sessão dedicada |
| HDASH1 | P1 | Backend / segurança | `op=health-dashboard` aceita senha admin via querystring GET | Migrar para JWT admin/POST |
| ALRT1 | P1 | Backend / e-mail | `dispararAlertaCritico` não checa `prefs.newsletter`. Se `EMAIL_ALERTAS_FAVORITOS` não setado, broadcast total. | Confirmar env var + corrigir filtro |
| SPF1 | P2 | DNS / deliverability | `send.vixradar.com` em softfail `~all` vs raiz `-all`. Hardcoded em script. | Atualizar script + DNS |
| CLEANAGG1 | P2 | Rotinas / governança | Cleanup aggressive apaga logs/métricas de todos os dias anteriores (retenção real = 1 dia) | Aggressive deve poupar `*.log`/`*_metrics_*.json` |
| FOCUSTRAP1 | P2 | Frontend / acessibilidade | Modal `role="dialog"` não retém foco (falha WCAG 2.4.3 confirmada ao vivo) | Trap de Tab + foco inicial |
| PRED2 | P3 | Ingestão / dados | Chaves com case divergente em `radar:estado:2026-W28`. Causa raiz identificada (CASEKEY1). | Limpeza manual do KV |
| P-CVM | P3 | Dados / CVM | `admin_corrigir_datas_cvm_kv` em lote. Requer admin_senha. | Operador executar via painel |
| E-MT | P3 | Email | Confirmar se `email_modo_teste` ativado. Requer admin_senha. | Operador verificar |

---

## Resolvido desde 2026-07-13

| ID | Data | O que |
|----|------|------|
| STATELEAK1 | 13/07 | KV com 125 chaves em results vs 103 emissores (22 resíduos mojibake). Fix v4.9.153. |
| CHUNK1 | 13/07 | Split-IntoChunks devolvia lotes de 1 emissor (bug array-unwrapping PowerShell). Fix `return ,$chunks`. |
| MIG1 | 13/07 | 3 scripts migrados pay-per-token → assinatura Claude Code. |
| MAT1 | 13/07 | Matinal parada 3 dias por saldo -US$1,21. Resolvido com MIG1. |
| DEF1 | 13/07 | Noturna 12/07 estourou hard cap. Resolvido com CHUNK1 + MIG1. |
| XSSEVT1 | 16/07 | `renderEventoCard` sem `esc()`. Fix deployado v201.76 (commit 10568a9). |
| PRED3 | 16/07 | 16 dos 22 CNPJs sem match resolvidos (commit 6cb1790). |
| ANOMPROMO1 | ~15/07 | Anomalia promovida reaparecia no cron seguinte. Fix em v4.9.152+, deployado na cadeia. |
| RLADMIN1 | ~15/07 | Rate limit fail-open em login/registrar. Fix em v4.9.152+, deployado. |
| CASEKEY1 | ~15/07 | `receber_analise` gravava chave sem case-fold. Fix em v4.9.152+, deployado. |
| RETRYDROP1 | 13/07 | Noturno descartava resultados pagos em retry auth-failure. Fix no disco. |
| VERIFMUTEX1 | 17/07 | Dreno de verificação sem mutex com 3 gatilhos concorrentes. Fix commit d329510. |
| Monitor 0x41301 | 17/07 | Monitor-TaskScheduler reportava SCHED_S_TASK_RUNNING como erro. Fix commit 37e7e2f. |
| DRIFT1 | ~15/07 | `app/version.json` v201.74 vs prod v201.75. Resolvido com deploy v201.76. |
| Bundle drift | 15/07 | Bundle saiu do .gitignore, canonical-test verde (commit a2e7d84). |

---

## Histórico resolvido (compacto, pré-13/07)

- v4.9.150 (11/07): Mojibake read path + briefing fix + preditivo quick wins
- v4.9.148 (07/07): admin_mercado POST-only, zscores_anbima auth, tel() fix
- v4.9.147 (07/07): z-scores ANBIMA no pipeline EWS
- v4.9.143 (20/06): listar_plano_rotina, cascade externa obsoleta
- v4.9.142 (18/06): admin_mercado auth, email_modo_teste
- Incidente 15/06: ANTHROPIC_API_KEY inválida cegava verificador. Secret rotacionado.
- v4.9.109 (14/06): cron duplicado, CLAUDE.md rewrite

---

## Próximos passos priorizados

| P | Ação | Ref |
|---|------|-----|
| P0 | Confirmar que noturna 17/07 completou 103/103 e timestamps atualizados | Staleness |
| P0 | Operador revisar e aprovar commit d329510 (protocolo RESULTADO + token budget + mutex) | Working tree |
| P0 | Operador decidir sobre VIXRadar-AgendaSemanal (desabilitada desde 13/07) | Agenda |
| P1 | Resolver RACEKV1 (escrita concorrente sem lock) | KV |
| P1 | Corrigir HDASH1 (senha admin via GET) | Segurança |
| P1 | Corrigir ALRT1 (filtro de alertas) | E-mail |
| P2 | Hardening SPF send.vixradar.com para `-all` | DNS |
| P2 | Corrigir CLEANAGG1 (retenção de logs) | Rotinas |
| P2 | Corrigir FOCUSTRAP1 (trap de foco em modais) | A11y |
| P3 | Limpar chaves duplicadas por case no KV (PRED2) | Dados |
