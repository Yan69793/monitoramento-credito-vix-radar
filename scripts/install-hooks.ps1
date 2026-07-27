# install-hooks.ps1 - Copia scripts/hooks/* para o diretorio de hooks do git.
# ASCII puro e sem BOM por design.
#
# Hooks vivem em .git/hooks, que NAO e versionado. Sem este passo o pre-commit
# nao existe num clone novo, e a guarda some junto. Rodar uma vez por clone.
# Worktrees compartilham o mesmo .git/hooks do repo principal, entao uma execucao cobre todos.
param([switch]$Force)

$ErrorActionPreference = 'Stop'

$hooksDir = (& git rev-parse --git-common-dir 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $hooksDir) {
    Write-Host 'ERRO: nao esta num repositorio git.' -ForegroundColor Red
    exit 1
}
if (-not [System.IO.Path]::IsPathRooted($hooksDir)) {
    $hooksDir = Join-Path (& git rev-parse --show-toplevel) $hooksDir
}
$hooksDir = Join-Path ($hooksDir -replace '/', '\') 'hooks'

$origem = Join-Path $PSScriptRoot 'hooks'
if (-not (Test-Path $origem)) {
    Write-Host "ERRO: $origem nao encontrado." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null

foreach ($h in (Get-ChildItem $origem -File)) {
    $destino = Join-Path $hooksDir $h.Name
    if ((Test-Path $destino) -and -not $Force) {
        $atual = [System.IO.File]::ReadAllText($destino)
        $novo = [System.IO.File]::ReadAllText($h.FullName)
        if ($atual -eq $novo) {
            Write-Host "  ja instalado: $($h.Name)" -ForegroundColor DarkGray
            continue
        }
        Write-Host "  DIFERENTE (use -Force para sobrescrever): $($h.Name)" -ForegroundColor Yellow
        continue
    }
    # LF obrigatorio: o sh do Git for Windows falha com CRLF no shebang.
    $texto = [System.IO.File]::ReadAllText($h.FullName) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($destino, $texto, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  instalado: $($h.Name) -> $destino" -ForegroundColor Green
}

Write-Host ''
Write-Host 'Hooks instalados. Teste: git commit (com .ps1 em stage).' -ForegroundColor Cyan
