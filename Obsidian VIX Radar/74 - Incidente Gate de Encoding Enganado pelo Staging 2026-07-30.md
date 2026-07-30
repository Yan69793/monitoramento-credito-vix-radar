---
data: 2026-07-30
tipo: incidente
tags: [vix-radar, encoding, powershell, git, gate, causa-raiz]
status: resolvido
---

# 74 - O gate de encoding nao foi contornado, foi enganado

> [!danger] Achado central
> O `pre-commit` lintava o arquivo do **working tree**. O que vira commit e o blob do
> **indice**. Com staging por hunk os dois divergem, e foi por essa fresta que um `.ps1`
> sem BOM entrou no repo com o gate ativo, verde, e o arquivo em disco correto.

## Sintoma

`VIXRadar-Coleta-Volatilidade` de 30/07 17:00 terminou `COM_FALHA`. A etapa 1
(`collect_cotacoes.ps1`) concluiu com sucesso, a etapa 2 morreu:

```
2026-07-30 17:02:14 ERRO upload: No ...\scripts\upload_volatilidade_kv.ps1:30 caractere:49
2026-07-30 17:02:14 FIM: coleta_volatilidade COM_FALHA
```

Os dados do dia foram coletados e nunca chegaram ao KV.

## Por que so quebra em producao

O arquivo parseia sem erro no pwsh 7 e falha no `powershell.exe` 5.1, que e o que o Task
Scheduler usa. UTF-8 sem BOM com nao-ASCII num literal: o 5.1 le como CP1252.

```
pwsh 7   -> parse OK
PS 5.1   -> 4 erros, o primeiro em linha 30 col 49, exatamente o que o log dizia
```

Isso e reincidencia direta de [[70 - Incidente Encoding e Compatibilidade PowerShell 5.1 2026-07-27]].

## A parte que interessa: por que a guarda nao pegou

Havia guarda. `scripts/lint-encoding.ps1` desde 16/07, e um `pre-commit` desde 27/07 que
o invoca. Testado isoladamente, o hook **bloqueia** um `.ps1` quebrado. Mesmo assim
`upload_volatilidade_kv.ps1` entrou sem BOM em `12f2490` (28/07 20:25), com o hook ativo.

Historico do blob prova que a perda foi nesse commit:

| commit | data | BOM no blob |
|---|---|---|
| `642e599` | 27/07 13:17 | presente |
| `12f2490` | 28/07 20:25 | **ausente** |

A hipotese de `--no-verify` estava errada. O mecanismo real, reproduzido:

```
[1] indice recebe blob QUEBRADO (sem BOM)
[2] working tree corrigido (com BOM)
[3] hook -> exit 0, commit liberado
```

O linter recebia caminhos relativos e lia o **disco**. Staging por hunk, adotado no repo
em 28/07, e exatamente o workflow que faz indice e disco divergirem. O gate validava um
arquivo que nao era o que ia para o commit.

## Correcao

`scripts/hooks/pre-commit` agora materializa o blob do indice em `.git/lint-staged/`,
espelhando os caminhos, e linta a copia. Depois apaga. A copia fica dentro do repo e nao
em `/tmp` porque caminho MSYS (`/c/...`) nao e entendido pelo `powershell.exe`.

A mensagem de bloqueio passou a dizer que depois do `-Fix` e obrigatorio `git add` de
novo, senao o indice mantem o blob velho e o commit reprova de novo sem motivo aparente.

Tres casos validados:

| cenario | esperado | obtido |
|---|---|---|
| indice quebrado + disco corrigido | bloqueia | exit 1 |
| arquivo limpo | passa | exit 0 |
| nenhum `.ps1` em stage | passa | exit 0 |

Os dois ultimos importam tanto quanto o primeiro. Gate que reprova arquivo bom vira gate
desligado, que foi como a versao anterior do linter morreu.

## Falso alarme registrado

Uma varredura inicial acusou 7 arquivos com nao-ASCII sem BOM. Seis estao em
`scripts/_archive/` e o linter os exclui de proposito. O problema real era um so.

## Achado colateral, mesmo diagnostico ruim

`VIXRadar-Export-Historico` falha desde 30/07 01:46 e o log dizia
`predictive_v1:latest ausente/ilegivel no KV - sem base para o dump (pipeline nao rodou?)`.

A API responde **401 Unauthorized**. Nao e ausencia de dado. O `CLOUDFLARE_API_TOKEN`
esta ativo (`/user/tokens/verify` -> `status: active`) e enxerga a conta certa
(`7ac79fb1...`), mas nao tem a permissao **Workers KV Storage**: tanto listar namespaces
quanto ler a chave devolvem 401 na chamada direta, sem wrangler no meio.

O script agora separa credencial recusada de dado ausente e nomeia a permissao faltante.
O padrao casa no stderr inteiro, nao nas duas primeiras linhas: o 5.1 quebra a saida
nativa na largura do console e o `- 401: Unauthorized` caia na terceira.

**Acao aberta:** conceder Workers KV Storage ao token no painel da Cloudflare. Enquanto
isso o export nao roda, e a serie historica fica sem os dias desde 30/07.

## Causa raiz e guarda

**Causa raiz:** guarda que valida uma fonte diferente da que e consumida. O linter olhava
o disco, o git consome o indice.
**Guarda:** o hook passou a linter exatamente o artefato que vira commit. Qualquer gate
futuro sobre conteudo versionado deve ler do indice, nunca do working tree.

## Ver tambem

[[70 - Incidente Encoding e Compatibilidade PowerShell 5.1 2026-07-27]] ·
[[73 - Incidente Roteamento de Provedor e Proveniencia 2026-07-30]] · [[PENDENCIAS.md]]
