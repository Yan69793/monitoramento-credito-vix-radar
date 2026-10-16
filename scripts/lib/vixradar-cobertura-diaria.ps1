# vixradar-cobertura-diaria.ps1 - controle diario de verificacao por emissor (COBDIARIA1, 2026-10-14).
#
# Por que existe. Ate aqui "cobertura" queria dizer ANALISE DE IA, e a analise de IA nao cabe no
# dia: medido em 14/10, a noturna pagou 1.193.101 tokens por 16 emissores FULL (74.569 cada) e
# deferiu 72; a matinal achou 20.721 de cap e analisou 0. Com 104 emissores e TETO_DIA 2.600.000,
# 104 analises FULL por dia nao existem. Mas o requisito do operador e VERIFICACAO diaria com fonte
# real, e verificar nao exige IA: o coletor (Google News RSS, 3 familias, HTTP real, zero token)
# responde "houve fato novo?" para os 104 em ~6 minutos. A IA so e OBRIGATORIA onde ha fato novo a
# interpretar (medido 08-14/10: 16 de 109 decisoes de triagem, ~15%); a revalidacao periodica dos
# quietos (89 de 109) e analise COMPLEMENTAR e fica atras na fila.
#
# O que este arquivo da:
#   1. Ledger por dia (`cobertura_diaria_YYYYMMDD.json`), um registro por emissor, com estado,
#      evidencia individual (consultas com familia, query, timestamp e HTTP), provider, modelo e
#      tokens, historico de transicoes. Escrita atomica sob mutex.
#   2. Classificacao PURA do resultado da verificacao do dia (SEM_NOVIDADE / NOVIDADE /
#      FALHA_CONSULTA / CACHE_ANTIGO), separada da regra de revalidacao da IA.
#   3. Transicao monotona: estado verificado nunca e rebaixado por falha posterior, e estado
#      verificado sem evidencia DO DIA e recusado (nada de conclusao por cache antigo).
#   4. Resumo com omitidos (universo do plano sem registro) - so ha OK com N/N verificados.
#   5. Decisao PURA do proximo passo de cada pendente (cascata economica): recoleta (0 token),
#      IA barata, IA com ferramenta, Claude como ultimo fallback (opt-in), ou INSUFICIENCIA.
#   6. Reserva de orcamento da cobertura obrigatoria antes de analise complementar.
#   7. Ordem de trabalho: obrigatorio do dia primeiro, complementar depois (sem perder ninguem).
#
# Depende de lib\vixradar-cobertura.ps1 (ConvertTo-VixChaveEmissor, Get-VixTriagemEmissor,
# Get-VixFontesColetor). PowerShell 5.1, ASCII puro, $ErrorActionPreference Continue.

$script:VixCobDiariaTerminais = @('VERIFICADO_SEM_NOVIDADE', 'VERIFICADO_ANALISADO')
$script:VixCobDiariaEstados = @('VERIFICADO_SEM_NOVIDADE', 'VERIFICADO_ANALISADO', 'PENDENTE_IA', 'FALHA_CONSULTA', 'PENDENTE')
$script:VixCobDiariaMaxTentativasColeta = 3
$script:VixCobDiariaHistoricoMax = 30
$script:VixCobDiariaFamilias = @('emissor', 'divida', 'fato')
# BRT sem horario de verao desde 2019 (Decreto 9.772). O dia do ledger e o dia civil BRT, o mesmo
# DateTag (Get-Date local) que as rotinas usam no nome dos arquivos.
$script:VixCobDiariaOffsetBrtH = -3

function Get-VixCobDiariaPath([string]$LogDir, [string]$DateTag) { return (Join-Path $LogDir ('cobertura_diaria_' + $DateTag + '.json')) }

function Get-VixCobDiariaConfig([string]$LogDir) {
    # Universo minimo declarado e teto do fallback Claude. AUSENTE = fallback Claude desligado
    # (fail-closed): este arquivo nao inventa teto, quem declara e o operador em custo-config.json.
    $cfg = @{ UNIVERSO_MINIMO = 0; CLAUDE_FALLBACK_DIA = 0 }
    $p = Join-Path $LogDir 'custo-config.json'
    if (Test-Path -LiteralPath $p) {
        try {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @('UNIVERSO_MINIMO', 'CLAUDE_FALLBACK_DIA')) {
                if ($null -ne $j.PSObject.Properties[$k]) { $v = [int64]0; if ([int64]::TryParse(('' + $j.$k), [ref]$v) -and $v -ge 0) { $cfg[$k] = $v } }
            }
        } catch { }
    }
    return $cfg
}

# Dia BRT (yyyyMMdd) de um timestamp ISO. Vazio quando nao parseia: quem chama trata como sem prova.
function Get-VixCobDiariaDiaBrt([string]$Iso) {
    $t = [datetime]::MinValue
    if (-not $Iso) { return '' }
    if (-not [datetime]::TryParse($Iso, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$t)) { return '' }
    return $t.AddHours($script:VixCobDiariaOffsetBrtH).ToString('yyyyMMdd')
}

function Get-VixCobDiariaCampo($Obj, [string]$Nome) {
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [hashtable] -or $Obj -is [System.Collections.Specialized.OrderedDictionary]) { if ($Obj.Contains($Nome)) { return $Obj[$Nome] }; return $null }
    $p = $Obj.PSObject.Properties[$Nome]
    if ($null -eq $p) { return $null }
    return $p.Value
}

# Evidencia do dia. Uma fonte so vale se tiver timestamp no dia BRT do ledger e HTTP 2xx (quando o
# campo existe). `ExigirFamilias` exige as tres familias validas - e o caso da ausencia certificada,
# que nao pode sair de uma familia so.
function Test-VixCobDiariaEvidencia {
    param([object[]]$Fontes = @(), [string]$DateTag = '', [bool]$ExigirFamilias = $false)
    $validas = @(); $fora = 0; $semHttp = 0
    $fams = @{}
    foreach ($f in @($Fontes)) {
        if ($null -eq $f) { continue }
        $dia = Get-VixCobDiariaDiaBrt ('' + (Get-VixCobDiariaCampo $f 'timestamp'))
        if ($dia -ne $DateTag) { $fora++; continue }
        $st = Get-VixCobDiariaCampo $f 'status_http'
        if ($null -ne $st -and ('' + $st) -ne '') {
            $n = 0
            if (-not [int]::TryParse(('' + $st), [ref]$n) -or $n -lt 200 -or $n -gt 299) { $semHttp++; continue }
        }
        $cl = ('' + (Get-VixCobDiariaCampo $f 'classificacao')).Trim().ToLowerInvariant()
        if ($cl -and $cl -ne 'ok') { $semHttp++; continue }
        $validas += $f
        $fa = ('' + (Get-VixCobDiariaCampo $f 'familia')).Trim().ToLowerInvariant()
        if ($fa) { $fams[$fa] = $true }
    }
    $faltam = @()
    if ($ExigirFamilias) { foreach ($x in $script:VixCobDiariaFamilias) { if (-not $fams.ContainsKey($x)) { $faltam += $x } } }
    $ok = ($validas.Count -gt 0 -and $faltam.Count -eq 0)
    $motivo = 'evidencia_do_dia'
    if (-not $ok) {
        if ($validas.Count -eq 0 -and $fora -gt 0) { $motivo = 'evidencia_fora_do_dia' }
        elseif ($validas.Count -eq 0) { $motivo = 'sem_evidencia' }
        else { $motivo = ('familias_faltando_' + ($faltam -join '_')) }
    }
    return @{ ok = $ok; motivo = $motivo; validas = $validas.Count; fora_do_dia = $fora; reprovadas = $semHttp; familias_faltando = $faltam }
}

