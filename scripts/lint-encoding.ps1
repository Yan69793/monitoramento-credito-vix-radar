# lint-encoding.ps1 - Reprova .ps1 que nao roda sob powershell.exe 5.1.
# ASCII puro e sem BOM por design: este arquivo precisa ser imune ao bug que detecta.
#
# Duas classes de falha sao verificadas, porque BOM sozinho nao cobre as duas:
#   1. ENCODING: nao-ASCII sem BOM. O powershell.exe 5.1 le arquivo sem BOM como
#      ANSI/CP1252, e o byte 0x94 do travessao (U+2014) vira aspa curva U+201D, que
#      o parser aceita como delimitador de string e quebra o script.
#   2. SINTAXE: recurso exclusivo de PS 6/7 (ternario, ??, ?., -MaximumRetryCount,
#      ConvertFrom-Json -AsHashtable). Nao tem nada a ver com BOM e passa batido
#      por qualquer checagem de encoding.
#
# A checagem que cobre as duas e simplesmente: o arquivo parseia no 5.1?
#
# Uso:
#   powershell.exe -NoProfile -File scripts/lint-encoding.ps1
#   powershell.exe -NoProfile -File scripts/lint-encoding.ps1 -Fix
#   powershell.exe -NoProfile -File scripts/lint-encoding.ps1 -Path a.ps1,b.ps1
#   powershell.exe -NoProfile -File scripts/lint-encoding.ps1 -Json
param(
    [string[]]$Path,
    [switch]$Fix,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$ExcludePatterns = @(
    '*\node_modules\*',
    '*\venv\*',
    '*\__pycache__\*',
    '*\_archive\*',
    '*\graphify-out\*',
    '*\_arquivo-legado*\*'
)

function Test-HasBOM([byte[]]$Bytes) {
    if ($Bytes.Length -lt 3) { return $false }
    return ($Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
}

function Test-HasNonAscii([byte[]]$Bytes) {
    foreach ($b in $Bytes) { if ($b -gt 0x7F) { return $true } }
    return $false
}

# O parser do host so vale se o host for 5.1. Sob pwsh 7 o ternario parseia sem erro
# e o detector daria verde no exato bug que motivou este script, entao delega ao 5.1.
$NeedsDelegation = ($PSVersionTable.PSVersion.Major -ge 6)

function Get-ParseErrorCount([string]$File) {
    if ($NeedsDelegation) {
        $cmd = '$t=$null;$e=$null;[System.Management.Automation.Language.Parser]::ParseFile(' +
               "'$File'" + ',[ref]$t,[ref]$e)|Out-Null;$e.Count'
        $out = & powershell.exe -NoProfile -NonInteractive -Command $cmd 2>$null
        return [int]($out | Select-Object -Last 1)
    }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$tokens, [ref]$errors) | Out-Null
    return $errors.Count
}

function Add-UTF8BOM([string]$File, [byte[]]$Bytes) {
    $withBOM = New-Object byte[] (3 + $Bytes.Length)
    $withBOM[0] = 0xEF; $withBOM[1] = 0xBB; $withBOM[2] = 0xBF
    [Array]::Copy($Bytes, 0, $withBOM, 3, $Bytes.Length)
    [System.IO.File]::WriteAllBytes($File, $withBOM)
}

# Sem -Path explicito, varre a raiz do repo. Usa git para achar a raiz, o que faz o
# linter funcionar em worktree, clone novo e CI, ao contrario do caminho fixo anterior.
$scanAll = (-not $Path -or $Path.Count -eq 0)
if ($scanAll) {
    $repoRoot = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $repoRoot) {
        $repoRoot = $repoRoot -replace '/', '\'
        # Somente os .ps1 que o git rastreia. Varrer o diretorio pegaria outros worktrees,
        # _historico e copias legadas: 21 falsos positivos em 23. Detector ruidoso e
        # detector ignorado, que foi como a versao anterior deste script morreu.
        $Path = @(& git ls-files '*.ps1' | ForEach-Object { Join-Path $repoRoot ($_ -replace '/', '\') })
        if (-not $Path -or $Path.Count -eq 0) { $Path = @($repoRoot) }
    } else {
        $Path = @((Split-Path -Parent $PSScriptRoot))
    }
}

# Aceita tanto -Path a,b (array) quanto -Path "a,b" (string unica), porque o hook
# invoca via powershell.exe -File, onde o binder nao divide string entre aspas.
if ($Path) { $Path = $Path | ForEach-Object { $_ -split ',' } | Where-Object { $_ } }

$arquivos = @()
foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $item = Get-Item -LiteralPath $p
    if ($item.PSIsContainer) {
        $arquivos += Get-ChildItem $item.FullName -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue |
                     Select-Object -ExpandProperty FullName
    } elseif ($item.Extension -eq '.ps1') {
        $arquivos += $item.FullName
    }
}

$arquivos = $arquivos | Sort-Object -Unique | Where-Object {
    $f = $_
    $skip = $false
    foreach ($excl in $ExcludePatterns) { if ($f -like $excl) { $skip = $true; break } }
    -not $skip
}

if (-not $Json) {
    Write-Host "=== LINT .PS1 (compatibilidade powershell.exe 5.1) ===" -ForegroundColor Cyan
    Write-Host "Modo: $(if ($Fix) { 'CORRECAO' } else { 'SCAN (readonly)' })   Arquivos: $($arquivos.Count)"
    Write-Host ''
}

$problemas = @()
$fixed = 0
$okCount = 0

foreach ($f in $arquivos) {
    $bytes = [System.IO.File]::ReadAllBytes($f)
    $hasBOM = Test-HasBOM $bytes
    $hasNonAscii = Test-HasNonAscii $bytes

    if ($Fix -and $hasNonAscii -and -not $hasBOM) {
        Add-UTF8BOM $f $bytes
        $fixed++
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $hasBOM = $true
        if (-not $Json) { Write-Host "  BOM ADD  $f" -ForegroundColor Green }
    }

    $riscoEncoding = ($hasNonAscii -and -not $hasBOM)
    $parseErros = Get-ParseErrorCount $f

    if (-not $riscoEncoding -and $parseErros -eq 0) {
        $okCount++
        continue
    }

    $motivo = @()
    if ($riscoEncoding) { $motivo += 'nao-ASCII sem BOM (5.1 le como ANSI)' }
    if ($parseErros -gt 0) { $motivo += "$parseErros erro(s) de parse no 5.1" }

    $problemas += [ordered]@{
        path        = $f
        hasBOM      = $hasBOM
        hasNonAscii = $hasNonAscii
        parseErros  = $parseErros
        motivo      = ($motivo -join ' + ')
    }
    if (-not $Json) { Write-Host "  REPROVA  $f" -ForegroundColor Red -NoNewline; Write-Host "  [$($motivo -join ' + ')]" -ForegroundColor Yellow }
}

# === Checagem 3: CRLF em script executado por sh/bash =======================
# scripts/hooks/* e *.sh rodam sob sh. Um CR no fim da linha do shebang produz
# "bad interpreter: /bin/sh^M" e o script simplesmente nao executa. O git nao
# denuncia: o .gitattributes marca esses caminhos como `text`, e o atributo
# `text` faz a comparacao ignorar fim de linha, entao arquivo quebrado no disco
# passa por limpo no `git status`. Achado em 24/08/2026 com 3 .sh em CRLF no
# working tree e blob em LF, sem uma linha de aviso do git. Regra declarada em
# .gitattributes nao verifica nada sozinha, por isso a verificacao vive aqui,
# no gate que o pre-commit ja invoca.
$shCount = 0
$shOk = 0
$crlfFixed = 0
if ($scanAll -and $repoRoot) {
    $shFiles = @(& git ls-files 'scripts/hooks/*' '*.sh' 2>$null)
    foreach ($rel in $shFiles) {
        if (-not $rel) { continue }
        $abs = Join-Path $repoRoot ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $abs)) { continue }
        $shCount++
        $shBytes = [System.IO.File]::ReadAllBytes($abs)
        $temCR = $false
        for ($i = 0; $i -lt $shBytes.Length; $i++) {
            if ($shBytes[$i] -eq 0x0D) { $temCR = $true; break }
        }
        if ($temCR -and $Fix) {
            $txt = [System.IO.File]::ReadAllText($abs)
            $txt = $txt.Replace("`r`n", "`n").Replace("`r", "`n")
            [System.IO.File]::WriteAllText($abs, $txt, (New-Object System.Text.UTF8Encoding($false)))
            $crlfFixed++
            $temCR = $false
            if (-not $Json) { Write-Host "  CRLF FIX $abs" -ForegroundColor Green }
        }
        if (-not $temCR) { $shOk++; continue }
        $problemas += [ordered]@{
            path        = $abs
            hasBOM      = $false
            hasNonAscii = $false
            parseErros  = 0
            motivo      = 'CRLF em script de shell (sh morre com bad interpreter)'
        }
        if (-not $Json) {
            Write-Host "  REPROVA  $abs" -ForegroundColor Red -NoNewline
            Write-Host '  [CRLF em script de shell]' -ForegroundColor Yellow
        }
    }
}

