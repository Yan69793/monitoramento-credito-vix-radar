# smoke-openrouter.ps1 - chamada HTTP real MINIMA via adapter OpenRouter (Fase B D1, gate de credencial).
# Prova: autenticacao valida, modelo configurado acessivel, HTTP 2xx, resposta parseavel, envelope ok.
# NAO toca producao, NAO persiste VIXRADAR_LLM_PROVIDER, NAO liga outras rotinas.
#
# Seguranca: a chave e lida do ambiente em processo pela lib (Process->User->Machine) e nunca
# sai em comando, log, stdout, diff ou body exibido. Em falha, imprime SOMENTE a classificacao
# segura (codigo HTTP + duro/retryable/transporte), nunca o corpo do erro completo. O motivo
# completo fica disponivel com -VerboseMsgs para diagnostico local do operador.
#
# Uso (operador ou executor autorizado, com a chave real no ambiente User):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\smoke-openrouter.ps1
#   pwsh -NoProfile -File scripts\smoke-openrouter.ps1
# Opcional: $env:VIXRADAR_OPENROUTER_MODEL='<modelo>' antes, para sobrepor o default.

param([switch]$VerboseMsgs)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'lib\vixradar-openrouter.ps1')

$pronto = Test-VixOpenRouterPronto
if (-not $pronto.ok) {
    Write-Host ('SMOKE_OPENROUTER|exit=2|motivo=' + $pronto.motivo)
    exit 2
}

$tmp = Join-Path $env:TEMP ('or-smoke-prompt-' + $PID + '.txt')
Set-Content -Path $tmp -Value 'Responda somente com a palavra ACESSO_OK e nada mais.' -Encoding UTF8

$sw = New-Object System.Diagnostics.Stopwatch
$sw.Start()
$r = Invoke-VixOpenRouterLote -PromptPath $tmp -RetryDelays @(0, 0, 0)
$sw.Stop()
$lat = [Math]::Round($sw.Elapsed.TotalSeconds, 1)

try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch { }

if ($r.ExitCode -eq 0) {
    $e = $null
    try { $e = $r.Linhas[0] | ConvertFrom-Json } catch { $e = $null }
    if ($null -eq $e) {
        Write-Host 'SMOKE_OPENROUTER|exit=1|motivo=envelope nao parseavel apesar de HTTP 2xx'
        exit 1
    }
    $temOk = (('' + $e.result) -match 'ACESSO_OK')
    $urls = [regex]::Matches(('' + $e.result), 'https?://').Count
    $uso = $e.usage
    Write-Host ('SMOKE_OPENROUTER|exit=0|http=2xx|model=' + $e.model + '|result_chars=' + (('' + $e.result).Length) + '|ok_texto=' + $temOk.ToString().ToLower() + '|urls=' + $urls + '|trabalho=' + $r.Tokens + '|in=' + $uso.input_tokens + '|out=' + $uso.output_tokens + '|cache_read=' + $uso.cache_read_input_tokens + '|lat_s=' + $lat)
    if ($VerboseMsgs) { Write-Host ('VERBOSE resultado=' + $e.result) }
    exit 0
}

$cod = 0
if ($r.Linhas -and $r.Linhas[0] -match 'OPENROUTER_FALHA_COD=(\d+)') { $cod = [int]$Matches[1] }
$cls = 'duro'
if (Test-VixOpenRouterStatusRetryable $cod) { $cls = 'retryable' }
if ($cod -eq 0) { $cls = 'transporte' }
Write-Host ('SMOKE_OPENROUTER|exit=1|http_cod=' + $cod + '|class=' + $cls)
if ($VerboseMsgs) { Write-Host ('VERBOSE motivo=' + $r.Msg) }
exit 1
