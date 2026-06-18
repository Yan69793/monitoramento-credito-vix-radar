---
name: artifact
description: >
  Cria artefatos interativos completos — HTML autossuficiente, apps React/Vue,
  dashboards, protótipos funcionais prontos para abrir no navegador.
  Invocado como /artifact. Use quando pedir artifact, artefato interativo,
  protótipo, dashboard, buildme, ou entregável visual executável.
---

# /artifact — Artefato Interativo

Entregue um artefato **funcional e autossuficiente**, não só descrição.

## Escolha o formato

| Pedido | Formato |
|--------|---------|
| UI simples, relatório, demo | HTML + CSS + JS em arquivo único |
| App com estado/componentes | React ou stack do projeto |
| Dados/tabular | HTML interativo ou componente do projeto |
| Diagrama | Mermaid no markdown OU SVG/HTML |

## Requisitos do artefato

- **Roda sozinho** — sem passos manuais obscuros
- **Dados de exemplo** embutidos se não houver API
- **Responsivo** quando for UI
- **Acessível** — contraste, labels, foco keyboard básico
- **Sem placeholders** tipo "implementar depois" no core

## Processo

1. Definir escopo mínimo viável do artefato
2. Estruturar arquivos (ou arquivo único)
3. Implementar com design limpo e tokens consistentes
4. Validar que abre/executa (mentalmente ou com ferramentas disponíveis)
5. Entregar caminho do arquivo + como abrir

## Em projetos existentes

- Respeitar stack, lint e convenções do repo
- Colocar em pasta adequada (`public/`, `src/`, `dist/` conforme o caso)
- Não quebrar build existente

## Entrega

Informe:
- O que foi criado
- Como abrir/testar (comando ou URL)
- Limitações conhecidas

Execute a tarefa do usuário (tudo após `/artifact`) neste modo.