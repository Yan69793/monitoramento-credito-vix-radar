$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'lib\vixradar-wrangler.ps1')
$script:f = 0
function A([bool]$c, [string]$n) { if ($c) { Write-Host ('PASS ' + $n) } else { Write-Host ('FAIL ' + $n); $script:f++ } }
A ((Get-VixWranglerFalhaClase 'Failed to fetch https://api.cloudflare.com/client/v4/accounts/x/storage/kv') -eq 'transitorio') 'transitorio: failed to fetch'
A ((Get-VixWranglerFalhaClase 'Request timed out') -eq 'transitorio') 'transitorio: timed out'
A ((Get-VixWranglerFalhaClase 'HTTP 429 Too Many Requests') -eq 'transitorio') 'transitorio: 429'
A ((Get-VixWranglerFalhaClase 'Error 401 Unauthorized') -eq 'auth') 'auth: 401'
A ((Get-VixWranglerFalhaClase 'Error 403 Forbidden') -eq 'auth') 'auth: 403'
A ((Get-VixWranglerFalhaClase 'Failed to fetch ... 401 Unauthorized') -eq 'auth') 'auth tem precedencia sobre transitorio'
A ((Get-VixWranglerFalhaClase 'key does not exist') -eq 'ausente') 'ausente: key not exist'
A ((Get-VixWranglerFalhaClase '') -eq 'outro') 'outro: vazio'
A ((Test-VixWranglerFalhaTransitoria 'Failed to fetch') -eq $true) 'test transitorio true'
A ((Test-VixWranglerFalhaTransitoria '401 Unauthorized') -eq $false) 'test transitorio false (auth)'
Write-Host ('RESULTADO: ' + $script:f + ' falha(s)')
if ($script:f -gt 0) { exit 1 }
exit 0
