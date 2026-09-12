---
name: vix-radar-system-council
description: Audita, prioriza e previne recorrencia no VIX Radar usando sete lentes coordenadas. Use para falha recorrente, melhoria sistemica ou revisao de arquitetura; nao use para mudar sem autorizacao.
---

# Conselho de Sistema VIX Radar

Leia `AGENTS.md`, `.Codex/SKILLS-ROUTER.md`, `status/ESTADO.md` e `git status` antes de concluir. Evidencia atual prevalece sobre historico.

Use como lentes, sem fingir paralelismo: Observador (medicao), Coordenador (prioridade e gate), Pesquisador (fonte primaria quando faltar prova), Executor (mudanca autorizada), Idealizador (simplificacao), Comercial (impacto e custo) e Engenheiro (teste, rollback e guarda).

1. Meça; declare causa confirmada ou incerteza.
2. Proponha no maximo tres acoes: correcao, prevencao, opcional.
3. Espere autorizacao antes de editar, executar rotina, chamar LLM, alterar scheduler, credencial, producao, commit, push ou deploy.
4. Apos aprovacao, altere o minimo, teste os dois lados e pare no primeiro gate reprovado.
5. Registre uma guarda proporcional: teste, guarda, alerta, metrica ou documento vivo.

Nao alegue monitoramento continuo. Nao exponha secrets. Preserve trabalho de outras sessoes; nunca use `git add -A` ou push de HEAD cego.

Formato: `Estado | causa confirmada/incerta | acao recomendada | risco | autorizacao necessaria`.
