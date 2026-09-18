<#
.SYNOPSIS
  Prova de duas pontas da guarda CFG-01 (versao do wrangler no deploy).

.DESCRIPTION
  Roda a FUNCAO REAL (dot-source de scripts/lib/vixradar-wrangler-pin.ps1, a
  mesma que o deploy-worker.ps1 carrega) contra uma bancada isolada sob
  scripts/_tmp_wrangler_pin_test/. Nao toca em api/, no wrangler.toml, na rede
  nem em producao.

  Caso bom (a guarda tem que ACEITAR):
    1. declarado 4.118.0, instalado 4.118.0, binario responde 4.118.0.

  Casos ruins (a guarda tem que REPROVAR, cada um pelo motivo certo):
    2. api/package.json sem a chave wrangler em dependencies;
    3. declarado com faixa (^4.118.0) em vez de versao exata;
    4. wrangler ausente de node_modules depois do npm ci --omit=dev;
    5. instalado difere do declarado (lock fora de sincronia);
    6. binario responde versao diferente da declarada;
    7. binario nao responde (sai com exit code diferente de zero).

  E um segundo caso bom: a guarda precisa aceitar $ApiDir relativo. Sem isso o
  Push-Location faz o caminho do binario dobrar o prefixo e a guarda reprova pelo
  motivo errado. Foi medido contra o api/ real em 18/09/2026.

  Cada caso confere o Ok E o motivo, porque "reprovou" sozinho nao prova que
  reprovou pelo motivo certo.

  Fecha com a checagem de fiacao: o deploy-worker.ps1 precisa carregar a lib,
  chamar a funcao e abortar com o motivo dela. Sem isso a guarda seria codigo
  morto passando no proprio teste.

.EXAMPLE
  powershell.exe -NoProfile -File scripts/test-wrangler-pin.ps1
  exit 0 = todos os casos passam
#>
[CmdletBinding()]
param(
  # Caminho alternativo do deploy-worker.ps1, so para medir a ponta ruim da
  # fiacao: com uma copia mutada (gate movido para depois do deploy) o bloco [9]
  # tem que REPROVAR. Sem argumento, audita o script real.
  [string]$DeployPath
)
$ErrorActionPreference = 'Continue'

$root   = $PSScriptRoot                       # scripts/
$bench  = Join-Path $root "_tmp_wrangler_pin_test"
$lib    = Join-Path (Join-Path $root "lib") "vixradar-wrangler-pin.ps1"
$deploy = if ($DeployPath) { $DeployPath } else { Join-Path $root "deploy-worker.ps1" }

if (-not (Test-Path $lib))    { Write-Host "FALHA lib nao encontrada: $lib"; exit 1 }
if (-not (Test-Path $deploy)) { Write-Host "FALHA deploy-worker.ps1 nao encontrado: $deploy"; exit 1 }

. $lib

if (-not (Get-Command Test-VixWranglerPin -ErrorAction SilentlyContinue)) {
  Write-Host "FALHA funcao Test-VixWranglerPin nao carregada pelo dot-source"
  exit 1
}

$falhas = 0
function Checar($nome, $condicao, $detalhe) {
  if ($condicao) {
    Write-Host "  ok   $nome" -ForegroundColor Green
  } else {
    Write-Host "  FALHA $nome -> $detalhe" -ForegroundColor Red
    $script:falhas++
  }
}

# ---------------------------------------------------------------------------
# Bancada. Cada caso e um diretorio com a forma real de api/:
#   package.json
#   node_modules/wrangler/package.json
#   node_modules/wrangler/bin/wrangler.js   (stub que imprime a versao)
# O stub e executado por node de verdade, entao a terceira ponta da guarda e
# medida de verdade, nao simulada.
# ---------------------------------------------------------------------------
function New-Caso {
  param(
    [string]$Nome,
    [string]$Declarado,      # $null = nao declara wrangler
    [string]$Instalado,      # $null = nao cria node_modules
    [string]$Responde,       # $null = nao cria o binario
    [int]$ExitCode = 0
  )

  $dir = Join-Path $bench $Nome
  if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
  New-Item -ItemType Directory -Path $dir -Force | Out-Null

  $deps = '"@sentry/cloudflare": "^10.69.0"'
  if ($Declarado) { $deps = $deps + ', "wrangler": "' + $Declarado + '"' }
  $pkg = '{ "name": "api", "dependencies": { ' + $deps + ' } }'
  Set-Content -Path (Join-Path $dir 'package.json') -Value $pkg -Encoding UTF8

  if ($Instalado) {
    $wr = Join-Path $dir 'node_modules\wrangler'
    New-Item -ItemType Directory -Path (Join-Path $wr 'bin') -Force | Out-Null
    Set-Content -Path (Join-Path $wr 'package.json') -Encoding UTF8 -Value ('{ "name": "wrangler", "version": "' + $Instalado + '" }')
    if ($Responde) {
      $js = 'console.log("' + $Responde + '"); process.exit(' + $ExitCode + ');'
      Set-Content -Path (Join-Path $wr 'bin\wrangler.js') -Value $js -Encoding UTF8
    }
  }
  return $dir
}

