# Workflow de Governança — Radar de Crédito Privado

Sistema de controle de qualidade para garantir que toda modificação no projeto siga o processo **Spec → Break → Plan → Execute**.

---

## Como Criar uma Nova Feature (4 Passos)

### Passo 1: `/spec` — Documentar
```
Abrir: .claude/commands/spec.md
Preencher todos os campos
Salvar em: specs/YYYY-MM-DD-nome-da-feature.md
```
Sem spec escrita e aprovada → não avançar.

---

### Passo 2: `/break` — Fragmentar
```
Abrir: .claude/commands/break.md
Referenciar a spec criada
Criar tasks de no máximo 300 linhas / 1 arquivo principal cada
```
Objetivo: garantir que cada task seja pequena o suficiente para não quebrar o sistema.

---

### Passo 3: `/plan` — Planejar
```
Abrir: .claude/commands/plan.md
Para cada task do /break, criar um plan com:
  - Código reutilizável identificado (path:linha)
  - Documentação externa necessária
  - Arquivos exatos a modificar (com linha aproximada)
```
Sem plan → sem código.

---

### Passo 4: `/execute` — Implementar
```
Seguir o plan à risca
Ao concluir cada task:
  node validate.js
Se validate falhar → corrigir ANTES de continuar
Um commit por task
```

---

## Como Executar as Validações

```bash
# Na raiz do projeto
node validate.js
```

**Saída esperada (sucesso):**
```
═══════════════════════════════════════════════════════
  Radar de Crédito Privado — Validador de Integridade
═══════════════════════════════════════════════════════

─── SECURITY ──────────────────────────────────────────
  ✅ Nenhuma chave de API detectada no index.html
  ✅ Worker referencia chaves via env.VARIABLE (correto)

─── ARCHITECTURE ──────────────────────────────────────
  ✅ Nenhuma lógica de classificação de crédito no frontend
  ✅ Worker contém FILTROS_SETORIAIS e lógica de classificação (correto)

─── DRY (DUPLICAÇÃO) ──────────────────────────────────
  ✅ Sem duplicação detectada nas 8 funções críticas verificadas
  ✅ Sem duplicação no Worker (5 funções verificadas)

─── IDs CRÍTICOS ──────────────────────────────────────
  ✅ Todos os 20 IDs críticos presentes
  ✅ Todas as 4 abas obrigatórias presentes

─── CSS CRÍTICO (MOBILE) ──────────────────────────────
  ✅ Todas as 9 regras críticas de CSS/mobile presentes

─── WORKER (ESTRUTURA) ────────────────────────────────
  ✅ Todas as 13 estruturas essenciais do Worker presentes
     Setores com filtro setorial mapeado no Worker: 4

═══════════════════════════════════════════════════════

✅ Todos os checks passaram. Deploy seguro.
```

**Em caso de falha:**
```
❌ 2 check(s) falharam. Corrija antes do deploy.
```
→ Ler as mensagens de erro, corrigir, rodar novamente.

---

## Qual Agent Chamar para Cada Modificação

| Modificação | Agent | Arquivo |
|------------|-------|---------|
| Novo filtro setorial (CRÍTICO/RELEVANTE por setor) | `ModelWriter` | `radar-standalone-worker.js` |
| Novo endpoint de API | `APIWriter` | `radar-standalone-worker.js` |
| Novo emissor na lista | `ComponentWriter` | `index.html` → `EMISSORES` |
| Novo setor inteiro | `ModelWriter` + `ComponentWriter` | Worker + index.html |
| Nova aba no painel de empresa | `ComponentWriter` | `index.html` → `#abas-bar` + `setAba()` |
| Novo componente visual | `ComponentWriter` | `index.html` |
| Modificar cascata de IA | `ModelWriter` | `radar-standalone-worker.js` |
| Adicionar check de validação | `TestWriter` | `validate.js` |

---

## Checklist de Segurança Antes de Commit

- [ ] `node validate.js` retorna exit 0
- [ ] Nenhuma chave de API (`pplx-*`, `AIza*`, `sk-or-*`) presente nos arquivos commitados
- [ ] IDs críticos preservados (verificado pelo validate.js)
- [ ] Bloqueios de teclado/menu de contexto intactos no `index.html`
- [ ] Lógica de classificação CRÍTICO/RELEVANTE **somente** no Worker
- [ ] `_routes.json` e `_headers` não modificados
- [ ] Documentação em `references/` atualizada se arquitetura mudou

---

## Estrutura de Arquivos de Governança

```
/
├── index.html                  ← PROTEGIDO
├── radar-standalone-worker.js  ← PROTEGIDO
├── _routes.json                ← PROTEGIDO
├── _headers                    ← PROTEGIDO
│
├── validate.js                 ← Rodar antes de qualquer deploy
├── workflow-config.json        ← Configuração da governança
├── WORKFLOW.md                 ← Este arquivo
│
├── references/
│   ├── architecture.md         ← Arquitetura, IDs, endpoints, setores
│   ├── design-system.md        ← Cores, componentes, CSS crítico
│   └── workflow.md             ← Agents, proibições, processo detalhado
│
├── .claude/
│   └── commands/
│       ├── spec.md             ← Template /spec
│       ├── break.md            ← Template /break
│       └── plan.md             ← Template /plan
│
└── specs/                      ← (criar ao usar /spec pela primeira vez)
    └── YYYY-MM-DD-nome.md
```

---

## Referência Rápida de Proibições

| ❌ Nunca fazer | Motivo |
|---------------|--------|
| Colocar API keys no `index.html` | Vazamento de credenciais |
| Classificar CRÍTICO/RELEVANTE no frontend | Viola Thin Client |
| Chamar Gemini/Perplexity diretamente do browser | Expõe chaves |
| Renomear IDs como `#sidebar`, `#emp-panel`, `#dashboard` | Quebra JS que os referencia |
| Usar `display:none/block` para drawer mobile | Quebra animação |
| Remover `env(safe-area-inset-bottom)` | Quebra em iPhone |
| Remover bloqueio Ctrl+U / F12 | Remove proteção do produto |
| Commit sem rodar `node validate.js` | Deploy inseguro |

---

## Links Úteis

- **Arquitetura detalhada:** `references/architecture.md`
- **Design system completo:** `references/design-system.md`
- **Agents e proibições:** `references/workflow.md`
- **Configuração técnica:** `workflow-config.json`