# Verificacao do DIA, pura. Usa a mesma triagem do motor com HorasDesdeIA=0: a regra de revalidacao
# de IA (120h/48h) e analise complementar e NAO entra na pergunta "houve fato novo hoje?". Pergunta
# aberta (INCONCLUSIVO anterior, recheck) continua exigindo IA: NOVIDADE.
function Get-VixVerificacaoDiaria {
    param($Coleta = $null, [string]$DeltaInicio = '', [int]$CvmNovos = 0, [bool]$EstadoNaoResolvido = $false, [string]$MotivoNaoResolvido = '', [string]$DateTag = '', [datetime]$Agora = (Get-Date))
    if ($null -eq $Coleta) { return @{ Resultado = 'FALHA_CONSULTA'; Motivo = 'sem_coleta'; Novas = @(); Fontes = @(); ColetadoEm = '' } }
    $col = '' + (Get-VixCobDiariaCampo $Coleta 'coletado_em')
    $disp = Get-VixCobDiariaCampo $Coleta 'disponivel'
    if ($null -ne $disp -and -not [bool]$disp) { return @{ Resultado = 'FALHA_CONSULTA'; Motivo = 'coleta_incompleta'; Novas = @(); Fontes = @(); ColetadoEm = $col } }
    if ($DateTag -and (Get-VixCobDiariaDiaBrt $col) -ne $DateTag) { return @{ Resultado = 'CACHE_ANTIGO'; Motivo = ('coleta_de_' + (Get-VixCobDiariaDiaBrt $col)); Novas = @(); Fontes = @(); ColetadoEm = $col } }
    $tri = Get-VixTriagemEmissor -Coleta $Coleta -DeltaInicio $DeltaInicio -CvmNovos $CvmNovos -HorasDesdeIA 0 -EstadoNaoResolvido $EstadoNaoResolvido -MotivoNaoResolvido $MotivoNaoResolvido -Agora $Agora
    $fontes = @(Get-VixFontesColetor $Coleta $DeltaInicio)
    $r = 'NOVIDADE'
    if ($tri.Classe -eq 'QUIETO') { $r = 'SEM_NOVIDADE' }
    elseif ($tri.Classe -eq 'INDISPONIVEL') { $r = 'FALHA_CONSULTA' }
    return @{ Resultado = $r; Motivo = ('' + $tri.Motivo); Novas = @($tri.Novas); Fontes = $fontes; ColetadoEm = $col }
}

# Transicao pura entre estados do registro. Regras:
#   - terminal nunca e rebaixado (falha posterior, deferimento ou cache nao apagam prova do dia);
#   - VERIFICADO_ANALISADO sobe sobre VERIFICADO_SEM_NOVIDADE (mais profundidade), o inverso nao;
#   - terminal novo SEM evidencia do dia vira PENDENTE (sem novidade) ou PENDENTE_IA (analise).
function Get-VixCobDiariaTransicao {
    param([string]$Atual = '', [string]$Novo = '', [bool]$EvidenciaOk = $false)
    $ehTermAtual = ($script:VixCobDiariaTerminais -contains $Atual)
    $ehTermNovo = ($script:VixCobDiariaTerminais -contains $Novo)
    if ($ehTermNovo -and -not $EvidenciaOk) {
        $rebaixado = 'PENDENTE'
        if ($Novo -eq 'VERIFICADO_ANALISADO') { $rebaixado = 'PENDENTE_IA' }
        if ($ehTermAtual) { return @{ Estado = $Atual; Aplicada = $false; Motivo = 'terminal_mantido_novo_sem_evidencia' } }
        return @{ Estado = $rebaixado; Aplicada = $true; Motivo = 'terminal_recusado_sem_evidencia_do_dia' }
    }
    if ($ehTermAtual -and -not $ehTermNovo) { return @{ Estado = $Atual; Aplicada = $false; Motivo = 'terminal_nao_rebaixa' } }
    if ($Atual -eq 'VERIFICADO_ANALISADO' -and $Novo -eq 'VERIFICADO_SEM_NOVIDADE') { return @{ Estado = $Atual; Aplicada = $false; Motivo = 'analisado_nao_rebaixa' } }
    # PENDENTE_IA (fato novo visto) nao volta a PENDENTE generico por um deferimento sem coleta.
    if ($Atual -eq 'PENDENTE_IA' -and $Novo -eq 'PENDENTE') { return @{ Estado = $Atual; Aplicada = $false; Motivo = 'pendente_ia_mantido' } }
    return @{ Estado = $Novo; Aplicada = $true; Motivo = 'aplicada' }
}

function New-VixCobDiariaLedger([string]$DateTag) {
    return @{ versao = 1; data = $DateTag; universo_total = 0; universo = @(); universo_fonte = ''; atualizado_em = ''; emissores = @{} }
}

function Read-VixCobDiaria([string]$Path, [string]$DateTag = '') {
    $l = New-VixCobDiariaLedger $DateTag
    if (-not (Test-Path -LiteralPath $Path)) { return $l }
    $j = $null
    try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw ('ledger de cobertura diaria ilegivel: ' + $Path + ' - ' + $_.Exception.Message) }
    if ($null -eq $j) { return $l }
    foreach ($c in @('data', 'universo_fonte', 'atualizado_em')) { if ($null -ne $j.PSObject.Properties[$c]) { $l[$c] = '' + $j.$c } }
    if ($null -ne $j.PSObject.Properties['universo_total']) { $l.universo_total = [int]$j.universo_total }
    if ($null -ne $j.PSObject.Properties['universo']) { $l.universo = @($j.universo | ForEach-Object { '' + $_ }) }
    if ($null -ne $j.PSObject.Properties['emissores'] -and $null -ne $j.emissores) {
        foreach ($p in @($j.emissores.PSObject.Properties)) { $l.emissores[$p.Name] = $p.Value }
    }
    return $l
}

function Write-VixCobDiaria([string]$Path, $Ledger) {
    $Ledger.atualizado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $em = [ordered]@{}
    foreach ($k in @(@($Ledger.emissores.Keys) | Sort-Object)) { $em[$k] = $Ledger.emissores[$k] }
    $doc = [ordered]@{ versao = 1; data = $Ledger.data; universo_total = [int]$Ledger.universo_total; universo = @($Ledger.universo); universo_fonte = $Ledger.universo_fonte; atualizado_em = $Ledger.atualizado_em; emissores = $em }
    $tmp = $Path + '.tmp-' + $PID
    [IO.File]::WriteAllText($tmp, ($doc | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, ($Path + '.bak')) } else { [IO.File]::Move($tmp, $Path) }
}

# Read-modify-write sob mutex nomeado: matinal, noturna e sentinela escrevem o mesmo dia.
function Invoke-VixCobDiariaSob([string]$Path, [string]$DateTag, [scriptblock]$Acao) {
    $mtx = New-Object System.Threading.Mutex($false, 'Global\vixradar-cobertura-diaria-v1')
    $tem = $false
    try {
        try { $tem = $mtx.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $tem = $true }
        if (-not $tem) { throw 'mutex da cobertura diaria ocupado por mais de 30s' }
        $l = Read-VixCobDiaria $Path $DateTag
        if (-not $l.data) { $l.data = $DateTag }
        $res = & $Acao $l
        Write-VixCobDiaria $Path $l
        return $res
    } finally {
        if ($tem) { try { $mtx.ReleaseMutex() } catch { } }
        $mtx.Dispose()
    }
}

# Universo do dia: o plano do Worker. Uniao, nunca encolhe dentro do dia (um plano parcial da
# matinal nao pode tirar emissor do denominador que a noturna gravou).
function Set-VixCobDiariaUniverso([string]$Path, [string]$DateTag, [string[]]$Nomes, [int]$Total, [string]$Fonte) {
    return Invoke-VixCobDiariaSob $Path $DateTag {
        param($l)
        $vistos = @{}
        $lista = New-Object System.Collections.Generic.List[string]
        foreach ($n in @(@($l.universo) + @($Nomes))) {
            $nn = ('' + $n).Trim()
            if (-not $nn) { continue }
            $k = ConvertTo-VixChaveEmissor $nn
            if ($vistos.ContainsKey($k)) { continue }
            $vistos[$k] = $true; $lista.Add($nn)
        }
        $l.universo = $lista.ToArray()
        $l.universo_total = [Math]::Max([Math]::Max([int]$l.universo_total, [int]$Total), $lista.Count)
        if ($Fonte) { $l.universo_fonte = $Fonte }
        return $l.universo_total
    }
}