if (Test-Path $bench) { Remove-Item $bench -Recurse -Force }
New-Item -ItemType Directory -Path $bench -Force | Out-Null

Write-Host ""
Write-Host "CFG-01: guarda da versao do wrangler (funcao real)" -ForegroundColor Cyan

# --- Caso bom ---------------------------------------------------------------
Write-Host "`n[1] caso bom: declarado, instalado e respondendo 4.118.0"
$d = New-Caso -Nome 'ok' -Declarado '4.118.0' -Instalado '4.118.0' -Responde '4.118.0'
$r = Test-VixWranglerPin -ApiDir $d
Checar 'aceita' ($r.Ok -eq $true) "Ok=$($r.Ok) motivo=$($r.Motivo)"
Checar 'reporta a versao declarada' ($r.Declarado -eq '4.118.0') "Declarado=$($r.Declarado)"
Checar 'sem motivo de reprovacao' ([string]::IsNullOrEmpty($r.Motivo)) "Motivo=$($r.Motivo)"

# --- Casos ruins ------------------------------------------------------------
Write-Host "`n[2] caso ruim: api/package.json nao declara wrangler"
$d = New-Caso -Nome 'sem-declaracao' -Declarado $null -Instalado '4.118.0' -Responde '4.118.0'
$r = Test-VixWranglerPin -ApiDir $d
Checar 'reprova' ($r.Ok -eq $false) "Ok=$($r.Ok)"
Checar 'motivo e a ausencia da declaracao' ($r.Motivo -match "nao declara 'wrangler'") "Motivo=$($r.Motivo)"

Write-Host "`n[3] caso ruim: declarado com faixa (^4.118.0) em vez de versao exata"
$d = New-Caso -Nome 'com-faixa' -Declarado '^4.118.0' -Instalado '4.118.0' -Responde '4.118.0'
$r = Test-VixWranglerPin -ApiDir $d
Checar 'reprova' ($r.Ok -eq $false) "Ok=$($r.Ok)"
Checar 'motivo e a exigencia de versao exata' ($r.Motivo -match 'versao EXATA') "Motivo=$($r.Motivo)"

Write-Host "`n[4] caso ruim: wrangler ausente de node_modules apos npm ci --omit=dev"
$d = New-Caso -Nome 'sem-instalacao' -Declarado '4.118.0' -Instalado $null -Responde $null
$r = Test-VixWranglerPin -ApiDir $d
Checar 'reprova' ($r.Ok -eq $false) "Ok=$($r.Ok)"
Checar 'motivo e a ausencia em node_modules' ($r.Motivo -match 'ausente em node_modules') "Motivo=$($r.Motivo)"

Write-Host "`n[5] caso ruim: instalado difere do declarado (lock fora de sincronia)"
$d = New-Caso -Nome 'divergente' -Declarado '4.118.0' -Instalado '4.117.0' -Responde '4.117.0'
$r = Test-VixWranglerPin -ApiDir $d
Checar 'reprova' ($r.Ok -eq $false) "Ok=$($r.Ok)"
Checar 'motivo e a divergencia declarado x instalado' ($r.Motivo -match 'difere do declarado') "Motivo=$($r.Motivo)"

Write-Host "`n[6] caso ruim: binario responde versao diferente da declarada"
$d = New-Caso -Nome 'binario-outro' -Declarado '4.118.0' -Instalado '4.118.0' -Responde '4.999.9'
$r = Test-VixWranglerPin -ApiDir $d
Checar 'reprova' ($r.Ok -eq $false) "Ok=$($r.Ok)"
Checar 'motivo e a versao que o binario respondeu' ($r.Motivo -match 'responde') "Motivo=$($r.Motivo)"

Write-Host "`n[7] caso ruim: binario nao responde (exit code diferente de zero)"
$d = New-Caso -Nome 'binario-quebrado' -Declarado '4.118.0' -Instalado '4.118.0' -Responde '4.118.0' -ExitCode 7
$r = Test-VixWranglerPin -ApiDir $d
Checar 'reprova' ($r.Ok -eq $false) "Ok=$($r.Ok)"
Checar 'motivo e o exit code da sonda' ($r.Motivo -match 'nao respondeu a --version') "Motivo=$($r.Motivo)"

Write-Host "`n[8] caso bom com caminho relativo: o prefixo nao pode dobrar"
$d = New-Caso -Nome 'relativo' -Declarado '4.118.0' -Instalado '4.118.0' -Responde '4.118.0'
Push-Location $bench
try {
  $r = Test-VixWranglerPin -ApiDir 'relativo'
} finally {
  Pop-Location
}
Checar 'aceita caminho relativo sem dobrar o prefixo' ($r.Ok -eq $true) "Ok=$($r.Ok) resposta=$($r.Resposta)"

# --- Fiacao -----------------------------------------------------------------
# Uma guarda que passa no proprio teste e nao esta ligada no deploy nao guarda
# nada. Aqui se confere que o deploy-worker.ps1 carrega a lib, chama a funcao,
# aborta com o motivo dela e nao voltou a chamar o npx.
Write-Host "`n[9] fiacao: o deploy-worker.ps1 usa esta guarda, e ANTES de qualquer wrangler"
$deployTxt = Get-Content $deploy -Raw

