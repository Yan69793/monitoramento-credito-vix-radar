# preflight-scan.ps1 - varredura estatica do SUPERSETO de .ps1 do repositorio.
#
# Contrato (nao negociar):
#   1. Este script roda sob powershell.exe 5.1. O parser de referencia da arvore viva E o
#      parser do 5.1 (o Task Scheduler e as rotinas usam powershell.exe). Se o host for
#      pwsh 6/7 o script RECUSA em vez de dar verde: sob o 7 o ternario/?? parseia sem erro
#      e o detector daria verde no exato bug que ele existe para pegar.
#   2. O universo varrido e o SUPERSETO real do repo, nunca lista declarada:
#        git ls-files '*.ps1'  +  git ls-files --others --exclude-standard '*.ps1'
#      menos os padroes de exclusao do linter. Motivo medido: dot-source e montado com
#      Join-Path em runtime (ex.: run_vixradar_sentinela.ps1 usa $ScriptsDir), entao lista
#      declarada daria verde com dependencia quebrada carregada so em runtime.
#   3. Os padroes de exclusao sao lidos do DISCO (lint-encoding.ps1). Copiar a lista aqui
#      criaria uma segunda verdade, e as duas divergiriam em silencio.
#
# Saida: JSON em stdout quando -Json. Exit 0 = varredura executou (mesmo com risco > 0);
#        exit 3 = a varredura NAO pode ser executada (o chamador tem de recusar).
param(
    [string]$RepoRoot,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$res = [ordered]@{
    ok               = $false
    erro             = ''
    ps_versao        = $PSVersionTable.PSVersion.ToString()
    root             = ''
    exclusoes_origem = ''
    exclusoes        = @()
    tracked          = 0
    untracked        = 0
    excluidos        = 0
    superset         = 0
    conflito         = @()
    parse            = @()
    risco            = 0
}

function Get-SupersetLista {
    param([string]$Root, [string[]]$Excl)
    $tracked = @(& git -C $Root ls-files '*.ps1' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files falhou' }
    $others = @(& git -C $Root ls-files --others --exclude-standard '*.ps1' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files --others falhou' }
    $todos = @(@($tracked) + @($others)) | Where-Object { $_ } | Sort-Object -Unique
    $abs = @()
    $excluidos = 0
    foreach ($rel in $todos) {
        $f = Join-Path $Root ($rel -replace '/', '\')
        $skip = $false
        foreach ($e in $Excl) { if ($f -like $e) { $skip = $true; break } }
        if ($skip) { $excluidos++; continue }
        $abs += $f
    }
    return [pscustomobject]@{
        Tracked   = @($tracked).Count
        Untracked = @($others).Count
        Excluidos = $excluidos
        Abs       = $abs
    }
}

try {
    if ($PSVersionTable.PSVersion.Major -ne 5) {
        throw ('host nao e o powershell.exe 5.1 (host=' + $PSVersionTable.PSVersion.ToString() + '); o parser de referencia de producao e o do 5.1')
    }
    if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
    if (-not (Test-Path -LiteralPath $RepoRoot)) { throw ('repo inexistente: ' + $RepoRoot) }

    $root = @(& git -C $RepoRoot rev-parse --show-toplevel 2>$null) | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $root) { throw ('nao foi possivel resolver a raiz do repositorio git a partir de ' + $RepoRoot) }
    $root = $root.ToString().Trim() -replace '/', '\'
    $res.root = $root

    $linter = Join-Path $root 'scripts\lint-encoding.ps1'
    if (-not (Test-Path -LiteralPath $linter)) { throw ('linter ausente (fonte das exclusoes): ' + $linter) }
    $res.exclusoes_origem = $linter
    $textoLinter = [System.IO.File]::ReadAllText($linter)
    $m = [regex]::Match($textoLinter, '(?s)\$ExcludePatterns\s*=\s*@\((.*?)\)')
    if (-not $m.Success) { throw 'nao foi possivel ler $ExcludePatterns de lint-encoding.ps1' }
    $excl = @([regex]::Matches($m.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    if ($excl.Count -eq 0) { throw 'lista de exclusoes vazia em lint-encoding.ps1' }
    $res.exclusoes = $excl

    $lista = Get-SupersetLista -Root $root -Excl $excl
    $res.tracked   = $lista.Tracked
    $res.untracked = $lista.Untracked
    $res.excluidos = $lista.Excluidos
    $res.superset  = @($lista.Abs).Count

    $conflito = @()
    $parse = @()
    foreach ($f in $lista.Abs) {
        if (-not (Test-Path -LiteralPath $f)) {
            $parse += [ordered]@{ arquivo = $f; erros = -1; primeiro = 'arquivo listado pelo git e ausente no disco' }
            continue
        }
        $txt = [System.IO.File]::ReadAllText($f)
        if ([regex]::IsMatch($txt, '(?m)^<<<<<<< ') -or [regex]::IsMatch($txt, '(?m)^>>>>>>> ')) {
            $conflito += $f
        }
        $tokens = $null
        $erros = $null
        [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$erros) | Out-Null
        if ($erros.Count -gt 0) {
            $parse += [ordered]@{ arquivo = $f; erros = $erros.Count; primeiro = $erros[0].Message }
        }
    }
    $res.conflito = @($conflito)
    $res.parse = @($parse)
    $res.risco = @($conflito).Count + @($parse).Count
    $res.ok = $true
} catch {
    $res.erro = $_.Exception.Message
}

if ($Json) {
    $res | ConvertTo-Json -Depth 6
} else {
    Write-Host '=== PREFLIGHT SCAN (superseto de .ps1) ==='
    Write-Host ('host   : ' + $res.ps_versao)
    Write-Host ('root   : ' + $res.root)
    Write-Host ('fontes : git ls-files + git ls-files --others --exclude-standard')
    Write-Host ('exclusoes de: ' + $res.exclusoes_origem)
    Write-Host ('superset: ' + $res.superset + ' arquivo(s)  (tracked=' + $res.tracked + ' untracked=' + $res.untracked + ' excluidos=' + $res.excluidos + ')')
    Write-Host ('RISCO  : ' + $res.risco)
    foreach ($c in @($res.conflito)) { Write-Host ('  CONFLITO ' + $c) -ForegroundColor Red }
    foreach ($p in @($res.parse)) { Write-Host ('  PARSE    ' + $p.arquivo + ' [' + $p.erros + '] ' + $p.primeiro) -ForegroundColor Red }
    if ($res.erro) { Write-Host ('ERRO: ' + $res.erro) -ForegroundColor Red }
}

if (-not $res.ok) { exit 3 }
exit 0
