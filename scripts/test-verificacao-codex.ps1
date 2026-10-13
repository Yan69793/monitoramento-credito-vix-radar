# Offline, extrai codigo real por AST. Nao chama CLI ou Worker.
param([string]$AlvoPath = (Join-Path $PSScriptRoot 'run_vixradar_verificacao_async.ps1'))
$ErrorActionPreference = 'Continue'
$script:Falhas = 0
function Assert-True([bool]$Cond, [string]$Nome) {
    if ($Cond) { Write-Host ('PASS ' + $Nome) }
    else { $script:Falhas++; Write-Host ('FAIL ' + $Nome) }
}
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($AlvoPath, [ref]$tokens, [ref]$errors)
Assert-True ($errors.Count -eq 0) 'parser PowerShell'
$defs = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)
foreach ($nome in @('Test-ClaudeAuthFailure', 'Get-VixCodexUsageProbe', 'Invoke-ClaudeBatch', 'Get-BalancedJson', 'Get-VeredictosArray', 'Get-VixParecerIncompleto')) {
    $def = $defs | Where-Object { $_.Name -eq $nome } | Select-Object -First 1
    if (-not $def) { Assert-True $false ('funcao presente ' + $nome); continue }
    Invoke-Expression $def.Extent.Text
}
if ($script:Falhas -gt 0) { exit 1 }
. (Join-Path $PSScriptRoot 'lib\vixradar-llm-provider.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1')
# COBERTURA-13OUT1 (2026-10-13): Invoke-ClaudeBatch usa Get-VixCodexArgsBase/Get-VixCodexPreambulo.
. (Join-Path $PSScriptRoot 'lib\vixradar-cobertura.ps1')
function Get-VixLlmProvider { return 'codex' }
Assert-True (Test-VixLlmProviderPermiteRotina -CodexAdapterHabilitado:$true) 'gate aceita Codex habilitado'
Assert-True (-not (Test-VixLlmProviderPermiteRotina -CodexAdapterHabilitado:$false)) 'gate bloqueia Codex ausente'
$texto = [IO.File]::ReadAllText($AlvoPath)
Assert-True ($texto.Contains('-CodexAdapterHabilitado:$codexAdapterHabilitado')) 'rotina usa gate comum com capability Codex'
function Write-Log([string]$Msg) { Write-Host $Msg }
function Set-VixClaudeAuthEnv { throw 'Claude nao pode ser chamado' }
function Invoke-VixOpenRouterLote { throw 'OpenRouter nao pode ser chamado' }
$LogDir = Join-Path $env:TEMP ('verif-codex-test-' + $PID)
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$DateTag = 'teste'
$ModelFallback = 'claude-sonnet-4-6'
$script:VixUsaCodex = $true
$script:VixUsaOpenRouter = $false
$script:MockModo = 'ok'
$script:CliArgs = @()
function codex {
    $Argumentos = @($args)
    foreach ($Prompt in $input) {
        $script:CliArgs = $Argumentos
        $global:LASTEXITCODE = 0
        if ($script:MockModo -eq 'falha') { $global:LASTEXITCODE = 1; return '{"type":"error","message":"falha de teste"}' }
        $outIndex = [array]::IndexOf($Argumentos, '-o')
        if ($script:MockModo -ne 'sem_arquivo') {
            $resposta = '[{"veredicto":"REPROVADO","confianca":0,"motivo":"EVIDENCIA_VAZIA","fontes_validas":[]}]'
            if ($script:MockModo -eq 'vazio') { $resposta = '' }
            Set-Content -LiteralPath $Argumentos[$outIndex + 1] -Value $resposta -Encoding UTF8
        }
        if ($script:MockModo -ne 'sem_usage') { return '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20}}' }
        return '{"type":"turn.completed"}'
    }
}
$promptTmp = Join-Path $LogDir 'prompt.txt'
Set-Content -LiteralPath $promptTmp -Value 'fixture sintetica offline' -Encoding UTF8
try {
    $r = Invoke-ClaudeBatch $promptTmp 'ignorado'
    Assert-True (-not $r.ProviderFalhou -and $r.ExitCode -eq 0) 'despacho Codex sem Claude/OpenRouter'
    Assert-True ($script:CliArgs -contains 'read-only' -and $script:CliArgs -contains '--ephemeral' -and $script:CliArgs -contains '--ignore-user-config') 'CLI isolado com sandbox somente leitura'
    Assert-True ($r.Tokens -eq 80 -and $r.Parcelas.cache_read -eq 40 -and $r.Parcelas.input -eq 60) 'usage real separado de cache lido'
    $v = Get-VeredictosArray $r.Output 1
    Assert-True ($v.Count -eq 1 -and -not (Get-VixParecerIncompleto $v[0])) 'parser e guard aceitam parecer completo'
    Assert-True ($null -eq (Get-VeredictosArray $r.Output 2)) 'parser rejeita resposta com parecer faltante'
    $invalid = '{"veredicto":"APROVADO","confianca":0.9,"motivo":"teste","fontes_validas":[]}' | ConvertFrom-Json
    Assert-True ((Get-VixParecerIncompleto $invalid) -eq 'aprovacao_sem_fonte') 'aprovacao sem evidencia bloqueada'
    foreach ($numero in @('NaN', 'Infinity', '-Infinity')) {
        $invalid.confianca = $numero
        Assert-True ((Get-VixParecerIncompleto $invalid) -eq 'confianca_fora_de_0_1') ('confianca nao finita bloqueada ' + $numero)
    }
    $corrigir = '{"veredicto":"CORRIGIR","confianca":0.9,"motivo":"teste offline","fontes_validas":["https://example.invalid/evidencia"],"correcoes":{"data_evento":"banana"}}' | ConvertFrom-Json
    Assert-True ((Get-VixParecerIncompleto $corrigir) -eq 'corrigir_sem_campo_aplicavel') 'CORRIGIR data banana nao retrata evento'
    $corrigir.correcoes = [pscustomobject]@{ titulo = 'Titulo valido da fixture' }
    $corrigir.confianca = 0.7
    Assert-True ((Get-VixParecerIncompleto $corrigir) -eq 'corrigir_confianca_abaixo_de_0_8') 'CORRIGIR abaixo do limiar real Worker bloqueado'
    $corrigir.confianca = 0.8
    Assert-True ((Get-VixParecerIncompleto $corrigir) -eq '') 'CORRIGIR titulo valido no limiar aceito'
    $hoje = [datetime]::UtcNow.AddHours(-3).Date
    foreach ($campos in @(
        @{ campo_ignorado = 'fixture' }, @{ titulo = 'curto' }, @{ titulo = ('x' * 241) },
        @{ classificacao = 'eco' }, @{ fonte_primaria = 'https://example.invalid/nao-consultada' },
        @{ data_evento = $hoje.AddDays(-36).ToString('yyyy-MM-dd') }, @{ data_evento = $hoje.AddDays(1).ToString('yyyy-MM-dd') }
    )) {
        $corrigir.correcoes = [pscustomobject]$campos
        Assert-True ((Get-VixParecerIncompleto $corrigir) -eq 'corrigir_sem_campo_aplicavel') ('CORRIGIR sem campo aplicavel ' + ($campos.Keys -join ','))
    }
    foreach ($campos in @(
        @{ classificacao = 'ECO' }, @{ fonte_primaria = 'https://example.invalid/evidencia' },
        @{ data_evento = $hoje.AddDays(-35).ToString('yyyy-MM-dd') }, @{ data_evento = $hoje.ToString('yyyy-MM-dd') }
    )) {
        $corrigir.correcoes = [pscustomobject]$campos
        Assert-True ((Get-VixParecerIncompleto $corrigir) -eq '') ('CORRIGIR campo suportado aceito ' + ($campos.Keys -join ','))
    }
    # Compara comportamento com a funcao REAL do Worker, nao outra fixture do schema.
    $workerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'api\src\worker.js'
    $workerText = [IO.File]::ReadAllText($workerPath)
    $startWorker = $workerText.IndexOf('function aplicarCorrecaoVerificador(ev, veredicto) {')
    $endWorker = $workerText.IndexOf('__name(aplicarCorrecaoVerificador,', $startWorker)
    Assert-True ($startWorker -ge 0 -and $endWorker -gt $startWorker) 'contrato Worker real encontrado'
    $nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
    Assert-True ([bool]$nodePath) 'Node disponivel para confronto com Worker real'
    if ($startWorker -ge 0 -and $endWorker -gt $startWorker -and $nodePath) {
        $jsPath = Join-Path $LogDir 'contrato-worker.cjs'
        $js = $workerText.Substring($startWorker, $endWorker - $startWorker)
        $js += "`nfunction obterAgoraBRT() { return new Date(Date.now()-3*60*60*1000); }"
        $js += "`nconst fs=require('node:fs');const casos=JSON.parse(fs.readFileSync(0,'utf8').replace(/^\uFEFF/,''));console.log(JSON.stringify(casos.map(v=>aplicarCorrecaoVerificador({},v))));"
        [IO.File]::WriteAllText($jsPath,$js,[Text.UTF8Encoding]::new($false))
        $casosWorker = @()
        $esperadosWorker = @()
        foreach ($campos in @(
            @{ data_evento='banana' }, @{ campo_ignorado='fixture' }, @{ titulo='curto' },
            @{ classificacao='eco' }, @{ fonte_primaria='https://example.invalid/outra' },
            @{ data_evento=$hoje.AddDays(-36).ToString('yyyy-MM-dd') },
            @{ data_evento=$hoje.AddDays(1).ToString('yyyy-MM-dd') },
            @{ data_evento=$hoje.AddDays(-35).ToString('yyyy-MM-dd') },
            @{ classificacao='ECO' }, @{ titulo='Titulo valido da fixture' },
            @{ fonte_primaria='https://example.invalid/evidencia' }
        )) {
            $caso = [pscustomobject]@{ veredicto='CORRIGIR'; confianca=0.9; motivo='teste'; fontes_validas=@('https://example.invalid/evidencia'); correcoes=[pscustomobject]$campos }
            $casosWorker += $caso
            $esperadosWorker += (-not (Get-VixParecerIncompleto $caso))
        }
        $casoBaixa = [pscustomobject]@{ veredicto='CORRIGIR'; confianca=0.7; motivo='teste'; fontes_validas=@('https://example.invalid/evidencia'); correcoes=[pscustomobject]@{titulo='Titulo valido da fixture'} }
        $casosWorker += $casoBaixa; $esperadosWorker += $false
        $realWorker = (($casosWorker | ConvertTo-Json -Depth 8 -Compress) | & $nodePath $jsPath) | ConvertFrom-Json
        Assert-True ($LASTEXITCODE -eq 0 -and @($realWorker).Count -eq $casosWorker.Count) 'funcao real Worker executada offline'
        for ($indice=0; $indice -lt $casosWorker.Count; $indice++) {
            Assert-True ($realWorker[$indice] -eq $esperadosWorker[$indice]) ('guard concorda com Worker real caso ' + $indice)
        }
    }
    foreach ($modo in @('falha', 'sem_arquivo', 'vazio')) {
        $script:MockModo = $modo
        $r = Invoke-ClaudeBatch $promptTmp 'ignorado'
        Assert-True ($r.ProviderFalhou) ('falha fechada ' + $modo)
    }
    $script:MockModo = 'sem_usage'
    $r = Invoke-ClaudeBatch $promptTmp 'ignorado'
    Assert-True ($r.UsageNaoMensuravel -and $r.Tokens -eq -1) 'ausencia de usage declarada sem zeros ficticios'
    Assert-True ($texto.Contains('if ($script:VixUsaCodex -and $stats.token_hard_hit)')) 'cap bloqueia lotes seguintes mesmo apos continue'
    $replayIf = $ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.IfStatementAst] -and $_.Clauses[0].Item1.Extent.Text -eq '$ReplayFilaPath' } | Select-Object -Last 1
    Assert-True ($null -ne $replayIf) 'ramo replay existente'
    if ($replayIf) {
        $replayText = $replayIf.Extent.Text
        Assert-True ($replayText -notmatch 'Invoke-WorkerJsonUtf8|Invoke-RestMethod|Send-VixRoutineAlert|Get-RoutineKey') 'replay sem chamadas Worker/alerta/credencial'
        $mutex = $texto.IndexOf('$__verifMutex =')
        Assert-True ($replayIf.Extent.StartOffset -lt $mutex) 'replay termina antes de reserva e preflight'
        # Executa ramo REAL em subprocesso com LLM mockado, rede substituida por excecao.
        $filaPath = Join-Path $LogDir 'fila.json'
        $outPath = Join-Path $LogDir 'resultado.json'
        @{ ok=$true; itens=@(@{ id='offline-1'; empresa='Fixture' }); system_prompt='fixture'; user_prompt='fixture' } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $filaPath -Encoding UTF8
        $childPath = Join-Path $LogDir 'replay-child.ps1'
        $functionText = ($defs | Where-Object { $_.Name -in @('Get-BalancedJson', 'Get-VeredictosArray', 'Get-VixParecerIncompleto') } | ForEach-Object { $_.Extent.Text }) -join "`r`n"
        $setup = @(
            'param([string]$ReplayFilaPath,[string]$ReplayOutPath,[int]$MaxEventos=1)',
            '$ErrorActionPreference = ''Continue''',
            '$LogDir = Split-Path -Parent $ReplayOutPath',
            '$script:VixUsaCodex=$true; $script:VixColetorAtivo=$false',
            'function Write-Log([string]$Msg) { Write-Host $Msg }',
            'function Get-VixBlocoColetorVerificacao($Itens) { return '''' }',
            'function Invoke-WorkerJsonUtf8 { throw ''REDE PROIBIDA'' }',
            'function Send-VixRoutineAlert { throw ''ALERTA PROIBIDO'' }',
            'function Invoke-ClaudeBatch { return @{ Output=@(''[{"veredicto":"REPROVADO","confianca":0,"motivo":"fixture offline","fontes_validas":[]}]''); ExitCode=0; ProviderFalhou=$false } }'
        ) -join "`r`n"
        [IO.File]::WriteAllText($childPath,($setup + "`r`n" + $functionText + "`r`n" + $replayText),[Text.UTF8Encoding]::new($true))
        $exe = (Get-Process -Id $PID).Path
        & $exe -NoProfile -ExecutionPolicy Bypass -File $childPath -ReplayFilaPath $filaPath -ReplayOutPath $outPath
        $childExit = $LASTEXITCODE
        $replayOut = Get-Content -LiteralPath $outPath -Raw | ConvertFrom-Json
        Assert-True ($childExit -eq 0 -and $replayOut.ok -and $replayOut.submit_ok -eq 0) 'replay real executado offline sem submit'
        & $exe -NoProfile -ExecutionPolicy Bypass -File $childPath -ReplayFilaPath $promptTmp -ReplayOutPath $outPath
        Assert-True ($LASTEXITCODE -eq 6) 'replay rejeita payload corrompido antes do LLM'
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($LogDir)
    if ($resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -eq ('verif-codex-test-' + $PID)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
Write-Host ('FALHAS=' + $script:Falhas)
if ($script:Falhas -gt 0) { exit 1 }
exit 0
