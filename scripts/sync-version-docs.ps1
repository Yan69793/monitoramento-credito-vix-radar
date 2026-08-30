<#
.SYNOPSIS
  Sincroniza a versao declarada em README.md com a versao real do deploy,
  chamado por deploy-worker.ps1 e deploy-pages.ps1, nunca a mao.

.DESCRIPTION
  A causa do drift de documentacao nao era falta de disciplina: era a
  atualizacao ser um passo manual que ninguem lembrava depois do deploy.
  deploy-worker.ps1/deploy-pages.ps1 ja commitam bundle+config atomicamente
  com a validacao de producao; este script entra no MESMO passo, para a doc
  nascer sincronizada em vez de depender de alguem lembrar.

  So mexe nos pontos que sao tabela de versao viva (README.md "Versoes em
  Producao", comentario do bundle em "Fontes Vivas", CACHE_VERSION). Nao toca
  em referencia historica ("obsoleta desde v4.9.108"), que e registro de quando
  algo mudou, nao ponteiro de versao atual.

  CLAUDE.md NAO e mais alvo. Ele teve tabela de versao ate 25/07/2026, quando o
  hardening 49471e0 a removeu de proposito, 8 dias depois deste script nascer.
  Os dois blocos que miravam CLAUDE.md ficaram sem casar nada por 36 dias, em
  silencio (SYNCDOC-MUDO1, 30/08/2026). README.md e a unica tabela de versao
  viva do repo, e manter duas seria justamente o drift que este script existe
  para matar.

.NOTES
  A GUARDA (SYNCDOC-MUDO1). Cada alvo e declarado com nome + regex, e a pergunta
  passou a ser "a ancora existe neste arquivo?" via [regex]::Matches().Count, e
  nao "o texto mudou?". Sao coisas diferentes: arquivo ja sincronizado tambem
  nao muda. A versao antiga somava os dois casos num "nada a alterar" mudo, que
  e como dois alvos mortos passaram despercebidos por mais de um mes. Alvo que
  nao casa nada agora sai em amarelo, nomeado.

  POR QUE AVISO E NAO ABORTO no fluxo normal. Este script roda no passo 5.5 do
  deploy, com producao JA publicada e o git ainda nao commitado. Abortar aqui
  deixaria producao na frente do repo, que e exatamente o drift descrito no
  cabecalho do deploy-worker.ps1. Quem precisa de exit code, teste de duas
  pontas e CI, usa -Strict.

  ENCODING. README.md e UTF-8 sem BOM. Leitura e escrita usam .NET com encoding
  explicito porque Get-Content/Set-Content sem -Encoding mudam de default entre
  powershell.exe 5.1 (ANSI) e pwsh 7 (UTF-8): sob 5.1 o "seta para a esquerda"
  do bloco Fontes Vivas e os acentos seriam corrompidos na gravacao. Mesma
  classe de bug que o lint-encoding.ps1 caca nos .ps1.

.EXAMPLE
  pwsh ./scripts/sync-version-docs.ps1 -WorkerVersion v4.9.164
  pwsh ./scripts/sync-version-docs.ps1 -FrontendVersion v201.76
  pwsh ./scripts/sync-version-docs.ps1 -FrontendVersion v201.76 -Strict
#>
[CmdletBinding()]
param(
  [string]$WorkerVersion,
  [string]$FrontendVersion,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"
$root   = Split-Path -Parent $PSScriptRoot
$readme = Join-Path $root "README.md"

# InvariantCulture de proposito: em -Format o "/" e placeholder de separador de
# data e vira "." em locale pt-BR. Com "-" nao ocorre, mas fixar a cultura tira
# a duvida em vez de depender de qual caractere e placeholder.
$hoje = (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)

$utf8SemBom = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
# Alvos declarados. Cada entrada e um contrato: "esta ancora existe no arquivo".
# Alvo que para de casar vira AVISO, nunca silencio. Ao remover uma linha de
# versao da doc, remova o alvo aqui junto, senao o deploy passa a reclamar.
# ---------------------------------------------------------------------------
$alvos = @()

if ($WorkerVersion) {
  $wv = $WorkerVersion -replace '\.js$', ''

  $alvos += @{
    Nome    = 'README.md :: comentario do bundle vivo (bloco Fontes Vivas)'
    Arquivo = $readme
    Padrao  = 'v4\.9\.\d+\.js(\s*←\s*bundle Worker em produção)'
    Novo    = "$wv.js`$1"
  }
  $alvos += @{
    Nome    = 'README.md :: tabela Versoes em Producao, linha Worker'
    Arquivo = $readme
    Padrao  = '(\|\s*Worker `radar-credito-api`\s*\|\s*)v4\.9\.\d+(\s*\|\s*)[0-9]{4}-[0-9]{2}-[0-9]{2}(\s*\|)'
    Novo    = "`${1}$wv`${2}$hoje`${3}"
  }
}

if ($FrontendVersion) {
  $fv = $FrontendVersion

  $alvos += @{
    Nome    = 'README.md :: CACHE_VERSION (bloco Fontes Vivas)'
    Arquivo = $readme
    Padrao  = 'CACHE_VERSION=v[0-9.]+'
    Novo    = "CACHE_VERSION=$fv"
  }
  $alvos += @{
    Nome    = 'README.md :: tabela Versoes em Producao, linha Frontend'
    Arquivo = $readme
    Padrao  = '(\|\s*Frontend `vixradar\.com`\s*\|\s*)v[0-9.]+(\s*\|\s*)[0-9]{4}-[0-9]{2}-[0-9]{2}(\s*\|)'
    Novo    = "`${1}$fv`${2}$hoje`${3}"
  }
}

function Sync-Alvos {
  param([array]$Alvos, [System.Text.Encoding]$Enc)

  $res = @{ Alterados = @(); JaOk = @(); Ausentes = @() }
  if ($Alvos.Count -eq 0) { return $res }

  $arquivos = @($Alvos | ForEach-Object { $_.Arquivo } | Select-Object -Unique)

  foreach ($arquivo in $arquivos) {
    $doArquivo = @($Alvos | Where-Object { $_.Arquivo -eq $arquivo })

    if (-not (Test-Path -LiteralPath $arquivo)) {
      foreach ($a in $doArquivo) { $res.Ausentes += "$($a.Nome) [arquivo inexistente: $arquivo]" }
      continue
    }

    $antes = [System.IO.File]::ReadAllText($arquivo, $Enc)
    $texto = $antes

    foreach ($a in $doArquivo) {
      # A guarda em si: a ancora existe? Nao "mudou alguma coisa?".
      if (([regex]::Matches($texto, $a.Padrao)).Count -eq 0) {
        $res.Ausentes += $a.Nome
        continue
      }
      $depois = [regex]::Replace($texto, $a.Padrao, $a.Novo)
      if ($depois -ne $texto) { $res.Alterados += $a.Nome } else { $res.JaOk += $a.Nome }
      $texto = $depois
    }

    if ($texto -ne $antes) { [System.IO.File]::WriteAllText($arquivo, $texto, $Enc) }
  }

  return $res
}

if ($alvos.Count -eq 0) {
  Write-Host "Nada a sincronizar: informe -WorkerVersion e/ou -FrontendVersion." -ForegroundColor DarkGray
  return
}

$r = Sync-Alvos -Alvos $alvos -Enc $utf8SemBom

if ($r.Alterados.Count -gt 0) {
  Write-Host "Docs sincronizados: $($r.Alterados -join ', ')" -ForegroundColor Cyan
}
if ($r.JaOk.Count -gt 0) {
  Write-Host "Docs ja sincronizados, alvo presente e sem mudanca: $($r.JaOk -join ', ')" -ForegroundColor DarkGray
}

if ($r.Ausentes.Count -gt 0) {
  Write-Host ""
  Write-Host "AVISO: ALVO DE SINCRONIA AUSENTE. $($r.Ausentes.Count) ponto(s) da doc NAO foram atualizados:" -ForegroundColor Yellow
  foreach ($nome in $r.Ausentes) {
    Write-Host "  - $nome" -ForegroundColor Yellow
  }
  Write-Host "  A regex do alvo nao casou nada. Ou a linha mudou de forma, ou saiu do arquivo." -ForegroundColor Yellow
  Write-Host "  Conserte a linha OU remova o alvo de scripts/sync-version-docs.ps1." -ForegroundColor Yellow
  Write-Host "  Alvo declarado que nunca casa e guarda morta, e guarda morta nao avisa quando a doc mente." -ForegroundColor Yellow
  if ($Strict) {
    Write-Host "  -Strict ligado, saindo com codigo 1." -ForegroundColor Yellow
    exit 1
  }
}