# Registro de um evento de verificacao/analise. Devolve o estado final e se a transicao valeu.
#   Estado     : VERIFICADO_SEM_NOVIDADE | VERIFICADO_ANALISADO | PENDENTE_IA | FALHA_CONSULTA | PENDENTE
#   Fontes     : consultas (familia, query, timestamp, status_http...) - prova individual
#   Analise    : @{ provider; modelo; tier; classificacao; tokens; submit_ok; n_eventos }
function Register-VixCobDiaria {
    param(
        [string]$Path, [string]$DateTag, [string]$Empresa, [string]$Estado, [string]$Motivo = '', [string]$Rotina = '',
        [object[]]$Fontes = @(), $Analise = $null, [string]$ColetadoEm = '', [datetime]$Agora = (Get-Date)
    )
    $exigeFam = ($Estado -eq 'VERIFICADO_SEM_NOVIDADE')
    $ev = Test-VixCobDiariaEvidencia -Fontes $Fontes -DateTag $DateTag -ExigirFamilias $exigeFam
    # Analise concluida: a prova e a propria analise de hoje (submit aceito) MAIS ao menos uma fonte
    # do dia. O carimbo da analise e o relogio do orquestrador, nao o do modelo.
    if ($Estado -eq 'VERIFICADO_ANALISADO') {
        $sub = [bool](Get-VixCobDiariaCampo $Analise 'submit_ok')
        $cls = ('' + (Get-VixCobDiariaCampo $Analise 'classificacao')).Trim().ToUpperInvariant()
        $nf = @($Fontes | Where-Object { $null -ne $_ }).Count
        $okAn = ($sub -and $cls -ne 'INCONCLUSIVO' -and $nf -gt 0 -and $Agora.ToUniversalTime().AddHours($script:VixCobDiariaOffsetBrtH).ToString('yyyyMMdd') -eq $DateTag)
        $mot = 'analise_do_dia'
        if (-not $sub) { $mot = 'submit_nao_aceito' } elseif ($cls -eq 'INCONCLUSIVO') { $mot = 'analise_inconclusiva' } elseif ($nf -eq 0) { $mot = 'analise_sem_fontes' } elseif (-not $okAn) { $mot = 'analise_fora_do_dia' }
        $ev = @{ ok = $okAn; motivo = $mot; validas = $nf; fora_do_dia = 0; reprovadas = 0; familias_faltando = @() }
    }
    $agoraIso = $Agora.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    return Invoke-VixCobDiariaSob $Path $DateTag {
        param($l)
        $k = ConvertTo-VixChaveEmissor $Empresa
        $r = $null
        if ($l.emissores.ContainsKey($k)) { $r = $l.emissores[$k] }
        $h = @{}
        if ($r -is [hashtable]) { $h = $r }
        elseif ($null -ne $r) { foreach ($p in @($r.PSObject.Properties)) { $h[$p.Name] = $p.Value } }
        if (-not $h.ContainsKey('empresa')) { $h.empresa = $Empresa; $h.estado = ''; $h.tentativas_coleta = 0; $h.tentativas_ia = 0; $h.historico = @(); $h.primeiro_em = $agoraIso }
        $t = Get-VixCobDiariaTransicao -Atual ('' + $h.estado) -Novo $Estado -EvidenciaOk ([bool]$ev.ok)
        if ($Estado -eq 'FALHA_CONSULTA') { $h.tentativas_coleta = [int]$h.tentativas_coleta + 1 }
        if ($null -ne $Analise) { $h.tentativas_ia = [int]$h.tentativas_ia + 1 }
        if ($t.Aplicada) {
            $h.estado = $t.Estado
            $h.motivo = $Motivo
            if ($t.Motivo -ne 'aplicada') { $h.motivo = ($t.Motivo + ':' + $ev.motivo + ':' + $Motivo) }
            $h.rotina = $Rotina; $h.atualizado_em = $agoraIso
            if ($script:VixCobDiariaTerminais -contains $t.Estado) {
                $h.verificado_em = $agoraIso
                $h.evidencia = [ordered]@{ motivo = $ev.motivo; fontes_validas = [int]$ev.validas; coletado_em = $ColetadoEm; fontes = @($Fontes | Where-Object { $null -ne $_ } | Select-Object -First 12) }
            }
        }
        if ($null -ne $Analise) { $h.analise = $Analise }
        $hist = @($h.historico)
        $hist += [ordered]@{ ts = $agoraIso; rotina = $Rotina; pedido = $Estado; final = $t.Estado; aplicada = [bool]$t.Aplicada; motivo = $Motivo; prova = $ev.motivo }
        if ($hist.Count -gt $script:VixCobDiariaHistoricoMax) { $hist = @($hist | Select-Object -Last $script:VixCobDiariaHistoricoMax) }
        $h.historico = $hist
        $l.emissores[$k] = $h
        return @{ Estado = $t.Estado; Aplicada = [bool]$t.Aplicada; Motivo = $t.Motivo; Prova = $ev.motivo }
    }
}

# Resumo puro. OK so com universo conhecido, >= minimo declarado, zero omitidos e todo emissor do
# universo em estado terminal com evidencia. Universo desconhecido nunca vira OK.
function Get-VixCobDiariaResumo {
    param($Ledger, [int]$UniversoMinimo = 0)
    $porEstado = @{}
    foreach ($e in $script:VixCobDiariaEstados) { $porEstado[$e] = 0 }
    $pend = New-Object System.Collections.Generic.List[object]
    $omit = New-Object System.Collections.Generic.List[string]
    $univ = @($Ledger.universo)
    $chavesUniv = @{}
    foreach ($n in $univ) { $chavesUniv[(ConvertTo-VixChaveEmissor ('' + $n))] = '' + $n }
    $term = 0
    foreach ($k in @($chavesUniv.Keys)) {
        if (-not $Ledger.emissores.ContainsKey($k)) { $omit.Add($chavesUniv[$k]); continue }
        $r = $Ledger.emissores[$k]
        $est = '' + (Get-VixCobDiariaCampo $r 'estado')
        if ($porEstado.ContainsKey($est)) { $porEstado[$est]++ } else { $porEstado[$est] = 1 }
        $temProva = ($null -ne (Get-VixCobDiariaCampo $r 'evidencia'))
        if (($script:VixCobDiariaTerminais -contains $est) -and $temProva) { $term++ }
        else { $pend.Add([pscustomobject]@{ empresa = ('' + (Get-VixCobDiariaCampo $r 'empresa')); estado = $est; motivo = ('' + (Get-VixCobDiariaCampo $r 'motivo')); tentativas_coleta = [int](Get-VixCobDiariaCampo $r 'tentativas_coleta'); tentativas_ia = [int](Get-VixCobDiariaCampo $r 'tentativas_ia') }) }
    }
    $foraUniverso = 0
    foreach ($k in @($Ledger.emissores.Keys)) { if (-not $chavesUniv.ContainsKey($k)) { $foraUniverso++ } }
    $total = [int]$Ledger.universo_total
    $motivos = @()
    if ($univ.Count -eq 0) { $motivos += 'universo_desconhecido' }
    if ($univ.Count -lt $total) { $motivos += ('universo_incompleto_' + $univ.Count + '_de_' + $total) }
    if ($UniversoMinimo -gt 0 -and $total -lt $UniversoMinimo) { $motivos += ('universo_abaixo_do_minimo_' + $total + '_lt_' + $UniversoMinimo) }
    if ($omit.Count -gt 0) { $motivos += ('omitidos_' + $omit.Count) }
    if ($pend.Count -gt 0) { $motivos += ('pendentes_' + $pend.Count) }
    $ok = ($motivos.Count -eq 0 -and $term -eq $total -and $total -gt 0)
    return [pscustomobject]@{
        ok = $ok; universo_total = $total; universo_listado = $univ.Count; verificados = $term
        sem_novidade = [int]$porEstado['VERIFICADO_SEM_NOVIDADE']; analisados = [int]$porEstado['VERIFICADO_ANALISADO']
        pendentes_ia = [int]$porEstado['PENDENTE_IA']; falhas_consulta = [int]$porEstado['FALHA_CONSULTA']; pendentes_outros = [int]$porEstado['PENDENTE']
        omitidos = $omit.ToArray(); pendentes = $pend.ToArray(); fora_do_universo = $foraUniverso; motivos = $motivos
    }
}

