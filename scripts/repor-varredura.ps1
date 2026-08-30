<#
.SYNOPSIS
Repoe varredura de dias perdidos, submetendo analises via receber_analise.

.DESCRIPTION
Modo -EnvioDireto: le um JSON com payloads prontos (lista de {empresa, setor,
provedor, resultado}) e submete cada um via receber_analise, com routine_key do
registro Windows (escopo User), no padrao Submit-Analise da rotina noturna.
Cada payload vira um POST para $WorkerUrl; a resposta e' validada em resp.ok.

Uso:
  powershell.exe -File repor-varredura.ps1 -EnvioDireto -PayloadPath .\payload.json

Saida: log em logs/routines/repor-varredura_YYYYMMDD.log terminando com
FIM: submit_ok=N (N = numero de submissoes cujo evento entrou no estado,
resp.n_eventos >= 1). O Worker responde ok:true mesmo quando descarta o
evento (removidos_pre_verificador > 0, fonte rejeitada), entao ok de
transporte nao conta. Submissao aceita sem evento persistido loga DESCARTADO
e nao soma. Exit code 0 se todos os alvos entraram, 1 se algum nao
(regra Task Scheduler: exit, nao return).
#>
[CmdletBinding()]
param(
  [switch]$EnvioDireto,
  [string]$PayloadPath = '',
  [string]$WorkerUrl = 'https://api.vixradar.com',
  [int]$TimeoutSec = 120
)

$ErrorActionPreference = 'Continue'

$script:LogDir = Join-Path $PSScriptRoot '..\logs\routines'
$script:LogFile = Join-Path $script:LogDir ("repor-varredura_" + (Get-Date -Format 'yyyyMMdd') + '.log')

function Write-Log {
  param([string]$Msg)
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Msg
  try {
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
  } catch {
    # Log nunca aborta a rotina; fallback para console.
  }
  Write-Host $line
}

function Get-RoutineKey {
  # Fonte canonica: registro Windows escopo User (ROTA1). Processo longevo herdaria
  # o env do boot e mandaria chave velha apos rotacao; hidratar do registro sempre.
  $doRegistro = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
  if ($doRegistro) { return $doRegistro }
  if ($env:ROUTINE_API_KEY) { return $env:ROUTINE_API_KEY }
  throw 'ROUTINE_API_KEY nao definida. Configure no registro User ou em $env:ROUTINE_API_KEY.'
}

function Invoke-WorkerJsonUtf8 {
  param([string]$Uri, $BodyObj, [int]$TimeoutSec = 120, [int]$Depth = 16)
  # Worker responde application/json SEM charset; Windows PowerShell 5.1 decodificaria
  # como ISO-8859-1 e corromperia acentos. Enviar bytes UTF-8 e decodificar a resposta
  # como UTF-8 explicitamente (mesmo idioma do Submit-Analise da rotina noturna).
  $params = @{ Uri = $Uri; Method = 'Post'; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
  $params.ContentType = 'application/json; charset=utf-8'
  $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($BodyObj | ConvertTo-Json -Depth $Depth -Compress))
  $resp = Invoke-WebRequest @params
  return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

function Submit-Analise {
  param($Key, $Empresa, $Setor, $Resultado, [string]$Provedor)
  $body = @{
    action = 'receber_analise'; routine_key = $Key; empresa = $Empresa; setor = $Setor
    _matinal = $false; provedor = $Provedor; resultado = $Resultado
  }
  return Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj $body -TimeoutSec $TimeoutSec
}

try {
  if (-not $EnvioDireto) {
    throw 'Modo -EnvioDireto obrigatorio nesta versao. Uso: repor-varredura.ps1 -EnvioDireto -PayloadPath <json>.'
  }
  if (-not $PayloadPath -or -not (Test-Path -Path $PayloadPath)) {
    throw "PayloadPath invalido ou inexistente: $PayloadPath"
  }
  if (-not (Test-Path -Path $script:LogDir)) {
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
  }

  $key = Get-RoutineKey
  $payloads = Get-Content -Path $PayloadPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $total = @($payloads).Count
  Write-Log "inicio reposicao. payloads=$total arquivo=$PayloadPath"

  $okCount = 0
  foreach ($p in @($payloads)) {
    $emp = [string]$p.empresa
    $setor = [string]$p.setor
    $prov = [string]$p.provedor
    if (-not $prov) { $prov = 'reposicao-manual' }
    try {
      $resp = Submit-Analise -Key $key -Empresa $emp -Setor $setor -Resultado $p.resultado -Provedor $prov
      if ($resp.ok -eq $true) {
        $nEv = 0
        if ($null -ne $resp.n_eventos) { $nEv = [int]$resp.n_eventos }
        $removidos = 0
        if ($null -ne $resp.verificacao -and $null -ne $resp.verificacao.removidos_pre_verificador) {
          $removidos = [int]$resp.verificacao.removidos_pre_verificador
        }
        if ($nEv -ge 1) {
          $okCount = $okCount + 1
          Write-Log ("OK|" + $emp + "|n_eventos=" + $nEv + "|removidos_pre_verificador=" + $removidos + "|pendente_async=" + $resp.pendente_verificacao_async)
        } else {
          # ok de transporte sem evento persistido: fonte rejeitada pelo Worker
          # (validarDatasFontes) ou sem fato valido na janela. Nao conta como reposicao.
          Write-Log ("DESCARTADO|" + $emp + "|n_eventos=" + $nEv + "|removidos_pre_verificador=" + $removidos)
        }
      } else {
        Write-Log ("FALHA|" + $emp + "|" + $resp.erro)
      }
    } catch {
      Write-Log ("ERRO|" + $emp + "|" + $_.Exception.Message)
    }
  }

  Write-Log ("FIM: submit_ok=" + $okCount + " de " + $total + " (eventos persistidos)")
  if ($okCount -eq $total) { exit 0 }
  exit 1
} catch {
  Write-Log ("ERRO_GERAL|" + $_.Exception.Message)
  exit 1
}
