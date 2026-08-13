# 01 — Evidência consolidada

Escopo em `00-scope.md`: landing pública vixradar.com + form `#phAcesso`.
Fonte de citações: `app/index.html` (frontend único de ~700KB, CSS/JS inline).
Coleta ao vivo feita com Chrome headless via Playwright, somente leitura,
4-5 carregamentos por agente, sem POST com credencial.

Achado transversal que condiciona tudo: **a landing pública renderiza o
aplicativo inteiro inline em modo demo** (painel, market overview, agenda,
shell de admin, 5 inputs de senha no DOM) na mesma página. Muitas medições
abaixo vêm dessa superfície embutida; onde importa, está marcado.

## Estrutural

- Elementos interativos na landing: **8** (a 3206, button 3207, button 3214,
  a 3216, a 3224, a 3225, a 3259, a 3269).
- Profundidade máxima do DOM: **6** (cadeia `#publicHome` 3202 →
  `.ph-page--extended` 3212 → `#phPlanos` 3248 → `.ph-plans` 3250 →
  `article.ph-plan` 3251 → `.ph-actions` 3259 → `a` 3259).
- Padrões repetidos: "abrir login" ×3 (3206, 3216, 3224, todos `showLogin()`);
  "cadastro" ×3 (3225, 3259, 3269, todos `showRegister()`).
- Classes mortas: `.ph-hero-ext` (3219, zero regras CSS), `.ph-page` (3212,
  só existe a variante `--extended`), `data-demo-fallback` (3237, só escrito
  por JS 3348, nunca lido).
- Decoração morta: `#phDemoSkeleton` (3238) shimmer vazio que nunca recebe
  conteúdo; `span.ph-signature__icon` (3209) decorativo; `.ph-actions`
  wrapper de filho único repetido (3259, 3269).

## Visual (medido ao vivo, computed style)

- Espaçamento: **28 valores** `[1,2,3,4,5,6,6.5,7,8,9,10,11,12,13,14,16,18,
  20,22,24,28,32,36,40,44,48,49.8,60]` px; 6.5 e 49.8 não vêm de px fixo
  local (não pertencem a escala alguma).
- Tipografia: **24 tamanhos** `[6.5 ... 128]` px; 52 e 128 sem declaração
  fixa no arquivo local.
- Cores: **142 únicas** renderizadas. Base navy rgb(13,19,33)/rgb(0,13,26)
  com variantes; dourado rgb(183,152,93)/rgb(201,169,110) com alphas de 0.03
  a 0.92; claro rgb(232,228,220); cinzas #374151/#4b5563 (piores contrastes,
  confirmados na fonte); vermelho/verde/âmbar.
- Contraste mínimo: **1.04:1** (botão "Analisar", app embutido). Na landing
  visível: © rodapé **1.7:1**, breadcrumb **3.3:1**, "Fonte: CVM" **3.5:1**,
  respostas FAQ **4.4:1**, labels E-MAIL/SENHA do login **4.41:1**.
- Estados: empty presente (mensagem "Nenhum alerta ativo" e 10 inputs vazios);
  loading presente na landing (5 nós), ausente no form; **error ausente**
  (0 nós .error/role=alert, submit vazio não renderiza erro inline; os 401 da
  API só aparecem no console); **success ausente**; focus quebrado (12 regras
  :focus no CSS, mas focar o input de e-mail não muda nada visível); disabled
  ausente em runtime (0 elementos [disabled], CSS declara mas nada usa).

## Copy & Honestidade

- Inflações: "antes do mercado" (3221) e "Antecipa · EWS antes da manchete"
  (3228) sem evidência de antecedência temporal (EWS é calculado sobre
  documentos CVM já publicados); "em tempo real" (3992) contradiz o FAQ
  (3282, "todo dia útil, 18h30"); drift numérico "100 emissores" (3222/3255)
  vs "103 Emissores" (3783).
- Dark patterns: ausentes os pesados (sem continuidade forçada, custo
  escondido, escassez falsa, confirmshaming). Presente: banner de cookies sem
  "Rejeitar" (4056-4059), consentimento presumido.
- Jargão: "EWS" (3228, 3256) nunca expandido; "materialidade 0–100"
  (3222, 3229, 3242) nunca explicada em linguagem simples.
- Rótulo vs comportamento: **"Assinar"** (3259) chama `showRegister()` e abre
  "Solicitar acesso", sem checkout nem pagamento; **"Falar com o time"**
  (3269) chama o mesmo `showRegister()` e abre o formulário de cadastro
  genérico, não um canal de contato.

## Peso & Fricção

- JS inicial: **584.802 B** (466KB inline + 119KB em 11 scripts externos);
  HTML 697KB.
- **24 requisições** na view primária; duas são **401 para api.vixradar.com**
  (fetch de dados no load da página pública) e uma telemetria cdn-cgi.
- TTI estimado: **~828 ms** (PerformanceObserver de longtask; domInteractive
  713ms, load 884ms, TTFB 334ms).
- **4 loops de animação** na tela ociosa (ag-spin, phSkel, vgShimmer, pulse);
  reduced-motion reduz de 3 para 2, ou seja, **2 loops ignoram a preferência**.
- **10 badges/modais** no carregamento inicial (live-badge, novo, anomalias,
  banner de cookies).
- Dark mode: fixo escuro (coerente com a marca), não alterna.

## Acessibilidade

- Contraste: **19 falhas AA** medidas ao vivo; na landing visível: © 1.7:1,
  breadcrumb 3.3:1, FAQ 4.4:1, labels do login 4.41:1. Títulos e CTAs
  principais passam (14.5-16:1).
- Ordem de foco: 1. Veja como funciona, 2. e-mail, 3. senha, 4. ACESSAR
  RADAR, 5-6. links auxiliares, **7-8. shell do app** (btn-live, btn-cmdk)
  mesmo com a landing na frente.
- Teclado: todas as ações primárias alcançáveis por Tab (Entrar, Solicitar
  acesso, Assinar, form) — SIM em todas.
- Landmarks: nav(1), main(1), aside(1), footer(1), region(1), dialog(8,
  ocultos). **header=0, form=0** (não há `<form>` nem role=form).
- Skip link: **NÃO existe**.
- Labels do login: presentes via `label[for]` ("E-MAIL" 3291, "SENHA" 3292),
  mas com contraste 4.41:1.
