# run_vixradar_matinal_claude.ps1 - Matinal v2: SKIP PS1 + Haiku/Sonnet top 15, cap 120k tokens
param([switch]$Force)
# 'Continue' obrigatorio: regra do CLAUDE.md do VIX Radar. Com 'Stop' o script
# aborta antes do 'exit' e o Task Scheduler/Claude Desktop perde o codigo de saida.
$ErrorActionPreference = 'Continue'
# PIPE1: console oculto e best-effort; erros funcionais continuam terminantes.
# Mesma correcao de encoding do noturno (ver run_vixradar_noturno_claude.ps1) - stdout do
# binario 'claude' sem console interativo pode decodificar em ANSI/OEM e corromper nomes
# acentuados, quebrando o match de RESULTADO por emissor.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot    = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito'
$WorkerUrl      = 'https://api.vixradar.com'
$ScriptsDir     = Join-Path $ProjectRoot 'scripts'
$ScheduledTasks = 'C:\Users\User\.claude\scheduled-tasks'
$CleanupScript  = Join-Path $ProjectRoot 'scripts\cleanup-rotina-artifacts.ps1'
$HaikuSkill     = Join-Path $ScriptsDir 'matinal-batch-haiku.md'
$SonnetSkill    = Join-Path $ScriptsDir 'matinal-batch-sonnet.md'
$LogDir         = Join-Path $ProjectRoot 'logs\routines'
$DateTag        = Get-Date -Format 'yyyyMMdd'
$LogFile        = Join-Path $LogDir ('vixradar-matinal_' + $DateTag + '.log')
$MetricsFile    = Join-Path $LogDir ('matinal_metrics_' + $DateTag + '.json')
$McpConfigFile  = Join-Path $LogDir 'mcp-empty.json'

$ModelHaiku     = 'claude-haiku-4-5-20251001'
$ModelSonnet    = 'claude-sonnet-4-6'
$TopN           = 15
$TokenTarget    = 120000
$TokenHardCap   = 180000
$SonnetEwsMin   = 38
$HaikuChunk     = 6
$SonnetChunk    = 4
$PauseSec       = 2

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# PIPE1 (2026-07-28): Write-Host sob -WindowStyle Hidden do Task Scheduler quebrava o pipe do
# console apos ~28 min de execucao (ERROR_PIPE_NOT_CONNECTED 0xE9). Esta funcao absorve o crash
# silenciosamente — o log em arquivo (Write-Log) ja registrou a linha; a perda no console e
# irrelevante em execucao agendada.
function Write-Safe([string]$msg) {
    try { Write-Host $msg } catch { }
}

