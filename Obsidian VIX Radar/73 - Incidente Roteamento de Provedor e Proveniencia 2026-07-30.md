---
data: 2026-07-30
tipo: incidente
tags: [vix-radar, provedor, proveniencia, seguranca, roteamento]
status: parcialmente-resolvido
---

# 73 - Incidente de Roteamento de Provedor e Proveniencia de Dados

> [!danger] Achado central
> `HKCU:\Environment` tinha `ANTHROPIC_BASE_URL` apontando para um agregador que **aceita nome de
> modelo Claude e devolve outro modelo, sem erro e sem aviso**. As rotinas carimbavam
> `claude-sonnet-4-6` e `claude-haiku-4-5-20251001` no log e recebiam `deepseek-v4-flash`.

## Evidencia (teste direto na API, 30/07)

Tres requisicoes ao endpoint do registry, lendo o campo `model` que o **servidor** retorna:

```
PEDIDO: claude-haiku-4-5-20251001  ->  SERVIDOR DEVOLVEU model=deepseek-v4-flash
PEDIDO: claude-sonnet-4-6          ->  SERVIDOR DEVOLVEU model=deepseek-v4-flash
PEDIDO: deepseek-v4-flash          ->  SERVIDOR DEVOLVEU model=deepseek-v4-flash
```

Autoidentificacao do modelo **nao serve como prova**. Perguntado via `claude -p`, o modelo
respondeu "Anthropic, claude-haiku-4-5-20251001", porque o system prompt do Claude Code ja
afirma isso. So o campo `model` da resposta HTTP e confiavel.

## Origem da configuracao

Nao estava espalhada por projeto. Tres lugares apenas.

