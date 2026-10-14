# vixradar-cobertura.ps1 - cobertura analitica: consumo do Codex, orcamento por emissor,
# provedor indisponivel, classificacao OK/PARCIAL/FALHA e fila persistente de pendencias.
# PowerShell 5.1, ASCII puro, dot-source: . (Join-Path $PSScriptRoot 'lib\vixradar-cobertura.ps1')
#
# COBERTURA-13OUT1 (2026-10-13). Evidencia do dia 13/10/2026:
#   matinal  445.955 tokens para 4 emissores (111k por emissor), 17 DEFERIDO, FIM "OK".
#   estimativa pre-lote do motor: 61.000 para o mesmo lote (7,3x abaixo do real).
#   sentinela: CAP_USO_DESCONHECIDO nos dois lotes Codex, FIM "tokens=0 ... resultado=OK".
# Causas provadas (codex debug prompt-input, sem chamada de modelo):
#   1. cada chamada do Codex carregava 50.309 caracteres de contexto do host que a rotina
#      nao usa: catalogo de 260+ skills (22.222), instrucoes de permissao (9.060), apps,
#      plugins e plugins recomendados (2.601) e o AGENTS.md global (12.844). O agente reenvia
#      esse bloco em CADA passo do laco de busca (16 buscas no lote de 13/10). O
#      features.skip_host_skill_discovery=true que o motor ja passava NAO remove o catalogo
#      (feature "under development" no codex-cli 0.160.1, medido).
#   2. o AGENTS.md global manda invocar task-observer/prompt-refinery/humanizer; o modelo
#      tenta ler os SKILL.md por shell e o sandbox recusa (matinal_stderr_20261013_26032.txt).
#   3. a sentinela nunca lia o usage do JSONL do Codex: o envelope montado nao tinha usage,
#      todo lote saia "sem usage" e o FIM gravava tokens=0, que o circuito do dia somava
#      como zero.

# ---------------------------------------------------------------------------------------
# 1. Argumentos do Codex: contexto minimo para rotina headless
# ---------------------------------------------------------------------------------------
# Cada override foi medido com `codex -c ... debug prompt-input` (50.309 -> 14.468 chars).
# Nenhum deles mexe no sandbox: read-only, --ignore-user-config e --ignore-rules continuam
# no chamador. A ferramenta web_search vem de --search, que tambem continua no chamador.
function Get-VixCodexArgsBase {
    return @(
        '-c', 'features.skip_host_skill_discovery=true',
        '-c', 'skills.include_instructions=false',
        '-c', 'include_permissions_instructions=false',
        '-c', 'include_apps_instructions=false',
        '-c', 'features.plugins=false',
        '-c', 'features.apps=false',
        '-c', 'features.tool_suggest=false',
        '-c', 'features.remote_plugin=false',
        '-c', 'features.recommended_plugins=false'
    )
}

# O AGENTS.md global do usuario nao tem chave de config que o desligue (testadas
# project_doc_max_bytes=0, agents_md.*, include_user_instructions: nenhuma remove). Este
# preambulo vai no topo do prompt da rotina e neutraliza as instrucoes de fluxo interativo,
# que eram o que disparava a leitura de SKILL.md por shell.
function Get-VixCodexPreambulo {
    return ('ROTINA HEADLESS AGENDADA. Instrucoes de AGENTS.md sobre skills, task-observer, ' +
        'prompt-refinery, humanizer, memoria de sessao ou fluxo interativo NAO se aplicam a esta ' +
        'execucao: nao leia arquivos, nao execute comandos de shell, nao invoque skills. ' +
        'Ferramentas permitidas: somente web_search e abertura de pagina. Siga apenas o protocolo abaixo.')
}

# ---------------------------------------------------------------------------------------
# 2. Consumo do Codex (codex exec --json)
# ---------------------------------------------------------------------------------------
# O Codex publica `turn.completed` com usage {input_tokens, cached_input_tokens,
# output_tokens, reasoning_output_tokens}. input_tokens JA INCLUI cached_input_tokens.
# Soma todos os eventos com usage (exec pode ter mais de um turno). Sem evento com usage,
# mensuravel=$false: o chamador NUNCA pode tratar isso como zero.
function Get-VixCodexUsageJsonl($Linhas) {
    $r = @{ mensuravel = $false; eventos = 0; input_total = [int64]0; cached = [int64]0; output = [int64]0; reasoning = [int64]0 }
    foreach ($linha in @($Linhas)) {
        $t = ('' + $linha).Trim()
        if (-not $t.StartsWith('{')) { continue }
        $obj = $null
        try { $obj = $t | ConvertFrom-Json } catch { continue }
        if ($null -eq $obj -or $null -eq $obj.PSObject.Properties['usage'] -or $null -eq $obj.usage) { continue }
        $u = $obj.usage
        if ($null -eq $u.PSObject.Properties['input_tokens'] -or $null -eq $u.PSObject.Properties['output_tokens']) { continue }
        $in = [int64]0; $out = [int64]0; $cac = [int64]0; $rea = [int64]0
        if (-not [int64]::TryParse(('' + $u.input_tokens), [ref]$in)) { continue }
        if (-not [int64]::TryParse(('' + $u.output_tokens), [ref]$out)) { continue }
        if ($u.PSObject.Properties['cached_input_tokens']) { [void][int64]::TryParse(('' + $u.cached_input_tokens), [ref]$cac) }
        elseif ($u.PSObject.Properties['cache_read_input_tokens']) { [void][int64]::TryParse(('' + $u.cache_read_input_tokens), [ref]$cac) }
        if ($u.PSObject.Properties['reasoning_output_tokens']) { [void][int64]::TryParse(('' + $u.reasoning_output_tokens), [ref]$rea) }
        if ($in -lt 0 -or $out -lt 0 -or $cac -lt 0 -or $cac -gt $in) { continue }
        $r.eventos++
        $r.input_total += $in; $r.cached += $cac; $r.output += $out; $r.reasoning += $rea
    }
    if ($r.eventos -gt 0) { $r.mensuravel = $true }
    return $r
}

# Parcelas na regua do circuito (REGUA-UNICA1). Conservador de proposito: o input em cache
# do Codex CONTINUA dentro de `input`/`trabalho` (o motor ja contava assim e o teto do dia
# foi calibrado nessa base; tirar o cache agora afrouxaria o limite sem decisao do operador).
# O cache sai em campo proprio (`codex_cached`) so para medicao.
function ConvertTo-VixParcelasCodex($Uso) {
    if (-not $Uso -or -not $Uso.mensuravel) { return $null }
    $trab = [int64]$Uso.input_total + [int64]$Uso.output
    # CACHECODEX-VISIVEL1 (2026-10-13): o cache do Codex entra como PARCELA PROPRIA (`cache_codex`)
    # e continua contando cheio no `trabalho`. Antes ele so existia no campo `codex_cached_input` da
    # linha FIM, que a lib de custo nao le: o dia via `tokens_cache_read = 0` para o provedor codex
    # enquanto 129.408 dos 167.768 tokens de uma escalada real eram cache (medido na sonda matinal de
    # 13/10). Resultado pratico: nao dava para separar consumo efetivo de cache no fechamento do dia,
    # que e exatamente a conta que decide se ha folga. A regua NAO muda - `trabalho` segue somando o
    # cache, de proposito, porque o cap tem de ser conservador; o que passa a existir e a VISIBILIDADE
    # da parcela, para o operador ver quanto do numero do cap e cache e nao trabalho novo.
    return @{ input = [int64]$Uso.input_total; output = [int64]$Uso.output; cache_creation = [int64]0; cache_read = [int64]0; cache_codex = [int64]$Uso.cached; trabalho = $trab; codex_cached = [int64]$Uso.cached; codex_reasoning = [int64]$Uso.reasoning }
}

# ---------------------------------------------------------------------------------------
# 3. Orcamento por emissor e quantos emissores cabem no que sobra do cap
# ---------------------------------------------------------------------------------------
# Custo default por emissor no Codex = mediana medida em outubro/2026 (lotes_detalhe dos
# metrics: 266k, 249k, 210k, 252k, 111k, 266k, 135k por emissor -> mediana 249k). E o
# piso de prudencia ate existir medicao do proprio provedor com o contexto enxuto.
$script:VixCustoEmissorDefaultCodex = [int64]250000

