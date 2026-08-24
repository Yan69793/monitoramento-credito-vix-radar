# run_vixradar_noturno_claude.ps1 - Noturno v2: SKIP PS1 + Haiku/Sonnet por prioridade, cap 500k tokens
param(
    [switch]$Force,
    # Shadow DeepSeek: reclassifica com as mesmas fontes do Claude. NUNCA submete ao Worker.
    # Tambem: env VIXRADAR_NOTURNO_SHADOW_DEEPSEEK=1 + DEEPSEEK_API_KEY / VIXRADAR_DEEPSEEK_API_KEY
    [switch]$ShadowDeepSeek
)
# 'Continue' obrigatorio: regra do CLAUDE.md do VIX Radar. Com 'Stop' o script
# aborta antes do 'exit' e o Task Scheduler/Claude Desktop perde o codigo de saida.
$ErrorActionPreference = 'Continue'
# PIPE1: console oculto e best-effort; erros funcionais continuam terminantes.

# Sem isso, stdout do binario nativo 'claude' pode ser decodificado com o codepage ANSI/OEM
# em vez de UTF-8 quando o processo roda sem console interativo (scheduled task) - corrompe
# nomes de emissores acentuados (ex.: "Raizen"->"Ra┬íen") e quebra o match em Get-ResultadoEmissor,
# descartando RESULTADO valido e submetendo NENHUM/sem_eventos no lugar (achado 2026-07-05).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot    = 'E:\Diretorio\Claude\Monitoramento de Credito'
$WorkerUrl      = 'https://api.vixradar.com'
$ScriptsDir     = Join-Path $ProjectRoot 'scripts'
$ScheduledTasks = 'C:\Users\User\.claude\scheduled-tasks'
$CleanupScript  = Join-Path $ProjectRoot 'scripts\cleanup-rotina-artifacts.ps1'
$HaikuSkill     = Join-Path $ScriptsDir 'noturno-batch-haiku.md'
$SonnetSkill    = Join-Path $ScriptsDir 'noturno-batch-sonnet.md'
$LogDir         = Join-Path $ProjectRoot 'logs\routines'
$DateTag        = Get-Date -Format 'yyyyMMdd'
$LogFile        = Join-Path $LogDir ('vixradar-noturno_' + $DateTag + '.log')
$MetricsFile    = Join-Path $LogDir ('noturno_metrics_' + $DateTag + '.json')
$ShadowJsonl    = Join-Path $LogDir ('noturno_shadow_deepseek_' + $DateTag + '.jsonl')
$ShadowSummaryFile = Join-Path $LogDir ('noturno_shadow_summary_' + $DateTag + '.json')
$McpConfigFile  = Join-Path $LogDir 'mcp-empty.json'

$ModelHaiku     = 'claude-haiku-4-5-20251001'
$ModelSonnet    = 'claude-sonnet-4-6'
$TokenTarget    = 500000   # meta - passar um pouco OK
$TokenHardCap   = 700000   # deferred só acima disto
# Coeficientes da estimativa pre-lote (ver bloco do hard cap). Modelo aditivo: boot + n * unit.
# CALIB1 (2026-08-18): Haiku recalibrado para o custo medido em sessao agendada (17/08: 9,4k/emissor,
# 15/08: 12,4k/emissor). A estimativa antiga de 4,5k fazia o plano achar que 89 emissores cabiam e o
# hard cap estourava no meio. Este script nao e mais o executor (a sessao do Desktop usa a skill em
# ~/.claude/scheduled-tasks/vixradar-noturno/), mas as constantes ficam coerentes com a skill.
# CALIB2 (2026-08-24): custo real medido nos 4 lotes de 23/08, colado no log daquele dia
# ("25,2k por emissor na aprofundada e 12,3k na rapida, contra 13k e 9,5k previstos").
# A subestimativa nao era academica: com 9,5k o plano achava que a fila rapida cabia
# folgada, gastava 673k dos 700k nela e a fila APROFUNDADA nao disparava. Em 22/08 os 19
# emissores de maior risco sairam com DEFERIDO|0 evento, e em 23/08 foram 31.
$TokenBootOverhead     = 15000   # piso fixo por invocacao do claude (medido ~13,6k - ver Invoke-ClaudeBatch)
$TokenPerEmissorSonnet = 25200   # medido 23/08 em 2 lotes aprofundados (152.644 + 149.312)
$TokenPerEmissorHaiku  = 12300   # medido 23/08 em 2 lotes rapidos (180.115 + 168.861)
# CAPRESERVA1 (2026-08-24): a fila rapida roda primeiro de proposito (inverter a ordem ja
# zerou o Haiku em 09/07), mas rodar primeiro nao pode significar gastar tudo. A rapida
# agora consome no maximo (hard cap - reserva da aprofundada). O corte cai na cauda da
# rapida, que ja vem ordenada por EWS desc, entao sobra risco minimo, nao risco alto.
$TokenReservaFracaoAprofundada = 0.60
$SonnetEwsMin   = 38
$HaikuChunk     = 15
$SonnetChunk    = 11
$PauseSec       = 2

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# PIPE1 (2026-07-28): Write-Host sob -WindowStyle Hidden do Task Scheduler quebrava o pipe do
# console apos ~28 min de execucao (ERROR_PIPE_NOT_CONNECTED 0xE9). Esta funcao absorve o crash
# silenciosamente — o log em arquivo (Write-Log) ja registrou a linha; a perda no console e
# irrelevante em execucao agendada.
function Write-Safe([string]$msg) {
    try { Write-Host $msg } catch { }
}

# v4.9.151: Start-Transcript captura TODO o output do script (stdout+stderr do processo),
# incluindo crashes que o try/catch nao alcanca (ex.: claude.exe matando o processo pai).
# Sem isso, 5 reinicios em 09/07 ficaram sem diagnostico (stderr vazio).
$TranscriptFile = Join-Path $LogDir ('noturno_transcript_' + $DateTag + '_' + $PID + '.txt')
try { Start-Transcript -Path $TranscriptFile -Append -Force -ErrorAction Stop } catch {
    Write-Safe "AVISO: Start-Transcript falhou ($($_.Exception.Message)) - continuando sem transcript"
}

# --mcp-config recebia JSON inline ('{"mcpServers":{}}') - em execucao agendada (scheduled task,
# possivelmente via powershell.exe 5.1 em vez de pwsh) as aspas embutidas eram perdidas na
# serializacao do argumento nativo, chegando ao claude.exe como {mcpServers:{}} sem aspas -> CLI
# tentava resolver como CAMINHO de arquivo e falhava com "MCP config file not found" em TODA
# chamada (achado 2026-07-05: rotina de 04/07 18h teve 0 buscas/0 tokens em 98/98 emissores por
# isso; so a 2a tentativa manual 5 min depois, noutro contexto de shell, funcionou). Arquivo
# elimina qualquer ambiguidade de quoting entre interpretadores.
Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding UTF8

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Write-Safe $line
    # Retry com backoff: incidente 2026-07-17 - segunda instancia pendurada segurou o handle do
    # log por ~2h e TODAS as escritas desta funcao falharam ("arquivo em uso"), cegando a
    # auditoria da rotina que rodou com sucesso. Reincidencia sustentada 2026-07-18 (LOGLOCK1-REC,
    # PENDENCIAS.md): lock ocupado 7+ min seguidos (suspeita OneDrive/SearchIndexer), 100% das
    # escritas da corrida falharam com o backoff antigo (5x200ms ~= 1s). Backoff exponencial ate
    # 8 tentativas (200/400/800/1600/2000x4ms ~= 11s no pior caso). Se todas falharem, fallback
    # para arquivo alternativo com PID no nome — nenhuma linha de log e perdida.
    for ($i = 1; $i -le 8; $i++) {
        try {
            Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
            return
        } catch {
            if ($i -eq 8) {
                $fallbackFile = ([regex]::Replace($LogFile, '\.log$', "_fallback_$pid.log"))
                Write-Safe "FALHA Write-Log ($i tentativas), fallback: $fallbackFile — $($_.Exception.Message)"
                try { Add-Content -Path $fallbackFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch { Write-Safe "FALHA Write-Log IRRECUPERAVEL: $($_.Exception.Message)" }
            }
            else { Start-Sleep -Milliseconds ([Math]::Min(200 * [Math]::Pow(2, $i - 1), 2000)) }
        }
    }
}

