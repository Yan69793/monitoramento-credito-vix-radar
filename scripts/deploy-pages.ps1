<#
.SYNOPSIS
  Deploy do frontend VIX Radar (Cloudflare Pages), idempotente e validado.

.DESCRIPTION
  1. Sincroniza app/index.html -> app/deploy_zip/ (a raiz vence).
  2. Extrai CACHE_VERSION do index.html e regenera version.json (deploy_zip + app/).
  3. Confere que os 4 arquivos do bundle existem.
  4. Roda `wrangler pages deploy ./app/deploy_zip`.
  5. Valida em producao (vixradar.com): CACHE_VERSION, version.json apex+www.

  CREDENCIAL: le CLOUDFLARE_API_TOKEN e CLOUDFLARE_ACCOUNT_ID de variaveis de
  ambiente. NUNCA hardcode token neste arquivo (regra inviolavel do projeto).
  Configure uma vez (User scope) com scripts/setup-deploy-credential.ps1 ou:
    [Environment]::SetEnvironmentVariable('CLOUDFLARE_API_TOKEN','<token>','User')
    [Environment]::SetEnvironmentVariable('CLOUDFLARE_ACCOUNT_ID','<id>','User')

.EXAMPLE
  pwsh ./scripts/deploy-pages.ps1
  pwsh ./scripts/deploy-pages.ps1 -SkipValidation
#>
[CmdletBinding()]
param(
  [string]$ProjectName = "radar-credito",
  [switch]$SkipValidation,
  [switch]$SkipGit,
  # Roda sync + todos os gates e para antes do wrangler. Nao deploya, nao commita.
  # Serve para provar que os gates pegam um bundle ruim sem publicar nada.
  [switch]$DryRun,
  # Ignora CLOUDFLARE_API_TOKEN e usa a sessao OAuth do wrangler direto.
  [switch]$ForcarOAuth
)

$ErrorActionPreference = "Stop"
$root    = Split-Path -Parent $PSScriptRoot
$appDir  = Join-Path $root "app"
$zipDir  = Join-Path $appDir "deploy_zip"
$indexSrc = Join-Path $appDir "index.html"

function Fail($msg) { Write-Host "ERRO: $msg" -ForegroundColor Red; exit 1 }
function Warn($msg) { Write-Host "AVISO: $msg" -ForegroundColor Yellow }

# Compara duas versoes de frontend (vNNN.MMM). Retorna -1, 0 ou 1.
#
# VERCMP1 (2026-08-04): a versao anterior concatenava os digitos, entao v202.1 virava
# 2021 e v201.93 virava 20193, e o gate anti-regressao concluia que producao (v201.93)
# estava A FRENTE do repo (v202.1) e abortava o deploy correto. Quebra sempre que o
# minor muda de quantidade de digitos, ou seja, em todo bump de major. Achado ao rodar
# o primeiro -DryRun depois da auditoria de 2026-08-04. Agora compara por componente.
function Compare-FrontendVersion($a, $b) {
  $pa = @(($a -replace '^v', '') -split '\.')
  $pb = @(($b -replace '^v', '') -split '\.')
  $n = [Math]::Max($pa.Count, $pb.Count)
  for ($i = 0; $i -lt $n; $i++) {
    $ca = 0
    $cb = 0
    if ($i -lt $pa.Count -and $pa[$i] -match '^\d+$') { $ca = [int]$pa[$i] }
    if ($i -lt $pb.Count -and $pb[$i] -match '^\d+$') { $cb = [int]$pb[$i] }
    if ($ca -lt $cb) { return -1 }
    if ($ca -gt $cb) { return 1 }
  }
  return 0
}

# --- 0. Pre-requisitos e credencial ---------------------------------------
# CREDOAUTH1 (2026-08-04): o token do registro foi trocado em 02/08 por um com
# permissao de Workers KV Storage, para destravar o Export-Historico. Esse token
# NAO tem permissao de Pages, entao todo `wrangler pages deploy` passa os gates,
# sobe ate o wrangler e morre com "Authentication error [code: 10000]". Antes disso
# o script exigia o token e nem tentava a sessao OAuth, que funciona e tem Pages.
#
# Ordem agora: sonda o token; se ele nao alcanca a API de Pages, avisa alto e cai
# para OAuth. Sem sonda o operador so descobre depois do sync ja ter mexido em
# deploy_zip e no version.json.
$usandoOAuth = $false