# Custo por emissor MEDIDO pela propria sentinela, persistido entre execucoes. Sem isso a
# sentinela nao tem historico (ela nao grava metrics com lotes_detalhe) e cada dia voltaria ao
# default, repetindo a calibracao e o estouro. Medido em 13/10 17:25: 1 emissor custou 156.293
# contra cap 120.000 (CAP_EXCEDIDO). Com este registro a execucao seguinte ja sabe e defere.
function Get-VixCustoSentinelaPath([string]$LogDir) { return (Join-Path $LogDir 'sentinela_custo_emissor.jsonl') }
function Add-VixCustoSentinela([string]$LogDir, [string]$Provider, [int64]$CustoEmissor, [int]$Emissores, [string]$Lote, [datetime]$Agora = (Get-Date)) {
    if ($CustoEmissor -le 0 -or $Emissores -le 0) { return }
    $linha = ([ordered]@{ ts = $Agora.ToString('s'); provider = $Provider; custo_emissor = $CustoEmissor; emissores = $Emissores; lote = $Lote } | ConvertTo-Json -Compress)
    [System.IO.File]::AppendAllText((Get-VixCustoSentinelaPath $LogDir), $linha + "`n", (New-Object System.Text.UTF8Encoding($false)))
}
function Get-VixHistoricoCustoSentinela([string]$LogDir, [string]$Provider, [int]$Dias = 7, [datetime]$Agora = (Get-Date)) {
    $path = Get-VixCustoSentinelaPath $LogDir
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $corte = $Agora.AddDays(-1 * $Dias)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($l in @(Get-Content -LiteralPath $path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if (-not ('' + $l).Trim()) { continue }
        $r = $null
        try { $r = $l | ConvertFrom-Json } catch { continue }
        if (('' + $r.provider) -ne $Provider) { continue }
        # ConvertFrom-Json (PS 5.1 e 7) ja entrega `ts` como DateTime; reconverter por texto
        # depende da cultura da maquina e falha (medido em 13/10 com pt-BR).
        $t = [datetime]::MinValue
        if ($r.ts -is [datetime]) { $t = $r.ts }
        elseif (-not [datetime]::TryParseExact(('' + $r.ts), 's', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$t)) { continue }
        if ($t -lt $corte) { continue }
        $v = [int64]0
        if ([int64]::TryParse(('' + $r.custo_emissor), [ref]$v) -and $v -gt 0) { $out.Add($v) }
    }
    return $out.ToArray()
}

# CALIBRACAO CONTROLADA (substitui o default limitado ao cap de 13/10, que mascarava a estimativa).
# A estimativa fica HONESTA (250k sem medicao) e o cap nao muda. Quando ela nao cabe no cap e nao
# existe nenhuma medicao do provedor, a execucao pode rodar UM emissor de calibracao, desde que:
# (1) a execucao esteja zerada, (2) nao tenha havido calibracao no dia (marcador em disco, gravado
# ANTES do lote para um crash nao repetir), (3) o orcamento do dia disponivel para a sentinela
# cubra a estimativa inteira e (4) a fonte seja 'default' (qualquer medicao ou historico vale mais
# que a excecao). O risco, estourar o cap de 120k por 1 emissor, fica declarado e limitado a 1 por dia.
function Get-VixCalibracaoPath([string]$LogDir, [string]$DateTag) { return (Join-Path $LogDir ('sentinela_calibracao_' + $DateTag + '.json')) }
function Get-VixDecisaoCapSentinela([int64]$Acum, [int64]$Cap, [int64]$CustoEstimado, [string]$Fonte, [int]$Chunk, [int64]$DisponivelDia = -1, [bool]$CalibracaoJaFeita = $false) {
    $cabem = Get-VixEmissoresQueCabem -Acum $Acum -Cap $Cap -CustoPorEmissor $CustoEstimado -Chunk $Chunk
    if ($cabem -gt 0) { return @{ Cabem = $cabem; Calibracao = $false; Motivo = 'cabe_no_cap' } }
    if ($Chunk -le 0) { return @{ Cabem = 0; Calibracao = $false; Motivo = 'lote_vazio' } }
    if ($Fonte -ne 'default') { return @{ Cabem = 0; Calibracao = $false; Motivo = 'custo_medido_nao_cabe_no_cap' } }
    if ($Acum -gt 0) { return @{ Cabem = 0; Calibracao = $false; Motivo = 'execucao_ja_gastou' } }
    if ($CalibracaoJaFeita) { return @{ Cabem = 0; Calibracao = $false; Motivo = 'calibracao_ja_feita_hoje' } }
    if ($DisponivelDia -lt 0) { return @{ Cabem = 0; Calibracao = $false; Motivo = 'orcamento_dia_desconhecido' } }
    if ($DisponivelDia -lt $CustoEstimado) { return @{ Cabem = 0; Calibracao = $false; Motivo = 'orcamento_dia_menor_que_estimativa' } }
    return @{ Cabem = 1; Calibracao = $true; Motivo = 'calibracao_1_emissor' }
}

# ORCAMENTOFIN1 (2026-10-14): desfecho da SENTINELA em funcao pura, para o teste exercitar a
# MESMA regra que a producao usa (licao da CORRECAO 5: guarda que nao exercita o codigo do
# pipeline nao e guarda).
#
# O defeito que isto fecha: a execucao que NAO conseguiu disparar NENHUM lote por falta de
# orcamento saia PARCIAL/exit 10 com tokens=0, analisados=0 e deferidos=8 - medido em
# 13/10/2026 (cap da execucao 17.112 contra custo medido de 156.293). O Agendador marcava a
# task como falha e o monitor lia ENTREGA_PARCIAL, que ele mesmo descreve como "a rotina rodou
# e entregou parte" - o que nao aconteceu. O estado correto para esse caso e o MESMO que o
# circuito fechado ja usa (SEM_ORCAMENTO, exit 0), com os emissores preservados na fila
# pendente e backlog=True.
#
# PARCIAL/exit 10 continua valendo, sem nenhuma mudanca, para toda execucao que gastou token,
# analisou, entregou em parte, ou deferiu por motivo que NAO seja orcamento (tempo, uso
# desconhecido, disjuntor de provedor) - e para o excedente do teto do Worker.
function Get-VixSentinelaResultado {
    param(
        [int]$LotesOk = 0,
        [int]$LotesFalhaProvider = 0,
        [int]$SubmitOk = 0,
        [int]$SubmitFail = 0,
        [int]$SemResultado = 0,
        [int64]$TokensAcum = 0,
        [int]$Deferidos = 0,
        [int]$DeferidosOrcamento = 0,
        [int]$DeferidosOutros = 0,
        [int]$Excedente = 0
    )
    $lotesIntentados = $LotesOk + $LotesFalhaProvider
    # Trabalho zero: nenhum lote processado, nenhum submit, nenhum lote sem resultado e nada
    # gasto. E o estado em que a execucao nao tentou - nao o estado em que ela tentou e nao
    # concluiu.
    $trabalhoZero = (($LotesOk -eq 0) -and ($LotesFalhaProvider -eq 0) -and ($SubmitOk -eq 0) -and ($SubmitFail -eq 0) -and ($SemResultado -eq 0) -and ($TokensAcum -eq 0))
    if ($trabalhoZero -and $DeferidosOrcamento -gt 0 -and $DeferidosOutros -eq 0) {
        return @{ Resultado = 'SEM_ORCAMENTO'; Exit = 0; Motivo = 'cap_sentinela_sem_orcamento' }
    }
    if ($lotesIntentados -gt 0 -and $LotesOk -eq 0 -and $LotesFalhaProvider -gt 0) {
        return @{ Resultado = 'FALLO_PROVEEDOR'; Exit = 9; Motivo = 'todos_os_lotes_falharam_por_provedor' }
    }
    if ($SemResultado -gt 0 -or $SubmitFail -gt 0 -or $Deferidos -gt 0 -or $Excedente -gt 0) {
        return @{ Resultado = 'PARCIAL'; Exit = 10; Motivo = 'cobertura_incompleta' }
    }
    return @{ Resultado = 'OK'; Exit = 0; Motivo = 'sem_gatilho_ou_cobertura_completa' }
}

function Get-VixMediana([object[]]$Valores) {
    $v = @($Valores | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
    if ($v.Count -eq 0) { return $null }
    $m = [int]([Math]::Floor($v.Count / 2))
    if (($v.Count % 2) -eq 1) { return [int64][Math]::Ceiling($v[$m]) }
    return [int64][Math]::Ceiling(($v[$m - 1] + $v[$m]) / 2)
}

# Historico por emissor do MESMO provedor, lido dos metrics que gravam `provider`.
# Arquivo sem `provider` (legado, contexto antigo) nao entra: a regua tem que ser a mesma
# configuracao que vai rodar agora.
function Get-VixHistoricoCustoPorEmissor([string]$LogDir, [string]$Provider, [int]$Dias = 7, [datetime]$Agora = (Get-Date)) {
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $LogDir -or -not (Test-Path -LiteralPath $LogDir)) { return @() }
    $corte = $Agora.Date.AddDays(-1 * $Dias)
    foreach ($f in @(Get-ChildItem -LiteralPath $LogDir -Filter '*_metrics_*.json' -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -match 'verificacao|agenda') { continue }
        # ORCAMENTO-CLASSE1 (2026-10-14): arquivo de DRY-RUN fica FORA do historico de custo.
        # Ele e medicao dirigida (-MaxEmissores), nao lote de producao: as tres amostras baratas
        # que derrubaram a mediana de 14/10 (7.870 / 10.946 / 21.250 por emissor) eram todas
        # `_dryrun_`. Medir o proximo lote por um lote que nao vai existir subestima o cap.
        if ($f.Name -match '_dryrun') { continue }
        if ($f.Name -notmatch '_metrics_(\d{8})') { continue }
        $d = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($Matches[1], 'yyyyMMdd', $null, [Globalization.DateTimeStyles]::None, [ref]$d)) { continue }
        if ($d -lt $corte) { continue }
        $m = $null
        try { $m = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $m -or -not $m.PSObject.Properties['provider'] -or ('' + $m.provider) -ne $Provider) { continue }
        foreach ($l in @($m.lotes_detalhe)) {
            if ($null -eq $l) { continue }
            $n = 0; $t = [int64]0
            if (-not [int]::TryParse(('' + $l.emissores), [ref]$n) -or $n -le 0) { continue }
            if (-not [int64]::TryParse(('' + $l.trabalho), [ref]$t) -or $t -le 0) { continue }
            $out.Add([int64][Math]::Ceiling($t / $n))
        }
    }
    return $out.ToArray()
}

# Regra: o que esta execucao ja mediu vence (maximo, nao media: um lote caro basta para
# provar que o proximo pode ser caro). Sem medicao propria, mediana do historico do mesmo
# provedor (>=2 amostras). Sem historico, o default. Nunca abaixo do piso da estimativa
# antiga do perfil, para que provedor barato nao afrouxe nada que ja existia.
function Get-VixCustoPorEmissor([object[]]$ObservadosExecucao, [object[]]$Historico, [int64]$Default, [int64]$Piso = 0, [object[]]$HistoricoProprio = @()) {
    $obs = @($ObservadosExecucao | Where-Object { $null -ne $_ -and [double]$_ -gt 0 })
    $prop = @($HistoricoProprio | Where-Object { $null -ne $_ -and [double]$_ -gt 0 })
    $fonte = 'default'
    $valor = [int64]$Default
    if ($obs.Count -gt 0) {
        $valor = [int64][Math]::Ceiling(($obs | Measure-Object -Maximum).Maximum)
        $fonte = 'observado_execucao'
    } elseif ($prop.Count -gt 0) {
        # Historico da PROPRIA rotina (ex.: sentinela): 1 amostra ja basta e vale o MAXIMO, nao a
        # mediana, porque o objetivo e nao repetir um estouro ja medido.
        $valor = [int64][Math]::Ceiling(($prop | Measure-Object -Maximum).Maximum)
        $fonte = 'historico_proprio_max_n' + $prop.Count
    } else {
        $hist = @($Historico | Where-Object { $null -ne $_ -and [double]$_ -gt 0 })
        if ($hist.Count -ge 2) { $valor = Get-VixMediana $hist; $fonte = 'historico_mediana_n' + $hist.Count }
    }
    if ($valor -lt $Piso) { $valor = $Piso; $fonte = $fonte + '+piso' }
    return @{ Custo = [int64]$valor; Fonte = $fonte }
}

# Quantos emissores do lote cabem no que sobra do cap. 0 = nenhum (lote inteiro deferido).
function Get-VixEmissoresQueCabem([int64]$Acum, [int64]$Cap, [int64]$CustoPorEmissor, [int]$Chunk) {
    if ($Chunk -le 0) { return 0 }
    $resto = $Cap - $Acum
    if ($resto -le 0) { return 0 }
    if ($CustoPorEmissor -le 0) { return $Chunk }
    $k = [int][Math]::Floor($resto / [double]$CustoPorEmissor)
    if ($k -gt $Chunk) { $k = $Chunk }
    if ($k -lt 0) { $k = 0 }
    return $k
}

# ---------------------------------------------------------------------------------------
# 3b. ESTIMATIVA POR CLASSE DE LOTE + ADMISSAO FAIL-CLOSED (ORCAMENTO-CLASSE1, 2026-10-14)
# ---------------------------------------------------------------------------------------
# DEFEITO MEDIDO (noturna manual de 14/10/2026, 02:28-02:46 BRT): o lote FULL de 16 emissores
# foi admitido com estimativa de 497.104 tokens (`custo_emissor=31.069`, fonte
# `historico_mediana_n5+piso`) e custou 1.193.101 contra cap de 700.000 - 2,4x a estimativa -
# fechando o dia com `cap_excedido=1`. Duas causas independentes, as duas visiveis no metrics:
#   (1) CLASSE DE LOTE MISTURADA. O mesmo provedor roda lote BARATO (coletor, sem ferramenta:
#       7.870 a 21.250 por emissor em 13/10) e lote FULL (com ferramenta: 178.306 por emissor
#       em 13/10 e 74.569 em 14/10). `Get-VixHistoricoCustoPorEmissor` devolvia as duas
#       populacoes numa lista so e a MEDIANA de 5 amostras (7.870 / 10.946 / 21.250 / 167.768 /
#       178.306) caiu em 21.250 - um lote barato -, subestimando o FULL por 8x antes do piso.
#   (2) DRY-RUN NO HISTORICO. As tres amostras baratas eram de arquivos `_dryrun_`, medicao
#       dirigida com `-MaxEmissores`, nunca lote de producao.
# Correcao: modelo de custo POR CLASSE, com dois parametros (fixo por chamada + variavel por
# emissor) ajustado como ENVELOPE SUPERIOR de todas as amostras da classe - nunca a mediana.
# A estimativa de um lote nunca fica abaixo de nenhuma medicao da classe e leva margem
# declarada. Lote cuja estimativa conservadora nao cabe no saldo NAO e admitido: encolhe
# (fragmentacao adaptativa) ou defere. Nada de elevar teto, zerar contador nem esconder
# estouro inevitavel do provedor.

$script:VixMargemLoteClasse = 1.25

# Classe de custo do lote. Nao e o rotulo do tier: a MATINAL rotula os proprios lotes como FULL
# mas roda sem ferramenta (pacote barato), e a escalada e FULL com ferramenta por evidencia do
# dia. Quem sabe a classe e o chamador; a funcao so normaliza.
function Get-VixClasseLote {
    param([string]$Tier = 'LIGHT', [bool]$Barato = $false, [bool]$Escalada = $false)
    if ($Escalada) { return 'ESCALADA' }
    if ($Barato) { return 'BARATO' }
    $t = ('' + $Tier).Trim().ToUpperInvariant()
    if ($t -eq 'LIGHT') { return 'LIGHT' }
    return 'FULL'
}

function Get-VixAmostraCampo($Amostra, [string]$Nome) {
    if ($null -eq $Amostra) { return $null }
    if ($Amostra -is [System.Collections.IDictionary]) { return $Amostra[$Nome] }
    if ($null -ne $Amostra.PSObject.Properties[$Nome]) { return $Amostra.$Nome }
    return $null
}

