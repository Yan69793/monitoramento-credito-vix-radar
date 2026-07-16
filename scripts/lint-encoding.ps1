# lint-encoding.ps1 — Detecta .ps1 agendado sem BOM com bytes nao-ASCII.
# ASCII puro (roda no powershell.exe 5.1 sem risco de parse).
# Uso:
#   pwsh lint-encoding.ps1           # scan reporta problemas
#   pwsh lint-encoding.ps1 -Fix      # scan + adiciona BOM UTF-8 onde seguro
#   pwsh lint-encoding.ps1 -Json     # saida JSON para pipe/CI
param(
    [switch]$Fix,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# Diretorios de scripts do workspace
$ScanDirs = @(
    'E:\Diretorio\Claude\Monitoramento de Credito\scripts',
    'E:\Diretorio\Claude\relatorio-diario-szuchmacher\scripts',
    'E:\Diretorio\Claude\Site\site-producao\scripts',
    'E:\Diretorio\Claude\Site\automacao-yan-os\agents'
)

# Arquivos que NAO devem ser verificados (terceiros, legados imexiveis)
$ExcludePatterns = @(
    '*\node_modules\*',
    '*\venv\*',
    '*\__pycache__\*',
    '*\_archive\*',
    '*\_arquivo-legado*\*'
)

function Test-HasBOM([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 3) { return $false }
    # BOM UTF-8 = 0xEF 0xBB 0xBF
    return ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Test-HasNonAscii([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    foreach ($b in $bytes) {
        if ($b -gt 0x7F) { return $true }
    }
    return $false
}

function Add-UTF8BOM([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return $false  # ja tem BOM
    }
    $withBOM = New-Object byte[] (3 + $bytes.Length)
    $withBOM[0] = 0xEF; $withBOM[1] = 0xBB; $withBOM[2] = 0xBF
    [Array]::Copy($bytes, 0, $withBOM, 3, $bytes.Length)
    [System.IO.File]::WriteAllBytes($Path, $withBOM)
    return $true
}

Write-Host "=== LINT ENCODING SCRIPTS .PS1 ===" -ForegroundColor Cyan
Write-Host "Modo: $(if ($Fix) { 'CORRECAO' } else { 'SCAN (readonly)' })"
Write-Host ''

$total = 0
$clean = 0
$bomOk = 0
$noNonAscii = 0
$fixed = 0
$problematicos = @()
$fixaveis = @()

foreach ($dir in $ScanDirs) {
    if (-not (Test-Path $dir)) {
        if (-not $Json) { Write-Host "  DIR AUSENTE: $dir" -ForegroundColor DarkGray }
        continue
    }
    $files = Get-ChildItem $dir -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $fullPath = $f.FullName
        $skip = $false
        foreach ($excl in $ExcludePatterns) {
            if ($fullPath -like $excl) { $skip = $true; break }
        }
        if ($skip) { continue }

        $total++
        $hasBOM = Test-HasBOM $fullPath
        $hasNonAscii = Test-HasNonAscii $fullPath

        if (-not $hasNonAscii) {
            # Arquivo ASCII puro - seguro independente de BOM
            $noNonAscii++
            if (-not $Json) { Write-Host "  OK ASCII  $fullPath" -ForegroundColor DarkGray }
            continue
        }

        if ($hasBOM) {
            # UTF-8 com BOM e nao-ASCII - OK, 5.1 le corretamente
            $bomOk++
            if (-not $Json) { Write-Host "  OK BOM   $fullPath" -ForegroundColor DarkGray }
            continue
        }

        # PROBLEMA: tem nao-ASCII mas NAO tem BOM
        # powershell.exe 5.1 vai decodificar como ANSI -> risco de quebra
        $prob = [ordered]@{
            path        = $fullPath
            hasBOM      = $false
            hasNonAscii = $true
            risk        = 'ALTO - powershell.exe 5.1 decodifica como ANSI'
            fixavel     = $true
            fixado      = $false
        }

        if ($Fix) {
            $ok = Add-UTF8BOM $fullPath
            if ($ok) {
                $prob.fixado = $true
                $fixed++
                if (-not $Json) { Write-Host "  FIXED    $fullPath" -ForegroundColor Green }
            } else {
                if (-not $Json) { Write-Host "  FAIL FIX $fullPath" -ForegroundColor Red }
            }
        } else {
            $fixaveis += $prob
            if (-not $Json) { Write-Host "  PROBLEMA $fullPath" -ForegroundColor Yellow }
        }
        $problematicos += $prob
    }
}

# Sumario
Write-Host ''
Write-Host "=== SUMARIO ===" -ForegroundColor Cyan
Write-Host "Total escaneado : $total"
Write-Host "ASCII puro (OK) : $noNonAscii"
Write-Host "UTF-8+BOM (OK)  : $bomOk"
Write-Host "Sem BOM + nao-ASCII (RISCO): $($problematicos.Count)"
if ($Fix) { Write-Host "Corrigidos       : $fixed" }

if ($Json) {
    $output = [ordered]@{
        total       = $total
        asciiOk     = $noNonAscii
        bomOk       = $bomOk
        risco       = $problematicos.Count
        fixed       = $fixed
        arquivos    = $problematicos
    }
    $output | ConvertTo-Json -Depth 4 | Write-Output
}

if ($problematicos.Count -eq 0) {
    Write-Host 'Nenhum arquivo de risco encontrado.' -ForegroundColor Green
    exit 0
} else {
    if (-not $Fix) {
        Write-Host ''
        Write-Host "Execute com -Fix para adicionar BOM UTF-8 aos $($problematicos.Count) arquivos." -ForegroundColor Yellow
    }
    exit [Math]::Min($problematicos.Count, 255)
}
