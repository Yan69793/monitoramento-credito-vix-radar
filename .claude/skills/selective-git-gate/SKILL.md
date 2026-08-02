---
name: selective-git-gate
description: Use when committing into a dirty worktree, when an entrega touches files that already have uncommitted changes from another workflow, or before opening any pull request - enforces SHA-base registration, explicit path allowlist, hunk-level staging, and the three origin-base validations that prove what the PR will actually show; staging proves the commit, only origin/main...HEAD proves the PR
---

# Selective Git Gate

Disciplina de entrega em repositório sujo, e prova de escopo antes de abrir PR.

Vale sempre que o worktree tem alterações de outro fluxo, quando a entrega co-edita arquivo já modificado, ou antes de qualquer PR, inclusive em worktree limpo.

## Princípio central

**O staging valida o conteúdo do commit. Só a comparação `origin/main...HEAD` valida o conteúdo real da PR.**

São coisas diferentes e a segunda não decorre da primeira. `git diff --cached` mede o que entra no commit contra o HEAD local. Se a branch local está à frente do remoto, branchear dela faz a PR carregar junto os commits não publicados, e nenhuma validação de staging enxerga isso.

## Antes de começar

1. Registrar o SHA-base: `git rev-parse HEAD`.
2. Snapshot do estado sujo: `git status --short > <scratch>/status-before.txt`. É a prova do antes.
3. Conferir divergência com o remoto: `git rev-list --count origin/main..HEAD`. Se for maior que zero, **branchear de `origin/main`, não do local**, ou a PR virá com os commits extras.
4. Definir a allowlist explícita de caminhos da entrega. Escrita, não implícita.

## Staging

Arquivo limpo (só a sua alteração): `git add <caminho>`, um por um. Nunca `git add .`, nunca `git add -A`.

Arquivo já sujo que você também editou: staging por hunk. `git add -p` é interativo e não funciona neste ambiente, então construa o patch programaticamente a partir do diff real, preservando bytes:

1. `git diff -- <arquivo>` e identifique os hunks (`grep -n '^@@'`).
2. Descarte os hunks que não são seus.
3. Em hunk misto, converta a linha `-` preexistente em linha de contexto (` `) e descarte o `+` correspondente, mantendo só as suas linhas adicionadas.
4. Recalcule o cabeçalho `@@ -a,b +c,d @@` com as contagens reais.
5. `git apply --cached --check <patch>` antes de `git apply --cached <patch>`.

Estruture a edição para facilitar isso: seção aditiva ao final do arquivo separa hunks naturalmente. Ainda assim, se a alteração preexistente tocar a última linha (rodapé, timestamp), o hunk vem misto e exige o passo 3.

## Validação antes do commit

- `git diff --cached --name-only` comparado à allowlist **por conjunto**, não por regex. O git escapa nomes não-ASCII (`\303\215`), então regex sobre a saída padrão gera falso positivo e falso negativo. Use `git -c core.quotePath=false` e compare conjuntos.
- Para cada arquivo já sujo, **inspecionar o diff staged por inteiro**: `git diff --cached -- <arquivo>`. Nome na allowlist não prova isolamento de conteúdo.
- Confirmar que as alterações preexistentes seguem fora do staged e intactas no worktree.
- `git diff --cached --check`.

## Validação antes de abrir a PR, as três obrigatórias

Nenhuma PR abre sem as três:

```bash
git log --oneline origin/main..HEAD
```
Somente os commits autorizados. Dois pontos: commits alcançáveis de HEAD e não da base.

```bash
git diff --name-status origin/main...HEAD
```
Conjunto idêntico à allowlist. Três pontos: diff contra o merge base, que é o que a PR mostra.

```bash
git diff --check origin/main...HEAD
```
Integridade.

Se qualquer uma divergir, a branch está errada. Corrija criando branch nova a partir de `origin/main`, nunca com force-push sobre a existente.

## Depois

`git status --short` comparado ao snapshot do antes: a diferença tem que ser exatamente a allowlist, nada mais.

## Por que esta skill existe

Em 2026-07-28, numa entrega documental de nove caminhos, o worktree tinha 83 arquivos modificados de outro fluxo. O staging seletivo funcionou, incluindo hunk misto em `PENDENCIAS.md`, e todas as validações de staging passaram. A PR mesmo assim veio com dois arquivos extras, porque `main` local estava um commit à frente de `origin/main` e a branch saiu do local. A divergência estava registrada no próprio relatório da auditoria desde a primeira verificação da sessão e não foi ligada à base da PR. Toda a bateria media `git diff --cached`, e nenhuma medida olhava para o que a PR mostraria.

É a mesma classe de defeito que a auditoria daquele dia passou horas nomeando (ver `00-AUDITORIA-SISTEMA-COMPLETA.md`, DATA-001): confiar num indicador que não apura o que promete apurar. A correção foi branch nova a partir de `origin/main`, sem force-push, com a PR incorreta fechada e preservada como registro.