# Amostras de UMA classe do provedor. Arquivo `_dryrun` fica fora (nao e lote de producao) e
# amostra sem campo `classe` usa o `fila` do metrics (full/light/escalada) - a taxonomia que o
# motor ja grava. `trabalho` nao numerico (NAO_MENSURAVEL) nao entra.
function Get-VixHistoricoCustoClasse([string]$LogDir, [string]$Provider, [string]$Classe, [int]$Dias = 7, [datetime]$Agora = (Get-Date)) {
    $alvo = ('' + $Classe).Trim().ToUpperInvariant()
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $LogDir -or -not (Test-Path -LiteralPath $LogDir)) { return $out.ToArray() }
    $corte = $Agora.Date.AddDays(-1 * $Dias)
    foreach ($f in @(Get-ChildItem -LiteralPath $LogDir -Filter '*_metrics_*.json' -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -match 'verificacao|agenda') { continue }
        if ($f.Name -match '_dryrun') { continue }
        if ($f.Name -notmatch '_metrics_(\d{8})') { continue }
        $d = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($Matches[1], 'yyyyMMdd', $null, [Globalization.DateTimeStyles]::None, [ref]$d)) { continue }
        if ($d -lt $corte) { continue }
        $m = $null
        try { $m = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        if (-not $m -or -not $m.PSObject.Properties['provider'] -or ('' + $m.provider) -ne $Provider) { continue }
        foreach ($l in @($m.lotes_detalhe)) {
            if ($null -eq $l) { continue }
            $cls = ''
            if ($null -ne $l.PSObject.Properties['classe']) { $cls = ('' + $l.classe).Trim().ToUpperInvariant() }
            else {
                $fl = ''
                if ($null -ne $l.PSObject.Properties['fila']) { $fl = ('' + $l.fila).Trim().ToLowerInvariant() }
                if ($fl -eq 'escalada') { $cls = 'ESCALADA' } elseif ($fl -eq 'light') { $cls = 'LIGHT' } elseif ($fl -eq 'full') { $cls = 'FULL' }
            }
            if ($cls -ne $alvo) { continue }
            $n = 0; $t = [int64]0
            if (-not [int]::TryParse(('' + $l.emissores), [ref]$n) -or $n -le 0) { continue }
            if (-not [int64]::TryParse(('' + $l.trabalho), [ref]$t) -or $t -le 0) { continue }
            $out.Add(@{ emissores = $n; trabalho = $t; per_emissor = [int64][Math]::Ceiling([double]$t / [double]$n) })
        }
    }
    return $out.ToArray()
}

# Envelope superior de custo da classe: custo(n) = a + b*n, com b = MAIOR coeficiente angular
# entre dois tamanhos distintos observados e a = maior residuo compativel com TODAS as amostras.
# Propriedade garantida (provada no teste): a + b*n >= trabalho de CADA amostra. Ou seja, o
# modelo nunca estima abaixo de um lote ja medido da mesma classe. Sem escala observada (uma
# amostra, ou lotes do mesmo tamanho) a inclinacao vira o PIOR custo por emissor observado - o
# lado seguro do erro. Sem amostra nenhuma, o default do provedor.
function Get-VixModeloLoteClasse {
    param(
        [object[]]$Amostras = @(),
        [int64]$DefaultEmissor = 0,
        [int64]$PisoEmissor = 0,
        [double]$Margem = -1
    )
    $mg = $Margem
    if ($mg -lt 1) { $mg = [double]$script:VixMargemLoteClasse }
    if ($mg -lt 1) { $mg = 1.0 }
    $am = New-Object System.Collections.Generic.List[object]
    foreach ($x in @($Amostras)) {
        $n = 0; $t = [int64]0
        if (-not [int]::TryParse(('' + (Get-VixAmostraCampo $x 'emissores')), [ref]$n) -or $n -le 0) { continue }
        if (-not [int64]::TryParse(('' + (Get-VixAmostraCampo $x 'trabalho')), [ref]$t) -or $t -le 0) { continue }
        $am.Add(@{ emissores = $n; trabalho = $t })
    }
    $a0 = 0.0; $b = 0.0; $fonte = 'default'
    if ($am.Count -eq 0) {
        $b = [double]$DefaultEmissor
        $fonte = 'default'
    } else {
        $bMax = 0.0
        for ($i = 0; $i -lt $am.Count; $i++) {
            for ($j = 0; $j -lt $am.Count; $j++) {
                if ($i -eq $j) { continue }
                $ni = [int]$am[$i]['emissores']; $nj = [int]$am[$j]['emissores']
                if ($ni -le $nj) { continue }
                $s = ([double]$am[$i]['trabalho'] - [double]$am[$j]['trabalho']) / [double]($ni - $nj)
                if ($s -gt $bMax) { $bMax = $s }
            }
        }
        if ($bMax -le 0) {
            foreach ($x in $am) {
                $pe = [double]$x['trabalho'] / [double]$x['emissores']
                if ($pe -gt $bMax) { $bMax = $pe }
            }
        }
        $b = $bMax
        foreach ($x in $am) {
            $i0 = [double]$x['trabalho'] - ($b * [double]$x['emissores'])
            if ($i0 -gt $a0) { $a0 = $i0 }
        }
        $fonte = 'classe_n' + $am.Count
    }
    # Tamanho do MENOR lote ja medido da classe. Nao e decoracao: com os parametros ajustados
    # numa unica amostra o envelope passa pela origem e o custo por emissor fica constante - o
    # que vale para o tamanho medido e MENTE para lote MENOR que ele. Medido em 14/10: o envelope
    # do lote de 2 estimava 222.883 para 1 emissor, enquanto o ajuste do dia real (237.117 fixos
    # + 59.749 por emissor) da 296.866. Encolher abaixo do medido e exatamente o caminho pelo qual
    # a estimativa voltaria a mentir; por isso a admissao nunca encolhe abaixo daqui.
    $nMin = 0; $tMin = [int64]0
    foreach ($x in $am) {
        if ($nMin -eq 0 -or [int]$x['emissores'] -lt $nMin) { $nMin = [int]$x['emissores']; $tMin = [int64]$x['trabalho'] }
    }
    return @{
        a = $a0; b = $b; margem = $mg; fonte = $fonte; n_amostras = $am.Count
        n_min = $nMin; t_min = $tMin
        piso_emissor = [int64]$PisoEmissor; default_emissor = [int64]$DefaultEmissor
    }
}

function Get-VixEstimativaLoteClasse {
    param($Modelo, [int]$Emissores = 0, [double]$Margem = -1)
    if ($null -eq $Modelo -or $Emissores -le 0) { return [int64]0 }
    $mg = $Margem
    if ($mg -lt 1) { $mg = [double]$Modelo.margem }
    if ($mg -lt 1) { $mg = 1.0 }
    $bruto = ((([double]$Modelo.a) + (([double]$Modelo.b) * [double]$Emissores)) * $mg)
    $piso = ([double]$Modelo.piso_emissor) * [double]$Emissores
    if ($piso -gt $bruto) { $bruto = $piso }
    return [int64][Math]::Ceiling($bruto)
}

# Par (custo por emissor, estimativa do lote, fonte) para o log. O campo `custo_emissor` do
# log continua significando custo por emissor, agora HONESTO para o tamanho do lote: em um
# envelope com custo fixo, dividir o total pelo numero de emissores do lote cheio e um numero
# que nao vale para um lote menor - e foi com esse numero que 14/10 estourou.
function Get-VixEstimativaClasseResumo {
    param($Modelo, [int]$Emissores = 0)
    $est = Get-VixEstimativaLoteClasse -Modelo $Modelo -Emissores $Emissores
    $pe = [int64]0
    if ($Emissores -gt 0) { $pe = [int64][Math]::Ceiling([double]$est / [double]$Emissores) }
    $fonte = ''
    if ($null -ne $Modelo) { $fonte = '' + $Modelo.fonte }
    if ($null -ne $Modelo -and [double]$Modelo.margem -gt 1) { $fonte = $fonte + '+margem' + [int][Math]::Round(([double]$Modelo.margem * 100)) }
    return @{ Custo = $pe; Est = $est; Fonte = $fonte }
}

# Quantos emissores cabem no saldo, com o ENVELOPE do lote - nao com um custo por emissor
# constante. A diferenca e material: em um envelope com custo fixo de chamada o custo por
# emissor DECRESCE com o tamanho, entao dividir o saldo pelo custo por emissor do lote cheio
# superestima quantos cabem e estoura o cap exatamente no caso que este codigo existe para
# barrar (com a = 237k, b = 59.7k e cap 700k dariam 7 emissores por 93.2k quando o lote de 7
# custa 819k). A estimativa cresce com o tamanho, entao o primeiro que nao cabe fecha a conta.
function Get-VixEmissoresQueCabemModelo {
    param($Modelo, [int64]$Acum = 0, [int64]$Cap = 0, [int]$Chunk = 0, [double]$Margem = -1)
    if ($Chunk -le 0) { return 0 }
    $resto = $Cap - $Acum
    if ($resto -le 0) { return 0 }
    # Piso do tamanho de lote: nunca abaixo do MENOR lote ja medido da classe (quando ele cabe no
    # chunk). Abaixo dele o envelope deixa de valer - foi assim que o lote de 1 emissor voltaria a
    # caber por 222.883 enquanto custa 296.866. Sem amostra nenhuma (n_min = 0) o default do
    # provedor ja e o valor de 1 emissor e o encolhimento livre e seguro.
    $i0 = 1
    if ($null -ne $Modelo -and [int]$Modelo.n_min -gt 1 -and [int]$Modelo.n_min -le $Chunk) { $i0 = [int]$Modelo.n_min }
    $k = 0
    for ($i = $i0; $i -le $Chunk; $i++) {
        if ((Get-VixEstimativaLoteClasse -Modelo $Modelo -Emissores $i -Margem $Margem) -le $resto) { $k = $i } else { break }
    }
    return $k
}

# ---------------------------------------------------------------------------------------
# 4. Provedor/modelo indisponivel: quando nao vale a pena chamar de novo
# ---------------------------------------------------------------------------------------
# SemPerspectiva=$true: modelo inexistente/indisponivel, cota/limite de uso, credencial.
# Repetir a chamada com o mesmo provedor nao muda o desfecho dentro desta execucao.
function Get-VixClasseFalhaProvider([string]$Texto) {
    $t = ('' + $Texto)
    if ($t -match '(?i)(model[^\r\n]{0,80}(not found|not supported|does not exist|unavailable|not available|unsupported|indispon)|modelo[^\r\n]{0,40}indispon|unknown model|invalid model)') {
        return @{ Classe = 'modelo_indisponivel'; SemPerspectiva = $true }
    }
    if ($t -match '(?i)(usage limit|hit your limit|rate.?limit|quota|insufficient_quota|too many requests|\b429\b|limite de (uso|sessao))') {
        return @{ Classe = 'cota'; SemPerspectiva = $true }
    }
    if ($t -match '(?i)(\b401\b|\b403\b|unauthorized|not logged in|please log ?in|authentication|token (expired|invalid)|credencial)') {
        return @{ Classe = 'auth'; SemPerspectiva = $true }
    }
    return @{ Classe = 'transitoria'; SemPerspectiva = $false }
}

# Disjuntor de provedor por execucao: falha sem perspectiva abre na hora; falha transitoria
# abre na segunda consecutiva. Lote aberto pelo disjuntor nao chama o provedor.
function New-VixDisjuntorProvider { return @{ aberto = $false; consecutivas = 0; classe = ''; motivo = '' } }
function Update-VixDisjuntorProvider($Disjuntor, [bool]$Falhou, [string]$Classe = '', [bool]$SemPerspectiva = $false) {
    if (-not $Falhou) { $Disjuntor.consecutivas = 0; return $Disjuntor }
    $Disjuntor.consecutivas++
    $Disjuntor.classe = $Classe
    if ($SemPerspectiva) { $Disjuntor.aberto = $true; $Disjuntor.motivo = 'sem_perspectiva:' + $Classe }
    elseif ($Disjuntor.consecutivas -ge 2) { $Disjuntor.aberto = $true; $Disjuntor.motivo = 'falhas_consecutivas:' + $Disjuntor.consecutivas }
    return $Disjuntor
}

