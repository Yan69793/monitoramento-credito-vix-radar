# test-reconciliacao-kvput.ps1 - prova do KVOUTPUT1 (2026-10-14), duas pontas.
#
# Defeito real corrigido: `Invoke-WranglerKVPut` chamava `npx wrangler kv key put ... 2>$ErrFile`
# SEM capturar o stdout. O stdout do wrangler entrava na COLECAO DE RETORNO da funcao, entao
# `return $code` devolvia um array (banner + "Writing the contents of ..." + o codigo) e o
# chamador testava `$kvCode -ne 0`. Comparar ARRAY contra escalar devolve os ELEMENTOS
# diferentes de zero - ou seja, o ramo "falhou" disparava sempre.
#
# Medido em 12/10/2026: o log do proprio wrangler
# (logs do usuario: wrangler-2026-10-12_15-00-26_505.log) traz
#   `-- START CF API RESPONSE: OK 200` e `wrangler command completed`,
# enquanto a rotina gravava "AVISO: kv put radar:reconciliacao_cvm:latest falhou - " e, por
# RECONCILIACAO-FAILCLOSED1, saia exit 3 (PARCIAL). O KV remoto FOI atualizado: nao houve perda
# de dado, so um sinal de falha falso todos os ciclos.
#
# Parte 1: comportamental - as duas formas da funcao, com o MESMO comando nativo que escreve em
#          stdout e sai 0. A forma antiga devolve array e o chamador conclui "falhou"; a nova
#          devolve [int] e o chamador conclui "ok".
# Parte 2: estrutural contra o arquivo real - o corpo da funcao captura o stdout e devolve [int],
#          e o chamador continua testando o codigo (contrato inalterado).
#
# Offline puro: nenhum token, nenhuma rede, nenhuma escrita em KV. O comando "nativo" e um
# `cmd /c echo` local que imita o formato do stdout do wrangler.
# ASCII puro, PS 5.1.

$ErrorActionPreference = 'Continue'
$script:ok = 0; $script:fal = 0
function Assert([bool]$c, [string]$m) { if ($c) { $script:ok++; Write-Host ('  OK    ' + $m) } else { $script:fal++; Write-Host ('  FALHA ' + $m) } }

$tmp = Join-Path $env:TEMP ('vixkvput_' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
# Imita o stdout real do wrangler (banner + linha de escrita) e sai 0, como no put que deu 200.
$fakeCmd = 'cmd /c "echo  wrangler 4.118.0 & echo Writing the contents of arquivo.json to the key & exit /b 0"'

try {
    Write-Host '=== Parte 1: comportamental - array vaza para o retorno e mente no chamador ==='

    # Forma ANTIGA (defeito): stdout sem redirect.
    function Invoke-KvPutFormaAntiga([string]$ErrFile, [string]$FakeCmd) {
        $code = 1; $intento = 0
        while ($intento -lt 3) {
            $intento++
            Invoke-Expression ($FakeCmd + ' 2>$ErrFile')
            $code = $LASTEXITCODE
            if ($code -eq 0) { break }
        }
        return $code
    }
    # Forma NOVA (corrigida): stdout para ARQUIVO e retorno tipado.
    function Invoke-KvPutFormaNova([string]$ErrFile, [string]$FakeCmd) {
        $code = 1; $intento = 0
        $stdoutFile = Join-Path $env:TEMP ('kvput_stdout_' + $PID + '.out')
        while ($intento -lt 3) {
            $intento++
            Invoke-Expression ($FakeCmd + ' 1>$stdoutFile 2>$ErrFile')
            $code = $LASTEXITCODE
            if ($code -eq 0) { break }
        }
        return [int]$code
    }

    $errFile = Join-Path $tmp 'err.txt'
    $antigo = Invoke-KvPutFormaAntiga $errFile $fakeCmd
    $novo = Invoke-KvPutFormaNova $errFile $fakeCmd

    Write-Host ('--- tipo da forma antiga: ' + $antigo.GetType().Name + ' | valor=[' + (@($antigo) -join ',') + '] ---')
    Assert (($antigo.GetType().Name) -eq 'Object[]') '1a: a forma antiga devolve ARRAY (o stdout vaza para o retorno)'
    Assert ([bool]($antigo -ne 0)) '1b: o chamador ANTIGO conclui "falhou" com exit code real = 0 (o defeito)'
    Assert (($novo.GetType().Name) -eq 'Int32') '1c: a forma nova devolve Int32 (corrigido)'
    Assert (-not [bool]($novo -ne 0)) '1d: o chamador NOVO conclui "ok" com o mesmo comando (corrigido)'
    Assert ([int]$novo -eq 0) '1e: e o valor devolvido e o exit code real do comando'

    Write-Host '=== Parte 2: estrutural contra scripts\predictive\reconciliar_ipe_cvm.ps1 ==='
    $alvo = Join-Path $PSScriptRoot 'predictive\reconciliar_ipe_cvm.ps1'
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($alvo, [ref]$tokens, [ref]$errors)
    Assert (@($errors).Count -eq 0) ('2a: o script alvo faz parse sem erro (obtido ' + @($errors).Count + ')')

    $fnPut = $null
    foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($f.Name -eq 'Invoke-WranglerKVPut') { $fnPut = $f }
    }
    Assert ($null -ne $fnPut) '2b: existe a funcao Invoke-WranglerKVPut'
    $fontePut = ''
    if ($fnPut) { $fontePut = $fnPut.Extent.Text }
    Assert ($fontePut -match '1>\$stdoutFile') '2c: o put captura o stdout do wrangler (ponta boa da correcao)'
    Assert (-not ($fontePut -match '--remote 2>\$ErrFile\s*$')) '2d: o put NAO tem mais a chamada sem captura de stdout (ponta ruim)'
    Assert ($fontePut -match 'return \[int\]\$code') '2e: o put devolve [int], nunca a colecao de saida'

    # A mesma classe de defeito existia no GET (so no caminho de retry): o Write-Log ecosava para
    # o fluxo de saida da funcao. Prova de que os dois caminhos foram fechados.
    $fnGet = $null
    foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($f.Name -eq 'Invoke-WranglerKVGet') { $fnGet = $f }
    }
    Assert ($null -ne $fnGet) '2f: existe a funcao Invoke-WranglerKVGet'
    $fonteGet = ''
    if ($fnGet) { $fonteGet = $fnGet.Extent.Text }
    Assert ($fonteGet -match 'Write-Log \("KV retry: ') '2g: o GET tem a linha de retry (contexto preservado)'
    Assert ($fonteGet -match '\| Out-Null') '2h: o eco do GET nao polui o retorno (| Out-Null)'
    Assert ($fonteGet -match 'return \[int\]\$code') '2i: o GET tambem devolve [int]'

    $texto = Get-Content -LiteralPath $alvo -Raw -Encoding UTF8
    Assert ($texto -match '\$kvCode -ne 0') '2j: o contrato do chamador continua o mesmo (testa o codigo)'
    Assert ($texto -match 'reconciliacao_kvput\.out') '2k: o stdout fica em arquivo para diagnostico de falha real'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
