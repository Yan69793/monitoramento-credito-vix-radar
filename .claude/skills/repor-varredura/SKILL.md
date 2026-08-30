---
name: repor-varredura
description: >
  Repoe varredura de dias perdidos no VIX Radar, quando um dia util nao teve
  rotina de analise (sem log com FIM em logs/routines/) ou o feed ficou preso em
  data antiga (max data_evento do estado defasado). Detecta o gap, monta alvos de
  credito datados na janela perdida com verificacao de fonte real, submete via
  receber_analise e confirma que o max data_evento avancou. Use quando o feed de
  noticias do frontend parar, quando houver dia util sem varredura (app fechado,
  task travada), quando uma auditoria apontar replay de dias, ou quando quiser
  garantir que a reposicao de varredura perdida nao volte a acontecer.
date: 2026-08-29
---

# Repor Varredura Perdida

Repoe analise de emissores de dias em que a varredura nao rodou. Nasceu do
incidente REPOSIC1 (29/08/2026): o feed ficou preso em 25/08 porque 28/08 nao teve
rotina nenhuma (app do Claude Desktop fechado) e a passada seguinte re-ancorou o
desenvolvimento novo em fato antigo, sem criar evento datado na janela.

## Quando usar

- Dia util sem `logs/routines/vixradar-noturno_*.log` (ou matinal/verificacao) com linha `FIM:`.
- Feed do frontend preso em data antiga, com fato real de credito na janela ausente do estado.
- Pedido de replay de dias ou reposicao de varredura.

## Fluxo

### 1. Detectar gap

- Listar `logs/routines/vixradar-*.log` das ultimas duas semanas, conferir quais dias uteis nao tem `FIM: submit_ok`.
- Conferir o max `data_evento` do estado: POST `dados_para_analise` por emissor (routine_key), ou `listar_plano_rotina`. Sem acesso ao KV, `op=state` exige JWT, nao usar.

### 2. Montar alvos (com verificacao de fonte REAL)

- Para cada emissor da carteira com contexto recente (ou todos se a janela for curta), WebSearch de fatos de credito datados na janela perdida: rating, default, recuperacao, M&A, captacao, corte/upgrade, vencimento.
- **Regra de ouro: conferir a data real da fonte no HTML.** A busca web alucina datas. REPOSIC1 quase entrou com "Moody's reafirma Petrobras 27/08" que era artigo de 2015 no pt.org.br, e "Fitch eleva Petrobras 26/08" que era de 2025. Baixar a pagina e procurar `article:published_time`, `datePublished`, `<time datetime>`.
- Preferir, nesta ordem: URL com data no path (`/2026/08/27/...`, imune ao fetch do validarDatasFontes), dominio da lista confiavel do Worker (exame.com, infomoney.com.br, valor.globo.com, estadao.com.br, moneytimes.com.br, braziljournal.com, neofeed.com.br, poder360.com.br), dominio de agencia de rating (moodys.com, fitchratings.com, spglobal.com; aceitos com verificacao forcada mesmo com fetch bloqueado).
- **Emitente fora da carteira de 103 nao entra**: o receber_analise devolve 400 "empresa fora de EMISSORES_LISTA". Conferir o nome canonico em `EMISSORES_LISTA` antes de montar o payload.

### 3. Executar

- Montar payload em JSON com shape de rotina: `[{empresa, setor, provedor, resultado:{empresa, setor, sem_eventos, cobertura_nota, fontes_consultadas, eventos:[{classificacao, titulo, data_evento, fonte_primaria, tags, impacto_credito, memo_*, _confianca}], _tier:"FULL", _rotina_v2:true}}]`.
- `data_evento` = data do fato na janela, mesmo em continuacao de saga conhecida (ex: nova decisao judicial da Braskem em 28/08 vira evento datado 28/08, nunca dobra no protocolo de 24/08).
- `classificacao` em CRITICO/RELEVANTE/ECO. CRITICO entra na fila de verificacao assincrona (fluxo normal, verifica em 02h/14h BRT).
- Rodar: `powershell.exe -File scripts/repor-varredura.ps1 -EnvioDireto -PayloadPath <json>`. Log em `logs/routines/repor-varredura_YYYYMMDD.log`, termina com `FIM: submit_ok=N`. Exit 0 se todas ok, 1 se alguma falhou.

### 4. Verificar

- Conferir max `data_evento` avancou para a janela: POST `dados_para_analise` por emissor, olhar `eventos_historicos`. REPOSIC1 confirmou Braskem 28/08, Oncoclínicas 27/08, Multiplan 27/08, Petrobras 26/08.
- Evento descartado aparece como `removidos_pre_verificador` na resposta do POST. Trocar a fonte e re-submeter (dedup por `data_evento|empresa|fonteBase` nao bloqueia).

### 5. Registrar

- Linha `FIM: submit_ok=N` no log ja cobre o registro local.
- Se o gap revelar causa raiz nova (task travada, app fechado, re-ancoragem), registrar em `Obsidian VIX Radar/PENDENCIAS.md` e `status/ESTADO.md` com correcao + causa raiz + guarda, e conferir se a skill de auditoria geral precisa de guarda nova.

## Scripts e arquivos

- `scripts/repor-varredura.ps1` — submissao via receber_analise (routine_key do registro User), padrao Submit-Analise da noturna.
- `scripts/repor-varredura-prompt.md` — prompt de reposicao para passada via Claude CLI (regra anti-ancoragem).
- `scripts/repor-varredura-payload-2026-08-28.json` — payload de exemplo da primeira reposicao.

## Regras

- Nunca confiar em resumo de busca para datar um fato; a data sai da fonte (meta/datePublished/datetime no HTML) ou da URL.
- Fonte com data no path ou dominio confiavel do Worker tem chance alta de sobreviver ao validarDatasFontes; fonte qualquer com fetch bloqueado e descartada.
- Nao submeter fato para emissor fora de `EMISSORES_LISTA`.
- Reposicao e escrita no estado corrente (mesma semana), `data_evento` so filtra e ordena.
