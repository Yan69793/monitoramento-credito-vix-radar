---
data: 2026-07-15
tipo: incidente
tags: [vix-radar, incidente, researchdown1, oncoclinicas, classificacao]
status: resolvido
---
# Incidente RESEARCHDOWN1 — evento CRITICO da Oncoclínicas rebaixado para RELEVANTE

**Data:** 2026-07-15
**Gatilho:** operador reportou, em estado de urgência ("clientes reclamando"), que a notícia da InfoMoney sobre a Oncoclínicas (aprovação do pedido de recuperação extrajudicial, R$5,1bi) "não saía no sistema".

## Diagnóstico (systematic-debugging, Fase 1 completa antes de qualquer fix)

O evento **estava** no sistema (`radar:estado:2026-W29`, lido diretamente do KV de produção) — não era ausência. A rotina noturna de 14/07 (lote sonnet-2, 18:13) analisou corretamente e classificou **CRITICO**. O verificador assíncrono aprovou o evento em seguida (`veredicto:"APROVADO"`, `confianca:0.75`, citando a própria URL da InfoMoney como fonte válida). Mas o registro final em produção mostrava **classificacao:"RELEVANTE"** para esse evento específico (os outros 2 eventos da Oncoclínicas na semana permaneceram CRITICO).

### Causa raiz (rastreada linha a linha, sem hipótese não verificada)

`sanitizarPayloadRadar()` (`api/v4.9.160.js:9621-9650`) roda dentro de `receber_analise`, **antes** de qualquer evento entrar na fila de verificação assíncrona:

```js
var _td = classificarTipoDadoFonte(ev?.fonte_primaria);
var _cls = ev?.classificacao;
if (_td === "research" && _cls === "CRITICO") {
  _cls = "RELEVANTE";  // [sanitizar][RESEARCH_REBAIXADO]
}
```

`classificarTipoDadoFonte()` derivava `"research"` de `EXA_ALLOWED_DOMAINS_RESEARCH` — lista criada para restringir o **plugin de busca Exa/OpenRouter**, cascade obsoleta desde v4.9.108 (ver `CLAUDE.md` do projeto), e reaproveitada por engano como sinal de credibilidade de fonte para gate de severidade. A lista mistura, sob o mesmo rótulo:

- **Imprensa financeira mainstream:** infomoney.com.br, valor.globo.com, moneytimes.com.br, seudinheiro.com, br.advfn.com, istoedinheiro.com.br, bpmoney.com.br
- **Research/opinião de casa (sell-side):** btgpactual.com, conteudos.xpi.com.br, suno.com.br, nordinvestimentos.com.br, analisa.genialinvestimentos.com.br, riconnect.rico.com.vc

O evento da Oncoclínicas tinha `fonte_primaria=br.advfn.com` → `tipo_dado="research"` → rebaixamento automático, silencioso (só `console.log`, sem telemetria, sem UI). O rebaixamento acontece **antes** do verificador assíncrono ver o evento, e **nada reverte** a classificação depois — mesmo com o verificador aprovando com a URL da InfoMoney (também na lista "research") como fonte válida. Confirmado por leitura completa do caminho `confirmar_verificacao` → `aplicarCorrecaoVerificador` (só atua quando `veredicto==="CORRIGIR"`, não é o caso — descartado como causa) → `mesclarEventoVerificado` → `enriquecerEvento` (não toca `classificacao`).

**Efeito colateral confirmado:** o mesmo `tipo_dado` alimenta o toggle `vix_hide_research` do frontend (`app/index.html:~5165`) — quem usa esse toggle podia ter a notícia **totalmente oculta**, não só rebaixada.

**Escala do problema:** sistêmico, não isolado à Oncoclínicas — qualquer evento CRITICO de qualquer um dos 103 emissores citando InfoMoney/Valor/ADVFN/MoneyTimes/SeuDinheiro/IstoÉDinheiro como fonte primária sofre o mesmo rebaixamento silencioso. Consistente com a curiosidade de que esses mesmos domínios **já eram tratados corretamente como "imprensa financeira BR"** em `DOMINIOS_RATING_AGENCY_SET` (comentário v4.9.157, ~30 linhas abaixo no mesmo arquivo) — só não nesta função.

## Fix (v4.9.161, commit local `a64ed21`, deploy pendente de autorização)

Novo `DOMINIOS_IMPRENSA_FINANCEIRA_SET` (7 domínios de imprensa), checado em `classificarTipoDadoFonte` **antes** de `DOMINIOS_RESEARCH_SET` → retorna `"imprensa"`. `EXA_ALLOWED_DOMAINS_RESEARCH`/`DOMINIOS_RESEARCH_SET` não tocados (continuam válidos para o plugin Exa dormente e para as 6 casas de research/opinião genuínas, que continuam sujeitas ao rebaixamento — correto, opinião de casa é evidência mais fraca que fato relatado). Escopo: 1 novo `Set` + 1 linha em `classificarTipoDadoFonte`. Validado isolado com 14 casos (`scratchpad/test_classificar.mjs`, 14/14 OK) antes de gerar o bundle. `node --check` limpo.

Reforço complementar nas 4 skills de rotina (matinal/noturno × haiku/sonnet): eventos de RE/RJ/default/rebaixamento devem checar `rad.cvm.gov.br` por Fato Relevante do próprio protocolo antes de fechar só com fonte de imprensa — reduz dependência de qualquer heurística de domínio para esses eventos.

**Não deployado nesta sessão** — aguardando autorização explícita do operador (regra do projeto). Bundle e diff completo prontos: `api/v4.9.161.js`, `api/wrangler.toml`.

## Correção do dado já gravado em produção

Deploy de código **não recalcula histórico** — o registro já persistido da Oncoclínicas continua RELEVANTE até correção pontual. Script pronto (`scratchpad/corrigir-evento-onco-critico.ps1`) para o operador rodar com `admin_senha` própria (`admin_upsert_analise`): substitui apenas o evento afetado (dedup por `data_evento+empresa+fonte_primaria` casa exatamente o registro existente), preserva os outros 2 eventos da semana intocados, corrige `classificacao→CRITICO` e `tipo_dado→imprensa`, e grava `_correcao_manual` para auditoria.

## Pendência aberta

- Deploy do v4.9.161 (autorização pendente).
- Execução do script de correção pontual pelo operador (só ele tem `admin_senha`).
- Verificar, depois do deploy, se há outros eventos de outros emissores atualmente RELEVANTE que deveriam ser CRITICO pelo mesmo motivo (não auditado nesta sessão — escopo ficou restrito ao caso reportado; considerar `admin_sweep_revalidacao` ou varredura manual como P1 de acompanhamento).
