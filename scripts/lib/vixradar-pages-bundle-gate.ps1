# Allowlist do pacote publicado pelo Cloudflare Pages.
# Arquivo novo precisa entrar aqui deliberadamente antes de ser publicado.
# PS 5.1 compativel, sem rede e sem ler credenciais.
function Get-VixPagesUnexpectedFiles {
  param([Parameter(Mandatory = $true)][string]$BundlePath)

  $bundleRoot = [IO.Path]::GetFullPath($BundlePath).TrimEnd('\', '/')
  if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) {
    throw "Bundle Pages ausente: $bundleRoot"
  }
  $allowed = @(
    '_headers', '_routes.json', 'index.html', 'landing-demo.json', 'robots.txt',
    'version.json', 'og-vix-radar.jpg', 'og-vix-radar-20261003.jpg',
    'manual/index.html', 'apresentacao/index.html',
    'admin/vr-admin-shared.js', 'admin/vr-admin-modules.js',
    'admin/vr-admin-metricas.js', 'admin/vr-admin-fase3.js', 'admin/vr-admin-engajamento.js',
    'app/js/api.js', 'app/js/admin-router.js', 'app/js/admin-bootstrap.js',
    'app/js/admin/shared.js', 'app/js/admin/modules.js', 'app/js/admin/metricas.js',
    'app/js/admin/fase3.js', 'app/js/admin/engajamento.js'
  )
  $rootItem = Get-Item -LiteralPath $bundleRoot -Force -ErrorAction Stop
  if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'A raiz do bundle Pages nao pode ser link ou junction.'
  }
  foreach ($item in Get-ChildItem -LiteralPath $bundleRoot -Recurse -Force -ErrorAction Stop) {
    $relative = $item.FullName.Substring($bundleRoot.Length + 1).Replace('\', '/')
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (-not $item.PSIsContainer -and $allowed -cnotcontains $relative)) {
      $relative
    }
  }
}
