# run_vixradar_varredura.ps1 - motor unico das varreduras do VIX Radar (Task Scheduler + claude -p).
#
# MOTOR1 (2026-09-02, decisao do operador). Substitui o corpo de run_vixradar_noturno_claude.ps1
# e run_vixradar_matinal_claude.ps1, que viraram wrappers de uma linha. Um so motor, dois perfis:
#   -Rotina matinal : dona do TOPO. Plano modo=matinal top_n=20, tudo que nao for SKIP vai para a
#                     fila Sonnet FULL (lotes de 4, prompt matinal-batch-sonnet.md, 3 buscas).
#   -Rotina noturno : dona da CAUDA. Plano modo=noturno, tudo que nao for SKIP vai para a fila
#                     Haiku LIGHT (lotes de 15, prompt noturno-batch-haiku.md). Sem fila Sonnet,
#                     sem reserva de aprofundada, cap inteiro na cauda. O topo ja veio SKIP do
#                     Worker por credito de analise do dia (CREDITODIA1, v4.9.234).
# O que mudou em relacao aos dois scripts antigos, tudo medido na auditoria de 01/09 (nota 99):
#   - ledger OK| de 6 campos com <status> SKIP|ANALISADO|DEFERIDO e linha FIM: com analisados=,
#     skip=, deferidos=, submits_aceitos= (SUBMITOK-ENGANOSO1; guarda check-ledger-noturno.ps1);
#   - receber_analise com origem, _tier aplicado e cvm_ids_analisados do plano (CVMNOVOSDEAD1);
#   - usage do claude -p gravado nas 4 parcelas (input, output, cache_creation, cache_read) por
#     lote, regua unica em lib\vixradar-custo.ps1 (REGUA-UNICA1);
#   - cap dinamico por dia: TETO_DIA menos gasto ja feito menos reserva das outras rotinas
#     (custo-config.json), circuito aberto quando a margem some;
#   - lock de arquivo escrito ANTES da primeira chamada ao Worker, tocado a cada lote e
#     removido no fim; abandono em 30 min sem toque (a sentinela le a mesma regra);
#   - espera de ate 25 min pelo mutex da sentinela antes de montar o plano;
#   - ALERTA_AUTH quando a lib de auth escala para a chave paga (nunca silencioso);
#   - -DryRun (analisa, nunca submete, ledger DRYRUN|), -MaxEmissores N (amostra),
#     -SimularTokenVencido (so com -DryRun, prova a escalada).
# Tudo que os scripts antigos tinham de defesa foi trazido: mutex, idempotencia por ledger,
# retry parcial por emissor, silent_fail, encoding UTF-8 forcado, Write-Log com backoff,
# Start-Transcript, mcp-empty.json em arquivo, stderr por PID, auth centralizada na lib.
# PowerShell 5.1, ASCII puro, $ErrorActionPreference Continue, exit obrigatorio (Task Scheduler).

param(
    [Parameter(Mandatory = $true)][ValidateSet('noturno', 'matinal')][string]$Rotina,
    [switch]$Force,
    [switch]$DryRun,
    [int]$MaxEmissores = 0,
    [switch]$SimularTokenVencido
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot    = 'E:\Diretorio\Claude\Monitoramento de Credito'
$WorkerUrl      = 'https://api.vixradar.com'
$ScriptsDir     = Join-Path $ProjectRoot 'scripts'
$ScheduledTasks = 'C:\Users\User\.claude\scheduled-tasks'
$CleanupScript  = Join-Path $ProjectRoot 'scripts\cleanup-rotina-artifacts.ps1'
$LogDir         = Join-Path $ProjectRoot 'logs\routines'
$DateTag        = Get-Date -Format 'yyyyMMdd'
$McpConfigFile  = Join-Path $LogDir 'mcp-empty.json'
$ModelHaiku     = 'claude-haiku-4-5-20251001'
$ModelSonnet    = 'claude-sonnet-4-6'
$PauseSec       = 2
$EwsContextoCritico = 38
$LockAbandonoMin = 30
$EsperaSentinelaMaxMin = 25

if ($Rotina -eq 'noturno') {
    $Perfil = @{
        id = 'vixradar-noturno'; modo = 'noturno'; top_n = 0
        skill = (Join-Path $ScriptsDir 'noturno-batch-haiku.md'); model = $ModelHaiku; chunk = 15; ultra = $true
        tier = 'LIGHT'; provedor = 'claude-haiku-routine'; matinal = $false
        capProprio = 700000; meta = 500000; bootTok = 15000; unitTok = 3800
        mutex = 'Global\vixradar-noturno-v2'; prefix = 'noturno'; reservaOutrasKey = 'RESERVA_VERIFICACAO'
    }
} else {
    $Perfil = @{
        id = 'vixradar-matinal'; modo = 'matinal'; top_n = 20
        skill = (Join-Path $ScriptsDir 'matinal-batch-sonnet.md'); model = $ModelSonnet; chunk = 4; ultra = $false
        tier = 'FULL'; provedor = 'claude-sonnet-routine'; matinal = $true
        capProprio = 400000; meta = 300000; bootTok = 15000; unitTok = 11500
        mutex = 'Global\vixradar-matinal-v2'; prefix = 'matinal'; reservaOutrasKey = 'RESERVA_NOTURNO'
    }
}
$LogFile     = Join-Path $LogDir ('vixradar-' + $Rotina + '_' + $DateTag + '.log')
$MetricsFile = Join-Path $LogDir ($Perfil.prefix + '_metrics_' + $DateTag + $(if ($DryRun) { '_dryrun' } else { '' }) + '.json')
$LockFile    = Join-Path $LogDir ('vixradar-' + $Rotina + '_' + $DateTag + '.lock')
$TokenTarget = $Perfil.meta
$TokenHardCap = $Perfil.capProprio

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# PIPE1 (2026-07-28): Write-Host sob -WindowStyle Hidden quebrava o pipe do console apos
# ~28 min (ERROR_PIPE_NOT_CONNECTED). O log em arquivo ja registrou a linha.
function Write-Safe([string]$msg) { try { Write-Host $msg } catch { } }

$TranscriptFile = Join-Path $LogDir ($Perfil.prefix + '_transcript_' + $DateTag + '_' + $PID + '.txt')
try { Start-Transcript -Path $TranscriptFile -Append -Force -ErrorAction Stop } catch {
    Write-Safe "AVISO: Start-Transcript falhou ($($_.Exception.Message)) - continuando sem transcript"
}

# --mcp-config em ARQUIVO: inline perdia as aspas em execucao agendada (achado 2026-07-05).
Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding UTF8

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Write-Safe $line
    # LOGLOCK1-REC: backoff exponencial ate 8 tentativas; fallback com PID no nome.
    for ($i = 1; $i -le 8; $i++) {
        try {
            Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
            return
        } catch {
            if ($i -eq 8) {
                $fallbackFile = ([regex]::Replace($LogFile, '\.log$', "_fallback_$pid.log"))
                Write-Safe "FALHA Write-Log ($i tentativas), fallback: $fallbackFile - $($_.Exception.Message)"
                try { Add-Content -Path $fallbackFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { Write-Safe "FALHA Write-Log IRRECUPERAVEL: $($_.Exception.Message)" }
            }
            else { Start-Sleep -Milliseconds ([Math]::Min(200 * [Math]::Pow(2, $i - 1), 2000)) }
        }
    }
}

$script:AuthFailRegex = '(?i)not logged in|please run /login|disabled claude subscription|use an anthropic api key instead|weekly limit|hit your.*limit|credit balance is too low|insufficient.*credit|authentication_error|invalid.*(api key|token)|oauth.*(expired|invalid)|token.*(expired|invalid)|(http|status)\s*401'

function Test-ClaudeAuthFailure([string[]]$outputLines) {
    # Achado 2026-07-08: o claude.exe pode perder a sessao e imprimir a mensagem com exit 0.
    # MOTOR1: regex ampliada para token longevo recusado (401/authentication_error/token expirado).
    $texto = ($outputLines -join "`n")
    return $texto -match $script:AuthFailRegex
}

# DRYRUN-CRASH1 (2026-09-02): o log dizia "claude CLI nao autenticado" para o que era limite
# de uso da assinatura (sessao estourada as 02:45, reset 06:10). Mensagem honesta: cita o
# trecho que casou. Categoria decide o texto do alerta, nao muda o abort.
function Get-ClaudeAuthMotivo([string[]]$outputLines) {
    $texto = ($outputLines -join "`n")
    if ($texto -match $script:AuthFailRegex) {
        $m = $Matches[0]
        if ($m -match '(?i)limit') { return ('limite de uso da assinatura atingido ("' + $m + '")') }
        if ($m -match '(?i)credit') { return ('credito da chave esgotado ("' + $m + '")') }
        return ('credencial recusada ("' + $m + '")')
    }
    return 'motivo nao identificado na saida'
}

# DRYRUN-CRASH1: $jobs.IndexOf($jr) com [ordered] estourava no binder do PowerShell 5.1
# ("Os tipos de argumento nao correspondem", PSToObjectArrayBinder). Indice por referencia.
function Get-JobIndex($jobsList, $job) {
    for ($k = 0; $k -lt $jobsList.Count; $k++) {
        if ([object]::ReferenceEquals($jobsList[$k], $job)) { return $k }
    }
    return -1
}

function Invoke-Cleanup([switch]$Aggressive) {
    if (-not (Test-Path $CleanupScript)) { return }
    try {
        if ($Aggressive) { $out = & $CleanupScript -KeepDays 7 -Aggressive } else { $out = & $CleanupScript -KeepDays 7 }
        Write-Log ('Cleanup: ' + $out)
    } catch { Write-Log ('Cleanup aviso: ' + $_.Exception.Message) }
}

function Get-RoutineKey {
    # ROTA1: hidratar do registro User SEMPRE (processo longevo herda env velho apos rotacao).
    $doRegistro = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    if ($doRegistro) { return $doRegistro }
    if ($env:ROUTINE_API_KEY) { return $env:ROUTINE_API_KEY }
    throw 'ROUTINE_API_KEY nao definida. Configure: $env:ROUTINE_API_KEY = "<chave>"'
}

. (Join-Path $PSScriptRoot 'lib\vixradar-claude-auth.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1')
Assert-VixLibFunctions @('Set-VixClaudeAuthEnv', 'Test-VixClaudeAmbienteLimpo', 'Test-VixWebSearchProbe', 'Send-VixRoutineAlert', 'Invoke-VixClaudeAuthEscalate', 'Initialize-VixClaudeAuth', 'Get-VixClaudeAuthModo')
foreach ($fn in @('Get-VixCustoConfig', 'Get-VixCustoDia', 'Get-VixCapEfetivo', 'Get-VixUsageParcelas')) {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { Write-Safe ('ERRO: funcao ' + $fn + ' ausente em lib\vixradar-custo.ps1'); exit 1 }
}

function Get-CvmResumo($docs) {
    if (-not $docs) { return '0 docs' }
    $arr = @($docs)
    if ($arr.Count -eq 0) { return '0 docs' }
    return ($arr.Count.ToString() + ' docs')
}

function Get-SlimEmissor($emp, [switch]$Ultra) {
    $docs = @($emp.cvm_documentos | Select-Object -First $(if ($Ultra) { 2 } else { 3 }) | ForEach-Object {
        $assunto = '' + $_.assunto
        if ($assunto.Length -gt 100) { $assunto = $assunto.Substring(0, 100) }
        $d = [ordered]@{ categoria = $_.categoria; assunto = $assunto; data = $_.data; link = $_.link }
        if ($_.empresa_cvm -and ($_.empresa_cvm -notmatch [regex]::Escape(($emp.empresa -split ' ')[0]))) { $d['empresa_cvm'] = $_.empresa_cvm }
        [pscustomobject]$d
    })
    $o = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; tier = $Perfil.tier
        ews_score = $emp.ews_score; cvm_novos = $emp.cvm_novos; cvm_documentos = $docs
    }
    $ctx = '' + $emp.contexto_historico
    if ($ctx) {
        $isCritico = ($emp.ews_score -ge $EwsContextoCritico) -or ($ctx -match 'REX|RJ|recupera|default|CRITICO')
        $max = if ($isCritico) { 400 } elseif ($Ultra) { 200 } else { 120 }
        if ($ctx.Length -gt $max) { $ctx = $ctx.Substring(0, $max) }
        $o['contexto_historico'] = $ctx
    }
    return $o
}

