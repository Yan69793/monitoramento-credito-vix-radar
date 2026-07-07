# Guia de Integração Figma — VIX Radar

**Projeto:** VIX Radar — Sistema de Monitoramento de Crédito Privado com IA  
**Data:** 2026-06-18  
**Status:** Design System v1.0 (Marble Navy + Cobre)  
**Titular:** Szuchmacher Consultoria Ltda.

---

## 1. Token Definitions

### 1.1 Paleta de Cores (CSS Variables)

A paleta está centralizada em variáveis CSS e deve ser replicada no Figma como design tokens.

```css
:root {
  /* Primary Brand Colors */
  --gold:           #B7985D;      /* Tom dourado principal */
  --gold-dim:       #C9A96E;      /* Dourado claro (hover/highlight) */
  --gold-dark:      #8A6F3A;      /* Dourado escuro (pressed/active) */
  
  /* Neutral Backgrounds */
  --navy:           #001020;      /* Fundo primário - preto profundo */
  --navy-2:         #001830;      /* Fundo secundário - elevação 1 */
  --navy-3:         #001528;      /* Fundo terciário - elevação 2 */
  
  /* Borders & Dividers */
  --border:         #0D2438;      /* Border primária */
  --border-2:       #0A1C30;      /* Border secundária (mais escura) */
  
  /* Text & Semantic */
  --text:           #D8D0C0;      /* Texto primário (alta contrast) */
  --text-dim:       #8896A0;      /* Texto secundário */
  --text-mute:      #4E6070;      /* Texto terciário (placeholders/hints) */
  --white:          #EDE8D8;      /* Branco off-white (highlights) */
}
```

#### Aplicação Semântica

| Uso | Token | Valor |
|-----|-------|-------|
| Fundo principal | `--navy` | #001020 |
| Fundo elevado (cards) | `--navy-2` | #001830 |
| Fundo super elevado (modals) | `--navy-3` | #001528 |
| Accent/CTA primário | `--gold` | #B7985D |
| Accent hover | `--gold-dim` | #C9A96E |
| Accent ativo/pressed | `--gold-dark` | #8A6F3A |
| Texto primário | `--text` | #D8D0C0 |
| Texto secundário | `--text-dim` | #8896A0 |
| Placeholder/hint | `--text-mute` | #4E6070 |
| Border padrão | `--border` | #0D2438 |
| Fundo gradiente (opcional) | radial gradient + cobre | Veja seção 1.5 |

### 1.2 Tipografia

#### Font Stack (Google Fonts + System)

```css
/* Títulos impactantes (serif) */
font-family: 'Bodoni Moda', Georgia, serif;

/* Títulos e cabeçalhos (sans) */
font-family: 'DM Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;

/* Corpo e UI geral (sans) */
font-family: 'Manrope', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;

/* Textos elegantes (serif) */
font-family: 'Cormorant Garamond', Georgia, serif;
font-family: 'Libre Baskerville', Georgia, serif;

/* Código e dados (mono) */
font-family: 'JetBrains Mono', monospace;

/* Dados leves */
font-family: 'Inter', -apple-system, sans-serif;
```

#### Escala Tipográfica (recomendada)

| Nível | Uso | Font | Tamanho | Weight | Line-height |
|-------|-----|------|---------|--------|-------------|
| H1 | Título página | Bodoni Moda | clamp(3rem, 10vw, 8rem) | 400 | 1.0 |
| H2 | Seção | DM Sans | 2.5rem | 500 | 1.2 |
| H3 | Subseção | DM Sans | 1.75rem | 500 | 1.3 |
| H4 | Card title | DM Sans | 1.25rem | 500 | 1.4 |
| Body | Parágrafo | Manrope | 1rem | 400 | 1.6 |
| Body-sm | Label/hint | Manrope | 0.875rem | 400 | 1.5 |
| Label | Form label | DM Sans | 0.75rem | 500 | 1.4 |
| Code | Dados/erro | JetBrains Mono | 0.875rem | 400 | 1.4 |

