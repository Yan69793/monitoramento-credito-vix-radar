# test-falhatransporte-teto.ps1 - P0 custo de falha vs elegibilidade de retry.
#
# PROVA (offline, deterministica, ZERO chamada paga):
#   (A) consumo de lote que falhou por provedor/transporte ENTRA no teto do dia;
#   (B) uso DESCONHECIDO (sem usage do provedor, ou metrics ilegivel) fecha o cap:
#       fail-closed, nunca cap proprio nem zero silencioso;
#   (C) as reservas das outras rotinas continuam preservadas (concorrencia);
#   (D) contrato antigo de Get-VixTokensSentinela (sem -IncluirFalha) preservado.
#
# NAO confunde as duas coisas: contabilizacao de CUSTO (teto) e elegibilidade para RETRY
# sao eixos independentes. Um lote falho consome quota e por isso conta no teto, mas os
# emissores dele continuam no backlog e voltam na proxima janela.
#
# PowerShell 5.1 e 7.

$ErrorActionPreference = 'Stop'
$script:ok = 0
$script:falhas = @()

function Assert($cond, [string]$nome) {
    if ($cond) { $script:ok++; Write-Host ('OK   ' + $nome) -ForegroundColor Green }
    else { $script:falhas += $nome; Write-Host ('FALHA ' + $nome) -ForegroundColor Red }
}

$lib = Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1'
Assert (Test-Path -LiteralPath $lib) 'lib\vixradar-custo.ps1 presente'
. $lib