function Test-ClaudeAuthFailure([string[]]$outputLines) {
    # Achado 2026-07-08: claude.exe pode perder a sessao OAuth local (Task Scheduler roda sem
    # console interativo) e imprimir esta mensagem em vez do envelope JSON - exit code do
    # processo continua 0, entao sem esta checagem o lote falso-positiva como sucesso e a
    # rotina degrada silenciosamente (RESULTADO ausente -> fallback "cobertura pendente" via
    # receber_analise, que sempre responde ok:true por ser so um HTTP POST ao Worker).
    $texto = ($outputLines -join "`n")
    return $texto -match '(?i)not logged in|please run /login|disabled claude subscription|use an anthropic api key instead|weekly limit|hit your.*limit|credit balance is too low|insufficient.*credit'
}

function Invoke-Cleanup([switch]$Aggressive) {
    if (-not (Test-Path $CleanupScript)) { return }
    try {
        if ($Aggressive) { $out = & $CleanupScript -KeepDays 7 -Aggressive }
        else { $out = & $CleanupScript -KeepDays 7 }
        Write-Log ('Cleanup: ' + $out)
    } catch {
        Write-Log ('Cleanup aviso: ' + $_.Exception.Message)
    }
}

function Get-RoutineKey {
    # v4.9.187: fallback de leitura de SKILL.md removido (recomendacao PENDENCIAS.md 2026-08-03).
    # O SKILL.md em scheduled-tasks/ pode conter chave velha apos rotacao. Env var e canonica.
    # ROTA1 (2026-08-18): apos a rotacao da chave, o registro User e a fonte da verdade.
    # Processo longevo (sessao do Claude Desktop) herda o env do boot e mandaria a chave
    # velha ate reiniciar - mesmo modo de falha que o rotate-routine-key.ps1 corrigiu na
    # hidratacao dele. Hidratar do registro SEMPRE, nao so quando o env esta ausente.
    $doRegistro = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    if ($doRegistro) { return $doRegistro }
    if ($env:ROUTINE_API_KEY) { return $env:ROUTINE_API_KEY }
    throw 'ROUTINE_API_KEY nao definida. Configure: $env:ROUTINE_API_KEY = "<chave>"'
}

# Auth do `claude -p` mora em um lugar so (2026-07-30). Antes disso a mesma logica estava
# copiada nos tres scripts de rotina, e a correcao do incidente 73 teve que ser aplicada
# tres vezes. Politica: assinatura primeiro, chave paga so quando o OAuth nao responde.
. (Join-Path $PSScriptRoot 'lib\vixradar-claude-auth.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')

# Assert-VixLibFunctions garante que funcoes removidas/renomeadas nas libs sem
# atualizar os call sites sao detectadas na hora, com erro claro, em vez de
# silenciosamente apos 24h como aconteceu em 04-05/08/2026.
Assert-VixLibFunctions @('Set-VixClaudeAuthEnv', 'Test-VixClaudeAmbienteLimpo', 'Test-VixWebSearchProbe', 'Send-VixRoutineAlert')

# Shadow DeepSeek e opcional e nunca submete ao Worker. Dot-source com guarda para
# a noturna nao morrer se a lib nao estiver presente (auditoria 2026-08-04: o arquivo
# estava untracked, entao um clone limpo do repo quebraria aqui).
$ShadowLibPath = Join-Path $PSScriptRoot 'lib\vixradar-noturno-shadow-deepseek.ps1'
$ShadowLibOk = $false
if (Test-Path $ShadowLibPath) {
    . $ShadowLibPath
    $ShadowLibOk = $true
} else {
    Write-Host "AVISO: lib do shadow DeepSeek ausente ($ShadowLibPath). Noturna segue sem shadow." -ForegroundColor Yellow
}

function Get-AnthropicApiKey {
    # Mantida como fachada: ha chamadas antigas por este nome. A regra vive no helper.
    return (Get-VixAnthropicApiKey)
}

function Get-CvmResumo($docs) {
    if (-not $docs) { return '0 docs' }
    $arr = @($docs)
    if ($arr.Count -eq 0) { return '0 docs' }
    return ($arr.Count.ToString() + ' docs')
}

function Get-SlimEmissor($emp, [switch]$Ultra) {
    # projeta docs CVM para os 4 campos que o agente usa; empresa_cvm so quando for alias divergente
    $docs = @($emp.cvm_documentos | Select-Object -First $(if ($Ultra) { 2 } else { 3 }) | ForEach-Object {
        $assunto = '' + $_.assunto
        if ($assunto.Length -gt 100) { $assunto = $assunto.Substring(0, 100) }
        $d = [ordered]@{ categoria = $_.categoria; assunto = $assunto; data = $_.data; link = $_.link }
        if ($_.empresa_cvm -and ($_.empresa_cvm -notmatch [regex]::Escape(($emp.empresa -split ' ')[0]))) {
            $d['empresa_cvm'] = $_.empresa_cvm
        }
        [pscustomobject]$d
    })
    $o = [ordered]@{
        empresa        = $emp.empresa
        setor          = $emp.setor
        tier           = $emp.tier
        ews_score      = $emp.ews_score
        cvm_novos      = $emp.cvm_novos
        cvm_documentos = $docs
    }
    # contexto historico: expandido para emissores ja em situacao critica (evita re-descoberta via busca paga);
    # nunca omitido por completo - lotes Haiku (Ultra) recebem versao reduzida
    $ctx = '' + $emp.contexto_historico
    if ($ctx) {
        $isCritico = ($emp.ews_score -ge $SonnetEwsMin) -or ($ctx -match 'REX|RJ|recupera|default|CRITICO')
        $max = if ($isCritico) { 400 } elseif ($Ultra) { 200 } else { 120 }
        if ($ctx.Length -gt $max) { $ctx = $ctx.Substring(0, $max) }
        $o['contexto_historico'] = $ctx
    }
    return $o
}

function Invoke-WorkerJsonUtf8 {
    # Worker responde application/json SEM charset; Windows PowerShell 5.1 decodificaria a
    # resposta como ISO-8859-1, corrompendo acentos em memoria (Raizen -> "RaA*zen", match
    # do plano falha e CRITICO real vira NENHUM - P0 nota 43, 2026-07-07). Le bytes crus e
    # decoda UTF-8 explicitamente; envia body como bytes UTF-8 pelo mesmo motivo.
    param([string]$Uri, $BodyObj, [int]$TimeoutSec = 120, [int]$Depth = 16)
    $params = @{ Uri = $Uri; Method = 'Post'; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    $params.ContentType = 'application/json; charset=utf-8'
    $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($BodyObj | ConvertTo-Json -Depth $Depth -Compress))
    $resp = Invoke-WebRequest @params
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

function Submit-Analise($key, $empresa, $setor, $resultado, [string]$provedor = 'claude-sonnet-routine') {
    $body = @{
        action = 'receber_analise'; routine_key = $key; empresa = $empresa; setor = $setor
        _matinal = $false; provedor = $provedor; resultado = $resultado
    }
    $json = $body | ConvertTo-Json -Depth 16 -Compress
    return Invoke-RestMethod -Uri $WorkerUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $json -TimeoutSec 120
}

function Submit-SkipEmissor($key, $emp) {
    $motivos = if ($emp.motivos) { ($emp.motivos -join ', ') } else { 'sem_delta_24h' }
    $cvmResumo = Get-CvmResumo $emp.cvm_documentos
    $resultado = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; sem_eventos = $true
        cobertura_nota = "Tier SKIP. CVM: $cvmResumo. $($emp.cvm_novos) novos. Motivos: $motivos."
        fontes_consultadas = @([ordered]@{ rodada = '0'; query = 'Worker plano'; resultado = $cvmResumo })
        eventos = @(); _tier = 'SKIP'; _rotina_v2 = $true
    }
    $resp = Submit-Analise $key $emp.empresa $emp.setor $resultado
    if ($resp.ok -ne $true) {
        Start-Sleep -Seconds $PauseSec
        $resp = Submit-Analise $key $emp.empresa $emp.setor $resultado
    }
    return $resp
}

