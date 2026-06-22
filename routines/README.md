# Scheduled Routines — VIX Radar (fonte canônica versionada)

> **Por que esta pasta existe.** As rotinas `vixradar-matinal` e `vixradar-noturno`
> são **Scheduled Tasks do Claude Code (desktop)**, não crons do Cloudflare Worker.
> Historicamente os prompts viviam **apenas** em disco no desktop
> (`C:\Users\User\.claude\scheduled-tasks\<nome>\SKILL.md`) — fora do git. Toda
> reinstalação do Claude desktop **zera o registro do agendador** e os SKILL.md
> ficam órfãos, fazendo as rotinas "saírem de lá" silenciosamente
> (incidente 2026-06-15 documentado em `Obsidian VIX Radar/03 - Estado de Produção.md`).
>
> A partir de agora **esta pasta é a fonte de verdade**. Se as rotinas sumirem do
> agendador, reinstale a partir daqui — sem reconstruir prompt do zero.

## O que cada rotina faz

| Routine | Cron (BRT) | Modelo | Universo | Endpoint de saída |
|---|---|---|---|---|
| `vixradar-matinal` | `0 10 * * 1-5` (10h, dias úteis) | Claude Opus | Top 15 por EWS (`listar_emissores_prioritarios` `top_n=15`) | `receber_analise` com `_matinal:true` → `_provedor=claude-opus-routine` |
| `vixradar-noturno` | `0 18 * * *` (18h, diário) | Claude Sonnet 4.6 | 103/103 (`listar_todos_emissores`) | `receber_analise` → `_provedor=claude-sonnet-routine` |

Ambas: para cada emissor → `dados_para_analise` (contexto CVM + histórico) →
9 rodadas de WebSearch (protocolo no SKILL.md) → montam o JSON canônico →
`POST receber_analise`. O gate de verdade graduada do Worker (verificação
adversarial + checagem de data/fonte) decide o que persiste — a rotina **não**
força entrada (Lei Zero: inventar dado é pior que não ter dado).

## Contrato dos endpoints (Worker v4.9.141, autenticação `routine_key`)

Base URL: `https://api.vixradar.com` · método `POST` · `Content-Type: application/json`.
Todos exigem `"routine_key": "<ROUTINE_API_KEY>"` no corpo (403 sem ela).

- `listar_todos_emissores` → `{ ok, total, emissores:[{nome,setor}] }`
- `listar_emissores_prioritarios` `{ top_n }` → `{ ok, total, emissores:[...] }`
- `dados_para_analise` `{ empresa, setor }` → `{ ok, janela_inicio, janela_fim, cvm_documentos, eventos_historicos, contexto_historico, instrumentos_ativos }`
- `receber_analise` `{ empresa, setor, resultado, _matinal? }` → `{ ok, empresa, semana, n_eventos, sem_eventos }`

`resultado` segue o schema JSON da seção "FORMATO JSON" do SKILL.md.

> **Segredo:** `ROUTINE_API_KEY` **não** é versionado. Vive como Wrangler secret
> no Worker e em `memory/credenciais.md` (gitignored). No desktop, a rotina lê a
> chave do ambiente/credenciais — nunca cole em texto claro neste repo.

## Como reinstalar no agendador (executar no Claude **desktop**)

> Este ambiente remoto (Claude Code na web) **não** tem as ferramentas
> `create_scheduled_task` / `list_scheduled_tasks` — elas só existem no Claude
> desktop, onde o agendador roda. Os passos abaixo são para a máquina do operador.

1. Confirmar o estado atual: `list_scheduled_tasks` (se vier vazio, o registro foi zerado).
2. Para cada rotina, `create_scheduled_task` com:
   - **name**: `vixradar-matinal` / `vixradar-noturno`
   - **schedule (cron)**: `0 10 * * 1-5` / `0 18 * * *` (timezone America/Sao_Paulo)
   - **model**: Opus (matinal) / Sonnet 4.6 (noturno)
   - **prompt**: o conteúdo integral do `SKILL.md` correspondente desta pasta.
3. Validar: `list_scheduled_tasks` deve mostrar as 2 `enabled:true` com `nextRunAt`.
4. Smoke manual (opcional): rodar a rotina uma vez e confirmar `receber_analise`
   retornando `ok:true` para ≥1 emissor.

Após reinstalar, registrar no Obsidian (`03 - Estado de Produção.md`) data/hora,
`nextRunAt` e qualquer mudança de horário (regra operacional do projeto).