$tmp = Join-Path $env:TEMP ('vixtetofalha_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$tag = '20261010'
$cfg = @{ TETO_DIA = 1300000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000 }

try {
    # =====================================================================
    # A. consumo de falha de provedor entra no teto
    # =====================================================================
    Write-Host ''
    Write-Host '=== A: consumo de lote falho entra no teto do dia ===' -ForegroundColor Cyan
    # Cenario real de 09/10: 1 lote OK com 1.000 tokens e 1 lote FALLO_PROVEEDOR com 900.000.
    @(
        '2026-10-10 09:25:00 LOTE sonnet-1: 4 emissores, modelo claude-sonnet-4-6',
        '2026-10-10 09:26:00 ERRO: lote sonnet-1 falhou por provedor/transporte (codex exit=1) - 4 emissores preservados no backlog.',
        '2026-10-10 09:27:00 FIM: sentinela resultado=FALLO_PROVEEDOR. tokens=1000 analisados=0 submit_fail=0 deferidos=0 sem_resultado=4 excedente_worker=0 buscas=0 backlog=True lotes_ok=0 lotes_falha_provider=1 tokens_falha_provider=900000'
    ) | Set-Content -LiteralPath (Join-Path $tmp ('vixradar-sentinela_' + $tag + '.log')) -Encoding UTF8

    $sTrab = Get-VixTokensSentinela -LogDir $tmp -DateTag $tag
    $sCons = Get-VixTokensSentinela -LogDir $tmp -DateTag $tag -IncluirFalha
    Assert ($sTrab -eq 1000) ('A1: tokens= do FIM continua sendo o TRABALHO (' + $sTrab + ')')
    Assert ($sCons -eq 901000) ('A2: consumo soma tokens= + tokens_falha_provider= (' + $sCons + ')')

    $c = Get-VixCustoDia -LogDir $tmp -DateTag $tag -Config $cfg
    Assert ($c.total_trabalho -eq 1000) ('A3: total_trabalho = 1000 (' + $c.total_trabalho + ')')
    Assert ($c.total_consumido -eq 901000) ('A4: total_consumido = 901000 (' + $c.total_consumido + ')')
    Assert ($c.total_consumido -gt $c.total_trabalho) 'A5: consumo > trabalho (o teto usa o consumo)'
    Assert ($c.mensuravel -eq $true) 'A6: metricas presentes e numericas = mensuravel'
    # A margem tem de refletir os 901k CONSUMIDOS. Antes da correcao ela diria 1.299.000
    # (so os 1.000 de trabalho), ou seja, 900k de quota queimada invisiveis ao circuito.
    Assert ($c.margem -eq 399000) ('A7: margem = TETO - CONSUMO = 399.000 (' + $c.margem + ')')
    Assert ($c.total_consumido -eq 901000 -and $c.margem -lt ($cfg.TETO_DIA - $c.total_trabalho)) 'A7b: o consumo de falha moveu a margem'

    # A8/A9: o teto e' o que limita - 901k consumidos derrubam o cap da sentinela.
    $dispSent = Get-VixDisponivelSentinela -Custo $c -Config $cfg
    Assert ($dispSent -eq 0) ('A8: sem orcamento para a sentinela apos 901k consumidos (' + $dispSent + ')')
    $capMatinal = Get-VixCapEfetivo -CapProprio 400000 -Custo $c -Config $cfg -ReservaOutras 850000
    Assert ($capMatinal -eq 0) ('A9: cap efetivo da matinal vai a 0 (' + $capMatinal + ')')

    # A10: retry e custo sao eixos separados - o backlog do lote falho continua intacto.
    Assert ($sTrab -eq 1000 -and $sCons -eq 901000) 'A10: custo contado sem inflar o trabalho entregue (retry intacto)'

    # =====================================================================
    # B. uso DESCONHECIDO -> fail-closed
    # =====================================================================
    Write-Host ''
    Write-Host '=== B: uso desconhecido fecha o cap (fail-closed) ===' -ForegroundColor Cyan
    $tmpB = Join-Path $tmp 'b'
    New-Item -ItemType Directory -Force -Path $tmpB | Out-Null
    # Exatamente o que run_vixradar_varredura.ps1 grava quando o codex nao emite usage.
    @'
{"data":"20261010","rotina":"matinal","tokens_mensuraveis":false,"tokens_total_est":"NAO_MENSURAVEL","tokens_trabalho":"NAO_MENSURAVEL","tokens_input":"NAO_MENSURAVEL","tokens_output":"NAO_MENSURAVEL","tokens_cache_creation":"NAO_MENSURAVEL","tokens_cache_read":"NAO_MENSURAVEL","analisados":0,"deferred":22}
'@ | Set-Content -LiteralPath (Join-Path $tmpB ('matinal_metrics_' + $tag + '.json')) -Encoding UTF8

    $lancou = $false
    $cB = $null
    try { $cB = Get-VixCustoDia -LogDir $tmpB -DateTag $tag -Config $cfg } catch { $lancou = $true; Write-Host ('  excecao: ' + $_.Exception.Message) -ForegroundColor Red }
    Assert (-not $lancou) 'B1: NAO_MENSURAVEL nao derruba mais a regua do dia (era RuntimeException)'
    Assert ($null -ne $cB -and $cB.mensuravel -eq $false) 'B2: dia com uso desconhecido e marcado mensuravel=false'
    Assert ($cB.total_consumido -eq 0) ('B3: valor desconhecido NAO vira zero silencioso na conta (' + $cB.total_consumido + ')')
    Assert ($cB.linha -match 'NAO_MENSURAVEL=matinal') 'B4: a linha CUSTO_DIA expoe a rotina nao mensuravel'

    $capB = Get-VixCapEfetivo -CapProprio 400000 -Custo $cB -Config $cfg -ReservaOutras 850000
    $dispB = Get-VixDisponivelSentinela -Custo $cB -Config $cfg
    Assert ($capB -eq 0) ('B5: cap efetivo = 0 com uso desconhecido, nunca o cap proprio (' + $capB + ')')
    Assert ($dispB -eq 0) ('B6: sentinela = 0 com uso desconhecido (' + $dispB + ')')

    # B7: arquivo ILEGIVEL tambem e' desconhecido (nao zero).
    $tmpB2 = Join-Path $tmp 'b2'
    New-Item -ItemType Directory -Force -Path $tmpB2 | Out-Null
    Set-Content -LiteralPath (Join-Path $tmpB2 ('noturno_metrics_' + $tag + '.json')) -Value '{ isso nao e json' -Encoding UTF8
    $cB2 = Get-VixCustoDia -LogDir $tmpB2 -DateTag $tag -Config $cfg
    Assert ($cB2.mensuravel -eq $false) 'B7: metrics ilegivel = uso desconhecido (fail-closed)'
    Assert ((Get-VixCapEfetivo -CapProprio 400000 -Custo $cB2 -Config $cfg -ReservaOutras 850000) -eq 0) 'B8: cap = 0 com metrics ilegivel'

    # B9: arquivo AUSENTE = rotina ainda nao rodou = 0 legitimo, e' mensuravel.
    $tmpB3 = Join-Path $tmp 'b3'
    New-Item -ItemType Directory -Force -Path $tmpB3 | Out-Null
    $cB3 = Get-VixCustoDia -LogDir $tmpB3 -DateTag $tag -Config $cfg
    Assert ($cB3.mensuravel -eq $true) 'B9: dia vazio segue mensuravel (rotina que nao rodou nao e desconhecida)'
    Assert ((Get-VixCapEfetivo -CapProprio 400000 -Custo $cB3 -Config $cfg -ReservaOutras 850000) -eq 400000) 'B10: dia vazio libera o cap proprio'

    # =====================================================================
    # C. reserva das outras rotinas (concorrencia no mesmo dia)
    # =====================================================================
    Write-Host ''
    Write-Host '=== C: reserva preservada entre rotinas ===' -ForegroundColor Cyan
    $tmpC = Join-Path $tmp 'c'
    New-Item -ItemType Directory -Force -Path $tmpC | Out-Null
    Assert ((Get-VixDisponivelSentinela -Custo $cB3 -Config $cfg) -eq 350000) 'C1: dia limpo -> 350k para a sentinela'
    @'
{"data":"20261010","rotina":"noturno","tokens_trabalho":700000,"tokens_input":700000,"tokens_output":0,"tokens_cache_creation":0,"tokens_cache_read":0,"analisados":104}
'@ | Set-Content -LiteralPath (Join-Path $tmpC ('noturno_metrics_' + $tag + '.json')) -Encoding UTF8
    $cC = Get-VixCustoDia -LogDir $tmpC -DateTag $tag -Config $cfg
    Assert ((Get-VixDisponivelSentinela -Custo $cC -Config $cfg) -eq 0) 'C2: noturna gastou 700k -> sentinela fica em 0, sem paralisa-la'

    # =====================================================================
    # D. contrato antigo preservado + guarda nova na sentinela
    # =====================================================================
    Write-Host ''
    Write-Host '=== D: compatibilidade e guardas no fonte ===' -ForegroundColor Cyan
    Assert ((Get-VixTokensSentinela -LogDir $tmp -DateTag $tag) -eq 1000) 'D1: sem -IncluirFalha o retorno e o de antes (compatibilidade)'

    $srcSent = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_vixradar_sentinela.ps1') -Raw -Encoding UTF8
    Assert ($srcSent -match 'usoDesconhecido') 'D2: a sentinela tem a bandeira de uso desconhecido'
    Assert ($srcSent -match 'CAP_USO_DESCONHECIDO') 'D3: existe o caminho de deferimento por uso desconhecido'
    Assert ($srcSent -match 'tokens_falha_provider=') 'D4: o FIM publica tokens_falha_provider (consumo visivel)'

    $srcVar = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
    Assert ($srcVar -match 'UsoMensuravel') 'D5: a varredura continua fail-closed em UsoMensuravel (referencia)'

    $libSrc = Get-Content -LiteralPath $lib -Raw -Encoding UTF8
    Assert ($libSrc -match 'total_consumido') 'D6: a regua expoe total_consumido'
    Assert ($libSrc -match 'ConvertTo-VixTokenSeguro') 'D7: a regua converte token de forma defensiva'
    Assert ($libSrc -match 'FAILCLOSED-CONSUMO1') 'D8: os dois gates tem o fail-closed por uso desconhecido'
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:falhas.Count) + ' asserts OK, ' + $script:falhas.Count + ' falha(s)')
if ($script:falhas.Count -gt 0) {
    foreach ($f in $script:falhas) { Write-Host ('  - ' + $f) -ForegroundColor Red }
    exit 1
}
exit 0
