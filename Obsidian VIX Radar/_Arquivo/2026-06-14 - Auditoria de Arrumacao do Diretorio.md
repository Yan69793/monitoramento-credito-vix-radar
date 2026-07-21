# Auditoria de arrumação do diretório — 2026-06-14

## Contexto

Solicitação: verificar alterações feitas no diretório, avaliar a arrumação e acompanhar próximas mudanças.

Diretório aberto na sessão: `E:\Diretorio\Claude\Monitoramento de Credito`.

Observação operacional: o caminho canônico citado no protocolo (`E:\Diretorio\Codex\Monitoramento de Credito\Obsidian VIX Radar`) não existe nesta máquina/pasta no momento da checagem. Foi usado o vault local disponível em `Obsidian VIX Radar\`.

## Evidência objetiva

- `git log --oneline -5`: falhou com `fatal: your current branch 'master' does not have any commits yet`.
- `git status --short`: repositório sem commit inicial, com grande volume de arquivos novos e alguns arquivos staged modificados/deletados.
- `git diff --cached --stat`: 29 arquivos staged, 8.176 inserções.
- `git diff --stat`: alterações não staged em `.gitignore` e `CLAUDE.md`, e remoção no working tree de `scripts/validate.js` e `scripts/workflow-config.json` que ainda aparecem staged.
- `api/wrangler.toml`: `main = "v4.9.108.js"`, `RADAR_USAGE_EVENTS` declarado, cron `0 4 * * *` documentado como agenda build.
- `api/v4.9.108.js`: `WORKER_VERSAO = "v4.9.108"`.
- `app/index.html`: `CACHE_VERSION="v201.51"`.
- `app/deploy_zip/version.json`: `{"version":"v201.51","deployed_at":"2026-06-13T02:20:25Z"}`.
- `app/version.json`: `{"version":"v201.50","deployed_at":"2026-06-12T23:38:30Z"}`.
- `producao/index.html`: `CACHE_VERSION = 'v36'`, portanto é material legado e não deve ser tratado como fonte atual.

## Estado da arrumação

A organização atual já separa melhor os papéis:

- `api/`: Worker e versões históricas do backend, incluindo `v4.9.108.js` e `wrangler.toml`.
- `app/`: frontend atual e `deploy_zip` de Pages.
- `docs/`: documentação técnica e arquivos arquivados.
- `Obsidian VIX Radar/`: memória operacional disponível.
- `memory/`: memória auxiliar; `memory/credenciais.md` está protegido no `.gitignore`.
- `research/`: pesquisas, notas técnicas e pipeline experimental.
- `_historico/`, `archive/`, `vixradar/`: material legado/recuperado, volumoso e majoritariamente ainda não versionado.

## Achados

1. O repositório ainda não tem commit inicial. Isso faz o Git mostrar quase tudo como adição, dificultando acompanhar mudanças incrementais.
2. Há divergência entre `app/version.json` (`v201.50`) e `app/deploy_zip/version.json`/`app/index.html` (`v201.51`). Para deploy, o pacote correto parece ser `app/deploy_zip`, mas a raiz `app/version.json` está atrasada.
3. `producao/` e `README.md` parecem refletir uma estrutura antiga: README ainda aponta `producao/` como produção atual e menciona stack/cascade antigos, enquanto o Obsidian e os arquivos atuais apontam `api/` + `app/`.
4. `.gitignore` está robusto para segredos e já ignora `memory/credenciais.md`, `.env*`, tokens e caches.
5. A regra permanente de CSS do `<strong>` foi respeitada em `app/index.html`: regra global encontrada sem `color`, com overrides específicos.
6. A regra permanente de telemetria está respeitada em `api/wrangler.toml`: binding `RADAR_USAGE_EVENTS` declarado.

## Riscos

- Sem commit inicial, não há baseline limpo para acompanhar próximas alterações.
- Se `producao/` ou README forem usados como referência operacional, há risco de regressão para frontend antigo (`v36`) e documentação superada.
- O working tree tem mistura de staged e unstaged; `scripts/validate.js` e `scripts/workflow-config.json` aparecem como adicionados no índice e deletados no working tree, exigindo decisão antes de commit.
- A busca de possíveis segredos gerou muitos matches em arquivos históricos e bundles; não foi evidenciada chave literal no recorte analisado, mas o volume legado exige varredura dedicada antes de versionar tudo.

## Próximos passos

1. Definir fonte viva do frontend: provavelmente `app/index.html` + `app/deploy_zip/*`; marcar `producao/` como legado ou removê-lo do fluxo ativo.
2. Atualizar `README.md` para refletir `api/` e `app/`, Worker `v4.9.108` e frontend `v201.51`.
3. Sincronizar `app/version.json` para `v201.51` ou documentar que apenas `app/deploy_zip/version.json` é artefato de deploy.
4. Resolver o estado dos scripts `scripts/validate.js` e `scripts/workflow-config.json`: restaurar se ainda forem usados, ou remover do índice se substituídos por `api/validate.js` e `api/workflow-config.json`.
5. Fazer commit inicial em etapas lógicas, começando por código ativo e documentação operacional, deixando `_historico/`, `archive/` e `vixradar/` para decisão separada.
6. Antes de qualquer commit amplo, executar varredura dedicada de segredos em histórico e arquivos recuperados.

## Status

Auditoria documental local concluída. Nenhuma mudança de código, configuração, Worker, Pages ou deploy foi realizada nesta etapa.

---

## Verificação incremental — 2026-06-14

Solicitação curta: "verifique".

### Evidência objetiva

- `git status --short` ainda mostra repositório sem baseline/commit inicial, com grande volume de arquivos novos.
- Surgiu `producao/ATENCAO-NAO-DEPLOYAR.md`, marcando explicitamente que `producao/` é legado e não deve ser deployado.
- `api/wrangler.toml` agora declara `main = "v4.9.109.js"`.
- `api/v4.9.109.js` declara `WORKER_VERSAO = "v4.9.109"`.
- `app/index.html` e `app/deploy_zip/version.json` continuam em `v201.51`.
- `app/version.json` continua atrasado em `v201.50`.
- O índice do Obsidian ainda cita Worker `v4.9.108`, portanto está defasado frente aos arquivos atuais.

### Interpretação

A arrumação avançou no ponto mais crítico: o diretório `producao/` agora possui aviso para evitar regressão acidental. Porém há novo drift documental: o estado atual real dos arquivos locais é Worker `v4.9.109`, enquanto o índice do Obsidian ainda registra `v4.9.108`.

### Pendências atualizadas

1. Atualizar `Obsidian VIX Radar/00 - Índice (MOC).md` para refletir `v4.9.109`, se essa versão já estiver validada/deployada.
2. Confirmar se `v4.9.109` foi efetivamente publicado em produção ou se é apenas estado local pronto para deploy.
3. Sincronizar `app/version.json` com `v201.51` ou documentar que ele não participa do deploy.
4. Manter `producao/` fora do fluxo operacional; o alerta recém-criado reduz risco de deploy incorreto.

### Status da verificação

Verificação local concluída. Nenhuma mudança de código, configuração, Worker, Pages ou deploy foi realizada; apenas esta atualização documental foi adicionada.
