# test-ews2-pacote.ps1 - Prova de duas pontas do portao de publicacao de run_vixradar_ews2_pacote.ps1.
#
# Roda a rotina com -Publicar, mas com -KvCli apontando para um wrangler FALSO (.cmd) que so registra as chamadas
# e guarda o que receberia num arquivo local. Nada toca o KV real.
#   Ponta ruim : 5 pacotes invalidos -> exit 4 e ZERO chamadas ao KV (nem leitura).
#   Ponta boa  : pacote valido -> exit 0, sequencia get/put/get so em ews2:latest, conteudo gravado = pacote.
#   Dry-run    : pacote valido sem -Publicar -> exit 0 e ZERO chamadas ao KV.
#   Guarda     : nenhuma chamada fora dos cenarios de conferencia menciona ews2:flag.
#   Conferencia: veredito desligar (EWS atual ganha em 6 de 6) -> exit 9, flag gravada com ativo=false e so assim;
#                EWS 2.0 melhor, empate, amostra pequena e dry-run -> flag intocada.
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
    if ($Extra -notcontains '-LivroDir') { $argv += '-SemConferencia' }
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

# Guarda: nada, ate aqui, encostou em ews2:flag
$todas = Get-Content -LiteralPath $Calls -ErrorAction SilentlyContinue
Assert-Teste (-not (@($todas) -match 'ews2:flag')) 'guarda/nunca toca ews2:flag fora da conferencia' (@($todas) -join ' || ')

# ---------------- Conferencia (EWS2CONF1): livro, historico e eventos de teste, tudo em pasta temporaria
$baixas = @($obj.emissores | Where-Object { $_.severidade -eq 'baixa' } | Select-Object -First 6)
$hist = Join-Path $Dir 'hist'
New-Item -ItemType Directory -Force -Path (Join-Path $hist $T) | Out-Null
$escoreAtual = @{}; foreach ($e in $baixas) { $escoreAtual[$e.nome] = 90 }
$hjson = [ordered]@{ emissores = @($obj.emissores | ForEach-Object { $sc = 0; if ($escoreAtual.ContainsKey($_.nome)) { $sc = 90 }; [ordered]@{ name = $_.nome; features = [ordered]@{ ews_score = $sc } } }) }
[System.IO.File]::WriteAllText((Join-Path $hist ($T + '\predictive.json')), ($hjson | ConvertTo-Json -Depth 6), $Utf8NoBom)

function New-Eventos([string]$Nome, $Emissores) {
    $f = Join-Path $Dir ('eventos_' + $Nome + '.json')
    $i = 0
    $lista = @($Emissores | ForEach-Object { $i++; [ordered]@{ cnpj = $_.cnpj; data = (([datetime]$T).AddDays(10 + $i * 3)).ToString('yyyy-MM-dd') } })
    [System.IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject $lista -Depth 4), $Utf8NoBom)
    return $f
}
function Invoke-Conf([string]$Nome, [string]$EventosArq, [string[]]$Modo) {
    Reset-Fake
    $livro = Join-Path $Dir ('livro_' + $Nome)
    Remove-Item -LiteralPath $livro -Recurse -Force -ErrorAction SilentlyContinue
    $r = Invoke-Rotina $PacoteValido (@('-LivroDir', $livro, '-HistoricoDir', $hist, '-EventosJson', $EventosArq, '-HojeConferencia', '2027-03-01') + $Modo)
    return [pscustomobject]@{ R = $r; Livro = $livro; Ch = @(Get-Chamadas) }
}