# MCP vazio (2026-07-14): sem isto o claude -p herdava todos os MCP servers da sessao interativa
# (tradingview, firecrawl, canva, computer-use) no system prompt de cada lote - custo real de
# tokens, nao so contagem. Mesmo arquivo compartilhado do run_vixradar_noturno_claude.ps1.
Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding UTF8

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Write-Safe $line
    # Retry com backoff: incidente 2026-07-17 (noturna) - lock de arquivo por instancia concorrente
    # fazia Add-Content sem try/catch derrubar a rotina inteira (ErrorActionPreference Stop).
    # Reincidencia sustentada 2026-07-18 (LOGLOCK1-REC, PENDENCIAS.md): lock ocupado 7+ min
    # seguidos (suspeita OneDrive/SearchIndexer). Backoff exponencial ate 8 tentativas
    # (200/400/800/1600/2000x4ms ~= 11s no pior caso). Se todas falharem, fallback para
    # arquivo alternativo com PID no nome — nenhuma linha de log e perdida.
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
    $docs = @($emp.cvm_documentos | Select-Object -First $(if ($Ultra) { 2 } else { 3 }))
    $o = [ordered]@{
        empresa        = $emp.empresa
        setor          = $emp.setor
        tier           = $emp.tier
        rodadas        = $emp.rodadas
        ews_score      = $emp.ews_score
        cvm_novos      = $emp.cvm_novos
        janela_inicio  = $emp.janela_inicio
        janela_fim     = $emp.janela_fim
        cvm_documentos = $docs
    }
    if (-not $Ultra -and $emp.contexto_historico) {
        $ctx = $emp.contexto_historico
        if ($ctx.Length -gt 120) { $ctx = $ctx.Substring(0, 120) }
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
        _matinal = $true; provedor = $provedor; resultado = $resultado
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

function Parse-TokensFromOutput([string]$text) {
    $total = 0
    if (-not $text) { return 0 }
    foreach ($pat in @('total[_\s-]*tokens?[:\s]+([\d,]+)', '([\d,]+)\s+tokens?\s+used')) {
        foreach ($match in [regex]::Matches($text, $pat, 'IgnoreCase')) {
            $n = [int]($match.Groups[1].Value -replace ',', '')
            if ($n -gt $total) { $total = $n }
        }
    }
    return $total
}

function Get-BatchOkEmissores([string[]]$outputLines) {
    # Robusto a formatacao markdown dos filhos claude -p (achado 2026-07-13): as linhas de
    # resultado "OK|empresa|tier|classificacao|..." chegam encapsuladas de varias formas -
    # cruas, com crase (`OK|...`), como linha de tabela (| OK | emp | tier | class |) ou como
    # bullet com pipe escapado (- OK\|emp\|...). O parser antigo (ancora ^OK\|) so reconhecia a
    # forma crua e falso-positivava silent_fail nas demais, gerando exit 6 espurio mesmo com
    # todos os submits ok:true. Normaliza cada linha, casa OK| em qualquer um dos formatos e
    # deduplica por emissor (evita dupla contagem quando o filho repete a linha crua + tabela).
    #
    # v4.9.161 (15/07): valida submit_ok (campo 7). Rejeita PENDENTE e variantes que indicam
    # que o LLM nao submeteu (bloqueio de ferramenta POST). So aceita true, ok, ou 1.
    $emissores = New-Object System.Collections.Generic.List[object]
    $criticos = New-Object System.Collections.Generic.List[string]
    $vistos = New-Object 'System.Collections.Generic.HashSet[string]'
    $pendentes = New-Object System.Collections.Generic.List[string]
    if (-not $outputLines) { return @{ Emissores = $emissores; Criticos = $criticos; Pendentes = $pendentes } }
    foreach ($raw in $outputLines) {
        if ($null -eq $raw) { continue }
        $n = ([string]$raw).Trim()
        $n = $n -replace '`', ''            # remove crases (forma `OK|...`)
        $n = $n -replace '^[>\*\-\s]+', ''  # remove prefixo de bullet/blockquote (- , * , > )
        $n = $n -replace '\\\|', '|'        # desescapa \| -> | (forma bullet escapada)
        if ($n.StartsWith('|')) {           # linha de tabela: colapsa bordas/espacos ao redor dos pipes
            $n = $n -replace '\s*\|\s*', '|'
            $n = $n.Trim('|')
        }
        if ($n -match '^OK\|([^|]+)\|([^|]+)\|([^|]+)\|') {
            $emp = $Matches[1].Trim()
            $cls = $Matches[3].Trim().ToUpper()
            # Extrai submit_ok (campo 7) se presente. Rejeita PENDENTE e variantes.
            $partes = $n -split '\|'
            $submitOk = if ($partes.Count -ge 7) { $partes[6].Trim().ToLower() } else { '' }
            $submitValido = ($submitOk -eq 'true' -or $submitOk -eq 'ok' -or $submitOk -eq '1')
            if (-not $submitValido) {
                $pendentes.Add("$emp ($submitOk)")
                continue
            }
            $chave = $emp.ToLower()
            if ($vistos.Add($chave)) {
                $emissores.Add($emp)
                if ($cls -eq 'CRITICO') { $criticos.Add($emp) }
            }
        }
    }
    return @{ Emissores = $emissores; Criticos = $criticos; Pendentes = $pendentes }
}

function Get-BatchBloqueioSubmit([string[]]$outputLines) {
    # Detecta saida de LLM que tentou submeter mas nao tinha ferramenta POST (regressao 15/07).
    # Frases: "BLOQUEIO DE SUBMISSAO", "POST nao executavel", "apenas WebFetch (GET)",
    # "nao tenho ferramenta de POST". Retorna $true se encontrou o padrao.
    if (-not $outputLines) { return $false }
    $regex = 'BLOQUEIO\s+DE\s+SUBMISSÃO|BLOQUEIO\s+DE\s+SUBMISSAO|POST\s+n[ãa]o\s+execut[áa]vel|apenas\s+WebFetch|n[ãa]o\s+tenho\s+ferramenta\s+de\s+POST|Invoke-RestMethod.*n[ãa]o\s+execut[áa]vel'
    foreach ($raw in $outputLines) {
        if ($null -eq $raw) { continue }
        if ([string]$raw -match $regex) { return $true }
    }
    return $false
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

function Get-ParsedResultados($outputLines) {
    # Protocolo do lote: RESULTADO|<empresa>|<json compacto> por emissor + LOTE_RESUMO|buscas=N
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

function Get-BatchResumoOk([string[]]$outputLines) {
    # Segundo sinal de cobertura, mais robusto que contar linhas (achado 2026-07-13): todo lote
    # encerra com "LOTE_RESUMO|ok=N|fail=M|..." (ou posicional "LOTE_RESUMO|N|M|..."). Quando o
    # filho reporta os emissores numa tabela com o nome na 1a coluna e o "ok" numa coluna final
    # (visto no lote sonnet-1), a contagem por linha OK| subestima, mas o total do resumo nao.
    # Retorna o N declarado, ou -1 se nao houver linha de resumo.
    if (-not $outputLines) { return -1 }
    foreach ($raw in $outputLines) {
        if ($null -eq $raw) { continue }
        $n = ([string]$raw).Trim() -replace '`', ''
        $n = $n -replace '\\\|', '|'
        if ($n.StartsWith('|')) { $n = ($n -replace '\s*\|\s*', '|').Trim('|') }
        $i = $n.IndexOf('LOTE_RESUMO')
        if ($i -ge 0) {
            $partes = ($n.Substring($i)) -split '\|'
            if ($partes.Count -ge 2) {
                $p1 = $partes[1].Trim()
                if ($p1 -match 'ok\s*=\s*(\d+)') { return [int]$Matches[1] }
                if ($p1 -match '^(\d+)$') { return [int]$Matches[1] }
            }
        }
    }
    return -1
}

function Test-ClaudeAuthFailure([string[]]$outputLines) {
    # Achado 2026-07-08 (identica a run_vixradar_noturno_claude.ps1/run_vixradar_verificacao_async.ps1):
    # claude.exe pode perder a sessao OAuth local (Task Scheduler roda sem console interativo) e
    # imprimir esta mensagem em vez de analisar - exit code do processo continua 0, entao sem esta
    # checagem o lote falso-positiva como sucesso e a rotina degrada silenciosamente (0 analises).
    $texto = ($outputLines -join "`n")
    return $texto -match '(?i)not logged in|please run /login|disabled claude subscription|use an anthropic api key instead|weekly limit|hit your.*limit|credit balance is too low|insufficient.*credit'
}

function Invoke-ClaudeBatch([string]$promptPath, [string]$Model) {
    # Reforca UTF8 a cada lote (defesa contra reset de codepage mid-run, mesmo padrao
    # de mojibake achado no noturno em 08/07 - ver run_vixradar_noturno_claude.ps1).
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # Auth resolvida no boot por Initialize-VixClaudeAuth: assinatura primeiro, chave paga
    # so se o OAuth nao responder. Reaplicada a cada lote porque o ambiente do processo
    # pode ter sido mexido no meio. Fixa a base URL oficial junto (incidente 73).
    Set-VixClaudeAuthEnv
    # --output-format json (v4.9.155): extrai envelope JSON do claude -p para capturar tokens
    # reais (input+output+cache) em vez do Parse-TokensFromOutput que sempre retornava 0 com
    # --output-format text. Mesmo padrao do run_vixradar_verificacao_async.ps1. stderr vai
    # para arquivo separado (nao misturar no stdout — corromperia o parse do JSON).
    $stderrFile = Join-Path $LogDir ('matinal_stderr_' + $DateTag + '_' + $PID + '.txt')
    # RETRY1 (2026-07-27): retry com backoff + fallback Haiku na ultima tentativa.
    # DeepSeek API (ANTHROPIC_BASE_URL) congestiona em horario de pico Chines (03:00-10:00 BRT),
    # causando exit=1 silencioso sem stderr. Backoff progressivo (0s/30s/60s) fura rate-limit
    # transitorio. Ultima tentativa troca Sonnet->Haiku (payload menor, menos tokens, maior
    # chance de passar em API congestionada).
    $retryModels = @($Model)
    if ($Model -ne 'claude-haiku-4-5-20251001') { $retryModels += 'claude-haiku-4-5-20251001' }
    $retryDelays = @(0, 30, 60)
    $raw = $null; $exitCode = 1; $retryLog = @()
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
            --add-dir $ScriptsDir `
            --add-dir $ScheduledTasks `
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
    $textOut = @($raw)
    $tokens = -1
    try {
        $jsonLine = @($raw) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
        if ($jsonLine) {
            $json = $jsonLine | ConvertFrom-Json
            if ($null -ne $json.result) { $textOut = @(('' + $json.result) -split "`n") }
            if ($json.usage) {
                # cache_read excluido da soma (2026-07-14): e releitura de contexto (cobrada a 0.1x),
                # nao trabalho novo. Somado, inflou o lote sonnet-1 para 966k tokens e estourou o
                # hard cap de 180k logo no 1o lote, deixando 11/15 emissores em deferred (ledger vazio).
                $tokens = [int]$json.usage.input_tokens + [int]$json.usage.output_tokens `
                    + [int]$json.usage.cache_creation_input_tokens
            }
        }
    } catch {
        # Parse do envelope JSON falhou — textOut fica com o raw, tokens fica -1.
        # O resto do pipeline (Get-BatchOkEmissores, Test-ClaudeAuthFailure) opera sobre
        # textOut e nao depende do parse JSON. Sempre foi assim com --output-format text.
    }
    $authFail = Test-ClaudeAuthFailure $textOut
    return @{ Output = $textOut; ExitCode = $exitCode; AuthFailure = $authFail; Tokens = $tokens }
}

function New-BatchPrompt($batch, $batchLabel, $modelName, $skillPath, $routineKey, [switch]$Ultra) {
    $slim = @($batch | ForEach-Object { Get-SlimEmissor $_ -Ultra:$Ultra })
    $json = $slim | ConvertTo-Json -Depth 8 -Compress
    $skill = (Get-Content $skillPath -Raw -Encoding UTF8).Trim()
    return @"
Execute lote $batchLabel ($($batch.Count) emissores). Modelo: $modelName. Sequencial. Sem subagentes. Sem arquivos locais. Sem chamadas HTTP de submit - o orquestrador grava os resultados.
PROIBIDO: markdown, tabelas, backticks, headers, narrativa, texto fora do protocolo abaixo.
SAIDA - exatamente estas linhas e nada mais:
1 linha por emissor: RESULTADO|<empresa exatamente como no JSON, com acentuacao identica>|<objeto resultado em JSON compacto de linha unica>
Formato do objeto resultado: {"classificacao_geral":"CRITICO|RELEVANTE|ECO|NENHUM","sem_eventos":true,"cobertura_nota":"...","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"...","resultado":"..."}]}
Cada evento em CRITICO/RELEVANTE EXIGE: memo_acontecimento (2-3 frases, o que aconteceu), memo_importancia_credito (por que importa para o credito), memo_monitorar (o que observar a seguir). Sem esses 3 campos preenchidos o evento fica incompleto.
Ultima linha: LOTE_RESUMO|buscas=<total de buscas executadas>

JSON:
$json

$skill
"@
}

function Remove-BatchPrompts([string]$tag) {
    Get-ChildItem $LogDir -Filter ('matinal_*_' + $tag + '.txt') -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $LogDir ('matinal_plano_' + $tag + '.json')) -Force -ErrorAction SilentlyContinue
}

$hoje = Get-Date
if ($hoje.DayOfWeek -in 'Saturday', 'Sunday') {
    Write-Log 'SKIP: fim de semana'
    exit 0
}
$feriados = @(
    '2026-01-01', '2026-02-16', '2026-02-17', '2026-04-03', '2026-04-21', '2026-05-01',
    '2026-06-04', '2026-09-07', '2026-10-12', '2026-11-02', '2026-11-15', '2026-11-20', '2026-12-25'
)
if ($feriados -contains $hoje.ToString('yyyy-MM-dd')) {
    Write-Log 'SKIP: feriado B3'
    exit 0
}

# Mutex global (2026-07-13): impede execucao concorrente do matinal. Mesma classe do incidente
# do noturno em 2026-07-06 (2 gatilhos disparando o mesmo PS1 sem exclusao mutua colidiram e
# submeteram cobertura minima) - o matinal tem gatilhos manuais equivalentes
# (register-all-routines-scheduler.ps1 -RunTask/-RunNowMatinal) sem essa protecao ate agora.
# WaitOne(0) = nao-bloqueante: se outra instancia ja detem o mutex, esta sai limpa sem tocar
# nos 15 emissores de maior EWS (o SO libera o mutex ao encerrar o processo).
$__matinalMutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-matinal-v2')
if (-not $__matinalMutex.WaitOne(0)) {
    Write-Log 'ABORT: outra instancia do matinal ja esta em execucao (mutex ocupado) - saindo limpo'
    exit 0
}

foreach ($f in @($HaikuSkill, $SonnetSkill)) {
    if (-not (Test-Path $f)) { Write-Log ('ERRO: skill ausente ' + $f); exit 1 }
}

Write-Log "INICIO: matinal top=$TopN meta=${TokenTarget} hard=${TokenHardCap} haiku+sonnet(EWS>=$SonnetEwsMin)"
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
    # So bloqueia por dependencia real desta rotina (KV + telemetria) - ver nota em run_vixradar_noturno_claude.ps1
    if (-not $health.bindings.kv -or -not $health.bindings.telemetria) {
        Write-Log ('ERRO: health - kv=' + $health.bindings.kv + ' telemetria=' + $health.bindings.telemetria)
        exit 3
    }
    Write-Log ('Health ' + $health.versao + ' ok=' + $health.ok + ' verificador_ok=' + $health.verificador_ok + ' (nao bloqueante para esta rotina)')
} catch {
    Write-Log ('ERRO: health ' + $_.Exception.Message)
    exit 3
}

try { $routineKey = Get-RoutineKey } catch { Write-Log $_.Exception.Message; exit 4 }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$stats = @{
    skip_ok = 0; skip_fail = 0; batch_ok = 0; batch_fail = 0; auth_fail = 0; silent_fail = 0; partial_fail = 0
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
    $plano = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_plano_rotina'; routine_key = $routineKey; modo = 'matinal'; top_n = $TopN } -TimeoutSec 180
    if ($plano.ok -ne $true) { Write-Log 'ERRO: plano'; exit 5 }
    if ($plano.total -eq 0) {
        Write-Log 'SKIP: nenhum emissor prioritario'
        exit 0
    }
    if ($plano.total -ne $TopN) { Write-Log ('AVISO: total=' + $plano.total + ' esperado=' + $TopN) }

    @{
        data = $plano.data; tiers = $plano.contagem_tiers; buscas = $plano.buscas_estimadas
        emissores = @($plano.emissores | ForEach-Object { @{ e = $_.empresa; t = $_.tier; ews = $_.ews_score } })
    } | ConvertTo-Json -Compress | Set-Content (Join-Path $LogDir ('matinal_plano_' + $DateTag + '.json')) -Encoding UTF8

    Write-Log ('Plano ' + ($plano.contagem_tiers | ConvertTo-Json -Compress))

    foreach ($emp in @($plano.emissores | Where-Object { $_.tier -eq 'SKIP' })) {
        try {
            $r = Submit-SkipEmissor $routineKey $emp
            if ($r.ok) { $stats.skip_ok++ } else { $stats.skip_fail++ }
        } catch { $stats.skip_fail++ }
        Start-Sleep -Seconds $PauseSec
    }
    Write-Log ('SKIP ' + $stats.skip_ok + ' via PS1')

    # Idempotencia (portado do noturno, v4.9.151): se a rotina reiniciou ou foi
    # disparada duas vezes no mesmo dia, nao reprocessar emissor ja feito. O noturno
    # ganhou isto depois de gastar ~180k tokens repetindo Oi e Oncoclinicas em 09/07;
    # a matinal ficou sem, e em 15/07 rodou a mesma fila as 10h00 e de novo as 17h26.
    # Mesmo formato de log (OK|nome|) e mesmo Get-NomeNormalizado dos dois lados.
    # -Force ignora a trava: util apos execucao contaminada (ex.: buscas falharam,
    # emissores foram submetidos com cobertura zero e precisam ser reprocessados).
    $jaProcessados = @{}
    if (-not $Force -and (Test-Path $LogFile)) {
        $linhasOk = Get-Content $LogFile -Encoding UTF8 | Where-Object { $_ -match '^[\d-]+ [\d:]+ OK\|([^|]+)' }
        foreach ($linha in $linhasOk) {
            if ($linha -match 'OK\|([^|]+)') {
                $jaProcessados[(Get-NomeNormalizado $Matches[1])] = $true
            }
        }
        if ($jaProcessados.Count -gt 0) {
            Write-Log ('Idempotencia: ' + $jaProcessados.Count + ' emissores ja processados hoje, pulando')
        }
    } elseif ($Force) {
        Write-Log 'AVISO: -Force ativo. Trava de idempotencia ignorada. Todos os emissores serao reprocessados.'
    }

    $analyzeList = @($plano.emissores | Where-Object {
        $_.tier -ne 'SKIP' -and -not $jaProcessados[(Get-NomeNormalizado ('' + $_.empresa))]
    })
    $queues = Build-LlmQueues $analyzeList
    Write-Log ('Filas: sonnet=' + $queues.Sonnet.Count + ' haiku=' + $queues.Haiku.Count)

    $jobs = New-Object System.Collections.Generic.List[object]
    foreach ($chunk in (Split-IntoChunks $queues.Sonnet $SonnetChunk)) {
        $jobs.Add([ordered]@{ Name = 'sonnet'; Model = $ModelSonnet; Chunk = @($chunk); Skill = $SonnetSkill; Ultra = $false; Provedor = 'claude-sonnet-routine' })
    }
    foreach ($chunk in (Split-IntoChunks $queues.Haiku $HaikuChunk)) {
        $jobs.Add([ordered]@{ Name = 'haiku'; Model = $ModelHaiku; Chunk = @($chunk); Skill = $HaikuSkill; Ultra = $true; Provedor = 'claude-haiku-routine' })
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
    foreach ($job in $jobs) {
        $ji++
        if ($stats.tokens_total -ge $TokenHardCap) {
            $stats.tokens_hard_hit = $true
            foreach ($e in $job.Chunk) { $pendingDeferred.Add($e) }
            continue
        }

        $batchSeq++
        $label = $job.Name + '-' + $ji
        $prompt = New-BatchPrompt $job.Chunk $label $job.Model $job.Skill $routineKey -Ultra:$job.Ultra
        $promptPath = Join-Path $LogDir ('matinal_' + $label + '_' + $DateTag + '.txt')
        Set-Content $promptPath -Value $prompt -Encoding UTF8

        Write-Log ('Lote ' + $label + ' [' + $job.Model + ']: ' + (($job.Chunk | ForEach-Object { $_.empresa }) -join ', '))
        $result = Invoke-ClaudeBatch $promptPath $job.Model
        $stats.batches_run++
        if ($job.Name -eq 'sonnet') { $stats.sonnet_count += $job.Chunk.Count } else { $stats.haiku_count += $job.Chunk.Count }

        if ($result.AuthFailure) {
            Write-Log ('ERRO CRITICO: claude CLI nao autenticado (sessao OAuth expirada/deslogada) no lote ' + $label + ' - reautentique com "claude /login" antes do proximo disparo. Abortando lotes restantes para nao degradar em cobertura minima silenciosa (' + ($jobs.Count - $ji) + ' lote(s) restante(s) NAO processado(s)).')
            # AUTHWEEK1 (2026-08-14): avisa o admin no momento do abort (limite semanal,
            # OAuth vencido etc). O Monitor-Tasks nao enxerga esta rotina.
            $null = Send-VixRoutineAlert -Rotina 'matinal' -Motivo 'claude CLI nao autenticado ou limite semanal atingido - lotes restantes abortados' -RoutineKey $routineKey
            $exitCode = 7
            $stats.auth_fail++
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
            $retryPrompt = New-BatchPrompt $missing $retryLabel $job.Model $job.Skill $routineKey -Ultra:$job.Ultra
            $retryPath = Join-Path $LogDir ('matinal_' + $retryLabel + '_' + $DateTag + '.txt')
            Set-Content $retryPath -Value $retryPrompt -Encoding UTF8
            $retryRes = Invoke-ClaudeBatch $retryPath $job.Model
            if ($retryRes.AuthFailure) {
                Write-Log ('ERRO CRITICO: claude CLI nao autenticado no retry do lote ' + $label + ' - ' + $missing.Count + ' emissores faltantes receberao fallback. Resultados ja processados (' + ($job.Chunk.Count - $missing.Count) + ' emissor(es)) serao submetidos normalmente.')
                $exitCode = 7
                $stats.batch_fail++
                Remove-Item $retryPath -Force -ErrorAction SilentlyContinue
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

        # silent_fail: zero RESULTADO| parseados
        $parsedCount = 0
        foreach ($emp in $job.Chunk) { if (Get-ResultadoEmissor $parsed.Map $emp.empresa) { $parsedCount++ } }
        if ($parsedCount -eq 0) {
            $stats.silent_fail++
            Write-Log ('ERRO: lote ' + $label + ' sem RESULTADO| - falha silenciosa (0/' + $job.Chunk.Count + ' emissores com analise real)')
        }

        # submit centralizado no PS1: schema garantido + retry por emissor
        $loteOk = 0; $loteFail = 0; $loteCrit = 0
        $buscasReaisLote = 0
        $iAgudo = [char]0x00ED
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
                # Contar fontes_consultadas com resultado valido. O contador autodeclarado
                # (LOTE_RESUMO|buscas=N) e escrito pelo modelo e pode reportar 12 buscas
                # enquanto todas falharam (incidente 27/07). Aqui contamos nos mesmos.
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
            # Emissor FULL com zero buscas efetivas: cobertura nao verificavel. Degradar
            # para INCONCLUSIVO em vez de gravar NENHUM ou ECO baseado em dado inexistente.
            # CRITICO preservado (vem de evento estrutural, nao depende de busca).
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
        }
        $stats.submit_ok += $loteOk
        $stats.submit_fail += $loteFail
        # Contador real de buscas (fontes_consultadas com resultado valido), nao o
        # autodeclarado pelo modelo. O autodeclarado (LOTE_RESUMO|buscas=N) pode
        # reportar N quando todas as buscas falharam (incidente 27/07).
        if ($buscasReaisLote -gt 0 -or $buscasLote -lt 0) { $buscasLote = $buscasReaisLote }
        if ($buscasLote -ge 0) { $stats.buscas_total += $buscasLote }
        Write-Log ('LOTE_FECHADO|' + $label + '|ok=' + $loteOk + '|fail=' + $loteFail + '|buscas=' + $buscasLote + '|criticos=' + $loteCrit)

        if ($loteFail -gt 0) { $stats.batch_fail++ } else { $stats.batch_ok++ }
        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue

        if ($stats.tokens_total -ge $TokenTarget -and -not $stats.tokens_over_target) {
            $stats.tokens_over_target = $true
            Write-Log ('AVISO: meta ' + $TokenTarget + ' ultrapassada - continua ate hard ' + $TokenHardCap)
        }
        if ($stats.tokens_total -ge $TokenHardCap) {
            $stats.tokens_hard_hit = $true
            Write-Log ('HARD CAP ' + $TokenHardCap + ' - restante deferred')
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
            data = $DateTag; top_n = $TopN; token_target = $TokenTarget; token_hard_cap = $TokenHardCap
            tokens_total_est = $stats.tokens_total; tokens_over_target = $stats.tokens_over_target
            tokens_hard_hit = $stats.tokens_hard_hit; skip_ok = $stats.skip_ok
            sonnet_llm = $stats.sonnet_count; haiku_llm = $stats.haiku_count; deferred = $stats.deferred
            batches = $stats.batches_run; auth_fail = $stats.auth_fail; silent_fail = $stats.silent_fail
            submit_ok = $stats.submit_ok; submit_fail = $stats.submit_fail; buscas_total = $stats.buscas_total
            criticos = @($stats.criticos); duracao_sec = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        } | ConvertTo-Json -Depth 5 | Set-Content $MetricsFile -Encoding UTF8
    }

    Write-Log ('FIM: tokens=' + $stats.tokens_total + ' meta=' + $TokenTarget + ' hard=' + $TokenHardCap +
        ' sonnet=' + $stats.sonnet_count + ' haiku=' + $stats.haiku_count +
        ' submit_ok=' + $stats.submit_ok + ' submit_fail=' + $stats.submit_fail +
        ' deferred=' + $stats.deferred + ' criticos=' + $stats.criticos.Count +
        ' auth_fail=' + $stats.auth_fail + ' silent_fail=' + $stats.silent_fail)

    # Dreno da fila de verificacao assincrona pos-matinal (v4.9.150)
    # Mesmo racional do noturno: eventos CRITICO/RELEVANTE submetidos pela matinal
    # ficam presos na fila ate o proximo drain. Este dreno garante visibilidade imediata.
    if ($stats.batch_ok -gt 0) {
        $verifScript = Join-Path $ScriptsDir 'run_vixradar_verificacao_async.ps1'
        if (Test-Path $verifScript) {
            Write-Log 'POS-MATINAL: drenando fila de verificacao...'
            try {
                $verifProc = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$verifScript`"" -PassThru -Wait -NoNewWindow
                Write-Log ('POS-MATINAL: dreno concluido (exit=' + $verifProc.ExitCode + ')')
            } catch {
                Write-Log ('POS-MATINAL: ERRO ao executar dreno - ' + $_.Exception.Message)
            }
        }
    }

    if ($stats.auth_fail -gt 0) {
        Write-Log 'ERRO FATAL: claude -p sem sessao autenticada em pelo menos 1 lote - rotina nao cobriu todos os emissores'
        $exitCode = 7
    } elseif ($stats.silent_fail -gt 0 -or $stats.skip_fail -gt 0 -or $stats.batch_fail -gt 0 -or $stats.submit_fail -gt 0) {
        $exitCode = 6
    }
} finally {
    Remove-BatchPrompts $DateTag
    Invoke-Cleanup -Aggressive
    Pop-Location
}

if ($exitCode -ne 0) { exit $exitCode }