# Cascata economica, pura. Ordem de custo crescente, Claude por ultimo e so com opt-in + teto
# declarado. INSUFICIENCIA e o unico desfecho quando nada cabe: quem chama registra incidente.
#   Estado               : estado atual do registro (terminal => NADA)
#   TentativasColeta     : falhas de coleta ja registradas hoje
#   IaInconclusiva       : a IA barata ja tentou e nao fechou (=> precisa de ferramenta)
#   Critico              : fato critico/cvm novo/EWS critico (=> vai direto para ferramenta)
#   PrimarioDisponivel   : provider ativo sem cota esgotada/auth quebrada (disjuntor fechado)
#   OrcamentoPrimario    : tokens que o circuito do dia ainda libera para o provider ativo
#   ClaudeHabilitado     : VIXRADAR_COBERTURA_FALLBACK_CLAUDE=1 e provider claude disponivel
#   ClaudeLimiteAtingido : sonda/429 da assinatura (limite de sessao/semana)
#   OrcamentoClaude      : CLAUDE_FALLBACK_DIA declarado menos o ja gasto no fallback hoje
function Get-VixCobDiariaProximoPasso {
    param(
        [string]$Estado = '', [int]$TentativasColeta = 0, [bool]$IaInconclusiva = $false, [bool]$Critico = $false,
        [bool]$PrimarioDisponivel = $true, [int64]$OrcamentoPrimario = 0, [int64]$CustoBarato = 0, [int64]$CustoFull = 0,
        [bool]$ClaudeHabilitado = $false, [bool]$ClaudeLimiteAtingido = $false, [int64]$OrcamentoClaude = 0
    )
    if ($script:VixCobDiariaTerminais -contains $Estado) { return @{ Passo = 'NADA'; Tier = ''; Custo = [int64]0; Motivo = 'verificado' } }
    if ($Estado -eq 'FALHA_CONSULTA' -and $TentativasColeta -lt $script:VixCobDiariaMaxTentativasColeta) {
        return @{ Passo = 'RECOLETAR'; Tier = 'COLETOR'; Custo = [int64]0; Motivo = ('falha_transitoria_' + $TentativasColeta + '_de_' + $script:VixCobDiariaMaxTentativasColeta) }
    }
    # Sem coleta valida (falha persistente ou estado nunca coletado) a IA tem de buscar sozinha:
    # so a ferramenta resolve. Fato novo comum vai primeiro para o pacote barato.
    $tier = 'BARATO'
    if ($Estado -eq 'FALHA_CONSULTA' -or $Estado -eq 'PENDENTE' -or $IaInconclusiva -or $Critico) { $tier = 'FULL' }
    $custo = $CustoBarato
    if ($tier -eq 'FULL') { $custo = $CustoFull }
    if ($custo -le 0) { return @{ Passo = 'INSUFICIENCIA'; Tier = $tier; Custo = [int64]0; Motivo = 'custo_desconhecido_fail_closed' } }
    if ($PrimarioDisponivel -and $OrcamentoPrimario -ge $custo) { return @{ Passo = 'IA_PRIMARIA'; Tier = $tier; Custo = [int64]$custo; Motivo = ('primario_' + $tier.ToLowerInvariant()) } }
    $porque = 'orcamento_primario_insuficiente'
    if (-not $PrimarioDisponivel) { $porque = 'primario_indisponivel' }
    if ($ClaudeHabilitado -and -not $ClaudeLimiteAtingido -and $OrcamentoClaude -ge $custo) {
        return @{ Passo = 'CLAUDE_FALLBACK'; Tier = $tier; Custo = [int64]$custo; Motivo = ($porque + '_claude_ultimo_recurso') }
    }
    $m = $porque
    if (-not $ClaudeHabilitado) { $m = $m + '_claude_desligado' }
    elseif ($ClaudeLimiteAtingido) { $m = $m + '_claude_no_limite' }
    else { $m = $m + '_claude_sem_orcamento' }
    return @{ Passo = 'INSUFICIENCIA'; Tier = $tier; Custo = [int64]$custo; Motivo = $m }
}

# Reserva da cobertura obrigatoria. Cada pendente de IA custa o pacote barato, mais a fracao que
# escala para ferramenta (medida; default 1.0 = pior caso, 13/10 escalou 3 de 3). Falha de coleta
# persistente vai direto para FULL. O que sobra do cap e o unico dinheiro da analise complementar.
function Get-VixCobDiariaReserva {
    param([int]$PendentesIa = 0, [int]$FalhasPersistentes = 0, [int64]$CustoBarato = 0, [int64]$CustoFull = 0, [double]$TaxaEscalada = 1.0, [int64]$CapEfetivo = 0)
    if ($TaxaEscalada -lt 0) { $TaxaEscalada = 0 }
    if ($TaxaEscalada -gt 1) { $TaxaEscalada = 1 }
    $res = [int64][Math]::Ceiling(($PendentesIa * ($CustoBarato + $TaxaEscalada * $CustoFull)) + ($FalhasPersistentes * $CustoFull))
    $comp = $CapEfetivo - $res
    if ($comp -lt 0) { $comp = 0 }
    $deficit = $res - $CapEfetivo
    if ($deficit -lt 0) { $deficit = 0 }
    return @{ Reserva = $res; Complementar = [int64]$comp; Deficit = [int64]$deficit; Cabe = ($deficit -eq 0) }
}

# Ordem de trabalho: obrigatorios do dia (sem verificacao terminal e com fato novo/pergunta aberta
# ou falha de coleta) primeiro, por prioridade e depois na ordem de entrada; complementares depois,
# na ordem de entrada. Estavel, sem duplicar, sem perder.
function Select-VixCobDiariaOrdem {
    param([object[]]$Emissores = @(), [hashtable]$Obrigatorios = @{})
    $obr = New-Object System.Collections.Generic.List[object]
    $comp = New-Object System.Collections.Generic.List[object]
    $visto = @{}
    $i = 0
    foreach ($e in @($Emissores)) {
        if ($null -eq $e) { continue }
        $k = ConvertTo-VixChaveEmissor ('' + $e.empresa)
        if ($visto.ContainsKey($k)) { continue }
        $visto[$k] = $true
        if ($Obrigatorios.ContainsKey($k)) { $obr.Add([pscustomobject]@{ e = $e; p = [int]$Obrigatorios[$k]; i = $i }) } else { $comp.Add($e) }
        $i++
    }
    $ord = @($obr | Sort-Object -Property @{ Expression = { $_.p }; Descending = $true }, @{ Expression = { $_.i }; Descending = $false } | ForEach-Object { $_.e })
    return @(@($ord) + @($comp.ToArray()))
}

# Esgotamento cruzado entre dias (medido 14/10): a noturna "de 13/10" rodou as 02:28 do dia 14,
# gastou 1.193.101 do TETO_DIA de 14/10 e a matinal das 10:06 recebeu cap de 20.721 e analisou 0.
# A noturna so reservava a verificacao. Regra: execucao que comeca ANTES da janela da matinal num
# dia em que a matinal ainda nao rodou reserva o cap proprio da matinal. Pura.
function Get-VixReservaMatinalPendente {
    param([datetime]$Agora = (Get-Date), [bool]$MatinalJaRodou = $false, [int64]$CapMatinal = 0, [int]$HoraLimite = 12)
    if ($MatinalJaRodou) { return [int64]0 }
    if ($Agora.Hour -ge $HoraLimite) { return [int64]0 }
    if ($CapMatinal -lt 0) { return [int64]0 }
    return [int64]$CapMatinal
}

