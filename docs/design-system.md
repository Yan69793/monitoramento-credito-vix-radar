# Design System — Radar de Crédito Privado

> Extraído do CSS existente em `index.html`. Usar estes tokens em qualquer adição de UI.
> **Regra:** nunca introduzir uma cor, componente ou padrão de layout não listado aqui sem aprovação via `/spec`.

---

## 1. Paleta de Cores (CSS Custom Properties)

### Tokens Primários
```css
:root {
  --gold:      #B7985D;  /* Destaque principal, bordas ativas, botão primário */
  --gold-dim:  #C9A96E;  /* Gold hover, links secundários */
  --gold-dark: #8A6F3A;  /* Gold pressionado, logo accent */
  --navy:      #001020;  /* Background body principal */
  --navy-2:    #001830;  /* Cards, topbar, abas-bar */
  --navy-3:    #001528;  /* Background item selecionado no sidebar */
  --border:    #0D2438;  /* Bordas padrão */
  --border-2:  #0A1C30;  /* Bordas secundárias */
  --text:      #D8D0C0;  /* Texto principal */
  --text-dim:  #8896A0;  /* Texto secundário */
  --text-mute: #4E6070;  /* Texto silenciado, labels, placeholders */
  --white:     #EDE8D8;  /* Texto de destaque, títulos */
}
```

### Cores Semânticas de Status de Crédito
```
CRÍTICO:   #EF4444  (borda/ícone)  |  #F87171 (texto)  |  #FCA5A5 (título)  |  #120606 (bg card)
RELEVANTE: #D97806  (borda/ícone)  |  #FCD34D (texto)  |  #FDE68A (título)  |  #0A0D00 (bg card)
OK/POSITIVO: #34D399 (texto/ícone) |  #0F2D1A (bg badge)
ROXO/RATING: #A78BFA (chip)        |  #1A1020 (bg chip)
```

### Cores de Setor (objeto `COR` no JS)
```
Energia Elétrica:          #F59E0B
Transportes e Logística:   #C9A96E
Saneamento:                #34D399
Petróleo, Gás e Combustíveis: #F87171
Mineração e Siderurgia:    #94A3B8
Financeiro:                #A78BFA
Papel, Celulose e Embalagens: #6EE7B7
Agronegócio:               #FCD34D
Saúde:                     #F9A8D4
Telecom e Tecnologia:      #93C5FD
Real Estate e Construção:  #FDBA74
Varejo e Consumo:          #FB923C
```

### Cores de Tipo de Fonte (objeto `FT_COR` no JS)
```
CVM:            #34D399
ANBIMA:         #C9A96E
B3:             #A78BFA
AGENCIA_RATING: #F59E0B
IMPRENSA:       #94A3B8
OUTRO:          #64748B
```

---

## 2. Tipografia

```css
font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
font-size base: 13px
letter-spacing base: 0.01em
```

### Escala de Tamanhos em Uso
| Uso | Size | Weight |
|-----|------|--------|
| Título empresa (`emp-nome`) | 18px | 700 |
| Título dashboard | 16px | 700 |
| Hora no topbar | 15px | 900 |
| Título evento (`ev-titulo`) | 14px | 700 |
| Texto corpo (`ev-texto`) | 13px | 400 |
| Botão run, nome emissor | 13px | 500/700 |
| Chip, classificação, aba | 10–11px | 700–800 |
| Labels uppercase | 9px | 700, letter-spacing: 0.10–0.14em |
| Data evento | 10px | 400 |

---

## 3. Componentes Existentes — Reuso Obrigatório

