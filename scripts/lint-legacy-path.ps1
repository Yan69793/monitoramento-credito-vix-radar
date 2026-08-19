# lint-legacy-path.ps1 - Reprova .ps1/SKILL.md operacional com o caminho legado
# E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito ainda hardcoded.
#
# Contexto (2026-08-18): a junction do projeto foi invertida. O caminho fisico
# canonico passou a ser E:\Diretorio\Claude\Monitoramento de Credito; FREQUENTE
# virou junction legada, so por compatibilidade. A migracao reapontou a Action
# das 12 tarefas do Task Scheduler, mas nao varreu o CONTEUDO INTERNO dos
# scripts nem dos SKILL.md das rotinas Claude Desktop - auditoria da mesma
# noite achou 26 arquivos com o caminho legado ainda hardcoded (incluindo o
# proprio SKILL.md da rotina noturna instruindo o sentido errado: "usar sempre
# o caminho FREQUENTE"). Nao quebra hoje porque a junction ainda resolve, mas
# convida remocao futura da junction achando que nada mais depende dela.
#
# Sem guarda, a proxima edicao reintroduz o mesmo padrao - mesma familia do
# Gate 3 de segredo no pre-commit: alguem corrige o que ve naquele dia, a
# proxima sessao reintroduz. Este lint torna a reintroducao impossivel de
# commitar sem passar por um allowlist explicito.
#
# ASCII puro e sem BOM por design, mesmo padrao de lint-encoding.ps1.
#
# Uso:
#   powershell.exe -NoProfile -File scripts/lint-legacy-path.ps1
#   powershell.exe -NoProfile -File scripts/lint-legacy-path.ps1 -Path a.ps1,b.ps1
#   powershell.exe -NoProfile -File scripts/lint-legacy-path.ps1 -Json
param(
    [string[]]$Path,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$PadraoLegado = 'FREQUENTE\Monitoramento de Credito'

# Allowlist explicita (2026-08-18): caminho relativo ao repo, com / (nao \).
# Documentacao historica que precisa citar o caminho antigo em prosa entra
# aqui, nunca em silencio. Todo item novo deve vir com o motivo comentado ao lado.
$Allowlist = @(
    'scripts/lint-legacy-path.ps1'   # o proprio detector: precisa do padrao literal em $PadraoLegado
)

$ExcludePatterns = @(
    '*\node_modules\*',
    '*\venv\*',
    '*\__pycache__\*',
    '*\_archive\*',
    '*\graphify-out\*',
    '*\_arquivo-legado*\*'
)

$repoRoot = & git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -eq 0 -and $repoRoot) {
    $repoRoot = $repoRoot -replace '/', '\'
} else {
    $repoRoot = $null
}

# Sem -Path explicito, varre .ps1 rastreados + SKILL.md das rotinas Claude
# Desktop. So os rastreados pelo git: varrer o diretorio pegaria outros
# worktrees, _historico e copias legadas (mesmo racional do lint-encoding.ps1).
if (-not $Path -or $Path.Count -eq 0) {
    if ($repoRoot) {
        $Path = @(& git ls-files '*.ps1' 'routines/claude-desktop/*/SKILL.md' | ForEach-Object { Join-Path $repoRoot ($_ -replace '/', '\') })
        if (-not $Path -or $Path.Count -eq 0) { $Path = @($repoRoot) }
    } else {
        $Path = @((Split-Path -Parent $PSScriptRoot))
    }
}

# Aceita tanto -Path a,b (array) quanto -Path "a,b" (string unica), porque o
# hook invoca via powershell.exe -File, onde o binder nao divide string entre aspas.
if ($Path) { $Path = $Path | ForEach-Object { $_ -split ',' } | Where-Object { $_ } }

$arquivos = @()
foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $item = Get-Item -LiteralPath $p
    if ($item.PSIsContainer) {
        $arquivos += Get-ChildItem $item.FullName -Recurse -Include '*.ps1', 'SKILL.md' -ErrorAction SilentlyContinue |
                     Select-Object -ExpandProperty FullName
    } else {
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
    Write-Host "=== LINT CAMINHO LEGADO (FREQUENTE pos-inversao 2026-08-18) ===" -ForegroundColor Cyan
    Write-Host "Arquivos: $($arquivos.Count)"
    Write-Host ''
}

$problemas = @()
$okCount = 0

foreach ($f in $arquivos) {
    $relPath = $f
    if ($repoRoot -and $f.StartsWith($repoRoot)) {
        $relPath = ($f.Substring($repoRoot.Length).TrimStart('\')) -replace '\\', '/'
    }
    # O pre-commit hook materializa blob em staging sob .git/lint-staged/<caminho real>
    # (mesma convencao do Gate 1). Sem descontar o prefixo, o allowlist nunca bate contra
    # o arquivo materializado - achado ao vivo no proprio commit deste script.
    if ($relPath -match '^\.git/lint-staged/(.+)$') { $relPath = $Matches[1] }
    if ($Allowlist -contains $relPath) {
        $okCount++
        continue
    }

    $conteudo = ''
    try { $conteudo = [System.IO.File]::ReadAllText($f) } catch { $conteudo = '' }

    if ($conteudo -notlike "*$PadraoLegado*") {
        $okCount++
        continue
    }

    $problemas += [ordered]@{ path = $f; motivo = 'caminho legado FREQUENTE hardcoded (pos-inversao 2026-08-18)' }
    if (-not $Json) { Write-Host "  REPROVA  $f" -ForegroundColor Red -NoNewline; Write-Host "  [caminho legado FREQUENTE]" -ForegroundColor Yellow }
}

if ($Json) {
    [ordered]@{
        total    = $arquivos.Count
        ok       = $okCount
        risco    = $problemas.Count
        arquivos = $problemas
    } | ConvertTo-Json -Depth 4 | Write-Output
} else {
    Write-Host ''
    Write-Host "=== SUMARIO ===" -ForegroundColor Cyan
    Write-Host "Total : $($arquivos.Count)"
    Write-Host "OK    : $okCount"
    Write-Host "RISCO : $($problemas.Count)"
}

if ($problemas.Count -eq 0) {
    if (-not $Json) { Write-Host 'Nenhum arquivo com o caminho legado.' -ForegroundColor Green }
    return 0
}

if (-not $Json) {
    Write-Host ''
    Write-Host 'Corrija para E:\Diretorio\Claude\Monitoramento de Credito (fisico canonico desde 18/08/2026).' -ForegroundColor Yellow
    Write-Host 'Excecao legitima (doc historica): adicione o caminho relativo ao array $Allowlist deste script, com o motivo comentado.' -ForegroundColor Yellow
}
exit [Math]::Min($problemas.Count, 255)
