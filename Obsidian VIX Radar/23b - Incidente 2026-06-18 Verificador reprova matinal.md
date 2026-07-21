---
tipo: incidente
data: 2026-06-18
componente: Worker v4.9.139 — receber_analise / verdade graduada
severidade: media-alta
status: diagnosticado (sem correção de código — comportamento esperado do gate)
---

# Incidente 2026-06-18 — Varredura matinal: eventos críticos não persistidos (gate de verificação)

## Contexto
Run autônomo da rotina `vixradar-matinal` (10h BRT, dia útil). Universo: top 15 EWS via
`listar_emissores_prioritarios`. Processados 15/15 emissores em 5 grupos paralelos
(9 rodadas WebSearch cada). Semana ISO corrente: **2026-W25**. Janela do Worker: 2026-05-19 a 2026-06-18.

## Resultado da persistência (n_eventos confirmado no POST)
| Emissor | Persistiu | Obs |
|---|---|---|
| Oi | 3 (2 CRIT, 1 REL) | eventos vindos do contexto já verificado (conf 0.95-0.98) |
| CSN | 2 REL | recompra + venda ativos infra |
| Light | 2 REL | RJ relatório + AGE aumento capital ~22/06 |
| Cosan | 1 (de 2) | 1 dedup contra estado existente (rating S&P) |
| Simpar | 5 | Fitch reafirma BB-; BNDESPAR opção JSL |
| Aegea | 3 (1 CRIT) | **Fitch rebaixa para B+** (qualidade contábil, alav ~5x) |
| Eneva | 2 | 6º ciclo ANP; aumento capital imaterial |
| Vibra | 3 | resgate antecipado VBBR14 (~R$779mi) |
| EcoRodovias | 1 REL | Acordo Global PR homologado |
| MRV | 1 ECO | prévia operacional maio |
| **Oncoclínicas** | **0** | reprovado no gate — ver causa raiz |
| **Kora Saúde** | **0** | reprovado no gate — ver causa raiz |
| **Raízen** | **0** | fora do universo `EMISSORES` do Worker |
| **BRK Ambiental** | **0** | único item datado na janela era research/ECO |
| **Pão de Açúcar (GPA)** | **0** | evento CRÍTICO sem fonte primária CVM na janela |

10/15 com eventos persistidos; 5/15 com n_eventos:0.

## Causa raiz confirmada (Onco / Kora — os mais graves)
`receber_analise` (`api/v4.9.139.js:14838-14841`) passa TODOS os eventos por
`validarEVerificar` (`:9626`) → `validarDatasFontes` (`:9684`, faz `fetch` real da
`fonte_primaria` e extrai data; descarta fora da janela) → `verificarEventosBatch`
(verificação adversarial via Anthropic Haiku). Só `aprovados` são persistidos;
`sem_eventos = (aprovados.length === 0)`. **Não é bug de cadastro nem de "slot W25 não
inicializado"** (esses foram diagnósticos incorretos dos subagentes — refutados: payloads
de Onco/Kora são byte-estruturalmente idênticos ao do Oi, mesmas 7 chaves, 3 eventos cada).

Os eventos de Onco/Kora foram reprovados porque as `fonte_primaria` eram fracas:
- Onco: página de **listagem genérica de RI** (`ri.grupooncoclinicas.com/.../material-facts/`) + Bloomberg Línea + InvestNews — sem documento primário com data confirmável.
- Kora: portais de research/imprensa (euqueroinvestir, infomoney, investidor10) + datas fora da janela (RExtrajudicial **04/05 < 19/05**; AGD **23/06 é futura**).

O verificador adversarial não confirmou o fato a partir dessas URLs → descarte. Comportamento
**esperado e correto** do pipeline de verdade graduada. Não foi forçada entrada (Lei Zero).

## Evidência objetiva
- Reenvio bruto: `{"ok":true,"empresa":"Oncoclínicas","semana":"2026-W25","n_eventos":0,"sem_eventos":true}`.
- Estrutura JSON idêntica ao Oi (Node parse: 3 eventos, chaves iguais) — só o conteúdo/fontes diferem.
- Código lido: `:14823-14857` (handler), `:9626-9720` (gate).

## Impacto
4 dos casos de crédito mais graves do radar (todos em distress real, confirmados por imprensa)
**não entraram no painel hoje**: Oncoclínicas (RE iminente / quebra de covenant ~R$3,3bi),
Kora Saúde (Fitch C(bra), default iminente, RExtrajudicial deferida), Raízen (RExtrajudicial
R$64,7bi, 75% adesão), GPA (edital RE, deságio até 70%). Painel subreporta risco nesses nomes.

## Correção / próximos passos
1. **Reanálise com fonte primária forte** (Onco/Kora/GPA): localizar o link DIRETO do documento
   CVM RAD (`frmDownloadDocumento.aspx?...numProtocolo=...`) de cada FR/edital, não a página de
   listagem. JSONs preservados em `scans\onco.json`, `scans\kora.json` para reenvio.
2. **Raízen**: avaliar inclusão em `EMISSORES` (decisão de produto — emissor em RE de R$64,7bi é
   material). Análise em `scans\raizen.json`. Exige edição do bundle.
3. **Melhoria de pipeline** (backlog): o gate descarta silenciosamente; expor no retorno do POST
   os `rejeitados` + `veredicto.motivo` (já existe em `verificarEventosBatch`) para a rotina
   distinguir "sem eventos" de "eventos reprovados" e poder reprocessar com fonte melhor.

## Observação de ambiente (não-bloqueante)
Hook `PostToolUse:Write` aponta para `check-sql-files.py` inexistente — falha em toda escrita,
polui o output dos subagentes. Não afetou esta tarefa. Corrigir config do plugin.