### `ev-card` — Card de Evento
```html
<!-- Crítico -->
<div class="ev-card crit">
  <div class="ev-top">
    <span class="ev-class crit">🔴 CRÍTICO</span>
    <div class="ev-meta">
      <span class="chip chip-t1 ft-badge">CVM</span>
      <span class="ev-date">2026-03-11</span>
    </div>
  </div>
  <div class="ev-titulo crit">Título do evento</div>
  <div class="ev-texto">Descrição detalhada...</div>
  <div class="ev-campo normal">
    <span class="ev-campo-label">IMPACTO NO CRÉDITO</span>
    Texto do impacto
  </div>
  <div class="ev-monitorar">
    <span class="ev-monitorar-label">⚑ MONITORAR</span>
    O que monitorar
  </div>
  <div class="ev-footer">
    <div class="ev-tags">
      <span class="tag">rating</span>
      <span class="tag">liquidez</span>
    </div>
    <a class="ev-link" href="..." target="_blank">→ Fonte</a>
  </div>
</div>

<!-- Relevante: trocar "crit" por "rel" em todas as classes -->
```

### `stat-card` — Card de Estatística
```html
<div class="stat-card">
  <div class="stat-num" style="color: #EF4444">3</div>
  <div class="stat-label">CRÍTICOS</div>
</div>
<!-- Grid pai: .stat-grid (4 colunas desktop, 2 mobile, 1 em <480px) -->
```

### `chip-t1/t2/t3` — Chips de Fonte
```html
<a class="chip chip-t1" href="..." target="_blank">CVM RAD</a>   <!-- verde -->
<a class="chip chip-t2" href="..." target="_blank">ANBIMA</a>     <!-- amarelo -->
<a class="chip chip-t3" href="..." target="_blank">Moody's</a>    <!-- roxo -->
```

### `emp-btn` — Botão de Emissor no Sidebar
```html
<button class="emp-btn [sel|crit|rel]" onclick="selecionarEmpresa(nome)">
  <span>Nome da Empresa</span>
  <span class="emp-status">🔴</span>  <!-- ou 🟡 ou · -->
</button>
```

### `setor-head` — Cabeçalho de Setor no Sidebar
```html
<div class="setor-head" style="color: #F59E0B">
  ◆ ENERGIA ELÉTRICA
</div>
```

### `load-box` — Estado de Carregamento
```html
<div class="load-box">
  <div class="load-dots">
    <span class="dot-anim" style="animation-delay:0s"></span>
    <span class="dot-anim" style="animation-delay:0.2s"></span>
    <span class="dot-anim" style="animation-delay:0.4s"></span>
  </div>
  <span style="color:#4E6070;font-size:11px">Analisando via IA…</span>
</div>
```

### `badge` — Badge de Status da Empresa
```html
<div class="badge [crit|rel|ok]">CRÍTICO</div>
```

### `alerta-card` — Card de Alerta de Mercado
```html
<div class="alerta-card" style="border-color:#EF4444">
  <div class="alerta-tipo" style="color:#EF4444">SPREAD</div>
  <div class="alerta-desc">Descrição do alerta</div>
  <div class="alerta-lim">Limiar atingido</div>
</div>
```

### `rodada-row` — Linha de Rodada de Busca
```html
<div class="rodada-row [encontrou|vazio]">
  <div class="rodada-n">R1</div>
  <div>
    <div class="rodada-q">query executada aqui</div>
    <div class="rodada-r [encontrou|vazio]">resultado encontrado ou —</div>
  </div>
</div>
```

---

## 4. Layout — Estrutura de Grid

### Desktop (> 768px)
```
┌─────────────────────────────────────────────────────┐
│ #topbar (grid 3 cols: logo | hora/data | botões)    │
├──────────┬──────────────────────────────────────────┤
│ #sidebar │ #main                                    │
│  220px   │   #dashboard  OU  #emp-panel             │
│          │                                          │
├──────────┴──────────────────────────────────────────┤
│ #status-bar                                         │
└─────────────────────────────────────────────────────┘
```

### Mobile (≤ 768px)
```
┌──────────────────────────────┐
│ #topbar (simplificado)       │
├──────────────────────────────┤
│ #main                        │
│   #dashboard OU #emp-panel   │
│                              │
├──────────────────────────────┤
│ #status-bar                  │
├──────────────────────────────┤
│ #mobile-bottom-nav (60px+)   │
└──────────────────────────────┘
    ↑ Drawer #sidebar sobe por cima (z-index: 900)
```

