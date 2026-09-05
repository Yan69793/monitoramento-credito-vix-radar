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
#
# PowerShell 5.1: sem ternario, sem ?? e sem ?., BOM UTF-8 obrigatorio, exit e nao
# return (o Task Scheduler le o exit code do processo).
#
# CLAUDE-FREE-MIGRATION (2026-09-04): -ForceClaude so o operador passa, em chamada manual
# com VIXRADAR_LLM_PROVIDER='claude-manual'. O Task Scheduler nunca passa essa flag; sem
# ela o gate abaixo bloqueia com exit 86 antes de gastar qualquer token.
param(
    [switch]$ForceClaude
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
$TokenHardCap   = 120000   # teto de tokens da execucao; muito menor que o da noturna de proposito
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
        return [pscustomobject]@{ worker_cvm_last_modified = ''; zip_last_modified = ''; pending = $false; pending_streak = 0; ts = '' }
    }
    try { return (Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch {
        Write-Log 'AVISO: sentinela_state.json ilegivel - tratando como estado zerado.'
        return [pscustomobject]@{ worker_cvm_last_modified = ''; zip_last_modified = ''; pending = $false; pending_streak = 0; ts = '' }
    }
}

function Write-State($workerLm, $zipLm, [bool]$pending, [int]$streak) {
    $o = [ordered]@{
        worker_cvm_last_modified = '' + $workerLm
        zip_last_modified        = '' + $zipLm
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
$estado = Read-State

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

# --- SENTINELA-SYNC1: a fonte publicou, o Worker ingere AGORA ---------------
# Duas condicoes, e a segunda existe porque a primeira e cega a republicacao no
# mesmo dia: o zip esta a frente do que o Worker ingeriu, OU o Last-Modified mudou
# desde a ultima vez que esta rotina agiu. `zip_last_modified` so avanca no estado
# quando a sincronizacao volta ok, entao falha de sync nao consome o gatilho e a
# proxima execucao tenta de novo.
$syncFeito = $false
$zipLmParaEstado = '' + $estado.zip_last_modified
if ($zipLmUtc) {
    $zipDia = $zipLmUtc.ToString('yyyy-MM-dd')
    $precisaSync = ($zipDia -gt $workerLm) -or ($zipLm -ne ('' + $estado.zip_last_modified))
    if ($precisaSync) {
        $atrasoMin = [math]::Round(((Get-Date).ToUniversalTime() - $zipLmUtc).TotalMinutes, 0)
        Write-Log ('FONTE: zip da CVM publicado em ' + $zipLm + ' (ha ' + $atrasoMin + ' min). Worker ingeriu ate ' + $workerLm + '. Sincronizando.')
        $senha = Get-AdminSenha
        if (-not $senha) {
            # Degradacao explicita, nunca aborto: sem cofre a rotina segue com o
            # acervo que o Worker ja tem, que e o comportamento de antes.
            Write-Log 'AVISO: cofre DPAPI da senha admin indisponivel - sem sincronizacao sob demanda. Rode api\Set-VixAdminCredential.ps1. Seguindo com o acervo atual.'
        } else {
            try {
                $rs = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'admin_sync_cvm_auto'; admin_senha = $senha } -TimeoutSec 180
                if ($rs -and $rs.ok -eq $true) {
                    $syncFeito = $true
                    $zipLmParaEstado = $zipLm
                    Write-Log ('SYNC: CVM reingerida sob demanda. documentos=' + $rs.sync.documentos + ' empresas=' + $rs.sync.empresas + ' last_modified=' + $rs.sync.last_modified_iso)
                } else {
                    Write-Log ('AVISO: admin_sync_cvm_auto devolveu nao-ok (' + ($rs.sync.motivo) + '). Gatilho preservado para a proxima execucao.')
                }
            } catch {
                Write-Log ('AVISO: admin_sync_cvm_auto falhou (' + $_.Exception.Message + '). Gatilho preservado para a proxima execucao.')
            }
            $senha = $null
        }
    } else {
        $zipLmParaEstado = $zipLm
    }
}
# Health relido depois do sync: o acervo mudou agora, e e sobre o valor NOVO que o
# portao decide.
if ($syncFeito) {
    try {
        $h2 = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 45
        if ($h2) { $workerLm = '' + $h2.cvm_fonte_last_modified }
    } catch { }
}

$acervoMudou = ($workerLm -ne ('' + $estado.worker_cvm_last_modified)) -or $syncFeito

if (-not $acervoMudou -and -not $pendingAnterior) {
    Write-Log ('PORTAO: acervo do Worker inalterado (' + $workerLm + ') e sem backlog. Nada a fazer.')
    Write-State $workerLm $zipLmParaEstado $false 0
    Write-Log 'FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=sem_novidade'
    exit 0
}

$motivoEntrada = 'acervo_novo'
if (-not $acervoMudou) { $motivoEntrada = 'backlog' }
Write-Log ('PORTAO: entrando por ' + $motivoEntrada + '. acervo_worker=' + $workerLm + ' backlog_anterior=' + $pendingAnterior + ' streak=' + $streak)

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
$script:VixUsaOpenRouter = ((Get-VixLlmProvider) -eq 'openrouter')
if ($script:VixUsaOpenRouter) {
    if (-not $script:VixLibOpenRouterOk -or -not (Get-Command 'Invoke-VixOpenRouterLote' -ErrorAction SilentlyContinue) -or -not (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue)) {
        Write-Log 'ERRO FATAL: adapter OpenRouter ausente ou incompleto (scripts/lib/vixradar-openrouter.ps1). Provider openrouter sem adapter = bloqueio.'
        Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
        Write-Log 'FIM: sentinela bloqueada sem adapter openrouter. tokens=0 analisados=0 motivo=sem_adapter'
        exit $VixLlmBloqueadoExit
    }
} elseif (-not (Test-VixLlmPermiteClaude -ForceClaude:$ForceClaude)) {
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
if ($script:VixUsaOpenRouter) {
    $__orBoot = Test-VixOpenRouterPronto
    if (-not $__orBoot.ok) {
        Write-Log ('ERRO: ' + $__orBoot.motivo)
        Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
        Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=openrouter_nao_pronto'
        exit 5
    }
    Write-Log 'AUTH_MODO: openrouter (adapter HTTP D1, sem claude, sem auth Anthropic)'
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
    if ((Get-VixClaudeAuthModo) -eq 'nenhum') {
        Write-Log 'ERRO: nenhuma credencial Claude disponivel. Abortando antes do primeiro lote.'
        Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
        Write-Log 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=sem_credencial'
        exit 5
    }
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
    return $o
}

function New-BatchPromptSentinela($batch, $batchLabel, $modelName, $skillPath, $janelaInicio, $janelaFim) {
    $slim = @($batch | ForEach-Object { Get-SlimEmissorSentinela $_ })
    $json = $slim | ConvertTo-Json -Depth 8 -Compress
    $skill = (Get-Content $skillPath -Raw -Encoding UTF8).Trim()
    return @"
Execute lote $batchLabel ($($batch.Count) emissores). Modelo: $modelName. Sequencial. Sem subagentes. Sem arquivos locais. Sem chamadas HTTP de submit - o orquestrador grava os resultados.
JANELA: $janelaInicio a $janelaFim
CONTEXTO: varredura pontual, disparada por documento novo na CVM ou por analise pendente. Foque no que mudou desde a ultima analise deste emissor.
PROIBIDO: markdown, tabelas, backticks, headers, narrativa, texto fora do protocolo abaixo.
SAIDA - exatamente estas linhas e nada mais:
1 linha por emissor: RESULTADO|<empresa exatamente como no JSON, com acentuacao identica>|<objeto resultado em JSON compacto de linha unica>
Formato do objeto resultado: {"classificacao_geral":"CRITICO|RELEVANTE|ECO|NENHUM","sem_eventos":true,"cobertura_nota":"...","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"...","resultado":"..."}]}
Cada evento em CRITICO/RELEVANTE EXIGE: memo_acontecimento (2-3 frases), memo_importancia_credito, memo_monitorar. Sem esses 3 campos o evento fica incompleto - nao omitir.
Ultima linha: LOTE_RESUMO|buscas=<total de buscas executadas>
Anomalia operacional (opcional, max 1): ANOTA|<frase curta>

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

function Invoke-ClaudeBatchSentinela([string]$promptPath, [string]$Model, [int]$TimeoutMin) {
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
    try {
        # Fase B D1 (2026-09-04): provider openrouter despacha para o adapter HTTP proprio
        # (lib\vixradar-openrouter.ps1), com as server tools web_search/web_fetch. Sem claude,
        # sem auth Anthropic, sem escalacao paga. Retry bounded interno ao adapter (tem timeout
        # de parede proprio, VIXRADAR_OPENROUTER_TIMEOUT_MIN); falha deixa os emissores intactos
        # no backlog, mesmo efeito do timeout do claude.
        if ($script:VixUsaOpenRouter) {
            $__orResp = Invoke-VixOpenRouterLote -PromptPath $promptPath
            $raw = @($__orResp.Linhas)
            if ($__orResp.ExitCode -ne 0) { Write-Log ('AVISO: lote OpenRouter falhou (' + $__orResp.Msg + ') - emissores preservados no backlog') }
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
            $proc = Start-Process -FilePath $exe -ArgumentList $argumentos `
                -RedirectStandardInput $promptPath `
                -RedirectStandardOutput $stdoutFile `
                -RedirectStandardError $stderrFile `
                -NoNewWindow -PassThru
            if (-not $proc.WaitForExit($TimeoutMin * 60 * 1000)) {
                $timedOut = $true
                Write-Log ('TIMEOUT: lote passou de ' + $TimeoutMin + ' min sem terminar. Matando a arvore do PID ' + $proc.Id + '.')
                Stop-ArvoreProcesso $proc.Id
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
    return @{ Output = $textOut; Tokens = $tokens; AuthFailure = (Test-VixClaudeAuthFailure $textOut); TimedOut = $timedOut }
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
$submitOk     = 0
$submitFail   = 0
$deferidos    = 0
$buscasTotal  = 0
$semResultado = 0

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
        $jobs += @{ Label = ($fila.N + '-' + $idx); Model = $fila.M; Skill = $fila.S; Chunk = $chunk }
    }
}

$inicioExec = Get-Date
foreach ($job in $jobs) {
    if ($tokensAcum -ge $TokenHardCap) {
        $deferidos += $job.Chunk.Count
        Write-Log ('CAP: teto de ' + $TokenHardCap + ' tokens atingido. ' + $job.Chunk.Count + ' emissores deferidos no lote ' + $job.Label + ' - voltam na proxima execucao pelo mesmo gatilho.')
        continue
    }
    $decorridoMin = ((Get-Date) - $inicioExec).TotalMinutes
    if ($decorridoMin -ge $TempoMaxMin) {
        $deferidos += $job.Chunk.Count
        Write-Log ('CAP_TEMPO: ' + [math]::Round($decorridoMin, 1) + ' min decorridos (teto ' + $TempoMaxMin + '). ' + $job.Chunk.Count + ' emissores deferidos no lote ' + $job.Label + ' - voltam na proxima execucao pelo mesmo gatilho.')
        continue
    }
    $promptPath = Join-Path $LogDir ('sentinela_' + $job.Label + '_' + $DateTag + '_' + $PID + '.txt')
    New-BatchPromptSentinela $job.Chunk $job.Label $job.Model $job.Skill $janelaInicio $janelaFim | Set-Content -Path $promptPath -Encoding UTF8
    Write-Log ('LOTE ' + $job.Label + ': ' + $job.Chunk.Count + ' emissores, modelo ' + $job.Model)
    # O teto por lote e o que sobra do teto da execucao, nunca mais que isso, com um
    # piso de 4 min para nao nascer expirado quando a janela ja esta quase no fim.
    $restanteMin = [int]([math]::Max(4, $TempoMaxMin - ((Get-Date) - $inicioExec).TotalMinutes))
    $res = Invoke-ClaudeBatchSentinela $promptPath $job.Model $restanteMin
    if ($res.Tokens -ge 0) { $tokensAcum += $res.Tokens }
    if ($res.TimedOut) {
        # Emissores do lote ficam intactos: nada de submit, nada marcado em cvm_vistos.
        # Contam como sem_resultado, o que liga o backlog e devolve todos na proxima
        # janela pelo mesmo gatilho. Nenhum lote fica pendurado e nada se perde.
        $semResultado += $job.Chunk.Count
        Write-Log ('CAP_TEMPO: lote ' + $job.Label + ' morto por timeout, ' + $job.Chunk.Count + ' emissores preservados no backlog.')
        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
        continue
    }
    if ($res.AuthFailure) {
        Write-Log 'ERRO: falha de autenticacao do claude no lote. Interrompendo, backlog preservado.'
        $null = Send-VixRoutineAlert -Rotina 'sentinela' -Motivo 'claude CLI nao autenticado ou limite atingido - emissores com gatilho nao foram analisados' -RoutineKey $routineKey
        Write-State $workerLm $zipLmParaEstado $true ($streak + 1)
        Write-Log ('FIM: sentinela abortada. tokens=' + $tokensAcum + ' analisados=' + $submitOk + ' motivo=auth_falhou')
        exit 7
    }
    $parsed = Get-ParsedResultadosSentinela $res.Output
    if ($parsed.Buscas -ge 0) { $buscasTotal += $parsed.Buscas }
    if ($parsed.Map.Count -eq 0) {
        Write-Log ('ERRO: lote ' + $job.Label + ' sem RESULTADO| - falha silenciosa, 0 de ' + $job.Chunk.Count + ' emissores analisados.')
        $semResultado += $job.Chunk.Count
        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
        continue
    }
    foreach ($emp in $job.Chunk) {
        $obj = $parsed.Map[(Get-NomeNormalizado ('' + $emp.empresa))]
        if (-not $obj) {
            Write-Log ('AVISO: sem resultado para ' + $emp.empresa + ' no lote ' + $job.Label + ' - gatilho preservado.')
            $semResultado++
            continue
        }
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
            _matinal = $false; provedor = ('claude-sentinela-' + $job.Model)
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
        } else {
            $submitFail++
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

Write-Log ('FIM: sentinela concluida. tokens=' + $tokensAcum + ' analisados=' + $submitOk + ' submit_fail=' + $submitFail + ' deferidos=' + $deferidos + ' sem_resultado=' + $semResultado + ' excedente_worker=' + $excedente + ' buscas=' + $buscasTotal + ' backlog=' + $sobrou)
exit 0

} finally {
    if ($__mutex) { $__mutex.ReleaseMutex(); $__mutex.Dispose() }
}
