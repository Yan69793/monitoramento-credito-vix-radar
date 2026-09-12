---
name: vix-radar-briefing
description: VIX Radar project health briefing. Output current state: versions, health check, top pendencies, next steps. Aggregates Obsidian docs + live Worker health. Terse output (~5-10 bullets, caveman-friendly). ~<5s response time.
---

# VIX Radar — Session Briefing

Quick health snapshot before starting work. Read-only, no deploy.

## Steps

1. **Versions.** Compare repo vs production:
   - `git log --oneline -1` (repo HEAD)
   - `curl -s https://api.vixradar.com` → `versao` (production Worker)
   - `curl -s https://vixradar.com` → `version.json` (frontend)
   - Flag any drift (repo ahead of prod = pending deploy; prod ahead of repo = recover bundle).

2. **Health.** Run the verification gate:
   ```powershell
   curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "`nHTTP:%{http_code} TEMPO:%{time_total}s"
   ```
   Expected: HTTP 200, `ok:true`, `telemetria:true`, `kv:true`, `sentry_ok:true`.
   Also check: `verificador_ok`, `feed_fresco`, `painel_fresco`, `feed_evento_mais_novo`.

3. **Top pendencies.** Read `Obsidian VIX Radar/PENDENCIAS.md` (canonical since 2026-07-27) and `status/ESTADO.md` "Itens abertos". Skip items already marked resolved with a commit hash.

4. **Next steps.** Use `/vix-radar-next-steps` for the P0/P1/P2 prioritized list.

## Output format

~5-10 bullets. No prose preamble. Each bullet: what it is, where it lives, what to do.

- Versions: Worker v4.9.X / frontend vYYYY.N, drift status
- Health: ok/kv/telemetria/sentry_ok/verificador_ok/feed_fresco/painel_fresco
- Top 3 pendencies (file + line reference)
- Next action

## Boundaries

- Read-only. Never deploy, never edit secrets, never POST destructive data.
- If health check fails, say so explicitly. Never claim "working" without the curl output pasted.
- Source of truth for state: `Obsidian VIX Radar/03 - Estado Atual.md`. If it conflicts with the live health, report both.