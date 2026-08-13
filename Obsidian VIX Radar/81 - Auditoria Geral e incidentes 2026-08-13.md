---
data: 2026-08-13
tipo: auditoria
tags: [vix-radar, auditoria-geral, incidente, auth, xss, gh-actions]
status: ativo
---

# 81 — Auditoria Geral e incidentes 2026-08-13

Auditoria geral (skill vix-radar-general-audit) a pedido do operador para o gate
de autorização. Veredito: **degradado**. Núcleo sólido (sem drift repo/prod,
bindings verdes, auth/RL/CORS corretos, veracidade da UI exit 0), mas health
oficial `ok:false` e três canais de proteção degradados ou cegos.

## Achados do dia

### P0 — Cascade de IA parado (AUTHWEEK1)

- Sonda OAuth em processo limpo: `429 "You've hit your weekly limit · resets Aug 15, 8am (America/Sao_Paulo)"`.
- Sonda chave paga (`VIXRADAR_ANTHROPIC_API_KEY`, registry User): `400 "Credit balance is too low"`.
- Consequência: dreno de verificação, matinal e noturno abortam limpo (exit 5)
  até 15/08 08h BRT ou recarga da chave paga. Noturno 13/08 18h00 vai abortar.
- Causa provável do estouro: 12/08 teve três drenos de verificação (14h27,
  18h28 e o do noturno) somando ~2M tokens além do noturno de 103 emissores.
- Guarda proposta: a sonda já detecta o 429, falta notificar (monitor ou
  check-gh-actions-health) e alertar o operador antes do próximo ciclo.

### P1 — Fila de verificação + dreno dependente do Claude Desktop

- Fila com 11 itens às 18h41 de 12/08. Dreno de hoje (10h20) não rodou, matinal
  (10h00) não rodou: sessões agendadas do Claude Desktop não dispararam.
- Sweep de órfãos (>48h) roda no health check e mata os itens antigos:
  health volta verde ~14/08 21h30Z mesmo sem dreno.
- Item estrutural continua aberto: segundo dreno pós-noturno ou trigger
  independente do Desktop.

### P1 — ADMIN_PASSWORD divergente entre GitHub Actions e Worker (GHWL1)

- frescor-check 403 desde 10/08 (último sucesso 09/08 03:19Z), scan-emergencia
  falhando desde 09/08. Os dois guardas de staleness da ingestão ficaram cegos
  por 4 dias sem detecção. daily-status-email continua verde.
- Evidência: log GH `curl: (22) ... error: 403`; teste local com senha errada
  reproduz o mesmo 403 `{"ok":false,"erro":"Acesso negado."}`; senha em posse do
  operador funciona (login admin 09/08, rotação demo via API 11/08).
- Correção: operador atualiza `secrets.ADMIN_PASSWORD` no GitHub Actions.
- Guarda nova: `scripts/check-gh-actions-health.ps1` (lista a última run dos 3
  workflows, exit = nº de problemas). Aviso do `apply-security-rotation.ps1`
  reforçado. Secrets não são gerenciáveis via PAT fine-grained, publicação
  automática segue impossível sem token clássico.

### P1 — BOM UTF-8: FECHADO hoje

- Varredura completa encontrou 35 .ps1 com não-ASCII sem BOM (o P1 de 12/08
  listava 12). 18 regravados com BOM byte a byte, 17 já tinham. Parse test
  PowerShell 5.1: 64/64 OK. Commit `9764a3d`.

### P2 — XSS Market Overview: FECHADO no código

- Frontend: módulo v100 (`app/index.html:4051`) interpola `e.titulo` e
  `e.empresa` crus em `innerHTML`. Corrigido com helper de escape `x()` nos 4
  pontos (timeline, tabela, onclick via `data-emp`/`dataset`). CACHE_VERSION
  v202.8 com `?v=202.8` alinhado em todos os módulos ES. **Deployado hoje**
  (v202.8, validado em produção: version.json apex, CACHE_VERSION, bytes dos
  assets).
- Worker: `sanitizarPayloadRadar` agora faz strip de tags HTML em `titulo` e
  `empresa` no write path (XSSV100-FIX1). Commit `01f95bd`. **Deploy pendente**:
  `deploy-worker.ps1:285` reprova `ok:false` pós-deploy; aguardar health verde
  (~14/08 21h30Z) e rodar `deploy-worker.ps1 -Version v4.9.193`.

### Solicitações de acesso (pergunta do operador)

- Telemetria AE 10 dias: última solicitação 07/08 10:04 (WhatsApp admin enviado
  10:04:39). Zero desde então. Zero `registrar_email_admin_erro` no período.
- KV `user:*`: 33 contas (20 aprovadas, 13 rejeitadas, 0 pendentes).
- Nada aguardando aprovação. Painel funcional (429 corrigido no v4.9.191,
  admin-bootstrap 200 em produção).

### Push bloqueado (P1)

- 8 commits locais à frente do origin/main (desde o FIMREAL1 de hoje 13h13).
  Tokens disponíveis (manager e gh PAT fine-grained) sem Contents write:
  `remote: Write access to repository not granted`. Operador precisa `gh auth
  refresh -s repo` ou push manual. Até lá, canonical-test vai acusar drift de
  frontend (GitHub ainda vê v202.7) na próxima run.

## Veredito para o gate de autorização

Não sustentável como 100% hoje. Bloqueadores: cascade de IA parado (dado
congelado em 12/08 18h28 até 15/08 ou recarga), health `ok:false`,
frescor/scan-emergencia cegos, push pendente. Itens do operador: recarregar
chave paga OU aguardar reset de sábado; atualizar secret do GH; destravar push.

## Fechamento do mesmo dia (15h10-15h50 BRT)

- **Cascade destravado:** chave paga recarregada pelo operador 15h12, sonda
  exit 0. Dreno 15h16-15h27: fila=11, 9 aprovados, 2 rejeitados, 223k tokens.
  Health `ok:true verificador_ok:true`.
- **Worker v4.9.193 no ar:** deploy validado (`ok=true kv=true telemetria=true
  sentry_ok=true`). XSS fechado nas duas camadas (frontend v202.8 + strip no
  write path).
- **Push destravado:** gh reautenticado via device flow OAuth (escopos repo/
  read:org/gist). Merge do `cbda7d1` (sessão paralela) resolvido mantendo as
  duas visões. 11 commits no origin, repo sincronizado.
- **Secret GH publicado:** senha admin validada contra o Worker (103
  emissores), publicada via `gh secret set`. frescor-check disparado
  manualmente: **success em 11s**. canonical-test: **success em 11s**. Os dois
  guardas cegos há 4 dias voltaram a ver produção.
- **DPAPI reparado:** a recuperação local da credencial admin estava quebrada
  (chave inválida, provável troca de senha do Windows pós-criptografia).
  Recriptografado com o valor atual, `Get-VixAdminCredential.ps1` volta a
  funcionar.
- **Solicitação nova 15h12:** aprovada (WhatsApp admin enviado 1s depois),
  KV 34 usuários, 0 pendentes.
- **Pendências residuais:** assinatura segue no limite semanal até 15/08 08h
  (rotinas rodam por chave paga); noturno 18h00 depende da sessão do Desktop
  (com chave paga, roda mesmo no limite); dreno único dependente do Desktop
  segue no backlog; senha admin em texto na conversa da sessão, considerar
  rotação futura da ADMIN_PASSWORD por higiene.
