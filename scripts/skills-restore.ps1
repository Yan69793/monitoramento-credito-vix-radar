# skills-restore.ps1 - desfaz o skills-archive-vix.ps1. Reversivel.
#
# Substitui o wrapper antigo que so chamava C:\Users\User\skills-restore.ps1,
# arquivo que nao existe mais.
#
# Uso:                 pwsh -File scripts/skills-restore.ps1
# Conferir sem mover:  pwsh -File scripts/skills-restore.ps1 -WhatIf
#
# ASCII-only de proposito. Sem ternario e sem '??' para valer no PS 5.1.

[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Continue'

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$HomeDir     = 'C:\Users\User'

$Targets = @(
    @{ Active = (Join-Path $HomeDir '.agents\skills');     Archive = (Join-Path $HomeDir '.agents\_off-skills');            }
    @{ Active = (Join-Path $HomeDir '.claude\skills');     Archive = (Join-Path $HomeDir '.claude\_off-skills');            }
    @{ Active = (Join-Path $HomeDir '.grok\skills');       Archive = (Join-Path $HomeDir '.grok\_off-skills');              }
    @{ Active = (Join-Path $ProjectRoot '.agents\skills'); Archive = (Join-Path $HomeDir '.agents\_off-skills-vix-projeto'); }
)

Write-Output '=== skills-restore ==='
$restoredTotal = 0
$conflicts = 0

foreach ($t in $Targets) {
    if (-not (Test-Path -LiteralPath $t.Archive)) {
        Write-Output ("sem arquivo: " + $t.Archive)
        continue
    }
    if (-not (Test-Path -LiteralPath $t.Active)) {
        if ($PSCmdlet.ShouldProcess($t.Active, 'criar pasta ativa')) {
            New-Item -ItemType Directory -Path $t.Active -Force | Out-Null
        }
    }
    $restored = 0
    foreach ($d in Get-ChildItem -LiteralPath $t.Archive -Directory -ErrorAction SilentlyContinue) {
        # o arquivamento sufixa '_dup' quando o nome ja existia no arquivo
        $nome = $d.Name
        if ($nome.EndsWith('_dup')) { $nome = $nome.Substring(0, $nome.Length - 4) }
        $dest = Join-Path $t.Active $nome
        if (Test-Path -LiteralPath $dest) {
            Write-Output ("conflito, ja existe: " + $dest)
            $conflicts++
            continue
        }
        if ($PSCmdlet.ShouldProcess($d.FullName, ('restaurar em ' + $t.Active))) {
            Move-Item -LiteralPath $d.FullName -Destination $dest -ErrorAction Continue
            if ($?) { $restored++ }
        } else {
            $restored++
        }
    }
    $restoredTotal += $restored
    Write-Output ("{0,-56} restaurar={1,4}" -f $t.Active, $restored)
}

Write-Output ("total a restaurar: " + $restoredTotal + "  conflitos: " + $conflicts)
Write-Output 'Reinicie a sessao para a restauracao valer no system prompt.'
exit 0
