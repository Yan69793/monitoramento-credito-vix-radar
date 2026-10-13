# test-verificacao-teto.ps1 - VERIF-TETO1 (2026-10-04), offline, sem rede e sem chave real.
# De 02 a 04/10 todo dreno da verificacao-async tomou 402 do OpenRouter pedindo 49152 tokens
# de conclusao, e o log registrava "parse de veredictos falhou" com erros_parse=1 e uma
# estimativa de 85000 a 120000 tokens cobrada contra o cap, sem nada gerado. Esta suite prova:
#   A. o teto exclusivo da verificacao (8192) chega ao adapter, e a falha de provider sai do
#      Invoke-ClaudeBatch marcada como provider, com causa e leitura da chave uma vez so;
#   B. resposta cortada no teto (finish_reason=length) volta marcada como truncada;
#   C. parecer incompleto e reprovado antes da submissao, das duas pontas;
#   D. no laco principal, falha de provider e truncamento saem ANTES do parse, sem erros_parse.
# Extrai as funcoes REAIS do script por AST. ASCII puro, roda no PowerShell 5.1 e no pwsh 7.
$ErrorActionPreference = 'Continue'
$script:fail = 0
$script:pass = 0

function Assert-True([bool]$cond, [string]$nome) {
    if ($cond) { $script:pass++; Write-Host ('PASS: ' + $nome) }
    else { $script:fail++; Write-Host ('FAIL: ' + $nome) }
}

