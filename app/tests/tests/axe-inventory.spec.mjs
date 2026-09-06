// axe WCAG — INVENTARIO no primeiro baseline, GATE de regressao depois.
// Regra (aprovada): a 1a rodada nao exige 0 violacoes; ela registra o estado
// atual. O CI falha apenas por violacoes NOVAS (rule id + target fora do
// baseline aprovado). Alvo final continua 0 violacoes aplicaveis.
//
// Modos:
//   UPDATE_AXE_BASELINE=1  -> grava axe-baseline.json (1a rodada Linux/CI;
//                             publicada como artefato; commit em etapa
//                             controlada apos aprovacao humana)
//   sem env, sem arquivo    -> inventario: PASS informativo + evidencia em .local/
//   sem env, com arquivo    -> comparativo: falha so em regressao NOVA
import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { openLanding, waitDemoCard } from './helpers.mjs';

const TESTS_DIR = path.dirname(fileURLToPath(import.meta.url));
const PKG_DIR = path.dirname(TESTS_DIR); // app/tests
const BASELINE_PATH = path.join(PKG_DIR, 'axe-baseline.json');
const EVIDENCE_DIR = path.join(PKG_DIR, '.local');
const TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'];

async function runAxe(page) {
  const results = await new AxeBuilder({ page }).withTags(TAGS).analyze();
  const map = {};
  for (const v of results.violations) {
    map[v.id] = [...new Set(v.nodes.map((n) => (n.target || []).join(' ')))].sort();
  }
  return { counts: results.violations.map((v) => `${v.id}:${v.nodes.length}`), map };
}

function loadBaseline() {
  if (!existsSync(BASELINE_PATH)) return null;
  return JSON.parse(readFileSync(BASELINE_PATH, 'utf8'));
}

test('axe WCAG 2.2 AA — landing publica', async ({ page }, testInfo) => {
  await openLanding(page, { extended: true });
  await waitDemoCard(page);
  const { counts, map } = await runAxe(page);

  mkdirSync(EVIDENCE_DIR, { recursive: true });
  writeFileSync(
    path.join(EVIDENCE_DIR, `axe-evidence-${testInfo.project.name}.json`),
    JSON.stringify({ ts: new Date().toISOString(), tags: TAGS, violations: map }, null, 2),
  );

  const summary = counts.join(', ') || '0 violacoes';
  console.log(`[axe:${testInfo.project.name}] violacoes: ${summary}`);

  const update = process.env.UPDATE_AXE_BASELINE === '1';
  if (update) {
    // Merge entre projects (desktop + mobile): a 1a rodada roda os dois e o
    // baseline final e a UNIAO de violacoes (viewports diferentes acham
    // violacoes diferentes — ex.: link-in-text-block so no mobile).
    const merged = {};
    const prev = loadBaseline();
    if (prev && prev.violations) Object.assign(merged, prev.violations);
    for (const [id, targets] of Object.entries(map)) {
      const base = new Set(merged[id] || []);
      for (const t of targets) base.add(t);
      merged[id] = [...base].sort();
    }
    writeFileSync(
      BASELINE_PATH,
      JSON.stringify({ generatedAt: new Date().toISOString(), scope: 'landing-publica', tags: TAGS, projects: ['desktop', 'mobile'], violations: merged }, null, 2),
    );
    testInfo.annotations.push({ type: 'axe-baseline', description: 'baseline (merge desktop+mobile) gravado em axe-baseline.json (revisar/commitar em etapa controlada)' });
    return;
  }

  const baseline = loadBaseline();
  if (!baseline) {
    testInfo.annotations.push({
      type: 'axe-inventario',
      description: `baseline ausente: inventario apenas. Violacoes atuais: ${summary}. Gerar canonico no CI Linux (UPDATE_AXE_BASELINE=1) e commitar apos aprovacao.`,
    });
    return;
  }

  const bv = baseline.violations || {};
  const regressions = [];
  for (const [id, targets] of Object.entries(map)) {
    const base = bv[id] || [];
    for (const t of targets) {
      if (!base.includes(t)) regressions.push(`${id} @ ${t}`);
    }
  }
  const resolved = Object.keys(bv).filter((id) => !(id in map));
  testInfo.annotations.push({
    type: 'axe-comparativo',
    description: `regressoes novas: ${regressions.length} | resolvidas desde o baseline: ${resolved.join(', ') || 'nenhuma'} | atuais: ${summary}`,
  });
  expect(regressions, `REGRESSOES NOVAS de acessibilidade: ${regressions.join(' | ')}`).toEqual([]);
});