# Fechamento/inspecao do dia. Escreve o relatorio sempre (local, sem efeito externo). Com
# -Fechamento e resultado nao OK: grava incidente critico e chama $AlertaAcao (efeito externo),
# exceto em -DryRun, que so escreve com prefixo DRYRUN_ e nunca alerta.
# Exit sugerido: 0 = N/N verificados; 10 = parcial durante o dia; 20 = incidente critico.
function Invoke-VixCobDiariaFechamento {
    param(
        [string]$LogDir, [string]$DateTag, [switch]$Fechamento, [switch]$DryRun, [scriptblock]$AlertaAcao = $null,
        [string]$Rotina = 'check-cobertura-diaria', [int]$UniversoMinimo = -1, $Capacidade = $null
    )
    $cfg = Get-VixCobDiariaConfig $LogDir
    if ($UniversoMinimo -lt 0) { $UniversoMinimo = [int]$cfg.UNIVERSO_MINIMO }
    $path = Get-VixCobDiariaPath $LogDir $DateTag
    $ledger = $null; $erroLeitura = ''
    if (-not (Test-Path -LiteralPath $path)) { $erroLeitura = 'ledger_ausente' }
    else { try { $ledger = Read-VixCobDiaria $path $DateTag } catch { $erroLeitura = ('ledger_ilegivel:' + $_.Exception.Message) } }
    if ($null -eq $ledger) { $ledger = New-VixCobDiariaLedger $DateTag }
    $res = Get-VixCobDiariaResumo -Ledger $ledger -UniversoMinimo $UniversoMinimo
    $motivos = @($res.motivos)
    if ($erroLeitura) { $motivos = @($erroLeitura) + $motivos }
    $ok = ($res.ok -and -not $erroLeitura)
    $passos = @()
    foreach ($p in @($res.pendentes)) {
        $dec = $null
        if ($null -ne $Capacidade) {
            $dec = Get-VixCobDiariaProximoPasso -Estado $p.estado -TentativasColeta $p.tentativas_coleta -IaInconclusiva (('' + $p.motivo) -like '*inconclusiv*') `
                -PrimarioDisponivel ([bool]$Capacidade.PrimarioDisponivel) -OrcamentoPrimario ([int64]$Capacidade.OrcamentoPrimario) -CustoBarato ([int64]$Capacidade.CustoBarato) -CustoFull ([int64]$Capacidade.CustoFull) `
                -ClaudeHabilitado ([bool]$Capacidade.ClaudeHabilitado) -ClaudeLimiteAtingido ([bool]$Capacidade.ClaudeLimiteAtingido) -OrcamentoClaude ([int64]$Capacidade.OrcamentoClaude)
            # O orcamento e consumido na ordem: o segundo pendente ve o saldo que o primeiro deixou.
            if ($dec.Passo -eq 'IA_PRIMARIA') { $Capacidade.OrcamentoPrimario = [int64]$Capacidade.OrcamentoPrimario - [int64]$dec.Custo }
            elseif ($dec.Passo -eq 'CLAUDE_FALLBACK') { $Capacidade.OrcamentoClaude = [int64]$Capacidade.OrcamentoClaude - [int64]$dec.Custo }
        }
        $passos += [ordered]@{ empresa = $p.empresa; estado = $p.estado; motivo = $p.motivo; passo = $(if ($dec) { $dec.Passo } else { 'NAO_AVALIADO' }); tier = $(if ($dec) { $dec.Tier } else { '' }); custo = $(if ($dec) { [int64]$dec.Custo } else { [int64]0 }); motivo_passo = $(if ($dec) { $dec.Motivo } else { 'sem_capacidade_informada' }) }
    }
    $insuf = @($passos | Where-Object { $_.passo -eq 'INSUFICIENCIA' }).Count
    $status = 'OK'
    $exit = 0
    if (-not $ok) {
        if ($Fechamento) { $status = 'INCIDENTE_CRITICO'; $exit = 20 } else { $status = 'PARCIAL'; $exit = 10 }
    }
    $agora = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $rel = [ordered]@{
        data = $DateTag; gerado_em = $agora; rotina = $Rotina; fechamento = [bool]$Fechamento; dryrun = [bool]$DryRun
        status = $status; ok = $ok; universo_total = $res.universo_total; universo_minimo = $UniversoMinimo; verificados = $res.verificados
        sem_novidade = $res.sem_novidade; analisados = $res.analisados; pendentes_ia = $res.pendentes_ia; falhas_consulta = $res.falhas_consulta
        pendentes_outros = $res.pendentes_outros; omitidos = @($res.omitidos); fora_do_universo = $res.fora_do_universo; motivos = $motivos
        insuficiencia = $insuf; proximos_passos = $passos
    }
    $pfx = ''
    if ($DryRun) { $pfx = 'DRYRUN_' }
    $relPath = Join-Path $LogDir ($pfx + 'cobertura_diaria_relatorio_' + $DateTag + '.json')
    try { [IO.File]::WriteAllText($relPath, ($rel | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false))) } catch { }
    $alertado = $false
    if ($status -eq 'INCIDENTE_CRITICO') {
        $incPath = Join-Path $LogDir ($pfx + 'incidente_cobertura_' + $DateTag + '.json')
        try { [IO.File]::WriteAllText($incPath, ($rel | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false))) } catch { }
        if (-not $DryRun -and $null -ne $AlertaAcao) {
            $txt = ('COBERTURA DIARIA ' + $DateTag + ': ' + $res.verificados + '/' + $res.universo_total + ' verificados, ' + @($res.pendentes).Count + ' pendentes, ' + @($res.omitidos).Count + ' omitidos, ' + $insuf + ' sem capacidade. Motivos: ' + ($motivos -join ', '))
            try { $alertado = [bool](& $AlertaAcao $txt) } catch { $alertado = $false }
        }
    }
    $linha = ('COBERTURA_DIARIA|' + $DateTag + '|' + $status + '|verificados=' + $res.verificados + '/' + $res.universo_total + '|sem_novidade=' + $res.sem_novidade + '|analisados=' + $res.analisados + '|pendentes_ia=' + $res.pendentes_ia + '|falhas_consulta=' + $res.falhas_consulta + '|omitidos=' + @($res.omitidos).Count + '|insuficiencia=' + $insuf + '|alertado=' + [int]$alertado + '|motivos=' + ($motivos -join ','))
    return [pscustomobject]@{ Status = $status; Ok = $ok; Exit = $exit; Linha = $linha; Relatorio = $rel; RelatorioPath = $relPath; Alertado = $alertado }
}

# Registro da verificacao do dia a partir de uma coleta ja feita pelo motor. SEM_NOVIDADE so vale
# confirmado por SEGUNDA amostra independente (o RSS nao e deterministico, caso Raizen 13/10):
# -JaConfirmado quando o motor ja fez a segunda coleta, senao $ColetaFn e chamada uma vez.
# Devolve a verificacao (Resultado/Motivo) e o estado gravado. Nunca lanca.
function Register-VixCobDiariaVerificacao {
    param(
        [string]$Path, [string]$DateTag, [string]$Empresa, $Coleta = $null, [scriptblock]$ColetaFn = $null, [bool]$JaConfirmado = $false,
        [string]$DeltaInicio = '', [int]$CvmNovos = 0, [bool]$EstadoNaoResolvido = $false, [string]$MotivoNaoResolvido = '', [string]$Rotina = '', [datetime]$Agora = (Get-Date)
    )
    $out = @{ Resultado = 'FALHA_CONSULTA'; Motivo = 'nao_avaliado'; Estado = ''; Erro = '' }
    try {
        $v = Get-VixVerificacaoDiaria -Coleta $Coleta -DeltaInicio $DeltaInicio -CvmNovos $CvmNovos -EstadoNaoResolvido $EstadoNaoResolvido -MotivoNaoResolvido $MotivoNaoResolvido -DateTag $DateTag -Agora $Agora
        if ($v.Resultado -eq 'CACHE_ANTIGO' -and $null -ne $ColetaFn) {
            $Coleta = & $ColetaFn
            $v = Get-VixVerificacaoDiaria -Coleta $Coleta -DeltaInicio $DeltaInicio -CvmNovos $CvmNovos -EstadoNaoResolvido $EstadoNaoResolvido -MotivoNaoResolvido $MotivoNaoResolvido -DateTag $DateTag -Agora $Agora
        }
        if ($v.Resultado -eq 'SEM_NOVIDADE' -and -not $JaConfirmado) {
            $c2 = $null
            if ($null -ne $ColetaFn) { try { $c2 = & $ColetaFn } catch { $c2 = $null } }
            $v2 = Get-VixVerificacaoDiaria -Coleta $c2 -DeltaInicio $DeltaInicio -CvmNovos $CvmNovos -EstadoNaoResolvido $EstadoNaoResolvido -MotivoNaoResolvido $MotivoNaoResolvido -DateTag $DateTag -Agora $Agora
            if ($v2.Resultado -ne 'SEM_NOVIDADE') { $v = $v2; $v.Motivo = ('segunda_amostra_' + $v2.Motivo) }
        }
        $estado = 'PENDENTE_IA'
        if ($v.Resultado -eq 'SEM_NOVIDADE') { $estado = 'VERIFICADO_SEM_NOVIDADE' }
        elseif ($v.Resultado -eq 'FALHA_CONSULTA' -or $v.Resultado -eq 'CACHE_ANTIGO') { $estado = 'FALHA_CONSULTA' }
        $r = Register-VixCobDiaria -Path $Path -DateTag $DateTag -Empresa $Empresa -Estado $estado -Motivo ($v.Resultado + ':' + $v.Motivo) -Rotina $Rotina -Fontes @($v.Fontes) -ColetadoEm ('' + $v.ColetadoEm) -Agora $Agora
        $out.Resultado = $v.Resultado; $out.Motivo = $v.Motivo; $out.Estado = $r.Estado
    } catch { $out.Erro = $_.Exception.Message }
    return $out
}

