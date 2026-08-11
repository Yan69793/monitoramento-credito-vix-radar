# check-root-hygiene.ps1 - alerta (nao bloqueia) arquivo novo, nao-ignorado, parado
# direto na raiz do repo ha mais de N dias sem virar commit nem entrar no .gitignore.
# Chamado pelo Gate 4 de scripts/hooks/pre-commit. Tambem roda manual:
#   pwsh ./scripts/check-root-hygiene.ps1
# So raiz (profundidade 0) - data/historico, data/reconciliacao, Obsidian VIX
# Radar/ e docs/ tem mecanismo proprio (auto-commit escopado ou disciplina de
# sessao) e nao devem ser duplicados aqui.
# Exit 0 sempre. ASCII puro (PowerShell 5.1 / git-bash).
param([int]$DiasLimite = 3)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $porcelain = & git status --porcelain 2>$null
    if ($LASTEXITCODE -ne 0) { exit 0 }
    $agora = Get-Date
    $achados = @()
    foreach ($linha in $porcelain) {
        if ($linha.Length -lt 4) { continue }
        $xy   = $linha.Substring(0, 2)
        $path = $linha.Substring(3).Trim('"')
        if ($xy -ne '??') { continue }
        if ($path -match '/') { continue }
        $full = Join-Path $root $path
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $item = Get-Item -LiteralPath $full -Force
        $idadeDias = ($agora - $item.CreationTime).TotalDays
        if ($idadeDias -ge $DiasLimite) {
            $achados += ("  - {0} (criado ha {1} dia(s))" -f $path, [math]::Floor($idadeDias))
        }
    }
    if ($achados.Count -gt 0) {
        Write-Host ""
        Write-Host ("AVISO (higiene de raiz): {0} item(ns) novo(s) na raiz ha {1}+ dias sem commit nem .gitignore:" -f $achados.Count, $DiasLimite)
        $achados | ForEach-Object { Write-Host $_ }
        Write-Host "  Decida: 'git add' + commit, mover de pasta, ou .gitignore. (Nao bloqueia o commit.)"
    }
} finally {
    Pop-Location
}
exit 0