### 1.3 Spacing System

```css
/* 4px base unit */
4px, 8px, 12px, 16px, 20px, 24px, 32px, 40px, 48px, 60px, 80px
```

#### Aplicação

| Uso | Valor |
|-----|-------|
| Gap mínimo (input) | 4px |
| Gap componente | 8px |
| Padding botão | 12px 16px |
| Padding card | 20px ou 24px |
| Margin seção | 40px ou 48px |
| Margin página (topo) | 60px |

### 1.4 Efeitos & Shadows

#### Shadow Scale

```css
/* Elevation 1 (hover) */
box-shadow: 0 4px 16px rgba(184, 115, 51, 0.12);

/* Elevation 2 (card) */
box-shadow: 0 8px 32px rgba(184, 115, 51, 0.16);

/* Elevation 3 (modal) */
box-shadow: 0 16px 48px rgba(184, 115, 51, 0.2);

/* Elevation 4 (dropdown) */
box-shadow: 0 20px 64px rgba(184, 115, 51, 0.24);
```

#### Backdrop Blur (quando aplicado)

```css
backdrop-filter: blur(8px);
opacity: 0.95;
```

### 1.5 Gradientes & Texturas

#### Gradiente Background (hero section)

```css
background:
  radial-gradient(ellipse 80% 40% at 15% 60%, rgba(184, 115, 51, 0.18) 0%, rgba(184, 115, 51, 0.06) 30%, transparent 60%),
  radial-gradient(ellipse 60% 50% at 75% 30%, rgba(160, 100, 45, 0.05) 0%, rgba(160, 100, 45, 0.03) 35%, transparent 55%),
  /* ... (ver index.html para composição completa) */
  #0B1426;
```

**Propósito:** Criar profundidade visual com gradientes radiais em tons de cobre/bronze sutilmente visíveis sobre fundo navy.

---

## 2. Component Library

### 2.1 Componentes de UI Base

#### Card (Padrão)