function Invoke-WorkerJsonUtf8 {
    # P0 nota 43: Worker responde JSON sem charset; PS 5.1 decodificaria como ISO-8859-1.
    param([string]$Uri, $BodyObj, [int]$TimeoutSec = 120, [int]$Depth = 16)
    $params = @{ Uri = $Uri; Method = 'Post'; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    $params.ContentType = 'application/json; charset=utf-8'
    $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($BodyObj | ConvertTo-Json -Depth $Depth -Compress))
    $resp = Invoke-WebRequest @params
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

function Submit-Analise($key, $empresa, $setor, $resultado, [string]$provedor, [string]$tier, $cvmIds) {
    if ($DryRun) { return [pscustomobject]@{ ok = $true; n_eventos = 0; dryrun = $true } }
    $body = [ordered]@{
        action = 'receber_analise'; routine_key = $key; empresa = $empresa; setor = $setor
        _matinal = [bool]$Perfil.matinal; origem = $Rotina; _tier = $tier; provedor = $provedor
        cvm_ids_analisados = @($cvmIds | Where-Object { $_ }); resultado = $resultado
    }
    return Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj $body -Depth 16 -TimeoutSec 120
}

function Submit-SkipEmissor($key, $emp) {
    $motivos = if ($emp.motivos) { ($emp.motivos -join ', ') } else { 'sem_delta' }
    $cvmResumo = Get-CvmResumo $emp.cvm_documentos
    $resultado = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; sem_eventos = $true
        cobertura_nota = "Tier SKIP. CVM: $cvmResumo. $($emp.cvm_novos) novos. Motivos: $motivos."
        fontes_consultadas = @([ordered]@{ rodada = '0'; query = 'Worker plano'; resultado = $cvmResumo })
        eventos = @(); _tier = 'SKIP'; _rotina_v2 = $true
    }
    $resp = Submit-Analise $key $emp.empresa $emp.setor $resultado 'claude-skip-routine' 'SKIP' @()
    if ($resp.ok -ne $true) { Start-Sleep -Seconds $PauseSec; $resp = Submit-Analise $key $emp.empresa $emp.setor $resultado 'claude-skip-routine' 'SKIP' @() }
    return $resp
}

function Submit-CapDeferred($key, $emp) {
    $resultado = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; sem_eventos = $true
        cobertura_nota = "Tier $($Perfil.tier). Cap efetivo $TokenHardCap tokens - ledger minimo. EWS=$($emp.ews_score). Priorizar amanha."
        fontes_consultadas = @([ordered]@{ rodada = '0'; query = 'token_cap'; resultado = 'deferred' })
        eventos = @(); _tier = $Perfil.tier; _rotina_v2 = $true; _token_cap_deferred = $true
    }
    return Submit-Analise $key $emp.empresa $emp.setor $resultado 'claude-cap-deferred' $Perfil.tier @()
}