function Test-CredencialPages {
  # try/catch porque com $ErrorActionPreference='Stop' o pwsh 7.3+ pode promover
  # exit code nao-zero de comando nativo a excecao terminante. Aqui exit != 0 e
  # resposta esperada da sonda, nao erro fatal.
  try {
    $null = & npx wrangler pages project list 2>&1
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

if ($ForcarOAuth) {
  Write-Host "Credencial: OAuth forcado por -ForcarOAuth" -ForegroundColor Cyan
  $env:CLOUDFLARE_API_TOKEN = ''
  $usandoOAuth = $true
} elseif (-not $env:CLOUDFLARE_API_TOKEN) {
  Write-Host "Credencial: CLOUDFLARE_API_TOKEN ausente, tentando sessao OAuth do wrangler" -ForegroundColor Yellow
  $usandoOAuth = $true
} else {
  if (Test-CredencialPages) {
    Write-Host "Credencial: CLOUDFLARE_API_TOKEN com acesso a Pages OK" -ForegroundColor Green
  } else {
    Warn "CLOUDFLARE_API_TOKEN existe mas NAO alcanca a API de Pages (falta a permissao Cloudflare Pages: Edit)."
    Warn "Caindo para a sessao OAuth do wrangler. Corrija o token quando puder, senao toda rotina que dependa dele em ambiente nao interativo vai falhar igual."
    $env:CLOUDFLARE_API_TOKEN = ''
    $usandoOAuth = $true
  }
}

if ($usandoOAuth) {
  if (-not (Test-CredencialPages)) {
    Fail "Nem o token nem a sessao OAuth alcancam a API de Pages. Rode 'npx wrangler login' ou adicione a permissao 'Cloudflare Pages: Edit' ao token em https://dash.cloudflare.com/profile/api-tokens"
  }
  Write-Host "Credencial: sessao OAuth do wrangler validada contra Pages" -ForegroundColor Green
}

if (-not $env:CLOUDFLARE_ACCOUNT_ID) {
  Fail "CLOUDFLARE_ACCOUNT_ID ausente. Configure a variavel de ambiente (User scope)."
}
if (-not (Test-Path $indexSrc)) { Fail "Nao achei $indexSrc" }

# --- 0.1 GATE ANTI-REGRESSAO: versao em producao ---------------------------
try {
  $prodVerJson = Invoke-RestMethod -Uri "https://vixradar.com/version.json?_=$(Get-Date -Format 'yyyyMMddHHmmss')" -TimeoutSec 10 -Headers @{ "Cache-Control"="no-cache" }
  $prodVersion = $prodVerJson.version
  if ($prodVersion) {
    # So compara depois de extrair CACHE_VERSION do index.html (passo 1),
    # porque precisamos da versao local para comparar.
    $script:prodVersion = $prodVersion
    Write-Host "Gate pre-deploy: producao reporta $prodVersion" -ForegroundColor DarkGray
  }
} catch {
  Warn "Falha ao consultar version.json de producao: $_. Prosseguindo sem o gate anti-regressao."
  $script:prodVersion = $null
}

# --- 0.2 GATE WORKING TREE: sem alteracoes nao commitadas ------------------
$trackedFiles = @(
  "app/index.html",
  "app/version.json",
  "app/deploy_zip/index.html",
  "app/deploy_zip/version.json",
  "scripts/deploy-pages.ps1"
)
$dirty = git diff --name-only -- $trackedFiles 2>$null
if ($DryRun) {
  Write-Host "Gate working tree: pulado (-DryRun nao commita)" -ForegroundColor DarkGray
  $dirty = $null
}
if ($dirty) {
  $dirtyList = ($dirty | ForEach-Object { "  $_" }) -join "`n"
  Fail "Working tree sujo nos arquivos do deploy. Faça commit ou stash antes de deployar:`n$dirtyList"
}
$stagedDirty = git diff --cached --name-only -- $trackedFiles 2>$null
if ($DryRun) { $stagedDirty = $null }
if ($stagedDirty) {
  $stagedList = ($stagedDirty | ForEach-Object { "  $_" }) -join "`n"
  Fail "Arquivos staged mas nao commitados. Commit ou unstage antes de deployar:`n$stagedList"
}
if (-not $DryRun) { Write-Host "Gate working tree: limpo" -ForegroundColor Green }

# --- 1. CACHE_VERSION ------------------------------------------------------
$html = Get-Content $indexSrc -Raw
$m = [regex]::Match($html, 'CACHE_VERSION\s*=\s*"(v[0-9.]+)"')
if (-not $m.Success) { Fail "Nao encontrei CACHE_VERSION em index.html" }
$ver = $m.Groups[1].Value
Write-Host "CACHE_VERSION detectada: $ver" -ForegroundColor Cyan

# --- 1.5 Gate anti-regressao (compara com producao) -----------------------
if ($script:prodVersion) {
  $cmp = Compare-FrontendVersion $ver $script:prodVersion
  if ($cmp -lt 0) {
    Fail "PRODUCAO ESTA A FRENTE DO REPO. Producao=$($script:prodVersion), voce esta tentando deployar $ver. Recupere o bundle de producao, commite e so entao faca novo deploy. NAO deploye — regrediria producao."
  }
  if ($cmp -eq 0) {
    Warn "Producao ja esta em $($script:prodVersion) — deploy e no-op. Use -SkipValidation se for re-deploy intencional."
  }
  Write-Host "Gate pre-deploy: producao=$($script:prodVersion), deploy=$ver OK" -ForegroundColor Green
}

# --- 2. Sincroniza deploy_zip (raiz vence) ---------------------------------
Copy-Item -Force $indexSrc (Join-Path $zipDir "index.html")
foreach ($f in @("_headers","_routes.json","landing-demo.json","robots.txt")) {
  $srcF = Join-Path $appDir $f
  if (Test-Path $srcF) { Copy-Item -Force $srcF (Join-Path $zipDir $f) }
}
# Diretorios de asset publicados. Src e o caminho dentro de app/, Dst e o destino
# DENTRO de deploy_zip. Os dois NAO sao iguais para js/: o index.html referencia
# "app/js/..." em caminho relativo, entao os modulos ES precisam cair em
# deploy_zip/app/js/, nao em deploy_zip/js/.
#
# MODULE-MIG1 (2026-08-03) criou app/js/ e commitou nas duas arvores na mao. Este
# script nunca soube dessa pasta, entao qualquer correcao em app/js/ nao chegaria
# em producao pelo caminho oficial. Achado da auditoria geral de 2026-08-04.
$assetDirs = @(
  @{ Src = "admin"; Dst = "admin"  },
  @{ Src = "js";    Dst = "app\js" }
)
# GITADD-ASSETDIRS1 (2026-08-11): coleta os paths ja resolvidos por este loop,
# pra o git add do passo 6 nunca ficar dessincronizado do que foi de fato copiado.
# Achado da auditoria de organizacao: o commit automatico do passo 6 nunca soube
# de app/js (nem de app/admin), entao deploy publicava em producao e o commit
# ficava pendente ate alguem lembrar de um 'git add' manual (ex.: commit b95a33a).
$assetGitPaths = @()
foreach ($d in $assetDirs) {
  $srcD = Join-Path $appDir $d.Src
  $dstD = Join-Path $zipDir $d.Dst
  if (-not (Test-Path $srcD)) { continue }
  if (Test-Path $dstD) { Remove-Item -Recurse -Force $dstD }
  $dstParent = Split-Path -Parent $dstD
  if ($dstParent -and -not (Test-Path $dstParent)) {
    New-Item -ItemType Directory -Force -Path $dstParent | Out-Null
  }
  Copy-Item -Recurse -Force $srcD $dstD
  Write-Host ("{0}/ copiado para deploy_zip/{1}" -f $d.Src, $d.Dst) -ForegroundColor Cyan
  $assetGitPaths += $srcD
  $assetGitPaths += $dstD
}

# GATE ASSET ORFAO: subpasta nova em app/ que ninguem mapeou nunca chega em producao,
# e o deploy segue verde mentindo. Foi exatamente assim que app/js/ ficou de fora.
# Pasta que NAO e asset publicado entra em $ignorarDirs, com motivo.
$ignorarDirs = @(
  "deploy_zip",  # o proprio destino
  "_arquivo",    # snapshots historicos
  "_preview",    # rascunho de template
  "design",      # documentacao e PNG de design, nao referenciado pelo index.html
  "node_modules"
)
$assetConhecidos = @($assetDirs | ForEach-Object { $_.Src })
foreach ($dir in (Get-ChildItem -Path $appDir -Directory -Force)) {
  # Pasta de ferramenta (.wrangler, .git, .vscode) nunca e asset publicado.
  if ($dir.Name.StartsWith('.')) { continue }
  if ($ignorarDirs -contains $dir.Name) { continue }
  if ($assetConhecidos -contains $dir.Name) { continue }
  Fail "Subpasta 'app/$($dir.Name)' nao esta no mapa `$assetDirs nem em `$ignorarDirs de deploy-pages.ps1. Ela NAO seria publicada e o deploy passaria verde. Classifique-a antes de deployar."
}
# Em -DryRun o deployed_at fica null: nada foi publicado, e carimbar hora de deploy
# num arquivo que ninguem deployou e exatamente o tipo de mentira que a auditoria
# de 2026-08-04 encontrou em producao (version.json v201.93 sobre HTML v202.1).
if ($DryRun) {
  $verJson = "{`"version`":`"$ver`",`"deployed_at`":null}"
} else {
  $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $verJson = "{`"version`":`"$ver`",`"deployed_at`":`"$ts`"}"
}
Set-Content -NoNewline -Path (Join-Path $zipDir "version.json") -Value $verJson
Set-Content -NoNewline -Path (Join-Path $appDir "version.json") -Value $verJson
Write-Host "deploy_zip sincronizado + version.json gerado ($verJson)" -ForegroundColor Cyan

# --- 3. Confere o bundle (arquivos, referencias e sintaxe JS) --------------
foreach ($f in @("index.html","_headers","_routes.json","version.json","landing-demo.json","robots.txt")) {
  if (-not (Test-Path (Join-Path $zipDir $f))) { Fail "Bundle incompleto: falta $f em deploy_zip" }
}

# --- 3.1 Todo <script src> local do index.html existe no bundle -------------
# A lista antiga era hardcoded nos 5 vr-admin-*.js e continuou passando verde
# depois que MODULE-MIG1 os trocou por um bootstrap ES. Gate que valida arquivo
# que ninguem mais carrega nao e gate. Agora a lista sai do proprio HTML.
# /cdn-cgi/ e servido pela propria Cloudflare (email obfuscation, insights) e nunca
# existe no bundle. Excluir, senao o gate reprova um caminho que nao e nosso.
$srcRefs = @(
  [regex]::Matches($html, '<script[^>]*\ssrc="(?<u>[^"]+)"') |
    ForEach-Object { $_.Groups['u'].Value } |
    Where-Object { $_ -notmatch '^(https?:)?//' } |
    Where-Object { $_ -notmatch '^/?cdn-cgi/' } |
    ForEach-Object { ($_ -split '\?')[0].TrimStart('/') } |
    Select-Object -Unique
)
if ($srcRefs.Count -eq 0) {
  Fail "Nenhum <script src> local encontrado em index.html. A regex do gate 3.1 quebrou, corrija antes de deployar."
}
foreach ($ref in $srcRefs) {
  $refPath = Join-Path $zipDir ($ref -replace '/', '\')
  if (-not (Test-Path $refPath)) {
    Fail "Bundle incompleto: index.html referencia '$ref' e o arquivo NAO existe em deploy_zip. Confira o mapa `$assetDirs do passo 2."
  }
}
Write-Host ("Gate de referencia: {0} script(s) local(is) do index.html presente(s)" -f $srcRefs.Count) -ForegroundColor Green

# --- 3.2 Cache-busting ?v= coerente com CACHE_VERSION ----------------------
# MODULE-MIG1 subiu com src="...?v=202.1" e CACHE_VERSION parada em v201.93.
# Producao ficou com HTML novo, version.json velho, e nenhum usuario com cache
# antigo foi avisado de que havia versao nova.
$verNum = $ver.TrimStart('v')
$vQueries = @(
  [regex]::Matches($html, '<script[^>]*\ssrc="(?<u>[^"]*\?v=(?<v>[^"&]+))"') |
    ForEach-Object { $_.Groups['v'].Value } |
    Select-Object -Unique
)
foreach ($vq in $vQueries) {
  if ($vq.TrimStart('v') -ne $verNum) {
    Fail "index.html carrega script com ?v=$vq mas CACHE_VERSION e $ver. Alinhe os dois antes de deployar, senao o cache-busting mente."
  }
}
if ($vQueries.Count -gt 0) {
  Write-Host ("Gate de cache-busting: {0} query ?v= alinhada(s) com {1}" -f $vQueries.Count, $ver) -ForegroundColor Green
}

# --- 3.3 GATE DE SINTAXE JS (obrigatorio, sem bypass) ----------------------
# Causa raiz do incidente MODULE-MIG1: 3 modulos ES foram publicados truncados e
# derrubaram o painel admin inteiro em producao. Health verde, deploy verde,
# version.json verde. Nenhuma etapa do caminho parseava JS. Custo deste gate:
# segundos. Custo de nao ter: um dia de painel morto sem ninguem perceber.
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Fail "node nao encontrado no PATH e o gate de sintaxe JS e obrigatorio. Instale o Node ou corrija o PATH."
}
$jsFiles = @(Get-ChildItem -Path $zipDir -Recurse -Filter *.js -File)
if ($jsFiles.Count -eq 0) { Fail "Nenhum .js em deploy_zip. O sync do passo 2 falhou." }

