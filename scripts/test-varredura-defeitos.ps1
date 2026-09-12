# test-varredura-defeitos.ps1 - D1/D4/D3/D2, offline via funcoes reais do motor.
# ASCII puro para PowerShell 5.1.
$ErrorActionPreference = 'Continue'
$fail = 0
$pass = 0

function Assert-True([bool]$cond, [string]$nome) {
    if ($cond) { $script:pass++; Write-Host ('PASS: ' + $nome) }
    else { $script:fail++; Write-Host ('FAIL: ' + $nome) }
}

function Get-MotorFuncDefs([string]$Path, [string[]]$Names) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw ('parse de ' + $Path + ' falhou: ' + $errors[0].Message) }
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $out = @()
    foreach ($name in $Names) {
        $f = $defs | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $f) { throw ('funcao ' + $name + ' nao encontrada em ' + $Path) }
        $out += $f.Extent.Text
    }
    return ,$out
}

$MotorPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_varredura.ps1'
foreach ($_def in (Get-MotorFuncDefs $MotorPath @('Get-NomeNormalizado', 'Get-VixLockState', 'Get-VixResumoLedger', 'Get-VixCodexUsageProbe', 'Get-VixCoberturaProviderCapability', 'Test-VixBuscaDegradada', 'ConvertTo-VixFonteEstrutural', 'Resolve-VixCoberturaFamilias'))) { Invoke-Expression $_def }

