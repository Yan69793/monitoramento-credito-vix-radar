---
name: bradesco-apresentacao
description: Apresentacao VIX Radar preparada para o Banco Bradesco, conta demo, screenshots
metadata:
  type: project
---

# Apresentacao Banco Bradesco — 2026-07-23

## Entregaveis

- `docs/apresentacoes/Bradesco_VIX_Radar_2026-07-23.html` — deck de 21 slides, dark luxury editorial (navy + gold), navegacao por teclado/touch/dots
- `docs/apresentacoes/screenshots/` — 11 screenshots (landing page + painel logado)
- `diagnosticos/pre-bradesco-2026-07-23.md` — relatorio de auditoria pre-apresentacao

## Conta demo

- Email: `demo.bradesco@vixradar.com`
- Senha: `BradescoDemo2026!`
- Status: aprovada, funcional
- Aprovada manualmente pelo operador (Yan) via link de email

## Estado do sistema na data

- Worker: v4.9.172 (health ok:true, todos os bindings ativos)
- Frontend: v201.85
- Verificador adversarial: operando (Sonnet 4.6)
- Newsletter: modo_teste desativado, envio para lista real
- Nenhum P2 ou P3 aberto afeta a experiencia de demonstracao

## Slides adicionados vs deck anterior (abril 2026)

- Mapa competitivo (Quantum Axis, Economatica, ANBIMA Data vs VIX Radar)
- Casos reais anonimizados (3 mini-casos)
- Verificacao adversarial como slide proprio
- Pipeline preditivo (ANBIMA z-scores, Altman Z''-EM, Merton DD)
- Track record (17 usuarios, 50+ deploys)
- Onboarding em 3 fases com trial de 14 dias

## O que nao foi feito

- Nao gerei versao PPTX (HTML pode ser impresso como PDF)
- Nao capturei screenshots detalhados do painel logado (login via Playwright nao navegou para alem da autenticacao)
- Slides nao incluem graficos quantitativos com dados reais de eventos

**Why:** O escopo era preparar o sistema e a apresentacao para a reuniao com o Bradesco. O sistema estava 100% operacional, nenhum deploy foi necessario. A apresentacao cobre todos os angulos tecnicos e comerciais relevantes para um banco.

**How to apply:** Na vespera da reuniao: verificar health do sistema, confirmar dados recentes no painel, preparar ambiente de demo (navegador limpo, 1920x1080, conexao estavel), ter o HTML da apresentacao aberto como fallback offline.