function Submit-CapDeferred($key, $emp) {
    $resultado = [ordered]@{
        empresa = $emp.empresa; setor = $emp.setor; sem_eventos = $true
        cobertura_nota = "Tier $($emp.tier). Cap hard ${TokenHardCap} tokens - ledger minimo. EWS=$($emp.ews_score). Priorizar amanha."
        fontes_consultadas = @([ordered]@{ rodada = '0'; query = 'token_cap'; resultado = 'deferred' })
        eventos = @(); _tier = $emp.tier; _rotina_v2 = $true; _token_cap_deferred = $true
    }
    return Submit-Analise $key $emp.empresa $emp.setor $resultado 'claude-cap-deferred'
}

function Build-LlmQueues($analyzeList) {
    $sonnet = @()
    $haiku = @()
    foreach ($emp in @($analyzeList)) {
        $high = ($emp.tier -eq 'FULL') -and (($emp.ews_score -ge $SonnetEwsMin) -or ($emp.cvm_novos -gt 0))
        if ($high) { $sonnet += $emp } else { $haiku += $emp }
    }
    return @{
        Sonnet = @($sonnet | Sort-Object -Property ews_score, cvm_novos -Descending)
        Haiku  = $haiku
    }
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

function Invoke-ClaudeBatch([string]$promptPath, [string]$Model) {
    # Flags de economia (medidas 2026-07-03): boot 33.9k -> ~13.6k tokens/invocacao.
    # --tools restringe schemas built-in (maior corte); MCP off; sem plugins/hooks de usuario;
    # --exclude-dynamic-system-prompt-sections estabiliza o prefixo p/ cache ephemeral_1h entre lotes.
    # stderr vai para arquivo proprio - nunca misturar no stdout (quebrava o parse do envelope JSON).
    # ErrorActionPreference='Stop' e' global (herdado do script); sem isso, QUALQUER linha em stderr
    # do binario nativo 'claude' (avisos/deprecations, comuns mesmo com exit 0) vira excecao terminante
    # que mata a rotina inteira a partir deste lote. Isolar localmente com Continue.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # stderr por-PID (nao date-tagged): duas instancias no mesmo dia (Task nativo 18:00 + scheduled-task
    # Claude Code ~18:06) compartilhavam noturno_stderr_<data>.txt; o 2>> da 2a instancia tomava sharing
    # violation em TODO lote -> exceao terminante -> 37 submits de cobertura minima 0 buscas/0 tokens
    # (incidente 2026-07-06). Sufixo _$PID isola o handle por processo. Defesa complementar ao mutex.
    $stderrFile = Join-Path $LogDir ('noturno_stderr_' + $DateTag + '_' + $PID + '.txt')
    $raw = $null; $exitCode = 1
    try {
        # Reforca UTF8 a cada lote (defesa contra reset de codepage mid-run, achado 08/07:
        # mojibake reapareceu num lote isolado mesmo com o fix global no boot do script).
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        # Auth resolvida no boot por Initialize-VixClaudeAuth: assinatura primeiro, chave paga
        # so se o OAuth nao responder. Reaplicada a cada lote porque o ambiente do processo
        # pode ter sido mexido no meio. Fixa a base URL oficial junto (incidente 73).
        Set-VixClaudeAuthEnv
        # RETRY1 (2026-07-27): retry com backoff + fallback Haiku na ultima tentativa.
        # DeepSeek API (ANTHROPIC_BASE_URL) congestiona em horario de pico Chines (03:00-10:00 BRT),
        # causando exit=1 silencioso sem stderr. Backoff progressivo (0s/30s/60s) fura rate-limit
        # transitorio. Ultima tentativa troca Sonnet->Haiku (payload menor, menos tokens, maior
        # chance de passar em API congestionada).
        $retryModels = @($Model)
        if ($Model -ne 'claude-haiku-4-5-20251001') { $retryModels += 'claude-haiku-4-5-20251001' }
        $retryDelays = @(0, 30, 60)
        $retryLog = @()
        for ($attempt = 0; $attempt -lt $retryDelays.Count; $attempt++) {
            if ($attempt -gt 0) {
                $delay = $retryDelays[$attempt]
                Write-Log ('RETRY: tentativa ' + ($attempt+1) + '/' + $retryDelays.Count + ' aguardando ' + $delay + 's (batch morreu na anterior)')
                Start-Sleep -Seconds $delay
            }
            $tryModel = if ($attempt -eq $retryDelays.Count - 1 -and $retryModels.Count -gt 1) { $retryModels[1] } else { $retryModels[0] }
            if ($tryModel -ne $Model) { Write-Log ('RETRY: fallback ' + $Model + '->' + $tryModel + ' (ultima tentativa)') }
            $raw = Get-Content $promptPath -Raw -Encoding UTF8 | claude -p `
                --model $tryModel `
                --permission-mode bypassPermissions `
                --output-format json `
                --tools 'WebSearch,WebFetch' `
                --strict-mcp-config --mcp-config $McpConfigFile `
                --setting-sources project `
                --disable-slash-commands `
                --no-session-persistence `
                --exclude-dynamic-system-prompt-sections 2>>$stderrFile
            $exitCode = $LASTEXITCODE
            $retryLog += ('t' + ($attempt+1) + ':exit=' + $exitCode + ':model=' + $tryModel)
            if ($exitCode -eq 0) { break }
            # O OAuth pode vencer no meio de uma rotina longa. Se a falha foi de credencial,
            # escala para a chave paga agora, e a proxima tentativa ja sai no modo novo. Sem
            # isto todos os lotes seguintes morriam, que foi o comportamento de 29-30/07.
            $saidaFalha = ('' + $raw)
            if (Test-Path $stderrFile) { $saidaFalha += (' ' + (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue)) }
            if (Invoke-VixClaudeAuthEscalate $saidaFalha) { $retryLog += 'auth:escalado-para-api' }
        }
        if ($retryLog.Count -gt 1) { Write-Log ('RETRY log: ' + ($retryLog -join ' ')) }
    } catch {
        Write-Log ('AVISO: excecao ao invocar claude -p (' + $_.Exception.Message + ') - lote marcado como falho')
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    $textOut = @($raw)
    $tokens = -1   # -1 = DESCONHECIDO (parse falhou); nunca reportar 0 falso
    try {
        $jsonLine = @($raw) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
        if ($jsonLine) {
            $json = $jsonLine | ConvertFrom-Json
            if ($null -ne $json.result) { $textOut = @(('' + $json.result) -split "`n") }
            if ($json.usage) {
                # cache_read excluido da soma (2026-07-14): mesmo fix do run_vixradar_matinal_claude.ps1
                # (releitura de contexto cobrada a 0.1x, nao trabalho novo; inflava o acumulado contra
                # o hard cap de 700k sem refletir custo ou trabalho real).
                $tokens = [int]$json.usage.input_tokens + [int]$json.usage.output_tokens `
                    + [int]$json.usage.cache_creation_input_tokens
            }
        }
    } catch {
        Write-Log ('AVISO: parse do envelope JSON falhou (' + $_.Exception.Message + ') - tokens DESCONHECIDO')
    }
    $authFail = Test-ClaudeAuthFailure $textOut
    return @{ Output = $textOut; ExitCode = $exitCode; Tokens = $tokens; AuthFailure = $authFail }
}

function Get-NomeNormalizado([string]$s) {
    # Remove diacriticos (Iguá -> Igua) para o match nao quebrar por acentuacao; hashtable ja e case-insensitive.
    $norm = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().Trim()
}

function Get-ParsedResultados($outputLines) {
    # Protocolo do lote: RESULTADO|<empresa>|<json compacto> por emissor + LOTE_RESUMO|buscas=N
    # Chave do map e' o nome normalizado (sem acento) - o match com o plano tambem normaliza (ver Get-ResultadoEmissor).
    $map = @{}
    $buscas = -1
    foreach ($line in @($outputLines)) {
        $t = ('' + $line).Trim()
        if ($t -match '^RESULTADO\|([^|]+)\|(\{.*\})\s*$') {
            $empName = Get-NomeNormalizado ($Matches[1].Trim())
            try {
                $obj = $Matches[2] | ConvertFrom-Json
                if ($obj) { $map[$empName] = $obj }
            } catch {
                Write-Log ('AVISO: RESULTADO com JSON invalido para ' + $empName)
            }
        } elseif ($t -match '^LOTE_RESUMO\|buscas=(\d+)') {
            $buscas = [int]$Matches[1]
        } elseif ($t -match '^ANOTA\|(.+)$') {
            Write-Log ('ANOTA: ' + $Matches[1])
        }
    }
    return @{ Map = $map; Buscas = $buscas }
}

function Get-ResultadoEmissor($parsedMap, [string]$empresaPlano) {
    return $parsedMap[(Get-NomeNormalizado $empresaPlano)]
}

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
    Get-ChildItem $LogDir -Filter ('noturno_*_' + $tag + '.txt') -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'noturno_stderr_*' } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $LogDir ('noturno_plano_' + $tag + '.json')) -Force -ErrorAction SilentlyContinue
}

foreach ($f in @($HaikuSkill, $SonnetSkill)) {
    if (-not (Test-Path $f)) { Write-Log ('ERRO: skill ausente ' + $f); exit 1 }
}

# Mutex global: impede execucao concorrente da noturna. O Task Scheduler nativo (VIXRadar-Noturno, 18:00)
# e a scheduled-task Claude Code (vixradar-noturno, ~18:06) disparam o MESMO PS1; sem exclusao mutua, a 2a
# instancia colidia com a 1a e submetia cobertura minima (incidente 2026-07-06). WaitOne(0) = nao-bloqueante:
# se outra instancia ja detem o mutex, esta sai limpa em 0 tokens (o SO libera o mutex ao encerrar o processo).
$__noturnoMutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-noturno-v2')
if (-not $__noturnoMutex.WaitOne(0)) {
    Write-Log 'ABORT: outra instancia da noturna ja esta em execucao (mutex ocupado) - saindo limpo em 0 tokens'
    exit 0
}

# Lock de arquivo da sessao Claude Desktop (scheduled-task vixradar-noturno, SKILL.md). O mutex
# acima so enxerga outra copia DESTE .ps1; a sessao Claude Desktop roda inline (chama o Worker
# direto via PowerShell/curl) e nunca aciona esse mutex. Incidente 2026-08-08: o Cowork chamou
# este .ps1 enquanto a sessao Claude Desktop estava no meio da varredura; esta instancia venceu
# a corrida, leu fonte mais velha (fora da janela) e sobrescreveu 3 emissores (Rumo, Bradesco,
# Tupy) ja analisados corretamente pela sessao, corrigido manualmente depois. Este check fecha
# essa direcao (sessao ja rodando -> este .ps1 desiste). A direcao inversa (este .ps1 ja rodando
# -> sessao desiste) fica a cargo do Passo 0 do SKILL.md, que checa o mutex acima antes de comecar.
$__skillLockFile = Join-Path $LogDir ('vixradar-noturno_' + $DateTag + '.lock')
if (Test-Path $__skillLockFile) {
    $__lockAgeMin = ((Get-Date) - (Get-Item $__skillLockFile).LastWriteTime).TotalMinutes
    if ($__lockAgeMin -lt 180) {
        Write-Log ('ABORT: lock da sessao Claude Desktop ativo ha ' + [math]::Round($__lockAgeMin,1) + ' min - saindo limpo em 0 tokens')
        $__noturnoMutex.ReleaseMutex()
        exit 0
    } else {
        Write-Log ('AVISO: lock da sessao Claude Desktop encontrado com ' + [math]::Round($__lockAgeMin/60,1) + 'h (>3h, tratado como abandonado) - seguindo')
    }
}

Write-Log "INICIO: noturno meta=${TokenTarget} hard=${TokenHardCap} haiku+sonnet(EWS>=$SonnetEwsMin)"
$inicioIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
# Shadow DeepSeek (piloto): off por default. Nunca grava no Worker.
# Sem a lib carregada nao ha shadow, e a funcao de teste nem existe para ser chamada.
$ShadowDeepSeekOn = $false
if ($ShadowLibOk) { $ShadowDeepSeekOn = Test-VixNoturnoShadowDeepSeekEnabled -SwitchOn:$ShadowDeepSeek }
$ShadowDeepSeekKey = $null
$statsShadow = @{ n = 0; parse_ok = 0; api_fail = 0; diverge = 0; critico_div = 0; tokens = 0 }
if ($ShadowDeepSeekOn) {
    $ShadowDeepSeekKey = Get-VixDeepSeekApiKey
    if (-not $ShadowDeepSeekKey) {
        Write-Log 'SHADOW: pedido ON mas DEEPSEEK_API_KEY / VIXRADAR_DEEPSEEK_API_KEY ausente - shadow desligado nesta corrida'
        $ShadowDeepSeekOn = $false
    } else {
        Write-Log ('SHADOW: DeepSeek ON (somente comparacao, submit=false) jsonl=' + $ShadowJsonl)
    }
} else {
    Write-Log 'SHADOW: DeepSeek OFF (use -ShadowDeepSeek ou VIXRADAR_NOTURNO_SHADOW_DEEPSEEK=1)'
}
# Sonda a assinatura uma vez e registra no log qual credencial serviu a execucao. A linha
# importa para proveniencia: em 30/07 o log carimbava Claude sem que isso fosse verificavel.
Initialize-VixClaudeAuth -McpConfigFile $McpConfigFile | Out-Null
if ((Get-VixClaudeAuthModo) -eq 'nenhum') {
    Write-Log 'ERRO FATAL: nenhuma credencial Claude disponivel (assinatura expirada, token longevo ausente, chave paga invalida ou ausente). Abortando antes do primeiro lote.'
    Write-Log 'ERRO FATAL: rode `claude setup-token` para token longevo ou defina VIXRADAR_ANTHROPIC_API_KEY com chave sk-ant-valida.'
    exit 5
}
$ambientViolacao = Test-VixClaudeAmbienteLimpo
if ($ambientViolacao) {
    Write-Log "AVISO: ambiente contaminado detectado — $ambientViolacao"
    Write-Log 'AVISO: variavel de ambiente ou settings.json aponta para agregador/modelo nao-Claude.'
    Write-Log 'AVISO: as variaveis ANTHROPIC_BASE_URL, ANTHROPIC_MODEL e ANTHROPIC_AUTH_TOKEN serao sobrescritas com valores oficiais da API Anthropic.'
    Write-Log 'AVISO: a rotina continua, mas o settings.json deve ser corrigido manualmente.'
    # Sobrescreve o que vier do settings.json/registry com valores Anthropic oficiais.
    # Remove-Item elimina do bloco de ambiente; [Environment]::SetEnvironmentVariable
    # blinda contra leitura de registro pelo binario nativo claude.exe.
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
    $env:CLAUDE_CODE_SUBAGENT_MODEL = 'claude-sonnet-5'
    Write-Log 'RECUPERACAO: env vars Anthropic injetadas para neutralizar contaminacao do settings.json.'
}
if (-not (Test-VixWebSearchProbe $McpConfigFile)) {
    Write-Log 'ERRO FATAL: probe WebSearch falhou - ferramenta de busca indisponivel.'
    Write-Log 'ERRO FATAL: verificar modelo configurado e conectividade. A execucao foi abortada antes do primeiro submit.'
    exit 7
}
Invoke-Cleanup

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Log 'ERRO: claude.exe ausente'
    exit 2
}

try {
    $health = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 30
    # So bloqueia por dependencia real desta rotina (KV + telemetria). NAO bloquear por 'ok' agregado:
    # 'ok' inclui verificador_ok/Resend, que nao tem relacao com busca web + submit via receber_analise
    # (achado 2026-07-04: rotina de 03/07 abortou 100% dos 103 emissores por causa disso, ok:false so por
    # saldo Anthropic insuficiente no verificador - nada a ver com o trabalho desta rotina).
    if (-not $health.bindings.kv -or -not $health.bindings.telemetria) {
        Write-Log ('ERRO: health - kv=' + $health.bindings.kv + ' telemetria=' + $health.bindings.telemetria)
        exit 3
    }
    Write-Log ('Health ' + $health.versao + ' ok=' + $health.ok + ' verificador_ok=' + $health.verificador_ok + ' (nao bloqueante para esta rotina)')
    $versaoWorker = $health.versao
} catch {
    Write-Log ('ERRO: health ' + $_.Exception.Message)
    exit 3
}

try { $routineKey = Get-RoutineKey } catch { Write-Log $_.Exception.Message; exit 4 }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$stats = @{
    skip_ok = 0; skip_fail = 0; batch_ok = 0; batch_fail = 0; silent_fail = 0
    tokens_total = 0; tokens_over_target = $false; tokens_hard_hit = $false; deferred = 0
    batches_run = 0; sonnet_count = 0; haiku_count = 0
    submit_ok = 0; submit_fail = 0; buscas_total = 0
    criticos = New-Object System.Collections.Generic.List[string]
}
$pendingDeferred = New-Object System.Collections.Generic.List[object]
$exitCode = 0
$batchSeq = 0

Push-Location $ProjectRoot
try {
    $plano = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_plano_rotina'; routine_key = $routineKey; modo = 'noturno' } -TimeoutSec 180
    if ($plano.ok -ne $true -or $plano.total -ne 103) { Write-Log 'ERRO: plano'; exit 5 }

    @{
        data = $plano.data; tiers = $plano.contagem_tiers; buscas = $plano.buscas_estimadas
        emissores = @($plano.emissores | ForEach-Object { @{ e = $_.empresa; t = $_.tier; ews = $_.ews_score } })
    } | ConvertTo-Json -Compress | Set-Content (Join-Path $LogDir ('noturno_plano_' + $DateTag + '.json')) -Encoding UTF8

    Write-Log ('Plano ' + ($plano.contagem_tiers | ConvertTo-Json -Compress))

    # v4.9.151: idempotencia - se a rotina reiniciou, nao reprocessar emissores ja feitos neste dia.
    # Oi e Oncoclínicas foram processadas 2x em 09/07 (~180k tokens desperdicados) por falta disto.
    # -Force ignora a trava: util apos execucao contaminada.
    $jaProcessados = @{}
    if (-not $Force -and (Test-Path $LogFile)) {
        $linhasOk = Get-Content $LogFile -Encoding UTF8 | Where-Object { $_ -match '^[\d-]+ [\d:]+ OK\|([^|]+)\|' }
        foreach ($linha in $linhasOk) {
            if ($linha -match 'OK\|([^|]+)\|') {
                $jaProcessados[(Get-NomeNormalizado $Matches[1])] = $true
            }
        }
        # tambem pular emissores que ja foram SKIP (Submit-SkipEmissor produz OK| no log)
        $linhasSkip = Get-Content $LogFile -Encoding UTF8 | Where-Object { $_ -match 'SKIP \d+ via PS1' }
        if ($linhasSkip) {
            # SKIP ja foi feito para todos da rodada anterior - pular da lista
            $skipsAnteriores = $linhasOk | Where-Object { $_ -match 'SKIP\|' }
            foreach ($linha in $skipsAnteriores) {
                if ($linha -match 'OK\|([^|]+)\|') {
                    $jaProcessados[(Get-NomeNormalizado $Matches[1])] = $true
                }
            }
        }
        if ($jaProcessados.Count -gt 0) {
            Write-Log ('Idempotencia: ' + $jaProcessados.Count + ' emissores ja processados hoje, pulando')
        }
    } elseif ($Force) {
        Write-Log 'AVISO: -Force ativo. Trava de idempotencia ignorada. Todos os emissores serao reprocessados.'
    }

    $janIni = '' + $plano.emissores[0].janela_inicio
    $janFim = '' + $plano.emissores[0].janela_fim

    $skipQueue = @($plano.emissores | Where-Object { $_.tier -eq 'SKIP' -and -not $jaProcessados.ContainsKey((Get-NomeNormalizado $_.empresa)) })
    $skipN = 0
    foreach ($emp in $skipQueue) {
        $skipN++
        try {
            $r = Submit-SkipEmissor $routineKey $emp
            if ($r.ok) { $stats.skip_ok++ } else { $stats.skip_fail++ }
        } catch { $stats.skip_fail++ }
        if ($skipN % 20 -eq 0 -or $skipN -eq $skipQueue.Count) {
            Write-Log ("SKIP progresso: $skipN/$($skipQueue.Count) (ok=$($stats.skip_ok) fail=$($stats.skip_fail))")
        }
        Start-Sleep -Seconds $PauseSec
    }
    Write-Log ('SKIP ' + $stats.skip_ok + ' via PS1')

    $analyzeList = @($plano.emissores | Where-Object { $_.tier -ne 'SKIP' -and -not $jaProcessados.ContainsKey((Get-NomeNormalizado $_.empresa)) })
    $queues = Build-LlmQueues $analyzeList
    Write-Log ('Filas: sonnet=' + $queues.Sonnet.Count + ' haiku=' + $queues.Haiku.Count)

    # CAPRESERVA1: reserva de orcamento da fila APROFUNDADA, calculada antes de gastar
    # o primeiro token. Vale o que a fila realmente precisa, limitado a fracao do hard
    # cap, para nao acontecer o inverso (aprofundada gigante zerando a rapida).
    $sonnetLotesPrev = 0
    if ($queues.Sonnet.Count -gt 0) { $sonnetLotesPrev = [Math]::Ceiling($queues.Sonnet.Count / $SonnetChunk) }
    $reservaNecessaria = ($sonnetLotesPrev * $TokenBootOverhead) + ($queues.Sonnet.Count * $TokenPerEmissorSonnet)
    $reservaTeto = [int]([Math]::Floor($TokenHardCap * $TokenReservaFracaoAprofundada))
    $ReservaAprofundada = $reservaNecessaria
    if ($ReservaAprofundada -gt $reservaTeto) { $ReservaAprofundada = $reservaTeto }
    $CapFilaRapida = $TokenHardCap - $ReservaAprofundada
    Write-Log ('RESERVA: aprofundada=' + $ReservaAprofundada + ' (necessario=' + $reservaNecessaria +
        ' teto=' + $reservaTeto + ') cap_fila_rapida=' + $CapFilaRapida + ' hard=' + $TokenHardCap)
    if ($reservaNecessaria -gt $reservaTeto) {
        Write-Log ('AVISO: fila aprofundada precisa de ' + $reservaNecessaria + ' e a reserva foi limitada a ' +
            $reservaTeto + '. Parte da aprofundada vai ser deferida mesmo com a rapida contida. Rever $TokenHardCap.')
    }

    # v4.9.151: Haiku primeiro garante cobertura total (LIGHT/AUDIT/FULL resto).
    # Sonnet depois com orcamento restante - se o hard cap estourar nos Sonnet,
    # pelo menos a cobertura base ja foi feita. Ordem anterior (Sonnet primeiro)
    # resultou em haiku=0 na rotina de 09/07 (17 emissores descobertos).
    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($chunk in (Split-IntoChunks $queues.Haiku $HaikuChunk)) {
        $jobs.Add([ordered]@{ Name = 'haiku'; Model = $ModelHaiku; Chunk = @($chunk); Skill = $HaikuSkill; Ultra = $true; Provedor = 'claude-haiku-routine' })
    }
    foreach ($chunk in (Split-IntoChunks $queues.Sonnet $SonnetChunk)) {
        $jobs.Add([ordered]@{ Name = 'sonnet'; Model = $ModelSonnet; Chunk = @($chunk); Skill = $SonnetSkill; Ultra = $false; Provedor = 'claude-sonnet-routine' })
    }

    # Guarda de regressao (2026-07-13): Split-IntoChunks ja teve bug de array-unwrapping do
    # PowerShell (return $chunks sem virgula unaria) que devolvia 1 emissor por lote em vez de
    # agrupados quando a fila cabia em 1 chunk - sintoma silencioso, so visivel lendo o log com
    # atencao (numero de lotes = numero de emissores). Corrigido (return ,$chunks); esta checagem
    # denuncia qualquer regressao futura em vez de deixar degradar silenciosamente de novo.
    $haikuJobsCount = @($jobs | Where-Object { $_.Name -eq 'haiku' }).Count
    $sonnetJobsCount = @($jobs | Where-Object { $_.Name -eq 'sonnet' }).Count
    $haikuEsperado = if ($queues.Haiku.Count -eq 0) { 0 } else { [Math]::Ceiling($queues.Haiku.Count / $HaikuChunk) }
    $sonnetEsperado = if ($queues.Sonnet.Count -eq 0) { 0 } else { [Math]::Ceiling($queues.Sonnet.Count / $SonnetChunk) }
    if ($haikuJobsCount -ne $haikuEsperado -or $sonnetJobsCount -ne $sonnetEsperado) {
        Write-Log ("AVISO CRITICO: agrupamento de lotes incorreto - haiku lotes=$haikuJobsCount esperado=$haikuEsperado, sonnet lotes=$sonnetJobsCount esperado=$sonnetEsperado (fila haiku=$($queues.Haiku.Count) sonnet=$($queues.Sonnet.Count)). Possivel regressao de Split-IntoChunks - revisar antes de continuar.")
    }

    $ji = 0
    $abortAfterSubmit = $false   # RETRYDROP1: sinaliza break apos submit (preserva resultados)
    foreach ($job in $jobs) {
        $ji++

        # v4.9.151: estimar tokens ANTES de iniciar o lote.
        # Hard cap checado pre-lote evita ultrapassar o limite durante o processamento
        # (09/07: acum=635k, lote Light consumiu +141k e estourou o cap em 76k).
        #
        # Modelo aditivo (fix 2026-07-14): o custo NAO e' linear em n. Ha um piso fixo de boot por
        # invocacao do claude (~13,6k - ver Invoke-ClaudeBatch) + custo por emissor. A formula linear
        # anterior (n * 40k Sonnet / n * 8k Haiku, calibrada em 09/07) superestimava 3,1x e punia
        # lotes grandes: em 14/07 15h ela deferiu o lote sonnet-8 INTEIRO (10 emissores, toda a fila
        # EWS>=38 - o segmento de maior risco) com acum=339.304 + est=400.000 >= 700.000. O consumo
        # real desses mesmos 10 emissores, medido as 18h, foi 127.015 (12,7k/emissor): teria fechado
        # em ~466k, abaixo ate' da meta. So' nao virou gap de cobertura porque a 2a execucao do dia
        # (idempotente) os processou. Coeficientes calibrados com os lotes reais de 14/07.
        $unit = if ($job.Name -eq 'sonnet') { $TokenPerEmissorSonnet } else { $TokenPerEmissorHaiku }
        $estLote = $TokenBootOverhead + ($job.Chunk.Count * $unit)

        # CAPRESERVA1: a fila rapida (haiku) bate no cap reduzido, que protege a reserva
        # da aprofundada. A aprofundada (sonnet) segue batendo no hard cap cheio.
        $capDoJob = $TokenHardCap
        if ($job.Name -ne 'sonnet') { $capDoJob = $CapFilaRapida }

        if (($stats.tokens_total + $estLote) -ge $capDoJob) {
            $stats.tokens_hard_hit = $true
            foreach ($e in $job.Chunk) { $pendingDeferred.Add($e) }
            $qualCap = 'HARD CAP'
            if ($job.Name -ne 'sonnet') { $qualCap = 'CAP FILA RAPIDA (reserva da aprofundada preservada)' }
            Write-Log ($qualCap + ' pre-lote: acum=' + $stats.tokens_total + ' est=' + $estLote + ' >= ' + $capDoJob + ' - lote ' + $job.Name + '-' + $ji + ' deferred (' + $job.Chunk.Count + ' emissores)')
            continue
        }

        # Aviso de meta: antes de iniciar o lote que ultrapassara a meta
        if (($stats.tokens_total + $estLote) -ge $TokenTarget -and -not $stats.tokens_over_target) {
            $stats.tokens_over_target = $true
            Write-Log ('AVISO: meta ' + $TokenTarget + ' sera ultrapassada neste lote (acum=' + $stats.tokens_total + ' est=' + $estLote + ') - continua ate hard ' + $TokenHardCap)
        }

        $batchSeq++
        $label = $job.Name + '-' + $ji
        $prompt = New-BatchPrompt $job.Chunk $label $job.Model $job.Skill $janIni $janFim -Ultra:$job.Ultra
        $promptPath = Join-Path $LogDir ('noturno_' + $label + '_' + $DateTag + '.txt')
        Set-Content $promptPath -Value $prompt -Encoding UTF8

        Write-Log ('Lote ' + $label + ' [' + $job.Model + ']: ' + (($job.Chunk | ForEach-Object { $_.empresa }) -join ', '))
        $result = Invoke-ClaudeBatch $promptPath $job.Model
        $stats.batches_run++
        if ($job.Name -eq 'sonnet') { $stats.sonnet_count += $job.Chunk.Count } else { $stats.haiku_count += $job.Chunk.Count }

        if ($result.AuthFailure) {
            Write-Log ('ERRO CRITICO: claude CLI nao autenticado (sessao OAuth expirada/deslogada) no lote ' + $label + ' - reautentique com "claude /login" antes do proximo disparo. Abortando lotes restantes para nao degradar em cobertura minima silenciosa (' + ($jobs.Count - $ji) + ' lote(s) restante(s) NAO processado(s)).')
            # AUTHWEEK1 (2026-08-14): avisa o admin no momento do abort (limite semanal,
            # OAuth vencido etc). O Monitor-Tasks nao enxerga esta rotina.
            $null = Send-VixRoutineAlert -Rotina 'noturno' -Motivo 'claude CLI nao autenticado ou limite semanal atingido - lotes restantes abortados' -RoutineKey $routineKey
            $exitCode = 7
            $stats.batch_fail++
            Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
            break
        }

        if ($result.Output) { $result.Output | ForEach-Object { Write-Log ('OUT: ' + $_) } }

        $bt = $result.Tokens
        if ($bt -gt 0) { $stats.tokens_total += $bt; Write-Log ('Tokens lote=' + $bt + ' acum=' + $stats.tokens_total) }
        else { Write-Log 'Tokens lote=DESCONHECIDO (parse falhou) - acum inalterado' }

        $parsed = Get-ParsedResultados $result.Output
        $buscasLote = $parsed.Buscas

        # retry parcial: reprocessa somente emissores sem linha RESULTADO valida
        $missing = @($job.Chunk | Where-Object { -not (Get-ResultadoEmissor $parsed.Map $_.empresa) })
        if ($missing.Count -gt 0) {
            Write-Log ('WARN: ' + $missing.Count + ' sem RESULTADO no lote ' + $label + ' - retry parcial: ' + (($missing | ForEach-Object { $_.empresa }) -join ', '))
            $retryLabel = $label + '-retry'
            $retryPrompt = New-BatchPrompt $missing $retryLabel $job.Model $job.Skill $janIni $janFim -Ultra:$job.Ultra
            $retryPath = Join-Path $LogDir ('noturno_' + $retryLabel + '_' + $DateTag + '.txt')
            Set-Content $retryPath -Value $retryPrompt -Encoding UTF8
            $retryRes = Invoke-ClaudeBatch $retryPath $job.Model
            if ($retryRes.AuthFailure) {
                # RETRYDROP1 (fix 2026-07-13): break imediato descartava resultados ja parseados
                # do lote principal em $parsed.Map (emissores com RESULTADO valido). Agora:
                # 1. NAO faz merge do retry (que falhou) no $parsed.Map
                # 2. Sinaliza abort apos submit (preserva resultados do lote principal)
                # 3. Emissores faltantes recebem fallback "Falha de parse" no bloco de submit
                Write-Log ('ERRO CRITICO: claude CLI nao autenticado (sessao OAuth expirada/deslogada) no retry do lote ' + $label + ' - ' + $missing.Count + ' emissores faltantes receberao fallback. Resultados ja processados (' + ($job.Chunk.Count - $missing.Count) + ' emissor(es)) serao submetidos normalmente. Lotes restantes NAO serao processados.')
                $exitCode = 7
                $stats.batch_fail++
                $abortAfterSubmit = $true
                Remove-Item $retryPath -Force -ErrorAction SilentlyContinue
                # NAO da break - cai para o bloco de submit com $parsed.Map preservado
            } else {
                if ($retryRes.Output) { $retryRes.Output | ForEach-Object { Write-Log ('OUT-RETRY: ' + $_) } }
                if ($retryRes.Tokens -gt 0) { $stats.tokens_total += $retryRes.Tokens }
                $retryParsed = Get-ParsedResultados $retryRes.Output
                foreach ($k in @($retryParsed.Map.Keys)) { $parsed.Map[$k] = $retryParsed.Map[$k] }
                if ($retryParsed.Buscas -gt 0) {
                    if ($buscasLote -lt 0) { $buscasLote = 0 }
                    $buscasLote += $retryParsed.Buscas
                }
                Remove-Item $retryPath -Force -ErrorAction SilentlyContinue
            }
        }

        # silent_fail: zero RESULTADO| parseados do output do modelo (cobre falhas alem da regex de
        # auth - ex.: prompt truncado, modelo devolveu texto em vez de RESULTADO|, falha nova do
        # claude CLI que nao esta na lista de auth). Sem isto, todos os emissores do lote caem no
        # fallback "Falha de parse do agente apos retry", submit_OK incrementa, metrics e exit code
        # ficam limpos, e a rotina sai como sucesso (achado 2026-07-08 - mesmo incidente do silent_fail
        # no matinal, via protocolo diferente: aqui a falha e mascarada via fallback, la via OK|).
        $parsedCount = 0
        foreach ($emp in $job.Chunk) { if (Get-ResultadoEmissor $parsed.Map $emp.empresa) { $parsedCount++ } }
        if ($parsedCount -eq 0) {
            $stats.silent_fail++
            Write-Log ('ERRO: lote ' + $label + ' sem RESULTADO| - falha silenciosa (0/' + $job.Chunk.Count + ' emissores com analise real)')
        }

        # submit centralizado no PS1: schema garantido (resultado aninhado) + retry por emissor
        $loteOk = 0; $loteFail = 0; $loteCrit = 0
        $buscasReaisLote = 0
        $iAgudo = [char]0x00ED
        foreach ($emp in $job.Chunk) {
            $res = Get-ResultadoEmissor $parsed.Map $emp.empresa
            $buscasEfetivas = 0
            if (-not $res) {
                # fallback minimo: nunca deixar o emissor sem nenhum registro na semana por falha de parse do agente
                Write-Log ('WARN: ' + $emp.empresa + '|sem RESULTADO apos retry - submit minimo de cobertura pendente')
                $res = [pscustomobject]@{
                    classificacao_geral = 'NENHUM'; sem_eventos = $true
                    cobertura_nota = 'Falha de parse do agente apos retry - cobertura pendente, revisar manualmente.'
                    eventos = @(); fontes_consultadas = @()
                }
            } else {
                $fontes = @($res.fontes_consultadas)
                foreach ($f in $fontes) {
                    $r = '' + $f.resultado
                    if ($r -and $r -notmatch "indisponivel|indispon${iAgudo}vel|falha|erro|n[aã]o execut|timeout|^vazio$|^$") {
                        $buscasEfetivas++
                    }
                }
            }
            $buscasReaisLote += $buscasEfetivas
            $classif = '' + $res.classificacao_geral
            if (-not $classif) { $classif = if (@($res.eventos).Count -gt 0) { 'RELEVANTE' } else { 'ECO' } }
            if ($emp.tier -eq 'FULL' -and $buscasEfetivas -eq 0 -and $classif -ne 'CRITICO') {
                Write-Log ('WARN: ' + $emp.empresa + '|FULL com 0 buscas efetivas -> INCONCLUSIVO')
                $classif = 'INCONCLUSIVO'
                $res.sem_eventos = $true
                if (-not $res.cobertura_nota) { $res.cobertura_nota = 'Zero buscas efetivas - cobertura nao verificavel (falha de ferramenta ou modelo).' }
            }
            $subOk = $false; $nEv = 0
            try {
                $resp = Submit-Analise $routineKey $emp.empresa $emp.setor $res $job.Provedor
                if ($resp.ok -ne $true) {
                    Start-Sleep -Seconds $PauseSec
                    $resp = Submit-Analise $routineKey $emp.empresa $emp.setor $res $job.Provedor
                }
                $subOk = ($resp.ok -eq $true)
                if ($subOk) { $nEv = [int]$resp.n_eventos }
                elseif ($resp.erro) { Write-Log ('SUBMIT_ERRO|' + $emp.empresa + '|' + $resp.erro) }
            } catch {
                Write-Log ('SUBMIT_EXC|' + $emp.empresa + '|' + $_.Exception.Message)
            }
            Write-Log ('OK|' + $emp.empresa + '|' + $emp.tier + '|' + $classif + '|' + $nEv + '|' + $subOk)
            if ($subOk) { $loteOk++ } else { $loteFail++ }
            if ($classif -eq 'CRITICO') { $loteCrit++; $stats.criticos.Add($emp.empresa) }

            # Shadow DeepSeek: mesmas fontes do Claude; nunca submit. Pula fallback de parse.
            if ($ShadowDeepSeekOn -and $ShadowDeepSeekKey -and $res -and ('' + $res.cobertura_nota) -notmatch 'Falha de parse do agente') {
                try {
                    $filaShadow = if ($job.Name -eq 'sonnet') { 'aprofundada' } else { 'rapida' }
                    $shRec = Invoke-VixNoturnoShadowDeepSeekOne `
                        -ApiKey $ShadowDeepSeekKey `
                        -Emp $emp `
                        -ClaudeResultado $res `
                        -JanelaInicio $janIni `
                        -JanelaFim $janFim `
                        -Fila $filaShadow `
                        -JsonlPath $ShadowJsonl `
                        -BatchLabel $label
                    $statsShadow.n++
                    if ($shRec.parse_ok) { $statsShadow.parse_ok++ }
                    if ($shRec.status -eq 'api_fail') { $statsShadow.api_fail++ }
                    if ($shRec.compare -and $shRec.compare.diverge) { $statsShadow.diverge++ }
                    if ($shRec.compare -and $shRec.compare.critico_divergente) { $statsShadow.critico_div++ }
                    if ($shRec.usage -and $shRec.usage.total_tokens) { $statsShadow.tokens += [int]$shRec.usage.total_tokens }
                    $divTag = if ($shRec.compare -and $shRec.compare.diverge) { 'DIVERGE' } else { 'match' }
                    Write-Log ('SHADOW|' + $emp.empresa + '|' + $shRec.status + '|' + $shRec.claude_classif + ' vs ' + $shRec.deepseek_classif + '|' + $divTag)
                } catch {
                    Write-Log ('SHADOW_EXC|' + $emp.empresa + '|' + $_.Exception.Message)
                }
                Start-Sleep -Milliseconds 400
            }
        }
        $stats.submit_ok += $loteOk
        $stats.submit_fail += $loteFail
        if ($buscasReaisLote -gt 0 -or $buscasLote -lt 0) { $buscasLote = $buscasReaisLote }
        if ($buscasLote -ge 0) { $stats.buscas_total += $buscasLote }
        Write-Log ('LOTE_FECHADO|' + $label + '|ok=' + $loteOk + '|fail=' + $loteFail + '|buscas=' + $buscasLote + '|criticos=' + $loteCrit)

        if ($loteFail -gt 0) { $stats.batch_fail++ } else { $stats.batch_ok++ }
        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
        if ($abortAfterSubmit) {
            Write-Log 'ABORT: retry AuthFailure - resultados deste lote submetidos, lotes restantes NAO processados'
            break
        }
    }

    foreach ($emp in $pendingDeferred) {
        try {
            $r = Submit-CapDeferred $routineKey $emp
            if ($r.ok) { $stats.deferred++ }
        } catch { Write-Log ('Deferred fail: ' + $emp.empresa) }
        Start-Sleep -Seconds 1
    }

    $sw.Stop()
    # METRICSZERO1 (2026-07-24): skip idempotente nao pode sobrescrever metrics de execucao real
    # com submit_ok:0. Se nao houve processamento novo e o arquivo ja registra submit_ok>0, preserva.
    $gravarMetrics = $true
    if ($stats.submit_ok -eq 0 -and $stats.skip_ok -eq 0 -and (Test-Path $MetricsFile)) {
        try {
            $existente = Get-Content $MetricsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existente.submit_ok -gt 0) {
                Write-Log ('METRICSZERO1: metrics preservado (submit_ok=' + $existente.submit_ok + ', atual zerado por skip idempotente)')
                $gravarMetrics = $false
            }
        } catch {}
    }
    if ($gravarMetrics) {
        @{
            data = $DateTag; token_target = $TokenTarget; token_hard_cap = $TokenHardCap
            tokens_total_est = $stats.tokens_total; tokens_over_target = $stats.tokens_over_target
            tokens_hard_hit = $stats.tokens_hard_hit; skip_ok = $stats.skip_ok
            sonnet_llm = $stats.sonnet_count; haiku_llm = $stats.haiku_count; deferred = $stats.deferred
            submit_ok = $stats.submit_ok; submit_fail = $stats.submit_fail; buscas_total = $stats.buscas_total
            silent_fail = $stats.silent_fail
            batches = $stats.batches_run; criticos = @($stats.criticos); duracao_sec = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        } | ConvertTo-Json -Depth 5 | Set-Content $MetricsFile -Encoding UTF8
    }

    Write-Log ('FIM: tokens=' + $stats.tokens_total + ' meta=' + $TokenTarget + ' hard=' + $TokenHardCap +
        ' sonnet=' + $stats.sonnet_count + ' haiku=' + $stats.haiku_count +
        ' submit_ok=' + $stats.submit_ok + ' submit_fail=' + $stats.submit_fail + ' buscas=' + $stats.buscas_total +
        ' silent_fail=' + $stats.silent_fail +
        ' deferred=' + $stats.deferred + ' criticos=' + $stats.criticos.Count)

    $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $errosTotal = $stats.silent_fail + $stats.skip_fail + $stats.batch_fail + $stats.submit_fail
    $resultadoTxt = if ($errosTotal -gt 0) { 'PARCIAL' } else { 'OK' }
    Write-Log ('ROTINA_RESUMO|vixradar-noturno|local|' + $inicioIso + '|' + $fimIso + '|' + $resultadoTxt + '|' + $stats.submit_ok + '|' + $errosTotal + '|' + $stats.deferred + '|' + $versaoWorker)

    if ($ShadowDeepSeekOn -and $statsShadow.n -gt 0) {
        try {
            $sum = Write-VixNoturnoShadowSummary -JsonlPath $ShadowJsonl -SummaryPath $ShadowSummaryFile -DateTag $DateTag
            Write-Log ('SHADOW_FIM: n=' + $sum.n_comparacoes + ' parse_ok=' + $sum.parse_ok + ' diverge=' + $sum.classif_diverge +
                ' critico_div=' + $sum.critico_divergente + ' ds_tokens=' + $sum.tokens_deepseek_total +
                ' summary=' + $ShadowSummaryFile)
        } catch {
            Write-Log ('SHADOW_FIM: falha ao gravar summary - ' + $_.Exception.Message)
            Write-Log ('SHADOW_FIM: n=' + $statsShadow.n + ' parse_ok=' + $statsShadow.parse_ok + ' diverge=' + $statsShadow.diverge +
                ' critico_div=' + $statsShadow.critico_div + ' ds_tokens=' + $statsShadow.tokens)
        }
    }

    # Dreno da fila de verificação assíncrona pós-noturno (v4.9.150)
    # Problema: o cron 18:20 drena ANTES do noturno terminar (~19:00), deixando eventos
    # CRITICO novos presos na fila por 16h+ até o drain das 10:20 do dia seguinte.
    # Este dreno resolve o timing gap e garante verificador_ok:true ao fim da noite.
    if ($stats.submit_ok -gt 0) {
        $verifScript = Join-Path $ScriptsDir 'run_vixradar_verificacao_async.ps1'
        if (Test-Path $verifScript) {
            Write-Log 'POS-NOTURNO: drenando fila de verificacao...'
            try {
                $verifProc = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$verifScript`"" -PassThru -Wait -NoNewWindow
                Write-Log ('POS-NOTURNO: dreno concluido (exit=' + $verifProc.ExitCode + ')')
            } catch {
                Write-Log ('POS-NOTURNO: ERRO ao executar dreno - ' + $_.Exception.Message)
            }
        }
    }

    if ($stats.silent_fail -gt 0 -or $stats.skip_fail -gt 0 -or $stats.batch_fail -gt 0) { $exitCode = 6 }
} catch {
    $errMsg = 'ERRO FATAL: excecao nao tratada no bloco principal - ' + $_.Exception.Message
    $stackMsg = 'STACK: ' + $_.Exception.StackTrace
    Write-Safe $errMsg
    Write-Safe $stackMsg
    if ($_.Exception.InnerException) {
        $innerMsg = 'INNER: ' + $_.Exception.InnerException.Message
        Write-Safe $innerMsg
    }
    # Gravar no log via caminho seguro (sem Write-Log que pode falhar e mascarar o erro)
    try { Add-Content -Path $LogFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $errMsg) -Encoding UTF8 -ErrorAction Stop } catch {}
    try { Add-Content -Path $LogFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $stackMsg) -Encoding UTF8 -ErrorAction Stop } catch {}
    $exitCode = 1
} finally {
    Remove-BatchPrompts $DateTag
    Invoke-Cleanup -Aggressive
    Pop-Location
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
}

if ($exitCode -ne 0) { exit $exitCode }