# ---------------------------------------------------------------------------------------
# 5. Resultado da rotina: OK, PARCIAL ou FALHA
# ---------------------------------------------------------------------------------------
# OK so quando nao sobrou analise obrigatoria pendente e nada falhou.
# PendentesObrigatorios = deferidos por cap/orcamento/provedor/uso desconhecido/tempo +
# recheck de cobertura + submit recusado. Rotacao semanal planejada NAO entra (o emissor
# nao era obrigatorio nesta execucao, por desenho da rotacao).
function Get-VixResultadoRotina([bool]$DryRun, [bool]$TrabalhoZero, [int]$PlanoTotal, [int]$Analisados, [int]$Skips, [int]$PendentesObrigatorios, [int]$Erros) {
    if ($DryRun) { return @{ Resultado = 'DRYRUN'; Exit = 0; Motivo = 'dryrun' } }
    if ($TrabalhoZero) { return @{ Resultado = 'FALHA'; Exit = 9; Motivo = 'trabalho_zero' } }
    if ($PlanoTotal -gt 0 -and ($Analisados + $Skips) -eq 0) { return @{ Resultado = 'FALHA'; Exit = 6; Motivo = 'sem_analise_efetiva' } }
    if ($PendentesObrigatorios -gt 0) { return @{ Resultado = 'PARCIAL'; Exit = 10; Motivo = 'pendentes_obrigatorios=' + $PendentesObrigatorios } }
    if ($Erros -gt 0) { return @{ Resultado = 'PARCIAL'; Exit = 6; Motivo = 'erros=' + $Erros } }
    return @{ Resultado = 'OK'; Exit = 0; Motivo = 'cobertura_completa' }
}

# ---------------------------------------------------------------------------------------
# 6. Fila persistente de pendencias de cobertura (local, sobrevive a reinicio)
# ---------------------------------------------------------------------------------------
# Complementa o DEFERREDREC1 do Worker (`_token_cap_deferred` -> deferred_prioritario):
# aquele so existe se o submit do deferimento foi aceito. Esta fila guarda o emissor mesmo
# quando o submit falhou, com prioridade, motivo e tentativas, e so solta quando uma
# analise efetiva (ANALISADO com submit aceito e sem recheck, ou SKIP aceito) acontece.
# Escrita atomica (arquivo temporario + troca) sob mutex nomeado, porque matinal, noturna
# e sentinela escrevem no mesmo arquivo.
function ConvertTo-VixChaveEmissor([string]$Nome) {
    $norm = ('' + $Nome).Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return ($sb.ToString().Trim().ToLowerInvariant() -replace '\s+', ' ')
}

function Get-VixFilaPendentePath([string]$LogDir) { return (Join-Path $LogDir 'fila_pendente_cobertura.json') }

function Read-VixFilaPendente([string]$Path) {
    $fila = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $fila }
    $j = $null
    try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { throw ('fila pendente ilegivel: ' + $Path + ' - ' + $_.Exception.Message) }
    if ($j -and $j.PSObject.Properties['itens']) {
        foreach ($it in @($j.itens)) {
            if (-not $it -or -not $it.empresa) { continue }
            $fila[(ConvertTo-VixChaveEmissor $it.empresa)] = @{
                empresa = '' + $it.empresa; prioridade = [int]$it.prioridade; motivo = '' + $it.motivo
                tier = '' + $it.tier; rotina = '' + $it.rotina; desde = '' + $it.desde
                atualizado = '' + $it.atualizado; tentativas = [int]$it.tentativas
                submit_registrado = [bool]$it.submit_registrado
            }
        }
    }
    return $fila
}

function Write-VixFilaPendente([string]$Path, $Fila) {
    $itens = @(Get-VixFilaPendenteOrdenada $Fila)
    $doc = [ordered]@{ versao = 1; atualizado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); total = $itens.Count; itens = $itens }
    $tmp = $Path + '.tmp-' + $PID
    $json = $doc | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    # File.Replace com backup explicito: no .NET Framework 4 (PS 5.1) o backup $null lanca
    # "caminho com formato invalido" (medido no test-cobertura-analitica.ps1, parte F).
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, ($Path + '.bak')) } else { [IO.File]::Move($tmp, $Path) }
}

function Invoke-VixFilaPendenteSob([string]$Path, [scriptblock]$Acao) {
    $mtx = New-Object System.Threading.Mutex($false, 'Global\vixradar-fila-pendente-v1')
    $tem = $false
    try {
        try { $tem = $mtx.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $tem = $true }
        if (-not $tem) { throw 'mutex da fila pendente ocupado por mais de 30s' }
        $fila = Read-VixFilaPendente $Path
        $mudou = & $Acao $fila
        if ($mudou) { Write-VixFilaPendente $Path $fila }
        return $fila
    } finally {
        if ($tem) { try { $mtx.ReleaseMutex() } catch { } }
        $mtx.Dispose()
    }
}

# Upsert: mantem `desde` original, soma tentativa, prioridade nunca cai, motivo e rotina
# passam a ser os da ultima ocorrencia. Uma entrada por emissor (chave normalizada).
function Add-VixFilaPendente([string]$Path, [string]$Empresa, [int]$Prioridade, [string]$Motivo, [string]$Rotina, [string]$Tier = '', [bool]$SubmitRegistrado = $false) {
    $agora = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $null = Invoke-VixFilaPendenteSob $Path {
        param($fila)
        $k = ConvertTo-VixChaveEmissor $Empresa
        if ($fila.ContainsKey($k)) {
            $e = $fila[$k]
            $e.tentativas = [int]$e.tentativas + 1
            if ($Prioridade -gt [int]$e.prioridade) { $e.prioridade = $Prioridade }
            $e.motivo = $Motivo; $e.rotina = $Rotina; $e.atualizado = $agora
            if ($Tier) { $e.tier = $Tier }
            $e.submit_registrado = $SubmitRegistrado
        } else {
            $fila[$k] = @{ empresa = $Empresa; prioridade = $Prioridade; motivo = $Motivo; tier = $Tier; rotina = $Rotina; desde = $agora; atualizado = $agora; tentativas = 1; submit_registrado = $SubmitRegistrado }
        }
        return $true
    }
}

function Remove-VixFilaPendente([string]$Path, [string]$Empresa) {
    $estado = @{ removido = $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $null = Invoke-VixFilaPendenteSob $Path {
        param($fila)
        $k = ConvertTo-VixChaveEmissor $Empresa
        if ($fila.ContainsKey($k)) { $fila.Remove($k); $estado.removido = $true; return $true }
        return $false
    }
    return [bool]$estado.removido
}

function Get-VixFilaPendenteOrdenada($Fila) {
    $lista = foreach ($k in @($Fila.Keys)) {
        $e = $Fila[$k]
        [ordered]@{ empresa = $e.empresa; prioridade = [int]$e.prioridade; motivo = $e.motivo; tier = $e.tier; rotina = $e.rotina; desde = $e.desde; atualizado = $e.atualizado; tentativas = [int]$e.tentativas; submit_registrado = [bool]$e.submit_registrado }
    }
    return @($lista | Sort-Object -Property @{ Expression = { $_.prioridade }; Descending = $true }, @{ Expression = { $_.desde }; Descending = $false }, @{ Expression = { $_.empresa }; Descending = $false })
}

# Reordena a fila de trabalho: pendentes primeiro (na ordem da fila persistente), depois o
# resto na ordem original. Sem duplicar emissor e sem perder nenhum.
function Select-VixOrdemComPendentes([object[]]$Emissores, $Fila) {
    $porChave = @{}
    $ordemOriginal = New-Object System.Collections.Generic.List[string]
    foreach ($e in @($Emissores)) {
        if ($null -eq $e) { continue }
        $k = ConvertTo-VixChaveEmissor ('' + $e.empresa)
        if ($porChave.ContainsKey($k)) { continue }
        $porChave[$k] = $e
        $ordemOriginal.Add($k)
    }
    $saida = New-Object System.Collections.Generic.List[object]
    $usados = @{}
    foreach ($p in @(Get-VixFilaPendenteOrdenada $Fila)) {
        $k = ConvertTo-VixChaveEmissor $p.empresa
        if ($porChave.ContainsKey($k) -and -not $usados.ContainsKey($k)) { $saida.Add($porChave[$k]); $usados[$k] = $true }
    }
    foreach ($k in $ordemOriginal) { if (-not $usados.ContainsKey($k)) { $saida.Add($porChave[$k]); $usados[$k] = $true } }
    return $saida.ToArray()
}

# ---------------------------------------------------------------------------------------
# 6b. ROTACAO PERSISTENTE (ROTACAO-14OUT1, 2026-10-14)
# ---------------------------------------------------------------------------------------
# Os 104 emissores precisam de um dono de fila que sobreviva a execucao. Ordenar so por idade
# (o que a profundidade noturna ja faz) e justo, mas nao tem POSICAO: reinicio, concorrencia e
# reentrada reembaralham, e nada garante que o trecho sempre cortado pelo cap nao seja sempre o
# mesmo. Aqui vive o estado que falta:
#   - `ordem`: fila justa do ciclo atual (chaves normalizadas, unicas, ordem preservada);
#   - `posicao`: indice do proximo a servir. Quem foi deferido por ORCAMENTO nao sai da fila e
#     continua na frente (o cursor nao passa por ele); quem foi SERVIDO sai;
#   - `servidos`: quem ja fechou no ciclo atual (auditoria + deteccao de reinicio indevido);
#   - `candidatos_dia`: teto operacional de candidatos NAO prioritarios por dia (default 40),
#     zerado quando o DIA muda - nunca quando a execucao reinicia;
#   - o ciclo so reinicia quando a fila ZERA. Reiniciar com fila viva perderia posicao e
#     repetiria quem ja foi servido, que e a definicao de reinicializacao indevida.
# Escrita atomica (tmp + Replace + .bak), mesma familia da fila pendente.
function Get-VixRotacaoPath([string]$LogDir) { return (Join-Path $LogDir 'rotacao_ciclo.json') }

# Read-modify-write sob mutex nomeado: a fila do ciclo e estado COMPARTILHADO entre execucoes
# (restart da noturna, catch-up do Agendador). Sem o lock, duas passadas que leram o mesmo
# estado gravariam por cima uma da outra e a segunda apagaria o avanco da primeira - a mesma
# classe de defeito que o RACEKV1 fechou no estado do Worker.
function Invoke-VixRotacaoSob([string]$Path, [scriptblock]$Acao) {
    $mtx = New-Object System.Threading.Mutex($false, 'Global\vixradar-rotacao-ciclo-v1')
    $tem = $false
    try {
        try { $tem = $mtx.WaitOne(30000) } catch [System.Threading.AbandonedMutexException] { $tem = $true }
        if (-not $tem) { throw 'mutex da rotacao ocupado por mais de 30s' }
        $c = Read-VixRotacaoCiclo $Path
        $res = & $Acao $c
        if ($null -ne $res) {
            # A acao devolve o envelope de Update-VixRotacaoCiclo: grava-se o CICLO de dentro dele.
            # Gravar o envelope produziria arquivo vazio, porque `$envelope.ordem` e $null e o
            # `@($null)` do PowerShell conta 1 - o ciclo seria reiniciado em toda execucao.
            $cicloFinal = $res
            if ($null -ne $res.PSObject.Properties['Ciclo']) { $cicloFinal = $res.Ciclo }
            Write-VixRotacaoCiclo -Path $Path -Ciclo $cicloFinal | Out-Null
        }
        return $res
    } finally {
        if ($tem) { try { $mtx.ReleaseMutex() } catch { } }
        $mtx.Dispose()
    }
}

function New-VixRotacaoCiclo {
    return @{ versao = 1; ciclo_id = ''; inicio = ''; posicao = 0; ordem = @(); servidos = @{}; dia_candidatos = ''; candidatos_dia = 0; atualizado_em = '' }
}

function Read-VixRotacaoCiclo([string]$Path) {
    $c = New-VixRotacaoCiclo
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $c }
    $j = $null
    try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $c }
    if ($null -eq $j) { return $c }
    foreach ($campo in @('ciclo_id', 'inicio', 'dia_candidatos', 'atualizado_em')) {
        if ($null -ne $j.PSObject.Properties[$campo]) { $c[$campo] = '' + $j.$campo }
    }
    $p = 0
    if ($null -ne $j.PSObject.Properties['posicao'] -and [int]::TryParse(('' + $j.posicao), [ref]$p) -and $p -ge 0) { $c.posicao = $p }
    $cd = 0
    if ($null -ne $j.PSObject.Properties['candidatos_dia'] -and [int]::TryParse(('' + $j.candidatos_dia), [ref]$cd) -and $cd -ge 0) { $c.candidatos_dia = $cd }
    if ($null -ne $j.PSObject.Properties['ordem']) {
        $l = New-Object System.Collections.Generic.List[string]
        foreach ($k in @($j.ordem)) { $kk = '' + $k; if ($kk -and -not $l.Contains($kk)) { $l.Add($kk) } }
        $c.ordem = $l.ToArray()
    }
    if ($null -ne $j.PSObject.Properties['servidos'] -and $null -ne $j.servidos) {
        foreach ($pr in @($j.servidos.PSObject.Properties)) { $c.servidos[$pr.Name] = '' + $pr.Value }
    }
    return $c
}