$ScriptsDir = $PSScriptRoot
$AlvoPath = Join-Path $ScriptsDir 'run_vixradar_verificacao_async.ps1'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($AlvoPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { Write-Host ('FAIL: parse do script: ' + $errors[0].Message); exit 1 }
$defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
foreach ($nome in @('Test-ClaudeAuthFailure', 'Invoke-ClaudeBatch', 'Get-VixParecerIncompleto')) {
    $f = $defs | Where-Object { $_.Name -eq $nome } | Select-Object -First 1
    if (-not $f) { Write-Host ('FAIL: funcao ' + $nome + ' nao encontrada'); exit 1 }
    Invoke-Expression $f.Extent.Text
}
# Format-VixOpenRouterTentativa e New-VixOpenRouterTentativa vem da lib real.
. (Join-Path $ScriptsDir 'lib\vixradar-openrouter.ps1')
. (Join-Path $ScriptsDir 'lib\vixradar-custo.ps1')

# Ambiente minimo que o Invoke-ClaudeBatch le do escopo do script.
$script:LogLinhas = @()
function Write-Log([string]$msg) { $script:LogLinhas += $msg }
$LogDir = $env:TEMP
$DateTag = 'teste'
$ModelFallback = 'claude-sonnet-4-6'
$script:VixUsaOpenRouter = $true
$promptTmp = Join-Path $env:TEMP ('verif-teto-' + $PID + '.txt')
Set-Content -Path $promptTmp -Value 'prompt de teste' -Encoding UTF8

try {
    # ===== A. teto e falha de provider =====
    $MaxTokensVerificacao = 8192
    $script:ArgsVistos = $null
    $script:ChaveLida = 0
    function Get-VixOpenRouterChaveStatus { $script:ChaveLida++; return [pscustomobject]@{ ok = $true; limit = 5; limit_remaining = 0.01; usage = 4.99; is_free_tier = $false; erro = '' } }
    function Invoke-VixOpenRouterLote([string]$PromptPath, [string]$Tier = '', [int]$MaxTokens = 0) {
        $script:ArgsVistos = @{ Tier = $Tier; MaxTokens = $MaxTokens }
        $t1 = New-VixOpenRouterTentativa 1 'deepseek/deepseek-v4-pro-0813' $MaxTokens 402 '402_saldo_conta afford=2657' $null
        $t2 = New-VixOpenRouterTentativa 2 'deepseek/deepseek-v4-pro-0813' ([int]($MaxTokens / 2)) 402 '402_saldo_conta afford=2657' $null
        return @{ Linhas = @('OPENROUTER_FALHA_COD=402'); ExitCode = 1; Msg = 'OPENROUTER_HTTP_STATUS=402 x'; Status = 402; Modelo = 'm'; Intentos = 2; FallbackUsado = $false
            Tentativas = @($t1, $t2); Causa402 = 'saldo_conta'; Afford = [int64]2657; StopReason = ''; Truncado = $false; SemConsumo = $true; MaxTokensPedido = $MaxTokens }
    }
    $script:VixChaveStatusLida = $false
    $rA = Invoke-ClaudeBatch $promptTmp 'claude-sonnet-4-6'
    Assert-True ($script:ArgsVistos.MaxTokens -eq 8192 -and $script:ArgsVistos.Tier -eq 'FULL') 'A1 adapter recebe -MaxTokens 8192 no tier FULL'
    Assert-True ($rA.ProviderFalhou -eq $true -and $rA.SemConsumo -eq $true) 'A2 402 sai como ProviderFalhou, SemConsumo=true'
    Assert-True ($rA.Truncado -eq $false -and $rA.MaxTokensPedido -eq 8192) 'A3 sem truncamento, MaxTokensPedido 8192'
    Assert-True (@($script:LogLinhas | Where-Object { $_ -like 'OR_TENTATIVA|*' }).Count -eq 2) 'A4 uma linha OR_TENTATIVA por tentativa'
    Assert-True (@($script:LogLinhas | Where-Object { $_ -like 'OR_402|causa=saldo_conta|afford=2657|teto_pedido=8192' }).Count -eq 1) 'A5 linha OR_402 com causa, afford e teto'
    Assert-True (@($script:LogLinhas | Where-Object { $_ -like 'OR_CHAVE|ok=True|limit=5|limit_remaining=0.01|*' }).Count -eq 1) 'A6 estado da chave registrado so com numeros'
    $null = Invoke-ClaudeBatch $promptTmp 'claude-sonnet-4-6'
    Assert-True ($script:ChaveLida -eq 1) 'A7 leitura da chave acontece uma vez por execucao, nao por lote'
    Assert-True (@($script:LogLinhas | Where-Object { $_ -match '(?i)bearer|sk-or|or-fake' }).Count -eq 0) 'A8 nenhum segredo no log'

    # Ponta boa: sucesso nao vira falha de provider.
    $script:LogLinhas = @()
    function Invoke-VixOpenRouterLote([string]$PromptPath, [string]$Tier = '', [int]$MaxTokens = 0) {
        $env1 = '{"result":"[{\"veredicto\":\"REPROVADO\"}]","is_error":false,"model":"m","stop_reason":"stop","usage":{"input_tokens":900,"output_tokens":700,"cache_creation_input_tokens":0,"cache_read_input_tokens":100}}'
        $t1 = New-VixOpenRouterTentativa 1 'm' $MaxTokens 200 'ok stop=stop' $null
        return @{ Linhas = @($env1); ExitCode = 0; Msg = 'ok'; Status = 200; Modelo = 'm'; Intentos = 1; FallbackUsado = $false
            Tentativas = @($t1); Causa402 = ''; Afford = [int64]-1; StopReason = 'stop'; Truncado = $false; SemConsumo = $false; MaxTokensPedido = $MaxTokens }
    }
    $rA2 = Invoke-ClaudeBatch $promptTmp 'claude-sonnet-4-6'
    Assert-True ($rA2.ProviderFalhou -eq $false -and -not $rA2.Truncado -and $rA2.Tokens -eq 1600) 'A9 ponta boa: sucesso sem falha de provider, tokens 900+700'

    # ===== B. truncamento =====
    function Invoke-VixOpenRouterLote([string]$PromptPath, [string]$Tier = '', [int]$MaxTokens = 0) {
        $env1 = '{"result":"[{\"veredicto\":\"APRO","is_error":false,"model":"m","stop_reason":"length","usage":{"input_tokens":900,"output_tokens":8192,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}'
        return @{ Linhas = @($env1); ExitCode = 0; Msg = 'ok'; Status = 200; Modelo = 'm'; Intentos = 1; FallbackUsado = $false
            Tentativas = @(); Causa402 = ''; Afford = [int64]-1; StopReason = 'length'; Truncado = $true; SemConsumo = $false; MaxTokensPedido = $MaxTokens }
    }
    $rB = Invoke-ClaudeBatch $promptTmp 'claude-sonnet-4-6'
    Assert-True ($rB.Truncado -eq $true -and $rB.ProviderFalhou -eq $false) 'B1 finish_reason=length volta Truncado, nao falha de provider'
    # Envelope estilo claude (stop_reason=max_tokens) tambem e truncado, mesmo se o adapter nao marcar.
    function Invoke-VixOpenRouterLote([string]$PromptPath, [string]$Tier = '', [int]$MaxTokens = 0) {
        $env1 = '{"result":"[","is_error":false,"model":"m","stop_reason":"max_tokens","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}'
        return @{ Linhas = @($env1); ExitCode = 0; Msg = 'ok'; Status = 200; Tentativas = @(); Truncado = $false; StopReason = ''; MaxTokensPedido = $MaxTokens }
    }
    $rB2 = Invoke-ClaudeBatch $promptTmp 'claude-sonnet-4-6'
    Assert-True ($rB2.Truncado -eq $true -and $rB2.StopReason -eq 'max_tokens') 'B2 stop_reason=max_tokens no envelope tambem e truncado'

    # ===== C. parecer completo, das duas pontas =====
    $ok1 = '{"veredicto":"APROVADO","confianca":0.9,"motivo":"fonte confirma","fontes_validas":["https://www.cvm.gov.br/x"]}' | ConvertFrom-Json
    $ok2 = '{"veredicto":"REPROVADO","confianca":0,"motivo":"EVIDENCIA_VAZIA","fontes_validas":[]}' | ConvertFrom-Json
    $ok3 = '{"veredicto":"CORRIGIR","confianca":0.85,"motivo":"data errada","fontes_validas":["https://valor.globo.com/a"],"correcoes":{"data_evento":"2026-09-30"}}' | ConvertFrom-Json
    $ok4 = '{"veredicto":"APROVADO","confianca":"0.8","motivo":"ok","fontes_validas":["http://a.b/c"]}' | ConvertFrom-Json
    Assert-True ((Get-VixParecerIncompleto $ok1) -eq '') 'C1 APROVADO com fonte, confianca e motivo: completo'
    Assert-True ((Get-VixParecerIncompleto $ok2) -eq '') 'C2 REPROVADO sem fonte (coleta vazia): completo'
    Assert-True ((Get-VixParecerIncompleto $ok3) -eq '') 'C3 CORRIGIR com fonte e correcoes: completo'
    Assert-True ((Get-VixParecerIncompleto $ok4) -eq '') 'C4 confianca em string numerica: completo'
    $casosRuins = @(
        @{ j = '{"veredicto":"APROVADO","confianca":0.9,"motivo":"x","fontes_validas":[]}'; m = 'aprovacao_sem_fonte' },
        @{ j = '{"veredicto":"APROVADO","confianca":0.9,"motivo":"x"}'; m = 'aprovacao_sem_fonte' },
        @{ j = '{"veredicto":"APROVADO","confianca":0.9,"motivo":"x","fontes_validas":["cvm.gov.br sem esquema"]}'; m = 'aprovacao_sem_fonte' },
        @{ j = '{"veredicto":"CORRIGIR","confianca":0.9,"motivo":"x","fontes_validas":["https://a.b"]}'; m = 'corrigir_sem_correcoes' },
        @{ j = '{"veredicto":"CORRIGIR","confianca":0.9,"motivo":"x","fontes_validas":["https://a.b"],"correcoes":{}}'; m = 'corrigir_sem_correcoes' },
        @{ j = '{"veredicto":"APROVADO","motivo":"x","fontes_validas":["https://a.b"]}'; m = 'confianca_ausente' },
        @{ j = '{"veredicto":"APROVADO","confianca":1.5,"motivo":"x","fontes_validas":["https://a.b"]}'; m = 'confianca_fora_de_0_1' },
        @{ j = '{"veredicto":"REPROVADO","confianca":0.2,"motivo":"","fontes_validas":[]}'; m = 'motivo_vazio' },
        @{ j = '{"veredicto":"TALVEZ","confianca":0.5,"motivo":"x","fontes_validas":[]}'; m = 'veredicto_invalido:TALVEZ' }
    )
    foreach ($c in $casosRuins) {
        $got = Get-VixParecerIncompleto ($c.j | ConvertFrom-Json)
        Assert-True ($got -eq $c.m) ('C5 reprova ' + $c.m + ' (obtido: ' + $got + ')')
    }
    Assert-True ((Get-VixParecerIncompleto $null) -eq 'parecer_nulo') 'C6 parecer nulo reprovado'

    # ===== D. ordem no laco principal (estrutural, por AST) =====
    $txt = Get-Content -LiteralPath $AlvoPath -Raw
    $iProvider = $txt.IndexOf('if ($result.ProviderFalhou)')
    $iTrunc = $txt.IndexOf('if ($result.Truncado)')
    $iParse = $txt.IndexOf('$veredictos = Get-VeredictosArray')
    Assert-True ($iProvider -gt 0 -and $iTrunc -gt 0 -and $iParse -gt 0 -and $iProvider -lt $iTrunc -and $iTrunc -lt $iParse) 'D1 falha de provider e truncamento sao tratados antes do parse'
    $ifs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses.Count -ge 1 -and $n.Clauses[0].Item1.Extent.Text -eq '$result.ProviderFalhou' }, $true)
    $blocoProvider = if (@($ifs).Count -gt 0) { @($ifs)[0].Clauses[0].Item2.Extent.Text } else { '' }
    Assert-True ($blocoProvider -match 'falhas_provider\+\+' -and $blocoProvider -match '\bcontinue\b') 'D2 bloco de provider conta falhas_provider e pula o lote'
    Assert-True ($blocoProvider -notmatch 'erros_parse') 'D3 bloco de provider nao incrementa erros_parse'
    Assert-True ($blocoProvider -match 'SemConsumo' -and $blocoProvider -match 'Tokens lote=0') 'D4 recusa sem consumo nao cobra estimativa contra o cap'
    Assert-True ($txt -match 'Invoke-VixOpenRouterLote -PromptPath \$promptPath -Tier ''FULL'' -MaxTokens \$MaxTokensVerificacao') 'D5 chamada ao adapter passa o teto explicito'
    Assert-True ($txt -match '(?m)^\$MaxTokensVerificacao = 8192\s*$') 'D6 teto default da verificacao = 8192'
    Assert-True ($txt -match 'Get-VixParecerIncompleto \$veredictos\[\$j\]') 'D7 todo parecer do LLM passa pela checagem antes de entrar em confirmarItens'
    Assert-True ($txt -match 'if \(\$confirmarItens\.Count -eq 0\)') 'D8 lote sem parecer completo nao chama confirmar_verificacao'
}
finally {
    Remove-Item $promptTmp -Force -ErrorAction SilentlyContinue
}

Write-Host ('RESULTADO: ' + $script:pass + ' passaram, ' + $script:fail + ' falharam')
if ($script:fail -gt 0) { exit 1 }
exit 0
