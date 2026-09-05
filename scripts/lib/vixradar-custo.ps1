# vixradar-custo.ps1 - regua unica de tokens e circuito de custo por dia.
# PowerShell 5.1, ASCII puro, dot-source: . "$PSScriptRoot\lib\vixradar-custo.ps1"
#
# REGUA-UNICA1 (2026-09-02). Tres reguas conviveram para a mesma classe de trabalho
# e davam numeros 2 a 3x diferentes: subagent_tokens da sessao do Claude Desktop
# (composicao desconhecida), usage do claude -p COM cache_read (verificacao, agenda)
# e usage SEM cache_read (noturna, sentinela). Aqui vale uma so:
#   trabalho = input + output + cache_creation      (o que e trabalho novo)
#   cache_read fica em coluna propria                (releitura cobrada a 0,1x)
# Os *_metrics_<data>.json dos runners gravam as 4 parcelas (tokens_input,
# tokens_output, tokens_cache_creation, tokens_cache_read, tokens_trabalho) e a lista
# lotes_detalhe. Arquivo legado so com tokens_total_est entra como trabalho na coluna
# "regua=total_legado", sem parcelas.
#
# Circuito do dia: TETO_DIA (default 1.300.000), RESERVA_VERIFICACAO (150.000) e
# MARGEM_MINIMA (100.000) vivem em logs\routines\custo-config.json, editavel sem tocar
# em script. O Worker nao contabiliza token local (registrarCustoAnalise so cobre o que
# o proprio Worker chama), entao este circuito e local e por arquivo.

function Get-VixCustoConfig([string]$LogDir) {
    $cfg = @{ TETO_DIA = 1300000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000 }
    $p = Join-Path $LogDir 'custo-config.json'
    if (Test-Path $p) {
        try {
            $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @('TETO_DIA', 'RESERVA_VERIFICACAO', 'RESERVA_NOTURNO', 'MARGEM_MINIMA')) {
                if ($j.PSObject.Properties[$k]) { $cfg[$k] = [int64]$j.$k }
            }
        } catch {
            Write-Host ('AVISO: custo-config.json ilegivel, usando defaults: ' + $_.Exception.Message)
        }
    }
    return $cfg
}

