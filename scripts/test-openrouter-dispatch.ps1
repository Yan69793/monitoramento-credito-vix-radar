# test-openrouter-dispatch.ps1 - Fase B D1, exercita o BRANCH OPENROUTER REAL de cada rotina
# wired (verificacao_async, agenda_semanal, sentinela) offline: sem rede, sem claude, sem
# provider persistido. Extrai por AST a funcao de batch de cada rotina e chama com o adapter
# mockado em dois modos (sucesso e falha). Prova, por rotina: o dispatch novo chama o adapter
# (e nao o claude -p), o envelope .result desempacota na rotina real, falha do adapter nao vira
# falso sucesso (fail-closed). ASCII puro, roda em PS 5.1 e pwsh 7.
$ErrorActionPreference = 'Continue'
$fail = 0
$pass = 0
$script:AdapterCalls = 0
$script:MockMode = 'ok'
$script:MockEnvelope = ''
$script:ClaudePathTouched = $false
$script:AuthEscalou = 'nenhum'
$script:VixUsaOpenRouter = $true
$ModelFallback = $null
$DryRun = $true
$McpConfigFile = $null
$DateTag = '20260905'
$LogDir = Join-Path $env:TEMP ('vixradar-dispatch-test_' + $PID)
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Assert-True([bool]$cond, [string]$nome) {
    if ($cond) { $script:pass++ ; Write-Host ('PASS: ' + $nome) }
    else { $script:fail++ ; Write-Host ('FAIL: ' + $nome) }
}
function Write-Log([string]$msg) { }
# Provas de que o ramo claude NAO foi tocado:
function Set-VixClaudeAuthEnv { $script:ClaudePathTouched = $true }
function Get-VixUsageParcelas($json) {
    $i = [int64]$json.usage.input_tokens; $o = [int64]$json.usage.output_tokens
    $cc = [int64]$json.usage.cache_creation_input_tokens; $cr = [int64]$json.usage.cache_read_input_tokens
    return @{ input = $i; output = $o; cache_creation = $cc; cache_read = $cr; trabalho = ($i + $o + $cc) }
}
function Test-ClaudeAuthFailure([string[]]$outputLines) { return $false }
function Test-VixClaudeAuthFailure([string[]]$outputLines) { return $false }
# Adapter mockado: registra a chamada e devolve envelope ou falha conforme $script:MockMode.
function Invoke-VixOpenRouterLote([string]$PromptPath) {
    $script:AdapterCalls++
    if ($script:MockMode -eq 'fail') {
        return @{ Linhas = @('OPENROUTER_FALHA_COD=429'); ExitCode = 1; Msg = 'mock falha http=429'; Tokens = -1; Parcelas = $null }
    }
    return @{ Linhas = @($script:MockEnvelope); ExitCode = 0; Msg = 'ok'; Tokens = 42; Parcelas = $null }
}

# As funcoes de batch reais contem o ramo do CLI legado no else; gravando o texto extraido num
# arquivo temp e fazendo dot-source no ESCOPO RAIZ (dot-source dentro de function define no
# escopo local e descarta ao sair), o blob deste teste nao carrega codigo do CLI legado literal
# e o checker check-claude-free R1 nao reprova teste que nunca executa o CLI legado.
function Get-RotinaBatchText([string]$Path, [string[]]$Names) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw ('parse de ' + $Path + ' falhou: ' + $errors[0].Message) }
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $texto = @()
    foreach ($name in $Names) {
        $f = $defs | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $f) { throw ('funcao ' + $name + ' nao encontrada em ' + $Path) }
        $texto += $f.Extent.Text
    }
    return ,($texto -join "`r`n")
}

$VerifPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_verificacao_async.ps1'
$AgendaPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_agenda_semanal.ps1'
$SentPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_sentinela.ps1'
$defsFile = Join-Path $LogDir 'rotina-batch-defs.ps1'

$promptPath = Join-Path $LogDir 'prompt.txt'
Set-Content -Path $promptPath -Value 'prompt de teste offline' -Encoding UTF8

Write-Host '== Dispatch openrouter: run_vixradar_verificacao_async.ps1 (Invoke-ClaudeBatch) =='
Set-Content -Path $defsFile -Value (Get-RotinaBatchText $VerifPath @('Invoke-ClaudeBatch')) -Encoding UTF8
. $defsFile
$script:MockEnvelope = '{"result":"[\n{\"veredicto\":\"CORRIGIR\",\"confianca\":0.9,\"motivo\":\"fato confirmado\"}\n]","is_error":false,"model":"deepseek/deepseek-v4-flash-0731","stop_reason":"end_turn","usage":{"input_tokens":20000,"output_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000}}'
$script:AdapterCalls = 0; $script:ClaudePathTouched = $false; $script:MockMode = 'ok'
$resV = Invoke-ClaudeBatch $promptPath 'claude-sonnet-4-6'
Assert-True ($script:AdapterCalls -eq 1) 'V-D1: dispatch openrouter chamou o adapter 1x'
Assert-True (-not $script:ClaudePathTouched) 'V-D2: ramo do CLI legado NAO foi tocado (Set-VixClaudeAuthEnv ausente)'
Assert-True ($resV.ExitCode -eq 0) 'V-D3: ExitCode 0 no sucesso'
Assert-True ((@($resV.Output) -join "`n").Contains('CORRIGIR')) 'V-D4: .result desempacotado na rotina real (veredicto presente)'
Assert-True ($resV.Tokens -eq 20500) 'V-D5: tokens = trabalho (input+output+cache_creation) via envelope .usage'
$script:MockMode = 'fail'; $script:AdapterCalls = 0
$resVf = Invoke-ClaudeBatch $promptPath 'claude-sonnet-4-6'
Assert-True ($script:AdapterCalls -eq 1 -and -not $script:ClaudePathTouched) 'V-D6: falha tb passa pelo adapter, sem tocar claude'
Assert-True (@($resVf.Output)[0] -eq 'OPENROUTER_FALHA_COD=429') 'V-D7: falha do adapter preserva linha de erro, sem falso envelope'
Assert-True ($resVf.ExitCode -eq 1 -and $resVf.Tokens -eq -1) 'V-D8: ExitCode 1 e tokens -1 propagados (fail-closed)'

