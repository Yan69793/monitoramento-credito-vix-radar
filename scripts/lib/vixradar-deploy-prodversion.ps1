<#
.SYNOPSIS
  Decisao do gate anti-regressao do deploy-pages.ps1 (versao de producao).

.DESCRIPTION
  FAILCLOSED1 (2026-10-10): antes desta funcao, uma falha ao ler
  https://vixradar.com/version.json desligava o gate anti-regressao em silencio
  ("Prosseguindo sem o gate"). O efeito era um fail-open: checkout limpo e velho
  + rede fora publicava por cima de producao mais nova, regredindo versao E
  conteudo (o caso real v202.60-sobre-v202.62 reintroduziria o bloco de abril).
  O gate anti-regressao e a unica barreira que compara repo x producao, entao
  quando ele nao pode rodar, o padrao passa a ser ABORTAR.

  Extraida para funcao pura para ser testavel sem rede nem credenciais
  (scripts/test-deploy-prodversion-gate.ps1 roda o codigo real).

  Contrato de saida (hashtable):
    Ok       [bool]   - pode prosseguir com o deploy?
    Version  [string] - versao de producao lida (ou $null quando nao ha valor)
    Bloqueio [string] - motivo do bloqueio quando Ok = $false ($null caso contrario)
    Forcado  [bool]   - $true somente quando -Offline pulou o gate conscientemente
#>
function Resolve-VixProdVersionGate {
  [CmdletBinding()]
  param(
    # Versao lida de producao. Vazio = leitura falhou ou nao trouxe o campo.
    [string]$FetchedVersion,
    # Motivo da falha de leitura (excecao), quando houver.
    [string]$FetchError,
    # Pula o gate de forma explicita e consciente. O deploy assume o risco.
    [switch]$Offline
  )

  if ($FetchedVersion) {
    return @{ Ok = $true; Version = $FetchedVersion; Bloqueio = $null; Forcado = $false }
  }

  if ($Offline) {
    return @{ Ok = $true; Version = $null; Bloqueio = $null; Forcado = $true }
  }

  $motivo = if ($FetchError) { $FetchError } else { "version.json de producao respondeu sem o campo 'version'" }
  return @{ Ok = $false; Version = $null; Bloqueio = $motivo; Forcado = $false }
}
