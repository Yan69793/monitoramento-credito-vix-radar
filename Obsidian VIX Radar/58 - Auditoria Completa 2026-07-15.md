---
data: 2026-07-15
tipo: auditoria
tags: [vix-radar, auditoria, operacional]
status: ativo
---
# Auditoria Completa — VIX Radar (2026-07-15)

## Síntese executiva
Sistema saudável, sem drift repo/produção. Achado central: mecanismo `FIN1` (deployado em v4.9.156-158, ainda não documentado no vault) preserva `_last_scanned_at` deliberadamente para emissores com cobertura de busca insuficiente (`INCONCLUSIVO`) — isso faz o gate clássico de staleness (`audit-routine-staleness.ps1`) reportar 82/103 emissores "stale >24h" como falso positivo de severidade, quando na verdade é o comportamento pretendido do novo mecanismo de escalonamento a tier FULL.

## Versões e drift
| Camada | Repo | Produção | Drift? |
|---|---|---|---|
| Worker | v4.9.158 (`api/wrangler.toml` → `main`) | v4.9.158 (`GET /` → `versao`) | Não |
| Frontend | v201.75 (`app/version.json`) | v201.75 (`vixradar.com/version.json`) | Não |

Repo com `git status` sujo (26 arquivos modificados + vários untracked) — nenhum deles no bundle Worker ativo (`api/v4.9.158.js` não está na lista de modificados); mudanças concentram-se em scripts PS1, docs Obsidian, `marketing/linkedin/`, `data/historico/`. Sem impacto em produção.

## Achados

### MÉDIO — RESOLVIDO nesta sessão (v4.9.159, deploy ~10:52 UTC)
- **[STALE-GATE1]** O gate `scripts/audit-routine-staleness.ps1` não distinguia emissor genuinamente sem atualização de emissor `_status:"INCONCLUSIVO"` (cobertura de busca abaixo do mínimo por tier, `_last_scanned_at` preservado de propósito pelo fix `FIN1`). Rodado às 06:58 BRT: `stale_24h:82/103`, `max_stale:37h`, sem distinção.
- **Correção:** Worker `v4.9.159.js` (`montarPlanoRotina`) passou a expor `status`/`inconclusivo` por emissor no retorno de `listar_plano_rotina` (aditivo, sem mudar lógica de tier). `audit-routine-staleness.ps1` reescrito para separar `stale_24h_real` de `stale_24h_inconclusivo`; só o primeiro conta para o gate/severidade ALTO. `SKILL.md` do `vix-radar-audit` atualizado (linhas 170/179/190).
- **Validação pós-deploy (10:52 UTC / 07:49 BRT):** `GET /` → `versao:v4.9.159 ok:true`. Gate recalibrado: `stale_24h_total:82` → **`stale_24h_real:7` + `stale_24h_inconclusivo:75`** — 75 dos 82 eram INCONCLUSIVO por design, só 7 são staleness genuína.
- **Achado novo (P2, decorrente da recalibração, não corrigido nesta sessão):** 7 emissores com staleness real >24h e sem justificativa de INCONCLUSIVO: PRIO, Bradesco, Klabin, Suzano, JBS, Brisanet, Engie Brasil Energia (todos `Última análise: 2026-07-13T21:0x`, ~37,8h). Requer investigação em sessão futura — fora do escopo desta recalibração.

### BAIXO
- Nenhum novo achado de segurança/auth nesta rodada — POST anônimo segue 401 (`{"erro":"Autenticação necessária."}`), health público OK.

## Validação em produção
| Teste | Resultado | Evidência |
|---|---|---|
| `GET /` | `ok:true, versao:v4.9.158, bindings{kv,rate_limiter,telemetria}:true, providers_configurados:2/2, verificador_ok:true` | curl bruto, HTTP 200, 0.71s |
| `vixradar.com/version.json` | `v201.75` | curl bruto, HTTP 200 |
| POST anônimo `{}` | `401 Autenticação necessária` | curl bruto |
| `dados_para_analise` (Assaí, Hidrovias) | ambos `Última análise: 2026-07-13` apesar de processados em 14/07 | curl autenticado via `routine_key`, ver achado STALE-GATE1 |
| Gate staleness (`audit-routine-staleness.ps1`) | `total:103, stale_24h:82, max_stale:37h, presos_data:0, tiers{SKIP:0,LIGHT:79,FULL:21,AUDIT:3}` | output bruto do script |

## Lacunas
- Não testado: `admin_health_check`, `admin_verificar_evento` (exigem senha admin, fora do escopo desta rodada — auditoria focou em versão/drift/staleness a pedido do usuário em sessão com múltiplas auditorias de projetos diferentes).
- Não testado: Playwright/frontend E2E, headers CSP, Task Scheduler local (rotinas matinal/noturno já cobertas indiretamente via logs de 14/07).
- Não confirmado se a run de 15/07 10h (matinal) já ocorreu — checagem feita às 06:58 BRT, antes do horário programado.

## Próximos passos
- **P1** — Recalibrar `audit-routine-staleness.ps1` para não contar `INCONCLUSIVO` como staleness crítica (ou documentar a mudança de semântica).
- **P2** — Registrar `FIN1-4`/`DIV1-5`/fix `60e2f67` em `03 - Estado de Produção.md` (mudança já em prod, sem nota própria).
- **P3** — Confirmar depois das 10h/18h de hoje se a cobertura FULL/AUDIT está de fato convergindo (21 FULL + 3 AUDIT hoje) e não presa em INCONCLUSIVO perpétuo.
