# BLOQUEIO DE CREDENCIAL EXTERNA - auth/cota do VIX Radar

Data da redacao: 2026-09-16. Card: t_57676197 (raiz t_0d05903b).
Branch: mva-provider-agnostic. HEAD medido: 3751ce2.

Este documento registra um bloqueio. Ele NAO decide, NAO propoe alternativa e NAO afirma
disponibilidade. Nenhum valor de token ou de chave aparece aqui: apenas presenca e tamanho.

Procedencia das referencias: as medicoes de branch/HEAD, o estado do Git e as linhas dos tres
arquivos de log citados foram lidos diretamente na redacao desta nota. As demais referencias
`arquivo:linha` vem do relatorio de recon read-only do card t_d0d5700d (comentario 140) e nao
foram remedidas aqui.

## 1. O bloqueio, em uma frase

Quando a assinatura Claude Code Pro atinge o limite de uso e o reset da cota nao cabe no teto de
parede da rotina, NAO EXISTE hoje credencial autorizada que permita a rotina continuar. Fazer a
rotina seguir exigiria credencial externa (credito pago Anthropic) que o repositorio nao autoriza
e que nenhum ajuste de codigo cria. A decisao nao e de engenharia.

## 2. Evidencia medida (mascarada)

Credencial de assinatura - a que existe e esta autorizada:

- `VIXRADAR_LLM_PROVIDER` = `claude-subscription` no escopo User; `Test-VixLlmPermiteClaude`
  libera este valor sem `-ForceClaude` (scripts/lib/vixradar-llm-provider.ps1:65-68).
- `VIXRADAR_ANTHROPIC_AUTH_TOKEN` presente no escopo User, 108 caracteres (valor nunca lido nem
  impresso); lido por `Get-VixAnthropicAuthToken` (scripts/lib/vixradar-claude-auth.ps1:132-146).
- Em 16/09 11:03 o token de assinatura foi ACEITO e a rotina fechou OK (4 aprovados,
  tokens=47069, `auth_escalou=nenhum`): logs/routines/vixradar-verificacao-async_20260916.log:6
  e :10-12. Ou seja: o incidente de auth esta LATENTE, nao ATIVO. O teto de cota continua em pe.

Credencial paga - existe no ambiente, NAO esta autorizada:

- `VIXRADAR_ANTHROPIC_API_KEY` presente no escopo User, 108 caracteres (valor nunca lido nem
  impresso), desautorizada em dois lugares independentes:
  - contrato escrito: CLAUDE.md:231-232 (sob `claude-subscription` a rotina usa o Claude CLI
    nativo, "sem chave Anthropic paga"); governanca repetida em
    scripts/lib/vixradar-claude-auth.ps1:74, :78 e :330;
  - codigo: `Get-VixAnthropicApiKey` devolve `$null` fora de `claude-manual` + `-ForceClaude`
    (scripts/lib/vixradar-claude-auth.ps1:77-80).
- `VIXRADAR_TETO_PAYG_DIARIO` vazio no escopo User => `Test-VixPaygTetoEstourado` = `$true`
  (scripts/lib/vixradar-llm-provider.ps1:250-264).

Gatilho e desfecho:

- Limite da assinatura reconhecido como cota esgotada: `Get-VixWsProbeClassificacao`
  (scripts/lib/vixradar-ambient-check.ps1:118 e :123-126).
- Condicao "reset nao cabe no teto": `Get-VixSessionLimitAcao`
  (scripts/lib/vixradar-claude-auth.ps1:377-388, texto literal em :388).
- Prova real: logs/routines/vixradar-noturno_20260915_dryrun_39464.log:218
  (`reset em 1242.7 min nao cabe no teto de parede (148.4 min disponiveis)`).
- Sem chave paga a assumir, o desfecho e `ALERTA_AUTH` e morte do lote:
  logs/routines/vixradar-noturno_20260915_dryrun_39464.log:219, :223 e :227 (tres escaladas
  forcadas inuteis - o retry artificial medido) e
  logs/routines/vixradar-verificacao-async_20260915.log:33-37.