# Idempotencia do ledger do dia. Medido 14/10 18:05: a noturna leu as 104 linhas OK| da execucao
# das 02:28 (16 ANALISADO, 16 SKIP, 72 DEFERIDO), tratou as 104 como processadas e fechou com fila 0
# e 700.000 de cap livre. DEFERIDO por orcamento e trabalho NAO feito: com -ReprocessarDeferidos ele
# volta a ser elegivel; ANALISADO e SKIP continuam travando reinicio. Pura: recebe as linhas do log.
function Get-VixIdempotenciaProcessados {
    param([string[]]$Linhas = @(), [bool]$ReprocessarDeferidos = $false)
    $proc = @{}; $def = @{}
    foreach ($ln in @($Linhas)) {
        $m = [regex]::Match(('' + $ln), '^[\d-]+ [\d:]+ OK\|([^|]+)\|[^|]*\|[^|]*\|[^|]*\|[^|]*\|([A-Z_]+)')
        if (-not $m.Success) {
            $m2 = [regex]::Match(('' + $ln), '^[\d-]+ [\d:]+ OK\|([^|]+)\|')
            if ($m2.Success) { $proc[$m2.Groups[1].Value] = $true }
            continue
        }
        $nome = $m.Groups[1].Value; $st = $m.Groups[2].Value
        if ($st -eq 'DEFERIDO' -and $ReprocessarDeferidos) { $def[$nome] = $true; continue }
        $proc[$nome] = $true
    }
    $soDeferidos = @($def.Keys | Where-Object { -not $proc.ContainsKey($_) })
    return @{ Processados = @($proc.Keys); DeferidosReabertos = $soDeferidos }
}

# Prioridade da obrigacao (maior primeiro). Falha de coleta e o que mais precisa de olho.
function Get-VixCobDiariaPrioridade([string]$Resultado, [string]$Motivo) {
    if ($Resultado -eq 'FALHA_CONSULTA' -or $Resultado -eq 'CACHE_ANTIGO') { return 100 }
    $m = ('' + $Motivo)
    if ($m -like 'cvm_novos*') { return 90 }
    if ($m -like 'critico_f1*') { return 85 }
    if ($m -like 'estado_nao_resolvido*') { return 70 }
    if ($m -like 'evidencia_nova*') { return 60 }
    return 50
}

# ------------------------------------------------------------------------------------------------
# COBFALLBACK1 (2026-10-14): EXECUTOR do fallback Claude da cobertura diaria.
#
# Get-VixCobDiariaProximoPasso ja DECIDE CLAUDE_FALLBACK para o pendente que o provider primario
# (codex) nao consegue pagar ou atender, e o fechamento grava a decisao em
# cobertura_diaria_relatorio_YYYYMMDD.json. Faltava quem executasse. O executor e um MODO do motor
# (run_vixradar_varredura.ps1 -Rotina noturno -CoberturaFallbackClaude); aqui ficam as regras
# puras que ele consome, testaveis sem CLI e sem rede:
#   - opt-in: VIXRADAR_COBERTURA_FALLBACK_CLAUDE=1 (Process, depois User). Ausente = INERTE;
#   - teto: CLAUDE_FALLBACK_DIA de custo-config.json (ausente/0 = INERTE, fail-closed);
#   - gasto do dia proprio do fallback em cobertura_fallback_claude_YYYYMMDD.json, por execucao,
#     separado do TETO_DIA do primario (as duas reguas nao se misturam). Uso nao mensuravel ou
#     arquivo ilegivel = saldo zero no resto do dia;
#   - alvos: so o que o relatorio decidiu CLAUDE_FALLBACK, conferido contra o ledger AGORA (quem
#     ja fechou sai) e contra o que o fallback ja tentou hoje (nao repete chamada sem perspectiva),
#     consumindo o saldo na ordem do relatorio;
#   - incidente local quando ha pendente decidido para o Claude e nada cabe (saldo, assinatura
#     indisponivel, limite de sessao/429 na sonda). Alerta externo fica com o motor.
# Governanca: Claude so pela assinatura via CLI. ANTHROPIC_API_PAYG nao autorizado - quem chama
# recusa modo de auth 'api' (AuthFn devolve ok=false) e nunca desvia para outro provedor.
$script:VixCobFallbackFlagNome = 'VIXRADAR_COBERTURA_FALLBACK_CLAUDE'

function Get-VixCobFallbackFlagValor {
    $v = [Environment]::GetEnvironmentVariable($script:VixCobFallbackFlagNome, 'Process')
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($script:VixCobFallbackFlagNome, 'User') }
    return ('' + $v)
}

function Test-VixCobFallbackFlag([string]$Valor) { return (('' + $Valor).Trim() -eq '1') }

function Get-VixCobFallbackGastoPath([string]$LogDir, [string]$DateTag) { return (Join-Path $LogDir ('cobertura_fallback_claude_' + $DateTag + '.json')) }

function Get-VixCobFallbackIncidentePath([string]$LogDir, [string]$DateTag, [bool]$DryRun = $false) {
    $pfx = ''
    if ($DryRun) { $pfx = 'DRYRUN_' }
    return (Join-Path $LogDir ($pfx + 'incidente_cobertura_fallback_' + $DateTag + '.json'))
}

# Leitura do gasto do dia. Ilegivel NAO vira zero: devolve ilegivel=$true e o saldo fecha.
function Read-VixCobFallbackGasto([string]$Path, [string]$DateTag = '') {
    $g = @{ versao = 1; data = $DateTag; execucoes = @{}; tentados = @{}; ilegivel = $false; ultima_falha = $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $g }
    $j = $null
    try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $g.ilegivel = $true; return $g }
    if ($null -eq $j) { return $g }
    if ($null -ne $j.PSObject.Properties['data']) { $g.data = '' + $j.data }
    if ($null -ne $j.PSObject.Properties['execucoes'] -and $null -ne $j.execucoes) {
        foreach ($p in @($j.execucoes.PSObject.Properties)) {
            $e = $p.Value
            $tok = [int64]0; $null = [int64]::TryParse(('' + (Get-VixCobDiariaCampo $e 'tokens')), [ref]$tok)
            $men = $true
            if ($null -ne (Get-VixCobDiariaCampo $e 'mensuravel')) { $men = [bool](Get-VixCobDiariaCampo $e 'mensuravel') }
            $g.execucoes[$p.Name] = @{ tokens = $tok; mensuravel = $men; dryrun = [bool](Get-VixCobDiariaCampo $e 'dryrun'); atualizado_em = ('' + (Get-VixCobDiariaCampo $e 'atualizado_em')) }
        }
    }
    if ($null -ne $j.PSObject.Properties['tentados'] -and $null -ne $j.tentados) {
        foreach ($p in @($j.tentados.PSObject.Properties)) { $g.tentados[$p.Name] = $p.Value }
    }
    if ($null -ne $j.PSObject.Properties['ultima_falha'] -and $null -ne $j.ultima_falha) {
        $g.ultima_falha = @{ classe = ('' + (Get-VixCobDiariaCampo $j.ultima_falha 'classe')); ts = ('' + (Get-VixCobDiariaCampo $j.ultima_falha 'ts')); execucao = ('' + (Get-VixCobDiariaCampo $j.ultima_falha 'execucao')) }
    }
    return $g
}

function Write-VixCobFallbackGasto([string]$Path, $Gasto) {
    $ex = [ordered]@{}
    foreach ($k in @(@($Gasto.execucoes.Keys) | Sort-Object)) { $ex[$k] = $Gasto.execucoes[$k] }
    $te = [ordered]@{}
    foreach ($k in @(@($Gasto.tentados.Keys) | Sort-Object)) { $te[$k] = $Gasto.tentados[$k] }
    $doc = [ordered]@{ versao = 1; data = $Gasto.data; atualizado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); ultima_falha = $Gasto.ultima_falha; execucoes = $ex; tentados = $te }
    $tmp = $Path + '.tmp-' + $PID
    [IO.File]::WriteAllText($tmp, ($doc | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, ($Path + '.bak')) } else { [IO.File]::Move($tmp, $Path) }
}

