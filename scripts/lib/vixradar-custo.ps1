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
    $cfg = @{ TETO_DIA = 1300000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000; SENTINELA_DIA = 320000 }
    $p = Join-Path $LogDir 'custo-config.json'
    if (Test-Path $p) {
        try {
            $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @('TETO_DIA', 'RESERVA_VERIFICACAO', 'RESERVA_NOTURNO', 'MARGEM_MINIMA', 'SENTINELA_DIA')) {
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

# USODESCONHECIDO-CAST1 (2026-10-10): a varredura publica a STRING 'NAO_MENSURAVEL' em
# tokens_trabalho/input/output/cache_creation/cache_read quando o provedor nao emite usage
# (run_vixradar_varredura.ps1, ramo UsoMensuravel=false - a via fail-closed dela). O
# `[int64]` cru sobre esse valor LANCA RuntimeException ('The input string NAO_MENSURAVEL
# was not in a correct format') e derrubava Get-VixCustoDia / Get-VixCapEfetivo. Como esse
# ramo grava o arquivo do dia, TODA rotina seguinte do mesmo dia morria no boot. Aqui a
# conversao passa a ser defensiva: valor nao numerico NAO vira zero silencioso - marca a
# rotina como nao mensuravel e o circuito trata isso como fail-closed.
function ConvertTo-VixTokenSeguro($valor, [ref]$ok) {
    if ($null -eq $valor) { return [int64]0 }
    if ($valor -is [int64] -or $valor -is [int] -or $valor -is [double] -or $valor -is [decimal]) {
        if ([double]$valor -lt 0) { return [int64]0 }
        return [int64]$valor
    }
    $txt = ('' + $valor).Trim()
    if ($txt -eq '') { return [int64]0 }
    $n = [int64]0
    if ([int64]::TryParse($txt, [ref]$n)) { if ($n -lt 0) { return [int64]0 }; return $n }
    $ok.Value = $false
    return [int64]0
}

function Get-VixParcelas($m) {
    $r = @{ input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0; cache_codex = [int64]0; trabalho = [int64]0; regua = 'ausente'; lotes = 0; emissores = 0; mensuravel = $true }
    if ($null -eq $m) { return $r }
    $ok = $true
    if ($m.PSObject.Properties['tokens_trabalho']) {
        $r.input = ConvertTo-VixTokenSeguro $m.tokens_input ([ref]$ok)
        $r.output = ConvertTo-VixTokenSeguro $m.tokens_output ([ref]$ok)
        $r.cache_creation = ConvertTo-VixTokenSeguro $m.tokens_cache_creation ([ref]$ok)
        $r.cache_read = ConvertTo-VixTokenSeguro $m.tokens_cache_read ([ref]$ok)
        $r.trabalho = ConvertTo-VixTokenSeguro $m.tokens_trabalho ([ref]$ok)
        # CACHECODEX-VISIVEL1 (2026-10-13): parcela propria do cache do Codex, que nao entra em
        # `trabalho` (ele ja esta somado dentro de tokens_input, por desenho do provedor) e por isso
        # nao muda nenhum cap. Existe para o fechamento do dia poder separar trabalho novo de cache.
        if ($m.PSObject.Properties['tokens_cache_codex']) { $r.cache_codex = ConvertTo-VixTokenSeguro $m.tokens_cache_codex ([ref]$ok) }
        $r.regua = 'parcelas'
    } elseif ($m.PSObject.Properties['tokens_total_est']) {
        $r.trabalho = ConvertTo-VixTokenSeguro $m.tokens_total_est ([ref]$ok)
        $r.regua = 'total_legado'
    }
    # Sinal explicito de "nao sei quanto gastei" vindo da propria rotina.
    if ($m.PSObject.Properties['tokens_mensuraveis'] -and ($m.tokens_mensuraveis -eq $false -or ('' + $m.tokens_mensuraveis) -eq 'false')) { $ok = $false }
    if (-not $ok) { $r.mensuravel = $false; $r.regua = 'nao_mensuravel' }
    foreach ($k in @('lotes', 'batches')) { if ($m.PSObject.Properties[$k]) { $r.lotes = [int]$m.$k } }
    foreach ($k in @('analisados', 'submit_ok', 'aprovados', 'atualizados')) {
        if ($m.PSObject.Properties[$k] -and $r.emissores -eq 0) { $r.emissores = [int]$m.$k }
    }
    return $r
}

# Soma tokens= das linhas FIM: da sentinela do dia (ela nao grava metrics json).
# FALHATRANSPORTE-TOKENS1 (2026-10-09): o FIM da sentinela passou a carregar tambem
# `tokens_falha_provider=`, que fica FORA do trabalho do dia. O regex e nao-guloso (.*?) e
# captura o PRIMEIRO `tokens=` depois de "FIM: sentinela" - nunca o de um campo acrescentado
# depois (nem "tokens_falha_provider", que nao contem a substring "tokens=").
function Get-VixTokensSentinela([string]$LogDir, [string]$DateTag, [switch]$IncluirFalha) {
    $sent = [int64]0
    $sl = Join-Path $LogDir ('vixradar-sentinela_' + $DateTag + '.log')
    if (Test-Path $sl) {
        foreach ($l in (Get-Content $sl -Encoding UTF8)) {
            if ($l -match 'FIM: sentinela .*?tokens=(\d+)') { $sent += [int64]$Matches[1] }
            # CUSTOFALHA-TETO1 (2026-10-10): tokens de lote que falhou por provedor/transporte
            # foram consumidos de verdade. Eles entram no CONSUMO do dia (teto), e nao no
            # trabalho entregue. Retry dos emissores e outra decisao, independente desta.
            if ($IncluirFalha -and $l -match 'tokens_falha_provider=(\d+)') { $sent += [int64]$Matches[1] }
        }
    }
    return $sent
}

function Get-VixSentinelaUsoDesconhecido([string]$LogDir, [string]$DateTag) {
    $n = 0
    $sl = Join-Path $LogDir ('vixradar-sentinela_' + $DateTag + '.log')
    if (Test-Path $sl) {
        foreach ($l in (Get-Content $sl -Encoding UTF8)) {
            if ($l -match 'FIM: sentinela .*?uso_desconhecido=(\d+)') { $n += [int]$Matches[1] }
        }
    }
    return $n
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
    $cacheCodex = [int64]0
    $mensuravel = $true
    $naoMensuraveis = @()
    foreach ($r in $rotinas) {
        $mf = Join-Path $LogDir $r.arquivo
        $m = Read-VixMetrics $mf
        # Arquivo AUSENTE = a rotina ainda nao rodou hoje: contribui 0 e e mensuravel.
        # Arquivo PRESENTE e ilegivel = uso desconhecido: fail-closed, nunca zero.
        if ((Test-Path -LiteralPath $mf) -and ($null -eq $m)) { $mensuravel = $false; $naoMensuraveis += ($r.nome + ':ilegivel') }
        $p = Get-VixParcelas $m
        if ($p.mensuravel -eq $false) { $mensuravel = $false; $naoMensuraveis += ($r.nome + ':nao_mensuravel') }
        # Dry-run gasta token de verdade (assinatura) e conta no dia, em arquivo separado da
        # execucao real. DRYRUN-METRICS-SOBRESCREVE1 (02/09): eram um unico
        # <prefixo>_metrics_<data>_dryrun.json e o segundo dry-run do dia apagava o primeiro
        # (o CUSTO_DIA dizia 85k com 120k gastos). Agora cada dry-run tem hora no nome
        # (_dryrun_HHmmss.json) e TODOS os _dryrun*.json do dia sao somados, o legado inclusive.
        $padraoDry = [regex]::Replace($r.arquivo, '\.json$', '_dryrun*.json')
        $nDry = 0
        foreach ($fd in @(Get-ChildItem -Path $LogDir -Filter $padraoDry -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $md = Read-VixMetrics $fd.FullName
            if (-not $md) { $mensuravel = $false; $naoMensuraveis += ($r.nome + ':dryrun_ilegivel'); continue }
            $pd = Get-VixParcelas $md
            if ($pd.mensuravel -eq $false) { $mensuravel = $false; $naoMensuraveis += ($r.nome + ':dryrun_nao_mensuravel') }
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
        # CACHECODEX-VISIVEL1: cache do Codex somado a parte. NAO entra em `$total` - `trabalho` ja
        # o inclui (input do Codex traz o cache dentro), entao somar de novo inflaria o cap.
        if ($p.ContainsKey('cache_codex')) { $cacheCodex += [int64]$p.cache_codex }
    }
    # CUSTOFALHA-TETO1 (2026-10-10): o TETO passa a ser medido pelo CONSUMO, nao so pelo
    # trabalho entregue. A sentinela separa `tokens=` (trabalho) de `tokens_falha_provider=`
    # (lote que falhou por provedor/transporte, 0 emissor analisado). Esse segundo numero
    # e consumo REAL: a assinatura foi cobrada por ele. Contar apenas `tokens=` deixava a
    # sentinela queimar quota em laco de falha sem o circuito do dia enxergar - o oposto do
    # que o CIRCUITOSENTINELA1 pretendia. Retry dos emissores nao depende deste numero.
    $sent = Get-VixTokensSentinela $LogDir $DateTag
    $sentConsumo = Get-VixTokensSentinela -LogDir $LogDir -DateTag $DateTag -IncluirFalha
    # COBERTURA-13OUT1 (2026-10-13): lote da sentinela que ENTREGOU sem usage nao pode somar
    # zero. Ate 13/10 o FIM gravava tokens=0 nesse caso (CAP_USO_DESCONHECIDO) e o circuito
    # liberava o dia como se nada tivesse sido gasto. Agora o FIM declara uso_desconhecido=N e
    # o dia vira NAO_MENSURAVEL (mesma regra FAILCLOSED-CONSUMO1 das outras rotinas).
    if ((Get-VixSentinelaUsoDesconhecido $LogDir $DateTag) -gt 0) { $mensuravel = $false; $naoMensuraveis += 'sentinela:uso_desconhecido' }
    $falhaSentinela = [int64]($sentConsumo - $sent)
    $por['sentinela'] = @{ input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0; trabalho = $sent; consumo = $sentConsumo; regua = 'fim_log'; lotes = 0; emissores = 0 }
    $total += $sent
    $consumo = [int64]($total + $falhaSentinela)
    $margem = [int64]$Config.TETO_DIA - $consumo
    $aberto = ($margem -lt [int64]$Config.MARGEM_MINIMA)
    $partes = @()
    foreach ($k in @('matinal', 'noturno', 'verificacao', 'sentinela', 'agenda')) {
        $partes += ($k + '=' + $por[$k].trabalho + '+cache_read=' + $por[$k].cache_read)
    }
    # Data na linha: o monitor imprime ontem e hoje em sequencia e sem ela as duas eram iguais.
    $linha = 'CUSTO_DIA ' + $DateTag + ': ' + ($partes -join ' ') + ' TOTAL_DIA=' + $total + ' TOTAL_CONSUMO=' + $consumo + ' TETO=' + $Config.TETO_DIA + ' MARGEM=' + $margem
    if ($cacheCodex -gt 0) { $linha += ' CACHE_CODEX=' + $cacheCodex + ' (ja incluido em TOTAL_DIA pela regua do provedor; visibilidade, nao desconto)' }
    if ($falhaSentinela -gt 0) { $linha += ' FALHA_PROVIDER=' + $falhaSentinela }
    if ($aberto) { $linha += ' CIRCUITO_ABERTO' }
    if (-not $mensuravel) { $linha += ' NAO_MENSURAVEL=' + ($naoMensuraveis -join ',') }
    return @{
        data = $DateTag; por_rotina = $por; total_trabalho = $total; total_consumido = $consumo; total_cache_read = $cacheRead
        total_cache_codex = $cacheCodex
        mensuravel = $mensuravel; nao_mensuraveis = $naoMensuraveis
        teto = [int64]$Config.TETO_DIA; margem = $margem; margem_minima = [int64]$Config.MARGEM_MINIMA
        circuito_aberto = $aberto; linha = $linha
    }
}

# Cap efetivo de uma rotina = min(cap proprio, TETO_DIA - gasto do dia - reserva das outras).
function Get-VixCapEfetivo([int64]$CapProprio, $Custo, $Config, [int64]$ReservaOutras) {
    if (-not $Config) { $Config = @{ TETO_DIA = 1300000; RESERVA_VERIFICACAO = 150000; MARGEM_MINIMA = 100000 } }
    # FAILCLOSED-CONSUMO1 (2026-10-10): uso DESCONHECIDO nao libera lote. Se alguma rotina
    # do dia publicou token nao mensuravel (ou o arquivo dela esta ilegivel), nao ha base
    # para dizer que ha orcamento - e o cap vai a zero, nunca para o cap proprio.
    if ($Custo -and $Custo.ContainsKey('mensuravel') -and $Custo.mensuravel -eq $false) { return [int64]0 }
    $gasto = [int64]0
    if ($Custo) {
        if ($Custo.ContainsKey('total_consumido')) { $gasto = [int64]$Custo.total_consumido }
        elseif ($Custo.ContainsKey('total_trabalho')) { $gasto = [int64]$Custo.total_trabalho }
    }
    $disp = [int64]$Config.TETO_DIA - $gasto - $ReservaOutras
    if ($disp -lt 0) { $disp = [int64]0 }
    if ($disp -lt $CapProprio) { return $disp }
    return $CapProprio
}

# ORCAMENTO-13OUT7: cap da ESCALADA FULL = pool proprio somado ao cap da rodada, mas sempre
# limitado pelo mesmo Get-VixCapEfetivo (TETO_DIA - consumo - reserva das outras). O pool nao
# eleva o teto do dia: so deixa de ser engolido pelo cap da rodada barata. Sem pool (0) devolve
# o cap da rodada, comportamento anterior.
function Get-VixCapEscaladaEfetivo([int64]$CapProprio, [int64]$CapEscalada, $Custo, $Config, [int64]$ReservaOutras) {
    if ($CapEscalada -le 0) { return (Get-VixCapEfetivo $CapProprio $Custo $Config $ReservaOutras) }
    return (Get-VixCapEfetivo ($CapProprio + $CapEscalada) $Custo $Config $ReservaOutras)
}

# CIRCUITOSENTINELA1 (2026-10-09): orcamento que sobra para a SENTINELA hoje, preservando
# as reservas das outras rotinas. Formula (unica fonte, testavel isoladamente):
#   disponivel = TETO_DIA - MARGEM_MINIMA - (RESERVA_NOTURNO + RESERVA_VERIFICACAO)
#                - gasto_das_outras_rotinas_hoje - gasto_da_sentinela_hoje
# Devolve 0 (nunca negativo) quando nao ha espaco - o chamador entao nao dispara lote.
# Sem isto, a sentinela consumia o orcamento do dia sem ser limitada por ele (ela so tinha
# o cap por execucao) e, em 09/10/2026, 10.558.736 tokens dela abriram o circuito e
# deferiram as 104 analises da noturna e as 22 da matinal.
function Get-VixDisponivelSentinela($Custo, $Config) {
    if (-not $Config) { $Config = @{ TETO_DIA = 1300000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000 } }
    # FAILCLOSED-CONSUMO1: uso desconhecido no dia fecha a sentinela (0), nunca a libera.
    if ($Custo -and $Custo.ContainsKey('mensuravel') -and $Custo.mensuravel -eq $false) { return [int64]0 }
    $gastoSentinela = [int64]0
    $gastoOutras = [int64]0
    if ($Custo) {
        if ($Custo.ContainsKey('total_consumido')) { $gastoOutras = [int64]$Custo.total_consumido }
        elseif ($Custo.ContainsKey('total_trabalho')) { $gastoOutras = [int64]$Custo.total_trabalho }
        if ($Custo.ContainsKey('por_rotina') -and $Custo.por_rotina.ContainsKey('sentinela')) {
            $s = $Custo.por_rotina['sentinela']
            if ($s.ContainsKey('consumo')) { $gastoSentinela = [int64]$s.consumo } else { $gastoSentinela = [int64]$s.trabalho }
            $gastoOutras = $gastoOutras - $gastoSentinela
        }
    }
    $reserva = [int64]$Config.RESERVA_NOTURNO + [int64]$Config.RESERVA_VERIFICACAO
    $disp = [int64]$Config.TETO_DIA - [int64]$Config.MARGEM_MINIMA - $reserva - $gastoOutras - $gastoSentinela
    # ORCAMENTO-13OUT7: limite diario PROPRIO da sentinela (SENTINELA_DIA), dentro do TETO_DIA e
    # sem eleva-lo. Medido: 1 emissor custa 147k a 156k, entao 320k = 2 emissores/dia. Sem este
    # limite a sentinela so era contida pela sobra do dia e consumia a folga da escalada FULL.
    if ($Config.ContainsKey('SENTINELA_DIA') -and [int64]$Config.SENTINELA_DIA -gt 0) {
        $restoProprio = [int64]$Config.SENTINELA_DIA - $gastoSentinela
        if ($restoProprio -lt $disp) { $disp = $restoProprio }
    }
    if ($disp -lt 0) { return [int64]0 }
    return $disp
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
