<#
.SYNOPSIS
  Rollback do frontend (Cloudflare Pages) para o bundle de um commit anterior, sem mexer na arvore de trabalho.

.DESCRIPTION
  VXROLLBACK1 (2026-10-14). O deploy-pages.ps1 recusa publicar versao MENOR que a de producao
  (gate anti-regressao, de proposito), entao ele nao serve para voltar atras. Este script e o
  caminho de volta, com os mesmos cuidados:
    1. extrai app/deploy_zip do commit -Ref para uma pasta temporaria (git archive, nao toca o working tree);
    2. confere que o pacote tem index.html e version.json, que a versao bate com -VersaoEsperada
       (quando informada) e que a allowlist do Pages aprova (mesmo gate do deploy);
    3. sem -Publicar so mostra o plano e o comando. Com -Publicar envia para -Branch;
    4. valida no URL de destino que version.json e o CACHE_VERSION do HTML voltaram ao esperado.
  Producao (branch main) exige -Producao alem de -Publicar: nunca acontece por padrao.
  Nao commita, nao faz push e nao altera Worker, KV, dados ou credenciais.

.EXAMPLE
  pwsh ./scripts/rollback-pages.ps1 -Ref origin/main -VersaoEsperada v202.63
  pwsh ./scripts/rollback-pages.ps1 -Ref origin/main -VersaoEsperada v202.63 -Branch ui-v2-preview -Publicar
  pwsh ./scripts/rollback-pages.ps1 -Ref <commit> -VersaoEsperada v202.63 -Producao -Publicar
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Ref,
  [string]$VersaoEsperada = '',
  [string]$Branch = 'ui-v2-preview',
  [string]$ProjectName = 'radar-credito',
  [switch]$Publicar,
  [switch]$Producao
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path (Join-Path $PSScriptRoot 'lib') 'vixradar-pages-bundle-gate.ps1')

function Fail($msg) { Write-Host "ERRO: $msg" -ForegroundColor Red; exit 1 }

$ehProducao = ($Branch -eq 'main' -or $Branch -eq 'master')
if ($ehProducao -and -not $Producao) { Fail "Branch '$Branch' e producao. Rollback de producao exige -Producao explicito." }
if ($Producao -and -not $ehProducao) { Fail "-Producao so combina com -Branch main." }

Push-Location $root
try {
  $sha = (git rev-parse --verify "$Ref^{commit}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or -not $sha) { Fail "Ref '$Ref' nao resolve para um commit." }
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('vx-rollback-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $tar = Join-Path $tmp 'bundle.tar'
  git archive --format=tar -o $tar $sha app/deploy_zip
  if ($LASTEXITCODE -ne 0) { Fail "git archive falhou para $sha." }
  tar -xf $tar -C $tmp
  if ($LASTEXITCODE -ne 0) { Fail "Nao consegui extrair o pacote de $sha." }
  $bundle = Join-Path $tmp 'app/deploy_zip'
  foreach ($f in @('index.html', 'version.json', '_headers')) {
    if (-not (Test-Path (Join-Path $bundle $f))) { Fail "Pacote do commit $sha nao tem $f." }
  }
  $vj = Get-Content (Join-Path $bundle 'version.json') -Raw | ConvertFrom-Json
  $m = [regex]::Match((Get-Content (Join-Path $bundle 'index.html') -Raw), 'CACHE_VERSION\s*=\s*"(v[0-9.]+)"')
  if (-not $m.Success) { Fail 'CACHE_VERSION ausente no index.html do pacote.' }
  if ($m.Groups[1].Value -ne $vj.version) { Fail ("Pacote incoerente: version.json=" + $vj.version + " e CACHE_VERSION=" + $m.Groups[1].Value) }
  if ($VersaoEsperada -and $vj.version -ne $VersaoEsperada) { Fail ("Versao do pacote (" + $vj.version + ") difere de -VersaoEsperada (" + $VersaoEsperada + ").") }
  $inesperados = @(Get-VixPagesUnexpectedFiles -BundlePath $bundle)
  if ($inesperados.Count -gt 0) { Fail ("Allowlist do Pages reprovou o pacote de ${sha}:`n" + ($inesperados -join "`n")) }
  Write-Host ("Pacote de {0} ({1}): versao {2}, allowlist OK" -f $Ref, $sha.Substring(0, 9), $vj.version) -ForegroundColor Green

  $destino = if ($ehProducao) { 'https://vixradar.com' } else { "https://$Branch.$ProjectName.pages.dev" }
  $cmd = "npx wrangler pages deploy `"$bundle`" --project-name=$ProjectName --branch=$Branch --commit-dirty=true"
  if (-not $Publicar) {
    Write-Host "`nPlano (nada foi enviado). Destino: $destino" -ForegroundColor Cyan
    Write-Host "  $cmd" -ForegroundColor Cyan
    return
  }
  Write-Host "`nPublicando rollback em '$Branch' ($destino)..." -ForegroundColor Yellow
  Invoke-Expression $cmd
  if ($LASTEXITCODE -ne 0) { Fail "wrangler pages deploy falhou (exit $LASTEXITCODE). O destino continua como estava." }

  $ok = $false
  for ($i = 1; $i -le 8 -and -not $ok; $i++) {
    try {
      $v = Invoke-RestMethod -Uri ("$destino/version.json?_=" + [guid]::NewGuid()) -Headers @{ 'Cache-Control' = 'no-cache' }
      $h = (Invoke-WebRequest -Uri ("$destino/?_=" + [guid]::NewGuid()) -UseBasicParsing).Content
      $mh = [regex]::Match($h, 'CACHE_VERSION\s*=\s*"(v[0-9.]+)"')
      if ($v.version -eq $vj.version -and $mh.Success -and $mh.Groups[1].Value -eq $vj.version) { $ok = $true }
      else { Write-Host ("  aguardando propagacao ({0}/8): version.json={1}, HTML={2}" -f $i, $v.version, $(if ($mh.Success) { $mh.Groups[1].Value } else { 'ausente' })) -ForegroundColor DarkGray }
    } catch { Write-Host ("  erro transiente ({0}/8): {1}" -f $i, $_.Exception.Message) -ForegroundColor DarkGray }
    if (-not $ok) { Start-Sleep -Seconds 5 }
  }
  if (-not $ok) { Fail ("Rollback enviado, mas $destino nao confirmou a versao " + $vj.version + ". Investigar propagacao/cache.") }
  Write-Host ("ROLLBACK OK: {0} serve {1} (version.json e HTML)." -f $destino, $vj.version) -ForegroundColor Green
} finally {
  Pop-Location
}
