<#
.SYNOPSIS
  Sincroniza a versao declarada em CLAUDE.md e README.md com a versao real do
  deploy — chamado por deploy-worker.ps1 e deploy-pages.ps1, nunca a mao.

.DESCRIPTION
  A causa do drift de documentacao nao era falta de disciplina: era a
  atualizacao ser um passo manual que ninguem lembrava depois do deploy.
  deploy-worker.ps1/deploy-pages.ps1 ja commitam bundle+config atomicamente
  com a validacao de producao; este script entra no MESMO passo, para a doc
  nascer sincronizada em vez de depender de alguem lembrar.

  So mexe nos pontos que sao tabela de versao viva (CLAUDE.md "Producao
  atual", README.md "Versoes em Producao" + comentario CACHE_VERSION). Nao
  toca em referencias historicas ("obsoleta desde v4.9.108"), que sao registro
  de quando algo mudou, nao ponteiro de versao atual.

.EXAMPLE
  pwsh ./scripts/sync-version-docs.ps1 -WorkerVersion v4.9.164
  pwsh ./scripts/sync-version-docs.ps1 -FrontendVersion v201.76
#>
[CmdletBinding()]
param(
  [string]$WorkerVersion,
  [string]$FrontendVersion
)

$ErrorActionPreference = "Stop"
$root     = Split-Path -Parent $PSScriptRoot
$claudeMd = Join-Path $root "CLAUDE.md"
$readme   = Join-Path $root "README.md"
$today    = (Get-Date).ToString("dd'/'MM")  # forca "/" literal: -Format "dd/MM" vira "dd.MM" em locale pt-BR

function Update-File {
  param([string]$Path, [scriptblock]$Transform)
  $before = Get-Content -Raw -Path $Path
  $after  = & $Transform $before
  if ($after -ne $before) {
    Set-Content -NoNewline -Path $Path -Value $after
    return $true
  }
  return $false
}

$changed = @()

if ($WorkerVersion) {
  $wv = $WorkerVersion -replace '\.js$', ''

  if (Update-File $readme {
    param($t)
    # Comentario do bundle vivo (bloco "Fontes Vivas")
    $t = [regex]::Replace($t, 'v4\.9\.\d+\.js(\s*←\s*bundle Worker em produção)', "$wv.js`$1")
    # Tabela "Versoes em Producao"
    $t = [regex]::Replace($t, '(\|\s*Worker `radar-credito-api`\s*\|\s*)v4\.9\.\d+(\s*\|\s*)[0-9]{4}-[0-9]{2}-[0-9]{2}(\s*\|)',
      { param($m) "$($m.Groups[1].Value)$wv$($m.Groups[2].Value)$(Get-Date -Format 'yyyy-MM-dd')$($m.Groups[3].Value)" })
    return $t
  }) { $changed += "README.md (worker)" }

  if (Update-File $claudeMd {
    param($t)
    $t = [regex]::Replace($t,
      '(\|\s*Worker\s*\|\s*\*\*)v4\.9\.\d+(\*\*\s*\|\s*`api/wrangler\.toml`\s*→\s*\*\*)v4\.9\.\d+(\.js\*\*)(\s*\([^)]*\))?(\s*\|)',
      "`${1}$wv`${2}$wv`${3} (sincronizado automaticamente em $today contra o health de produção)`${5}")
    return $t
  }) { $changed += "CLAUDE.md (worker)" }
}

if ($FrontendVersion) {
  $fv = $FrontendVersion

  if (Update-File $readme {
    param($t)
    $t = [regex]::Replace($t, 'CACHE_VERSION=v[0-9.]+', "CACHE_VERSION=$fv")
    $t = [regex]::Replace($t, '(\|\s*Frontend `vixradar\.com`\s*\|\s*)v[0-9.]+(\s*\|\s*)[0-9]{4}-[0-9]{2}-[0-9]{2}(\s*\|)',
      { param($m) "$($m.Groups[1].Value)$fv$($m.Groups[2].Value)$(Get-Date -Format 'yyyy-MM-dd')$($m.Groups[3].Value)" })
    return $t
  }) { $changed += "README.md (frontend)" }

  if (Update-File $claudeMd {
    param($t)
    $t = [regex]::Replace($t,
      '(\|\s*Frontend\s*\|\s*\*\*)v[0-9.]+(\*\*\s*\|\s*`app/index\.html`\s*→\s*\*\*)v[0-9.]+(\*\*)(\s*\([^)]*\))?(\s*\|)',
      "`${1}$fv`${2}$fv`${3} (sincronizado automaticamente em $today)`${5}")
    return $t
  }) { $changed += "CLAUDE.md (frontend)" }
}

if ($changed.Count -gt 0) {
  Write-Host "Docs sincronizados: $($changed -join ', ')" -ForegroundColor Cyan
} else {
  Write-Host "Docs ja sincronizados, nada a alterar." -ForegroundColor DarkGray
}
