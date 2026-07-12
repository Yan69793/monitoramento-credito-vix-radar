# Auditoria Verificador Async — 2026-07-10

Auditoria das alteracoes em `run_vixradar_verificacao_async.ps1` — guards de refusal (Fable 5), fallback model, parsing e observabilidade.

## Contexto

O verificador adversarial (dreno da fila `radar:verif_fila`) roda via `claude -p`. Correcao de registro (2026-07-10, ver [[49 - Avaliação Fable 5 e Guards Refusal 2026-07-10]]): com `ANTHROPIC_API_KEY` setada no registro (User), `Get-AnthropicApiKey` a injeta e o dreno roda **cobrado por token** (metered), nao por assinatura — assinatura e so o fallback se a chave sumir. O modelo atual e `claude-sonnet-4-6`. Prepara-se para eventual troca para `claude-fable-5`, que pode disparar `stop_reason=refusal` (classificador de seguranca) — cenario nunca observado em producao ate agora.

## Achados da auditoria

### 1. Ordem dos guards — CORRETA

`run_vixradar_verificacao_async.ps1:239-265`:

```
AuthFailure → break (aborta todos os lotes restantes — sessao inteira comprometida)
Refusal     → continue (recusa e por conteudo do lote, proximo lote pode passar)
Parse fail  → continue (idem)
```

Decisao correta: auth quebra sessao inteira; refusal e parse sao por lote.

### 2. Parsing de refusal — CORRETO

`:117-124` em `Invoke-ClaudeBatch`:

```powershell
if ($json.stop_reason -eq 'refusal') {
    $refusal = $true
    if ($json.stop_details) {
        $refusalCategory = $json.stop_details.category
        $refusalExplanation = $json.stop_details.explanation
    }
}
```

- `stop_reason` existe no envelope JSON do CLI (confirmado em teste real com `--output-format json`)
- `stop_details.category/.explanation` sao opcionais — leitura condicional, nao quebra se ausentes
- 3 casos sinteticos passaram (com stop_details, sem, end_turn normal)

### 3. Branch refusal salva rawout — CORRIGIDO

`:249-253`:

```powershell
$rawOutPath = Join-Path $LogDir ('verifasync_rawout_refusal_' + $label + '_' + $DateTag + '.txt')
Set-Content $rawOutPath -Value (($result.Output) -join "`n") -Encoding UTF8
Write-Log ('AVISO: classificador de seguranca recusou o lote ... Saida bruta em ' + $rawOutPath)
```

Antes: branch refusal nao salvava rawout. Branch vizinho (parse-falhou) salvava. Se `stop_details` viesse vazio (cenario provavel, nunca observado no CLI), a evidencia de qual evento disparou o classificador se perdia.

Corrigido: salva `verifasync_rawout_refusal_*.txt`, log ganha contagem de eventos do lote e caminho do arquivo.

### 4. Guard de nulidade em `$ModelFallback` — CORRIGIDO

`:80`:

```powershell
if ($ModelFallback -and $Model -ne $ModelFallback) { $fallbackArgs = @('--fallback-model', $ModelFallback) }
```

Antes: sem o `$ModelFallback -and`, se a funcao fosse copiada para outro script sem `$ModelFallback` no escopo, `$null -ne $Model` passava e `--fallback-model` ia vazio — quebrando o `claude -p` inteiro.

Corrigido + testado nos 3 cenarios:
- `$ModelFallback = $null` → 0 args (correto)
- `$ModelFallback = 'claude-sonnet-4-6'`, `$Model = 'claude-fable-5'` → 2 args (correto)
- Ambos iguais → 0 args (correto, evita fallback-pra-si-mesmo)

### 5. `Get-BalancedJson` — CORRETO

`:128-148`: varredura char-a-char com tracking de `inStr` (dentro de string) e `esc` (escape). Conta profundidade de `[`/`{` vs `]`/`}`. Ignora delimitadores dentro de strings JSON.

Robusto contra o cenario que quebrou o extrator anterior (2026-07-05): `LastIndexOf(']')` casava com `]` de links markdown anexados pelo modelo depois do JSON. A varredura balanceada para no `]` que fecha o array, ignorando tudo depois.

### 6. Sintaxe — 0 ERROS

`PSParser::Tokenize` confirmou sintaxe valida apos cada edicao. Ultima modificacao: 2026-07-10 15:27 BRT.

### 7. Exit 8 — SEGURO

`:327-328`:

```powershell
if ($stats.erros_parse -gt 0) { $exitCode = 6 } elseif ($stats.refusals -gt 0) { $exitCode = 8 }
```

Matinal (`run_vixradar_matinal_claude.ps1:416`) e noturno (`run_vixradar_noturno_claude.ps1:631`) invocam o dreno como processo filho (`Start-Process -Wait`) e **so logam** o exit code — nao ha branch por codigo. Nao colide com exit codes existentes (0=ok, 6=parse, 7=auth, 1=fatal).

### 8. `$ModelVerificador` mantido Sonnet 4.6

`:25` — `'claude-sonnet-4-6'`. Sem troca para Fable 5. `$ModelFallback` = Sonnet 4.6 tambem → fallback inativo (igual ao principal). So ativa se `$ModelVerificador` mudar para Fable 5.

## Falhas do implementador — corrigidas

1. **Branch refusal nao salvava rawout.** Corrigido em `:249-253` (ver item 3).
2. **Guard de nulidade ausente em `$ModelFallback`.** Corrigido em `:80` (ver item 4).
3. **Custo mal reportado.** Foi dito "~US$ 0,52" mas era so rodada 1. Total real das 2 rodadas de teste: ~US$ 1,07 (0,522 + 0,546).

## Limitacoes conhecidas — documentadas, nao implementadas

1. **Retry de lote recusado.** Item recusado fica na fila → proximo run re-tenta o mesmo lote → recusa de novo (deterministico por conteudo). Nao e loop infinito: janela de releitura = 3 dias × 2 runs/dia ≈ 6 tentativas, depois o item sai da janela. Com `ChunkSize=4`, um evento problematico segura os outros 3 do lote nesse periodo. Mitigacao futura (so se refusal real ocorrer): re-tentar em chunks de 1 pra isolar o evento.
2. **`refusals` conta lotes, nao eventos.** Nome ambiguo no metrics JSON. Contagem de eventos agora aparece no log (linha do `Write-Log` no branch refusal), suficiente para diagnostico.
3. **Divergencia teste vs producao.** Testes usaram `--permission-mode auto`; producao usa `bypassPermissions`. Buscas rodaram nos testes, mas nao e replica exata do ambiente de producao.
4. **`--fallback-model` cobre refusal?** Nao confirmado. Help do CLI fala "overloaded or not available". Nunca foi provocado refusal real para validar. Guard de deteccao cobre o gap: se disparar e o fallback nao pegar, log mostra causa exata (`stop_reason=refusal, categoria=X`).

## Evidencia de producao

Log `vixradar-verificacao-async_20260710.log`:
- Run 08:22: 10 itens, 3 lotes, aprovados=7 rejeitados=3 erros_parse=0
- Run 08:54: fila vazia
- Run 10:20 (cron): fila vazia
- Run 10:27 (cron duplicado): fila vazia
- Run 12:17 (pos-matinal): 10 itens, 3 lotes, aprovados=6 rejeitados=4 erros_parse=0

Nenhum refusal em producao — guarda e preventiva.

## Veredito

**Script correto no nucleo.** 3 falhas encontradas e corrigidas pelo proprio implementador. Guards, parsing, sintaxe, isolamento de exit codes e observabilidade validados com evidencia. Nenhuma acao pendente — limitacoes sao conhecidas e documentadas, sem evidencia que justifique implementa-las agora.