# Soma pura do gasto. Qualquer execucao nao mensuravel ou arquivo ilegivel fecha o saldo.
function Get-VixCobFallbackResumoGasto($Gasto) {
    $tot = [int64]0; $men = $true
    if ($null -eq $Gasto) { return @{ Gasto = [int64]0; Mensuravel = $true } }
    if ([bool]$Gasto.ilegivel) { $men = $false }
    foreach ($k in @($Gasto.execucoes.Keys)) {
        $e = $Gasto.execucoes[$k]
        $tot += [int64]$e.tokens
        if (-not [bool]$e.mensuravel) { $men = $false }
    }
    return @{ Gasto = $tot; Mensuravel = $men }
}

function Get-VixCobFallbackSaldo {
    param([int64]$Teto = 0, [int64]$Gasto = 0, [bool]$Mensuravel = $true)
    if ($Teto -le 0) { return [int64]0 }
    if (-not $Mensuravel) { return [int64]0 }
    $s = $Teto - $Gasto
    if ($s -lt 0) { return [int64]0 }
    return [int64]$s
}

# Grava o gasto ACUMULADO de uma execucao (monotono: nunca diminui) e marca os emissores enviados
# ao modelo como tentados hoje. Read-modify-write sob mutex proprio.
function Set-VixCobFallbackGastoExecucao {
    param([string]$Path, [string]$DateTag, [string]$Execucao, [int64]$Tokens = 0, [bool]$Mensuravel = $true, [bool]$DryRun = $false, [string[]]$Tentados = @(), [datetime]$Agora = (Get-Date), [string]$Falha = '$nulo')
    $mtx = New-Object System.Threading.Mutex($false, 'Global\vixradar-cobfallback-gasto-v1')
    $tem = $false
    try {
        try { $tem = $mtx.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $tem = $true }
        if (-not $tem) { throw 'mutex do gasto do fallback ocupado por mais de 30s' }
        $g = Read-VixCobFallbackGasto $Path $DateTag
        if ([bool]$g.ilegivel) { throw ('gasto do fallback ilegivel, nao sobrescrevo: ' + $Path) }
        if (-not $g.data) { $g.data = $DateTag }
        $iso = $Agora.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $ant = $null
        if ($g.execucoes.ContainsKey($Execucao)) { $ant = $g.execucoes[$Execucao] }
        $tok = $Tokens
        $men = $Mensuravel
        if ($null -ne $ant) {
            if ([int64]$ant.tokens -gt $tok) { $tok = [int64]$ant.tokens }
            if (-not [bool]$ant.mensuravel) { $men = $false }
        }
        $g.execucoes[$Execucao] = @{ tokens = [int64]$tok; mensuravel = [bool]$men; dryrun = [bool]$DryRun; atualizado_em = $iso }
        foreach ($t in @($Tentados)) {
            $nn = ('' + $t).Trim()
            if (-not $nn) { continue }
            $g.tentados[(ConvertTo-VixChaveEmissor $nn)] = [ordered]@{ empresa = $nn; ts = $iso; execucao = $Execucao; dryrun = [bool]$DryRun }
        }
        # Falha: '$nulo' = sem mudanca; '' = lote entregue, limpa a falha registrada; qualquer outra
        # coisa = classe da falha (cota, auth, modelo_indisponivel, transitoria) da execucao.
        if ($Falha -ne '$nulo') {
            if ($Falha -eq '') { $g.ultima_falha = $null } else { $g.ultima_falha = @{ classe = $Falha; ts = $iso; execucao = $Execucao } }
        }
        Write-VixCobFallbackGasto $Path $g
        return (Get-VixCobFallbackResumoGasto $g)
    } finally {
        if ($tem) { try { $mtx.ReleaseMutex() } catch { } }
        $mtx.Dispose()
    }
}

# Classe da falha do Claude, reutilizando Get-VixClasseFalhaProvider (libixradar-cobertura.ps1) sobre
# stdout+stderr+motivo da cota. Pura. ClaudeLimiteAtingido (entrada da cascata) so e verdadeiro para
# cota/429/limite de sessao: auth e modelo indisponivel sao falha, mas nao "limite".
function Get-VixCobFallbackFalhaClasse([string]$Texto) {
    $c = Get-VixClasseFalhaProvider $Texto
    # A regra unica cobre "hit your limit" mas nao a frase real da assinatura ("hit your session /
    # usage / weekly limit"), a mesma que Get-VixWsProbeClassificacao reconhece. Sem este reforco o
    # limite de sessao cairia em transitoria/auth e ClaudeLimiteAtingido ficaria falso.
    if (('' + $c.Classe) -ne 'modelo_indisponivel' -and ('' + $Texto) -match '(?i)hit your (session|usage|weekly) limit') { return 'cota' }
    return ('' + $c.Classe)
}

function Get-VixCobFallbackLimiteAtingido($Gasto) {
    if ($null -eq $Gasto -or $null -eq $Gasto.ultima_falha) { return $false }
    return ((('' + $Gasto.ultima_falha.classe).Trim()) -eq 'cota')
}

# Motivo gravado no ledger do emissor que o Claude NAO fechou. Estado PENDENTE_IA (a pergunta do dia
# segue aberta) e o fechamento o devolve como INSUFICIENCIA - nunca verificado.
function Get-VixCobFallbackMotivoPendente([string]$MotivoItem, [string]$Classe) {
    $c = ('' + $Classe).Trim()
    if (-not $c) { $c = 'sem_classe' }
    return ('claude_fallback_falhou:' + $MotivoItem + ':' + $c)
}

# Selecao pura dos alvos. So entra o que o relatorio DO DIA decidiu CLAUDE_FALLBACK; o ledger e
# relido para tirar quem ja fechou; quem o fallback ja enviou ao modelo hoje nao e repetido; o
# saldo e consumido na ordem do relatorio com o custo que a decisao estimou (tier dela).
function Select-VixCobFallbackAlvos {
    param($Relatorio = $null, $Ledger = $null, [string]$DateTag = '', [int64]$Saldo = 0, [hashtable]$Tentados = @{})
    $alvos = New-Object System.Collections.Generic.List[object]
    $fora = New-Object System.Collections.Generic.List[object]
    $out = @{ Candidatos = 0; Alvos = @(); Fora = @(); SaldoRestante = [int64]$Saldo; Motivo = 'ok' }
    if ($null -eq $Relatorio) { $out.Motivo = 'relatorio_ausente'; return $out }
    $dRel = '' + (Get-VixCobDiariaCampo $Relatorio 'data')
    if ($DateTag -and $dRel -ne $DateTag) { $out.Motivo = ('relatorio_de_outro_dia_' + $dRel); return $out }
    $restante = [int64]$Saldo
    $visto = @{}
    foreach ($p in @(Get-VixCobDiariaCampo $Relatorio 'proximos_passos')) {
        if ($null -eq $p) { continue }
        if (('' + (Get-VixCobDiariaCampo $p 'passo')) -ne 'CLAUDE_FALLBACK') { continue }
        $emp = ('' + (Get-VixCobDiariaCampo $p 'empresa')).Trim()
        if (-not $emp) { continue }
        $k = ConvertTo-VixChaveEmissor $emp
        if ($visto.ContainsKey($k)) { continue }
        $visto[$k] = $true
        $out.Candidatos++
        $tier = ('' + (Get-VixCobDiariaCampo $p 'tier')).Trim().ToUpperInvariant()
        $custo = [int64]0; $null = [int64]::TryParse(('' + (Get-VixCobDiariaCampo $p 'custo')), [ref]$custo)
        $estLedger = ''
        if ($null -ne $Ledger -and $Ledger.emissores.ContainsKey($k)) { $estLedger = '' + (Get-VixCobDiariaCampo $Ledger.emissores[$k] 'estado') }
        if ($script:VixCobDiariaTerminais -contains $estLedger) { $fora.Add([pscustomobject]@{ empresa = $emp; tier = $tier; custo = $custo; motivo = 'ja_verificado' }); continue }
        if ($Tentados.ContainsKey($k)) { $fora.Add([pscustomobject]@{ empresa = $emp; tier = $tier; custo = $custo; motivo = 'ja_tentado_hoje' }); continue }
        if ($custo -le 0 -or ($tier -ne 'FULL' -and $tier -ne 'BARATO')) { $fora.Add([pscustomobject]@{ empresa = $emp; tier = $tier; custo = $custo; motivo = 'custo_ou_tier_desconhecido_fail_closed' }); continue }
        if ($restante -lt $custo) { $fora.Add([pscustomobject]@{ empresa = $emp; tier = $tier; custo = $custo; motivo = 'saldo_claude_insuficiente' }); continue }
        $restante -= $custo
        $alvos.Add([pscustomobject]@{ empresa = $emp; tier = $tier; custo = $custo; estado = ('' + (Get-VixCobDiariaCampo $p 'estado')); motivo_passo = ('' + (Get-VixCobDiariaCampo $p 'motivo_passo')) })
    }
    $out.Alvos = $alvos.ToArray(); $out.Fora = $fora.ToArray(); $out.SaldoRestante = [int64]$restante
    if ($out.Candidatos -eq 0) { $out.Motivo = 'sem_pendente_claude_fallback' }
    elseif ($alvos.Count -eq 0) {
        $mot = @($fora | ForEach-Object { $_.motivo } | Sort-Object -Unique)
        $out.Motivo = ('nada_coube:' + ($mot -join ','))
    }
    return $out
}