---

## 5. Regras CSS Críticas — NÃO Quebrar

### 5.1 Mobile Drawer (Sidebar)
```css
/* Estado FECHADO — obrigatório */
#sidebar {
  transform: translateY(100%);
  transition: transform 0.3s cubic-bezier(0.32,0.72,0,1);
}
/* Estado ABERTO — adicionado via JS: sidebar.classList.add('drawer-open') */
#sidebar.drawer-open {
  transform: translateY(0);
}
```
**Nunca** usar `display:none/block` para abrir/fechar o drawer — quebraria a animação.

### 5.2 Bottom Nav — Safe Area
```css
#mobile-bottom-nav {
  height: calc(60px + env(safe-area-inset-bottom));
  padding-bottom: env(safe-area-inset-bottom);
}
#body {
  padding-bottom: calc(60px + env(safe-area-inset-bottom)); /* mobile */
}
```
Necessário para iPhones com notch/home indicator.

### 5.3 Sidebar Width
```css
/* Desktop */
#sidebar { width: 220px; flex-shrink: 0; }
/* Mobile */
#sidebar { width: 100%; height: 75vh; }
```

### 5.4 Z-Index Stack
```
#mobile-bottom-nav:  z-index 1000
#sidebar (drawer):   z-index 900
#mobile-drawer-overlay: z-index 800
Overlays modais:     z-index 1100+
```

### 5.5 Scrollbar Custom
```css
::-webkit-scrollbar { width: 4px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #0D2438; border-radius: 2px; }
```

### 5.6 Overflow Body
```css
html, body { height: 100%; overflow: hidden; }
```
Scroll acontece dentro dos containers filhos, não no body.

---

## 6. Animações Existentes

```css
@keyframes fadeInUp {
  from { opacity:0; transform:translateX(-50%) translateY(10px); }
  to   { opacity:1; transform:translateX(-50%) translateY(0); }
}
@keyframes spin {
  to { transform: rotate(360deg); }
}
@keyframes pulse {
  0%,100% { opacity:.3; transform:scale(.8) }
  50%     { opacity:1;  transform:scale(1) }
}
```

Uso:
- `.spin`: ícone de loading rotativo (ex: `⟳`)
- `.dot-anim`: pontos pulsantes no `load-box` (use com `animation-delay` escalonado)

---

## 7. Padrões de Botão

| Classe | Uso | Cor |
|--------|-----|-----|
| `.btn-run` | Ação principal (disparar análise) | bg `#B7985D`, texto `#001020` |
| `.btn-run:disabled` | Análise em andamento | bg `#001528`, texto `#4E6070` |
| `.btn-back` | Voltar ao dashboard | border `#0D2438`, hover `#B7985D` |
| `.btn-export` | Exportar relatório | border/texto `#A8894A` |
| `.mode-btn.active` | Modo ativo (Live) | bg `#B7985D`, texto `#001020`, bold |

---

## 8. Classes de Estado Condicional

Aplicadas via JavaScript conforme dados recebidos do Worker:

| Classe | Aplicada em | Condição |
|--------|------------|---------|
| `.crit` | `.emp-btn`, `.badge`, `.ev-card`, `.ev-class`, `.ev-titulo` | `classificacao === "CRITICO"` |
| `.rel` | idem | `classificacao === "RELEVANTE"` |
| `.sel` | `.emp-btn` | emissor atualmente selecionado |
| `.active` | `.aba-btn`, `.mode-btn`, `.mob-nav-btn` | aba/modo ativo |
| `.encontrou` | `.rodada-row`, `.rodada-r` | rodada com resultado |
| `.vazio` | `.rodada-row`, `.rodada-r` | rodada sem resultado |
| `.ok`, `.warn` | `.status-item` | status da fonte de dados |
| `.done` | `.btn-export` | PDF gerado com sucesso |
| `.visible` | `#banner` | banner ativo |
| `.drawer-open` | `#sidebar` | drawer mobile aberto |
| `.open` | `#mobile-drawer-overlay` | overlay visível |
