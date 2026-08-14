# Glossario de dominio — VIX Radar

Fonte canonica dos termos que aparecem em rotulo de UI, campo de KV, nome de
variavel, prompt de LLM e texto de e-mail. Existe por uma razao concreta: em
2026-07-27 um card da Visao Geral exibia "Cobertura 62%" medindo, na verdade,
"percentual de emissores sem alerta". Backend correto, deploy correto, health
verde, e a tela dizendo o oposto do fato. Ninguem detectou porque nenhum checklist
comparava o **rotulo** com a **formula**.

Regra: **um termo, um significado, em todo o sistema.** Se uma tela precisa de um
conceito que nao esta aqui, o certo e criar um termo novo, nao reusar um existente
com outro sentido.

## Termos reservados

| Termo | Significa exatamente | Nao significa |
|---|---|---|
| **Cobertura** | Fracao do universo efetivamente varrida/analisada, ou rodadas de busca concluidas (`fontes_consultadas`, `_coberturaMin`, `cobertura_nota`) | Emissores sem alerta. Saude do mercado. Disponibilidade do sistema |
| **Emissores** | Contagem do universo monitorado (103) | Emissores com evento. Emissores varridos hoje |
| **Criticos** | Emissores distintos com ao menos um evento `CRITICO` na janela | Contagem de eventos. Severidade de infra |
| **Relevantes** | Emissores distintos com evento `RELEVANTE`, **excluindo** os ja contados como criticos | Total de eventos relevantes |
| **EWS** | Early Warning Score do emissor (faixas: >=61 CRITICO, >=36 ALERTA, >=16 ATENCAO, senao ESTAVEL) | Score preditivo de default |
| **Score preditivo** | Saida do pipeline preditivo (`predictive_v1`, drivers incluindo Merton DD) | EWS |
| **Staleness** | Idade do dado desde a ultima atualizacao real | Tempo desde o ultimo deploy |
| **Varredura** | Execucao de analise sobre o universo (matinal/noturna) | Contagem de alertas encontrados |
| **Sem alertas** | Emissores sem evento CRITICO nem RELEVANTE na janela de 30 dias | Cobertura |
| **Health** | Estado dos bindings e providers do Worker (`ok`, `kv`, `telemetria`, `verificador_ok`) | Saude do mercado de credito |
| **Cobertura ANBIMA** | Disponibilidade da serie no arquivo de precos diario da ANBIMA (db*.txt) para UM emissor. Usado no aviso "Cobertura ANBIMA" do painel do emissor (`app/index.html` ~5486): emissor possui debentures registradas, mas sem preco na fonte ANBIMA | Cobertura do universo varrido (termo reservado "Cobertura" simples). Nunca usar "Cobertura" sem o qualificador "ANBIMA" para esse sentido |

## Colisao perigosa conhecida

"Cobertura" e "critico" existem nos **dois** dominios do produto, com sentidos
diferentes, e essa e a origem mais provavel de rotulo enganoso:

| Dominio | "Cobertura" | "Critico" |
|---|---|---|
| Operacao do sistema | quanto do universo foi varrido | falha que trava a operacao |
| Analise de credito | (nao usar) | evento de credito classificado CRITICO |

Ao rotular qualquer indicador, declarar de qual dominio ele fala. Se o rotulo for
ambiguo entre os dois, ele esta errado.

## Contrato de indicador

Todo numero exibido precisa dos cinco campos abaixo resolvidos. Se algum ficar
vazio, o indicador nao esta pronto para producao.

1. **Rotulo** — termo deste glossario, ou termo novo adicionado aqui.
2. **Formula** — expressao exata, com numerador e denominador explicitos.
3. **Fonte** — de onde vem cada parcela (KV, `op=state`, calculo local, Scheduler).
4. **Janela** — periodo considerado, e se ela e fixa ou segue um filtro da tela.
5. **Faixas** — limiares que mudam cor/selo, e o que cada faixa comunica.

Exemplo preenchido, o card corrigido em 2026-07-27:

- Rotulo: `Sem alertas`
- Formula: `(totalEmissores - criticosAtivos - relevantesAtivos) / totalEmissores`
- Fonte: `EMISSORES` (universo) + eventos de `resultados` e `ARQUIVO_PRE`
- Janela: 30 dias fixos (`JANELA_DIAS`), **nao** acompanha o toggle 7D/30D do grafico ao lado
- Faixas: `>=90` saudavel/verde, `>=70` atencao/ambar, `<70` critico/vermelho

## Como manter

- Termo novo em UI, KV ou prompt entra aqui no mesmo commit.
- `scripts/audit-ui-metrics.mjs` le a lista de termos reservados a partir da
  constante `TERMOS_RESERVADOS`. Ao adicionar termo aqui, adicionar la tambem,
  senao o detector deixa de cobri-lo.
- Divergencia entre este arquivo e o `CLAUDE.md` do projeto e sempre bug de um
  dos dois. Resolver no mesmo ciclo, nunca deixar as duas versoes coexistirem.
