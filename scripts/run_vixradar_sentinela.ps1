# run_vixradar_sentinela.ps1 - varredura pontual por gatilho (SENTINELA1, 2026-08-25)
#
# Status: vigente
# Data da Versao: 2026-08-25
# Origem do Registro: implementado nesta sessao; contrato do lote copiado de
#   run_vixradar_noturno_claude.ps1 (New-BatchPrompt / Get-ParsedResultados),
#   gatilho medido contra producao v4.9.216.
# Condicao de Obsolescencia: perde validade se o modo "pontual" do Worker mudar de
#   contrato, se o protocolo RESULTADO| do lote mudar, ou se a ingestao da CVM
#   deixar de depender dos crons do Worker (ver LIMITE DE SLA abaixo).
#
# O QUE FAZ
# Detector barato na frente, analise cara atras. Roda duas vezes por hora, aos :25 e
# aos :55, das 09h25 as 17h55 em dias uteis. Na maioria das execucoes sai gastando
# ZERO token, porque o portao e um dado duro e gratuito.
#
# Entra em acao quando UMA das duas coisas e verdade:
#   1. O acervo da CVM que o Worker enxerga mudou desde a ultima vez que agimos
#      (campo cvm_fonte_last_modified do health, publico, sem credencial).
#   2. Sobrou backlog da execucao anterior (emissor deferido por teto de tokens ou
#      analise que falhou). Sem esta segunda regra, um deferido so voltaria a ser
#      olhado se a CVM publicasse de novo, o que pode nunca acontecer.
#
# SLA (SENTINELA-SYNC1 fechado em 25/08/2026)
# A latencia de ate uma hora conta da PUBLICACAO na CVM ate a analise sair, dentro
# da janela operacional. Quando o HEAD acusa Last-Modified novo, a rotina manda o
# Worker reingerir na hora, via admin_sync_cvm_auto, em vez de esperar os crons das
# 12h30 e 18h30.
#
# A credencial disso NAO e nova e NAO fica em texto puro. Sai do mesmo cofre DPAPI
# local que Coleta-Volatilidade, monitor-tasks e watch-vixradar-health ja usam,
# lido por api\Get-VixAdminCredential.ps1, cifrado no escopo CurrentUser. Nada de
# segredo novo, nada de arquitetura paralela.
#
# Degradacao explicita: sem cofre, a rotina NAO aborta. Ela registra o atraso
# medido entre a publicacao e a ingestao e segue trabalhando com o acervo que o
# Worker ja tem, que e exatamente o comportamento anterior. Perder a sincronizacao
# nao pode custar a varredura.
#
# EXIT CODES (mesma convencao de run_vixradar_agenda_semanal.ps1)
#   0 ok, inclusive o caminho sem gatilho em 0 token
#   2 claude.exe ausente          3 health do Worker inacessivel ou KV/telemetria fora
#   4 ROUTINE_API_KEY ausente     5 sem credencial Claude
#   6 ambiente contaminado ou erro de posting
#   7 probe WebSearch falhou      8 Worker recusou listar_plano_rotina
#   9 provedor/transporte (OpenRouter): todos os lotes falharam, NENHUM lote processado
#  10 PARCIAL: sobrou emissor com gatilho sem analise (deferido por teto/tempo/uso
#     desconhecido, sem resultado ou submit recusado). COBERTURA-13OUT1 (13/10/2026): o
#     deferimento por teto deixou de sair 0, porque cobertura incompleta nao e sucesso.
#     ORCAMENTOFIN1 (14/10/2026): a excecao e a execucao que nao disparou NENHUM lote por
#     falta de orcamento - essa sai SEM_ORCAMENTO/exit 0, igual ao circuito fechado, porque
#     ela nao tentou e nao entregou parte de nada. A regra e pura e unica em
#     Get-VixSentinelaResultado (lib\vixradar-cobertura.ps1).
#
# PowerShell 5.1: sem ternario, sem ?? e sem ?., BOM UTF-8 obrigatorio, exit e nao
# return (o Task Scheduler le o exit code do processo).
#
# CLAUDE-FREE-MIGRATION (2026-09-04): -ForceClaude so o operador passa, em chamada manual
# com VIXRADAR_LLM_PROVIDER='claude-manual'. O Task Scheduler nunca passa essa flag; sem
# ela o gate abaixo bloqueia com exit 86 antes de gastar qualquer token.
#
# PLANTAO1 (2026-10-19, decisao do operador): -Plantao e o modo de fim de semana e feriado,
# chamado pela matinal (lib\vixradar-plantao.ps1). So acervo novo da CVM dispara analise;
# backlog de dia util NAO e gatilho e fica preservado no estado para o proximo dia util.
param(
    [switch]$ForceClaude,
    [switch]$Plantao
)

$ErrorActionPreference = 'Continue'

$ProjectRoot    = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ScriptsDir     = Join-Path $ProjectRoot 'scripts'
$LogDir         = Join-Path $ProjectRoot 'logs\routines'
$WorkerUrl      = 'https://api.vixradar.com'
$CvmZipUrl      = 'https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_2026.zip'
$HaikuSkill     = Join-Path $ScriptsDir 'noturno-batch-haiku.md'
$SonnetSkill    = Join-Path $ScriptsDir 'noturno-batch-sonnet.md'
$DateTag        = Get-Date -Format 'yyyyMMdd'
$LogFile        = Join-Path $LogDir ('vixradar-sentinela_' + $DateTag + '.log')
$StateFile      = Join-Path $LogDir 'sentinela_state.json'
$McpConfigFile  = Join-Path $LogDir 'mcp-empty.json'

$Teto           = 8        # emissores por execucao, espelha ROTINA_PONTUAL_TETO no Worker
$TokenHardCap   = 170000   # teto da execucao (ORCAMENTO-13OUT7: 120k < custo medido de 1 emissor, 156.293; 170k cabe 1). Limite do DIA: SENTINELA_DIA em custo-config.json
# Teto de relogio, nao so de token. Medido em 25/08: dois lotes seguidos ficaram 20+
# min com o processo vivo e ~1,5s de CPU, esperando rede (provavel limite de taxa da
# assinatura depois da noturna). Sem este teto, um lote lento empurra os seguintes e a
# execucao so morre no ExecutionTimeLimit de 40 min da task, com o mutex preso ate la.
# NAO e timeout por lote: o `claude -p` ja disparado nao e interrompido no meio (ver
# pendencia SENTINELA-HANG1). Este guarda impede o efeito cascata para os lotes seguintes.
$TempoMaxMin    = 22
$SonnetEwsMin   = 38
$LoteMax        = 4
$PauseSec       = 2
$PendingAlerta  = 6        # streak de pendencia que vira alerta em vez de silencio

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    # Retry curto: OneDrive, SearchIndexer e um `tail -f` aberto por qualquer um ja
    # seguraram o handle do log por minutos (LOGLOCK1-REC). Medido nesta sessao em
    # 25/08: um tail -f de monitoramento comeu as linhas finais da primeira execucao,
    # inclusive o FIM:, e a versao anterior desta funcao DESCARTAVA a linha em silencio
    # depois de 5 tentativas. Descartar linha e falha silenciosa, familia EMAILSILENT1.
    # Agora, esgotado o retry, a linha vai para um arquivo alternativo por PID e a
    # execucao continua. Perder o rastro nunca e' opcao aceitavel.
    # -ErrorAction Stop e OBRIGATORIO aqui, nao e enfeite. Com $ErrorActionPreference
    # = 'Continue' (exigido pelo CLAUDE.md deste projeto), o IOException do Add-Content
    # e erro NAO-TERMINANTE: ele nao entra no catch, imprime em stderr e a execucao cai
    # direto na linha seguinte. Sem o -ErrorAction Stop, o retry abaixo era decorativo e
    # a linha se perdia em silencio. Medido em 25/08 nesta sessao: um tail -f segurou o
    # handle e o FIM: sumiu do log de uma execucao inteira, com o loop de retry no lugar.
    $escreveu = $false
    for ($i = 0; $i -lt 5; $i++) {
        try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop; $escreveu = $true; break }
        catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $escreveu) {
        # Rastro nunca se perde. Se o log principal esta preso, a linha vai para um
        # arquivo por PID e a execucao segue.
        $fallback = Join-Path $LogDir ('vixradar-sentinela_' + $DateTag + '_fallback_' + $PID + '.log')
        try { Add-Content -Path $fallback -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
    }
    Write-Host $line
}