function Split-IntoChunks($items, [int]$chunkSize) {
    $list = @($items)
    if ($list.Count -eq 0) { return @() }
    $chunks = @()
    for ($i = 0; $i -lt $list.Count; $i += $chunkSize) {
        $end = [Math]::Min($i + $chunkSize - 1, $list.Count - 1)
        $chunks += ,@($list[$i..$end])
    }
    return ,$chunks
}

function Update-VixLock {
    try { (Get-Item $LockFile -ErrorAction Stop).LastWriteTime = Get-Date } catch { }
}

function Invoke-ClaudeBatch([string]$promptPath, [string]$Model) {
    # Flags de economia (medidas 2026-07-03): boot 33.9k -> ~13.6k tokens/invocacao.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $stderrFile = Join-Path $LogDir ($Perfil.prefix + '_stderr_' + $DateTag + '_' + $PID + '.txt')
    $raw = $null; $exitCode = 1; $escalou = $false
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        $retryDelays = @(0, 30, 60)
        $retryLog = @()
        for ($attempt = 0; $attempt -lt $retryDelays.Count; $attempt++) {
            if ($attempt -gt 0) {
                $delay = $retryDelays[$attempt]
                Write-Log ('RETRY: tentativa ' + ($attempt + 1) + '/' + $retryDelays.Count + ' aguardando ' + $delay + 's (lote morreu na anterior)')
                Start-Sleep -Seconds $delay
            }
            Update-VixLock
            Set-VixClaudeAuthEnv
            $raw = Get-Content $promptPath -Raw -Encoding UTF8 | claude -p `
                --model $Model `
                --permission-mode bypassPermissions `
                --output-format json `
                --tools 'WebSearch,WebFetch' `
                --strict-mcp-config --mcp-config $McpConfigFile `
                --setting-sources project `
                --disable-slash-commands `
                --no-session-persistence `
                --exclude-dynamic-system-prompt-sections 2>>$stderrFile
            $exitCode = $LASTEXITCODE
            $retryLog += ('t' + ($attempt + 1) + ':exit=' + $exitCode + ':model=' + $Model)
            if ($exitCode -eq 0) { break }
            # Credencial que venceu no meio da rotina: escala para a chave paga e repete.
            $saidaFalha = ('' + $raw)
            if (Test-Path $stderrFile) { $saidaFalha += (' ' + (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue)) }
            if (Invoke-VixClaudeAuthEscalate $saidaFalha) { $retryLog += 'auth:escalado-para-api'; $escalou = $true }
        }
        if ($retryLog.Count -gt 1) { Write-Log ('RETRY log: ' + ($retryLog -join ' ')) }
        # DRYRUN-CRASH1: exit != 0 sem stderr deixava a causa sem evidencia (02/09 02:45).
        # Guarda a cabeca do stdout no log para a proxima falha ter prova.
        if ($exitCode -ne 0) {
            $cabeca = ('' + (@($raw) -join ' ')).Trim()
            if ($cabeca.Length -gt 300) { $cabeca = $cabeca.Substring(0, 300) }
            if ($cabeca) { Write-Log ('CLAUDE_STDOUT_FALHA: ' + $cabeca) } else { Write-Log 'CLAUDE_STDOUT_FALHA: (stdout vazio, stderr em ' + $stderrFile + ')' }
        }
    } catch {
        Write-Log ('AVISO: excecao ao invocar claude -p (' + $_.Exception.Message + ') - lote marcado como falho')
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    $textOut = @($raw)
    $parcelas = @{ input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0; trabalho = [int64]0 }
    $tokens = -1
    try {
        $jsonLine = @($raw) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
        if ($jsonLine) {
            $json = $jsonLine | ConvertFrom-Json
            if ($null -ne $json.result) { $textOut = @(('' + $json.result) -split "`n") }
            if ($json.usage) { $parcelas = Get-VixUsageParcelas $json; $tokens = [int64]$parcelas.trabalho }
        }
    } catch {
        Write-Log ('AVISO: parse do envelope JSON falhou (' + $_.Exception.Message + ') - tokens DESCONHECIDO')
    }
    $authFail = Test-ClaudeAuthFailure $textOut
    return @{ Output = $textOut; ExitCode = $exitCode; Tokens = $tokens; Parcelas = $parcelas; AuthFailure = $authFail; Escalou = $escalou }
}

function Get-NomeNormalizado([string]$s) {
    $norm = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return $sb.ToString().Trim()
}