function Write-VixRotacaoCiclo([string]$Path, $Ciclo) {
    if (-not $Path -or $null -eq $Ciclo) { return $null }
    $ordem = New-Object System.Collections.Generic.List[string]
    foreach ($k in @($Ciclo.ordem)) { $kk = '' + $k; if ($kk -and -not $ordem.Contains($kk)) { $ordem.Add($kk) } }
    $doc = [ordered]@{
        versao = 1
        ciclo_id = ('' + $Ciclo.ciclo_id)
        inicio = ('' + $Ciclo.inicio)
        posicao = [int]$Ciclo.posicao
        ordem = $ordem.ToArray()
        servidos = [ordered]@{}
        dia_candidatos = ('' + $Ciclo.dia_candidatos)
        candidatos_dia = [int]$Ciclo.candidatos_dia
        total_na_fila = $ordem.Count
        total_servidos = @($Ciclo.servidos.Keys).Count
        atualizado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    foreach ($k in @(@($Ciclo.servidos.Keys) | Sort-Object)) { $doc.servidos['' + $k] = '' + $Ciclo.servidos[$k] }
    $tmp = $Path + '.tmp-' + $PID
    [IO.File]::WriteAllText($tmp, ($doc | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, ($Path + '.bak')) } else { [IO.File]::Move($tmp, $Path) }
    return $doc
}

# Devolve os candidatos da execucao: PRIORITARIOS primeiro (risco, EWS, analise vencida,
# pendencia viva - nunca limitados pela cota de rotacao) e depois a fila do ciclo, ate o teto
# diario de candidatos nao prioritarios. Puro: nao escreve nada.
function Select-VixRotacaoCandidatos {
    param(
        [object[]]$Emissores = @(),
        [object[]]$ChavesPrioritarias = @(),
        $Ciclo = $null,
        [int]$LimiteDiario = 40,
        [string]$DiaTag = ''
    )
    $cat = New-VixRotacaoCiclo
    if ($null -ne $Ciclo) { $cat = $Ciclo }
    $porChave = @{}
    $ordemEntrada = New-Object System.Collections.Generic.List[string]
    foreach ($e in @($Emissores)) {
        if ($null -eq $e) { continue }
        $k = ConvertTo-VixChaveEmissor ('' + $e.empresa)
        if (-not $k -or $porChave.ContainsKey($k)) { continue }
        $porChave[$k] = $e
        $ordemEntrada.Add($k)
    }
    $prior = @{}
    foreach ($ck in @($ChavesPrioritarias)) {
        $k = ConvertTo-VixChaveEmissor ('' + $ck)
        if ($k) { $prior[$k] = $true }
    }
    $saida = New-Object System.Collections.Generic.List[object]
    $usados = @{}
    foreach ($k in $ordemEntrada) {
        if ($prior.ContainsKey($k) -and -not $usados.ContainsKey($k)) { $saida.Add($porChave[$k]); $usados[$k] = $true }
    }
    $ordemCiclo = New-Object System.Collections.Generic.List[string]
    # Quem JA fechou no ciclo atual nao volta para a rotacao (o turno dele ja foi dado); quem e
    # PRIORIDADE continua entrando SEMPRE, porque prioridade e por risco e nao consome turno de
    # rotacao - e o plano/ledger do dia e que impede reanalise no mesmo dia.
    $serv = @{}
    if ($null -ne $cat.servidos) { foreach ($k in @($cat.servidos.Keys)) { $serv['' + $k] = $true } }
    $visto = @{}
    foreach ($k in @($cat.ordem)) {
        $kk = '' + $k
        if (-not $kk -or $visto.ContainsKey($kk)) { continue }
        $visto[$kk] = $true
        if (-not $porChave.ContainsKey($kk)) { continue }
        if ($prior.ContainsKey($kk)) { continue }
        if ($serv.ContainsKey($kk)) { continue }
        $ordemCiclo.Add($kk)
    }
    foreach ($k in $ordemEntrada) {
        if ($prior.ContainsKey($k)) { continue }
        if ($visto.ContainsKey($k)) { continue }
        if ($serv.ContainsKey($k)) { continue }
        $visto[$k] = $true
        $ordemCiclo.Add($k)
    }
    $n = $ordemCiclo.Count
    $ring = New-Object System.Collections.Generic.List[string]
    if ($n -gt 0) {
        $pos = [int]$cat.posicao
        if ($pos -lt 0 -or $pos -ge $n) { $pos = 0 }
        for ($i = 0; $i -lt $n; $i++) { $ring.Add($ordemCiclo[($pos + $i) % $n]) }
    }
    $jaHoje = 0
    if ($DiaTag -and ('' + $cat.dia_candidatos) -eq ('' + $DiaTag)) { $jaHoje = [int]$cat.candidatos_dia }
    $restantes = [int]$LimiteDiario - $jaHoje
    if ($restantes -lt 0) { $restantes = 0 }
    $consumidos = New-Object System.Collections.Generic.List[string]
    $c = 0
    foreach ($k in $ring) {
        if ($c -ge $restantes) { break }
        if ($usados.ContainsKey($k)) { continue }
        $saida.Add($porChave[$k]); $usados[$k] = $true; $consumidos.Add($k); $c++
    }
    $adiados = New-Object System.Collections.Generic.List[string]
    foreach ($k in $ordemEntrada) { if (-not $usados.ContainsKey($k) -and -not $serv.ContainsKey($k)) { $adiados.Add($k) } }
    $priorSel = New-Object System.Collections.Generic.List[string]
    foreach ($k in $ordemEntrada) { if ($prior.ContainsKey($k)) { $priorSel.Add($k) } }
    return [pscustomobject]@{
        Candidatos = $saida.ToArray()
        Ring = $ring.ToArray()
        PriorChaves = $priorSel.ToArray()
        ConsumidosChaves = $consumidos.ToArray()
        AdiadosCota = $adiados.ToArray()
        CotaRestante = $restantes
        JaHoje = $jaHoje
    }
}

# Atualiza o ciclo com o desfecho da execucao. Devolve o ciclo novo e a auditoria
# (perdidos/duplicados/reiniciou). `Servidos` = quem FECHOU (analisado/skip); `Consumidos` =
# quem foi oferecido como candidato de rotacao nesta execucao. Quem foi oferecido e nao fechou
# (deferido por cap) continua na fila, na frente.
function Update-VixRotacaoCiclo {
    param(
        $Ciclo = $null,
        [string[]]$Presentes = @(),
        [string[]]$Servidos = @(),
        [string[]]$Consumidos = @(),
        [string[]]$Ring = @(),
        [string]$DiaTag = '',
        [datetime]$Agora = (Get-Date)
    )
    $c = New-VixRotacaoCiclo
    if ($null -ne $Ciclo) { $c = $Ciclo }
    if (('' + $c.dia_candidatos) -ne ('' + $DiaTag)) { $c.dia_candidatos = '' + $DiaTag; $c.candidatos_dia = 0 }
    $serv = @{}
    foreach ($k in @($Servidos)) { $kk = ConvertTo-VixChaveEmissor ('' + $k); if ($kk) { $serv[$kk] = $true } }
    $cons = @{}
    foreach ($k in @($Consumidos)) { $kk = ConvertTo-VixChaveEmissor ('' + $k); if ($kk) { $cons[$kk] = $true } }
    $pres = New-Object System.Collections.Generic.List[string]
    $vistoPres = @{}
    foreach ($k in @($Presentes)) {
        $kk = ConvertTo-VixChaveEmissor ('' + $k)
        if (-not $kk -or $vistoPres.ContainsKey($kk)) { continue }
        $vistoPres[$kk] = $true
        $pres.Add($kk)
    }
    # Fecha o ciclo: os servidos desta execucao entram no mapa do CICLO (nao so no do dia) e a
    # fila resultante e a ordem atual menos TODOS os servidos do ciclo - nao so os desta passada.
    # Sem isto, quem fechou em execucao anterior do MESMO ciclo voltava para a fila pela regra de
    # "nao perder fila", a fila nunca zerava e o reinicio do ciclo (unico ponto permitido) nao
    # acontecia.
    $diaServ = $Agora.ToUniversalTime().ToString('yyyy-MM-dd')
    foreach ($kk in @($serv.Keys)) { $c.servidos[$kk] = $diaServ }
    $servCiclo = @{}
    foreach ($kk in @($c.servidos.Keys)) { $servCiclo['' + $kk] = $true }
    $ordem = New-Object System.Collections.Generic.List[string]
    $naOrdem = @{}
    foreach ($k in @($c.ordem)) {
        $kk = '' + $k
        if (-not $kk -or $naOrdem.ContainsKey($kk)) { continue }
        if ($servCiclo.ContainsKey($kk)) { continue }
        $naOrdem[$kk] = $true
        $ordem.Add($kk)
    }
    foreach ($kk in $pres) {
        if ($servCiclo.ContainsKey($kk)) { continue }
        if ($naOrdem.ContainsKey($kk)) { continue }
        $naOrdem[$kk] = $true
        $ordem.Add($kk)
    }
    $reiniciou = $false
    if ($ordem.Count -eq 0 -and $servCiclo.Count -gt 0) {
        $reiniciou = $true
        $c.ciclo_id = $Agora.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $c.inicio = $c.ciclo_id
        $c.servidos = @{}
        foreach ($kk in $pres) { if (-not $naOrdem.ContainsKey($kk)) { $naOrdem[$kk] = $true; $ordem.Add($kk) } }
    }
    # Cursor = primeiro item do ANEL que ainda NAO fechou. Quem foi oferecido e nao fechou
    # (deferido por orcamento) continua na frente: e isso que impede starvation, e e por isso
    # que o teste le `servidos` e nao `consumidos` aqui.
    $proximo = ''
    foreach ($k in @($Ring)) {
        $kk = '' + $k
        if (-not $serv.ContainsKey($kk)) { $proximo = $kk; break }
    }
    $pos = 0
    if ($proximo) {
        for ($i = 0; $i -lt $ordem.Count; $i++) { if ($ordem[$i] -eq $proximo) { $pos = $i; break } }
    }
    $c.posicao = $pos
    $c.ordem = $ordem.ToArray()
    $c.candidatos_dia = [int]$c.candidatos_dia + @($cons.Keys).Count
    $contagem = @{}
    $duplicados = 0
    foreach ($k in @($c.ordem)) { if ($contagem.ContainsKey($k)) { $duplicados++ } else { $contagem[$k] = $true } }
    $perdidos = 0
    foreach ($kk in $pres) { if (-not $contagem.ContainsKey($kk) -and -not $c.servidos.ContainsKey($kk)) { $perdidos++ } }
    return [pscustomobject]@{
        Ciclo = $c; Reiniciou = $reiniciou; Perdidos = $perdidos; Duplicados = $duplicados
        NaFila = @($c.ordem).Count; ServidosCiclo = @($c.servidos.Keys).Count
        Posicao = $pos; CandidatosDia = [int]$c.candidatos_dia
    }
}

# ---------------------------------------------------------------------------------------
# 6c. RECONCILIACAO DE COBERTURA (COBERTURA-RECON1, 2026-10-14)
# ---------------------------------------------------------------------------------------
# Defeito medido em 14/10: 16 analises publicadas e SO 11 registros de cobertura - nao havia
# denominador comum, porque o contrato so registrava quem estava PENDENTE. Sem isso ninguem
# podia afirmar se faltava cobertura ou se faltava registro. Aqui a regra e unica e explicita:
#   ledger ANALISADO = contrato ANALISADO + contrato INCONCLUSIVO   (analise publicada)
#   ledger SKIP      = contrato REUTILIZADO                          (analise reaproveitada)
#   ledger DEFERIDO  = contrato DEFERIDO                             (nao analisado, registrado)
#   TRIADOS          >= emissores do plano                           (triagem universal)
#   rotacao_perdidos = 0                                             (ninguem fora da fila)
# Divergencia NAO e sucesso: quem chama soma ao erro e a rotina nao pode fechar OK.
function Test-VixCoberturaReconciliacao {
    param(
        [int]$LedgerAnalisados = 0,
        [int]$LedgerSkips = 0,
        [int]$LedgerDeferidos = 0,
        [int]$ContratoAnalisado = 0,
        [int]$ContratoInconclusivo = 0,
        [int]$ContratoResolvido = 0,
        [int]$ContratoReutilizado = 0,
        [int]$ContratoDeferido = 0,
        [int]$Triados = 0,
        [int]$PlanoTotal = 0,
        [int]$RotacaoPerdidos = 0,
        [bool]$ExigirTriagem = $false
    )
    $d = @()
    # RESOLVIDO conta como publicacao: e um emissor que estava pendente e fechou com submit aceito
    # e cobertura verificada. Fora da conta, o dia em que a fila de recheck e resolvida seria lido
    # como falta de cobertura - falso alarme do mesmo tamanho do defeito original.
    $publicados = $ContratoAnalisado + $ContratoInconclusivo + $ContratoResolvido
    if ($publicados -ne $LedgerAnalisados) { $d += ('analisados:ledger=' + $LedgerAnalisados + ' contrato=' + $publicados) }
    if ($ContratoReutilizado -ne $LedgerSkips) { $d += ('skips:ledger=' + $LedgerSkips + ' contrato=' + $ContratoReutilizado) }
    if ($ContratoDeferido -ne $LedgerDeferidos) { $d += ('deferidos:ledger=' + $LedgerDeferidos + ' contrato=' + $ContratoDeferido) }
    if ($ExigirTriagem -and $Triados -lt $PlanoTotal) { $d += ('triados:' + $Triados + '<' + $PlanoTotal) }
    if ($RotacaoPerdidos -gt 0) { $d += ('rotacao_perdidos:' + $RotacaoPerdidos) }
    return @{ ok = ($d.Count -eq 0); divergencias = $d }
}

# ---------------------------------------------------------------------------------------
# 7. Triagem deterministica (COBERTURA-13OUT1, parte 2): IA so onde ha fato novo a interpretar
# ---------------------------------------------------------------------------------------
# Regra de negocio. A rotina tem dois trabalhos diferentes que ate 13/10 eram feitos pelo
# mesmo agente caro: (a) PROCURAR se ha fato novo e (b) INTERPRETAR o fato para credito.
# (a) e mecanico e sai do coletor (Google News RSS, 3 familias F1/F2/F3, HTTP real, zero
# token). (b) exige IA. Emissor sem nenhuma publicacao desde o inicio do delta e sem documento
# novo na CVM nao tem o que interpretar: a ausencia e certificada pelas tres consultas reais.
# Garantias que NAO mudam: coleta incompleta (qualquer familia sem HTTP 200/XML valido) nunca
# certifica ausencia e cai na IA como antes; documento CVM novo sempre vai para a IA; e todo
# emissor passa por analise de IA de verdade pelo menos a cada RevalidacaoH horas (48h para
# EWS >= 50), mesmo quieto, para o RSS nao ser o unico olho por dias seguidos.
$script:VixTriagemRevalidacaoH = 120
$script:VixTriagemRevalidacaoCriticoH = 48
$script:VixTriagemEwsCritico = 50

function ConvertTo-VixTextoBusca([string]$s) {
    $norm = ('' + $s).Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) { if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) } }
    return (' ' + (($sb.ToString().ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim()) + ' ')
}
function Test-VixMencionaEmissor([string]$Titulo, [string]$Empresa) {
    $t = ConvertTo-VixTextoBusca $Titulo
    $termos = New-Object System.Collections.Generic.List[string]
    $semParen = ($Empresa -replace '\([^)]*\)', ' ')
    $termos.Add($semParen)
    $m = [regex]::Match($Empresa, '\(([^)]+)\)')
    if ($m.Success) { $termos.Add($m.Groups[1].Value) }
    $prim = (($semParen.Trim() -split '\s+')[0])
    if ($prim.Length -ge 3) { $termos.Add($prim) }
    foreach ($x in $termos) {
        $n = (ConvertTo-VixTextoBusca $x)
        if ($n.Trim().Length -ge 2 -and $t.Contains($n)) { return $true }
    }
    return $false
}
function Test-VixTituloCritico([string]$Titulo) {
    $t = ConvertTo-VixTextoBusca $Titulo
    foreach ($k in @('recuperacao judicial','recuperacao extrajudicial','falencia','rebaixa','downgrade','calote','default','inadimpl','vencimento antecipado','waiver','covenant','quebra de','fato relevante','intervencao','liquidacao extrajudicial','reestrutura')) {
        if ($t.Contains($k)) { return $true }
    }
    return $false
}
function Get-VixTriagemEmissor($Coleta, [string]$DeltaInicio, [int]$CvmNovos = 0, $HorasDesdeIA = $null, [int]$Ews = 0, [bool]$EstadoNaoResolvido = $false, [string]$MotivoNaoResolvido = '', [datetime]$Agora = (Get-Date)) {
    $limiteH = $script:VixTriagemRevalidacaoH
    if ($Ews -ge $script:VixTriagemEwsCritico) { $limiteH = $script:VixTriagemRevalidacaoCriticoH }
    if ($CvmNovos -gt 0) { return @{ Classe = 'MATERIAL'; Motivo = ('cvm_novos_' + $CvmNovos); Novas = @() } }
    if ($null -eq $HorasDesdeIA -or [double]$HorasDesdeIA -ge $limiteH) {
        $hTxt = if ($null -eq $HorasDesdeIA) { 'sem_registro' } else { ([int][double]$HorasDesdeIA).ToString() + 'h' }
        return @{ Classe = 'MATERIAL'; Motivo = ('revalidacao_ia_' + $hTxt + '_limite_' + $limiteH + 'h'); Novas = @() }
    }
    if ($null -eq $Coleta -or ($null -ne $Coleta.PSObject.Properties['disponivel'] -and -not $Coleta.disponivel)) {
        return @{ Classe = 'INDISPONIVEL'; Motivo = 'coleta_incompleta'; Novas = @() }
    }
    # HTTP 200 com XML valido e ZERO itens no feed de F1 (e na soma das familias) nao e emissor
    # quieto: e throttling ou consulta quebrada. Conta o que o feed devolveu antes do filtro de
    # janela. Coleta sem o campo (cache antigo) tambem nao certifica.
    $bruF1 = -1; $bruTot = -1
    if ($null -ne $Coleta.PSObject.Properties['itens_brutos'] -and $null -ne $Coleta.itens_brutos) {
        $ib = $Coleta.itens_brutos
        $bruF1 = 0; $bruTot = 0
        if ($ib -is [hashtable] -or $ib -is [System.Collections.Specialized.OrderedDictionary]) { foreach ($k in @($ib.Keys)) { $bruTot += [int]$ib[$k]; if ($k -eq 'F1') { $bruF1 = [int]$ib[$k] } } }
        else { foreach ($pp in @($ib.PSObject.Properties)) { $bruTot += [int]$pp.Value; if ($pp.Name -eq 'F1') { $bruF1 = [int]$pp.Value } } }
    }
    if ($bruF1 -lt 0) { return @{ Classe = 'INDISPONIVEL'; Motivo = 'coleta_sem_itens_brutos'; Novas = @() } }
    if ($bruF1 -eq 0) { return @{ Classe = 'INDISPONIVEL'; Motivo = 'f1_feed_vazio_suspeito'; Novas = @() } }
    $corte = $null
    $d = [datetime]::MinValue
    if ($DeltaInicio -and [datetime]::TryParseExact(('' + $DeltaInicio).Substring(0, [Math]::Min(10, ('' + $DeltaInicio).Length)), 'yyyy-MM-dd', $null, [Globalization.DateTimeStyles]::None, [ref]$d)) { $corte = $d.Date }
    if ($null -eq $corte) { $corte = $Agora.ToUniversalTime().Date.AddDays(-1) }
    # Relevancia CONSERVADORA: so sai da conta a manchete que NAO cita o emissor (nome completo,
    # apelido entre parenteses ou primeiro termo, sem acento e por palavra inteira). Manchete que
    # cita o emissor conta como sinal mesmo sem palavra-chave de credito, porque filtrar por
    # palavra-chave poderia calar um evento real (erro para o lado perigoso). Nome ambiguo
    # (Oi, Light, Vamos) cita o emissor em ruido e por isso vai para a IA: erro para o lado seguro.
    $novas = @(@($Coleta.evidencias) | Where-Object {
        $x = [datetime]::MinValue
        $null -ne $_ -and [datetime]::TryParseExact(('' + $_.data), 'yyyy-MM-dd', $null, [Globalization.DateTimeStyles]::None, [ref]$x) -and $x -ge $corte -and (Test-VixMencionaEmissor ('' + $_.titulo) ('' + $Coleta.empresa))
    })
    # Gate de evento critico (falso negativo): manchete NOVA da familia F1 (consulta pelo proprio
    # nome do emissor) com termo de estresse de credito vai para a IA mesmo sem citar o nome no
    # titulo (apelido, grupo controlador, grafia). Lista curta e deliberadamente larga.
    if ($novas.Count -eq 0) {
        $critNovas = @(@($Coleta.evidencias) | Where-Object {
            $x = [datetime]::MinValue
            $null -ne $_ -and ('' + $_.familia) -eq 'F1' -and [datetime]::TryParseExact(('' + $_.data), 'yyyy-MM-dd', $null, [Globalization.DateTimeStyles]::None, [ref]$x) -and $x -ge $corte -and (Test-VixTituloCritico ('' + $_.titulo))
        })
        if ($critNovas.Count -gt 0) { return @{ Classe = 'MATERIAL'; Motivo = ('critico_f1_sem_nome_' + $critNovas.Count + '_desde_' + $corte.ToString('yyyy-MM-dd')); Novas = $critNovas } }
    }
    if ($novas.Count -gt 0) { return @{ Classe = 'MATERIAL'; Motivo = ('evidencia_nova_' + $novas.Count + '_desde_' + $corte.ToString('yyyy-MM-dd')); Novas = $novas } }
    # ESTADONAORESOLVIDO1 (2026-10-13): ultimo portao antes do QUIETO, e o unico que olha para o
    # ESTADO do emissor em vez de para a evidencia do dia. QUIETO e uma CERTIFICACAO de ausencia
    # produzida pelo caminho mais barato que existe (tres consultas de RSS, sem fonte primaria e
    # sem IA). Emissor cujo ultimo desfecho foi INCONCLUSIVO, ou que carrega pendencia de analise
    # aberta, tem pergunta VIVA: certificar ausencia ali apaga a pergunta com o cheque mais fraco
    # da casa - e foi assim que INCONCLUSIVO virava QUIETO. Fica aqui, e nao no inicio, de
    # proposito: coleta indisponivel continua INDISPONIVEL e revalidacao vencida continua
    # MATERIAL, porque o operador precisa distinguir "nao olhei" de "olhei e nao posso concluir".
    # O que esta regra faz e so uma coisa: impedir que o veredito QUIETO saia para quem tem
    # pergunta aberta. Ele segue para a IA como qualquer MATERIAL.
    if ($EstadoNaoResolvido) {
        $__mnr = if ($MotivoNaoResolvido) { $MotivoNaoResolvido } else { 'pendencia_aberta' }
        return @{ Classe = 'MATERIAL'; Motivo = ('estado_nao_resolvido_' + $__mnr); Novas = @() }
    }
    return @{ Classe = 'QUIETO'; Motivo = ('sem_publicacao_desde_' + $corte.ToString('yyyy-MM-dd')); Novas = @() }
}