Write-Host '== D1 lock: PID vivo bloqueia, morto ou reutilizado e orfao =='
$tmp = Join-Path $env:TEMP ('vix-d1-' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$lock = Join-Path $tmp 'teste.lock'
$self = Get-Process -Id $PID
$selfStart = $self.StartTime.ToUniversalTime().ToString('o')
Set-Content -LiteralPath $lock -Value ("pid=$PID`ninicio_utc=$selfStart") -Encoding UTF8
$live = Get-VixLockState $lock 30
Assert-True ($live.bloqueia -and ($live.motivo -eq 'LOCK_VIVO')) 'D1a: PID vivo com inicio igual bloqueia'
Set-Content -LiteralPath $lock -Value ("pid=999999`ninicio_utc=$selfStart") -Encoding UTF8
$dead = Get-VixLockState $lock 30
Assert-True ((-not $dead.bloqueia) -and ($dead.motivo -eq 'LOCK_ORFAO_PID_MORTO')) 'D1b: PID morto e LOCK_ORFAO, assume sem remover manualmente'
Set-Content -LiteralPath $lock -Value ("pid=$PID`ninicio_utc=2000-01-01T00:00:00.0000000Z") -Encoding UTF8
$reused = Get-VixLockState $lock 30
Assert-True ((-not $reused.bloqueia) -and ($reused.motivo -eq 'LOCK_ORFAO_PID_REUTILIZADO')) 'D1c: PID reutilizado por inicio divergente e LOCK_ORFAO'

Write-Host '== D4 total: vem do ledger do dia, nao dos contadores da execucao =='
$ledger = Join-Path $tmp 'dia.log'
@(
    '2026-09-12 10:00:00 OK|Empresa A|FULL|NENHUM|0|True|ANALISADO|0'
    '2026-09-12 10:01:00 OK|Empresa B|SKIP|-|0|True|SKIP|0'
    '2026-09-12 10:02:00 OK|Empresa A|FULL|NENHUM|0|True|ANALISADO|0'
    '2026-09-12 10:03:00 OK|Empresa C|FULL|-|0|False|DEFERIDO|0'
) | Set-Content -LiteralPath $ledger -Encoding UTF8
$sumario = Get-VixResumoLedger $ledger
Assert-True ($sumario.total -eq 3) 'D4: Total do dia conta emissor unico do ledger, inclusive reinicio, e ignora contador atual'
Assert-True ($sumario.analisados -eq 1 -and $sumario.skips -eq 1 -and $sumario.deferidos -eq 1) 'D4b: resumo vem dos status gravados no ledger'

Write-Host '== D3 Codex: usage e medida so quando o JSON a emite =='
$usage = Get-VixCodexUsageProbe @('{"type":"turn.completed","usage":{"input_tokens":12,"output_tokens":34,"cache_creation_input_tokens":5,"cache_read_input_tokens":6}}')
Assert-True ($usage.mensuravel -and $usage.parcelas.input -eq 12 -and $usage.parcelas.output -eq 34) 'D3a: usage emitida pelo codex e capturada'
$unmeasured = Get-VixCodexUsageProbe @('{"type":"turn.completed"}')
Assert-True ((-not $unmeasured.mensuravel) -and $null -eq $unmeasured.parcelas) 'D3b: sem usage emitida publica NAO_MENSURAVEL, nunca zero'

Write-Host '== D2 cobertura: somente capability declarada pode nao ter HTTP =='
function New-Fonte([string]$prov, $http) {
    return [pscustomobject]@{ familia = 'emissor'; query = 'Empresa contexto'; timestamp = '2026-09-12T18:00:00Z'; provedor = $prov; status_http = $http; resultado = 'sem fato novo na janela'; classificacao = 'ok' }
}
$codexFonte = ConvertTo-VixFonteEstrutural (New-Fonte 'codex:web_search' $null)
Assert-True ($codexFonte.ok -and ($codexFonte.motivo -eq 'ok_sem_http_provider') -and $codexFonte.cobertura_parcial) 'D2a: codex declarado aceita status_http null e marca contrato parcial'
$openrouterSemHttp = ConvertTo-VixFonteEstrutural (New-Fonte 'openrouter:web_search' $null)
Assert-True ((-not $openrouterSemHttp.ok) -and ($openrouterSemHttp.motivo -eq 'sem_prova_sem_status_http')) 'D2b: provider HTTP sem status continua rejeitado'
$desconhecido = ConvertTo-VixFonteEstrutural (New-Fonte 'desconhecido:web_search' 200)
Assert-True ((-not $desconhecido.ok) -and ($desconhecido.motivo -eq 'sem_prova_provedor_desconhecido')) 'D2c: provider desconhecido continua rejeitado'
$codexSemCampo = [pscustomobject]@{ familia = 'emissor'; query = 'Empresa contexto'; timestamp = '2026-09-12T18:00:00Z'; provedor = 'codex:web_search'; resultado = 'sem fato novo na janela'; classificacao = 'ok' }
$semCampo = ConvertTo-VixFonteEstrutural $codexSemCampo
Assert-True ((-not $semCampo.ok) -and ($semCampo.motivo -eq 'sem_prova_sem_status_http')) 'D2d: status_http ausente continua rejeitado mesmo para codex'
$familias = [pscustomobject]@{ fontes_consultadas = @(
    (New-Fonte 'codex:web_search' $null),
    [pscustomobject]@{ familia = 'divida'; query = 'Empresa divida'; timestamp = '2026-09-12T18:00:00Z'; provedor = 'codex:web_search'; status_http = $null; resultado = 'sem fato novo'; classificacao = 'ok' },
    [pscustomobject]@{ familia = 'fato'; query = 'Empresa CVM'; timestamp = '2026-09-12T18:00:00Z'; provedor = 'codex:web_search'; status_http = $null; resultado = 'sem fato novo'; classificacao = 'ok' }
) }
$cobertura = Resolve-VixCoberturaFamilias $familias
Assert-True ($cobertura.ok -and $cobertura.cobertura_parcial -and (($cobertura.contratos_provedor -join ',') -eq 'cobertura_parcial_provider_codex')) 'D2d: cobertura parcial traz contrato especifico do provider'

Write-Host '== D2 retry Codex: o prompt preserva provider e excecao declarada =='
$tokensPrompt = $null; $errorsPrompt = $null
$motorAst = [System.Management.Automation.Language.Parser]::ParseFile($MotorPath, [ref]$tokensPrompt, [ref]$errorsPrompt)
$retryCalls = $motorAst.FindAll({
    param($n)
    if ($n -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
    if ($n.CommandElements.Count -lt 2 -or $n.CommandElements[0].Extent.Text -ne 'New-BatchPrompt') { return $false }
    return ($n.Extent.Text -match '\$missing')
}, $true)
Assert-True (($retryCalls.Count -eq 1) -and ($retryCalls[0].Extent.Text -match '\$janFim\s+\$fonteProvedor\s+-Ultra:\$job\.Ultra')) 'D2e: retry repassa fonteProvedor ao New-BatchPrompt'
$promptDef = $motorAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-BatchPrompt' }, $true) | Select-Object -First 1
$promptText = if ($promptDef) { $promptDef.Extent.Text } else { '' }
Assert-True (($promptText -match '"provedor":"\$FonteProvedor:web_search\|web_fetch"') -and ($promptText -match 'somente provedor "codex" pode emitir "status_http":null') -and ($promptText -match 'Todo outro provedor exige status_http inteiro 2xx')) 'D2f: prompt do retry Codex declara codex:web_search|web_fetch e excecao sem HTTP'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: pass=' + $pass + ' fail=' + $fail)
if ($fail -gt 0) { exit 1 } else { exit 0 }