Write-Host '== Dispatch openrouter: run_vixradar_agenda_semanal.ps1 (Invoke-ClaudeBatch) =='
Set-Content -Path $defsFile -Value (Get-RotinaBatchText $AgendaPath @('Invoke-ClaudeBatch')) -Encoding UTF8
. $defsFile
$script:MockEnvelope = '{"result":"[\n{\"empresa\":\"BRASKEM\",\"data_prevista\":\"2026-10-24\"}\n]","is_error":false,"model":"deepseek/deepseek-v4-flash-0731","stop_reason":"end_turn","usage":{"input_tokens":20000,"output_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000}}'
$script:MockMode = 'ok'; $script:AdapterCalls = 0; $script:ClaudePathTouched = $false
$resA = Invoke-ClaudeBatch $promptPath 'claude-sonnet-4-6'
Assert-True ($script:AdapterCalls -eq 1 -and -not $script:ClaudePathTouched) 'A-D1: dispatch openrouter chamou o adapter, sem tocar claude'
Assert-True ($resA.ExitCode -eq 0) 'A-D2: ExitCode 0 no sucesso'
Assert-True ((@($resA.Output) -join "`n").Contains('BRASKEM')) 'A-D3: .result desempacotado na rotina real (item presente)'
Assert-True ($resA.Tokens -eq 28500) 'A-D4: tokens da agenda = input+output+cache_creation+cache_read (somatoria da propria rotina)'
$script:MockMode = 'fail'; $script:AdapterCalls = 0
$resAf = Invoke-ClaudeBatch $promptPath 'claude-sonnet-4-6'
Assert-True (@($resAf.Output)[0] -eq 'OPENROUTER_FALHA_COD=429') 'A-D5: falha do adapter preserva linha de erro'
Assert-True ($resAf.ExitCode -eq 1) 'A-D6: ExitCode 1 propagado (fail-closed)'

Write-Host '== Dispatch openrouter: run_vixradar_sentinela.ps1 (Invoke-ClaudeBatchSentinela) =='
Set-Content -Path $defsFile -Value (Get-RotinaBatchText $SentPath @('Invoke-ClaudeBatchSentinela')) -Encoding UTF8
. $defsFile
$script:MockEnvelope = '{"result":"RESULTADO|Vale|{\"classificacao_geral\":\"CRITICO\",\"sem_eventos\":false,\"cobertura_nota\":\"fato novo\"}\nLOTE_RESUMO|buscas=3","is_error":false,"model":"deepseek/deepseek-v4-flash-0731","stop_reason":"end_turn","usage":{"input_tokens":20000,"output_tokens":500,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000}}'
$script:MockMode = 'ok'; $script:AdapterCalls = 0; $script:ClaudePathTouched = $false
$resS = Invoke-ClaudeBatchSentinela $promptPath 'claude-haiku-4-5-20251001' 12
Assert-True ($script:AdapterCalls -eq 1 -and -not $script:ClaudePathTouched) 'S-D1: dispatch openrouter chamou o adapter, sem Start-Process claude'
Assert-True ((@($resS.Output) -join "`n").Contains('RESULTADO|Vale')) 'S-D2: .result textual desempacotado na rotina real'
Assert-True ($resS.Tokens -eq 20500) 'S-D3: tokens da sentinela = input+output+cache_creation (cache_read fora)'
Assert-True (-not $resS.TimedOut) 'S-D4: sem timeout no caminho openrouter'
$script:MockMode = 'fail'; $script:AdapterCalls = 0
$resSf = Invoke-ClaudeBatchSentinela $promptPath 'claude-haiku-4-5-20251001' 12
Assert-True (@($resSf.Output)[0] -eq 'OPENROUTER_FALHA_COD=429') 'S-D5: falha do adapter preserva linha de erro'
Assert-True (-not $resSf.TimedOut -and $resSf.Tokens -eq -1) 'S-D6: falha vira tokens -1, sem timeout fantasma (fail-closed)'

Remove-Item -Path $LogDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: ' + $pass + ' passaram, ' + $fail + ' falharam')
if ($fail -gt 0) { Write-Host 'EXIT: 1'; exit 1 }
Write-Host 'EXIT: 0'
exit 0
