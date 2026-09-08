# VIX Radar - Gate de conteudo do deploy Pages (DRIFT-CONTEUDO1, 2026-09-08)
#
# Detecta o estado perigoso de deploy: app/index.html (fonte do repo) divergiu
# de app/deploy_zip/index.html (espelho commitado que a producao serve) SEM bump
# de CACHE_VERSION. Nesse estado, quem compara so a versao conclui "sem drift",
# e o sync do deploy-pages.ps1 apagaria a divergencia antes de qualquer gate
# enxergar. Caso real: mudancas D2 (06/09/2026) ficaram no repo sob o rotulo
# v202.42 e a producao seguiu servindo o bundle anterior, sem D2.
#
# Regra fail-closed (usada pelo deploy-pages.ps1, gate 1.6):
#   conteudo diferente + CACHE_VERSION igual     => DRIFT (deploy aborta)
#   conteudo diferente + CACHE_VERSION diferente => bump em voo: o sync do
#       passo 2 do deploy resolve o conteudo com o rotulo novo (deploy segue)
#   conteudo igual (mesmo com EOL diferente)     => sem drift
#
# PS 5.1 compativel (sem operadores do PS 7). ASCII only, sem BOM necessario.
function Get-VixPagesContentDrift {
  param(
    [Parameter(Mandatory = $true)][string]$IndexPath,
    [Parameter(Mandatory = $true)][string]$ZipIndexPath
  )

  if (-not (Test-Path $IndexPath)) { throw "IndexPath nao encontrado: $IndexPath" }
  if (-not (Test-Path $ZipIndexPath)) { return $null }

  $textA = [System.IO.File]::ReadAllText($IndexPath)
  $textB = [System.IO.File]::ReadAllText($ZipIndexPath)

  # Normaliza fim de linha (CRLF x LF): a copia de deploy pode sofrer conversao
  # de EOL; conteudo identico com EOL diferente NAO e drift e nao pode abortar.
  $normA = $textA -replace "`r`n", "`n"
  $normB = $textB -replace "`r`n", "`n"

  if ($normA -ceq $normB) { return $null }

  $verA = [regex]::Match($normA, 'CACHE_VERSION\s*=\s*"(v[0-9.]+)"').Groups[1].Value
  $verB = [regex]::Match($normB, 'CACHE_VERSION\s*=\s*"(v[0-9.]+)"').Groups[1].Value

  if (-not $verA) { throw "CACHE_VERSION ausente em $IndexPath" }
  if (-not $verB) { return $null }

  if ($verA -cne $verB) { return $null }

  return [pscustomobject]@{
    cacheVersion = $verA
    zipVersion   = $verB
  }
}
