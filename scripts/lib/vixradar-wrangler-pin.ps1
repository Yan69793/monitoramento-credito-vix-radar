<#
.SYNOPSIS
  Guarda CFG-01: a ferramenta que faz o deploy e a versao declarada, nunca a que
  o npm resolver na hora.

.DESCRIPTION
  Extraida de scripts/deploy-worker.ps1 em 18/09/2026 para ficar testavel nas
  duas pontas, na mesma forma da guarda de conteudo do Pages. O deploy carrega
  esta funcao e aborta se ela reprovar; scripts/test-wrangler-pin.ps1 carrega a
  MESMA funcao contra uma bancada isolada e prova que ela aceita o caso bom e
  reprova cada caso ruim, sem tocar em deploy.

  Contexto do achado: ate 18/09/2026 o wrangler nao estava declarado em
  api/package.json. Ele entrava na arvore por duas arestas de terceiros - a
  devDependency @cloudflare/vitest-pool-workers e um peer OPCIONAL declarado por
  @sentry/cloudflare. O deploy roda `npm ci --omit=dev`, que remove
  devDependencies; enquanto o peer opcional segurava o wrangler na arvore, o
  deploy funcionava por coincidencia. Bastava o @sentry/cloudflare parar de
  declarar esse peer para o wrangler sumir e o npx baixar outra versao da rede
  no meio do deploy, sem ninguem escolher qual.

  A funcao confere as tres pontas da mesma afirmacao:
    1. api/package.json declara wrangler em dependencies, com versao EXATA;
    2. o npm ci instalou essa versao em node_modules/wrangler;
    3. o binario local responde a mesma versao quando executado direto com node.

  Devolve objeto com Ok, Motivo, Declarado, Instalado e Resposta. Quem decide
  abortar e o chamador, para a mesma funcao servir ao gate e ao teste.
#>
function Get-VixWranglerBin {
  <#
  .SYNOPSIS
    Devolve o caminho do binario do wrangler instalado, ou $null.

  .DESCRIPTION
    Ponto unico de resolucao da ferramenta de deploy. Existe para que nenhuma
    parte do fluxo de deploy precise do `npx`: o `npx`, quando o pacote nao esta
    em node_modules, resolve pela rede e executa uma versao que ninguem
    escolheu. Aqui so o binario declarado e instalado conta, e a ausencia dele
    e uma resposta ($null) que o chamador decide como tratar - nunca um download.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$ApiDir
  )
  $bin = Join-Path $ApiDir 'node_modules\wrangler\bin\wrangler.js'
  if (Test-Path $bin) { return $bin }
  return $null
}

function Test-VixWranglerPin {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$ApiDir
  )

  $res = @{
    Ok        = $false
    Motivo    = ''
    Declarado = $null
    Instalado = $null
    Resposta  = $null
  }

  # Fixa o caminho como absoluto ANTES de qualquer Push-Location. O binario e
  # executado com Push-Location ativo, entao um $ApiDir relativo passaria a
  # resolver contra o diretorio novo e dobraria o prefixo. Medido em 18/09/2026
  # ao rodar a guarda com './api': o node procurou api\api\node_modules\... e a
  # guarda reprovou pelo motivo errado (exit code) em vez de aceitar. No deploy
  # nao aparecia porque $apiDir ja vem absoluto de Split-Path -Parent $PSScriptRoot.
  $ApiDir = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($ApiDir)

  $pkgApiPath = Join-Path $ApiDir 'package.json'
  if (-not (Test-Path $pkgApiPath)) {
    $res.Motivo = "api/package.json ausente em $ApiDir"
    return [pscustomobject]$res
  }

  try {
    $pkg = Get-Content $pkgApiPath -Raw | ConvertFrom-Json
  } catch {
    $res.Motivo = "api/package.json ilegivel: $_"
    return [pscustomobject]$res
  }

  # 1. Declarado, e declarado como versao exata.
  $declarado = $null
  if ($pkg.PSObject.Properties.Name -contains 'dependencies' -and $pkg.dependencies) {
    $declarado = $pkg.dependencies.wrangler
  }
  if (-not $declarado) {
    $res.Motivo = "api/package.json nao declara 'wrangler' em dependencies (CFG-01). Sem isso a ferramenta de deploy e resolvida na hora, nao e a declarada."
    return [pscustomobject]$res
  }
  $res.Declarado = "$declarado"

  if ("$declarado" -notmatch '^\d+\.\d+\.\d+$') {
    $res.Motivo = "wrangler declarado como '$declarado' - precisa ser versao EXATA (X.Y.Z, sem ^ nem ~). Com faixa, uma instalacao futura troca a ferramenta de deploy em silencio (CFG-01)."
    return [pscustomobject]$res
  }

  # 2. O npm ci instalou essa versao.
  $wranglerBin = Join-Path $ApiDir 'node_modules\wrangler\bin\wrangler.js'
  if (-not (Test-Path $wranglerBin)) {
    $res.Motivo = "wrangler ausente em node_modules apos npm ci --omit=dev (CFG-01). O deploy cairia no download implicito do npx, que e exatamente o que a declaracao existe para impedir."
    return [pscustomobject]$res
  }

  $wranglerPkgPath = Join-Path $ApiDir 'node_modules\wrangler\package.json'
  if (-not (Test-Path $wranglerPkgPath)) {
    $res.Motivo = "node_modules/wrangler/package.json ausente - instalacao incompleta (CFG-01)."
    return [pscustomobject]$res
  }

  try {
    $instalado = (Get-Content $wranglerPkgPath -Raw | ConvertFrom-Json).version
  } catch {
    $res.Motivo = "node_modules/wrangler/package.json ilegivel: $_"
    return [pscustomobject]$res
  }
  $res.Instalado = "$instalado"

  if ("$instalado" -ne "$declarado") {
    $res.Motivo = "wrangler instalado ($instalado) difere do declarado ($declarado) em api/package.json. O lock esta fora de sincronia com o package.json. Rode 'npm install' em api/ e commite o lock antes de deployar (CFG-01)."
    return [pscustomobject]$res
  }

  # 3. O binario responde a mesma versao. Executa o arquivo local direto com
  # node, sem npx e sem npm: e a prova de que o deploy nao depende de resolucao
  # de versao na rede. O shim do node_modules/.bin faz exatamente esta chamada.
  Push-Location $ApiDir
  try {
    try {
      $saida = (& node $wranglerBin --version 2>&1 | Out-String).Trim()
      $exit  = $LASTEXITCODE
    } catch {
      # Com $ErrorActionPreference = 'Stop' o PowerShell pode promover exit code
      # nao-zero de comando nativo a excecao terminante. Aqui isso e resposta
      # esperada da sonda, nao motivo para derrubar o chamador.
      $saida = "$_"
      $exit  = 1
    }
  } finally {
    Pop-Location
  }

  $res.Resposta = $saida
  if ($exit -ne 0) {
    $res.Motivo = "O wrangler local nao respondeu a --version (exit $exit).`n$saida"
    return [pscustomobject]$res
  }
  if ($saida -ne "$declarado") {
    $res.Motivo = "O wrangler local responde '$saida' mas api/package.json declara '$declarado' (CFG-01). Nao deployar com ferramenta diferente da declarada."
    return [pscustomobject]$res
  }

  $res.Ok = $true
  return [pscustomobject]$res
}
