# Arquivo de rotinas superadas

Conteúdo movido aqui em 2026-08-18 (FASE 2 de governança das rotinas), não apagado, só
quarentenado — mesmo espírito do `scripts/_archive/` que já existe no projeto.

- `vixradar-matinal/`, `vixradar-noturno/`: versão pré-migração (16/07/2026), descreve o
  mecanismo Windows Task Scheduler nativo. A produção real migrou para sessão agendada do
  Claude Desktop em 07/08/2026 (confirmado por `git log`, sem entrada correspondente aqui
  desde então). Fonte viva hoje: `routines/claude-desktop/matinal/` e
  `routines/claude-desktop/noturno/`, atualizadas na mesma sessão que fez esta migração.

Se precisar do histórico do mecanismo antigo (auditoria, comparação, rollback de referência),
está aqui intacto. Não usar como fonte operacional.