$tmpEsm = Join-Path $env:TEMP ("vixradar_jscheck_" + [guid]::NewGuid().ToString('N') + ".mjs")
$tmpCjs = [IO.Path]::ChangeExtension($tmpEsm, ".cjs")
$jsRuins = @()
foreach ($js in $jsFiles) {
  # Tenta como ES module; se reprovar, tenta como script classico. So e erro real
  # quando os dois modos falham, senao IIFE legado geraria falso positivo.
  Copy-Item -Force $js.FullName $tmpEsm
  $saidaEsm = & node --check $tmpEsm 2>&1
  $okEsm = ($LASTEXITCODE -eq 0)
  $okCjs = $false
  if (-not $okEsm) {
    Copy-Item -Force $js.FullName $tmpCjs
    & node --check $tmpCjs 2>&1 | Out-Null
    $okCjs = ($LASTEXITCODE -eq 0)
  }
  if (-not ($okEsm -or $okCjs)) {
    $rel = $js.FullName.Substring($zipDir.Length).TrimStart('\')
    $erro = @($saidaEsm | Where-Object { $_ -match 'Error' } | Select-Object -First 1)
    $jsRuins += ("  {0}  ->  {1}" -f $rel, $(if ($erro.Count -gt 0) { $erro[0] } else { "erro de parse" }))
  }
}
Remove-Item -Force $tmpEsm, $tmpCjs -ErrorAction SilentlyContinue
if ($jsRuins.Count -gt 0) {
  Fail ("GATE DE SINTAXE JS reprovou {0} arquivo(s). NADA foi deployado:`n{1}" -f $jsRuins.Count, ($jsRuins -join "`n"))
}
Write-Host ("Gate de sintaxe JS: {0} arquivo(s) OK" -f $jsFiles.Count) -ForegroundColor Green

# --- 3.4 GATE DAS ROTAS DE ACESSO AO PAINEL ADMIN --------------------------
# Contexto (2026-08-09): o Ctrl+Shift+A parou de abrir o painel porque o Brave registra
# esse chord para o comando 52500 (IDC_TAB_SEARCH) e consome a tecla antes de ela chegar
# na pagina. O site estava intacto. A licao nao e sobre o Brave: as entradas do painel sao
# todas discretas, entao perder uma nao quebra nada visivel e o deploy passa verde.
#
# Atalho de teclado e rota de NAVEGACAO, nunca mecanismo de seguranca. A metade (b) existe
# para impedir que ele vire rota de ACESSO. Isto e protecao contra regressao estrutural,
# nao teste de autorizacao: a autoridade final e do Worker, que valida a senha do lado dele
# e nao confia em nada que o frontend afirme.
$idxHtml    = Get-Content (Join-Path $zipDir "index.html") -Raw
$sharedPath = Join-Path $zipDir "app\js\admin\shared.js"
if (-not (Test-Path $sharedPath)) { Fail "Gate 3.4: app/js/admin/shared.js ausente no bundle." }
$sharedJs = Get-Content $sharedPath -Raw
$falhas34 = @()

# (a1) O handler de atalho existe e ainda faz o toggle do overlay. Ancora no par
# fecharAdmin/abrirAdmin porque nome de variavel e mangled e nao serve de ancora. O
# (?!addEventListener) impede que a captura vaze para o listener seguinte.
$mAtalho = [regex]::Match($idxHtml,
  'addEventListener\("keydown",\s*function\s*\(e\)\s*\{(?<corpo>(?:(?!addEventListener)[\s\S]){0,800}?)\w+\.classList\.contains\("vis"\)\s*\?\s*fecharAdmin\(\)\s*:\s*abrirAdmin\(\)')
$corpoAtalho = ""
if (-not $mAtalho.Success) {
  $falhas34 += "  (a) index.html: nao achei o listener de keydown que faz o toggle do painel admin"
} else {
  $corpoAtalho = $mAtalho.Groups['corpo'].Value
  if ($corpoAtalho -notmatch 'shiftKey') { $falhas34 += "  (a) index.html: o handler de atalho nao reconhece shiftKey" }
  if ($corpoAtalho -notmatch 'altKey')   { $falhas34 += "  (a) index.html: o handler de atalho nao reconhece altKey. Com um chord so, basta o navegador reservar ele para o painel ficar inalcancavel por teclado." }
}

# (a2) O modulo ES registra o atalho de fato, nao so define a funcao.
if ($sharedJs -notmatch '(?m)^\s*registerAdminShortcut\(\)\s*;') { $falhas34 += "  (a) shared.js: registerAdminShortcut() definido mas nunca chamado" }
if ($sharedJs -notmatch 'altKey')                                { $falhas34 += "  (a) shared.js: isAdminShortcut nao reconhece altKey" }

# (a3) A rota que nenhum navegador consegue tomar: o botao em Configuracoes.
if ($idxHtml -notmatch 'id="config-admin-entry"[\s\S]{0,600}?abrirAdmin\(\)') {
  $falhas34 += "  (a) index.html: bloco config-admin-entry sem botao que chama abrirAdmin"
}

# (a4) Todo ?v= dos modulos ES bate com CACHE_VERSION. O gate 3.2 so olha o index.html, e
# um import interno atrasado faz o browser baixar shared.js duas vezes, como dois modulos
# distintos, cada um com seu estado.
$jsDir = Join-Path $zipDir "app\js"
if (Test-Path $jsDir) {
  foreach ($js in @(Get-ChildItem -Path $jsDir -Recurse -Filter *.js -File)) {
    $txt = Get-Content $js.FullName -Raw
    foreach ($mv in [regex]::Matches($txt, '\?v=(?<v>[0-9][0-9.]*)')) {
      if ($mv.Groups['v'].Value.TrimStart('v') -ne $verNum) {
        $rel = $js.FullName.Substring($zipDir.Length).TrimStart('\')
        $falhas34 += ("  (a) {0}: import com ?v={1} e CACHE_VERSION e {2}" -f $rel, $mv.Groups['v'].Value, $ver)
      }
    }
  }
}

# (b1) abrirAdmin continua ramificando para o portao de senha quando nao ha sessao.
if ($idxHtml -notmatch 'abrirAdmin\s*=\s*function\s*\(\)\s*\{[\s\S]{0,600}?admin-auth-gate') {
  $falhas34 += "  (b) index.html: abrirAdmin nao ramifica mais para admin-auth-gate. O atalho passaria direto para o painel."
}

# (b2) A autenticacao continua sendo decidida pelo servidor.
$mAuth = [regex]::Match($idxHtml, 'adminAutenticar\s*=\s*async\s*function\s*\(\)\s*\{(?<corpo>[\s\S]{0,1500}?)\}\s*,\s*window\.')
if (-not $mAuth.Success) {
  $falhas34 += "  (b) index.html: nao achei adminAutenticar"
} else {
  $corpoAuth = $mAuth.Groups['corpo'].Value
  if ($corpoAuth -notmatch 'admin_listar') { $falhas34 += "  (b) adminAutenticar nao chama mais action:admin_listar no servidor" }
  if ($corpoAuth -notmatch 'admin_senha')  { $falhas34 += "  (b) adminAutenticar nao envia mais admin_senha" }
  if ($corpoAuth -notmatch '\.ok')         { $falhas34 += "  (b) adminAutenticar nao checa mais o ok da resposta do servidor" }
}

# (b3) O handler de atalho so navega: nao manipula senha nem revela o painel por conta propria.
if ($corpoAtalho) {
  foreach ($proibido in @('admin_senha', 'admin_listar', 'admin-painel')) {
    if ($corpoAtalho -match [regex]::Escape($proibido)) {
      $falhas34 += ("  (b) o handler de atalho toca em '{0}'. Atalho e navegacao, autorizacao e do servidor." -f $proibido)
    }
  }
}

if ($falhas34.Count -gt 0) {
  Fail ("GATE 3.4 (rotas de acesso ao painel admin) reprovou. NADA foi deployado:`n{0}" -f ($falhas34 -join "`n"))
}
Write-Host "Gate 3.4: rotas de acesso ao painel admin OK (atalho, modulo, botao, ?v=, portao de senha)" -ForegroundColor Green

if ($DryRun) {
  Write-Host "`nDRY-RUN: sync feito e todos os gates passaram. NADA foi deployado, NADA foi commitado." -ForegroundColor Cyan
  Write-Host "Rode sem -DryRun para publicar." -ForegroundColor Cyan
  exit 0
}

# --- 4. Deploy -------------------------------------------------------------
Write-Host "`nDeployando para Cloudflare Pages ($ProjectName / main)..." -ForegroundColor Yellow
npx wrangler pages deploy "$zipDir" --project-name=$ProjectName --branch=main --commit-dirty=true
if ($LASTEXITCODE -ne 0) {
  # DEPLOYTS1 (2026-08-04): o passo 2 ja gravou deployed_at com a hora atual. Se o
  # wrangler falha aqui, esse carimbo vira registro de um deploy que nunca existiu,
  # exatamente o tipo de version.json mentiroso que a auditoria de hoje foi achar
  # em producao. Reverte antes de abortar.
  $verJsonFalho = "{`"version`":`"$ver`",`"deployed_at`":null}"
  Set-Content -NoNewline -Path (Join-Path $zipDir "version.json") -Value $verJsonFalho
  Set-Content -NoNewline -Path (Join-Path $appDir "version.json") -Value $verJsonFalho
  Write-Host "version.json revertido para deployed_at:null (o deploy nao aconteceu)." -ForegroundColor DarkGray
  Fail "wrangler pages deploy falhou (exit $LASTEXITCODE)"
}

# --- 5. Validacao em producao ----------------------------------------------
# NAO sai daqui: o passo 6 (sync com o git) precisa rodar mesmo sem validacao,
# senao -SkipValidation reintroduz o drift que este script existe para evitar.
$ok = $true
if ($SkipValidation) {
  Write-Host "`nValidacao pulada (-SkipValidation)." -ForegroundColor DarkGray
} else {

Write-Host "`nValidando producao..." -ForegroundColor Yellow

# PROPAG1 (2026-08-04): a validacao era um Start-Sleep de 4s e um unico tiro. No
# deploy de v202.1 o HTML ja tinha propagado e o version.json ainda nao, entao o
# script saiu com exit 2 e "NADA commitado" sobre um deploy que deu certo. Isso
# gera exatamente o drift repo-producao que este script existe para evitar, e por
# um motivo que so precisava de mais alguns segundos. Agora retenta.
function Wait-Propagacao {
  param([string]$Rotulo, [scriptblock]$Sonda, [int]$Tentativas = 8, [int]$EsperaSeg = 5)
  for ($i = 1; $i -le $Tentativas; $i++) {
    try {
      $r = & $Sonda
      if ($r.ok) {
        Write-Host ("  {0}: {1} OK{2}" -f $Rotulo, $r.valor, $(if ($i -gt 1) { " (tentativa $i)" } else { "" })) -ForegroundColor Green
        return $true
      }
      if ($i -lt $Tentativas) {
        Write-Host ("  {0}: {1}, aguardando propagacao ({2}/{3})" -f $Rotulo, $r.valor, $i, $Tentativas) -ForegroundColor DarkGray
      } else {
        Write-Host ("  {0}: {1} (esperado {2}) apos {3} tentativas" -f $Rotulo, $r.valor, $ver, $Tentativas) -ForegroundColor Red
        return $false
      }
    } catch {
      if ($i -eq $Tentativas) { Write-Host ("  {0}: falha de leitura: {1}" -f $Rotulo, $_) -ForegroundColor Red; return $false }
      Write-Host ("  {0}: erro transiente, retentando ({1}/{2})" -f $Rotulo, $i, $Tentativas) -ForegroundColor DarkGray
    }
    Start-Sleep -Seconds $EsperaSeg
  }
  return $false
}

if (-not (Wait-Propagacao "version.json apex" {
  $vj = Invoke-RestMethod -Uri "https://vixradar.com/version.json?_=$([guid]::NewGuid())" -Headers @{ "Cache-Control"="no-cache" }
  @{ ok = ($vj.version -eq $ver); valor = $vj.version }
})) { $ok = $false }

if (-not (Wait-Propagacao "CACHE_VERSION no HTML" {
  $page = Invoke-WebRequest -Uri "https://vixradar.com/?_=$([guid]::NewGuid())" -UseBasicParsing
  $m2 = [regex]::Match($page.Content, 'CACHE_VERSION="(v[0-9.]+)"')
  @{ ok = ($m2.Success -and $m2.Groups[1].Value -eq $ver); valor = $(if ($m2.Success) { $m2.Groups[1].Value } else { "ausente" }) }
})) { $ok = $false }

# CACHEJS1: o deploy so termina quando os modulos ES que o index.html carrega
# estao servindo os bytes do bundle. Foi assim que MODULE-MIG1 passou verde
# publicando JS quebrado, ninguem conferia o conteudo do que subiu.
foreach ($ref in $srcRefs) {
  $local = Get-Item (Join-Path $zipDir ($ref -replace '/', '\'))
  $rotulo = "asset $ref"
  if (-not (Wait-Propagacao $rotulo {
    $resp = Invoke-WebRequest -Uri ("https://vixradar.com/$ref" + "?_=$([guid]::NewGuid())") -UseBasicParsing -Headers @{ "Cache-Control"="no-cache" }
    @{ ok = ($resp.RawContentLength -eq $local.Length); valor = "$($resp.RawContentLength)B vs $($local.Length)B local" }
  } 6 5)) { $ok = $false }
}

}  # fim do else de -SkipValidation

if (-not $ok) { Write-Host "`nDEPLOY publicado mas validacao divergiu, investigar propagacao/cache. NADA commitado." -ForegroundColor Red; exit 2 }

# --- 5.5 Sincroniza a versao declarada em CLAUDE.md/README.md --------------
# Mesmo racional do deploy-worker.ps1: sem isto a doc so atualiza se alguem
# lembrar depois do deploy.
& (Join-Path $PSScriptRoot "sync-version-docs.ps1") -FrontendVersion $ver

# --- 6. Sync com o git -----------------------------------------------------
# O version.json e GERADO por este script (passo 2). Sem commitar, o repo fica
# declarando a versao anterior enquanto producao ja avancou, e o canonical-test
# acusa drift de frontend. Foi exatamente o que aconteceu com v201.75 (deploy
# 13/07, repo em v201.74 ate 15/07). O deploy so termina quando o GitHub sabe.
if ($SkipGit) {
  Write-Host "`nGit pulado (-SkipGit)." -ForegroundColor DarkGray
  Write-Host "ATENCAO: producao esta em $ver e o repo NAO sabe. O canonical-test vai acusar drift ate voce commitar." -ForegroundColor Yellow
  exit 0
}

Write-Host "`nSincronizando o git..." -ForegroundColor Yellow
Push-Location $root
try {
  # GITADD-ASSETDIRS1: $assetGitPaths vem do loop de copia (~linha 196), sempre
  # os mesmos $srcD/$dstD que acabaram de ser publicados pelo wrangler no passo 4.
  $gitAddPaths = @(
    "app/version.json", "app/deploy_zip/version.json",
    "app/index.html", "app/deploy_zip/index.html",
    "CLAUDE.md", "README.md"
  ) + $assetGitPaths
  git add -- $gitAddPaths
  if ($LASTEXITCODE -ne 0) { Fail "git add falhou (exit $LASTEXITCODE)." }

  $staged = git diff --cached --name-only
  if (-not $staged) {
    Write-Host "  Nada a commitar (repo ja sincronizado)." -ForegroundColor DarkGray
  } else {
    git commit -m "chore(frontend): deploy $ver em producao"
    if ($LASTEXITCODE -ne 0) { Fail "git commit falhou (exit $LASTEXITCODE)." }
    Write-Host "  commit criado" -ForegroundColor Green
  }

  git push origin HEAD
  if ($LASTEXITCODE -ne 0) {
    Write-Host "`nDEPLOY OK mas o PUSH FALHOU, o GitHub ainda nao sabe que producao esta em $ver." -ForegroundColor Red
    Write-Host "O canonical-test vai acusar drift ate o push passar. Resolva e rode: git push origin HEAD" -ForegroundColor Red
    exit 3
  }
  Write-Host "  push OK" -ForegroundColor Green
} finally {
  Pop-Location
}

Write-Host "`nDEPLOY OK, producao em $ver, repo e GitHub sincronizados." -ForegroundColor Green
exit 0