| Local | Conteudo | Acao |
|---|---|---|
| `HKCU:\Environment` | `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, 4 overrides de modelo, `CLAUDE_CODE_SUBAGENT_MODEL` | Removidos. Config preservada como `DEEPSEEK_API_KEY` e `DEEPSEEK_BASE_URL` |
| `~/.claude/settings.json` | `"model": "deepseek-v4-pro[1m]"` | Removido |
| `Jornada Interior/.claude/settings.local.json` | bloco `env` com base URL e modelos DeepSeek | **Pendente**, ver abaixo |

## Impacto

1. **Alegacao do produto.** `product.md` linha 23 e `marketing/linkedin/README.md` linha 38
   afirmam "IA, Anthropic Claude". A landing e a apresentacao de 21 slides enviada ao Bradesco
   BBI em 27/07 vendem isso. Enquanto o roteamento esteve ativo, a afirmacao nao se sustentava.
2. **Verificacao adversarial.** O desenho pressupoe um segundo modelo desafiando o primeiro.
   Haiku e Sonnet colapsavam no mesmo `deepseek-v4-flash`, ou seja o modelo se auditando.
   Esse e o diferencial numero um em `positioning.md` e tem slide proprio na apresentacao.
3. **Telemetria de custo.** O CLI calcula `total_cost_usd` com tabela Anthropic para chamada
   servida por outro provedor. Todo numero de token e custo no vault foi medido com regua errada.
4. **Subagente, WebSearch e WebFetch** morriam nesta maquina. Bate com a nota de memoria sobre
   rotina exigir ambiente higienizado.

## Proveniencia dos dados (marcacao pedida pelo operador)

- **Certo:** o noturno de 30/07 disparado pelo Task Scheduler as 18:00:04, concluido 18:13:32
  com exit 0, rodou com o env do registry, portanto foi servido por `deepseek-v4-flash`.
  103 emissores. Log carimba `Lote haiku-1 [claude-haiku-4-5-20251001]` ate `Lote sonnet-7
  [claude-sonnet-4-6]`.
- ~~**A apurar:** execucoes anteriores. Ate 30/07 os scripts apagavam `ANTHROPIC_API_KEY`
  antes de chamar `claude -p`, forcando OAuth, o que provavelmente batia na Anthropic real.~~

> [!warning] Correcao de 30/07 20h. A frase acima estava errada e subestimava a janela.
> Apagar `ANTHROPIC_API_KEY` **nao muda o destino da requisicao**. Quem decide o destino e
> `ANTHROPIC_BASE_URL`, que apontava para o agregador. Forcar OAuth muda a credencial, nao
> a rota.

Tres fatos que juntos fecham o ponto:

1. O registry tinha tambem `ANTHROPIC_AUTH_TOKEN`, que o CLI usa como bearer contra a base
   URL configurada. Remover so a `ANTHROPIC_API_KEY` deixava esse caminho de pe.
2. O commit `74a92a7` (30/07 17:23) restaurou pay-per-token justamente porque **o OAuth
   estava expirando no Task Scheduler**. Essa e a premissa do proprio commit.
3. O log de 30/07 registra lotes concluidos as 16:43, 16:48, 16:57, 17:01, 17:04, 17:12 e
   17:19, todos anteriores as 17:23. Se o OAuth estava vencido, um lote que **teve sucesso**
   as 16:43 nao pode ter sido servido por OAuth.

Ou seja, no periodo em que o sistema se dizia "assinatura", as chamadas continuavam indo
para o agregador. A janela de contaminacao vai de quando `ANTHROPIC_BASE_URL` foi criada no
registry ate 30/07 19:10 (commit `4615b58`), e nao apenas o noturno das 18:00.

**Nao afirmar cobertura Claude para nenhuma data anterior a 30/07 19:10.** A data de criacao
das variaveis do registry continua nao determinada, e sem ela o inicio da janela fica aberto.

## Correcao aplicada em 30/07

Os tres scripts (`run_vixradar_noturno_claude.ps1`, `run_vixradar_matinal_claude.ps1`,
`run_vixradar_verificacao_async.ps1`) passaram a:

1. Fixar `$env:ANTHROPIC_BASE_URL = 'https://api.anthropic.com'` antes de cada invocacao,
   sem herdar do ambiente.
2. Limpar `ANTHROPIC_AUTH_TOKEN`.
3. Aceitar somente chave com prefixo `sk-ant-`, via `VIXRADAR_ANTHROPIC_API_KEY`. Chave de
   agregador e recusada e registrada no log.

Sintaxe validada nos tres. Backup do registry e do settings global no scratchpad da sessao.

**Causa raiz:** roteamento de provedor em variavel de ambiente global. Qualquer processo da
maquina herdava, incluindo Task Scheduler e o app desktop, cada um resolvendo de um jeito.
**Guarda:** provedor fixado dentro do script, nunca herdado. Configuracao de provedor barato
fica por projeto, nunca em `HKCU:\Environment`.

## Verificacao de 30/07 22h (pos-correcao)

O teste que expos o problema foi refeito lendo o campo `model` da resposta HTTP:

```
PEDIDO: claude-haiku-4-5-20251001  ->  SERVIDOR DEVOLVEU model=claude-haiku-4-5-20251001
PEDIDO: claude-sonnet-4-6          ->  SERVIDOR DEVOLVEU model=claude-sonnet-4-6
```

`HKCU:\Environment` nao tem mais nenhuma variavel `ANTHROPIC_*` nem override de modelo.
Restaram `DEEPSEEK_API_KEY` e `DEEPSEEK_BASE_URL`, que nao roteiam nada sozinhas.
`~/.claude/settings.json` sem bloco `env` e sem chave `model`.

`claude -p --model claude-sonnet-4-6` em `powershell.exe -NoProfile -NonInteractive`, que
e a condicao do Task Scheduler, retornou exit 0 em 4,1s com custo calculado em tabela
Anthropic e `service_tier: standard`. Correcao commitada em `4615b58`.

## Politica de credencial (30/07 20h, commit `5c8dc4f`)

A escolha deixou de ser fixa. `Initialize-VixClaudeAuth` sonda a assinatura uma vez por
execucao e so cai na chave paga se o OAuth nao responder. A sondagem e gratuita nos dois
desfechos, porque roda com `ANTHROPIC_API_KEY` limpa: ou passa pelo OAuth, ou falha na
autenticacao consumindo 0 token. Nunca toca a API paga.

Se o OAuth vencer no meio de uma rotina longa, `Invoke-VixClaudeAuthEscalate` troca para a
chave paga e os lotes seguintes continuam. Antes disso a rotina inteira morria a partir do
lote em que o token vencia, que foi 29-30/07.

Toda execucao agora carimba no log qual credencial serviu:

```
AUTH: assinatura (OAuth) respondeu - rodando sem custo por token.
AUTH: assinatura indisponivel (sessao OAuth expirada ou deslogada). Caindo para chave paga.
```

Isso e proveniencia verificavel, que e exatamente o que faltava neste incidente. A logica
saiu dos tres scripts e vive em `scripts/lib/vixradar-claude-auth.ps1`, motivo pelo qual a
correcao de provedor precisou ser escrita tres vezes.

**Estado em 30/07 22h:** esta maquina nao tem credencial de assinatura. `claude auth status`
devolve `loggedIn: false, authMethod: none`. Duas tentativas de `claude login` e
`claude setup-token` ao longo da noite nao completaram, e a mensagem do CLI migrou de
`OAuth session expired` para `Not logged in`, ou seja limparam a sessao vencida sem criar
uma nova. As tres rotinas rodam em chave paga ate haver login.

> [!note] Pista falsa que custou tempo, registrada para nao se repetir
> `~/.claude/.credentials.json` cresceu para 10 KB e passou a ser reescrito com frequencia,
> o que parecia login bem-sucedido. Nao era. As chaves de topo do arquivo sao **so**
> `mcpOAuth`, com 25 entradas de conectores MCP. O bloco `claudeAiOauth` nao existe mais.
> Tamanho e mtime desse arquivo **nao servem** como sinal de login. Use `claude auth status`.

## Pendencias

- [x] **P0.** ~~Definir `VIXRADAR_ANTHROPIC_API_KEY`~~. Definida, prefixo `sk-ant-api03`,
      validada contra a API real em 30/07 22h. A matinal de 31/07 as 10:00 tem chave.
- [ ] **P0.** Rotacionar a chave Anthropic exposta em transcricao de sessao em 30/07.
      **Nao verificavel daqui:** a chave configurada tem formato correto e funciona, mas
      nao da para saber se e a nova ou a exposta. Confirmar no console da Anthropic.
- [ ] **P1.** Rotacionar a chave DeepSeek, tambem exposta em 30/07.
- [ ] **P1.** Reprocessar o noturno de 30/07. **Decidido em 30/07 22h: fazer, mas na
      assinatura**, portanto bloqueado no `claude login`. Dois pre-requisitos mecanicos:
      mover `logs/routines/vixradar-noturno_20260730.log` para
      `vixradar-noturno_20260730.contaminado.log`, senao a idempotencia le as 95 linhas
      `OK|` e pula tudo (aconteceu tres vezes, sempre com `tokens=0`); e confirmar na linha
      `AUTH:` do log que a execucao saiu mesmo pela assinatura antes de deixar os lotes
      rodarem. Meta de 500k tokens, teto de 700k.
- [ ] **P1.** Decidir o reprocessamento de datas anteriores a 30/07, agora que a janela de
      contaminacao se mostrou maior do que a nota registrava.
- [ ] **P2.** `Jornada Interior/.claude/settings.local.json` perdeu a chave que herdava do
      registry. Atualizar para OpenRouter ou tornar a config autossuficiente.
- [ ] **P2.** Revisar se `product.md`, `README.md` de marketing, landing e apresentacao precisam
      de correcao retroativa, a depender da janela de contaminacao apurada.

## Ver tambem

[[03 - Estado Atual]] · [[PENDENCIAS.md]] · [[70 - Incidente Encoding e Compatibilidade PowerShell 5.1 2026-07-27]]