if ($Json) {
    [ordered]@{
        total    = $arquivos.Count
        ok       = $okCount
        risco    = $problemas.Count
        fixed    = $fixed
        sh_total = $shCount
        sh_ok    = $shOk
        crlf_fix = $crlfFixed
        arquivos = $problemas
    } | ConvertTo-Json -Depth 4 | Write-Output
} else {
    Write-Host ''
    Write-Host "=== SUMARIO ===" -ForegroundColor Cyan
    Write-Host "Total : $($arquivos.Count) .ps1 + $shCount shell"
    Write-Host "OK    : $okCount .ps1 + $shOk shell (LF)"
    Write-Host "RISCO : $($problemas.Count)"
    if ($Fix) { Write-Host "BOM adicionado: $fixed   CRLF corrigido: $crlfFixed" }
}

if ($problemas.Count -eq 0) {
    if (-not $Json) { Write-Host 'Nenhum arquivo reprovado.' -ForegroundColor Green }
    return 0
}

if (-not $Json) {
    Write-Host ''
    Write-Host 'BOM ausente e CRLF de shell se resolvem com -Fix.' -ForegroundColor Yellow
    Write-Host 'Erro de parse NAO: e sintaxe PS 6/7 num script que roda no 5.1.' -ForegroundColor Yellow
}
exit [Math]::Min($problemas.Count, 255)
