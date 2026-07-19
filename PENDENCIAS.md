# PENDENCIAS.md — VIX Radar

**Atualizado:** 2026-07-18 (auditoria completa, achados 17/07 confirmados ao vivo) | **Produção:** Worker v4.9.164, Frontend v201.76, health ok, verificador_ok true

## Síntese executiva

1. **Sistema operacional, sem drift.** Worker v4.9.164, Frontend v201.76, health `ok:true`, bindings todos true, verificador_ok true. Drift repo/prod zerado (canonical-test verde desde 15/07).
2. ~~**Crise de staleness monitorada**~~ **RESOLVIDA** — snapshot pós-noturna confirmado (`logs/monitor-tasks/staleness_pos-noturna_20260717-220053.json`, 17/07 22:00 UTC): 103/103 fresh_le24h, stale_24_48h=0, stale_gt48h=0, idade_max=3.8h. FIN1-REV materializado.
3. **Rotinas ativas:** Matinal 17/07 OK (19 emissores, 5 CRITICO, hard cap 180k). Noturna 17/07 completou 103/103 (0 SKIP, confirmado por snapshot pós-noturna). Verificador async operacional com mutex + token budget (commit d329510).
4. **Monitor-TaskScheduler:** Falso positivo 0x41301 corrigido (commit 37e7e2f).
5. **VIXRadar-AgendaSemanal:** Desabilitada desde 13/07 (credit balance too low). Aguarda decisão do operador.
6. **Working tree:** `api/v4.9.165.js` (novo) + `api/wrangler.toml` (modificado) prontos para o fix RACEKV1, não commitados nem deployados, aguardando aprovação do operador. Fora isso, limpo (commits d329510, e6d1261, 37e7e2f); só bundles legacy não trackeados em `api/`.

---

## Pendências abertas

| ID | Sev | Área | Achado | Ação |
|----|-----|------|--------|------|
| RACEKV1 | P1 | Backend / dados | Escrita concorrente sem lock em `radar:estado:{semana}` (KV sem CAS), confirmado no código vivo (`persistirResultadoCompartilhado`/`mesclarEventoVerificado`/`retratarEventoRejeitado`/`rodarSweepRevalidacao`, 4 funções, 9 call sites). **Fix pronto em `api/v4.9.165.js` + `wrangler.toml` (não deployado)**: Durable Object `EstadoSemanaDO` (1 instância por semana) serializa as 4 funções via fila de promises (FIFO real); as originais viraram `*_Interno` sem alteração de corpo; wrappers com mesmo nome roteiam pelo DO com fail-open (binding ausente/erro → cai para `*_Interno` direto, mesma janela de hoje, nunca descarta o dado). Validado: `node --check` limpo + 8 asserções isoladas (`scratchpad/test_estado_semana_do_queue.mjs`: FIFO sob concorrência, fila não emperra após falha, fail-open preserva dado). Não validado ainda: binding real em produção (exige deploy + migration `v2`). | Operador aprovar deploy de v4.9.165 (`pwsh ./scripts/deploy-worker.ps1 -Version v4.9.165`); rollback trivial (`main=v4.9.164.js`, migration nova fica inerte se revertido) |
| HDASH1-RES | P3 | Backend / segurança | Registro estava desatualizado desde v4.9.151. Handler atual (`api/v4.9.164.js:15200-15213`) usa só `_exigeJwtAdmin`; testado ao vivo (18/07): `senha`/`admin_senha` por querystring retornam 401 em todos os casos. `handleUso` ainda lê `searchParams.get("senha")` (linha 5181) mas é código morto (único call site pré-valida via POST body). | Nenhuma. Considerar remover o fallback morto de `handleUso` por higiene (não é vulnerabilidade). |
| ALRT1-RES | P3 | Backend / e-mail | Parte P1 (broadcast total sem filtro quando `EMAIL_ALERTAS_FAVORITOS` ausente) **já corrigida em v4.9.163/164** — confirmado ao vivo no bundle (`selecionarDestinatariosAlerta`, `api/v4.9.164.js:4840-4867`), os dois caminhos agora checam `prefs.alertas===false` simetricamente. Residual documentado no próprio código: `prefs.newsletter` não governa alerta crítico (decisão de produto deliberada, não bug). | Operador decidir se alerta crítico deve respeitar `prefs.newsletter` (hoje trata como canal independente) |
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
| ALRT1 (broadcast) | 17/07 (confirmado 18/07) | Fallback sem `EMAIL_ALERTAS_FAVORITOS` fazia broadcast total sem checar `prefs.alertas`. Fix v4.9.163/164, confirmado ao vivo no bundle. Residual movido para ALRT1-RES (P3, decisão de produto). |
| Staleness 79/103 | 17/07 (confirmado 18/07) | Noturna 17/07 (0 SKIP) reescreveu `_last_scanned_at` de todos. Snapshot pós-noturna: 0 stale >24h. |
| HDASH1 | v4.9.151 (confirmado 18/07) | Senha admin via querystring GET em `health-dashboard`. Fix real desde commit `5cff1cc` (11/07); `PENDENCIAS.md` carregou como aberto por 5 versões. Testado ao vivo: 401 em todas as tentativas de bypass. |
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
| P0 | Operador aprovar deploy de v4.9.165 (fix RACEKV1, ver detalhe acima) | KV |
| P2 | Hardening SPF send.vixradar.com para `-all` | DNS |
| P2 | Corrigir CLEANAGG1 (retenção de logs) | Rotinas |
| P2 | Corrigir FOCUSTRAP1 (trap de foco em modais) | A11y |
| P3 | Limpar chaves duplicadas por case no KV (PRED2) | Dados |