function Get-ParsedResultados($outputLines) {
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

function Get-ResultadoEmissor($parsedMap, [string]$empresaPlano) { return $parsedMap[(Get-NomeNormalizado $empresaPlano)] }

function New-BatchPrompt($batch, $batchLabel, $modelName, $skillPath, $janelaInicio, $janelaFim, [switch]$Ultra) {
    $slim = @($batch | ForEach-Object { Get-SlimEmissor $_ -Ultra:$Ultra })
    $json = $slim | ConvertTo-Json -Depth 8 -Compress
    $skill = (Get-Content $skillPath -Raw -Encoding UTF8).Trim()
    return @"
Execute lote $batchLabel ($($batch.Count) emissores). Modelo: $modelName. Sequencial. Sem subagentes. Sem arquivos locais. Sem chamadas HTTP de submit - o orquestrador grava os resultados.
JANELA: $janelaInicio a $janelaFim
PROIBIDO: markdown, tabelas, backticks, headers, narrativa, texto fora do protocolo abaixo.
SAIDA - exatamente estas linhas e nada mais:
1 linha por emissor: RESULTADO|<empresa exatamente como no JSON, com acentuacao identica>|<objeto resultado em JSON compacto de linha unica>
Formato do objeto resultado: {"classificacao_geral":"CRITICO|RELEVANTE|ECO|NENHUM","sem_eventos":true,"cobertura_nota":"...","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"...","resultado":"..."}]}
Cada evento em CRITICO/RELEVANTE EXIGE: memo_acontecimento (2-3 frases, o que aconteceu - alimenta o card do usuario E o contexto_historico da rotina de amanha), memo_importancia_credito (por que importa para o credito), memo_monitorar (o que observar a seguir). Sem esses 3 campos preenchidos o evento fica incompleto - nao omitir.
Ultima linha: LOTE_RESUMO|buscas=<total de buscas executadas>
Anomalia operacional (opcional, max 1): ANOTA|<frase curta>
Exemplo literal de saida completa para lote de 2 emissores:
RESULTADO|Empresa A|{"classificacao_geral":"ECO","sem_eventos":true,"cobertura_nota":"R2 sem sinal de credito na janela.","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"Empresa A divida rating","resultado":"sem eventos"}]}
RESULTADO|Empresa B|{"classificacao_geral":"RELEVANTE","sem_eventos":false,"cobertura_nota":"","eventos":[{"classificacao":"RELEVANTE","titulo":"Emissao de debentures","evento":"...","impacto_credito":"...","memo_acontecimento":"Empresa B emitiu R$500mi em debentures em 01/07 para rolagem de divida de curto prazo.","memo_importancia_credito":"Reduz risco de refinanciamento no curto prazo, sem piora de alavancagem.","memo_monitorar":"Prazo e taxa da nova emissao vs divida anterior.","fonte_primaria":"https://exemplo.com/materia-especifica","fonte_tipo":"IMPRENSA","data_evento":"2026-07-01","data_aproximada":false,"tags":["emissao"]}],"fontes_consultadas":[{"rodada":"R2","query":"Empresa B debentures","resultado":"emissao confirmada"},{"rodada":"R6","query":"Empresa B rating","resultado":"sem acao de rating"}]}
LOTE_RESUMO|buscas=3

JSON:
$json

$skill
"@
}

function Remove-BatchPrompts([string]$tag) {
    Get-ChildItem $LogDir -Filter ($Perfil.prefix + '_*_' + $tag + '.txt') -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike ($Perfil.prefix + '_stderr_*') -and $_.Name -notlike ($Perfil.prefix + '_transcript_*') } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $LogDir ($Perfil.prefix + '_plano_' + $tag + '.json')) -Force -ErrorAction SilentlyContinue
}

function Write-Ledger([string]$emp, [string]$tier, [string]$classif, [int]$nEv, [bool]$subOk, [string]$status) {
    $pfx = if ($DryRun) { 'DRYRUN|' } else { 'OK|' }
    Write-Log ($pfx + $emp + '|' + $tier + '|' + $classif + '|' + $nEv + '|' + $subOk.ToString().ToLower() + '|' + $status)
}

if (-not (Test-Path $Perfil.skill)) { Write-Log ('ERRO: skill ausente ' + $Perfil.skill); exit 1 }

# Feriado B3: nenhuma fonte publica, nada a varrer. Fim de semana fica a cargo do gatilho
# (noturno seg-sex no Task Scheduler; matinal diaria de proposito).
$feriados = @(
    '2026-01-01', '2026-02-16', '2026-02-17', '2026-04-03', '2026-04-21', '2026-05-01',
    '2026-06-04', '2026-09-07', '2026-10-12', '2026-11-02', '2026-11-15', '2026-11-20', '2026-12-25'
)
if (($feriados -contains (Get-Date).ToString('yyyy-MM-dd')) -and -not $DryRun) {
    Write-Log ('SKIP: feriado B3. FIM: ' + $Rotina + ' pulado por feriado. Total do dia 0/0. analisados=0 skip=0 deferidos=0 submits_aceitos=0')
    exit 0
}

# Mutex global: nunca duas instancias da mesma rotina (incidente 2026-07-06).
$__mutex = New-Object System.Threading.Mutex($false, $Perfil.mutex)
if (-not $__mutex.WaitOne(0)) {
    Write-Log ('ABORT: outra instancia da ' + $Rotina + ' ja esta em execucao (mutex ocupado) - saindo limpo em 0 tokens')
    exit 0
}

# Espera pela sentinela (ela roda ate 22 min a partir de :25/:55 e a noturna comeca 18h05).
$__sentMutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-sentinela-v1')
$__esperou = 0
while (-not $__sentMutex.WaitOne(0)) {
    if ($__esperou -eq 0) { Write-Log ('AGUARDANDO sentinela: mutex Global\vixradar-sentinela-v1 ocupado, esperando ate ' + $EsperaSentinelaMaxMin + ' min') }
    if ($__esperou -ge ($EsperaSentinelaMaxMin * 2)) { Write-Log 'AVISO: sentinela ainda ocupada apos o limite de espera - seguindo mesmo assim (o lock de arquivo abaixo segura a proxima sentinela)'; break }
    Start-Sleep -Seconds 30
    $__esperou++
}
if ($__sentMutex.WaitOne(0)) { $__sentMutex.ReleaseMutex() }
if ($__esperou -gt 0) { Write-Log ('sentinela livre apos ' + ($__esperou * 30) + 's') }

# Lock de arquivo: outra instancia (sessao Claude Desktop, Cowork, manual) escreve o mesmo
# arquivo. Vivo = tocado nos ultimos $LockAbandonoMin minutos; alem disso e abandono.
if (Test-Path $LockFile) {
    $__lockAgeMin = ((Get-Date) - (Get-Item $LockFile).LastWriteTime).TotalMinutes
    if ($__lockAgeMin -lt $LockAbandonoMin) {
        Write-Log ('ABORT: lock ' + (Split-Path $LockFile -Leaf) + ' tocado ha ' + [math]::Round($__lockAgeMin, 1) + ' min (outra execucao viva) - saindo limpo em 0 tokens')
        $__mutex.ReleaseMutex()
        exit 0
    } else {
        Write-Log ('LOCK_ABANDONADO: ' + (Split-Path $LockFile -Leaf) + ' sem toque ha ' + [math]::Round($__lockAgeMin, 1) + ' min - assumindo')
    }
}
try {
    ("source=run_vixradar_varredura.ps1`nrotina=$Rotina`npid=$PID`ninicio=" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`ndryrun=$DryRun") | Set-Content -Path $LockFile -Encoding UTF8 -ErrorAction Stop
    Write-Log ('LOCK_OK: ' + (Split-Path $LockFile -Leaf) + ' criado, toque a cada lote, abandono em ' + $LockAbandonoMin + ' min')
} catch {
    Write-Log ('AVISO: nao consegui escrever o lock ' + $LockFile + ' - ' + $_.Exception.Message)
}

$modoTxt = if ($DryRun) { 'DRYRUN' } else { 'real' }
# DRYRUN-CRASH1: em dry-run a linha vira DRYRUN_ALERTA_AUTH para o monitor (9004) nao tratar teste como incidente.
$AlertaAuthTag = if ($DryRun) { 'DRYRUN_ALERTA_AUTH: ' } else { 'ALERTA_AUTH: ' }
Write-Log ('INICIO: ' + $Rotina + ' (motor Task Scheduler, run_vixradar_varredura.ps1, modo=' + $modoTxt + ') tier=' + $Perfil.tier + ' modelo=' + $Perfil.model + ' lote=' + $Perfil.chunk + ' cap_proprio=' + $Perfil.capProprio)
$inicioIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

if ($SimularTokenVencido) {
    if (-not $DryRun) {
        Write-Log 'ERRO: -SimularTokenVencido so e aceito com -DryRun (nunca contra submissao real).'
        exit 1
    }
    # So no processo, nunca no registro: a lib le o env do processo antes do registro User.
    # Placebo montado em dois pedacos: nao e credencial, e o gate de segredo do pre-commit
    # (RX_ANTHROPIC) nao pode ver o formato inteiro no fonte.
    $env:VIXRADAR_ANTHROPIC_AUTH_TOKEN = 'sk-ant-' + 'oat01-SIMULADO-VENCIDO-' + $PID
    Write-Log 'SIMULACAO: VIXRADAR_ANTHROPIC_AUTH_TOKEN invalido injetado no processo (prova de escalada, -SimularTokenVencido)'
}

Initialize-VixClaudeAuth -McpConfigFile $McpConfigFile | Out-Null
$authModoInicial = Get-VixClaudeAuthModo
Write-Log ('AUTH_MODO: ' + $authModoInicial)
if ($authModoInicial -eq 'nenhum') {
    Write-Log 'ERRO FATAL: nenhuma credencial Claude disponivel (assinatura expirada, token longevo ausente, chave paga invalida ou ausente). Abortando antes do primeiro lote.'
    Write-Log 'ERRO FATAL: rode `claude setup-token` para token longevo ou defina VIXRADAR_ANTHROPIC_API_KEY com chave sk-ant-valida.'
    Write-Log ('ALERTA_AUTH: sem credencial nenhuma na ' + $Rotina + ' (modo=nenhum)')
    exit 5
}
if ($authModoInicial -eq 'api') {
    Write-Log ($AlertaAuthTag +$Rotina + ' comecou direto na chave paga (assinatura indisponivel no boot). Cada lote custa dolar.')
}
$ambientViolacao = Test-VixClaudeAmbienteLimpo
if ($ambientViolacao) {
    Write-Log "AVISO: ambiente contaminado detectado - $ambientViolacao"
    $env:ANTHROPIC_BASE_URL = 'https://api.anthropic.com'
    Remove-Item Env:\ANTHROPIC_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_DEFAULT_OPUS_MODEL -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', '', 'Process')
    [Environment]::SetEnvironmentVariable('ANTHROPIC_MODEL', '', 'Process')
    [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', $null, 'User')
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $null, 'User')
    Write-Log 'RECUPERACAO: env vars Anthropic injetadas para neutralizar contaminacao do settings.json.'
}
if (-not (Test-VixWebSearchProbe $McpConfigFile)) {
    Write-Log 'ERRO FATAL: probe WebSearch falhou - ferramenta de busca indisponivel. Abortado antes do primeiro submit.'
    exit 7
}
Invoke-Cleanup
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Write-Log 'ERRO: claude.exe ausente'; exit 2 }

try {
    $health = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 30
    if (-not $health.bindings.kv -or -not $health.bindings.telemetria) {
        Write-Log ('ERRO: health - kv=' + $health.bindings.kv + ' telemetria=' + $health.bindings.telemetria)
        exit 3
    }
    Write-Log ('Health ' + $health.versao + ' ok=' + $health.ok + ' verificador_ok=' + $health.verificador_ok + ' (nao bloqueante para esta rotina)')
    $versaoWorker = $health.versao
} catch { Write-Log ('ERRO: health ' + $_.Exception.Message); exit 3 }

try { $routineKey = Get-RoutineKey } catch { Write-Log $_.Exception.Message; exit 4 }

# Cap dinamico por dia (REGUA-UNICA1): teto do dia menos o que as outras rotinas ja gastaram
# hoje, menos a reserva de quem ainda vai rodar.
$custoCfg = Get-VixCustoConfig $LogDir
if (-not $custoCfg.ContainsKey('RESERVA_NOTURNO')) { $custoCfg['RESERVA_NOTURNO'] = 700000 }
$custoDia = Get-VixCustoDia $LogDir $DateTag $custoCfg
$reservaOutras = [int64]$custoCfg.RESERVA_VERIFICACAO
if ($Perfil.reservaOutrasKey -eq 'RESERVA_NOTURNO') { $reservaOutras += [int64]$custoCfg.RESERVA_NOTURNO }
$TokenHardCap = [int64](Get-VixCapEfetivo ([int64]$Perfil.capProprio) $custoDia $custoCfg $reservaOutras)
if ($TokenTarget -gt $TokenHardCap) { $TokenTarget = $TokenHardCap }
Write-Log ('CAP_EFETIVO=' + $TokenHardCap + ' (cap_proprio=' + $Perfil.capProprio + ' gasto_dia=' + $custoDia.total_trabalho + ' teto=' + $custoDia.teto + ' reserva_outras=' + $reservaOutras + ')')
Write-Log $custoDia.linha
if ($custoDia.circuito_aberto) {
    Write-Log ('CIRCUITO_ABERTO: margem do dia ' + $custoDia.margem + ' abaixo de ' + $custoDia.margem_minima + '. Nenhum lote sera disparado; tudo que nao for SKIP sai como DEFERIDO.')
    $TokenHardCap = 0
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$stats = @{
    skip_ok = 0; skip_fail = 0; batch_ok = 0; batch_fail = 0; silent_fail = 0
    tokens_total = [int64]0; tokens_over_target = $false; tokens_hard_hit = $false; deferred = 0; deferred_fail = 0
    batches_run = 0; analisados = 0; submit_ok = 0; submit_fail = 0; buscas_total = 0
    input = [int64]0; output = [int64]0; cache_creation = [int64]0; cache_read = [int64]0
    auth_escalou = 'nenhum'
    criticos = New-Object System.Collections.Generic.List[string]
}
$lotesDetalhe = New-Object System.Collections.Generic.List[object]
$pendingDeferred = New-Object System.Collections.Generic.List[object]
$exitCode = 0
$batchSeq = 0

Push-Location $ProjectRoot
try {
    $bodyPlano = @{ action = 'listar_plano_rotina'; routine_key = $routineKey; modo = $Perfil.modo }
    if ($Perfil.top_n -gt 0) { $bodyPlano.top_n = $Perfil.top_n }
    $plano = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj $bodyPlano -TimeoutSec 180
    if ($plano.ok -ne $true) { Write-Log 'ERRO: plano'; exit 5 }
    if ($Perfil.modo -eq 'noturno' -and $plano.total -ne 103) { Write-Log ('ERRO: plano noturno com total ' + $plano.total + ' (esperado 103)'); exit 5 }
    if ($plano.total -eq 0) {
        Write-Log ('FIM: ' + $Rotina + ' concluido. Total do dia 0/0. analisados=0 skip=0 deferidos=0 submits_aceitos=0 (plano vazio)')
        exit 0
    }
    $planoTotal = [int]$plano.total

    @{
        data = $plano.data; tiers = $plano.contagem_tiers; buscas = $plano.buscas_estimadas
        emissores = @($plano.emissores | ForEach-Object { @{ e = $_.empresa; t = $_.tier; ews = $_.ews_score; m = @($_.motivos)[0] } })
    } | ConvertTo-Json -Compress -Depth 5 | Set-Content (Join-Path $LogDir ($Perfil.prefix + '_plano_' + $DateTag + '.json')) -Encoding UTF8
    Write-Log ('Plano ' + ($plano.contagem_tiers | ConvertTo-Json -Compress) + ' total=' + $planoTotal + $(if ($Perfil.modo -eq 'matinal') { ' top_n_solicitado=' + $plano.top_n_solicitado + ' extras_setor=' + @($plano.extras_setor).Count } else { '' }))
    $creditados = @($plano.emissores | Where-Object { $_.tier -eq 'SKIP' -and @($_.motivos)[0] -like 'analisado_hoje_por_*' })
    if ($creditados.Count -gt 0) {
        Write-Log ('CREDITO_DIA: ' + $creditados.Count + ' emissores ja analisados hoje por outra rotina (SKIP): ' + (($creditados | ForEach-Object { $_.empresa + '<' + (@($_.motivos)[0] -replace '^analisado_hoje_por_', '') + '>' }) -join ', '))
    }

    # Idempotencia por ledger do dia (v4.9.151): reinicio nao reprocessa quem ja tem OK|.
    $jaProcessados = @{}
    if (-not $Force -and -not $DryRun -and (Test-Path $LogFile)) {
        $linhasOk = Get-Content $LogFile -Encoding UTF8 | Where-Object { $_ -match '^[\d-]+ [\d:]+ OK\|([^|]+)\|' }
        foreach ($linha in $linhasOk) { if ($linha -match 'OK\|([^|]+)\|') { $jaProcessados[(Get-NomeNormalizado $Matches[1])] = $true } }
        if ($jaProcessados.Count -gt 0) { Write-Log ('Idempotencia: ' + $jaProcessados.Count + ' emissores ja processados hoje, pulando') }
    } elseif ($Force) {
        Write-Log 'AVISO: -Force ativo. Trava de idempotencia ignorada.'
    }

    $janIni = '' + $plano.emissores[0].janela_inicio
    $janFim = '' + $plano.emissores[0].janela_fim

    # SKIP do plano (inclui os creditados): submissao minima para o ledger fechar em 103.
    $skipQueue = @($plano.emissores | Where-Object { $_.tier -eq 'SKIP' -and -not $jaProcessados.ContainsKey((Get-NomeNormalizado $_.empresa)) })
    $skipN = 0
    foreach ($emp in $skipQueue) {
        $skipN++
        $subOk = $false
        try { $r = Submit-SkipEmissor $routineKey $emp; $subOk = ($r.ok -eq $true) } catch { $subOk = $false }
        if ($subOk) { $stats.skip_ok++ } else { $stats.skip_fail++ }
        Write-Ledger $emp.empresa 'SKIP' '-' 0 $subOk 'SKIP'
        if (-not $DryRun) { Start-Sleep -Milliseconds 400 }
    }
    Write-Log ('SKIP_LOTE: ok=' + $stats.skip_ok + ' falha=' + $stats.skip_fail + ' total=' + $skipQueue.Count)

    # Fila unica, ordenada por risco: cortes por cap caem sempre na cauda de menor EWS.
    $analyzeList = @($plano.emissores | Where-Object { $_.tier -ne 'SKIP' -and -not $jaProcessados.ContainsKey((Get-NomeNormalizado $_.empresa)) })
    $fila = @($analyzeList | Sort-Object -Property ews_score, cvm_novos -Descending)
    foreach ($emp in $fila) {
        $h = if ($null -ne $emp.horas_desde_analise) { $emp.horas_desde_analise } else { '-' }
        $u = if ($emp.ultima_origem) { $emp.ultima_origem } else { '-' }
        Write-Log ('ALVO ' + $emp.empresa + ' tier=' + $emp.tier + ' cvm_novos=' + $emp.cvm_novos + ' motivo=' + @($emp.motivos)[0] + ' ews=' + $emp.ews_score + ' ultimo=' + $u + ' h=' + $h + ' aplicado=' + $Perfil.tier)
    }
    if ($MaxEmissores -gt 0) {
        if ($DryRun) {
            $fila = @($fila | Select-Object -First $MaxEmissores)
            Write-Log ('AMOSTRA: -MaxEmissores ' + $MaxEmissores + ' (dry-run, medicao)')
        } else {
            Write-Log 'AVISO: -MaxEmissores ignorado fora de -DryRun (a rotina real cobre a fila inteira)'
        }
    }
    Write-Log ('Fila ' + $Perfil.tier + ': ' + $fila.Count + ' emissores em lotes de ' + $Perfil.chunk + ' (cap_efetivo=' + $TokenHardCap + ')')

    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($chunk in (Split-IntoChunks $fila $Perfil.chunk)) {
        $jobs.Add([ordered]@{ Name = $Perfil.tier.ToLower(); Model = $Perfil.model; Chunk = @($chunk); Skill = $Perfil.skill; Ultra = [bool]$Perfil.ultra; Provedor = $Perfil.provedor })
    }
    $lotesEsperados = if ($fila.Count -eq 0) { 0 } else { [Math]::Ceiling($fila.Count / $Perfil.chunk) }
    if ($jobs.Count -ne $lotesEsperados) {
        Write-Log ("AVISO CRITICO: agrupamento de lotes incorreto - lotes=$($jobs.Count) esperado=$lotesEsperados (fila=$($fila.Count)). Possivel regressao de Split-IntoChunks.")
    }

    $ji = 0
    $abortAfterSubmit = $false
    $capAtingido = $false
    foreach ($job in $jobs) {
        $ji++
        Update-VixLock
        $estLote = $Perfil.bootTok + ($job.Chunk.Count * $Perfil.unitTok)
        if ($capAtingido -or ($stats.tokens_total + $estLote) -ge $TokenHardCap) {
            $stats.tokens_hard_hit = $true
            $capAtingido = $true
            foreach ($e in $job.Chunk) { $pendingDeferred.Add($e) }
            Write-Log ('CAP pre-lote: acum=' + $stats.tokens_total + ' est=' + $estLote + ' >= ' + $TokenHardCap + ' - lote ' + $job.Name + '-' + $ji + ' deferred (' + $job.Chunk.Count + ' emissores, cauda de menor EWS)')
            continue
        }
        if (($stats.tokens_total + $estLote) -ge $TokenTarget -and -not $stats.tokens_over_target) {
            $stats.tokens_over_target = $true
            Write-Log ('AVISO: meta ' + $TokenTarget + ' sera ultrapassada neste lote (acum=' + $stats.tokens_total + ' est=' + $estLote + ') - continua ate o cap ' + $TokenHardCap)
        }

        $batchSeq++
        $label = $job.Name + '-' + $ji
        $prompt = New-BatchPrompt $job.Chunk $label $job.Model $job.Skill $janIni $janFim -Ultra:$job.Ultra
        $promptPath = Join-Path $LogDir ($Perfil.prefix + '_' + $label + '_' + $DateTag + '.txt')
        Set-Content $promptPath -Value $prompt -Encoding UTF8

        Write-Log ('Lote ' + $label + ' [' + $job.Model + ']: ' + (($job.Chunk | ForEach-Object { $_.empresa }) -join ', '))
        $swLote = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-ClaudeBatch $promptPath $job.Model
        $swLote.Stop()
        $stats.batches_run++
        if ($result.Escalou) {
            $stats.auth_escalou = 'api'
            Write-Log ($AlertaAuthTag +$Rotina + ' escalou para chave paga no lote ' + $label + ' (credencial de assinatura recusada no meio da execucao). Lotes seguintes custam dolar.')
            # DRYRUN-CRASH1: dry-run nunca dispara notificar_rotina (02/09 02:45 mandou e-mail real de um teste).
            if ($DryRun) { Write-Log 'DRYRUN: alerta NAO enviado (notificar_rotina suprimido em dry-run)' }
            else { $null = Send-VixRoutineAlert -Rotina $Rotina -Motivo ('ALERTA_AUTH: escalou para chave paga no lote ' + $label + ' - assinatura recusada no meio da execucao; regerar token com claude setup-token') -RoutineKey $routineKey }
        }
        if ($result.AuthFailure) {
            $motivoAuth = Get-ClaudeAuthMotivo $result.Output
            $jIdx = Get-JobIndex $jobs $job
            Write-Log ('ERRO CRITICO: claude -p recusou o lote ' + $label + ' - ' + $motivoAuth + ' - abortando lotes restantes (' + ($jobs.Count - $jIdx - 1) + ' lote(s) NAO processado(s)).')
            Write-Log ($AlertaAuthTag +$Rotina + ' abortada no lote ' + $label + ' - ' + $motivoAuth)
            if ($DryRun) { Write-Log 'DRYRUN: alerta NAO enviado (notificar_rotina suprimido em dry-run)' }
            else { $null = Send-VixRoutineAlert -Rotina $Rotina -Motivo ('ALERTA_AUTH: ' + $motivoAuth + ' - lotes restantes abortados (' + $label + ')') -RoutineKey $routineKey }
            $exitCode = 7
            $stats.batch_fail++
            Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
            # Lote atual (nada submetido) e todos os seguintes vao para DEFERIDO.
            if ($jIdx -ge 0) { for ($k = $jIdx; $k -lt $jobs.Count; $k++) { foreach ($e in $jobs[$k].Chunk) { $pendingDeferred.Add($e) } } }
            break
        }

        if ($result.Output) { $result.Output | ForEach-Object { Write-Log ('OUT: ' + $_) } }

        $bt = $result.Tokens
        if ($bt -gt 0) {
            $stats.tokens_total += $bt
            $stats.input += $result.Parcelas.input; $stats.output += $result.Parcelas.output
            $stats.cache_creation += $result.Parcelas.cache_creation; $stats.cache_read += $result.Parcelas.cache_read
            Write-Log ('Tokens lote=' + $bt + ' (input=' + $result.Parcelas.input + ' output=' + $result.Parcelas.output + ' cache_creation=' + $result.Parcelas.cache_creation + ' cache_read=' + $result.Parcelas.cache_read + ') acum=' + $stats.tokens_total)
        } else {
            Write-Log 'Tokens lote=DESCONHECIDO (parse falhou) - acum inalterado'
        }
        $lotesDetalhe.Add([ordered]@{
            nome = $label; fila = $job.Name; emissores = $job.Chunk.Count
            input = $result.Parcelas.input; output = $result.Parcelas.output; cache_creation = $result.Parcelas.cache_creation
            cache_read = $result.Parcelas.cache_read; trabalho = $result.Parcelas.trabalho; duracao_sec = [Math]::Round($swLote.Elapsed.TotalSeconds, 1)
        })

        $parsed = Get-ParsedResultados $result.Output
        $buscasLote = $parsed.Buscas

        $missing = @($job.Chunk | Where-Object { -not (Get-ResultadoEmissor $parsed.Map $_.empresa) })
        if ($missing.Count -gt 0) {
            Write-Log ('WARN: ' + $missing.Count + ' sem RESULTADO no lote ' + $label + ' - retry parcial: ' + (($missing | ForEach-Object { $_.empresa }) -join ', '))
            $retryLabel = $label + '-retry'
            $retryPrompt = New-BatchPrompt $missing $retryLabel $job.Model $job.Skill $janIni $janFim -Ultra:$job.Ultra
            $retryPath = Join-Path $LogDir ($Perfil.prefix + '_' + $retryLabel + '_' + $DateTag + '.txt')
            Set-Content $retryPath -Value $retryPrompt -Encoding UTF8
            $retryRes = Invoke-ClaudeBatch $retryPath $job.Model
            if ($retryRes.Escalou) { $stats.auth_escalou = 'api'; Write-Log ('ALERTA_AUTH: escalou para chave paga no retry ' + $retryLabel) }
            if ($retryRes.AuthFailure) {
                # RETRYDROP1: preserva o que o lote principal ja parseou, marca abort apos submit.
                Write-Log ('ERRO CRITICO: claude -p recusou o retry do lote ' + $label + ' - ' + (Get-ClaudeAuthMotivo $retryRes.Output) + ' - ' + $missing.Count + ' faltantes recebem fallback; lotes restantes NAO serao processados.')
                $exitCode = 7
                $stats.batch_fail++
                $abortAfterSubmit = $true
                Remove-Item $retryPath -Force -ErrorAction SilentlyContinue
            } else {
                if ($retryRes.Output) { $retryRes.Output | ForEach-Object { Write-Log ('OUT-RETRY: ' + $_) } }
                if ($retryRes.Tokens -gt 0) {
                    $stats.tokens_total += $retryRes.Tokens
                    $stats.input += $retryRes.Parcelas.input; $stats.output += $retryRes.Parcelas.output
                    $stats.cache_creation += $retryRes.Parcelas.cache_creation; $stats.cache_read += $retryRes.Parcelas.cache_read
                    $lotesDetalhe.Add([ordered]@{ nome = $retryLabel; fila = $job.Name; emissores = $missing.Count; input = $retryRes.Parcelas.input; output = $retryRes.Parcelas.output; cache_creation = $retryRes.Parcelas.cache_creation; cache_read = $retryRes.Parcelas.cache_read; trabalho = $retryRes.Parcelas.trabalho; duracao_sec = 0 })
                }
                $retryParsed = Get-ParsedResultados $retryRes.Output
                foreach ($k in @($retryParsed.Map.Keys)) { $parsed.Map[$k] = $retryParsed.Map[$k] }
                if ($retryParsed.Buscas -gt 0) { if ($buscasLote -lt 0) { $buscasLote = 0 }; $buscasLote += $retryParsed.Buscas }
                Remove-Item $retryPath -Force -ErrorAction SilentlyContinue
            }
        }

        $parsedCount = 0
        foreach ($emp in $job.Chunk) { if (Get-ResultadoEmissor $parsed.Map $emp.empresa) { $parsedCount++ } }
        if ($parsedCount -eq 0) {
            $stats.silent_fail++
            Write-Log ('ERRO: lote ' + $label + ' sem RESULTADO| - falha silenciosa (0/' + $job.Chunk.Count + ' emissores com analise real)')
        }

        $loteOk = 0; $loteFail = 0; $loteCrit = 0; $loteDry = 0
        $buscasReaisLote = 0
        $iAgudo = [char]0x00ED
        $aTil = [char]0x00E3
        foreach ($emp in $job.Chunk) {
            $res = Get-ResultadoEmissor $parsed.Map $emp.empresa
            $buscasEfetivas = 0
            if (-not $res) {
                Write-Log ('WARN: ' + $emp.empresa + '|sem RESULTADO apos retry - submit minimo de cobertura pendente')
                $res = [pscustomobject]@{
                    classificacao_geral = 'NENHUM'; sem_eventos = $true
                    cobertura_nota = 'Falha de parse do agente apos retry - cobertura pendente, revisar manualmente.'
                    eventos = @(); fontes_consultadas = @()
                }
            } else {
                foreach ($f in @($res.fontes_consultadas)) {
                    $r = '' + $f.resultado
                    if ($r -and $r -notmatch "indisponivel|indispon${iAgudo}vel|falha|erro|n[a${aTil}]o execut|timeout|^vazio$|^$") { $buscasEfetivas++ }
                }
            }
            $buscasReaisLote += $buscasEfetivas
            $classif = '' + $res.classificacao_geral
            if (-not $classif) { $classif = if (@($res.eventos).Count -gt 0) { 'RELEVANTE' } else { 'ECO' } }
            if ($Perfil.tier -eq 'FULL' -and $buscasEfetivas -eq 0 -and $classif -ne 'CRITICO') {
                Write-Log ('WARN: ' + $emp.empresa + '|FULL com 0 buscas efetivas -> INCONCLUSIVO')
                $classif = 'INCONCLUSIVO'
                $res.sem_eventos = $true
                if (-not $res.cobertura_nota) { $res.cobertura_nota = 'Zero buscas efetivas - cobertura nao verificavel (falha de ferramenta ou modelo).' }
            }
            try { $res | Add-Member -NotePropertyName '_tier' -NotePropertyValue $Perfil.tier -Force } catch { }
            $subOk = $false; $nEv = 0
            try {
                $resp = Submit-Analise $routineKey $emp.empresa $emp.setor $res $job.Provedor $Perfil.tier @($emp.cvm_novos_ids)
                if ($resp.ok -ne $true -and -not $DryRun) {
                    Start-Sleep -Seconds $PauseSec
                    $resp = Submit-Analise $routineKey $emp.empresa $emp.setor $res $job.Provedor $Perfil.tier @($emp.cvm_novos_ids)
                }
                $subOk = ($resp.ok -eq $true)
                if ($subOk) { $nEv = [int]$resp.n_eventos }
                elseif ($resp.erro) { Write-Log ('SUBMIT_ERRO|' + $emp.empresa + '|' + $resp.erro) }
            } catch {
                Write-Log ('SUBMIT_EXC|' + $emp.empresa + '|' + $_.Exception.Message)
            }
            if ($DryRun) { $subOk = $false }
            Write-Ledger $emp.empresa $Perfil.tier $classif $nEv $subOk 'ANALISADO'
            $stats.analisados++
            # Dry-run nao submete: nao e ok nem fail, e contado a parte (antes saia fail=3 enganoso).
            if ($DryRun) { $loteDry++ } elseif ($subOk) { $loteOk++ } else { $loteFail++ }
            if ($classif -eq 'CRITICO') { $loteCrit++; $stats.criticos.Add($emp.empresa) }
        }
        $stats.submit_ok += $loteOk
        $stats.submit_fail += $loteFail
        if ($buscasReaisLote -gt 0 -or $buscasLote -lt 0) { $buscasLote = $buscasReaisLote }
        if ($buscasLote -ge 0) { $stats.buscas_total += $buscasLote }
        Write-Log ('LOTE_FECHADO|' + $label + '|ok=' + $loteOk + '|fail=' + $loteFail + '|dryrun=' + $loteDry + '|buscas=' + $buscasLote + '|criticos=' + $loteCrit + '|tokens=' + $bt + '|duracao_sec=' + [Math]::Round($swLote.Elapsed.TotalSeconds, 1))
        if ($loteFail -gt 0 -and -not $DryRun) { $stats.batch_fail++ } else { $stats.batch_ok++ }
        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
        Update-VixLock
        if ($abortAfterSubmit) {
            Write-Log 'ABORT: retry AuthFailure - resultados deste lote submetidos, lotes restantes NAO processados'
            # Lote atual ja submetido: so os seguintes vao para DEFERIDO.
            $jIdx = Get-JobIndex $jobs $job
            if ($jIdx -ge 0) { for ($k = $jIdx + 1; $k -lt $jobs.Count; $k++) { foreach ($e in $jobs[$k].Chunk) { $pendingDeferred.Add($e) } } }
            break
        }
    }

    foreach ($emp in $pendingDeferred) {
        $subOk = $false
        try { $r = Submit-CapDeferred $routineKey $emp; $subOk = ($r.ok -eq $true) } catch { $subOk = $false }
        if ($subOk) { $stats.deferred++ } else { $stats.deferred_fail++ }
        Write-Ledger $emp.empresa $emp.tier '-' 0 $subOk 'DEFERIDO'
        if (-not $DryRun) { Start-Sleep -Milliseconds 400 }
    }
    if ($pendingDeferred.Count -gt 0) {
        Write-Log ('DEFERIDOS: ok=' + $stats.deferred + ' falha=' + $stats.deferred_fail + ' total=' + $pendingDeferred.Count + ' motivo=cap_efetivo (' + $stats.tokens_total + '/' + $TokenHardCap + ' realizados)')
    }

    $sw.Stop()
    $submitsAceitos = $stats.skip_ok + $stats.submit_ok + $stats.deferred
    $ledgerTotal = $stats.skip_ok + $stats.skip_fail + $stats.analisados + $stats.deferred + $stats.deferred_fail

    # METRICSZERO1: reinicio idempotente nao sobrescreve metrics de execucao real com zeros.
    $gravarMetrics = $true
    if (-not $DryRun -and $stats.analisados -eq 0 -and $stats.skip_ok -eq 0 -and (Test-Path $MetricsFile)) {
        try {
            $existente = Get-Content $MetricsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existente.analisados -gt 0 -or $existente.submit_ok -gt 0) { Write-Log 'METRICSZERO1: metrics preservado (execucao atual zerada por idempotencia)'; $gravarMetrics = $false }
        } catch {}
    }
    if ($gravarMetrics) {
        [ordered]@{
            data = $DateTag; rotina = $Rotina; dryrun = [bool]$DryRun; motor = 'task-scheduler'
            token_target = $TokenTarget; token_hard_cap = $TokenHardCap; cap_proprio = $Perfil.capProprio; circuito_aberto = [bool]$custoDia.circuito_aberto
            tokens_total_est = $stats.tokens_total; tokens_trabalho = $stats.tokens_total
            tokens_input = $stats.input; tokens_output = $stats.output; tokens_cache_creation = $stats.cache_creation; tokens_cache_read = $stats.cache_read
            tokens_over_target = $stats.tokens_over_target; tokens_hard_hit = $stats.tokens_hard_hit
            analisados = $stats.analisados; skip_ok = $stats.skip_ok; deferred = $stats.deferred; submits_aceitos = $submitsAceitos
            submit_ok = $stats.submit_ok; submit_fail = $stats.submit_fail; buscas_total = $stats.buscas_total; silent_fail = $stats.silent_fail
            # DRYRUN-CRASH1: @(List[object]) com [ordered] dentro estoura o binder do 5.1
            # ("Os tipos de argumento nao correspondem"), reproduzido isolado em 02/09. ToArray() nao.
            lotes = $stats.batches_run; batches = $stats.batches_run; lotes_detalhe = $lotesDetalhe.ToArray()
            criticos = $stats.criticos.ToArray(); duracao_sec = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
            auth_modo_inicial = $authModoInicial; auth_escalou = $stats.auth_escalou
        } | ConvertTo-Json -Depth 6 | Set-Content $MetricsFile -Encoding UTF8
    }

    $fimTag = if ($DryRun) { 'FIM_DRYRUN: ' } else { 'FIM: ' }
    Write-Log ($fimTag + $Rotina + ' concluido. Total do dia ' + $ledgerTotal + '/' + $planoTotal + '. analisados=' + $stats.analisados + ' skip=' + $stats.skip_ok + ' deferidos=' + $stats.deferred + ' submits_aceitos=' + $submitsAceitos +
        ' submit_ok=' + $stats.submit_ok + ' submit_fail=' + $stats.submit_fail + ' tokens=' + $stats.tokens_total + ' cache_read=' + $stats.cache_read + ' cap_efetivo=' + $TokenHardCap + ' lotes=' + $stats.batches_run +
        ' buscas=' + $stats.buscas_total + ' silent_fail=' + $stats.silent_fail + ' criticos=' + $stats.criticos.Count + ' auth_escalou=' + $stats.auth_escalou + ' duracao_sec=' + [Math]::Round($sw.Elapsed.TotalSeconds, 1))

    $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $errosTotal = $stats.silent_fail + $stats.skip_fail + $stats.batch_fail + $stats.submit_fail + $stats.deferred_fail
    $resultadoTxt = if ($DryRun) { 'DRYRUN' } elseif ($errosTotal -gt 0) { 'PARCIAL' } else { 'OK' }
    Write-Log ('ROTINA_RESUMO|' + $Perfil.id + '|local|' + $inicioIso + '|' + $fimIso + '|' + $resultadoTxt + '|' + $stats.submit_ok + '|' + $errosTotal + '|' + $stats.deferred + '|' + $versaoWorker)

    # Dreno da fila de verificacao logo apos a varredura (v4.9.150): evento CRITICO nao fica
    # preso ate o proximo dreno agendado. Nunca em dry-run.
    if ($stats.submit_ok -gt 0 -and -not $DryRun) {
        $verifScript = Join-Path $ScriptsDir 'run_vixradar_verificacao_async.ps1'
        if (Test-Path $verifScript) {
            Write-Log ('POS-' + $Rotina.ToUpper() + ': drenando fila de verificacao...')
            try {
                $verifProc = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$verifScript`"" -PassThru -Wait -NoNewWindow
                Write-Log ('POS-' + $Rotina.ToUpper() + ': dreno concluido (exit=' + $verifProc.ExitCode + ')')
            } catch { Write-Log ('POS-' + $Rotina.ToUpper() + ': ERRO ao executar dreno - ' + $_.Exception.Message) }
        }
    }

    if (-not $DryRun -and ($stats.silent_fail -gt 0 -or $stats.skip_fail -gt 0 -or $stats.batch_fail -gt 0)) { if ($exitCode -eq 0) { $exitCode = 6 } }
} catch {
    $errMsg = 'ERRO FATAL: excecao nao tratada no bloco principal - ' + $_.Exception.Message
    # DRYRUN-CRASH1: o StackTrace do .NET nao diz a linha do script. ScriptStackTrace e PositionMessage dizem.
    $stackMsg = 'STACK: ' + ('' + $_.ScriptStackTrace) + ' | POS: ' + (('' + $_.InvocationInfo.PositionMessage) -replace '\r?\n', ' ') + ' | NET: ' + $_.Exception.StackTrace
    Write-Safe $errMsg; Write-Safe $stackMsg
    try { Add-Content -Path $LogFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $errMsg) -Encoding UTF8 -ErrorAction Stop } catch {}
    try { Add-Content -Path $LogFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $stackMsg) -Encoding UTF8 -ErrorAction Stop } catch {}
    $exitCode = 1
} finally {
    Remove-BatchPrompts $DateTag
    Invoke-Cleanup -Aggressive
    Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    try { $__mutex.ReleaseMutex() } catch { }
    Pop-Location
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
}

if ($exitCode -ne 0) { exit $exitCode }
exit 0
