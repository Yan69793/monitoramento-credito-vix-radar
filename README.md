# Radar de Crédito Privado (VIX Radar)

Sistema de inteligência de crédito privado com IA. Monitora 103 emissores de renda fixa
no Brasil e classifica eventos por criticidade (CRÍTICO / RELEVANTE / ECO / RUÍDO),
eliminando a varredura manual da equipe de gestão. Roda 100% em Cloudflare — sem servidor
próprio, sem banco de dados, sem manutenção de infraestrutura.

---

## Acesso

| Ambiente | URL |
|---|---|
| Frontend | https://vixradar.com |
| Worker (API) | https://api.vixradar.com |
| Worker (workers.dev) | https://radar-credito-api.prospects-intel.workers.dev |

---

## Fontes Vivas (não editar diretamente — são bundles de produção)

```
api/
  v4.9.229.js        ← bundle Worker em produção (bundle Wrangler, NÃO editar)
  wrangler.toml      ← config de deploy: main, bindings, cron triggers, custom domain

app/
  index.html         ← frontend canônico (CACHE_VERSION=v202.35)
  _headers           ← headers HTTP do Pages (cache, segurança)
  _routes.json       ← roteamento do Pages
  deploy_zip/        ← artefato pronto para deploy (index.html + _headers + _routes.json + version.json)
```

**Deploy Worker:** usar o canônico `pwsh scripts/deploy-worker.ps1` (commita e pusha, evitando o drift repo/produção de julho). Chamada direta exige `--no-autoconfig`: `cd api && npx wrangler deploy <bundle>.js --config wrangler.toml --no-autoconfig --compatibility-flags nodejs_compat --name radar-credito-api`

**Deploy Pages:** `npx wrangler pages deploy ./app/deploy_zip --project-name=radar-credito`

---

## Estrutura do Repositório

```
.github/workflows/   ← CI: canonical-test.yml (health check a cada 6h)
Obsidian VIX Radar/  ← memória documental canônica (estado de produção, auditorias, decisões, PENDENCIAS.md)
docs/                ← documentação técnica de referência
memory/              ← notas de sessão (memory/credenciais.md é gitignored)
scripts/             ← automações de deploy
CLAUDE.md            ← protocolo operacional obrigatório para IAs e devs
AGENTS.md            ← regras permanentes de desenvolvimento
```

### Diretórios fora do fluxo operacional

```
producao/            ← LEGADO v30/v40. NUNCA deployar — ver ATENCAO-NAO-DEPLOYAR.md
_historico/          ← arquivo histórico de sessões e snapshots (gitignored)
archive/             ← versões arquivadas de código (não deployar)
vixradar/            ← clone/espelho antigo (não deployar)
research/            ← pesquisa e referências externas
```

---

## Stack Técnico

| Componente | Tecnologia |
|---|---|
| Frontend | HTML/CSS/JS puro (sem framework, sem build step) |
| Backend | Cloudflare Workers (JavaScript, bundle Wrangler) |
| Storage | Cloudflare KV (`RADAR_KV`) |
| Rate Limiting | Cloudflare Durable Object (`RATE_LIMITER_DO`, SQLite) |
| Telemetria | Cloudflare Analytics Engine (`RADAR_USAGE_EVENTS`) |
| IA inline | `claude-haiku-4-5-20251001` via Anthropic API (Pulso manual) |
| IA em lote | Haiku + Sonnet 4.6 (matinal top 15 e noturno 103/103) via Scheduled Tasks — nenhuma rotina usa Opus |
| Email | Resend (`boletim@vixradar.com`) |
| Deploy | Cloudflare Pages + Workers + Wrangler CLI |

---

## Versões em Produção

| Componente | Versão | Confirmada |
|---|---|---|
| Worker `radar-credito-api` | v4.9.229 | 2026-09-01 |
| Frontend `vixradar.com` | v202.35 | 2026-08-30 |
| Emissores monitorados | 103 empresas / 13 setores | — |

---

## Para Desenvolvedores e IAs

Leia [`CLAUDE.md`](CLAUDE.md) antes de qualquer ação — contém protocolo obrigatório de diagnóstico,
regras invioláveis de deploy, e o mapa completo do sistema.

Decisões operacionais, estado de produção e histórico de deploys estão em
[`Obsidian VIX Radar/03 - Estado Atual.md`](Obsidian%20VIX%20Radar/03%20-%20Estado%20Atual.md).
