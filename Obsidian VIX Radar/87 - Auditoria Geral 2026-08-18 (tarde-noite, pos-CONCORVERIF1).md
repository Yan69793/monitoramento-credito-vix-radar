---
data: 2026-08-18
tipo: auditoria
tags: [vix-radar, auditoria, seguranca, verificador, concorrencia]
status: ativo
---

# Auditoria Geral 2026-08-18 (tarde-noite, pós-CONCORVERIF1)

Readonly, sem deploy, sem alteração de secret. Sessão remota (Claude Code, sandbox sem acesso à máquina Windows local nem à rede de produção via curl direto). Escopo: cobrir o delta de código desde a nota 85 (mesmo dia, manhã) e a lacuna de documentação do incidente `verificador_ok` de ontem à tarde.

## Contexto que faltava no vault

A nota 85 (auditoria geral + preditiva) e a nota 86 (rotação da routine_key) foram escritas com base no estado da manhã de 18/08, health `ok:true` v4.9.195. Na tarde do mesmo dia, sem nenhuma nota registrando, aconteceu o seguinte, reconstruído via GitHub Actions e `git log` nesta sessão:

`canonical-test.yml` falhou duas vezes, 13:04:32Z (10h04 BRT) e 18:53:23Z (15h53 BRT), ambas com a mesma causa: `Health ok=false — fatores: admin_email_ok=true sentry_ok=true verificador_ok=false`. E-mail e Sentry saudáveis, só o verificador. A primeira falha caiu 4 minutos depois do horário padrão da rotina matinal (10h BRT).

A correção saiu em três deploys entre 17h26 e 18h06 BRT do mesmo dia: v4.9.196 (heartbeat da verificação assíncrona), v4.9.197 (CONCORVERIF1, reserva atômica na fila) e v4.9.198 (CHAVEESCOPO1, credencial escopada `REMOTE_VERIFICACAO_KEY`). Depois disso `canonical-test.yml` voltou a passar (run de 01:50:09Z / 22h50 BRT, o mais recente confirmado nesta sessão).

## Causa raiz do incidente de ontem

Desde 18/08 a fila `radar:verif_fila:{data}` passou a ser drenada por duas origens em paralelo: a sessão local do Claude Desktop (10h20/18h20 BRT) e uma nova Claude Code Routine remota (02h/14h BRT), criada para cobrir a janela em que o PC do operador está desligado. `listar_fila_verificacao` sempre foi leitura pura, sem reserva. Com duas origens lendo a mesma fila quase ao mesmo tempo, as duas podiam pegar o mesmo evento, gastar verificação adversarial duplicada e, se os veredictos divergissem, quem confirmasse por último vencia em silêncio — sem log de conflito, sem alerta. Achado de auditoria de código do próprio time em 18/08, não incidente de produção com dado errado confirmado, mas exposição real.

## O conserto, e o que ele não fecha

CONCORVERIF1 adiciona `reservar_itens_fila`, que roda dentro do `EstadoSemanaDO` (mesmo DO que já serializa a fila, FIFO por instância), reserva por 20 minutos, `claimante` registrado. Confirmei nesta sessão que o mecanismo está de fato wired nas instruções das duas rotinas (`routines/claude-desktop/verificacao-async/SKILL.md` Passo 3.5, `ROUTINES-CLOUD.md` Passo 3), não é capacidade morta no Worker. Confirmei também, por grep no `worker.js` inteiro, que `REMOTE_VERIFICACAO_KEY` só abre essas três ações (`listar_fila_verificacao`, `reservar_itens_fila`, `confirmar_verificacao`), nenhuma outra — o escopo mínimo prometido no commit é real.

Fica uma janela residual, P2. A reserva é feita uma vez, para até 20 itens de uma vez, no início da execução. O processamento é serial, até 5 lotes de 4 eventos, até 3 buscas web por evento — plausível passar de 20 minutos num lote cheio com busca lenta. O recheck de segurança antes de `confirmar_verificacao` só é obrigatório quando `protecao_ativa` veio `false` na reserva (DO indisponível). Não cobre reserva que expirou por demora com `protecao_ativa:true`, que é a mesma classe de bug que o commit corrigiu, pela porta dos fundos. Correção proposta: tornar o recheck incondicional, sempre, um HTTP a mais por lote, fecha a janela por completo. Nenhuma guarda automatizada existe ainda para isso além desta nota.

## Outros achados

- **P2 rotina/confiabilidade:** `chore(data): historico 2026-08-18` nunca apareceu no git log até 22h57 BRT, mais de 2h depois do horário de costume (~20h48-20h49, visto em 16 e 17/08 no mesmo dia do export). Não apurável nesta sessão, sem acesso a `logs/routines/` local. Hipótese mais provável: sobreposição com a inversão da junction NTFS relatada na mesma noite em `03 - Estado Atual.md` (12 tarefas agendadas reapontadas). Conferir `FIM:` do Export-Histórico de 18/08 na próxima sessão local.
- **P3 drift cosmético:** comentário de cabeçalho do `api/wrangler.toml` (linha 2) diz `main = v4.9.195`, três versões atrás da diretiva real (linha 536, `v4.9.198.js`). Sem risco de produção, o guard de CI lê a diretiva real. Só engana leitura humana.
- **P2 já aberto, sem mudança:** Merton DD 0/103, ver nota 85. Não re-verificado nesta sessão (exigiria leitura de KV ao vivo, sem acesso daqui).

## Confirmado saudável

- Veracidade da UI: `audit-ui-metrics.mjs` rodado de novo, exit 0, mesmo resultado da nota 85.
- Frontend sem mudança desde v202.10 (15/08).
- `WORKER_V` de produção batendo com o repo pelo próprio guard do `canonical-test.yml` (run de sucesso mais recente, 01:50:09Z), embora eu não tenha rodado o portão de verificação com as próprias mãos nesta sessão.

## Lacunas desta auditoria

- Não consegui rodar `curl` contra `radar-credito-api.prospects-intel.workers.dev`: o proxy de rede desta sessão remota devolve 403 no túnel (confirmado, `recentRelayFailures` do proxy cita esse host). Saúde ao vivo veio só por evidência indireta do GitHub Actions.
- Sem acesso a `logs/routines/` (existe só na máquina Windows local, não versionado).
- Performance e acessibilidade não medidas nesta sessão (sem navegador). P3s de a11y da nota 85 seguem abertos, sem mudança.
- Preditivo, segurança ampla (ASVS completo) e produto/domínio: herdados da nota 85, não reabertos porque nada mudou nesses eixos desde então.

## Proposta de manutenção da skill

`references/audit-matrix.md` ainda não cobre padrão de reserva/lease com TTL em Durable Object (só fala de dual-write e fail-open para a migração KV→DO). CONCORVERIF1 introduz uma classe nova de risco (lease expirado sob carga) que vale um item permanente na matriz da próxima vez que ela for revisada.
