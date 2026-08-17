param(
    [string]$Url = 'https://radar-credito-api.prospects-intel.workers.dev'
)

# Portao de verificacao do CLAUDE.md. Le o health, imprime a saida crua para colar
# na resposta e sai com codigo 1 se qualquer flag obrigatoria nao vier true.
# Sem isso o curl sai 0 mesmo com ok:false e a task do VS Code fica verde com o
# sistema doente, que foi o modo de falha do ADMIN_EMAIL ausente por 3 dias.
$ErrorActionPreference = 'Continue'

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$body = & curl.exe -s $Url
$sw.Stop()
$tempo = [math]::Round($sw.Elapsed.TotalSeconds, 2)

Write-Host $body
Write-Host ''
Write-Host ("URL: " + $Url)
Write-Host ("TEMPO: " + $tempo + "s")
Write-Host ''

if (-not $body) {
    Write-Host 'PORTAO REPROVADO: resposta vazia' -ForegroundColor Red
    exit 1
}

$j = $null
try { $j = $body | ConvertFrom-Json } catch { $j = $null }
if ($null -eq $j) {
    Write-Host 'PORTAO REPROVADO: resposta nao e JSON' -ForegroundColor Red
    exit 1
}

# kv, rate_limiter e telemetria vivem dentro de "bindings", o resto e raiz.
# A busca tenta os dois niveis para nao quebrar se o shape do health mudar.
function Get-FlagHealth {
    param($Doc, [string]$Nome)
    $p = $Doc.PSObject.Properties[$Nome]
    if ($null -ne $p) { return $p.Value }
    $b = $Doc.PSObject.Properties['bindings']
    if ($null -ne $b -and $null -ne $b.Value) {
        $pb = $b.Value.PSObject.Properties[$Nome]
        if ($null -ne $pb) { return $pb.Value }
    }
    return $null
}

# Os 4 primeiros sao o portao do CLAUDE.md. Os 3 ultimos derrubam o canonical-test.
$obrigatorias = @('ok', 'kv', 'telemetria', 'sentry_ok', 'rate_limiter', 'admin_email_ok', 'verificador_ok')
$falhas = @()
foreach ($k in $obrigatorias) {
    $v = Get-FlagHealth -Doc $j -Nome $k
    if ($null -eq $v) {
        $falhas += ($k + '=ausente')
        continue
    }
    if ($v -ne $true) {
        $falhas += ($k + '=' + [string]$v)
    }
}

if ($falhas.Count -gt 0) {
    Write-Host ('PORTAO REPROVADO: ' + ($falhas -join ', ')) -ForegroundColor Red
    exit 1
}

Write-Host ('PORTAO OK: ' + ($obrigatorias -join ', ')) -ForegroundColor Green
exit 0