## 3. Nomenclatura, para nao atribuir procedencia errada

"exit 9004" nao e exit code de script nenhum. 9004 e codigo SINTETICO do vigia diario, atribuido
a linha `ALERTA_AUTH` encontrada no log (scripts/monitor-tasks.ps1:922-933;
scripts/lib/vixradar-watchdog.ps1:164 e :177-195). Os exits reais nos caminhos de auth sao 5
(sem credencial: run_vixradar_varredura.ps1:1070 e :1075; run_vixradar_verificacao_async.ps1:439),
7 (aborto por AuthFailure: run_vixradar_varredura.ps1:1321) e 86 (`BLOQUEADO_SEM_PROVIDER`:
scripts/lib/vixradar-llm-provider.ps1:31 e :148).

Consequencia pratica: "preservar o 9004" significa preservar a LINHA `ALERTA_AUTH` no log, nao
um codigo de saida de processo.

## 4. O que esta bloqueado

- A continuacao da rotina LLM quando a cota da assinatura estoura e o reset fica fora do teto de
  parede. Hoje nao existe segundo caminho autorizado.
- O fallback pago existe no codigo e esta INERTE por decisao, nao por defeito:
  `Get-VixAnthropicApiKey` devolve `$null` e as duas escaladas
  (scripts/lib/vixradar-claude-auth.ps1:340-356 e :391-418) morrem sem chave. Nada a desligar.
- O token de assinatura nao esta quebrado, e regerar token nao resolve cota - a propria linha do
  log diz isso (logs/routines/vixradar-verificacao-async_20260915.log:33-34).
- Trocar de provider nao esta disponivel: segundo o encaminhamento ja registrado no card
  t_0d05903b (comentario de 16/09 12:41), o OpenRouter esta sem chave e com conta zerada, e o
  codex exige habilitacao explicita do chamador.

## 5. O que NAO se propoe aqui

- Comprar credito, abrir conta nova ou ativar PAYG. Nao autorizado e fora do escopo.
- Criar chave nova, segunda conta ou credencial paralela.
- Reativar qualquer fallback pago, inclusive o `-Fallback429 'ChavePaga'` do pre-flight.
- Inventar disponibilidade: nao se afirma "tem cota", "o reset chega" nem "ha plano B".
- Declarar solucao onde ha contorno: cortar o retry reduz chamadas inuteis, mas NAO cria cota.

## 6. Postura operacional adotada

- Fail-closed: sem credencial autorizada, a rotina PARA. Nao ha continuacao degradada silenciosa.
- Deferimento com motivo claro: o lote nao processado e deferido com motivo operacional
  (`limite_sessao_assinatura`; rotulo por causa ja implementado em d8a38ab -
  `Get-VixDeferidoMotivo`, scripts/run_vixradar_varredura.ps1:641).
- Sinal preservado: a linha `ALERTA_AUTH` continua sendo emitida e o monitor continua sintetizando
  o 9004 a partir dela.
- Producao intacta: esta frente nao fez deploy, nao alterou Task Scheduler e nao rodou rotina em
  modo real.

## 7. Encaminhamento

Este documento nao decide e nao propoe alternativa. Ele registra o bloqueio e devolve a decisao ao
operador humano: o que falta nao e codigo, e credencial externa autorizada ou corte de escopo
operacional. Os caminhos mutuamente exclusivos ja foram encaminhados em:

- card t_0d05903b, comentario de 16/09 12:41 (com custo de cada um);
- status/ESTADO.md, item aberto "16/09 (manha), AUTH-VIXRADAR".

Enquanto nao houver decisao escrita do operador, o sistema permanece no comportamento descrito na
secao 6: fail-closed e deferimento com motivo.

## 8. Limites desta nota

- Baseada no recon do card t_d0d5700d e nas medicoes listadas; nao reexecuta teste de patch.
- Nao substitui o diff do patch (card t_03c78e33) nem a verificacao independente (t_93397302).
- Nao afirma nada sobre disponibilidade futura de cota da assinatura.
