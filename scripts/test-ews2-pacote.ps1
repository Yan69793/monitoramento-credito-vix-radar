# test-ews2-pacote.ps1 - Prova de duas pontas do portao de publicacao de run_vixradar_ews2_pacote.ps1.
#
# Roda a rotina com -Publicar, mas com -KvCli apontando para um wrangler FALSO (.cmd) que so registra as chamadas
# e guarda o que receberia num arquivo local. Nada toca o KV real.
#   Ponta ruim : 5 pacotes invalidos -> exit 4 e ZERO chamadas ao KV (nem leitura).
#   Ponta boa  : pacote valido -> exit 0, sequencia get/put/get so em ews2:latest, conteudo gravado = pacote.
#   Dry-run    : pacote valido sem -Publicar -> exit 0 e ZERO chamadas ao KV.
#   Guarda     : nenhuma chamada em nenhum cenario menciona ews2:flag.
#
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test-ews2-pacote.ps1 [-PacoteValido <json>]
# Sem -PacoteValido usa o ews2_latest.json mais recente de tmp\operacional\vix-radar\ews2-pacote (rode a rotina em
# dry-run antes). Exit 0 so com todos os asserts verdes.

param([string]$PacoteValido)

$ErrorActionPreference = 'Continue'
$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$Rotina = Join-Path $ProjectRoot 'scripts\run_vixradar_ews2_pacote.ps1'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not $PacoteValido) {
    $PacoteValido = Get-ChildItem -LiteralPath 'E:\Diretorio\Claude\tmp\operacional\vix-radar\ews2-pacote' -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'ews2_latest.json' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $PacoteValido -or -not (Test-Path -LiteralPath $PacoteValido)) { Write-Output 'ERRO: sem pacote valido de referencia (rode a rotina em dry-run antes)'; exit 2 }

$Dir = Join-Path 'E:\Diretorio\Claude\tmp\operacional\vix-radar\ews2-pacote-teste' (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Calls = Join-Path $Dir 'calls.log'
$Store = Join-Path $Dir 'store.json'

# wrangler falso: registra a linha de argumentos; put copia --path para store.json; get devolve store.json
$fakePs = @'
param()
$a = @($args)
$calls = Join-Path $PSScriptRoot 'calls.log'
$store = Join-Path $PSScriptRoot 'store.json'
Add-Content -LiteralPath $calls -Value ($a -join ' ') -Encoding ASCII
$sub = $a[2]
if ($sub -eq 'put') {
    $i = [Array]::IndexOf($a, '--path')
    Copy-Item -LiteralPath $a[$i + 1] -Destination $store -Force
    [Console]::Out.WriteLine('Writing the value to key (fake)')
    exit 0
}
if ($sub -eq 'get') {
    if (Test-Path -LiteralPath $store) { [Console]::Out.Write([System.IO.File]::ReadAllText($store)) } else { [Console]::Out.WriteLine('Value not found') }
    exit 0
}
exit 1
'@
[System.IO.File]::WriteAllText((Join-Path $Dir 'fake.ps1'), $fakePs, $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $Dir 'fake-wrangler.cmd'), "@powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0fake.ps1`" %*`r`n", $Utf8NoBom)
$Fake = Join-Path $Dir 'fake-wrangler.cmd'

$script:Falhas = 0; $script:Total = 0
function Assert-Teste([bool]$Cond, [string]$Nome, [string]$Detalhe) {
    $script:Total++
    if ($Cond) { Write-Output ('PASS ' + $Nome) } else { $script:Falhas++; Write-Output ('FAIL ' + $Nome + ' :: ' + $Detalhe) }
}
function Get-Chamadas { if (Test-Path -LiteralPath $Calls) { return @(Get-Content -LiteralPath $Calls) } else { return @() } }
function Reset-Fake { Remove-Item -LiteralPath $Calls, $Store -Force -ErrorAction SilentlyContinue }
function Invoke-Rotina([string]$Pacote, [string[]]$Extra) {
    $logDir = Join-Path $Dir 'logs'
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Rotina, '-PacotePronto', $Pacote, '-KvCli', $Fake, '-LogDir', $logDir, '-BackupRaiz', (Join-Path $Dir 'backups')) + $Extra
    $saida = & powershell.exe @argv 2>&1
    $code = $LASTEXITCODE
    $res = ($saida | Where-Object { "$_" -match 'RESULTADO ' } | Select-Object -Last 1)
    return [pscustomobject]@{ Code = $code; Resultado = "$res" }
}

$raw = [System.IO.File]::ReadAllText($PacoteValido, [System.Text.Encoding]::UTF8)
$obj = $raw | ConvertFrom-Json
$T = $obj.data_observacao

