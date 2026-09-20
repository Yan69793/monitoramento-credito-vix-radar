# vixradar-profundidade.ps1 - PROFUNDIDADE-NOTURNA1: selecao adaptativa de tier da noturna.
# PowerShell 5.1, ASCII puro, dot-source: . "$PSScriptRoot\lib\vixradar-profundidade.ps1"
#
# O PROBLEMA, medido em 19/09. O plano do Worker pede de 42 a 84 FULL e ate 5 AUDIT por
# noite. O executor achatava tudo para o tier do perfil (LIGHT) e nunca lia `rodadas` do
# plano, entao a carteira inteira recebia profundidade LIGHT e o plano FULL era decorativo.
# A fila aprofundada em Sonnet da noturna foi removida pelo MOTOR1 em 02/09 e a
# documentacao continuou descrevendo duas filas.
#
# O DESENHO (CENARIO C ADAPTATIVO, decidido pelo operador).
# Por noite util, e nao por tier do plano:
#   1. quantos emissores ainda nao receberam nenhum FULL nesta semana;
#   2. quantas noites uteis restam, incluindo a de hoje;
#   3. o minimo de FULL desta noite para ainda fechar 104/104 na sexta: ceil(faltam / noites);
#   4. a sobra do cap vai para LIGHT, reduzindo o maior gap primeiro.
# FULL e otimo por escassez: a carteira nao cabe com profundidade FULL no orcamento, entao
# a rotacao semanal e deliberada e o LIGHT preenche a lacuna. Nao existe scoring paralelo:
# a ordem usa horas_desde_analise e ews_score, que ja vem no plano.
#
# O QUE ESTA LIB NAO FAZ. Ela nao chama o Worker, nao grava log e nao monta prompt. Ela e
# pura de proposito, para o teste poder rodar cinco noites offline e provar o fechamento
# semanal sem tocar em rotina real.