# Ponta ruim: o EWS atual ranqueia os 6 eventos acima do EWS 2.0 (todos baixa no pacote) -> desligar
$evRuim = New-Eventos 'ruim' $baixas
# 1a rodada: o veredito so avisa (exit 14), a flag nao e tocada
$c = Invoke-Conf 'ruim' $evRuim @('-Publicar', '-ConfirmacaoMinDias', '0')
Assert-Teste ($c.R.Code -eq 14 -and -not (@($c.Ch) -match 'ews2:flag')) 'conferencia/desligar 1a rodada so avisa (exit=14, flag intocada)' ('exit=' + $c.R.Code + ' ' + ($c.Ch -join ' || '))
# 2a rodada com o mesmo veredito: confirma e desliga
Reset-Fake
$r2 = Invoke-Rotina $PacoteValido @('-LivroDir', $c.Livro, '-HistoricoDir', $hist, '-EventosJson', $evRuim, '-HojeConferencia', '2027-03-01', '-Publicar', '-ConfirmacaoMinDias', '0')
$c = [pscustomobject]@{ R = $r2; Livro = $c.Livro; Ch = @(Get-Chamadas) }
$flagCalls = @($c.Ch | Where-Object { $_ -match 'ews2:flag' })
Assert-Teste ($c.R.Code -eq 9) 'conferencia/desligar 2a rodada confirma exit=9' ('exit=' + $c.R.Code + ' ' + $c.R.Resultado)
Assert-Teste ($flagCalls.Count -eq 3 -and $flagCalls[0] -match '^kv key get ews2:flag ' -and $flagCalls[1] -match '^kv key put ews2:flag ' -and $flagCalls[2] -match '^kv key get ews2:flag ') 'conferencia/desligar sequencia get-put-get em ews2:flag' ($c.Ch -join ' || ')
$gravado = if (Test-Path -LiteralPath $Store) { [System.IO.File]::ReadAllText($Store) | ConvertFrom-Json } else { $null }
Assert-Teste ($gravado -and $gravado.ativo -eq $false -and $gravado.origem -eq 'conferencia_automatica') 'conferencia/desligar grava SO ativo=false' ($gravado | ConvertTo-Json -Compress)
Assert-Teste ((@(Get-ChildItem -LiteralPath $c.Livro -Filter '*.json')).Count -eq 1) 'conferencia/pacote registrado no livro' ''

# Confirmacao exige tempo: com ConfirmacaoMinDias alto, a 2a rodada ainda so avisa
$ev3 = New-Eventos 'ruim2' $baixas
$c3 = Invoke-Conf 'ruim2' $ev3 @('-Publicar', '-ConfirmacaoMinDias', '30')
Reset-Fake
$r3 = Invoke-Rotina $PacoteValido @('-LivroDir', $c3.Livro, '-HistoricoDir', $hist, '-EventosJson', $ev3, '-HojeConferencia', '2027-03-01', '-Publicar', '-ConfirmacaoMinDias', '30')
Assert-Teste ($c3.R.Code -eq 14 -and $r3.Code -eq 14 -and -not (@(Get-Chamadas) -match 'ews2:flag')) 'conferencia/desligar sem tempo de confirmacao nao liga a flag' ('exit1=' + $c3.R.Code + ' exit2=' + $r3.Code)

# Ponta boa: EWS 2.0 melhor que o EWS atual nos mesmos 6 eventos (emissores 'alta' no pacote, escore atual 0) -> manter
$altas = @($obj.emissores | Where-Object { $_.severidade -eq 'alta' } | Select-Object -First 6)
$evBom = New-Eventos 'bom' $altas
$c = Invoke-Conf 'bom' $evBom @('-Publicar')
Assert-Teste ($c.R.Code -eq 0) 'conferencia/ews2 melhor exit=0' ('exit=' + $c.R.Code + ' ' + $c.R.Resultado)
Assert-Teste (-not (@($c.Ch) -match 'ews2:flag')) 'conferencia/ews2 melhor nao toca a flag' ($c.Ch -join ' || ')

# Amostra pequena (3 eventos, mesmo com o EWS atual ganhando) -> nada a decidir
$evPouco = New-Eventos 'pouco' @($baixas | Select-Object -First 3)
$c = Invoke-Conf 'pouco' $evPouco @('-Publicar')
Assert-Teste ($c.R.Code -eq 0 -and -not (@($c.Ch) -match 'ews2:flag')) 'conferencia/amostra insuficiente exit=0 e flag intocada' ('exit=' + $c.R.Code + ' ' + ($c.Ch -join ' || '))

# Dry-run com veredito desligar: informa e NAO escreve nada
$c = Invoke-Conf 'dry' $evRuim @()
Assert-Teste ($c.R.Code -eq 0 -and $c.Ch.Count -eq 0) 'conferencia/dry-run com veredito desligar nao escreve nada' ('exit=' + $c.R.Code + ' ' + ($c.Ch -join ' || '))

# Guarda final: a flag so foi tocada no cenario do veredito desligar, e so com ativo=false (assert acima)
Write-Output ('RESUMO: {0}/{1} pass, {2} falha(s). Artefatos: {3}' -f ($script:Total - $script:Falhas), $script:Total, $script:Falhas, $Dir)
if ($script:Falhas -gt 0) { exit 1 }
exit 0