# Pacotes invalidos: cada um quebra UMA regra do portao
$invalidos = [ordered]@{}
$invalidos['nota_sha256_errado'] = $raw.Replace($obj.liberacao.nota_sha256, ('0' * 64))
$invalidos['schema_errado']      = $raw.Replace('"schema": "ews2/1"', '"schema": "ews2/0"')
$o = $raw | ConvertFrom-Json; $o.emissores = @($o.emissores | Select-Object -Skip 1)
$invalidos['103_emissores']      = ($o | ConvertTo-Json -Depth 12)
$o = $raw | ConvertFrom-Json; $s = $o.sinais_aprovados[0]; $o.emissores[0].sinais.$s = 2
$invalidos['sinal_fora_do_dominio'] = ($o | ConvertTo-Json -Depth 12)
$invalidos['json_truncado']      = $raw.Substring(0, [int]($raw.Length / 2))

foreach ($nome in $invalidos.Keys) {
    $f = Join-Path $Dir ('invalido_' + $nome + '.json')
    [System.IO.File]::WriteAllText($f, $invalidos[$nome], $Utf8NoBom)
    Reset-Fake
    $extra = @('-Publicar')
    if ($nome -eq 'json_truncado') { $extra += @('-T', $T) }
    $r = Invoke-Rotina $f $extra
    $ch = Get-Chamadas
    Assert-Teste ($r.Code -eq 4) ('ruim/' + $nome + ' exit=4') ('exit=' + $r.Code + ' ' + $r.Resultado)
    Assert-Teste ($ch.Count -eq 0 -and -not (Test-Path -LiteralPath $Store)) ('ruim/' + $nome + ' KV intocado') (($ch -join ' || '))
}

# T divergente: pacote valido, mas a rotina esperava outra data de observacao
Reset-Fake
$r = Invoke-Rotina $PacoteValido @('-Publicar', '-T', '2000-01-03')
Assert-Teste ($r.Code -eq 4 -and (Get-Chamadas).Count -eq 0) 'ruim/T_divergente exit=4 e KV intocado' ('exit=' + $r.Code)

# Dry-run com pacote valido: aprova sem nenhuma chamada
Reset-Fake
$r = Invoke-Rotina $PacoteValido @()
Assert-Teste ($r.Code -eq 0) 'dry-run/valido exit=0' ('exit=' + $r.Code + ' ' + $r.Resultado)
Assert-Teste ((Get-Chamadas).Count -eq 0) 'dry-run/valido KV intocado' ((Get-Chamadas) -join ' || ')

# Ponta boa com -Publicar: get (backup), put, get (releitura), todos em ews2:latest
Reset-Fake
$r = Invoke-Rotina $PacoteValido @('-Publicar')
$ch = Get-Chamadas
Assert-Teste ($r.Code -eq 0) 'bom/publicar exit=0' ('exit=' + $r.Code + ' ' + $r.Resultado)
Assert-Teste ($ch.Count -eq 3 -and $ch[0] -match '^kv key get ews2:latest ' -and $ch[1] -match '^kv key put ews2:latest ' -and $ch[2] -match '^kv key get ews2:latest ') 'bom/publicar sequencia get-put-get em ews2:latest' ($ch -join ' || ')
Assert-Teste ((@($ch | Where-Object { $_ -notmatch '--remote' -or $_ -notmatch 'c6805b8d8a7b468e9f854ab4f91fb93a' })).Count -eq 0) 'bom/publicar --remote e namespace RADAR_KV' ($ch -join ' || ')
$igual = (Test-Path -LiteralPath $Store) -and ((Get-FileHash -LiteralPath $Store).Hash -eq (Get-FileHash -LiteralPath $PacoteValido).Hash)
Assert-Teste $igual 'bom/publicar conteudo gravado = pacote validado' 'hash diverge ou store ausente'

# Segunda publicacao: agora existe valor anterior, tem que virar backup
$r = Invoke-Rotina $PacoteValido @('-Publicar')
$bk = $null
if ($r.Resultado -match '"backup":"([^"]+)"') { $bk = $Matches[1] -replace '\\\\', '\' }
Assert-Teste ($r.Code -eq 0 -and $bk -and (Test-Path -LiteralPath $bk) -and $bk.StartsWith($Dir)) 'bom/republicar gera backup do valor anterior' ('exit=' + $r.Code + ' backup=' + $bk)

# Guarda: nada, em cenario nenhum, encostou em ews2:flag
$todas = Get-Content -LiteralPath $Calls -ErrorAction SilentlyContinue
Assert-Teste (-not (@($todas) -match 'ews2:flag')) 'guarda/nunca toca ews2:flag' (@($todas) -join ' || ')

Write-Output ('RESUMO: {0}/{1} pass, {2} falha(s). Artefatos: {3}' -f ($script:Total - $script:Falhas), $script:Total, $script:Falhas, $Dir)
if ($script:Falhas -gt 0) { exit 1 }
exit 0