# ---------------------------------------------------------------------------------------
# 7b. Filtro de relevancia de credito, SOMBRA (COBERTURA-13OUT2)
# ---------------------------------------------------------------------------------------
# Dentro do MATERIAL, separa o que merece IA do que e so ruido de imprensa (Light esportivo, Oi
# novela). Em sombra ele so REGISTRA a decisao e depois o desfecho da IA, para medir revocacao;
# nenhum emissor deixa de ir para a IA por causa dele. Regra de projeto: erra para o lado
# seguro. Tudo que for gatilho critico e RELEVANTE sem discussao: documento CVM novo, revalidacao
# obrigatoria, EWS >= 50, termo critico, F2/F3 (divida, emissao, fato/RI), agencia de rating no
# veiculo, ou termo de credito/mercado. So vira RUIDO manchete nova de F1 sem nenhum desses.
$script:VixRelevanciaLexico = @('divida','debenture','rating','classificacao de risco','nota de credito','resultado','lucro','prejuizo','ebitda','alavanc','caixa','liquidez','emissao','captacao','bond','juros','spread','aquisicao','venda de ativo','desinvest','fusao','oferta','dividendo','balanco','guidance','multa','investigacao','operacao da','cade','tcu','aneel','antt','anp','anvisa','greve','acidente','rompimento','incendio','paralisa','denuncia','acordo','credor','refinanc','rolagem','garantia','cvm','b3','acionista','controle','troca de ceo','renuncia','demissao','ceo','cfo','auditor','ressalva','contingencia','passivo','processo','arbitragem','liminar','concessao','licenca','tarifa','reajuste','custo','margem','receita','vendas','producao','demanda')
$script:VixRelevanciaAgencias = @('fitch','moodys','moody s','standard poors','s p global','austin rating','sp global')