- **Fundo:** `--navy-2` (#001830)
- **Border:** 1px solid `--border` (#0D2438)
- **Padding:** 20px ou 24px
- **Border-radius:** 8px
- **Shadow:** Elevation 2 (rgba(184, 115, 51, 0.16))
- **Hover:** Background levemente mais claro (`--navy-3`), shadow elevation 3

**Usado em:** Dashboards (métricas HEART), listagens, detalhes.

#### Button (Primário — CTA)

- **Background:** `--gold` (#B7985D)
- **Color:** `--navy` (#001020)
- **Padding:** 12px 24px
- **Border-radius:** 6px
- **Font:** DM Sans, 500, 0.95rem
- **Transition:** 200ms ease
- **States:**
  - Normal: `--gold`
  - Hover: `--gold-dim` (#C9A96E) + shadow elevation 2
  - Active/Pressed: `--gold-dark` (#8A6F3A)
  - Disabled: opacity 0.5 + cursor not-allowed

#### Button (Secundário)

- **Background:** transparent
- **Border:** 1px solid `--border`
- **Color:** `--text` (#D8D0C0)
- **Outros:** idem primário
- **Hover:** Border + background `--navy-2`

#### Input & Form Field

- **Background:** `--navy-3` (#001528)
- **Border:** 1px solid `--border` (#0D2438)
- **Color:** `--text` (#D8D0C0)
- **Placeholder:** `--text-mute` (#4E6070)
- **Padding:** 12px 16px
- **Border-radius:** 6px
- **Focus:** Border `--gold`, box-shadow 0 0 0 3px rgba(183, 152, 93, 0.1)
- **Font:** Manrope, 400, 1rem

#### Label

- **Color:** `--text-dim` (#8896A0)
- **Font:** DM Sans, 500, 0.75rem
- **Margin-bottom:** 8px
- **Text-transform:** uppercase (opcional)
- **Letter-spacing:** 0.5px

#### Divider / Border

- **Cor:** `--border` (#0D2438) ou `--border-2` (#0A1C30)
- **Espessura:** 1px
- **Margin:** 16px 0 ou conforme contexto

### 2.2 Componentes de Dashboard (HEART)

#### HEART Metric Card

- **Layout:** Flex column, center-aligned
- **Estrutura:**
  ```html
  .heart-card
    .heart-metric-name    (label, --text-dim)
    .heart-metric-value   (número grande, --gold, Bodoni Moda 2.5rem)
    .heart-metric-change  (delta ±%, --text-mute, 0.875rem)
    .heart-metric-bar     (progress bar visual, --gold)
  ```
- **Animação:** Entrada em fade + slight scale (cubic-bezier(0.2, 0.8, 0.2, 1))

**Métricas HEART implementadas:**
- Adoption (aprovação de usuários)
- Retention (retenção 30d)
- Engagement (logins + consultas)
- Task Success (consultas / aberturas)
- Happiness (mix de atividade)

#### Sparkline Chart

- **Stroke:** `--gold` (#B7985D)
- **Background (fill):** rgba(183, 152, 93, 0.1)
- **Dimensões:** typically 60px wide × 20px tall
- **Interativo:** hover mostra tooltip com data/valor

#### Data Table

- **Header:** `--navy-2`, DM Sans 500, `--text-dim`
- **Row zebra:** alternando `--navy` e `--navy-2`
- **Cell padding:** 12px 16px
- **Border:** `--border` 1px
- **Hover:** row background `--navy-3`

### 2.3 Componentes de Formulário

#### Checkbox

- **Size:** 18×18px
- **Border:** 2px solid `--border`
- **Checked bg:** `--gold`
- **Checked icon:** ✓ (white, centralized)
- **Transition:** 150ms

#### Radio Button

- **Size:** 18px (diameter)
- **Border:** 2px solid `--border`
- **Checked outer:** `--gold` border
- **Checked inner circle:** 8px solid `--gold`
- **Transition:** 150ms

#### Select/Dropdown

- **Base:** Input field styling
- **Dropdown menu:**
  - **Background:** `--navy-2`
  - **Border:** 1px solid `--border`
  - **Max-height:** 300px
  - **Overflow:** scroll
  - **Item hover:** background `--navy-3`
  - **Item selected:** background `--gold` opacity 20%, text `--gold`

#### Toggle Switch

- **Size:** 40px wide × 24px tall
- **Background (off):** `--border`
- **Background (on):** `--gold`
- **Knob:** 20×20px, white/navy, transition 200ms

### 2.4 Componentes de Navegação

#### Navbar/Header

- **Background:** `--navy` (#001020)
- **Height:** 64px (típico)
- **Border-bottom:** 1px solid `--border`
- **Flex layout:** space-between, center
- **Logo:** 40×40px, branco/gold
- **Nav links:** `--text`, hover `--gold`
- **CTA button:** primário (gold)

#### Sidebar / Navigation Menu

- **Background:** `--navy-2`
- **Width:** 250px (expandido) ou 64px (collapsed)
- **Border-right:** 1px `--border`
- **Link styling:**
  - Normal: `--text-dim`
  - Hover: `--text`, background `--navy-3`
  - Active: background `--navy-3`, left border 3px `--gold`
- **Transition:** 300ms ease

#### Breadcrumb

- **Font:** Manrope, 0.875rem, `--text-dim`
- **Separator:** " / " ou "›" em `--text-mute`
- **Last item:** `--text` (bold)

#### Tabs

- **Tab bar background:** `--navy-2`
- **Tab button padding:** 16px 20px
- **Tab text:** `--text-dim`, DM Sans 500
- **Active tab:** text `--gold`, border-bottom 3px `--gold`
- **Transition:** 200ms

### 2.5 Componentes de Feedback

#### Alert/Toast

- **Info:** background `--navy-2`, border-left 4px `--gold`
- **Success:** border-left `#10B981`
- **Warning:** border-left `#F59E0B`
- **Error:** border-left `#EF4444`
- **Padding:** 16px
- **Border-radius:** 6px
- **Icon + text layout:** flex, gap 12px
- **Auto-close:** 4s (info), 6s (error)

#### Badge / Chip

- **Background:** `--gold` opacity 20%
- **Color:** `--gold`
- **Padding:** 4px 12px
- **Border-radius:** 12px
- **Font:** 0.75rem, 500
- **Removable:** + close icon (hover)

#### Spinner / Loading

- **Size:** 24px × 24px (típico)
- **Stroke:** 3px, `--gold`
- **Animation:** linear rotation 2s
- **Background circle:** none (stroke only)

#### Modal / Dialog

- **Overlay:** rgba(0, 0, 0, 0.6), z-index 1000
- **Modal box:** `--navy-3`, border 1px `--border`, shadow elevation 4
- **Border-radius:** 12px
- **Padding:** 32px
- **Header:** H3, `--text`, margin-bottom 20px
- **Footer:** flex, gap 12px, botões (primário + secundário)
- **Close button:** 32×32px, ícone × no topo-direito

---

## 3. Frameworks & Libraries

### 3.1 Stack Tecnológico

| Camada | Tecnologia | Versão | Notas |
|--------|-----------|--------|-------|
| **Frontend** | HTML5 + CSS3 + Vanilla JS | ES2020+ | Sem framework (SPA puro) |
| **Styling** | CSS Variables + CSS Grid/Flexbox | nativo | Inline styles no HTML |
| **Tipografia** | Google Fonts API | v2 | 8 famílias, ~120KB |
| **API** | Fetch API (ES2020) + async/await | nativo | CORS habilitado |
| **Animações** | CSS Keyframes + JS requestAnimationFrame | nativo | Transições 200-400ms típicas |
| **Backend** | Express.js | 5.2.1 | Node.js, REST API |
| **LLM** | OpenAI API | v6.33.0 | GPT-4, embeddings, etc. |
| **Hosting** | Cloudflare Pages + Workers | 2024 | Edge computing, KV, Durable Objects |
| **Bundler** | Vite (dev) / Wrangler (deploy) | — | Workers build system |
| **Auth** | JWT (localStorage) | — | Bearer token no header |

### 3.2 Estrutura de Código (Frontend)

#### HTML Entry Point

- **Arquivo:** `app/index.html` (~6000+ linhas)
- **Estrutura:**
  - `<head>`: Meta, Google Fonts, estilos CSS inline (`<style>`)
  - `<body>`: Div root `#app`, modais, componentes
  - `<script>`: Módulos JS (vr-admin-*.js)

#### JavaScript Modular

```
app/admin/
  ├─ vr-admin-modules.js     (HEART metrics, utils core)
  ├─ vr-admin-engajamento.js (Dashboard engagement)
  ├─ vr-admin-fase3.js       (Fase 3 workflow)
  ├─ vr-admin-metricas.js    (Métricas gerais)
  └─ vr-admin-shared.js      (Funções compartilhadas)
```

#### API Communication

```javascript
async postAdmin(action, extra) {
  const body = { action, admin_senha, ...extra };
  const response = await fetch(API, {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  return response.json();
}
```

---

## 4. Asset Management

### 4.1 Armazenamento de Assets

#### Estrutura

```
app/
├── design/
│   ├── preview-p1/
│   ├── LANDING-REVERT.md
│   ├── vix-classic-default.png
│   ├── vix-extended-slim.png
│   ├── vix-p0-demo-desktop.png
│   └── ... (preview images)
├── _arquivo/
│   └── snapshots HTML históricos
└── _preview/
    └── PDFs de boletins
```

#### Convenção de Nomes

- **Padrão:** `vix-{feature}-{context}.{ext}`
  - `vix-classic-default.png` → Classic dashboard, default theme
  - `vix-p1-demo-desktop.png` → Phase 1 demo, desktop viewport
  - `vix-p1-hero-mobile.png` → Hero section, mobile

#### Formatos Suportados

| Tipo | Formato | Compressão | Notas |
|------|---------|-----------|-------|
| Screenshots | PNG | lossless | Qualidade máxima (design refs) |
| Background hero | PNG/WebP | optimized | ~200KB max |
| Ícones | SVG inline | — | Escalável, sem requisição |
| Dados export | JSON | gzip | API responses |

### 4.2 Otimização de Assets

#### Imagens

- **PNG:** TinyPNG / ImageOptim (lossless)
- **WebP:** fallback para navegadores antigos
- **Responsive images:** srcset + sizes (não aplicado ainda)
- **Lazy loading:** defer para below-fold

#### Fontes

- **Google Fonts:** display=swap (FOUT aceitável)
- **Subsetting:** Considerar apenas Latin para reduzir 15-20%
- **Local fallback:** System fonts como fallback imediato

#### CSS

- **Inline:** Toda CSS está inline no `<style>` do HTML (sem .css externo)
- **Bundle size:** ~45KB (minified)
- **Purge:** Não aplicável (não há build system de CSS)

---

## 5. Icon System

### 5.1 Ícones Implementados

#### Ícones Emoji (Atual)

Projeto utiliza emojis Unicode como ícones primariamente:

```javascript
/* Exemplos encontrados no código */
const icons = {
  success: "✓",
  error: "✘",
  warning: "⚠",
  info: "ℹ",
  heart: "❤",
  star: "★",
  menu: "☰",
  close: "✕",
  arrow_down: "▼",
  arrow_up: "▲",
};
```

#### Próximos Passos (Recomendado)

Para escalabilidade com Figma, migrar para **SVG icon system**:

```
assets/icons/
├── ui/
│   ├── menu.svg
│   ├── close.svg
│   ├── search.svg
│   └── ...
├── status/
│   ├── success.svg
│   ├── error.svg
│   ├── warning.svg
│   └── info.svg
└── navigation/
    ├── home.svg
    ├── settings.svg
    └── ...
```

### 5.2 Convenção de Nomes

```
{category}-{action}-{state}.svg

menu-toggle-default.svg
menu-toggle-active.svg
heart-like-default.svg
heart-like-active.svg
arrow-down-primary.svg
arrow-down-muted.svg
```

### 5.3 Importação em Componentes

#### Método Atual (Emoji)

```html
<button>
  <span class="icon">☰</span>
  <span>Menu</span>
</button>
```

#### Método Proposto (SVG)

```html
<button>
  <svg class="icon icon--menu" viewBox="0 0 24 24">
    <use href="assets/icons/ui/menu.svg#icon"></use>
  </svg>
  <span>Menu</span>
</button>
```

#### CSS para SVG

```css
.icon {
  width: 24px;
  height: 24px;
  stroke: currentColor;
  stroke-width: 2;
  fill: none;
  transition: stroke 200ms;
}

button:hover .icon {
  stroke: var(--gold);
}
```

---

## 6. Styling Approach

### 6.1 Metodologia CSS

#### Tipo: CSS-in-HTML (Inline Styles + Utility Classes)

- **Arquivo único:** `<style>` block em `index.html`
- **Escopo:** Sem CSS Modules, sem preprocessador (SCSS/Less)
- **Organização:** Comentários secionados (BEM-like, mas simples)
- **Responsividade:** Media queries + clamp() para sizing fluido

#### Exemplo de Organização (conforme index.html)

```css
/* ━━━ RESET & GLOBAL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */
* { box-sizing: border-box; }
body { ... }

/* ━━━ CSS VARIABLES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */
:root { --gold: #B7985D; ... }

/* ━━━ PUBLIC HOME (Hero Landing) ━━━━━━━━━━━━━━ */
#publicHome { ... }

/* ━━━ ADMIN DASHBOARD ━━━━━━━━━━━━━━━━━━━━━━━━━ */
#adminPanel { ... }

/* ━━━ COMPONENTS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */
.button { ... }
.card { ... }
.modal { ... }

/* ━━━ ANIMATIONS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */
@keyframes phImpact { ... }
@keyframes fadeIn { ... }
```

### 6.2 Media Queries (Responsividade)

```css
/* Desktop (padrão) */
/* 1024px+ (sem breakpoint expl., assume-se desktop) */

/* Tablet */
@media (max-width: 1024px) {
  .ph-title-impact { font-size: clamp(2rem, 8vw, 5rem); }
}

/* Mobile */
@media (max-width: 640px) {
  #publicHome { padding: 30px 16px; }
  .ph-landing { gap: 24px; }
  .hero-button { width: 100%; }
}

/* Very small */
@media (max-width: 360px) {
  /* Extra tweaks para smartwatches, obsoleto? */
}
```

### 6.3 Global Styles

#### Reset & Base

```css
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html {
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

body {
  background: var(--navy);
  color: var(--text);
  font-family: 'Manrope', sans-serif;
  line-height: 1.6;
  overflow-x: hidden;
}

/* Scrollbar customizado */
::-webkit-scrollbar { width: 8px; }
::-webkit-scrollbar-track { background: var(--navy-2); }
::-webkit-scrollbar-thumb {
  background: var(--border);
  border-radius: 4px;
}
::-webkit-scrollbar-thumb:hover {
  background: var(--gold);
}
```

#### Link Styles

```css
a {
  color: var(--gold);
  text-decoration: none;
  transition: color 200ms;
}

a:hover {
  color: var(--gold-dim);
  text-decoration: underline;
}

a:visited {
  color: var(--gold-dark);
}
```

#### Form Reset

```css
input, textarea, select, button {
  font: inherit;
  color: inherit;
  background: inherit;
  border: inherit;
  cursor: pointer;
}

input:focus, textarea:focus, select:focus {
  outline: 2px solid var(--gold);
  outline-offset: 2px;
}

button {
  cursor: pointer;
}

button:disabled {
  cursor: not-allowed;
  opacity: 0.5;
}
```

### 6.4 Design Tokens em Variáveis

```css
:root {
  /* Colors */
  --gold: #B7985D;
  --navy: #001020;
  /* ... (veja seção 1.1) */
  
  /* Spacing */
  --space-xs: 4px;
  --space-sm: 8px;
  --space-md: 16px;
  --space-lg: 24px;
  --space-xl: 40px;
  
  /* Border Radius */
  --radius-sm: 4px;
  --radius-md: 6px;
  --radius-lg: 8px;
  --radius-full: 9999px;
  
  /* Transitions */
  --duration-fast: 150ms;
  --duration-normal: 200ms;
  --duration-slow: 300ms;
  --easing-ease: cubic-bezier(0.25, 0.46, 0.45, 0.94);
  --easing-ease-in-out: cubic-bezier(0.2, 0.8, 0.2, 1);
  
  /* Z-Index Scale */
  --z-base: 0;
  --z-dropdown: 100;
  --z-fixed: 500;
  --z-modal-bg: 1000;
  --z-modal: 1001;
  --z-toast: 2000;
}
```

---

## 7. Project Structure

### 7.1 Arquitetura Geral

```
E:\Diretorio\Claude\Monitoramento de Credito\
├── .claude/                    # Claude Code workspace
├── .forja/                     # Forja automações
├── .github/                    # GitHub workflows
├── .wrangler/                  # Cloudflare cache
├── .playwright-mcp/            # Playwright MCP
├── api/                        # Backend Express + OpenAI
│   ├── package.json
│   ├── index.js               # Entry point
│   └── routes/                # API endpoints
├── app/                        # Frontend SPA
│   ├── index.html             # Main entry (6000+ linhas)
│   ├── index.prod.html        # Prod build
│   ├── admin/                 # Admin JS modules
│   │   ├── vr-admin-modules.js
│   │   ├── vr-admin-engajamento.js
│   │   ├── vr-admin-fase3.js
│   │   └── ...
│   ├── design/                # Design assets + previews
│   │   ├── preview-p1/
│   │   └── *.png              # Screenshots
│   ├── _routes.json           # Cloudflare routing
│   └── _headers               # HTTP headers
├── Obsidian VIX Radar/        # Memória canônica (projeto)
│   ├── 00 - Índice (MOC).md
│   ├── Acompanhamento/
│   ├── Arquitetura/
│   └── ...
├── CLAUDE.md                   # Este documento (v current)
├── FIGMA-INTEGRATION.md        # (novo) Guia Figma
├── docs/                       # Documentação
├── scripts/                    # Scripts de deploy/build
├── testing/                    # Testes (se houver)
└── ... (outros diretórios de dados, research, etc.)
```

### 7.2 Padrões de Features

#### Estrutura Típica de Nova Feature

```
Feature: Nova Métrica no Dashboard

1. Dado HTML (novo div em index.html)
   └─ <div id="nova-metrica" class="heart-card"> ... </div>

2. CSS (novo bloco em <style>)
   └─ #nova-metrica { ... }
   └─ @keyframes novaMetricaAnimate { ... }

3. JavaScript (novo módulo ou função em vr-admin-modules.js)
   └─ function calcNovaMetrica(dados) { ... }
   └─ function renderNovaMetrica(valor) { ... }

4. API (novo endpoint em api/index.js)
   └─ POST /api?action=nova_metrica
   └─ Response: { success: true, metrica: {...} }

5. Documentação (actualização em Obsidian)
   └─ Arquitetura/Features/Nova Métrica.md
   └─ Log de mudança em Acompanhamento/

6. Deploy (via Wrangler + Cloudflare Pages)
   └─ npm run deploy:pages
   └─ npm run deploy:api
```

### 7.3 State Management

#### Local Storage

```javascript
// Autenticação
localStorage.setItem('radar_jwt', token);
localStorage.getItem('radar_jwt');

// Preferências de usuário
localStorage.setItem('user_theme', 'dark'); // (sempre dark aqui)
localStorage.setItem('dashboard_layout', 'compact');

// Cache de dados
sessionStorage.setItem('radar_admin_senha', password);
```

#### Session State

```javascript
// Runtime memory (não persistido)
let adminMode = false;
let currentUser = null;
let dashboardData = {}; // Atualizado via fetch
```

---

## 8. Regras de Integração Figma + Código

### 8.1 Fluxo de Design-to-Code

#### Passo 1: Design no Figma
- Criar componentes com tokens já definidos
- Nomeação: `[component] Button / Primary / Default`
- Exportar como PNG 2x para review (design/previews/)

#### Passo 2: Código no Projeto
- Criar `.html` (estrutura) + `.css` (inline em `<style>`)
- Usar variáveis CSS do sistema (--gold, --text, etc.)
- Testar responsividade (360px, 640px, 1024px, 1440px)

#### Passo 3: Validação Cruzada
- Compara screenshot Figma vs. live app
- Verificar espaçamento (4px grid), cores (exato match), tipografia (peso, tamanho, line-height)
- Documentar desvios e decidir se ajustam código ou design

### 8.2 Manutenção de Sincronização

#### Mudanças no Design (Figma → Código)

1. **Atualizar Figma Design System** (colors, typography)
2. **Exportar CSS vars** de Figma
3. **Copiar para index.html `<style>`**
4. **Validar componentes** affected
5. **Testar em browsers** (Chrome, Safari, Firefox)
6. **Commit:** `docs: sync design tokens from Figma`

#### Mudanças no Código (Código → Figma)

1. **Implementar feature** em HTML/CSS
2. **Screenshot da live app** (1440px, 1080px, mobile)
3. **Atualizar Figma** com componente novo/revisado
4. **Adicionar a design library** para reuso
5. **Documentar** em Obsidian > Arquitetura/Components

### 8.3 Checklist para Novo Componente

- [ ] Design criado em Figma com tokens corretos
- [ ] Código implementado com CSS variables
- [ ] Testado em 3 breakpoints: 360px, 640px, 1440px
- [ ] Hover/active/disabled states implementados
- [ ] Animações suave (200-300ms) com easing apropriado
- [ ] Acessibilidade: focus states, ARIA labels, contrast 4.5:1 min
- [ ] Screenshot adicionado a design/previews/
- [ ] Documentado em Obsidian > Arquitetura/
- [ ] PR/Commit com referência a Figma URL

---

## 9. Padrões de Nomeação

### 9.1 Variáveis CSS

```css
--{category}-{property}-{state}
--color-gold
--color-gold-dim       /* hover */
--color-gold-dark      /* pressed */
--space-sm, --space-md, --space-lg
--shadow-elevation-1, --shadow-elevation-2
--duration-fast, --easing-ease-in-out
```

### 9.2 Classes CSS

```css
.component-name
.component-name--variant   /* BEM modifier */
.component-name.is-active  /* State */
.component-name.is-disabled
.component-name > .component-name__child
```

**Exemplos:**
```css
.button
.button--primary         /* variant */
.button.is-disabled      /* state */
.button > .button__icon

.card
.card--elevated          /* variant (mais shadow) */
.card.is-hover
```

### 9.3 ID HTML

```
#app
#publicHome
#adminPanel
#{feature}-container
#{section}-wrapper
```

### 9.4 Atributos Data

```html
<!-- Para componentes dinâmicos / estado -->
<div data-component="modal" data-state="open">
<button data-action="submit" data-loading="false">

<!-- JavaScript referencia -->
document.querySelector('[data-action="submit"]')
```

---

## 10. Guia Rápido para Equipe de Design

### Para usar este guia:

1. **Paleta de cores:** Copiar valores hex de seção 1.1 → Figma color library
2. **Tipografia:** Instalar 8 Google Fonts → Figma typography styles
3. **Componentes:** Usar estrutura seção 2 → criar Main components em Figma
4. **Spacing:** Usar escala 4-8-12-16... → definir auto layout com gaps
5. **Ícones:** Migrar para SVG (seção 5) → criar icon library no Figma
6. **Estados:** Documentar normal, hover, active, disabled (seção 2 examples)
7. **Breakpoints:** Verificar 360px, 640px, 1024px, 1440px
8. **Feedback:** Atualizar este documento após cada design review

---

## 11. Roadmap de Melhorias

### Curto Prazo (Próximas 2-4 semanas)

- [ ] Migrar ícones emoji → SVG icon library
- [ ] Criar Figma Design System file (tokens + components)
- [ ] Documentar variantes de componentes (dark mode stub)
- [ ] Code Connect mapping Figma ↔ index.html

### Médio Prazo (2-3 meses)

- [ ] Implementar light mode variant (se negócio solicitar)
- [ ] Criar storybook ou Figma Prototypes interativos
- [ ] Automated visual regression testing (Percy, Chromatic)
- [ ] Refatorar CSS em separado (opcional, se projeto crescer)

### Longo Prazo (6+ meses)

- [ ] Migrar para framework UI (React + Storybook + Tailwind?) — avaliar trade-offs
- [ ] i18n + l10n (múltiplos idiomas, além PT-BR)
- [ ] Design tokens JSON export (Design Tokens Community Group)
- [ ] Multi-brand system (se houver rebranding futuro)

---

## 12. Referências & Recursos

### Dentro do Projeto

- **Memória canônica:** `Obsidian VIX Radar/00 - Índice (MOC).md`
- **Código frontend:** `app/index.html` (fonte única de verdade)
- **Código backend:** `api/index.js` (endpoints)
- **Design assets:** `app/design/`

### Externas

- [Figma Design Systems](https://www.figma.com/design-systems/)
- [Design Tokens W3C](https://design-tokens.github.io/community-group/format/)
- [CSS Variables Guide](https://developer.mozilla.org/en-US/docs/Web/CSS/var)
- [A11y Contrast Checker](https://webaim.org/resources/contrastchecker/)
- [Cloudflare Workers + Pages](https://developers.cloudflare.com/)

---

**Documento de integração gerado:** 2026-06-18  
**Versão:** 1.0  
**Próxima revisão:** 2026-07-18 (ou após mudança arquitetural significativa)