function Read-State {
    if (-not (Test-Path $StateFile)) {
        return [pscustomobject]@{ worker_cvm_last_modified = ''; zip_last_modified = ''; acervo_sha256 = ''; pending = $false; pending_streak = 0; ts = '' }
    }
    try { return (Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch {
        Write-Log 'AVISO: sentinela_state.json ilegivel - tratando como estado zerado.'
        return [pscustomobject]@{ worker_cvm_last_modified = ''; zip_last_modified = ''; acervo_sha256 = ''; pending = $false; pending_streak = 0; ts = '' }
    }
}

function Write-State($workerLm, $zipLm, [bool]$pending, [int]$streak) {
    $o = [ordered]@{
        worker_cvm_last_modified = '' + $workerLm
        zip_last_modified        = '' + $zipLm
        acervo_sha256            = '' + $script:AcervoShaParaEstado
        pending                  = $pending
        pending_streak           = $streak
        ts                       = (Get-Date -Format 'o')
    }
    try { $o | ConvertTo-Json -Depth 5 | Set-Content -Path $StateFile -Encoding UTF8 }
    catch { Write-Log ('AVISO: falha ao gravar sentinela_state.json - ' + $_.Exception.Message) }
}

function Get-NomeNormalizado([string]$s) {
    $norm = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().Trim()
}

function Get-AdminSenha {
    # SENTINELA-SYNC1: mesma via ja usada por upload_volatilidade_kv.ps1,
    # monitor-tasks.ps1 e watch-vixradar-health.ps1. Cofre DPAPI CurrentUser, so
    # esta conta nesta maquina abre. Nunca em texto puro, nunca em parametro.
    $helper = Join-Path $ProjectRoot 'api\Get-VixAdminCredential.ps1'
    if (Test-Path -LiteralPath $helper) {
        $s = & $helper -AsPlainText 2>$null
        if ($s) { return $s }
    }
    if ($env:ADMIN_PASSWORD) { return $env:ADMIN_PASSWORD }
    return $null
}

function Get-RoutineKey {
    # ROTA1: o registro User e a fonte da verdade, processo longevo herda env do boot.
    $doRegistro = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    if ($doRegistro) {
        $k = $doRegistro.Trim()
        if ($k.Length -eq 0) { throw 'ROUTINE_API_KEY no registro vazia apos trim.' }
        return $k
    }
    if ($env:ROUTINE_API_KEY) {
        $k = $env:ROUTINE_API_KEY.Trim()
        if ($k.Length -eq 0) { throw 'ROUTINE_API_KEY definida porem vazia apos trim.' }
        return $k
    }
    throw 'ROUTINE_API_KEY nao definida.'
}

function Invoke-WorkerJsonUtf8 {
    # O Worker responde application/json sem charset e o PS 5.1 decodificaria como
    # ISO-8859-1, corrompendo acento em memoria. Le bytes crus e decoda UTF-8.
    param([string]$Uri, $BodyObj, [int]$TimeoutSec = 120, [int]$Depth = 16)
    $params = @{ Uri = $Uri; Method = 'Post'; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    $params.ContentType = 'application/json; charset=utf-8'
    $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($BodyObj | ConvertTo-Json -Depth $Depth -Compress))
    $resp = Invoke-WebRequest @params
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

Write-Log ('INICIO: sentinela teto=' + $Teto + ' hard=' + $TokenHardCap)
if ($Plantao) { Write-Log 'MODO: plantao (fim de semana/feriado). Gatilho so por acervo novo da CVM; backlog preservado.' }

# --- Guarda 1: mutex proprio, nao rodar duas sentinelas ---------------------
$__mutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-sentinela-v1')
if (-not $__mutex.WaitOne(0)) {
    Write-Log 'ABORT_COLISAO: outra sentinela em execucao (mutex proprio ocupado) - saindo em 0 token.'
    Write-Log 'FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=mutex_proprio'
    exit 0
}

try {

# --- Guarda 2: nao concorrer com as rotinas principais ---------------------
# Horario deslocado (:25 e :55) e a primeira defesa. Esta e a que vale quando uma
# rotina principal atrasa e invade a janela.
foreach ($par in @(@('Global\vixradar-noturno-v2', 'noturna'), @('Global\vixradar-matinal-v2', 'matinal'))) {
    $__rotMutex = New-Object System.Threading.Mutex($false, $par[0])
    $__rotLivre = $__rotMutex.WaitOne(0)
    if ($__rotLivre) { $__rotMutex.ReleaseMutex() }
    if (-not $__rotLivre) {
        Write-Log ('ABORT_COLISAO: ' + $par[1] + ' em execucao (mutex global ocupado) - saindo em 0 token. Proxima tentativa em 30 min.')
        Write-Log ('FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=colisao_' + $par[1])
        exit 0
    }
}
# MOTOR1 (2026-09-02): o lock de arquivo passou a ser TOCADO a cada lote pelo motor
# (run_vixradar_varredura.ps1), entao vivo = tocado ha menos de 30 min; alem disso e
# abandono (crash, reboot no meio da rotina). Antes o limite era 180 min sem toque, o que
# deixava a sentinela cega por 3h depois de um crash da noturna.
foreach ($rot in @('vixradar-noturno', 'vixradar-matinal')) {
    $lockFile = Join-Path $LogDir ($rot + '_' + $DateTag + '.lock')
    if (Test-Path $lockFile) {
        $idadeMin = ((Get-Date) - (Get-Item $lockFile).LastWriteTime).TotalMinutes
        if ($idadeMin -lt 30) {
            Write-Log ('ABORT_COLISAO: lock de sessao ' + $rot + ' ativo ha ' + [math]::Round($idadeMin, 1) + ' min - saindo em 0 token.')
            Write-Log ('FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=colisao_' + $rot)
            exit 0
        } else {
            Write-Log ('LOCK_ABANDONADO: ' + $rot + ' sem toque ha ' + [math]::Round($idadeMin, 1) + ' min - ignorando o lock e seguindo')
        }
    }
}

# --- Portao barato: o que mudou? -------------------------------------------
# SENTINELASHA1 (2026-10-19): decisao do portao em lib pura, provada por test-sentinela-portao.ps1.
. (Join-Path $ScriptsDir 'lib\vixradar-sentinela-portao.ps1')
if (-not (Get-Command Get-VixSentinelaPortao -ErrorAction SilentlyContinue)) { Write-Log 'ERRO: lib\vixradar-sentinela-portao.ps1 ausente'; Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=lib_portao_ausente'; exit 6 }
$estado = Read-State
# Marcador do acervo gravado no estado. So avanca quando o portao decide com ele (entrar
# ou quieto); fonte cega preserva o anterior.
$script:AcervoShaParaEstado = '' + $estado.acervo_sha256

# HEAD no zip da CVM. Custo desprezivel e e o unico jeito de saber que a fonte
# publicou algo antes do Worker ingerir.
$zipLm = ''
$zipLmUtc = $null
try {
    $head = Invoke-WebRequest -Uri $CvmZipUrl -Method Head -TimeoutSec 45 -UseBasicParsing
    $zipLm = '' + $head.Headers['Last-Modified']
    if ($zipLm) {
        $tmp = [datetime]::MinValue
        if ([datetime]::TryParse($zipLm, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$tmp)) { $zipLmUtc = $tmp }
    }
} catch {
    Write-Log ('AVISO: HEAD no zip da CVM falhou (' + $_.Exception.Message + ') - seguindo pelo health do Worker.')
}

$health = $null
try { $health = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 45 } catch { }
if ($null -eq $health) {
    Write-Log 'ERRO: health do Worker inacessivel. Nada gasto.'
    Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=health_inacessivel'
    exit 3
}
# Nunca abortar pelo 'ok' agregado: ele carrega coisas que nao sao dependencia
# desta rotina. So KV e telemetria sao.
if (-not ($health.bindings.kv -and $health.bindings.telemetria)) {
    Write-Log 'ERRO: KV ou telemetria fora no Worker - dependencia real desta rotina.'
    Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=kv_ou_telemetria_fora'
    exit 3
}

$workerLm = '' + $health.cvm_fonte_last_modified
$pendingAnterior = $false
if ($estado.pending -eq $true) { $pendingAnterior = $true }
$streak = 0
if ($estado.pending_streak) { $streak = [int]$estado.pending_streak }

# --- SENTINELASHA1 (2026-10-19): sync da ENET explicito em TODA execucao ----
# Ate 19/10 o sync dependia de `precisaSync` (data do zip > health.cvm_fonte_last_modified),
# e com o campo null desde 13/09 isso era sempre verdadeiro. O sync a cada execucao era o
# que trazia Fato Relevante da ENET durante o dia, entao ele vira regra declarada, sem
# depender do zip. O HEAD do zip fica so como informacao e para o estado. `zip_last_modified`
# so avanca com sync ok; falha de sync nao consome gatilho.
$syncFeito = $false
$zipLmParaEstado = '' + $estado.zip_last_modified
if ($zipLmUtc) {
    $atrasoMin = [math]::Round(((Get-Date).ToUniversalTime() - $zipLmUtc).TotalMinutes, 0)
    Write-Log ('FONTE: zip da CVM publicado em ' + $zipLm + ' (ha ' + $atrasoMin + ' min). Health last_modified=' + $workerLm + ' acervo_sha=' + $health.cvm_acervo_sha256 + '. Sincronizando a ENET.')
} else {
    Write-Log ('FONTE: sem Last-Modified do zip. Sincronizando a ENET mesmo assim.')
}
$senha = Get-AdminSenha
if (-not $senha) {
    # Degradacao explicita, nunca aborto em dia util: sem cofre a rotina segue com o acervo
    # que o Worker ja tem. Em plantao isso e fonte cega (o portao decide).
    Write-Log 'AVISO: cofre DPAPI da senha admin indisponivel - sem sincronizacao sob demanda. Rode api\Set-VixAdminCredential.ps1. Seguindo com o acervo atual.'
} else {
    try {
        $rs = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'admin_sync_cvm_auto'; admin_senha = $senha } -TimeoutSec 180
        if ($rs -and $rs.ok -eq $true) {
            $syncFeito = $true
            if ($zipLm) { $zipLmParaEstado = $zipLm }
            Write-Log ('SYNC: CVM reingerida sob demanda. documentos=' + $rs.sync.documentos)
        } else {
            Write-Log ('AVISO: admin_sync_cvm_auto devolveu nao-ok (' + ($rs.sync.motivo) + '). Gatilho preservado para a proxima execucao.')
        }
    } catch {
        Write-Log ('AVISO: admin_sync_cvm_auto falhou (' + $_.Exception.Message + '). Gatilho preservado para a proxima execucao.')
    }
    $senha = $null
}
# Health relido depois do sync: o portao decide sobre o acervo NOVO.
$shaAtual = '' + $health.cvm_acervo_sha256
if ($syncFeito) {
    try {
        $h2 = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 45
        if ($h2) { $workerLm = '' + $h2.cvm_fonte_last_modified; $shaAtual = '' + $h2.cvm_acervo_sha256 }
    } catch { }
}

$portao = Get-VixSentinelaPortao -ShaAtual $shaAtual -ShaEstado ('' + $estado.acervo_sha256) -WorkerLm $workerLm -WorkerLmEstado ('' + $estado.worker_cvm_last_modified) -SyncFeito $syncFeito -Pending $pendingAnterior -Plantao ([bool]$Plantao)
$acervoMudou = [bool]$portao.AcervoMudou
if ($portao.Acao -eq 'cego') {
    # PLANTAO1 + SENTINELASHA1: fonte cega nunca vira dia quieto. Estado inteiro preservado.
    Write-Log ('PORTAO: sem visao da fonte (' + $portao.Motivo + ', regua=' + $portao.Regua + '). Nao e dia quieto; backlog (' + $pendingAnterior + ', streak=' + $streak + ') preservado.')
    Write-State ('' + $estado.worker_cvm_last_modified) ('' + $estado.zip_last_modified) $pendingAnterior $streak
    Write-Log ('FIM: sentinela abortada. tokens=0 analisados=0 motivo=' + $portao.Motivo)
    exit 3
}
if ($shaAtual) { $script:AcervoShaParaEstado = $shaAtual }
if ($portao.Acao -eq 'quieto') {
    if ($portao.Motivo -eq 'plantao_sem_novidade') {
        # Em plantao o backlog nao dispara e fica para o proximo dia util.
        Write-Log ('PORTAO: plantao, acervo inalterado (regua=' + $portao.Regua + '). Backlog (' + $pendingAnterior + ', streak=' + $streak + ') fica para o proximo dia util.')
        Write-State $workerLm $zipLmParaEstado $pendingAnterior $streak
    } else {
        Write-Log ('PORTAO: acervo do Worker inalterado (regua=' + $portao.Regua + ') e sem backlog. Nada a fazer.')
        Write-State $workerLm $zipLmParaEstado $false 0
    }
    Write-Log ('FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=' + $portao.Motivo)
    exit 0
}

$motivoEntrada = $portao.Motivo
Write-Log ('PORTAO: entrando por ' + $motivoEntrada + '. regua=' + $portao.Regua + ' acervo_sha=' + $shaAtual + ' acervo_worker=' + $workerLm + ' backlog_anterior=' + $pendingAnterior + ' streak=' + $streak)

if ($streak -ge $PendingAlerta) {
    Write-Log ('ALERTA: backlog pendente ha ' + $streak + ' execucoes seguidas. Pode ser emissor que nao fecha, nao laco normal de drenagem.')
}

# --- Consulta o plano. Custo zero de LLM. ----------------------------------
try { $routineKey = Get-RoutineKey } catch { Write-Log ('ERRO: ' + $_.Exception.Message); Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=sem_routine_key'; exit 4 }

$plano = $null
try {
    $plano = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_plano_rotina'; routine_key = $routineKey; modo = 'pontual'; teto = $Teto } -TimeoutSec 180
} catch {
    Write-Log ('ERRO: listar_plano_rotina modo=pontual falhou - ' + $_.Exception.Message)
    Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=worker_recusou_plano'
    exit 8
}
if (-not $plano -or $plano.ok -ne $true) {
    Write-Log 'ERRO: Worker devolveu plano nao-ok para modo=pontual.'
    Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=plano_nao_ok'
    exit 8
}

$alvos = @($plano.emissores)
$excedente = 0
if ($plano.pontual_excedente) { $excedente = [int]$plano.pontual_excedente }
Write-Log ('PLANO: candidatos=' + $plano.pontual_candidatos + ' selecionados=' + $alvos.Count + ' excedente=' + $excedente + ' worker=' + $plano.worker_version)

if ($alvos.Count -eq 0) {
    Write-Log 'PLANO: nenhum emissor com gatilho. Backlog drenado.'
    Write-State $workerLm $zipLmParaEstado $false 0
    Write-Log 'FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=plano_vazio'
    exit 0
}
foreach ($a in $alvos) {
    Write-Log ('  ALVO ' + $a.empresa + ' tier=' + $a.tier + ' cvm_novos=' + $a.cvm_novos + ' fr=' + $a.cvm_novos_fato_relevante + ' motivos=' + ($a.motivos -join ','))
}

# FALHAPROVIDERDIA1 (2026-10-10): um FIM do proprio dia com lotes_falha_provider>0 basta.
# Em 09/10 o mesmo lote falho repetiu 16 vezes, 0 analise, e queimou a cota real mesmo
# com tokens=0 no trabalho. O proximo disparo sai antes do modelo. O arquivo de log muda
# com a data, entao o dia util seguinte volta a tentar. Dia sem esse FIM devolve false.
function Test-VixSentinelaFalhaProviderNoDia([string]$CaminhoLog) {
    if (-not $CaminhoLog) { return $false }
    if (-not (Test-Path -LiteralPath $CaminhoLog)) { return $false }
    $linhas = @()
    try { $linhas = @(Get-Content -LiteralPath $CaminhoLog -Encoding UTF8 -ErrorAction Stop) }
    catch { return $false }
    foreach ($linha in $linhas) {
        if ($linha -match 'FIM:.*lotes_falha_provider=(\d+)') {
            if ([int]$Matches[1] -gt 0) { return $true }
        }
    }
    return $false
}

if (Test-VixSentinelaFalhaProviderNoDia $LogFile) {
    Write-Log 'FALHA_PROVIDER_JA_NO_DIA: ja houve lote com falha de provedor hoje. Nenhum modelo dispara; backlog intacto.'
    Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
    Write-Log ('FIM: sentinela resultado=ADIADA_FALHA_PROVIDER. tokens=0 analisados=0 submit_fail=0 deferidos=0 sem_resultado=0 excedente_worker=' + $excedente + ' buscas=0 backlog=True lotes_ok=0 lotes_falha_provider=0 motivo=falha_provider_ja_no_dia')
    exit 0
}

# CLAUDE-FREE-MIGRATION (2026-09-04): daqui pra frente a sentinela gasta LLM (claude por
# lote). Sem provider manual forcado, bloqueia com exit 86 ANTES do Get-Command claude, da
# sonda WebSearch e de qualquer claude. Provider 'none' (default) ou 'claude-manual' sem a
# flag = BLOQUEADO. A task segue Enabled de proposito: bloqueio visivel, nao rotina morta.
. (Join-Path $ScriptsDir 'lib\vixradar-llm-provider.ps1')
# Fase B D1 (2026-09-04): adapter OpenRouter e opcional. Ausencia do arquivo nao derruba
# os outros providers (none/claude-manual seguem intactos); so o provider 'openrouter'
# exige o adapter e o gate abaixo aborta 86 se ele nao existir.
if (Test-Path (Join-Path $ScriptsDir 'lib\vixradar-openrouter.ps1')) {
    . (Join-Path $ScriptsDir 'lib\vixradar-openrouter.ps1')
    $script:VixLibOpenRouterOk = $true
} else {
    $script:VixLibOpenRouterOk = $false
}

# COLETOR-PS1 (2026-09-23): a coleta de evidencia sai do modelo e vira fetch proprio. O porque
# esta no cabecalho de scripts/lib/vixradar-coletor.ps1. Desligavel por VIXRADAR_COLETOR_PS=0,
# que existe para medir token com e sem coletor na MESMA rotina, sem editar codigo.
$script:VixColetorAtivo = $false
$script:VixColetorCache = @{}
$__coletorLib = Join-Path $ScriptsDir 'lib\vixradar-coletor.ps1'
if (Test-Path $__coletorLib) {
    . $__coletorLib
    $__flagColetor = [Environment]::GetEnvironmentVariable('VIXRADAR_COLETOR_PS', 'Process')
    if (-not $__flagColetor) { $__flagColetor = [Environment]::GetEnvironmentVariable('VIXRADAR_COLETOR_PS', 'User') }
    if (-not $__flagColetor) { $__flagColetor = [Environment]::GetEnvironmentVariable('VIXRADAR_COLETOR_PS', 'Machine') }
    if (('' + $__flagColetor).Trim() -ne '0') { $script:VixColetorAtivo = $true }
    Write-Log ('COLETOR_PS: ativo=' + $script:VixColetorAtivo + ' (VIXRADAR_COLETOR_PS; 0 desliga)')
} else {
    Write-Log 'COLETOR_PS: lib ausente - a evidencia continua sendo buscada pelo modelo.'
}

# CIRCUITOSENTINELA1 (2026-10-09): a sentinela passa a LER o circuito de custo do dia.
# Ate aqui ela consumia o orcamento do dia mas nao era limitada por ele: Get-VixTokensSentinela
# soma o tokens= do FIM ao ledger diario, e a unica trava local era o cap por execucao (120k).
# Em 09/10/2026 isso somou 10.558.736 tokens contra TETO_DIA=1.300.000 na regua das rotinas
# locais, abriu o CIRCUITO_ABERTO e DEFERIU as 104 analises da noturna e as 22 da matinal.
$__custoLib = Join-Path $ScriptsDir 'lib\vixradar-custo.ps1'
$script:VixCustoLibOk = $false
if (Test-Path $__custoLib) {
    . $__custoLib
    $script:VixCustoLibOk = ($null -ne (Get-Command Get-VixCustoDia -ErrorAction SilentlyContinue))
}
if (-not $script:VixCustoLibOk) { Write-Log 'AVISO: lib\vixradar-custo.ps1 ausente - sentinela roda sem o circuito do dia (comportamento anterior)' }
# COBERTURA-13OUT1 (2026-10-13): usage do Codex lido do JSONL, contexto enxuto, teto por
# emissor antes do lote e fila pendente persistente. Lib obrigatoria: sem ela a sentinela
# voltaria a gravar tokens=0 para consumo desconhecido.
$__coberturaLib = Join-Path $ScriptsDir 'lib\vixradar-cobertura.ps1'
if (-not (Test-Path -LiteralPath $__coberturaLib)) { Write-Log 'ERRO: lib\vixradar-cobertura.ps1 ausente - sentinela nao dispara sem medir consumo.'; exit 1 }
. $__coberturaLib

$script:VixUsaOpenRouter = (Test-VixUsaLlmAdapterHttp)
$script:VixUsaCodex = ((Get-VixLlmProvider) -eq 'codex')
$openRouterAdapterHabilitado = ($script:VixLibOpenRouterOk -and (Get-Command 'Invoke-VixOpenRouterLote' -ErrorAction SilentlyContinue) -and (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue))
$codexAdapterHabilitado = ($null -ne (Get-Command 'codex' -ErrorAction SilentlyContinue))
if (-not (Test-VixLlmProviderPermiteRotina -ForceClaude:$ForceClaude -OpenRouterAdapterHabilitado:$openRouterAdapterHabilitado -CodexAdapterHabilitado:$codexAdapterHabilitado)) {
    Write-Log (Get-VixLlmBloqueadoMsg 'run_vixradar_sentinela.ps1')
    Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
    Write-Log 'FIM: sentinela bloqueada sem provider. tokens=0 analisados=0 motivo=sem_provider'
    exit $VixLlmBloqueadoExit
}

# --- A partir daqui gasta LLM. Guardas de ambiente antes do primeiro token. --
# Fase B D1 (2026-09-04): provider openrouter nao usa auth Claude, nao roda probe WebSearch do
# CLI e nao exige claude.exe. O adapter tem a chave OpenRouter (ambiente) e as server tools
# web_search/web_fetch nativas; a credencial ja foi validada externamente pelo operador.
foreach ($f in @($HaikuSkill, $SonnetSkill)) {
    if (-not (Test-Path $f)) {
        Write-Log ('ERRO: skill de lote ausente ' + $f)
        Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
        Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=skill_ausente'
        exit 6
    }
}
if ($script:VixUsaCodex) {
    Write-Log 'AUTH_MODO: codex (assinatura Codex CLI, sem OpenRouter e sem auth Anthropic)'
} elseif ($script:VixUsaOpenRouter) {
    $__orBoot = Test-VixOpenRouterPronto
    if (-not $__orBoot.ok) {
        Write-Log ('ERRO: ' + $__orBoot.motivo)
        Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
        Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=openrouter_nao_pronto'
        exit 5
    }
    Write-Log ('AUTH_MODO: ' + (Get-VixLlmEndpointDescricao) + ' (adapter HTTP, sem claude, sem auth Anthropic). busca_web=' + (Test-VixLlmEndpointTemBusca))
} else {
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Log 'ERRO: claude.exe ausente.'
        Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
        Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=claude_ausente'
        exit 2
    }
    Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding UTF8
    . (Join-Path $ScriptsDir 'lib\vixradar-claude-auth.ps1')
    . (Join-Path $ScriptsDir 'lib\vixradar-ambient-check.ps1')

    Initialize-VixClaudeAuth -McpConfigFile $McpConfigFile | Out-Null
    $__claudeAuthModo = Get-VixClaudeAuthModo
    # CLAUDEFALLBACK-OR1 (2026-09-22): mesmo desvio dos outros drivers - so ativa com
    # VIXRADAR_CLAUDE_FALLBACK_PROVIDER=openrouter explicito. Ver vixradar-llm-provider.ps1.
    if ($__claudeAuthModo -eq 'nenhum' -and (Get-VixClaudeFallbackOpenRouterHabilitado) -and $script:VixLibOpenRouterOk -and (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue)) {
        $__claudeFrBoot = Test-VixOpenRouterPronto
        if ($__claudeFrBoot.ok) {
            Write-Log 'FALLBACK_OPENROUTER: assinatura sem credencial, desviando a sentinela para openrouter (VIXRADAR_CLAUDE_FALLBACK_PROVIDER=openrouter).'
            $script:VixUsaOpenRouter = $true
        } else {
            Write-Log ('FALLBACK_OPENROUTER: fallback habilitado mas adapter nao pronto (' + $__claudeFrBoot.motivo + '). Sem desvio possivel.')
        }
    }
    if ($script:VixUsaOpenRouter) {
        Write-Log 'AUTH_MODO: openrouter (fallback da assinatura esgotada, adapter HTTP D1)'
    } elseif ($__claudeAuthModo -eq 'nenhum') {
        Write-Log 'ERRO: nenhuma credencial Claude disponivel. Abortando antes do primeiro lote.'
        Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
        Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=sem_credencial'
        exit 5
    }
    # CLAUDEFALLBACK-OR1-FIX1 (2026-09-23): o desvio para openrouter acontece DENTRO deste ramo,
    # entao o if/elseif acima decidiu so o LOG. Sem esta guarda a execucao seguia para as
    # checagens exclusivas do caminho Claude (ambiente, probe WebSearch) e morria em exit 7 mesmo
    # tendo desviado. Medido em producao em 22/09 17:57, literal: a linha 'AUTH_MODO: openrouter'
    # seguida de 'ERRO: probe WebSearch falhou'. Mesmo padrao ja correto em
    # run_vixradar_varredura.ps1:1291 e run_vixradar_agenda_semanal.ps1:369.
    if (-not $script:VixUsaOpenRouter) {
    $ambientViolacao = Test-VixClaudeAmbienteLimpo
    if ($ambientViolacao) {
        Write-Log ('AVISO: ambiente contaminado - ' + $ambientViolacao + '. Sobrescrevendo com valores oficiais Anthropic.')
        $env:ANTHROPIC_BASE_URL = 'https://api.anthropic.com'
        Remove-Item Env:\ANTHROPIC_MODEL -ErrorAction SilentlyContinue
        Remove-Item Env:\ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', '', 'Process')
        [Environment]::SetEnvironmentVariable('ANTHROPIC_MODEL', '', 'Process')
    }
    if (-not (Test-VixWebSearchProbe $McpConfigFile)) {
        Write-Log 'ERRO: probe WebSearch falhou - busca indisponivel. Nenhum submit feito.'
        Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
        Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=websearch_indisponivel'
        exit 7
    }
    }
}

function Get-VixColetorParaEmissor([string]$Empresa) {
    # Cache por emissor dentro da execucao: o mesmo emissor reaparece em retry de lote, e refazer
    # a coleta seria gastar parede do lote a toa. Nao custa token de qualquer forma, mas custa
    # tempo, e o lote tem teto de parede.
    if (-not $script:VixColetorAtivo) { return $null }
    $k = ('' + $Empresa).Trim().ToLowerInvariant()
    if ($script:VixColetorCache.ContainsKey($k)) { return $script:VixColetorCache[$k] }
    $c = $null
    try { $c = Get-VixColetorEvidencia -Empresa $Empresa } catch { $c = $null }
    $script:VixColetorCache[$k] = $c
    return $c
}

function Get-SlimEmissorSentinela($emp) {
    $docs = @($emp.cvm_documentos | Select-Object -First 3 | ForEach-Object {
        $assunto = '' + $_.assunto
        if ($assunto.Length -gt 100) { $assunto = $assunto.Substring(0, 100) }
        [pscustomobject][ordered]@{ categoria = $_.categoria; assunto = $assunto; data = $_.data; link = $_.link }
    })
    $o = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; tier = $emp.tier
        ews_score = $emp.ews_score; cvm_novos = $emp.cvm_novos; cvm_documentos = $docs
    }
    $ctx = '' + $emp.contexto_historico
    if ($ctx) {
        if ($ctx.Length -gt 300) { $ctx = $ctx.Substring(0, 300) }
        $o['contexto_historico'] = $ctx
    }
    # COLETOR-PS1: evidencia factual, coletada por este processo e nao pelo modelo. Quando o
    # coletor esta ligado, o modelo NAO busca - ver a instrucao no prompt. A F3 do contrato
    # (CVM/RI/fato) nao vem do RSS, vem dos cvm_documentos que o plano ja entrega, e por isso a
    # cobertura efetiva e a do coletor somada a F3 quando ha documento no plano.
    $coleta = Get-VixColetorParaEmissor ('' + $emp.empresa)
    if ($coleta) {
        $o['evidencia_coletada'] = Format-VixColetorEvidenciaTexto $coleta
        $f1 = 0; $f2 = 0
        try { $f1 = [int]$coleta.por_familia['F1'] } catch { $f1 = 0 }
        try { $f2 = [int]$coleta.por_familia['F2'] } catch { $f2 = 0 }
        $o['cobertura_familias'] = [ordered]@{
            F1 = $f1
            F2 = $f2
            F3 = $(if ($docs.Count -gt 0) { $docs.Count } else { 0 })
            origem = 'coletor PowerShell (Google News RSS) + cvm_documentos do plano'
        }
    }
    return $o
}

function New-BatchPromptSentinela($batch, $batchLabel, $modelName, $skillPath, $janelaInicio, $janelaFim) {
    $slim = @($batch | ForEach-Object { Get-SlimEmissorSentinela $_ })
    $json = $slim | ConvertTo-Json -Depth 8 -Compress
    $skill = (Get-Content $skillPath -Raw -Encoding UTF8).Trim()
    # COLETOR-PS1: quando o coletor esta ligado, a busca sai do modelo. As duas linhas abaixo sao
    # contrato da mudanca, nao enfeite. Sem a proibicao explicita o modelo busca por conta propria
    # e o ganho de token evapora; sem a regra de fontes_consultadas o campo volta a ser
    # auto-declaracao, que e exatamente a classe PROVAFALSA1 que o contrato de cobertura combate.
    $blocoColeta = ''
    $linhaBuscas = 'Ultima linha: LOTE_RESUMO|buscas=<total de buscas executadas>'
    if ($script:VixColetorAtivo) {
        $linhaBuscas = 'Ultima linha: LOTE_RESUMO|buscas=0'
        $blocoColeta = @"
COLETA: a busca JA FOI FEITA pelo orquestrador e esta no campo "evidencia_coletada" de cada emissor, com familia (F1 emissor, F2 divida/emissao/captacao, F3 CVM/RI/fato), data, veiculo e dominio. PROIBIDO executar busca web propria, PROIBIDO usar ferramenta de busca ou fetch. Classifique SOMENTE com a evidencia fornecida mais o "contexto_historico" e os "cvm_documentos" do proprio JSON.
FONTES: preencha "fontes_consultadas" com o que voce REALMENTE usou, copiando familia, data e dominio da evidencia. Nao invente query, veiculo nem resultado. Se a evidencia de um emissor vier vazia (EVIDENCIA_VAZIA), a classificacao e NENHUM com "sem_eventos":true e "cobertura_nota" dizendo que nao houve publicacao na janela.
"@
    }
    return @"
Execute lote $batchLabel ($($batch.Count) emissores). Modelo: $modelName. Sequencial. Sem subagentes. Sem arquivos locais. Sem chamadas HTTP de submit - o orquestrador grava os resultados.
JANELA: $janelaInicio a $janelaFim
CONTEXTO: varredura pontual, disparada por documento novo na CVM ou por analise pendente. Foque no que mudou desde a ultima analise deste emissor.
PROIBIDO: markdown, tabelas, backticks, headers, narrativa, texto fora do protocolo abaixo.
SAIDA - exatamente estas linhas e nada mais:
1 linha por emissor: RESULTADO|<empresa exatamente como no JSON, com acentuacao identica>|<objeto resultado em JSON compacto de linha unica>
Formato do objeto resultado: {"classificacao_geral":"CRITICO|RELEVANTE|ECO|NENHUM","sem_eventos":true,"cobertura_nota":"...","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"...","resultado":"..."}]}
Cada evento em CRITICO/RELEVANTE EXIGE: memo_acontecimento (2-3 frases), memo_importancia_credito, memo_monitorar. Sem esses 3 campos o evento fica incompleto - nao omitir.
$linhaBuscas
Anomalia operacional (opcional, max 1): ANOTA|<frase curta>
$blocoColeta
JSON:
$json

$skill
"@
}

function Stop-ArvoreProcesso([int]$ProcId) {
    # PS 5.1 nao tem Process.Kill($true), que so existe do .NET Core 3.0 em diante.
    # Matar so o pai deixaria o node filho vivo segurando a conexao, que e onde o
    # trabalho de verdade acontece: `claude.exe` e lancador. taskkill /T mata a arvore.
    try { & taskkill.exe /PID $ProcId /T /F 2>&1 | Out-Null } catch { }
    Start-Sleep -Milliseconds 300
    try {
        $p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
        if ($p) { Stop-Process -Id $ProcId -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Invoke-VixProcessoComArquivos {
    # EXITCODEPROC1 (2026-10-10): no powershell.exe 5.1 (o parser que as tarefas usam) o
    # objeto devolvido por `Start-Process -PassThru` NAO popula .ExitCode - medido nas duas
    # versoes: no 5.1 fica $null mesmo depois de WaitForExit()/Refresh(), e o log saia
    # "codex exit=" sem numero, escondendo QUAL foi a falha. Aqui o processo sai por
    # System.Diagnostics.Process, que expoe ExitCode de forma confiavel nas duas versoes.
    # O desenho continua sendo ARQUIVO (le stdin do prompt, grava stdout/stderr em arquivo),
    # e nao pipe, pelo mesmo motivo do comentario do Invoke-ClaudeBatchSentinela: com pipe,
    # buffer cheio bloqueia o filho e o pai bloqueia lendo (deadlock de 25/08). Por isso os
    # dois fluxos de saida sao drenados em paralelo (ReadToEndAsync) e o stdin e fechado
    # ANTES do WaitForExit, senao o filho que le stdin ate o fim espera EOF para sempre.
    param(
        [string]$Exe,
        [string]$ArgumentLine,
        [string]$StdinPath,
        [string]$StdoutPath,
        [string]$StderrPath,
        [int]$TimeoutMs
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $ArgumentLine
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $tOut = $proc.StandardOutput.ReadToEndAsync()
    $tErr = $proc.StandardError.ReadToEndAsync()
    $fsIn = $null
    if ($StdinPath -and (Test-Path -LiteralPath $StdinPath)) {
        $fsIn = [System.IO.File]::OpenRead($StdinPath)
        $tIn = $fsIn.CopyToAsync($proc.StandardInput.BaseStream)
        try { [void]$tIn.Wait(60000) } catch { }
        try { $fsIn.Dispose() } catch { }
    }
    try { $proc.StandardInput.Close() } catch { }
    $exited = $proc.WaitForExit($TimeoutMs)
    if (-not $exited) {
        Stop-ArvoreProcesso $proc.Id
        [void]$proc.WaitForExit(8000)
    }
    $textoOut = ''
    $textoErr = ''
    try { $textoOut = $tOut.GetAwaiter().GetResult() } catch { }
    try { $textoErr = $tErr.GetAwaiter().GetResult() } catch { }
    try { [System.IO.File]::WriteAllText($StdoutPath, $textoOut, (New-Object System.Text.UTF8Encoding($false))) } catch { }
    try { [System.IO.File]::WriteAllText($StderrPath, $textoErr, (New-Object System.Text.UTF8Encoding($false))) } catch { }
    $code = $null
    try { $code = $proc.ExitCode } catch { }
    try { $proc.Dispose() } catch { }
    return @{ Exit = $code; TimedOut = (-not $exited) }
}

function Invoke-ClaudeBatchSentinela([string]$promptPath, [string]$Model, [int]$TimeoutMin, [string]$Tier = '', [string]$ProviderOverride = '') {
    # CODEXFALLBACK-OR1 (2026-10-14): ProviderOverride existe para o desvio de UM lote do
    # Codex para o adapter OpenRouter quando o Codex fica inutilizavel (cota, credencial,
    # modelo indisponivel ou indisponibilidade persistente). Vale so para esta invocacao;
    # a decisao (e a guarda contra recursao) vive em Get-VixCodexFailoverDecisao.
    $providerSentinela = if ($ProviderOverride) { $ProviderOverride.Trim().ToLowerInvariant() } elseif ($script:VixUsaCodex) { 'codex' } elseif ($script:VixUsaOpenRouter) { 'openrouter' } else { 'claude' }
    $usaCodexS = ($providerSentinela -eq 'codex')
    $usaOrS = ($providerSentinela -eq 'openrouter')
    $providerOverrideAtivoS = [bool]$ProviderOverride
    # SENTINELA-HANG1: timeout de verdade, com morte da arvore de processos.
    #
    # O desenho antigo era `Get-Content | claude -p`, pipeline sem timeout nenhum.
    # Medido em 25/08: dois lotes ficaram 20+ min com o processo vivo e ~1,5s de CPU
    # acumulado, esperando rede. O lote so morreria no ExecutionTimeLimit de 40 min da
    # task, com o mutex preso ate la.
    #
    # Start-Process com os tres fluxos redirecionados para ARQUIVO, em vez de pipe,
    # tambem elimina o deadlock classico: com pipe, o buffer de stderr enche, o filho
    # bloqueia escrevendo e o pai bloqueia lendo stdout. Com arquivo, quem escreve e o
    # sistema. O stdin sai do proprio arquivo de prompt, que ja existia.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $stderrFile = Join-Path $LogDir ('sentinela_stderr_' + $DateTag + '_' + $PID + '.txt')
    $stdoutFile = Join-Path $LogDir ('sentinela_stdout_' + $DateTag + '_' + $PID + '.json')
    $raw = $null
    $timedOut = $false
    $falhaTransporte = $false
    $falhaMsg = ''
    $script:VixSentUltimaClasseFalha = ''
    $script:VixSentUltimaSemPerspectiva = $false
    try {
        # Fase B D1 (2026-09-04): provider openrouter despacha para o adapter HTTP proprio
        # (lib\vixradar-openrouter.ps1), com as server tools web_search/web_fetch. Sem claude,
        # sem auth Anthropic, sem escalacao paga. Retry bounded interno ao adapter (tem timeout
        # de parede proprio, VIXRADAR_OPENROUTER_TIMEOUT_MIN); falha deixa os emissores intactos
        # no backlog, mesmo efeito do timeout do claude.
        if ($usaCodexS) {
            $codexResultFile = Join-Path $LogDir ('sentinela_codex_result_' + $DateTag + '_' + $PID + '.txt')
            $codexStdoutFile = Join-Path $LogDir ('sentinela_codex_stdout_' + $DateTag + '_' + $PID + '.jsonl')
            Remove-Item $codexResultFile,$codexStdoutFile -Force -ErrorAction SilentlyContinue
            $exe = (Get-Command codex -ErrorAction Stop).Source
            # CODEX-SKILLBLOCK1 (2026-10-09): o Codex anunciava as skills do host
            # (~/.agents/skills) ao modelo, que tentava le-las via `pwsh -Command Get-Content` e
            # levava "blocked by policy" do sandbox read-only. Todos os lotes de 09/10/2026
            # sairam FALLO_PROVEEDOR com 0 analise (sentinela_stderr_20261009_*.txt). O prompt ja
            # embute a skill em texto; desligar a descoberta de skills do host NAO afrouxa o
            # sandbox (segue read-only, --ignore-user-config, --ignore-rules).
            # COBERTURA-13OUT1: Get-VixCodexArgsBase tira catalogo de skills, permissoes, apps e
            # plugins do contexto (50.309 -> 14.468 chars por passo, codex debug prompt-input).
            $args = @(Get-VixCodexArgsBase) + @('--search','exec','--json','--ephemeral','--sandbox','read-only','--ignore-user-config','--ignore-rules','--skip-git-repo-check','-C',('"'+$env:TEMP+'"'),'-o',('"'+$codexResultFile+'"'),'-')
            $resProc = Invoke-VixProcessoComArquivos -Exe $exe -ArgumentLine ($args -join ' ') -StdinPath $promptPath -StdoutPath $codexStdoutFile -StderrPath $stderrFile -TimeoutMs ($TimeoutMin * 60 * 1000)
            if ($resProc.TimedOut) {
                $timedOut=$true
                Write-Log ('TIMEOUT: lote Codex passou de ' + $TimeoutMin + ' min. Lote morto com a arvore.')
            }
            # COBERTURA-13OUT1: o usage do Codex vem no JSONL do stdout (turn.completed). Ate
            # 13/10 este arquivo era apagado sem ser lido, o envelope saia sem usage e TODO lote
            # Codex virava CAP_USO_DESCONHECIDO com FIM tokens=0.
            $usoCodexS = @{ mensuravel = $false }
            if (Test-Path -LiteralPath $codexStdoutFile) { $usoCodexS = Get-VixCodexUsageJsonl (Get-Content -LiteralPath $codexStdoutFile -Encoding UTF8) }
            $usageEnv = $null
            # CODEXFALLBACK-OR1: custo medido da tentativa do Codex, para o desvio nao perder a
            # contabilidade. -1 = desconhecido (consumo desconhecido nunca vira zero no chamador).
            $__fxTokS = [int64]-1
            if ($usoCodexS.mensuravel) {
                $parcCodexS = ConvertTo-VixParcelasCodex $usoCodexS
                $__fxTokS = [int64]$parcCodexS.input + [int64]$parcCodexS.output + [int64]$parcCodexS.cache_creation
                $usageEnv = [ordered]@{ input_tokens = $parcCodexS.input; output_tokens = $parcCodexS.output; cache_creation_input_tokens = 0; cache_read_input_tokens = 0 }
                Write-Log ('USAGE_CODEX: eventos=' + $usoCodexS.eventos + ' input_total=' + $usoCodexS.input_total + ' cached_input=' + $usoCodexS.cached + ' output=' + $usoCodexS.output + ' reasoning=' + $usoCodexS.reasoning)
            }
            if (-not $timedOut -and $resProc.Exit -eq 0 -and (Test-Path -LiteralPath $codexResultFile)) {
                # CODEX-PSDECOR1 (2026-10-09): ver run_vixradar_varredura.ps1 - Get-Content -Raw
                # anexa note properties (PSPath/.../ReadCount) que o ConvertTo-Json serializa e
                # quebram o parse do lote. O cast [string] (ToString) as descarta.
                $codexText=[string](Get-Content -LiteralPath $codexResultFile -Raw -Encoding UTF8)
                if ([string]::IsNullOrWhiteSpace($codexText)) {
                    # CODEX-VAZIO1: exit 0 com resultado vazio nao e entrega - falha de provedor.
                    $falhaTransporte=$true
                    $falhaMsg='codex exit=0 com resultado vazio'
                    if ($usageEnv) { $raw = @(([ordered]@{ result = ''; is_error = $true; model = 'codex-subscription'; usage = $usageEnv } | ConvertTo-Json -Compress)) }
                } else {
                    $envOk = [ordered]@{result=$codexText;is_error=$false;model='codex-subscription'}
                    if ($usageEnv) { $envOk.usage = $usageEnv }
                    $raw=@(($envOk|ConvertTo-Json -Compress))
                    # CODEXFALLBACK-OR1: lote entregue zera o contador de falhas consecutivas
                    # do provedor (separa instabilidade de indisponibilidade persistente).
                    $script:VixCodexProviderFalhasConsecutivas = 0
                }
            } else {
                $falhaTransporte=$true
                $falhaMsg='codex exit=' + $(if ($resProc.TimedOut) { 'timeout' } elseif ($null -eq $resProc.Exit) { 'indisponivel' } else { '' + $resProc.Exit })
                if(Test-Path $codexStdoutFile){$raw=Get-Content $codexStdoutFile -Encoding UTF8}
                # Lote que falhou tambem gastou: quando o JSONL trouxe usage, ele vai no envelope.
                if ($usageEnv) { $raw = @(([ordered]@{ result = ''; is_error = $true; model = 'codex-subscription'; usage = $usageEnv } | ConvertTo-Json -Compress)) }
                $errTxtS = ''
                if (Test-Path -LiteralPath $stderrFile) { $errTxtS = '' + (Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue) }
                $clsS = Get-VixClasseFalhaProvider ($errTxtS + ' ' + (@($raw) -join ' '))
                $script:VixSentUltimaClasseFalha = $clsS.Classe
                $script:VixSentUltimaSemPerspectiva = [bool]$clsS.SemPerspectiva
                $falhaMsg = $falhaMsg + ' classe=' + $clsS.Classe
            }
            Remove-Item $codexResultFile,$codexStdoutFile -Force -ErrorAction SilentlyContinue
            # CODEXFALLBACK-OR1 (2026-10-14): o Codex e o provedor ativo e nao tinha fallback.
            # Desvio opt-in, fail-closed, de UM lote para o adapter OpenRouter. A regra pura
            # (classes elegiveis + guarda contra recursao + destino pronto) vive em
            # Get-VixCodexFailoverDecisao; aqui entram so os fatos medidos neste lote.
            if ($falhaTransporte) {
                $script:VixCodexProviderFalhasConsecutivas = [int]$script:VixCodexProviderFalhasConsecutivas + 1
                $__fxHabS = (Get-VixCodexFallbackOpenRouterHabilitado)
                $__fxDestS = $false
                if ($__fxHabS -and -not $providerOverrideAtivoS -and $script:VixLibOpenRouterOk -and (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue)) {
                    $__fxBootS = Test-VixOpenRouterPronto
                    $__fxDestS = [bool]$__fxBootS.ok
                    if (-not $__fxDestS) { Write-Log ('FALLBACK_OPENROUTER_CODEX: habilitado, mas o destino nao esta pronto (' + $__fxBootS.motivo + '). Sem desvio; vale o fail-closed anterior.') }
                }
                $__fxDecS = Get-VixCodexFailoverDecisao -Classe $script:VixSentUltimaClasseFalha -FalhasConsecutivas $script:VixCodexProviderFalhasConsecutivas -DestinoPronto $__fxDestS -Habilitado $__fxHabS -ProviderOverrideAtivo $providerOverrideAtivoS
                if ($__fxDecS -eq 'failover') {
                    Write-Log ('FALLBACK_OPENROUTER_CODEX: codex classe=' + $script:VixSentUltimaClasseFalha + ' tokens_codex=' + $(if ($__fxTokS -ge 0) { '' + $__fxTokS } else { 'NAO_MENSURAVEL' }) + ' - transferindo somente este lote para openrouter (VIXRADAR_CODEX_FALLBACK_PROVIDER=openrouter).')
                    $__fxRespS = Invoke-ClaudeBatchSentinela $promptPath $Model $TimeoutMin $Tier -ProviderOverride 'openrouter'
                    if ($__fxRespS) {
                        $__fxRespS['TokensFalhaFallback'] = $__fxTokS
                        return $__fxRespS
                    }
                    Write-Log 'FALLBACK_OPENROUTER_CODEX: o adapter nao devolveu lote; seguindo o fail-closed do Codex.'
                } else {
                    Write-Log ('FALLBACK_OPENROUTER_CODEX: sem desvio (decisao=' + $__fxDecS + ' classe=' + $script:VixSentUltimaClasseFalha + ' habilitado=' + $__fxHabS + ' destino_pronto=' + $__fxDestS + ' override=' + $providerOverrideAtivoS + ').')
                }
            }
        } elseif ($usaOrS) {
            # SENTINELA-SEARCHBUDGET2 (2026-09-29): 8 buscas/emissor = 40 resultados
            # com max_results=5 e deixou EcoRodovias sem RESULTADO quando a F3 exigiu
            # fallback apos PDF CVM ilegivel. A Sentinela trabalha com lotes pequenos e
            # turbo; 12 buscas/emissor eleva o teto para 60 sem transformar em quota.
            $__orResp = Invoke-VixOpenRouterLote -PromptPath $promptPath -Tier $Tier -TotalTimeoutSec ($TimeoutMin * 60) -Emissores $job.Chunk.Count -BuscasPorEmissor 12
            $raw = @($__orResp.Linhas)
            if ($__orResp.ExitCode -ne 0) {
                $falhaTransporte = $true
                $falhaMsg = '' + $__orResp.Msg
                $clsOr = Get-VixClasseFalhaProvider $falhaMsg
                $script:VixSentUltimaClasseFalha = $clsOr.Classe
                $script:VixSentUltimaSemPerspectiva = [bool]$clsOr.SemPerspectiva
            }
        } else {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $OutputEncoding = [System.Text.Encoding]::UTF8
            Set-VixClaudeAuthEnv
            $exe = (Get-Command claude -ErrorAction SilentlyContinue).Source
            if (-not $exe) { throw 'claude.exe ausente no PATH' }
            # ASPAS OBRIGATORIAS no caminho do mcp-config. Start-Process junta o
            # -ArgumentList com espaco e NAO cita nada, entao
            # "E:\Diretorio\Claude\Monitoramento de Credito\..." chegava ao claude como
            # tres argumentos e todo lote morria com "Invalid MCP configuration:
            # MCP config file not found: E:\Diretorio\Claude\Monitoramento".
            # O pipeline antigo nao sofria porque quem montava a linha era o PowerShell.
            # Achado na verificacao de entrega de 26/08, antes da primeira execucao
            # agendada: sem isto a rotina rodaria 16 vezes por dia entregando zero analise.
            $argumentos = @(
                '-p',
                '--model', $Model,
                '--permission-mode', 'bypassPermissions',
                '--output-format', 'json',
                '--tools', 'WebSearch,WebFetch',
                '--strict-mcp-config', '--mcp-config', ('"' + $McpConfigFile + '"'),
                '--setting-sources', 'project',
                '--disable-slash-commands',
                '--no-session-persistence',
                '--exclude-dynamic-system-prompt-sections'
            )
            Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue
            $resProc = Invoke-VixProcessoComArquivos -Exe $exe -ArgumentLine ($argumentos -join ' ') -StdinPath $promptPath -StdoutPath $stdoutFile -StderrPath $stderrFile -TimeoutMs ($TimeoutMin * 60 * 1000)
            if ($resProc.TimedOut) {
                $timedOut = $true
                Write-Log ('TIMEOUT: lote passou de ' + $TimeoutMin + ' min sem terminar. Lote morto com a arvore.')
                # Sem re-disparo imediato de proposito: um lote que estourou o relogio quase
                # sempre estoura de novo na sequencia, e gastaria o teto duas vezes. Quem
                # reexecuta e o backlog, na proxima janela, com os emissores intactos.
            }
            if (Test-Path $stdoutFile) { $raw = Get-Content $stdoutFile -Encoding UTF8 }
        }
    } catch {
        Write-Log ('AVISO: excecao ao invocar claude -p (' + $_.Exception.Message + ') - lote marcado como falho.')
    } finally {
        $ErrorActionPreference = $prevEAP
        Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue
    }
    $textOut = @($raw)
    $tokens = -1
    try {
        $jsonLine = @($raw) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
        if ($jsonLine) {
            $json = $jsonLine | ConvertFrom-Json
            if ($null -ne $json.result) { $textOut = @(('' + $json.result) -split "`n") }
            if ($json.usage) {
                # cache_read fora da soma: releitura de contexto e cobrada a 0.1x e nao e
                # trabalho novo. Somar inflava o acumulado contra o teto sem custo real.
                $tokens = [int]$json.usage.input_tokens + [int]$json.usage.output_tokens + [int]$json.usage.cache_creation_input_tokens
            }
        }
    } catch {
        Write-Log ('AVISO: parse do envelope JSON falhou - tokens DESCONHECIDO.')
    }
    # AUTHMODO1 (2026-09-07): Test-VixClaudeAuthFailure mora na lib vixradar-claude-auth.ps1,
    # que so dot-source o ramo claude. No ramo openrouter a funcao NAO existe e referenciarla
    # era erro de runtime que varria o FIM e devolvia exit 0 falso (ralentizando o fix do 429:
    # sentinela al 01:03:22 nao logue AVISO/FIM, apenas o error e exit 0). O adapter ja
    # reporta FalhaTransporte/FalhaMsg; a deteccion de auth Anthropic no aplica aqui.
    $authFailureFinal = $false
    if (-not $usaOrS -and -not $usaCodexS) {
        $authFailureFinal = (Test-VixClaudeAuthFailure $textOut)
    }
    return @{ Output = $textOut; Tokens = $tokens; AuthFailure = $authFailureFinal; TimedOut = $timedOut; FalhaTransporte = $falhaTransporte; FalhaMsg = $falhaMsg }
}

function Get-ParsedResultadosSentinela($outputLines) {
    $map = @{}
    $buscas = -1
    foreach ($line in @($outputLines)) {
        $t = ('' + $line).Trim()
        if ($t -match '^RESULTADO\|([^|]+)\|(\{.*\})\s*$') {
            $empName = Get-NomeNormalizado ($Matches[1].Trim())
            try { $obj = $Matches[2] | ConvertFrom-Json; if ($obj) { $map[$empName] = $obj } }
            catch { Write-Log ('AVISO: RESULTADO com JSON invalido para ' + $empName) }
        } elseif ($t -match '^LOTE_RESUMO\|buscas=(\d+)') {
            $buscas = [int]$Matches[1]
        } elseif ($t -match '^ANOTA\|(.+)$') {
            Write-Log ('ANOTA: ' + $Matches[1])
        }
    }
    return @{ Map = $map; Buscas = $buscas }
}

# --- Execucao dos lotes ----------------------------------------------------
$janelaInicio = '' + $alvos[0].janela_inicio
$janelaFim    = '' + $alvos[0].janela_fim
$tokensAcum   = 0
# FALHATRANSPORTE-TOKENS1 (2026-10-09): tokens de lote que falhou por provedor/transporte
# ficam em contador PROPRIO (visivel no FIM), nunca somados ao trabalho do dia.
$tokensFalhaProvider = 0
# USODESCONHECIDO1 (2026-10-10): quando o provedor nao emite usage nao ha medida de consumo.
# A varredura fecha o cap nesse caso (UsoMensuravel=false -> tokens_hard_hit=true); a sentinela
# ignorava o lote e continuava disparando com o acumulado parado - fail-open. Agora fecha o cap.
$usoDesconhecido = $false
$submitOk     = 0
$submitFail   = 0
$deferidos    = 0
# ORCAMENTOFIN1 (2026-10-14): a sentinela precisa distinguir "nao tentei porque nao havia
# orcamento" de "tentei e a cobertura ficou incompleta". Os dois apareciam como PARCIAL/exit 10.
# O contador abaixo separa os deferimentos por ORCAMENTO (teto de tokens da execucao,
# cap_sentinela) dos demais (tempo, uso desconhecido, disjuntor de provedor).
$deferidosOrcamento = 0
$deferidosOutros    = 0
$buscasTotal  = 0
$semResultado = 0
$lotesOk = 0
$lotesFalhaProvider = 0
# COBERTURA-13OUT1: consumo de lote que falhou sem usage, cobrado por estimativa (nunca zero),
# lotes entregues sem usage (fail-closed do dia), custo observado e disjuntor de provedor.
$tokensEstimadosFalha = [int64]0
$lotesUsoDesconhecido = 0
$custosObservadosS = New-Object System.Collections.Generic.List[object]
$disjuntorS = New-VixDisjuntorProvider
$script:VixSentUltimaClasseFalha = ''
$script:VixSentUltimaSemPerspectiva = $false
$providerExecS = if ($script:VixUsaOpenRouter) { 'openrouter' } elseif ($script:VixUsaCodex) { 'codex' } else { 'claude-subscription' }
$histCustoS = @()
if ($script:VixUsaCodex) { try { $histCustoS = @(Get-VixHistoricoCustoPorEmissor -LogDir $LogDir -Provider 'codex' -Dias 7) } catch { $histCustoS = @() } }
$histProprioS = @()
if ($script:VixUsaCodex) { try { $histProprioS = @(Get-VixHistoricoCustoSentinela -LogDir $LogDir -Provider 'codex' -Dias 7) } catch { $histProprioS = @() } }
$filaPendentePathS = Get-VixFilaPendentePath $LogDir
function Add-VixPendenteSentinela($emp, [string]$Motivo) {
    try { Add-VixFilaPendente -Path $filaPendentePathS -Empresa ('' + $emp.empresa) -Prioridade ([int]$emp.ews_score) -Motivo $Motivo -Rotina 'sentinela' -Tier ('' + $emp.tier) -SubmitRegistrado $false }
    catch { Write-Log ('FILA_PENDENTE_ERRO: add ' + $emp.empresa + ' - ' + $_.Exception.Message) }
}

# Sonnet para quem tem risco alto ou documento novo, Haiku para o resto. Mesma regra
# de Build-LlmQueues da noturna, para o custo por emissor nao divergir entre rotinas.
$filaSonnet = @()
$filaHaiku  = @()
foreach ($emp in $alvos) {
    $high = ($emp.tier -eq 'FULL') -and ((([int]$emp.ews_score) -ge $SonnetEwsMin) -or (([int]$emp.cvm_novos) -gt 0))
    if ($high) { $filaSonnet += $emp } else { $filaHaiku += $emp }
}
$filaSonnet = @($filaSonnet | Sort-Object -Property @{ Expression = { [int]$_.ews_score }; Descending = $true })
$filaHaiku  = @($filaHaiku  | Sort-Object -Property @{ Expression = { [int]$_.ews_score }; Descending = $true })

$jobs = @()
$idx = 0
foreach ($fila in @(@{ N = 'sonnet'; M = 'claude-sonnet-4-6'; S = $SonnetSkill; L = $filaSonnet }, @{ N = 'haiku'; M = 'claude-haiku-4-5-20251001'; S = $HaikuSkill; L = $filaHaiku })) {
    $lista = @($fila.L)
    for ($i = 0; $i -lt $lista.Count; $i += $LoteMax) {
        $idx++
        $chunk = @($lista[$i..([Math]::Min($i + $LoteMax - 1, $lista.Count - 1))])
        $jobs += @{ Label = ($fila.N + '-' + $idx); Model = $fila.M; Tier = if ($fila.N -eq 'sonnet') { 'FULL' } else { 'LIGHT' }; Skill = $fila.S; Chunk = $chunk }
    }
}

# CIRCUITOSENTINELA1 (2026-10-09): orcamento da sentinela DENTRO do circuito do dia.
# Regra: a sentinela so pode gastar o que sobra depois de reservar a noturna e a verificacao,
# e nunca o orcamento ja consumido por elas (nem por execucoes anteriores da propria sentinela).
# Isso e o que impede uma rotina de paralisar todas as demais: em 09/10/2026 a sentinela
# somou 10.558.736 tokens ao dia, abriu CIRCUITO_ABERTO e zerou a noturna (104) e a matinal (22).
# Nao eleva teto nenhum - apenas faz a sentinela respeitar a reserva que ja existe em
# custo-config.json (RESERVA_NOTURNO/RESERVA_VERIFICACAO), hoje ignorada por ela.
$__disponivelDiaS = [int64]-1
if ($script:VixCustoLibOk) {
    $__cfgSentinela = Get-VixCustoConfig $LogDir
    $__custoDiaSentinela = Get-VixCustoDia $LogDir $DateTag $__cfgSentinela
    $__gastoSentinela = [int64]0
    # CONTABILIDADEIGUAL1 (2026-10-13): a linha de log tem de reportar o MESMO numero que decide o
    # orcamento. Get-VixDisponivelSentinela desconta `consumo` (trabalho + lote que falhou por
    # provedor/transporte, que gastou de verdade); este log descontava so `trabalho`, entao num dia
    # com falha de provedor o CIRCUITO_DIA mostrava menos gasto da sentinela do que o circuito
    # efetivamente usava - o operador lendo o log veria folga que nao existia.
    if ($__custoDiaSentinela.por_rotina.ContainsKey('sentinela')) {
        $__sentinelaRot = $__custoDiaSentinela.por_rotina['sentinela']
        $__gastoSentinela = [int64]$__sentinelaRot.trabalho
        if ($__sentinelaRot.ContainsKey('consumo')) { $__gastoSentinela = [int64]$__sentinelaRot.consumo }
    }
    $__gastoOutras = [int64]$__custoDiaSentinela.total_consumido - $__gastoSentinela
    $__reserva = [int64]$__cfgSentinela.RESERVA_NOTURNO + [int64]$__cfgSentinela.RESERVA_VERIFICACAO
    $__disponivelSentinela = Get-VixDisponivelSentinela -Custo $__custoDiaSentinela -Config $__cfgSentinela
    $__disponivelDiaS = [int64]$__disponivelSentinela
    Write-Log ('CIRCUITO_DIA: teto=' + $__cfgSentinela.TETO_DIA + ' gasto_outras=' + $__gastoOutras + ' gasto_sentinela_hoje=' + $__gastoSentinela + ' reserva_noturno+verificacao=' + $__reserva + ' disponivel_sentinela=' + $__disponivelSentinela)
    if ($__disponivelSentinela -le 0) {
        Write-Log 'CIRCUITO_SENTINELA_FECHADO: sem orcamento para a sentinela hoje (reserva da noturna/verificacao preservada). Nenhum lote dispara; backlog intacto.'
        Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
        Write-Log ('FIM: sentinela resultado=SEM_ORCAMENTO. tokens=0 analisados=0 submit_fail=0 deferidos=0 sem_resultado=0 excedente_worker=' + $excedente + ' buscas=0 backlog=True lotes_ok=0 lotes_falha_provider=0 motivo=circuito_sentinela')
        exit 0
    }
    if ($__disponivelSentinela -lt $TokenHardCap) {
        Write-Log ('CAP_AJUSTADO: cap da execucao ' + $TokenHardCap + ' -> ' + $__disponivelSentinela + ' (orcamento do dia disponivel para a sentinela)')
        $TokenHardCap = [int64]$__disponivelSentinela
    }
}

$inicioExec = Get-Date
foreach ($job in $jobs) {
    if ($tokensAcum -ge $TokenHardCap) {
        $deferidos += $job.Chunk.Count
        $deferidosOrcamento += $job.Chunk.Count
        foreach ($e in $job.Chunk) { Add-VixPendenteSentinela $e 'cap_sentinela' }
        Write-Log ('CAP: teto de ' + $TokenHardCap + ' tokens atingido. ' + $job.Chunk.Count + ' emissores deferidos no lote ' + $job.Label + ' - voltam na proxima execucao pelo mesmo gatilho.')
        continue
    }
    # USODESCONHECIDO1 (2026-10-10): um lote sem usage fecha o cap para os seguintes. Sem esta
    # guarda a execucao seguia disparando lote com o acumulado congelado (fail-open).
    if ($usoDesconhecido) {
        $deferidos += $job.Chunk.Count
        $deferidosOutros += $job.Chunk.Count
        foreach ($e in $job.Chunk) { Add-VixPendenteSentinela $e 'uso_desconhecido' }
        Write-Log ('CAP_USO_DESCONHECIDO: cap fechado por lote anterior sem usage. ' + $job.Chunk.Count + ' emissores deferidos no lote ' + $job.Label + '.')
        continue
    }
    # COBERTURA-13OUT1: disjuntor de provedor. Falha sem perspectiva (modelo indisponivel,
    # cota, credencial) ou duas falhas seguidas: nenhum lote novo chama o provedor nesta execucao.
    if ($disjuntorS.aberto) {
        $deferidos += $job.Chunk.Count
        $deferidosOutros += $job.Chunk.Count
        foreach ($e in $job.Chunk) { Add-VixPendenteSentinela $e 'falha_provider' }
        Write-Log ('DISJUNTOR_PROVIDER: aberto (' + $disjuntorS.motivo + ') - lote ' + $job.Label + ' nao chamado, ' + $job.Chunk.Count + ' emissores deferidos.')
        continue
    }
    $decorridoMin = ((Get-Date) - $inicioExec).TotalMinutes
    if ($decorridoMin -ge $TempoMaxMin) {
        $deferidos += $job.Chunk.Count
        $deferidosOutros += $job.Chunk.Count
        foreach ($e in $job.Chunk) { Add-VixPendenteSentinela $e 'cap_tempo' }
        Write-Log ('CAP_TEMPO: ' + [math]::Round($decorridoMin, 1) + ' min decorridos (teto ' + $TempoMaxMin + '). ' + $job.Chunk.Count + ' emissores deferidos no lote ' + $job.Label + ' - voltam na proxima execucao pelo mesmo gatilho.')
        continue
    }
    # COBERTURA-13OUT1: teto ANTES do lote, pelo custo por emissor medido (Codex). Ate 13/10 o
    # unico teste era acum >= cap, entao o primeiro lote Codex sempre disparava inteiro contra o
    # cap de 120k, sem medida (usage nunca era lido). Outros provedores seguem como antes.
    $estLoteS = [int64]0
    if ($script:VixUsaCodex) {
        $cpeS = Get-VixCustoPorEmissor -ObservadosExecucao $custosObservadosS.ToArray() -Historico $histCustoS -Default $script:VixCustoEmissorDefaultCodex -HistoricoProprio $histProprioS
        $calPathS = Get-VixCalibracaoPath $LogDir $DateTag
        $decS = Get-VixDecisaoCapSentinela -Acum $tokensAcum -Cap $TokenHardCap -CustoEstimado $cpeS.Custo -Fonte $cpeS.Fonte -Chunk $job.Chunk.Count -DisponivelDia $__disponivelDiaS -CalibracaoJaFeita (Test-Path -LiteralPath $calPathS)
        $cabemS = [int]$decS.Cabem
        if ($decS.Calibracao) {
            try { Set-Content -LiteralPath $calPathS -Value ('{"data":"' + $DateTag + '","lote":"' + $job.Label + '","estimativa":' + $cpeS.Custo + ',"cap":' + $TokenHardCap + '}') -Encoding UTF8 } catch { }
            Write-Log ('CAP_CALIBRACAO: estimativa honesta ' + $cpeS.Custo + ' (fonte=' + $cpeS.Fonte + ') nao cabe no cap ' + $TokenHardCap + ' e nao ha medicao. Roda 1 emissor, uma vez por dia, com orcamento do dia ' + $__disponivelDiaS + ' cobrindo a estimativa. RISCO DECLARADO: pode passar do cap; o pos-lote fecha o cap e a medida real substitui a estimativa.')
        } elseif ($cabemS -le 0) {
            Write-Log ('CAP_PREVENTIVO: lote ' + $job.Label + ' nao dispara. motivo=' + $decS.Motivo + ' custo_emissor=' + $cpeS.Custo + ' fonte=' + $cpeS.Fonte + ' acum=' + $tokensAcum + ' cap=' + $TokenHardCap + ' disponivel_dia=' + $__disponivelDiaS)
        }
        if ($cabemS -le 0) {
            $deferidos += $job.Chunk.Count
            $deferidosOrcamento += $job.Chunk.Count
            foreach ($e in $job.Chunk) { Add-VixPendenteSentinela $e 'cap_sentinela' }
            Write-Log ('CAP_ESTIMADO: ' + $job.Chunk.Count + ' emissor(es) do lote ' + $job.Label + ' nao cabem (custo_emissor=' + $cpeS.Custo + ' fonte=' + $cpeS.Fonte + ' acum=' + $tokensAcum + ' cap=' + $TokenHardCap + '). Deferidos para a fila pendente; matinal/noturna priorizam.')
            continue
        }
        if ($cabemS -lt $job.Chunk.Count) {
            $foraS = @($job.Chunk | Select-Object -Skip $cabemS)
            $job.Chunk = @($job.Chunk | Select-Object -First $cabemS)
            $deferidos += $foraS.Count
            $deferidosOrcamento += $foraS.Count
            foreach ($e in $foraS) { Add-VixPendenteSentinela $e 'cap_sentinela' }
            Write-Log ('CAP_LOTE_REDUZIDO: lote ' + $job.Label + ' roda ' + $cabemS + ', ' + $foraS.Count + ' deferido(s) (custo_emissor=' + $cpeS.Custo + ' fonte=' + $cpeS.Fonte + ').')
        }
        $estLoteS = [int64]$cpeS.Custo * $job.Chunk.Count
    }
    $modeloLote = $job.Model
    if ($script:VixUsaOpenRouter) { $modeloLote = 'openrouter:' + (Get-VixOpenRouterModel $job.Tier) + ' tier=' + $job.Tier }
    $modeloPrompt = $job.Model
    if ($script:VixUsaOpenRouter) { $modeloPrompt = Get-VixOpenRouterModel $job.Tier }
    # COBERTURA-13OUT1: com Codex o prompt dizia "Modelo: claude-sonnet-4-6", o modelo respondia
    # que esse modelo estava indisponivel na sessao (ANOTA de 13/10, 13:58 e 14:28) e o log
    # registrava o rotulo Claude como se fosse o executado (mesma classe do MODELOLOG1).
    if ($script:VixUsaCodex) { $modeloLote = 'codex:codex-subscription tier=' + $job.Tier; $modeloPrompt = 'codex-subscription' }
    $promptPath = Join-Path $LogDir ('sentinela_' + $job.Label + '_' + $DateTag + '_' + $PID + '.txt')
    $promptTextoS = New-BatchPromptSentinela $job.Chunk $job.Label $modeloPrompt $job.Skill $janelaInicio $janelaFim
    if ($script:VixUsaCodex) { $promptTextoS = (Get-VixCodexPreambulo) + "`r`n`r`n" + $promptTextoS }
    $promptTextoS | Set-Content -Path $promptPath -Encoding UTF8
    Write-Log ('LOTE ' + $job.Label + ': ' + $job.Chunk.Count + ' emissores, modelo ' + $modeloLote)
    # O teto por lote e o que sobra do teto da execucao, nunca mais que isso, com um
    # piso de 4 min para nao nascer expirado quando a janela ja esta quase no fim.
    $restanteMin = [int]([math]::Max(4, $TempoMaxMin - ((Get-Date) - $inicioExec).TotalMinutes))
    $res = Invoke-ClaudeBatchSentinela $promptPath $job.Model $restanteMin $job.Tier
    # CODEXFALLBACK-OR1 (2026-10-14): lote desviado do Codex para o OpenRouter. A tentativa do
    # Codex que falhou continua cobrada no consumo do dia: medida quando houve usage, estimada
    # quando nao houve (consumo desconhecido nunca vira zero, CUSTOFALHA-TETO1).
    if ($res.ContainsKey('TokensFalhaFallback')) {
        $__fxCobS = [int64]$res.TokensFalhaFallback
        if ($__fxCobS -ge 0) {
            if ($__fxCobS -gt 0) {
                $tokensFalhaProvider += $__fxCobS
                Write-Log ('FALLBACK_CODEX_COBRADO: ' + $__fxCobS + ' tokens medidos da tentativa codex que falhou antes do desvio; cobrados no consumo do dia.')
            }
        } else {
            $__fxEstS = [int64]$estLoteS
            if ($__fxEstS -le 0) { $__fxEstS = [int64]$TokenHardCap }
            if ($__fxEstS -gt 0) {
                $tokensFalhaProvider += $__fxEstS
                $tokensEstimadosFalha += $__fxEstS
                Write-Log ('FALLBACK_CODEX_COBRADO: ESTIMADO_FALHA ' + $__fxEstS + ' tokens da tentativa codex que falhou sem usage antes do desvio; cobrados no consumo do dia.')
            }
        }
    }
    if ($res.FalhaTransporte) { $lotesFalhaProvider++ }
    # FALHATRANSPORTE-TOKENS1 (2026-10-09): lote que falhou por provedor/transporte nao
    # analisou emissor nenhum - o token que ele consumiu e desperdicio, nao trabalho. Em
    # 09/10/2026 esses lotes somaram 10.558.736 tokens de "trabalho" para 0 analise, abriram
    # o circuito do dia e deferiram as 104 da noturna e as 22 da matinal. O consumo continua
    # medido e visivel em tokens_falha_provider, apenas fora do teto de trabalho.
    if ($res.Tokens -ge 0) {
        # CUSTOFALHA-TETO1 (2026-10-10): o contador proprio continua existindo para o TRABALHO
        # entregue nao ser inflado por lote que nao analisou ninguem - mas o CONSUMO do dia
        # precisa dos dois. Get-VixCustoDia soma `tokens=` + `tokens_falha_provider=` no
        # total_consumido, que e o que limita o teto. Retry dos emissores e decisao a parte.
        if ($res.FalhaTransporte) { $tokensFalhaProvider += $res.Tokens }
        else {
            $tokensAcum += $res.Tokens
            if ($job.Chunk.Count -gt 0 -and $res.Tokens -gt 0) {
                $custosObservadosS.Add([int64][Math]::Ceiling($res.Tokens / $job.Chunk.Count))
                if ($script:VixUsaCodex) { try { Add-VixCustoSentinela -LogDir $LogDir -Provider 'codex' -CustoEmissor ([int64][Math]::Ceiling($res.Tokens / $job.Chunk.Count)) -Emissores $job.Chunk.Count -Lote $job.Label } catch { Write-Log ('CUSTO_SENTINELA_ERRO: ' + $_.Exception.Message) } }
            }
            if ($tokensAcum -gt $TokenHardCap) { Write-Log ('CAP_EXCEDIDO: lote ' + $job.Label + ' custou ' + $res.Tokens + ' contra estimativa ' + $estLoteS + '; acum=' + $tokensAcum + ' > cap=' + $TokenHardCap + '. Cap fechado.') }
        }
    } elseif ($res.FalhaTransporte) {
        # COBERTURA-13OUT1: lote que FALHOU sem usage. Consumo desconhecido nunca vira zero:
        # cobra a estimativa no contador de falha (entra no CONSUMO do dia, CUSTOFALHA-TETO1).
        $estFalhaS = $estLoteS
        if ($estFalhaS -le 0) { $estFalhaS = [int64]$TokenHardCap }
        $tokensFalhaProvider += $estFalhaS
        $tokensEstimadosFalha += $estFalhaS
        Write-Log ('USO_ESTIMADO_FALHA: lote ' + $job.Label + ' falhou sem usage; cobrado ' + $estFalhaS + ' no consumo do dia (nunca zero).')
    } else {
        # USODESCONHECIDO1: sem usage nao ha como saber quanto foi consumido. Fail-closed:
        # o cap fecha para o resto da execucao em vez de seguir disparando sem medir.
        # COBERTURA-13OUT1: e o FIM passa a declarar uso_desconhecido=N, que o circuito do dia
        # (lib\vixradar-custo.ps1) le como NAO_MENSURAVEL. Antes o FIM dizia tokens=0 e o dia
        # somava zero para lotes que gastaram de verdade.
        $usoDesconhecido = $true
        $lotesUsoDesconhecido++
        Write-Log ('CAP_USO_DESCONHECIDO: lote ' + $job.Label + ' sem usage do provedor - cap fechado, diagnostico de parse suprimido.')
    }
    if ($res.FalhaTransporte) {
        $disjuntorS = Update-VixDisjuntorProvider $disjuntorS $true $script:VixSentUltimaClasseFalha ([bool]$script:VixSentUltimaSemPerspectiva)
        Write-Log ('LOTE_FALHA_PROVIDER|' + $job.Label + '|classe=' + $script:VixSentUltimaClasseFalha + '|disjuntor=' + $(if ($disjuntorS.aberto) { 'ABERTO:' + $disjuntorS.motivo } else { 'fechado' }))
    } else {
        $disjuntorS = Update-VixDisjuntorProvider $disjuntorS $false
    }
    if ($res.TimedOut) {
        # Emissores do lote ficam intactos: nada de submit, nada marcado em cvm_vistos.
        # Contam como sem_resultado, o que liga o backlog e devolve todos na proxima
        # janela pelo mesmo gatilho. Nenhum lote fica pendurado e nada se perde.
        $semResultado += $job.Chunk.Count
        foreach ($e in $job.Chunk) { Add-VixPendenteSentinela $e 'timeout_lote' }
        Write-Log ('CAP_TEMPO: lote ' + $job.Label + ' morto por timeout, ' + $job.Chunk.Count + ' emissores preservados no backlog.')
        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
        continue
    }
    if ($res.AuthFailure) {
            Write-Log 'ERRO: falha de autenticacao do claude no lote. Interrompendo, backlog preservado.'
            $null = Send-VixRoutineAlert -Rotina 'sentinela' -Motivo 'claude CLI nao autenticado ou limite atingido - emissores com gatilho nao foram analisados' -RoutineKey $routineKey -Causa 'falha_auth' -Severidade 'critico'
            Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
            Write-Log ('FIM: sentinela abortada. tokens=' + $tokensAcum + ' analisados=' + $submitOk + ' motivo=auth_falhou')
            exit 7
        }
    $parsed = Get-ParsedResultadosSentinela $res.Output
    if ($parsed.Buscas -ge 0) { $buscasTotal += $parsed.Buscas }
    if ($parsed.Map.Count -eq 0) {
        if ($res.FalhaTransporte) {
            Write-Log ('ERRO: lote ' + $job.Label + ' falhou por provedor/transporte (' + $res.FalhaMsg + ') - ' + $job.Chunk.Count + ' emissores preservados no backlog.')
        } else {
            Write-Log ('ERRO: lote ' + $job.Label + ' sem RESULTADO| - falha silenciosa, 0 de ' + $job.Chunk.Count + ' emissores analisados.')
        }
        $semResultado += $job.Chunk.Count
        $motivoSemRes = 'sem_resultado'
        if ($res.FalhaTransporte) { $motivoSemRes = 'falha_provider' }
        foreach ($e in $job.Chunk) { Add-VixPendenteSentinela $e $motivoSemRes }
        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
        continue
    }
    $lotesOk++
    foreach ($emp in $job.Chunk) {
        $obj = $parsed.Map[(Get-NomeNormalizado ('' + $emp.empresa))]
        if (-not $obj) {
            # SENTINELA-RETRY1 (2026-09-29): se um emissor for omitido em lote,
            # reprocessa somente o ausente uma vez antes de manter o backlog.
            $retryLabel = $job.Label + '-retry-' + (Get-NomeNormalizado ('' + $emp.empresa))
            $retryPrompt = Join-Path $LogDir ('sentinela_' + $retryLabel + '_' + $DateTag + '_' + $PID + '.txt')
            try {
                # COBERTURA-13OUT1: retry individual so com orcamento (Codex), com uso medido, e
                # nunca com o disjuntor aberto ou uso desconhecido na execucao.
                $retryPermitido = (-not $usoDesconhecido) -and (-not $disjuntorS.aberto) -and ($tokensAcum -lt $TokenHardCap)
                $cpeRetryS = $null
                if ($retryPermitido -and $script:VixUsaCodex) {
                    $cpeRetryS = Get-VixCustoPorEmissor -ObservadosExecucao $custosObservadosS.ToArray() -Historico $histCustoS -Default $script:VixCustoEmissorDefaultCodex -HistoricoProprio $histProprioS
                    $retryPermitido = ((Get-VixEmissoresQueCabem -Acum $tokensAcum -Cap $TokenHardCap -CustoPorEmissor $cpeRetryS.Custo -Chunk 1) -ge 1)
                }
                if (-not $retryPermitido) { throw ('retry individual suprimido: sem orcamento ou provedor bloqueado (acum=' + $tokensAcum + ' cap=' + $TokenHardCap + ' disjuntor=' + $disjuntorS.aberto + ' uso_desconhecido=' + $usoDesconhecido + ')') }
                $retryModeloPrompt = $job.Model
                if ($script:VixUsaOpenRouter) { $retryModeloPrompt = Get-VixOpenRouterModel $job.Tier }
                if ($script:VixUsaCodex) { $retryModeloPrompt = 'codex-subscription' }
                $retryTexto = New-BatchPromptSentinela @($emp) $retryLabel $retryModeloPrompt $job.Skill $janelaInicio $janelaFim
                if ($script:VixUsaCodex) { $retryTexto = (Get-VixCodexPreambulo) + "`r`n`r`n" + $retryTexto }
                $retryTexto | Set-Content -Path $retryPrompt -Encoding UTF8
                Write-Log ('RETRY_INDIVIDUAL: ' + $emp.empresa + ' ausente em ' + $job.Label + '; repetindo isoladamente uma vez.')
                $retryRestanteMin = [int]([math]::Max(4, $TempoMaxMin - ((Get-Date) - $inicioExec).TotalMinutes))
                $retryRes = Invoke-ClaudeBatchSentinela $retryPrompt $job.Model $retryRestanteMin $job.Tier
                if ($retryRes.Tokens -ge 0) {
                    if ($retryRes.FalhaTransporte) { $tokensFalhaProvider += $retryRes.Tokens }
                    else { $tokensAcum += $retryRes.Tokens }
                } elseif ($retryRes.FalhaTransporte) {
                    $estRetryS = [int64]$TokenHardCap
                    if ($cpeRetryS) { $estRetryS = [int64]$cpeRetryS.Custo }
                    $tokensFalhaProvider += $estRetryS; $tokensEstimadosFalha += $estRetryS
                    Write-Log ('USO_ESTIMADO_FALHA: retry ' + $retryLabel + ' falhou sem usage; cobrado ' + $estRetryS + ' (nunca zero).')
                } else {
                    $usoDesconhecido = $true; $lotesUsoDesconhecido++
                    Write-Log ('CAP_USO_DESCONHECIDO: retry ' + $retryLabel + ' sem usage do provedor - cap fechado.')
                }
                if ($retryRes.FalhaTransporte) { $disjuntorS = Update-VixDisjuntorProvider $disjuntorS $true $script:VixSentUltimaClasseFalha ([bool]$script:VixSentUltimaSemPerspectiva) }
                $retryParsed = Get-ParsedResultadosSentinela $retryRes.Output
                if ($retryParsed.Buscas -ge 0) { $buscasTotal += $retryParsed.Buscas }
                $obj = $retryParsed.Map[(Get-NomeNormalizado ('' + $emp.empresa))]
                if ($obj) {
                    Write-Log ('RETRY_INDIVIDUAL_OK: ' + $emp.empresa + ' recuperado.')
                } else {
                    Write-Log ('RETRY_INDIVIDUAL_FALHOU: ' + $emp.empresa + ' segue sem RESULTADO|; gatilho preservado.')
                }
            } catch {
                Write-Log ('RETRY_INDIVIDUAL_ERRO: ' + $emp.empresa + ' - ' + $_.Exception.Message)
            } finally {
                Remove-Item $retryPrompt -Force -ErrorAction SilentlyContinue
            }
            if (-not $obj) {
                $semResultado++
                Add-VixPendenteSentinela $emp 'sem_resultado'
                continue
            }
        }
        $provRotina = 'claude-sentinela-' + $job.Model
        if ($script:VixUsaOpenRouter) { $provRotina = 'openrouter-sentinela-' + (Get-VixOpenRouterModel $job.Tier) }
        # COBERTURA-13OUT1: rastreabilidade. Com Codex o estado gravava 'claude-sentinela-claude-sonnet-4-6'
        # para analise feita pelo Codex. A origem 'pontual' passa a ir explicita no corpo
        # (worker.js deriva origem do prefixo claude-sentinela quando body.origem falta).
        if ($script:VixUsaCodex) { $provRotina = 'codex-sentinela-codex-subscription' }
        $resultado = [ordered]@{
            empresa = $emp.empresa; setor = $emp.setor
            classificacao_geral = $obj.classificacao_geral
            sem_eventos = $obj.sem_eventos
            cobertura_nota = $obj.cobertura_nota
            eventos = @($obj.eventos)
            fontes_consultadas = @($obj.fontes_consultadas)
            _tier = $emp.tier; _rotina_v2 = $true; _origem = 'sentinela'
        }
        # Os ids so vao junto quando ha analise real para entregar. Se o submit falhar,
        # o Worker nao marca nada e o emissor volta na proxima execucao.
        $body = @{
            action = 'receber_analise'; routine_key = $routineKey
            empresa = $emp.empresa; setor = $emp.setor
            _matinal = $false; provedor = $provRotina; origem = 'pontual'
            resultado = $resultado
            cvm_ids_analisados = @($emp.cvm_novos_ids)
        }
        $resp = $null
        try { $resp = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj $body -TimeoutSec 120 } catch { }
        if (-not $resp -or $resp.ok -ne $true) {
            Start-Sleep -Seconds $PauseSec
            try { $resp = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj $body -TimeoutSec 120 } catch { }
        }
        if ($resp -and $resp.ok -eq $true) {
            $submitOk++
            Write-Log ('  OK| ' + $emp.empresa + ' eventos=' + $resp.n_eventos + ' cvm_marcados=' + $resp.cvm_marcados + ' fila_verif=' + $resp.pendente_verificacao_async)
            # COBERTURA-13OUT1: analise entregue solta a pendencia persistente do emissor.
            try { if (Remove-VixFilaPendente -Path $filaPendentePathS -Empresa ('' + $emp.empresa)) { Write-Log ('FILA_PENDENTE: ' + $emp.empresa + ' resolvido (analise efetiva)') } } catch { Write-Log ('FILA_PENDENTE_ERRO: remove ' + $emp.empresa + ' - ' + $_.Exception.Message) }
        } else {
            $submitFail++
            Add-VixPendenteSentinela $emp 'submit_recusado'
            Write-Log ('  FALHA| ' + $emp.empresa + ' - submit recusado, gatilho preservado.')
        }
    }
    Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
}

# --- Estado para a proxima execucao ----------------------------------------
# pending liga quando sobrou trabalho de qualquer natureza: excedente do teto do
# Worker, deferido pelo teto local, submit recusado ou lote sem resultado. Enquanto
# ligado, a proxima execucao consulta o plano mesmo sem novidade na fonte.
$sobrou = ($excedente -gt 0) -or ($deferidos -gt 0) -or ($submitFail -gt 0) -or ($semResultado -gt 0)
$novoStreak = 0
if ($sobrou) { $novoStreak = $streak + 1 }
Write-State $workerLm $zipLmParaEstado $sobrou $novoStreak

# E. EXIT CODE / HEALTH (2026-09-07): sucesso real so com pelo menos um lote processado.
# Cap/defer planejado segue exit 0; TODOS os lotes falhando por provedor/transporte nao
# pode virar sucesso falso. exit 9 = disparou mas nao processou nenhum lote.
#
# ORCAMENTOFIN1 (2026-10-14): a classificacao virou funcao PURA na lib
# (Get-VixSentinelaResultado, lib\vixradar-cobertura.ps1) e esta chamada e a UNICA fonte dela -
# a cadeia de ifs que existia aqui era uma segunda copia da mesma regra, e guarda que nao
# exercita o codigo do pipeline nao e guarda. O que mudou de comportamento: execucao que nao
# disparou NENHUM lote por falta de orcamento sai SEM_ORCAMENTO/exit 0 (mesmo estado do
# circuito fechado), em vez de PARCIAL/exit 10 - que e o estado de "rodou e entregou parte".
$__resFimS = Get-VixSentinelaResultado -LotesOk $lotesOk -LotesFalhaProvider $lotesFalhaProvider -SubmitOk $submitOk -SubmitFail $submitFail -SemResultado $semResultado -TokensAcum $tokensAcum -Deferidos $deferidos -DeferidosOrcamento $deferidosOrcamento -DeferidosOutros $deferidosOutros -Excedente $excedente
$resultadoFim = $__resFimS.Resultado
$exitFim = [int]$__resFimS.Exit
if ($resultadoFim -eq 'SEM_ORCAMENTO') {
    Write-Log ('COBERTURA_INCOMPLETA_SEM_ORCAMENTO: ' + $deferidosOrcamento + ' emissor(es) com gatilho nao couberam no orcamento do dia e foram para a fila pendente; matinal/noturna priorizam. nenhum lote foi disparado nesta execucao.')
}

# COBERTURA-13OUT1: tokens= continua sendo so o MEDIDO (trabalho). Lote entregue sem usage vai
# em uso_desconhecido=N, que lib\vixradar-custo.ps1 transforma em NAO_MENSURAVEL no circuito do
# dia (fail-closed), em vez do zero silencioso de antes. Lote que falhou sem usage foi cobrado
# por estimativa dentro de tokens_falha_provider (tokens_estimados_falha mostra quanto).
Write-Log ('FIM: sentinela resultado=' + $resultadoFim + '. tokens=' + $tokensAcum + ' analisados=' + $submitOk + ' submit_fail=' + $submitFail + ' deferidos=' + $deferidos + ' deferidos_orcamento=' + $deferidosOrcamento + ' deferidos_outros=' + $deferidosOutros + ' sem_resultado=' + $semResultado + ' excedente_worker=' + $excedente + ' buscas=' + $buscasTotal + ' backlog=' + $sobrou + ' lotes_ok=' + $lotesOk + ' lotes_falha_provider=' + $lotesFalhaProvider + ' tokens_falha_provider=' + $tokensFalhaProvider + ' uso_desconhecido=' + $lotesUsoDesconhecido + ' tokens_estimados_falha=' + $tokensEstimadosFalha + ' motivo=' + $__resFimS.Motivo + ' provider=' + $providerExecS + ' disjuntor_provider=' + $(if ($disjuntorS.aberto) { 'ABERTO:' + $disjuntorS.motivo } else { 'fechado' }))
exit $exitFim

} finally {
    if ($__mutex) { $__mutex.ReleaseMutex(); $__mutex.Dispose() }
}