function Get-VixRelevanciaCredito($Triagem, [int]$CvmNovos = 0, [int]$Ews = 0) {
    if ($null -eq $Triagem -or ('' + $Triagem.Classe) -ne 'MATERIAL') { return @{ Decisao = 'NAO_APLICA'; Motivo = ('classe_' + $Triagem.Classe) } }
    $mot = '' + $Triagem.Motivo
    if ($CvmNovos -gt 0 -or $mot -like 'cvm_novos*') { return @{ Decisao = 'RELEVANTE'; Motivo = 'cvm_novo' } }
    if ($mot -like 'revalidacao*') { return @{ Decisao = 'RELEVANTE'; Motivo = 'revalidacao_obrigatoria' } }
    if ($mot -like 'critico_f1*') { return @{ Decisao = 'RELEVANTE'; Motivo = 'termo_critico_f1' } }
    if ($Ews -ge $script:VixTriagemEwsCritico) { return @{ Decisao = 'RELEVANTE'; Motivo = 'ews_critico' } }
    $novas = @($Triagem.Novas)
    if ($novas.Count -eq 0) { return @{ Decisao = 'RELEVANTE'; Motivo = 'sem_evidencia_para_julgar' } }
    foreach ($n in $novas) {
        if ($null -eq $n) { continue }
        $fam = '' + $n.familia
        if ($fam -eq 'F2' -or $fam -eq 'F3') { return @{ Decisao = 'RELEVANTE'; Motivo = ('familia_' + $fam) } }
        if (Test-VixTituloCritico ('' + $n.titulo)) { return @{ Decisao = 'RELEVANTE'; Motivo = 'termo_critico' } }
        $vv = ConvertTo-VixTextoBusca (('' + $n.veiculo) + ' ' + ('' + $n.dominio))
        foreach ($ag in $script:VixRelevanciaAgencias) { if ($vv.Contains($ag)) { return @{ Decisao = 'RELEVANTE'; Motivo = 'agencia_rating' } } }
        $tt = ConvertTo-VixTextoBusca ('' + $n.titulo)
        foreach ($k in $script:VixRelevanciaLexico) { if ($tt.Contains($k)) { return @{ Decisao = 'RELEVANTE'; Motivo = ('lexico_' + $k) } } }
    }
    return @{ Decisao = 'RUIDO'; Motivo = ('sem_termo_de_credito_em_' + $novas.Count + '_manchete(s)') }
}

function Get-VixRelevanciaSombraPath([string]$LogDir, [string]$DateTag) { return (Join-Path $LogDir ('relevancia_sombra_' + $DateTag + '.jsonl')) }
function Add-VixRelevanciaRegistro([string]$Path, $Registro) {
    $linha = ($Registro | ConvertTo-Json -Compress -Depth 4)
    [System.IO.File]::AppendAllText($Path, $linha + "`n", (New-Object System.Text.UTF8Encoding($false)))
}
# Revocacao do filtro: dos emissores que o filtro chamaria de RUIDO, quantos a IA depois achou
# evento (falso negativo, a unica metrica que importa). Une 'decisao' e 'desfecho' por emissor.
function Get-VixRevocacaoRelevancia([object[]]$Registros) {
    $dec = @{}; $des = @{}
    foreach ($r in @($Registros)) {
        if ($null -eq $r) { continue }
        $k = ConvertTo-VixChaveEmissor ('' + $r.empresa)
        if (('' + $r.tipo) -eq 'decisao') { $dec[$k] = $r } elseif (('' + $r.tipo) -eq 'desfecho') { $des[$k] = $r }
    }
    $ruido = 0; $fn = 0; $semDesfecho = 0; $relev = 0; $nomesFn = @()
    foreach ($k in @($dec.Keys)) {
        if (('' + $dec[$k].decisao) -eq 'RELEVANTE') { $relev++; continue }
        if (('' + $dec[$k].decisao) -ne 'RUIDO') { continue }
        $ruido++
        if (-not $des.ContainsKey($k)) { $semDesfecho++; continue }
        if ([int]$des[$k].n_eventos -gt 0) { $fn++; $nomesFn += ('' + $dec[$k].empresa) }
    }
    $medidos = $ruido - $semDesfecho
    return @{ Relevante = $relev; Ruido = $ruido; RuidoMedido = $medidos; RuidoSemDesfecho = $semDesfecho; FalsosNegativos = $fn; Emissores = $nomesFn; Seguro = ($medidos -ge 1 -and $fn -eq 0) }
}

# Fontes estruturais do coletor (familia, query, timestamp, provedor, status_http real,
# resultado, classificacao). Servem ao caminho deterministico e tambem SOMAM as fontes do
# modelo no caminho de IA, para a cobertura das tres familias ser provada por consulta medida.
function Get-VixFontesColetor($Coleta, [string]$DeltaInicio = '') {
    $mapa = @{ 'F1' = 'emissor'; 'F2' = 'divida'; 'F3' = 'fato' }
    $out = @()
    if ($null -eq $Coleta -or -not $Coleta.disponivel) { return $out }
    foreach ($q in @($Coleta.queries)) {
        $fid = '' + $q.familia
        $n7 = 0
        try { $n7 = [int]$Coleta.por_familia[$fid] } catch { $n7 = 0 }
        $txt = ('Google News RSS, janela ' + $Coleta.janela_dias + 'd: ' + $n7 + ' publicacao(oes) na janela')
        if ($DeltaInicio) { $txt = $txt + '; delta desde ' + $DeltaInicio }
        # [pscustomobject] de proposito: o portao de ausencia do motor confere os campos por
        # PSObject.Properties (o mesmo formato que o JSON do modelo tem). Dicionario nao tem
        # propriedades, o portao lia status_http ausente e a triagem nunca certificava nada
        # (achado pelo test-cobertura-recuperacao.ps1, P1).
        $out += [pscustomobject][ordered]@{
            rodada = 'C'; familia = $mapa[$fid]; query = ('' + $q.query); timestamp = ('' + $Coleta.coletado_em)
            provedor = 'coletor:google_news_rss'; status_http = 200; resultado = $txt; classificacao = 'ok'
        }
    }
    return $out
}

# Modo coletor na via da IA (COBERTURA-13OUT2). Medido em dry-run de 13/10: com o coletor ativo o
# lote custou 21.892 tokens para 2 emissores (~11k cada, contra ~178k), mas os dois voltaram
# INCONCLUSIVO porque o motor so anexava as fontes estruturais do coletor no caminho
# deterministico. Aqui o orquestrador soma ao resultado da IA as consultas que ELE fez (familia,
# query, timestamp, HTTP real). Regras de veracidade: (1) coleta incompleta nao soma nada e o
# portao de ausencia continua reprovando; (2) se a IA diz "sem eventos" mas o coletor viu manchete
# nova que cita o emissor, nao soma e marca divergencia, o emissor fica INCONCLUSIVO e volta na
# fila (a IA nao pode calar o que a coleta viu); (3) nunca duplica consulta ja declarada.
function Add-VixFontesColetorAoResultado($Res, $Coleta, [string]$DeltaInicio = '', $Novas = @()) {
    $out = @{ Adicionadas = 0; Divergencia = $false; Motivo = '' }
    if ($null -eq $Res -or $null -eq $Coleta) { $out.Motivo = 'sem_coleta'; return $out }
    if ($null -ne $Coleta.PSObject.Properties['disponivel'] -and -not $Coleta.disponivel) { $out.Motivo = 'coleta_incompleta'; return $out }
    $nEv = @($Res.eventos).Count
    $cls = '' + $Res.classificacao_geral
    if ($nEv -eq 0 -and $cls -in @('NENHUM', 'ECO', '') -and @($Novas).Count -gt 0) {
        $out.Divergencia = $true; $out.Motivo = ('divergencia_ia_sem_evento_coletor_viu_' + @($Novas).Count); return $out
    }
    $atuais = @($Res.fontes_consultadas)
    $jaTem = @{}
    foreach ($f in $atuais) { if ($null -ne $f -and $null -ne $f.PSObject.Properties['query']) { $jaTem[('' + $f.query).Trim().ToLowerInvariant()] = $true } }
    $novasFontes = @()
    foreach ($f in @(Get-VixFontesColetor $Coleta $DeltaInicio)) {
        $q = ('' + $f.query).Trim().ToLowerInvariant()
        if ($jaTem.ContainsKey($q)) { continue }
        $novasFontes += $f
    }
    if ($novasFontes.Count -eq 0) { $out.Motivo = 'nada_a_somar'; return $out }
    $todas = @($atuais) + @($novasFontes)
    if ($null -ne $Res.PSObject.Properties['fontes_consultadas']) { $Res.fontes_consultadas = $todas }
    else { $Res | Add-Member -NotePropertyName 'fontes_consultadas' -NotePropertyValue $todas -Force }
    $out.Adicionadas = $novasFontes.Count; $out.Motivo = 'fontes_do_coletor_somadas'
    return $out
}

function New-VixResultadoDeterministico([string]$Empresa, $Coleta, $Triagem, [string]$DeltaInicio = '') {
    $fontes = @(Get-VixFontesColetor $Coleta $DeltaInicio)
    return [ordered]@{
        classificacao_geral = 'NENHUM'; sem_eventos = $true
        cobertura_nota = ('Triagem deterministica (COBERTURA-13OUT1): ' + $Triagem.Motivo + '. Tres familias consultadas pelo orquestrador com HTTP 200 (F1 emissor, F2 divida/emissao, F3 CVM/RI/fato) e nenhum documento CVM novo. Sem fato novo a interpretar; IA nao acionada. Revalidacao por IA garantida a cada ' + $script:VixTriagemRevalidacaoH + 'h.')
        eventos = @(); fontes_consultadas = $fontes
        _triagem = 'QUIETO_DETERMINISTICO'; _triagem_motivo = $Triagem.Motivo
    }
}

# Pistas para o caminho de IA: so as publicacoes NOVAS (desde o delta), em texto curto. O
# modelo comeca confirmando a pista em vez de refazer busca ampla nas tres familias.
function Format-VixLeadsTriagem($Triagem, [int]$Max = 6) {
    $l = @()
    foreach ($e in @($Triagem.Novas | Select-Object -First $Max)) { $l += ('[' + $e.familia + '] ' + $e.data + ' | ' + $e.veiculo + ' (' + $e.dominio + ') | ' + $e.titulo) }
    return ($l -join "`n")
}

