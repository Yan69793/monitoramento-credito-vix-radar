---
type: reference
date: 2026-08-10
title: Correção — gh CLI está disponível localmente
status: ativo
---

# Correção — acesso ao GitHub a partir desta máquina

Uma memória anterior do Claude Code (fora deste repositório, no sistema de memória
persistente por sessão) registrava que a máquina local não tinha `gh` CLI nem token do
GitHub configurado, e que por isso rotinas não conseguiam ler Actions, issues ou PRs do
repositório privado `Yan69793/monitoramento-credito-vix-radar`.

Essa memória estava errada. Confirmado em 10/08/2026 via `gh auth status`.

## O que é verdade agora

- `gh` CLI instalado em `C:\Program Files\GitHub CLI\gh`, autenticado como `Yan69793`
  via `GH_TOKEN`.
- Leitura de Actions funciona direto: `gh run list`, `gh run view --log-failed`,
  `gh api repos/<owner>/<repo>/...`. Usado nesta sessão para diagnosticar uma falha
  real do workflow `canonical-test.yml` (run `31393983894`, causa: `verificador_ok`
  travado, sem drift de versão).
- `jq` continua ausente no PATH do Git Bash local. Usar `gh ... --jq` (o próprio `gh`
  embute um interpretador jq) ou `node -e` para parsear JSON fora do `gh`.
- O repositório tem um único colaborador cadastrado, a própria conta do dono. Avisos de
  falha de workflow por email chegam só para ele.

## Por que isso importa

Uma sessão que herdar a memória antiga (não corrigida) pode desistir de diagnosticar
falha de CI achando que não tem como ler o log, quando na verdade tem. Já quase
aconteceu nesta sessão antes da checagem.

## Como aplicar

Antes de assumir bloqueio de acesso ao GitHub neste projeto, rodar `gh auth status`
primeiro. Autenticação de CLI é o tipo de estado que expira ou é revogado sem aviso,
então não tratar nem esta nota nem a anterior como garantia permanente, reconferir.

Este arquivo existe porque a correção equivalente no sistema de memória do Claude Code
(`project_github_sem_acesso.md`, fora deste repositório) não tem controle de versão
próprio. Esta cópia fica protegida pelo git do projeto.