# Duas licoes de medicao estao embutidas aqui.
#
# 1. ORDEM, nao presenca. A primeira versao procurava so os literais, e isso foi
#    refutado: mover o bloco inteiro do gate para DEPOIS da linha de deploy
#    mantinha todos os literais no arquivo, o deploy rodava sem portao nenhum, e
#    o teste terminava verde.
# 2. SO LINHA EXECUTAVEL. Comentar a chamada e deixar o literal num comentario
#    satisfazia a checagem de presenca. Comentario nao executa nada.
#
# A sequencia exigida agora e: dot-source < gate < primeira chamada ao wrangler
# < aborto < deploy. Nenhuma chamada ao wrangler pode vir antes do gate, porque
# antes dele a versao da ferramenta nao foi conferida.
$textoExecutavel = (@($deployTxt -split "`n" | Where-Object { $_.TrimStart() -notlike '#*' }) -join "`n")

$posDotSource     = $textoExecutavel.IndexOf('vixradar-wrangler-pin.ps1')
$posGate          = $textoExecutavel.IndexOf('Test-VixWranglerPin -ApiDir')
$posAborta        = $textoExecutavel.IndexOf('Fail $pinWrangler.Motivo')
$posDeploy        = $textoExecutavel.IndexOf('deploy $bundle --config')
$posPrimeiraSonda = $textoExecutavel.IndexOf('secret list')

Checar 'carrega a lib' ($posDotSource -ge 0) 'dot-source ausente'
Checar 'chama Test-VixWranglerPin' ($posGate -ge 0) 'chamada ausente'
Checar 'aborta com o motivo da funcao' ($posAborta -ge 0) 'abortar nao usa o Motivo'
Checar 'acha o comando de deploy' ($posDeploy -ge 0) 'nao achei a linha de deploy'
Checar 'acha chamada ao wrangler' ($posPrimeiraSonda -ge 0) 'nao achei nenhuma chamada ao wrangler'
Checar 'a lib e carregada antes do gate' (($posDotSource -ge 0) -and ($posDotSource -lt $posGate)) "lib=$posDotSource gate=$posGate"
Checar 'o gate roda ANTES de qualquer chamada ao wrangler' (($posGate -ge 0) -and ($posPrimeiraSonda -gt $posGate)) "gate=$posGate sonda=$posPrimeiraSonda"
Checar 'o gate roda ANTES do deploy' (($posGate -ge 0) -and ($posDeploy -ge 0) -and ($posGate -lt $posDeploy)) "gate=$posGate deploy=$posDeploy"
Checar 'o aborto fica entre o gate e o deploy' (($posAborta -gt $posGate) -and ($posAborta -lt $posDeploy)) "aborta=$posAborta gate=$posGate deploy=$posDeploy"
Checar 'nenhum npx em linha executavel' ($textoExecutavel -notmatch '\bnpx\b') 'npx resolve a ferramenta pela rede quando o pacote falta'

# A linha que executa o deploy tem que chamar o binario local. A checagem
# anterior proibia so o literal "npx wrangler deploy", e "npx wrangler@4.118.0
# deploy" nao casa com esse literal - ou seja, aceitava exatamente a coisa que o
# CFG-01 fecha. Agora a asserção e sobre a linha inteira.
$linhasDeploy = @($textoExecutavel -split "`n" | Where-Object { $_ -match 'deploy \$bundle' })
Checar 'existe uma unica linha de deploy' ($linhasDeploy.Count -eq 1) "achei $($linhasDeploy.Count)"
if ($linhasDeploy.Count -eq 1) {
  $linha = $linhasDeploy[0].Trim()
  Checar 'o deploy chama o binario local' ($linha -match '^&\s+node\s+\$wranglerBin\s+deploy\b') "linha: $linha"
  Checar 'o deploy nao passa pelo npx' ($linha -notmatch 'npx') "linha: $linha"
}

# A lib tem que estar protegida pelo gate de working tree E levada pelo commit:
# sem as duas, o deploy roda uma versao da guarda que o repo nao tem.
Checar 'a lib esta na lista de arquivos do deploy' ($textoExecutavel -match '\$trackedFiles[\s\S]{0,900}?vixradar-wrangler-pin\.ps1') 'fora do gate de working tree'
Checar 'a lib entra no git add' ($textoExecutavel -match 'git add[\s\S]{0,400}?vixradar-wrangler-pin\.ps1') 'fora do git add'

# --- Limpeza ----------------------------------------------------------------
if (Test-Path $bench) { Remove-Item $bench -Recurse -Force }

Write-Host ""
if ($falhas -eq 0) {
  Write-Host "CFG-01 OK: caso bom aceito, 6 casos ruins reprovados pelo motivo certo, guarda ligada no deploy." -ForegroundColor Green
  exit 0
} else {
  Write-Host "CFG-01 FALHOU: $falhas verificacao(oes) reprovada(s)." -ForegroundColor Red
  exit 1
}