# Cache de coleta entre rotinas do mesmo dia (reaproveita evidencia valida). Coleta
# indisponivel nunca e cacheada: falha nao pode ser reaproveitada como se fosse medicao.
function Get-VixColetaCachePath([string]$LogDir, [string]$DateTag) { return (Join-Path $LogDir ('coleta_cache_' + $DateTag + '.json')) }
function Get-VixColetaCacheada([string]$Path, [string]$Empresa, [int]$TtlMin = 180, [datetime]$Agora = (Get-Date)) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $j = $null
    try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    $k = ConvertTo-VixChaveEmissor $Empresa
    $p = $j.PSObject.Properties[$k]
    if ($null -eq $p) { return $null }
    $c = $p.Value
    $t = [datetime]::MinValue
    if (-not [datetime]::TryParse(('' + $c.coletado_em), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$t)) { return $null }
    if (($Agora.ToUniversalTime() - $t).TotalMinutes -gt $TtlMin) { return $null }
    if (-not $c.disponivel) { return $null }
    # por_familia volta como PSCustomObject; o consumidor indexa por chave
    $pf = @{}
    foreach ($pp in @($c.por_familia.PSObject.Properties)) { $pf[$pp.Name] = [int]$pp.Value }
    $c | Add-Member -NotePropertyName por_familia -NotePropertyValue $pf -Force
    return $c
}
function Save-VixColetaCache([string]$Path, $Coleta) {
    if ($null -eq $Coleta -or -not $Coleta.disponivel) { return }
    $doc = @{}
    if (Test-Path -LiteralPath $Path) {
        try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in @($j.PSObject.Properties)) { $doc[$p.Name] = $p.Value } } catch { $doc = @{} }
    }
    $doc[(ConvertTo-VixChaveEmissor ('' + $Coleta.empresa))] = $Coleta
    $tmp = $Path + '.tmp-' + $PID
    [IO.File]::WriteAllText($tmp, ($doc | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, ($Path + '.bak')) } else { [IO.File]::Move($tmp, $Path) }
}

# Registro local da ultima analise de IA por emissor (a revalidacao periodica le daqui). O
# plano do Worker conta qualquer analise, inclusive a deterministica, entao nao serve sozinho.
#
# INCONCLUSIVONAOECONCLUSAO1 (2026-10-13): o que conta como analise CONCLUIDA passa a ter uma
# definicao unica, e ela exclui INCONCLUSIVO. O motor tinha duas afirmacoes opostas em duas linhas
# vizinhas: a de baixo (`$classif -ne 'INCONCLUSIVO'`) tratava INCONCLUSIVO como pendencia viva e
# mantinha o emissor na fila, enquanto a de cima marcava `ultima_ia` para QUALQUER submit aceito,
# inclusive INCONCLUSIVO. Consequencia medida por leitura: emissor analisado e devolvido
# INCONCLUSIVO ganhava carimbo de IA recente, a triagem periodica passava no portao
# `HorasDesdeIA < limite`, e o emissor era certificado QUIETO na execucao seguinte sem que
# ninguem tivesse resolvido a pergunta aberta - exatamente o INCONCLUSIVO virando QUIETO que a
# cobertura proibe. As duas linhas passam a ler esta funcao.
function Test-VixAnaliseConcluida([bool]$SubOk, [string]$Classificacao) {
    if (-not $SubOk) { return $false }
    return (('' + $Classificacao).Trim().ToUpperInvariant() -ne 'INCONCLUSIVO')
}
function Get-VixUltimaIAPath([string]$LogDir) { return (Join-Path $LogDir 'ultima_analise_ia.json') }
function Get-VixHorasDesdeIA([string]$Path, [string]$Empresa, $HorasPlano = $null, [datetime]$Agora = (Get-Date)) {
    if (Test-Path -LiteralPath $Path) {
        try {
            $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            $p = $j.PSObject.Properties[(ConvertTo-VixChaveEmissor $Empresa)]
            if ($p) {
                $t = [datetime]::MinValue
                if ([datetime]::TryParse(('' + $p.Value), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$t)) { return [double](($Agora.ToUniversalTime() - $t).TotalHours) }
            }
        } catch { }
    }
    # Sem registro local: o plano so viu analise de IA ate esta mudanca, entao serve de semente.
    if ($null -ne $HorasPlano -and ('' + $HorasPlano) -ne '' -and ('' + $HorasPlano) -ne '-') {
        $h = 0.0
        if ([double]::TryParse(('' + $HorasPlano), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$h)) { return $h }
    }
    return $null
}
function Set-VixUltimaIA([string]$Path, [string]$Empresa, [datetime]$Quando = (Get-Date)) {
    $doc = @{}
    if (Test-Path -LiteralPath $Path) {
        try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in @($j.PSObject.Properties)) { $doc[$p.Name] = '' + $p.Value } } catch { $doc = @{} }
    }
    $doc[(ConvertTo-VixChaveEmissor $Empresa)] = $Quando.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $tmp = $Path + '.tmp-' + $PID
    [IO.File]::WriteAllText($tmp, ($doc | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, ($Path + '.bak')) } else { [IO.File]::Move($tmp, $Path) }
}

# ---------------------------------------------------------------------------------------
# 8. Escalada seletiva para FULL (COBERTURA-13OUT4, 2026-10-13)
# ---------------------------------------------------------------------------------------
# Por que existe. Medido em 13/10 no dry-run do modo coletor (-MaxEmissores 3, nada gravado em
# producao): o pacote barato custou ~11k por emissor contra ~178k do modo FULL, mas NAO abre a
# fonte primaria. Os tres emissores do lote, todos com manchete nova do dia, voltaram
# INCONCLUSIVO - a IA sem ferramenta nao consegue confirmar o fato na fonte. Ligar o coletor sem
# escalada deixaria todo emissor com noticia fresca em reanalise eterna.
#
# A arquitetura tem tres partes, e a terceira e a que da nome a ela:
#   1. a coleta do orquestrador (Google News RSS, HTTP real, zero token) responde "ha fato novo
#      a interpretar?" para os 104;
#   2. o pacote barato interpreta o que a coleta achou, sem ferramenta;
#   3. SO o emissor que precisa de fonte primaria volta numa segunda passada COM ferramenta.
# A escalada e por EMISSOR, nunca por lote: o mesmo lote barato fecha metade dos emissores e
# manda a outra metade para a fila de ferramenta.
#
# Todo gatilho abaixo e um caso em que o pacote barato NAO tem prova suficiente. A ordem importa:
# o primeiro que casa define motivo e prioridade, e o mais grave vence. "Sem gatilho" e o unico
# caminho que fecha o emissor sem ferramenta, e ele exige coleta completa: coleta indisponivel
# escala por definicao (regra 5 do projeto - coleta incompleta nunca vira QUIETO).
$script:VixEscaladaEwsCritico = 50
# Lote de escalada e pequeno de proposito. Cada emissor escalado abre fonte primaria na mao
# (~178k medido em 13/10), entao lote grande nao amortiza boot: multiplica exposicao a estouro
# do cap. 4 e o mesmo tamanho dos lotes FULL da matinal, a unica regua FULL com historico.
$script:VixEscaladaChunk = 4
$script:VixEscaladaPrioridades = [ordered]@{
    coleta_indisponivel    = 100
    divergencia_ia_coletor = 90
    ews_critico            = 80
    cvm_novos              = 70
    recheck_cobertura      = 60
    termo_critico          = 55
    agencia_rating         = 52
    evento_novo            = 40
}

# Pura: nenhuma rede, nenhum estado. As duas pontas sao testaveis isoladamente - cada gatilho
# escalando, e o caso sem gatilho NAO escalando.
function Get-VixEscaladaDecisao {
    param(
        [string]$Classificacao = '',
        [int]$Eventos = 0,
        [bool]$RecheckPendente = $false,
        [bool]$DivergenciaColetor = $false,
        [int]$CvmNovos = 0,
        [int]$Ews = 0,
        [bool]$ColetaIndisponivel = $false,
        [object[]]$Novas = @()
    )
    $esc = $false
    $motivo = ''
    $gatilho = ''
    if ($ColetaIndisponivel) { $esc = $true; $gatilho = 'coleta_indisponivel' }
    elseif ($DivergenciaColetor) { $esc = $true; $gatilho = 'divergencia_ia_coletor' }
    elseif ($Ews -ge $script:VixEscaladaEwsCritico) { $esc = $true; $gatilho = 'ews_critico' }
    elseif ($CvmNovos -gt 0) { $esc = $true; $gatilho = 'cvm_novos' }
    elseif ($RecheckPendente -or ('' + $Classificacao).Trim().ToUpperInvariant() -eq 'INCONCLUSIVO') { $esc = $true; $gatilho = 'recheck_cobertura' }
    else {
        $temCritico = $false
        $temAgencia = $false
        foreach ($n in @($Novas)) {
            if ($null -eq $n) { continue }
            if (-not $temCritico -and (Test-VixTituloCritico ('' + $n.titulo))) { $temCritico = $true }
            if (-not $temAgencia) {
                $vv = ConvertTo-VixTextoBusca (('' + $n.veiculo) + ' ' + ('' + $n.dominio))
                foreach ($ag in $script:VixRelevanciaAgencias) { if ($vv.Contains($ag)) { $temAgencia = $true; break } }
            }
        }
        if ($temCritico) { $esc = $true; $gatilho = 'termo_critico' }
        elseif ($temAgencia) { $esc = $true; $gatilho = 'agencia_rating' }
        elseif ($Eventos -gt 0) { $esc = $true; $gatilho = 'evento_novo' }
    }
    $pri = 0
    if ($esc) {
        if ($script:VixEscaladaPrioridades.Contains($gatilho)) { $pri = [int]$script:VixEscaladaPrioridades[$gatilho] }
        # O motivo carrega o numero observado (ews, cvm_novos, eventos) porque e ele que vai para
        # o log e para a fila persistente; o gatilho fica separado para a conta por classe.
        switch ($gatilho) {
            'ews_critico'   { $motivo = ('ews_critico_' + $Ews) }
            'cvm_novos'     { $motivo = ('cvm_novos_' + $CvmNovos) }
            'evento_novo'   { $motivo = ('evento_novo_' + $Eventos) }
            default         { $motivo = $gatilho }
        }
    } else {
        $motivo = 'sem_gatilho_de_escalada'
    }
    return @{ Escalar = $esc; Motivo = $motivo; Gatilho = $gatilho; Prioridade = $pri }
}

# ROTACAOFULL-NAORETEM1 (2026-10-13): a decisao de RETER vive aqui, pura, para ser testavel com
# fixtures em vez de so por leitura do fonte. Ate agora ela era uma condicao inline no laco de
# lotes do motor, e a unica prova de que o lote FULL da rotacao semanal nao e retido (nem
# re-escalado, pagando dois FULL pelo mesmo emissor na mesma noite) era estrutural: um assert que
# procurava a string `$job.Barato` no texto do motor. Condicao que so se prova por grep passa a
# valer por acidente - basta alguem reordenar os termos. As tres condicoes, e por que cada uma:
#   Ativa    - sem a escalada ligada nao existe retencao nenhuma;
#   JaEscalada - lote de escalada nao reescala, senao a escalada se chama para sempre;
#   Barato   - SO lote que rodou SEM ferramenta pode reter. O lote FULL da rotacao semanal
#              (Sonnet, COM ferramenta, escolhido por risco, cheio de EWS >= 50) casaria gatilho
#              em quase todo emissor: a rodada boa, que ja abriu a fonte primaria, seria
#              descartada e o mesmo emissor pagaria dois lotes FULL na mesma noite. Escalada
#              existe para consertar o que o pacote barato nao conseguiu, e um lote com
#              ferramenta nao tem o que consertar.
function Test-VixEscaladaRetem([bool]$Ativa, [bool]$JaEscalada, [bool]$Barato) {
    if (-not $Ativa) { return $false }
    if ($JaEscalada) { return $false }
    if (-not $Barato) { return $false }
    return $true
}

# Ordena a fila de escalada por risco: prioridade do gatilho, depois EWS, depois nome. Dedup por
# emissor mantendo a MAIOR prioridade (o mesmo emissor pode casar dois gatilhos na mesma rodada).
function Select-VixEscaladaOrdenada {
    param([object[]]$Itens = @())
    $melhor = @{}
    foreach ($it in @($Itens)) {
        if ($null -eq $it -or $null -eq $it.Emp) { continue }
        $k = ConvertTo-VixChaveEmissor ('' + $it.Emp.empresa)
        if (-not $melhor.ContainsKey($k)) { $melhor[$k] = $it; continue }
        if ([int]$it.Prioridade -gt [int]$melhor[$k].Prioridade) { $melhor[$k] = $it }
    }
    return @($melhor.Values | Sort-Object -Property @{ Expression = { [int]$_.Prioridade }; Descending = $true }, @{ Expression = { [int]$_.Emp.ews_score }; Descending = $true }, @{ Expression = { '' + $_.Emp.empresa }; Descending = $false })
}