function Write-VixCobFallbackIncidente {
    param([string]$LogDir, [string]$DateTag, [string]$Motivo, $Dados = $null, [bool]$DryRun = $false)
    $p = Get-VixCobFallbackIncidentePath $LogDir $DateTag $DryRun
    $doc = [ordered]@{ data = $DateTag; gerado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); tipo = 'COBFALLBACK_SEM_CAPACIDADE'; dryrun = [bool]$DryRun; motivo = $Motivo; detalhe = $Dados }
    [IO.File]::WriteAllText($p, ($doc | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    return $p
}

# Preparo do executor, em ordem de custo: nada que custe token roda antes de saber que ha alvo que
# cabe. Acao: INERTE (opt-in/teto ausente), NADA_A_FAZER (sem pendente decidido para o Claude, ou
# todos ja verificados), INCIDENTE (pendente decidido para o Claude e nada cabe - incidente local
# gravado), EXECUTAR (alvos prontos). AuthFn/SondaFn sao injetados: devolvem @{ ok; modo/motivo }.
# A sonda (session limit/429) so roda depois da auth, e as duas so rodam com alvo que cabe.
function Invoke-VixCobFallbackPreparo {
    param(
        [string]$LogDir, [string]$DateTag, [string]$FlagValor = '', [scriptblock]$AuthFn = $null, [scriptblock]$SondaFn = $null,
        [bool]$DryRun = $false, [hashtable]$Config = $null
    )
    $out = [ordered]@{ Acao = 'INERTE'; Motivo = ''; Teto = [int64]0; Gasto = [int64]0; Saldo = [int64]0; Candidatos = 0; Alvos = @(); Fora = @(); IncidentePath = ''; AuthModo = ''; Sonda = '' }
    if (-not (Test-VixCobFallbackFlag $FlagValor)) { $out.Motivo = 'flag_desligada'; return $out }
    $cfg = $Config
    if ($null -eq $cfg) { $cfg = Get-VixCobDiariaConfig $LogDir }
    $out.Teto = [int64]$cfg.CLAUDE_FALLBACK_DIA
    if ($out.Teto -le 0) { $out.Motivo = 'teto_claude_fallback_nao_declarado'; return $out }
    $relPath = Join-Path $LogDir ('cobertura_diaria_relatorio_' + $DateTag + '.json')
    $rel = $null
    if (-not (Test-Path -LiteralPath $relPath)) { $out.Acao = 'NADA_A_FAZER'; $out.Motivo = 'relatorio_ausente'; return $out }
    try { $rel = Get-Content -LiteralPath $relPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $out.Acao = 'NADA_A_FAZER'; $out.Motivo = 'relatorio_ilegivel'; return $out }
    $ledger = $null
    try { $ledger = Read-VixCobDiaria (Get-VixCobDiariaPath $LogDir $DateTag) $DateTag } catch { $out.Acao = 'NADA_A_FAZER'; $out.Motivo = 'ledger_ilegivel'; return $out }
    $g = Read-VixCobFallbackGasto (Get-VixCobFallbackGastoPath $LogDir $DateTag) $DateTag
    $rg = Get-VixCobFallbackResumoGasto $g
    $out.Gasto = [int64]$rg.Gasto
    $out.Saldo = Get-VixCobFallbackSaldo -Teto $out.Teto -Gasto $rg.Gasto -Mensuravel ([bool]$rg.Mensuravel)
    $sel = Select-VixCobFallbackAlvos -Relatorio $rel -Ledger $ledger -DateTag $DateTag -Saldo $out.Saldo -Tentados $g.tentados
    $out.Candidatos = [int]$sel.Candidatos; $out.Alvos = @($sel.Alvos); $out.Fora = @($sel.Fora)
    $detalhe = { [ordered]@{ teto = $out.Teto; gasto = $out.Gasto; saldo = $out.Saldo; gasto_mensuravel = [bool]$rg.Mensuravel; gasto_ilegivel = [bool]$g.ilegivel; candidatos = $out.Candidatos; alvos = @($out.Alvos); fora = @($out.Fora); auth_modo = $out.AuthModo; sonda = $out.Sonda } }
    if ($sel.Candidatos -eq 0) { $out.Acao = 'NADA_A_FAZER'; $out.Motivo = $sel.Motivo; return $out }
    if (@($sel.Alvos).Count -eq 0) {
        $naoVerif = @($sel.Fora | Where-Object { $_.motivo -ne 'ja_verificado' })
        if ($naoVerif.Count -eq 0) { $out.Acao = 'NADA_A_FAZER'; $out.Motivo = 'todos_ja_verificados'; return $out }
        $m = $sel.Motivo
        if (-not [bool]$rg.Mensuravel) { $m = $m + ':gasto_nao_mensuravel' }
        $out.Acao = 'INCIDENTE'; $out.Motivo = $m
        $out.IncidentePath = Write-VixCobFallbackIncidente -LogDir $LogDir -DateTag $DateTag -Motivo $m -Dados (& $detalhe) -DryRun $DryRun
        return $out
    }
    $au = $null
    if ($null -ne $AuthFn) { try { $au = & $AuthFn } catch { $au = @{ ok = $false; modo = 'excecao'; motivo = $_.Exception.Message } } }
    if ($null -eq $au) { $au = @{ ok = $false; modo = 'sem_authfn'; motivo = 'sem_authfn' } }
    $out.AuthModo = '' + $au.modo
    if (-not [bool]$au.ok) {
        $out.Acao = 'INCIDENTE'; $out.Motivo = ('assinatura_indisponivel_' + $out.AuthModo)
        $out.IncidentePath = Write-VixCobFallbackIncidente -LogDir $LogDir -DateTag $DateTag -Motivo $out.Motivo -Dados (& $detalhe) -DryRun $DryRun
        return $out
    }
    $so = $null
    if ($null -ne $SondaFn) { try { $so = & $SondaFn } catch { $so = @{ ok = $false; motivo = 'excecao' } } }
    if ($null -eq $so) { $so = @{ ok = $false; motivo = 'sem_sondafn' } }
    $out.Sonda = '' + $so.motivo
    if (-not [bool]$so.ok) {
        $ms = ('' + $so.motivo)
        if ($ms -eq 'session_limit' -or $ms -eq 'rate_limit_transitorio') { $out.Motivo = ('claude_no_limite_' + $ms) } else { $out.Motivo = ('sonda_falhou_' + $ms) }
        $out.Acao = 'INCIDENTE'
        # Limite/429 da assinatura vira estado do dia: o fechamento le e passa ClaudeLimiteAtingido
        # para a cascata (INSUFICIENCIA em vez de sucesso). Falha de escrita nao esconde o incidente.
        if ($ms -eq 'session_limit' -or $ms -eq 'rate_limit_transitorio') {
            try { $null = Set-VixCobFallbackGastoExecucao -Path (Get-VixCobFallbackGastoPath $LogDir $DateTag) -DateTag $DateTag -Execucao 'sonda' -Tokens 0 -DryRun $DryRun -Falha 'cota' } catch { $out.Motivo = $out.Motivo + ':gasto_nao_gravado' }
        }
        $out.IncidentePath = Write-VixCobFallbackIncidente -LogDir $LogDir -DateTag $DateTag -Motivo $out.Motivo -Dados (& $detalhe) -DryRun $DryRun
        return $out
    }
    $out.Acao = 'EXECUTAR'; $out.Motivo = ('alvos_' + @($sel.Alvos).Count + '_de_' + $sel.Candidatos)
    return $out
}
