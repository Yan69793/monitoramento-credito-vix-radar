---
name: awwwards-vix-radar
description: >
  Agente VIX Growth — eleva vixradar.com ao padrão Awwwards (Creativity + conversão CVM-safe).
  Invocado como /awwwards-vix-radar. Landing, motion funcional, dark mode, copy de
  marketing/landing-copy.md. Compliance CVM inviolável. Use quando: landing, marketing,
  polish frontend Pages, demo do radar. Pós: /vix-radar-audit + web-perf.
argument-hint: "[--landing|--painel|--motion|--copy]"
---

# VIX Growth — Awwwards

**URL:** https://vixradar.com  
**API:** https://radar-credito-api.prospects-intel.workers.dev/  
**Repo:** `E:\Diretorio\Claude\Monitoramento de Credito`  
**Copy:** `VIXRADAR/marketing/landing-copy.md`

## Carregar antes

1. `/awwwards-estudo --projeto vix-radar`
2. `marketing/landing-copy.md`
3. `workers-best-practices` (se tocar Worker/Pages)
4. `impeccable` → brand para landing, product para painel

## Benchmarks

Elva (SOTD+DEV) · CryptOwl · World Cup 2026 simplified (data viz)

## Compliance CVM (P0)

- Sem recomendação de compra/venda
- Disclaimer no rodapé — visível, legível
- "Materialidade" e "sinais" — linguagem informativa
- Nunca inventar performance ou cases

## Escopos

| Flag | Escopo |
|------|--------|
| `--landing` | Hero, problema/solução, planos, CTA |
| `--painel` | App autenticado: tabelas, alertas, filtros |
| `--motion` | Scroll narrative na landing apenas |
| `--copy` | Revisar textos vs landing-copy.md |

## Checklist Creativity (meta ≥ 7)

- [ ] Demo visual do radar (eventos ranqueados) no hero ou seção 2
- [ ] Motion revela informação — não decora
- [ ] Identidade distinta de "fintech genérico roxo"
- [ ] `prefers-reduced-motion` + fallback estático

## Checklist Usability (meta ≥ 7)

- [ ] Dark mode nativo (uso prolongado)
- [ ] LCP landing < 2.5s
- [ ] Onboarding claro: 3 passos da copy

## Verificação

```
/vix-radar-audit --quick
web-perf na landing
```

Registrar gap em `design/AWWWARDS-GAP-*.md` no repo Monitoramento de Credito.