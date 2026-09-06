# VIX Radar — frontend QA (baseline ANTES do redesign)

QA automatizado do frontend publico (`app/`), gratuito (custo adicional R$ 0), sem deploy.

## Escopo (baseline atual)
- Superficie **publica anonima**: landing (`#publicHome`) + card demo (`/landing-demo.json`, local).
- Dashboard autenticado **fica fora**: senha de admin nunca em teste. Cobrir o dashboard exige sessao
  aprovada/demo interna — iteracao futura, documentada em `PESQUISA-MCP-VIX-2026-09-06.md` e
  `DIRECAO-VISUAL-VIX-2026-09-06.md`.
- Nenhuma alteracao de UI/CSS (`app/index.html` intocado). Falhas encontradas viram relatorio;
  correcao visual so apos aprovacao humana.

## Rodar
```bash
cd app/tests
npm ci
npx playwright install chromium
npx playwright test                 # smoke + keyboard + viewport + axe
npx lhci collect && npx lhci upload # lighthouse baseline (sem thresholds)
```

## axe — inventario agora, gate de regressao depois
- 1a rodada: inventario. `UPDATE_AXE_BASELINE=1 npx playwright test` grava `axe-baseline.json`
  (canonico deve nascer no **CI Linux**; publicar como artefato; **commit em etapa controlada** apos aprovacao humana).
- Rodadas seguintes comparam contra o baseline commitado e **falham so por regressao NOVA**
  (rule id + target fora do baseline). Alvo final: **0 violacoes aplicaveis**.
- Evidencia local: `.local/axe-evidence-<project>.json` (ignorado pelo git).

## Screenshots (visual regression)
- Spec roda **somente em Linux** (`process.platform === 'linux'`); em Windows executa `test.skip`.
- Canonico: 1a rodada Linux com `--update-snapshots` publica os PNGs como artefato;
  commit dos PNGs aprovados e etapa separada/controlada. Depois disso, rodadas validam contra o commitado.

## Regras de CI
- `workers: 1`, `retries: 0` (baseline deterministica), versoes fixadas via `package-lock.json`.
- `permissions: contents: read` — o workflow nunca commita nada.
- Artefatos preservados: `playwright-report/`, screenshots, `.lighthouseci/` (para definir thresholds depois), evidencia axe.