# Normalizacao de nome de emissor. O motor ja tem a sua (run_vixradar_varredura.ps1, linha
# 623) com esta mesma semantica: remove acento e apara. A copia aqui existe so para a lib
# ficar autossuficiente quando um teste a carrega sozinha, sem o motor. Carregada dentro do
# motor, a definicao identica de la reassume e nao ha divergencia possivel.
if (-not (Get-Command Get-NomeNormalizado -ErrorAction SilentlyContinue)) {
    function Get-NomeNormalizado([string]$s) {
        $norm = $s.Normalize([Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $norm.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
        }
        return $sb.ToString().Trim()
    }
}

# Chave da semana = a data da segunda-feira, em yyyyMMdd. Evita a borda de ano da semana
# ISO e e legivel no nome do arquivo de ledger.
function Get-VixSegundaDaSemana([datetime]$Quando) {
    $d = $Quando.Date
    # DayOfWeek: Sunday=0 ... Saturday=6. Segunda=1.
    $offset = ([int]$d.DayOfWeek - 1)
    if ($offset -lt 0) { $offset = 6 }
    return $d.AddDays(-1 * $offset)
}

function Get-VixSemanaChave([datetime]$Quando) {
    return (Get-VixSegundaDaSemana $Quando).ToString('yyyyMMdd')
}

# D3 do P0 PROFUNDIDADE-NOTURNA1: estimativa de custo por tier num lugar so.
#
# ESTIMATIVA CONSERVADORA, NAO CUSTO MEDIDO. O numero do FULL e a media observada
# dos slots FULL da MATINAL em 13 a 19/09, com Sonnet em lotes de 4. Ele NAO foi medido no lote
# noturno novo, que usa chunk 16, e lote maior amortiza o boot por emissor. Ou seja, o numero
# da matinal provavelmente SUPERESTIMA o custo por emissor da noturna, e superestimar aqui e o
# lado seguro do erro: reserva cap a mais, nunca a menos. O numero do LIGHT (6023.82) vem da
# fila chamada `light` do mesmo periodo, que misturava LIGHT, FULL e AUDIT no mesmo balde.
#
# Os dois numeros governam APENAS a reserva pre-lote e a escolha de quantos emissores entram
# por noite. Quanto o sistema pode gastar de verdade continua sendo medido por token real em
# lib\vixradar-custo.ps1 (Get-VixCustoDia, Get-VixCapEfetivo) e limitado pelo hard cap. Trocar
# o numero aqui muda quantos emissores a noite cobre, nunca o teto de gasto.
function Get-VixCustoEstimadoTier {
    param([string]$Tier = 'LIGHT')
    $t = ('' + $Tier).Trim().ToUpperInvariant()
    if ($t -eq 'FULL' -or $t -eq 'AUDIT') {
        return [pscustomobject]@{
            Tier      = $t
            Custo     = [double]31068.75
            Rotulo    = 'ESTIMATIVA_CONSERVADORA'
            Medido    = $false
            Origem    = 'media dos slots FULL da matinal (Sonnet, chunk 4), 13-19/09/2026'
            Ressenha  = 'nao e custo medido do lote noturno (chunk 16); superestima de proposito'
        }
    }
    return [pscustomobject]@{
        Tier      = $t
        Custo     = [double]6023.82
        Rotulo    = 'ESTIMATIVA_CONSERVADORA'
        Medido    = $false
        Origem    = 'fila light observada 13-19/09/2026 (balde misto LIGHT+FULL+AUDIT)'
        Ressenha  = 'balde misto; nao isola o custo real do tier LIGHT'
    }
}

# Noites uteis que ainda restam nesta semana, contando hoje quando hoje e dia util.
# Sabado e domingo devolvem 0: nao ha noite util para fechar a semana.
function Get-VixDiasUteisRestantes([datetime]$Quando) {
    $d = $Quando.Date
    $dw = [int]$d.DayOfWeek
    if ($dw -eq 0 -or $dw -eq 6) { return 0 }
    # Sexta=5. Restam (5 - dw + 1) dias.
    return (6 - $dw)
}

# Quantas horas se passaram desde a segunda-feira 00:00 da semana do $Quando.
# Usado so como fallback de leitura do plano, quando o ledger da semana nao existe ainda.
function Get-VixHorasDesdeSegunda([datetime]$Quando) {
    $seg = Get-VixSegundaDaSemana $Quando
    return ($Quando - $seg).TotalHours
}

function Get-VixFullSemanaArquivo([string]$LogDir, [string]$Semana) {
    return (Join-Path $LogDir ('full_semana_' + $Semana + '.json'))
}

# Le o ledger de FULL da semana. Devolve hashtable nomeNormalizado -> 'yyyy-MM-dd'.
# Arquivo ausente ou ilegivel devolve tabela vazia: a selecao volta a decidir pelo plano,
# que e fail-open de leitura e nunca derruba a rotina por ledger faltando.
function Get-VixFullSemana([string]$LogDir, [string]$Semana) {
    $map = @{}
    $p = Get-VixFullSemanaArquivo $LogDir $Semana
    if (-not (Test-Path $p)) { return $map }
    try {
        $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($j -and $j.emissores) {
            foreach ($prop in $j.emissores.PSObject.Properties) {
                $map[[string]$prop.Name] = [string]$prop.Value
            }
        }
    } catch {
        Write-Host ('AVISO: ledger de FULL da semana ilegivel em ' + $p + ' - seguindo so com o plano')
    }
    return $map
}

function Save-VixFullSemana([string]$LogDir, [string]$Semana, $Map) {
    $obj = [ordered]@{ semana = $Semana; atualizado_em = (Get-Date).ToString('s'); emissores = [ordered]@{} }
    foreach ($k in ($Map.Keys | Sort-Object)) { $obj.emissores[$k] = $Map[$k] }
    $p = Get-VixFullSemanaArquivo $LogDir $Semana
    ($obj | ConvertTo-Json -Depth 4 -Compress) | Set-Content $p -Encoding UTF8
    return $p
}

# Uniao, nunca soma, de emissores com FULL confirmado. A fonte de producao e o ledger
# OK|...|FULL|...|true|ANALISADO das rotinas, nao ultimo_tier do plano. O plano so mostra o
# ultimo estado e perde um FULL que tenha sido seguido por LIGHT.
function Merge-VixFullSemana {
    param(
        [hashtable]$FullSemana = @{},
        [object[]]$EmissoresFull = @(),
        [datetime]$Data = (Get-Date)
    )
    $out = @{}
    foreach ($k in $FullSemana.Keys) { $out[[string]$k] = [string]$FullSemana[$k] }
    foreach ($e in $EmissoresFull) {
        $bruto = if ($e -is [string]) { [string]$e } elseif ($null -ne $e.empresa) { [string]$e.empresa } else { '' }
        if (-not $bruto) { continue }
        $nome = Get-NomeNormalizado $bruto
        if (-not $nome) { continue }
        if (-not $out.ContainsKey($nome)) { $out[$nome] = $Data.ToString('yyyy-MM-dd') }
    }
    return $out
}

# Le apenas FULL efetivamente aceito pelo Worker. DRYRUN, submit false, SKIP e DEFERIDO nao
# contam como credito semanal. O retorno e uma lista para que a uniao seja feita pelo chamador.
function Get-VixFullConfirmadosDoLedger([string]$LogDir, [string]$Rotina, [datetime]$Data) {
    $out = @()
    $tag = $Data.ToString('yyyyMMdd')
    $p = Join-Path $LogDir ('vixradar-' + $Rotina + '_' + $tag + '.log')
    if (-not (Test-Path -LiteralPath $p)) { return ,$out }
    foreach ($linha in @(Get-Content -LiteralPath $p -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($linha -match '^[\d-]+\s+[\d:]+\s+OK\|([^|]+)\|FULL\|[^|]*\|[^|]*\|true\|ANALISADO\|') {
            $out += [string]$Matches[1]
        }
    }
    return ,$out
}

# Estado semanal e reconstruido dos ledgers reais de matinal e noturno. Isso permite iniciar
# no meio da semana e preserva a uniao mesmo se o ultimo_tier do plano ja tiver virado LIGHT.
function Get-VixFullSemanaDosLedgers([string]$LogDir, [datetime]$Quando, [datetime]$Ate = [datetime]::MinValue) {
    $out = @{}
    if ($Ate -eq [datetime]::MinValue) { $Ate = $Quando }
    $dia = Get-VixSegundaDaSemana $Quando
    while ($dia.Date -le $Ate.Date) {
        foreach ($rotina in @('matinal', 'noturno')) {
            $fullDoDia = Get-VixFullConfirmadosDoLedger $LogDir $rotina $dia
            $out = Merge-VixFullSemana -FullSemana $out -EmissoresFull $fullDoDia -Data $dia
        }
        $dia = $dia.AddDays(1)
    }
    return $out
}

# Ordem de prioridade para FULL. Nao e score novo: e ordenacao pelos dois campos que ja
# existem no plano. Quem nao tem registro de analise vai na frente (horas nulas viram 9999),
# depois quem esta sem analise ha mais tempo, e o EWS desempata. O nome fecha a ordem para
# a selecao ser deterministica entre execucoes e reproduzivel no teste.
function Get-VixOrdemFull($Emissores) {
    $ord = @($Emissores | Sort-Object `
        @{ Expression = { if ($_.vix_recheck_pendente) { [int]1 } else { [int]0 } }; Descending = $true }, `
        @{ Expression = { $h = $_.horas_desde_analise; if ($null -eq $h) { [double]9999 } else { [double]$h } }; Descending = $true }, `
        @{ Expression = { if ($null -eq $_.ews_score) { [double]0 } else { [double]$_.ews_score } }; Descending = $true }, `
        @{ Expression = { [string]$_.empresa }; Descending = $false })
    return ,$ord
}

function Get-VixOrdemLight($Emissores) {
    # Mesma regua da ordem FULL: gap maior primeiro, EWS desempatando, nome fechando.
    # `gap_web_dias` NAO tem campo de origem no plano: nao existe data de ultima cobertura
    # com busca web. O gap aqui e o de horas_desde_analise, e o relatorio declara isso.
    return ,(Get-VixOrdemFull $Emissores)
}

<#
.SYNOPSIS
Selecao adaptativa de tier da noturna. Pura: mesma entrada devolve sempre a mesma saida.

.DESCRIPTION
Devolve @{ Full = @(emissores); Light = @(emissores); Meta = @{...} }.

Regras, na ordem:
  1. faltam = BaseCarteira - (quantos ja tem FULL nesta semana). Nunca negativo.
  2. minFull = ceil(faltam / noites restantes). Com noites = 0 nao ha o que garantir.
  3. FULL desta noite = min(minFull, quantos o cap paga, quantos candidatos existem).
     Nao passa de minFull de proposito: sobra vai para LIGHT, nao para FULL extra.
  4. restante = cap - (FULL x custoFULL), nunca negativo.
  5. LIGHT desta noite = min(quantos o restante paga, candidatos restantes).

Candidato a FULL e quem nao tem FULL nesta semana. Candidato a LIGHT e quem sobrou, na
mesma ordem de gap. Quem o plano ja marcou SKIP (inclusive credito de analise do dia,
CREDITODIA1) nao entra: e o que impede o noturno de repetir a matinal do mesmo dia.
#>
function Select-VixProfundidadeNoturna {
    param(
        [object[]]$Emissores = @(),
        [hashtable]$FullSemana = @{},
        [hashtable]$CobertosHoje = @{},
        [int]$BaseCarteira = 104,
        [int]$NoitesRestantes = 1,
        [int64]$CapEfetivo = 0,
        # D3: sem constante solta. A proveniencia de cada numero vive em Get-VixCustoEstimadoTier.
        [double]$CustoFull = (Get-VixCustoEstimadoTier 'FULL').Custo,
        [double]$CustoLight = (Get-VixCustoEstimadoTier 'LIGHT').Custo,
        [int]$ChunkFull = 16,
        [int]$ChunkLight = 15
    )

    # `CobertosHoje` e quem outra rotina ja analisou hoje (o plano marca SKIP com motivo
    # analisado_hoje_por_*, CREDITODIA1). Sai da selecao inteira: nao recebe FULL nem LIGHT.
    # `FullSemana` e quem ja tem FULL nesta semana, de qualquer rotina. Continua elegivel a
    # LIGHT, porque LIGHT nao consome a cota semanal de FULL.
    $eleg = @($Emissores | Where-Object {
        if ($_.tier -eq 'SKIP') { return $false }
        if ($CobertosHoje.ContainsKey((Get-NomeNormalizado $_.empresa))) { return $false }
        return $true
    })
    $nEleg = $eleg.Count

    $jaFull = $FullSemana.Count
    $faltam = $BaseCarteira - $jaFull
    if ($faltam -lt 0) { $faltam = 0 }

    $noites = $NoitesRestantes
    if ($noites -lt 0) { $noites = 0 }

    $minFull = 0
    if ($noites -gt 0 -and $faltam -gt 0) {
        $minFull = [int][Math]::Ceiling([double]$faltam / [double]$noites)
    }

    # Candidatos a FULL: elegiveis que ainda nao tem FULL nesta semana.
    $candFull = @($eleg | Where-Object { -not $FullSemana.ContainsKey((Get-NomeNormalizado $_.empresa)) })
    $ordFull = Get-VixOrdemFull $candFull

    $capPagaFull = 0
    if ($CustoFull -gt 0) { $capPagaFull = [int][Math]::Floor([double]$CapEfetivo / $CustoFull) }

    $nFull = $minFull
    if ($nFull -gt $capPagaFull) { $nFull = $capPagaFull }
    if ($nFull -gt $ordFull.Count) { $nFull = $ordFull.Count }
    if ($nFull -lt 0) { $nFull = 0 }

    $full = @()
    if ($nFull -gt 0) { $full = @($ordFull | Select-Object -First $nFull) }
    $setFull = @{}
    foreach ($f in $full) { $setFull[(Get-NomeNormalizado $f.empresa)] = $true }

    $custoFullTotal = [double]$nFull * $CustoFull
    $restante = [double]$CapEfetivo - $custoFullTotal
    if ($restante -lt 0) { $restante = 0 }

    $capPagaLight = 0
    if ($CustoLight -gt 0) { $capPagaLight = [int][Math]::Floor($restante / $CustoLight) }

    $candLight = @($eleg | Where-Object { -not $setFull.ContainsKey((Get-NomeNormalizado $_.empresa)) })
    $ordLight = Get-VixOrdemLight $candLight

    $nLight = $capPagaLight
    if ($nLight -gt $ordLight.Count) { $nLight = $ordLight.Count }
    if ($nLight -lt 0) { $nLight = 0 }

    $light = @()
    if ($nLight -gt 0) { $light = @($ordLight | Select-Object -First $nLight) }

    $custoLightTotal = [double]$nLight * $CustoLight
    $estimado = $custoFullTotal + $custoLightTotal

    $gapMax = 0
    foreach ($e in @($full) + @($light)) {
        $h = $e.horas_desde_analise
        if ($null -eq $h) { continue }
        $d = [int][Math]::Floor([double]$h / 24.0)
        if ($d -gt $gapMax) { $gapMax = $d }
    }

    $semFullDepois = $jaFull + $nFull
    if ($semFullDepois -gt $BaseCarteira) { $semFullDepois = $BaseCarteira }

    $semFullPct = 0
    if ($BaseCarteira -gt 0) { $semFullPct = [Math]::Round(100.0 * $semFullDepois / $BaseCarteira, 1) }

    $meta = @{
        elegiveis            = $nEleg
        cobertos_hoje        = $CobertosHoje.Count
        ja_full_semana       = $jaFull
        faltam_na_semana     = $faltam
        noites_restantes     = $noites
        min_full_noite       = $minFull
        full_noite           = $nFull
        light_noite          = $nLight
        nao_selecionados     = $nEleg - $nFull - $nLight
        cap_paga_full        = $capPagaFull
        cap_paga_light       = $capPagaLight
        full_semana_depois   = $semFullDepois
        full_semana_pct      = $semFullPct
        estimado_trabalho    = [int64]$estimado
        cap_efetivo          = $CapEfetivo
        custo_full           = $CustoFull
        custo_light          = $CustoLight
        chunk_full           = $ChunkFull
        chunk_light          = $ChunkLight
        # Diagnostico de intervalo entre analises LLM. Nao e gap_web e nao e gate de producao.
        gap_dias_proxy_nao_web = $gapMax
    }

    return @{ Full = $full; Light = $light; Meta = $meta }
}

# D1 do P0 PROFUNDIDADE-NOTURNA1: cauda de rotacao. Todo emissor que entrou na decisao e nao
# foi escolhido para FULL nem para LIGHT tem desfecho real e preciso aparecer no ledger, senao
# ele fica em limbo: nem analisado, nem SKIP, nem DEFERIDO. O motivo separa as duas causas
# possiveis, e a distincao importa para o dia seguinte:
#   rotacao_semanal -> nao aprofundou por desenho da rotacao. NAO e corte por orcamento.
#   cap_efetivo     -> o cap fechou (inclusive CIRCUITO_ABERTO). E corte por orcamento.
# Pura de proposito: o teste prova o fechamento do ledger sem subir o motor.
function Get-VixCaudaRotacao {
    param(
        [object[]]$AnalyzeList = @(),
        [object[]]$Fila = @(),
        [bool]$CapAtingido = $false,
        [int64]$TokenHardCap = 0,
        [bool]$CircuitoAberto = $false
    )
    $setFila = @{}
    foreach ($e in $Fila) { $setFila[(Get-NomeNormalizado $e.empresa)] = $true }
    # SKIP nao entra na cauda: ele nao foi decidido nesta noite, ja saiu do plano antes. O motor
    # ja passa a lista pre-filtrada, mas a funcao filtra de novo para nenhum chamador futuro
    # conseguir deferir como rotacao um emissor que o Worker marcou como SKIP.
    $base = @($AnalyzeList | Where-Object { $_.tier -ne 'SKIP' })
    $cauda = @($base | Where-Object { -not $setFila.ContainsKey((Get-NomeNormalizado $_.empresa)) })
    $motivo = 'rotacao_semanal'
    if ($CapAtingido -or $TokenHardCap -le 0 -or $CircuitoAberto) { $motivo = 'cap_efetivo' }
    return [pscustomobject]@{ Emissores = $cauda; Motivo = $motivo }
}

# Monta os lotes de uma lista ja ordenada, com tier e higiene proprios: FULL usa o modelo e o
# prompt aprofundados, LIGHT usa os do perfil. Devolve lista de jobs no mesmo formato que o
# motor ja consome (Name, Model, Chunk, Skill, Ultra, Provedor, Tier).
function New-VixJobsPorTier {
    param(
        [object[]]$Selecionados = @(),
        [string]$Tier = 'LIGHT',
        [int]$Chunk = 15,
        [string]$Model = '',
        [string]$Skill = '',
        [bool]$Ultra = $false,
        [string]$Provedor = ''
    )
    $jobs = New-Object System.Collections.Generic.List[object]
    if ($Selecionados.Count -eq 0) { return $jobs }
    $i = 0
    while ($i -lt $Selecionados.Count) {
        $fim = $i + $Chunk - 1
        if ($fim -ge $Selecionados.Count) { $fim = $Selecionados.Count - 1 }
        $fatia = @($Selecionados[$i..$fim])
        $jobs.Add([ordered]@{
            Name     = $Tier.ToLower()
            Tier     = $Tier.ToUpper()
            Model    = $Model
            Chunk    = $fatia
            Skill    = $Skill
            Ultra    = $Ultra
            Provedor = $Provedor
        })
        $i = $fim + 1
    }
    return $jobs
}