function Read-VixMetrics([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    try { return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-VixParcelas($m) {
    $r = @{ input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0; trabalho = [int64]0; regua = 'ausente'; lotes = 0; emissores = 0 }
    if ($null -eq $m) { return $r }
    if ($m.PSObject.Properties['tokens_trabalho']) {
        $r.input = [int64]$m.tokens_input
        $r.output = [int64]$m.tokens_output
        $r.cache_creation = [int64]$m.tokens_cache_creation
        $r.cache_read = [int64]$m.tokens_cache_read
        $r.trabalho = [int64]$m.tokens_trabalho
        $r.regua = 'parcelas'
    } elseif ($m.PSObject.Properties['tokens_total_est']) {
        $r.trabalho = [int64]$m.tokens_total_est
        $r.regua = 'total_legado'
    }
    foreach ($k in @('lotes', 'batches')) { if ($m.PSObject.Properties[$k]) { $r.lotes = [int]$m.$k } }
    foreach ($k in @('analisados', 'submit_ok', 'aprovados', 'atualizados')) {
        if ($m.PSObject.Properties[$k] -and $r.emissores -eq 0) { $r.emissores = [int]$m.$k }
    }
    return $r
}

# Soma tokens= das linhas FIM: da sentinela do dia (ela nao grava metrics json).
function Get-VixTokensSentinela([string]$LogDir, [string]$DateTag) {
    $sent = [int64]0
    $sl = Join-Path $LogDir ('vixradar-sentinela_' + $DateTag + '.log')
    if (Test-Path $sl) {
        foreach ($l in (Get-Content $sl -Encoding UTF8)) {
            if ($l -match 'FIM: sentinela .*tokens=(\d+)') { $sent += [int64]$Matches[1] }
        }
    }
    return $sent
}

function Get-VixCustoDia([string]$LogDir, [string]$DateTag, $Config) {
    if (-not $Config) { $Config = Get-VixCustoConfig $LogDir }
    $rotinas = @(
        @{ nome = 'matinal'; arquivo = ('matinal_metrics_' + $DateTag + '.json') },
        @{ nome = 'noturno'; arquivo = ('noturno_metrics_' + $DateTag + '.json') },
        @{ nome = 'verificacao'; arquivo = ('verificacao_async_metrics_' + $DateTag + '.json') },
        @{ nome = 'agenda'; arquivo = ('agenda-semanal_metrics_' + $DateTag + '.json') }
    )
    $por = @{}
    $total = [int64]0
    $cacheRead = [int64]0
    foreach ($r in $rotinas) {
        $m = Read-VixMetrics (Join-Path $LogDir $r.arquivo)
        $p = Get-VixParcelas $m
        # Dry-run gasta token de verdade (assinatura) e conta no dia, em arquivo separado da
        # execucao real. DRYRUN-METRICS-SOBRESCREVE1 (02/09): eram um unico
        # <prefixo>_metrics_<data>_dryrun.json e o segundo dry-run do dia apagava o primeiro
        # (o CUSTO_DIA dizia 85k com 120k gastos). Agora cada dry-run tem hora no nome
        # (_dryrun_HHmmss.json) e TODOS os _dryrun*.json do dia sao somados, o legado inclusive.
        $padraoDry = [regex]::Replace($r.arquivo, '\.json$', '_dryrun*.json')
        $nDry = 0
        foreach ($fd in @(Get-ChildItem -Path $LogDir -Filter $padraoDry -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $md = Read-VixMetrics $fd.FullName
            if (-not $md) { continue }
            $pd = Get-VixParcelas $md
            foreach ($k in @('input', 'output', 'cache_creation', 'cache_read', 'trabalho')) { $p[$k] = [int64]$p[$k] + [int64]$pd[$k] }
            $p.lotes = [int]$p.lotes + [int]$pd.lotes
            $nDry++
        }
        if ($nDry -gt 0) {
            if ($p.regua -eq 'ausente') { $p.regua = 'parcelas+dryrun' } elseif ($p.regua -notmatch '\+dryrun') { $p.regua = $p.regua + '+dryrun' }
            if ($nDry -gt 1) { $p.regua = $p.regua + 'x' + $nDry }
        }
        $por[$r.nome] = $p
        $total += $p.trabalho
        $cacheRead += $p.cache_read
    }
    $sent = Get-VixTokensSentinela $LogDir $DateTag
    $por['sentinela'] = @{ input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0; trabalho = $sent; regua = 'fim_log'; lotes = 0; emissores = 0 }
    $total += $sent
    $margem = [int64]$Config.TETO_DIA - $total
    $aberto = ($margem -lt [int64]$Config.MARGEM_MINIMA)
    $partes = @()
    foreach ($k in @('matinal', 'noturno', 'verificacao', 'sentinela', 'agenda')) {
        $partes += ($k + '=' + $por[$k].trabalho + '+cache_read=' + $por[$k].cache_read)
    }
    # Data na linha: o monitor imprime ontem e hoje em sequencia e sem ela as duas eram iguais.
    $linha = 'CUSTO_DIA ' + $DateTag + ': ' + ($partes -join ' ') + ' TOTAL_DIA=' + $total + ' TETO=' + $Config.TETO_DIA + ' MARGEM=' + $margem
    if ($aberto) { $linha += ' CIRCUITO_ABERTO' }
    return @{
        data = $DateTag; por_rotina = $por; total_trabalho = $total; total_cache_read = $cacheRead
        teto = [int64]$Config.TETO_DIA; margem = $margem; margem_minima = [int64]$Config.MARGEM_MINIMA
        circuito_aberto = $aberto; linha = $linha
    }
}

# Cap efetivo de uma rotina = min(cap proprio, TETO_DIA - gasto do dia - reserva das outras).
function Get-VixCapEfetivo([int64]$CapProprio, $Custo, $Config, [int64]$ReservaOutras) {
    if (-not $Config) { $Config = @{ TETO_DIA = 1300000; RESERVA_VERIFICACAO = 150000; MARGEM_MINIMA = 100000 } }
    $gasto = [int64]0
    if ($Custo -and $Custo.ContainsKey('total_trabalho')) { $gasto = [int64]$Custo.total_trabalho }
    $disp = [int64]$Config.TETO_DIA - $gasto - $ReservaOutras
    if ($disp -lt 0) { $disp = [int64]0 }
    if ($disp -lt $CapProprio) { return $disp }
    return $CapProprio
}

# Extrai as 4 parcelas do envelope usage do claude -p (--output-format json).
function Get-VixUsageParcelas($json) {
    $r = @{ input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0; trabalho = [int64]0 }
    if ($null -eq $json -or -not $json.usage) { return $r }
    $u = $json.usage
    if ($u.input_tokens) { $r.input = [int64]$u.input_tokens }
    if ($u.output_tokens) { $r.output = [int64]$u.output_tokens }
    if ($u.cache_creation_input_tokens) { $r.cache_creation = [int64]$u.cache_creation_input_tokens }
    if ($u.cache_read_input_tokens) { $r.cache_read = [int64]$u.cache_read_input_tokens }
    $r.trabalho = $r.input + $r.output + $r.cache_creation
    return $r
}
