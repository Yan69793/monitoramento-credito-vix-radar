# run_vixradar_verificacao_async.ps1 - Dreno da fila de verificacao assincrona (radar:verif_fila:{data})
# Roda via Claude Code (assinatura mensal) em vez do Worker chamar a API Anthropic paga por token.
# NOTA (2026-07-13): v4.9.152 — migrado de pay-per-token para assinatura Claude Code.
# ANTHROPIC_API_KEY e removida do ambiente em Invoke-ClaudeBatch; claude -p usa OAuth.
# Motivo: saldo pre-pago esgotou 3x em 10 dias (03/07, 04/07, 10/07), interrompendo cobertura.
# Get-AnthropicApiKey e demais guards permanecem no codigo para eventual retorno a pay-per-token.
# Programado para rodar pouco depois de vixradar-matinal (10h BRT) e vixradar-noturno (18h BRT).
$ErrorActionPreference = 'Stop'
# Encoding UTF-8 na captura do stdout do 'claude' (higiene, alinhado ao noturno/matinal).
# NOTA: a falha de parse dos veredictos (2026-07-05) NAO era encoding - era o extrator ingenuo
# com LastIndexOf(']') casando com ']' de links markdown que o modelo anexa depois do JSON.
# Corrigido em Get-VeredictosArray/Get-BalancedJson (varredura balanceada).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot    = 'E:\Diretorio\Claude\Monitoramento de Credito'
$WorkerUrl      = 'https://api.vixradar.com'
$ScheduledTasks = 'C:\Users\User\.claude\scheduled-tasks'
$LogDir         = Join-Path $ProjectRoot 'logs\routines'
$DateTag        = Get-Date -Format 'yyyyMMdd'
$LogFile        = Join-Path $LogDir ('vixradar-verificacao-async_' + $DateTag + '.log')
$MetricsFile    = Join-Path $LogDir ('verificacao_async_metrics_' + $DateTag + '.json')
$McpConfigFile  = Join-Path $LogDir 'mcp-empty.json'

$ModelVerificador = 'claude-sonnet-4-6'
$ModelFallback    = 'claude-sonnet-4-6'  # --fallback-model quando ModelVerificador != ModelFallback (ex.: troca futura pra claude-fable-5)
$ChunkSize        = 4
$PauseSec         = 2

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
# Ver run_vixradar_noturno_claude.ps1 para o achado completo: --mcp-config inline perdia as
# aspas em contexto de execucao agendada, quebrando 100% das chamadas. Arquivo elimina a fragilidade.
Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding UTF8

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Test-ClaudeAuthFailure([string[]]$outputLines) {
    # Identica a run_vixradar_noturno_claude.ps1/run_vixradar_matinal_claude.ps1 (achado 2026-07-08):
    # claude.exe pode perder a sessao OAuth local e imprimir esta mensagem em vez do envelope JSON,
    # com exit code 0. Sem isso o lote so cai no branch generico "parse de veredictos falhou" -
    # correto quanto ao efeito (erros_parse incrementa, exitCode vira 6), mas a causa fica oculta
    # no log (indistinguivel de JSON malformado/truncado por outro motivo).
    $texto = ($outputLines -join "`n")
    return $texto -match '(?i)not logged in|please run /login|disabled claude subscription|use an anthropic api key instead|weekly limit|hit your.*limit|credit balance is too low|insufficient.*credit'
}

function Get-RoutineKey {
    if ($env:ROUTINE_API_KEY) { return $env:ROUTINE_API_KEY }
    $skillPath = Join-Path $ScheduledTasks 'vixradar-noturno\SKILL.md'
    if (Test-Path $skillPath) {
        $raw = Get-Content $skillPath -Raw -Encoding UTF8
        if ($raw -match 'ROUTINE_KEY\s*=\s*(\S+)') { return $Matches[1] }
    }
    throw 'ROUTINE_KEY nao encontrada'
}

function Get-AnthropicApiKey {
    if ($env:ANTHROPIC_API_KEY) { return $env:ANTHROPIC_API_KEY }
    $fromRegistry = [Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY', 'User')
    if ($fromRegistry) { return $fromRegistry }
    Write-Log 'AVISO: ANTHROPIC_API_KEY ausente - claude -p usara assinatura (limite semanal). Para resolver: [Environment]::SetEnvironmentVariable(''ANTHROPIC_API_KEY'',''sk-ant-...'',''User'')'
    return $null
}

# Identica a run_vixradar_noturno_claude.ps1 (mesmas flags de economia/isolamento ja validadas em producao)
function Invoke-ClaudeBatch([string]$promptPath, [string]$Model) {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $stderrFile = Join-Path $LogDir ('verifasync_stderr_' + $DateTag + '_' + $PID + '.txt')
    $raw = $null; $exitCode = 1
    # --fallback-model so entra quando Model difere do fallback - evita fallback-pra-si-mesmo.
    # Hoje (Model=Sonnet=ModelFallback) isso NAO adiciona a flag; ativa sozinho se Model virar Fable.
    # Guard de nulidade: se a funcao for copiada para outro script sem $ModelFallback no escopo,
    # a comparacao com $null passaria e a flag iria vazia - quebrando o claude -p inteiro.
    $fallbackArgs = @()
    if ($ModelFallback -and $Model -ne $ModelFallback) { $fallbackArgs = @('--fallback-model', $ModelFallback) }
    try {
        # Reforca UTF8 a cada lote (defesa contra reset de codepage mid-run, mesmo padrao
        # de mojibake achado no noturno em 08/07 - ver run_vixradar_noturno_claude.ps1).
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        # v4.9.152: assinatura Claude Code (sem pay-per-token). Remove ANTHROPIC_API_KEY do ambiente
        # do processo filho para forcar fallback a assinatura OAuth. Get-AnthropicApiKey permanece
        # no codigo para eventual retorno a pay-per-token (descomentar 2 linhas abaixo).
        # $apiKey = Get-AnthropicApiKey
        # if ($apiKey) { $env:ANTHROPIC_API_KEY = $apiKey }
        if ($env:ANTHROPIC_API_KEY) { $env:ANTHROPIC_API_KEY = $null }
        $raw = Get-Content $promptPath -Raw -Encoding UTF8 | claude -p `
            --model $Model `
            --permission-mode bypassPermissions `
            --output-format json `
            --tools 'WebSearch,WebFetch' `
            --strict-mcp-config --mcp-config $McpConfigFile `
            --setting-sources project `
            --disable-slash-commands `
            --no-session-persistence `
            --exclude-dynamic-system-prompt-sections `
            @fallbackArgs 2>>$stderrFile
        $exitCode = $LASTEXITCODE
    } catch {
        Write-Log ('AVISO: excecao ao invocar claude -p (' + $_.Exception.Message + ') - lote marcado como falho')
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    $textOut = @($raw)
    $tokens = -1
    $refusal = $false
    $refusalCategory = $null
    $refusalExplanation = $null
    try {
        $jsonLine = @($raw) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
        if ($jsonLine) {
            $json = $jsonLine | ConvertFrom-Json
            if ($null -ne $json.result) { $textOut = @(('' + $json.result) -split "`n") }
            if ($json.usage) {
                $tokens = [int]$json.usage.input_tokens + [int]$json.usage.output_tokens `
                    + [int]$json.usage.cache_creation_input_tokens + [int]$json.usage.cache_read_input_tokens
            }
            # Classificador de seguranca do Fable 5/Mythos 5 pode recusar com stop_reason=refusal
            # (resposta HTTP 200 normal, nao excecao). stop_details.category/.explanation nao
            # confirmados no envelope do CLI (nunca observado em teste real) - le se existir, sem
            # quebrar se nao existir. Sem este guard, uma recusa cairia no branch generico de
            # parse-falhou e a causa raiz ficaria invisivel no log.
            if ($json.stop_reason -eq 'refusal') {
                $refusal = $true
                if ($json.stop_details) {
                    $refusalCategory = $json.stop_details.category
                    $refusalExplanation = $json.stop_details.explanation
                }
            }
        }
    } catch {
        Write-Log ('AVISO: parse do envelope JSON falhou (' + $_.Exception.Message + ') - tokens DESCONHECIDO')
    }
    $authFail = Test-ClaudeAuthFailure $textOut
    return @{
        Output = $textOut; ExitCode = $exitCode; Tokens = $tokens; AuthFailure = $authFail
        Refusal = $refusal; RefusalCategory = $refusalCategory; RefusalExplanation = $refusalExplanation
    }
}

function Get-BalancedJson([string]$scan) {
    # Varre a partir do primeiro '[' (ou '{') ate o delimitador que o FECHA, contando profundidade
    # e ignorando colchetes/chaves dentro de strings JSON. Robusto contra texto apos o JSON
    # (ex.: o modelo via `claude -p` anexa uma lista de fontes em markdown `[titulo](url)` depois
    # do bloco - o LastIndexOf(']') ingenuo casava com esses ']' e corrompia a extracao).
    $start = $scan.IndexOf('[')
    $startObj = $scan.IndexOf('{')
    if ($start -lt 0 -or ($startObj -ge 0 -and $startObj -lt $start)) { $start = $startObj }
    if ($start -lt 0) { return $null }
    $depth = 0; $inStr = $false; $esc = $false
    for ($k = $start; $k -lt $scan.Length; $k++) {
        $ch = [string]$scan[$k]
        if ($esc) { $esc = $false; continue }
        if ($ch -eq '\') { $esc = $true; continue }
        if ($ch -eq '"') { $inStr = -not $inStr; continue }
        if ($inStr) { continue }
        if ($ch -eq '[' -or $ch -eq '{') { $depth++ }
        elseif ($ch -eq ']' -or $ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $scan.Substring($start, $k - $start + 1) }
        }
    }
    return $null
}

function Get-VeredictosArray($outputLines, [int]$esperado) {
    # O verificador retorna um array JSON de veredictos, mas o `claude -p` costuma envolver em
    # cerca ```json ... ``` e anexar uma lista de fontes em markdown depois. Estrategia:
    #   1. Se houver bloco cercado ```json/```, extrair o conteudo dele (isola o JSON do resto).
    #   2. Senao, usar o texto inteiro.
    #   3. Extrair o JSON balanceado a partir do primeiro '[' (ignora qualquer coisa apos o array).
    $texto = ($outputLines -join "`n").Trim()
    $fence = [regex]::Match($texto, '```(?:json)?\s*([\s\S]*?)```')
    $scan = if ($fence.Success) { $fence.Groups[1].Value } else { $texto }
    $bruto = Get-BalancedJson $scan
    if (-not $bruto) { return $null }
    try {
        $parsed = $bruto | ConvertFrom-Json
    } catch {
        return $null
    }
    $arr = @($parsed)
    if ($arr.Count -lt $esperado) { return $null }
    if ($arr.Count -gt $esperado) {
        Write-Log ("AVISO: modelo retornou " + $arr.Count + " veredictos para " + $esperado + " eventos - truncando para os primeiros " + $esperado)
        $arr = $arr[0..($esperado - 1)]
    }
    return $arr
}

function Invoke-WorkerJsonUtf8 {
    # Worker responde application/json SEM charset; Windows PowerShell 5.1 decodificaria a
    # resposta como ISO-8859-1, corrompendo acentos em memoria (nomes de emissor e ate o
    # system_prompt do verificador - P0 nota 43, 2026-07-07). Le bytes crus e decoda UTF-8
    # explicitamente; envia body como bytes UTF-8 pelo mesmo motivo.
    param([string]$Uri, $BodyObj, [int]$TimeoutSec = 120, [int]$Depth = 16)
    $params = @{ Uri = $Uri; Method = 'Post'; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    $params.ContentType = 'application/json; charset=utf-8'
    $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($BodyObj | ConvertTo-Json -Depth $Depth -Compress))
    $resp = Invoke-WebRequest @params
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

Write-Log 'INICIO: drenar fila de verificacao assincrona'

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Log 'ERRO: claude.exe ausente'
    exit 2
}

try {
    $health = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 30
    Write-Log ('Health ' + $health.versao + ' verificador_ok=' + $health.verificador_ok)
} catch {
    Write-Log ('ERRO: health ' + $_.Exception.Message)
    exit 3
}

try { $routineKey = Get-RoutineKey } catch { Write-Log $_.Exception.Message; exit 4 }

$stats = @{ total_fila = 0; lotes = 0; aprovados = 0; rejeitados = 0; erros_parse = 0; refusals = 0; tokens_total = 0 }
$exitCode = 0

try {
    $fila = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_fila_verificacao'; routine_key = $routineKey; dias = 3 } -TimeoutSec 60

    if ($fila.ok -ne $true) { Write-Log 'ERRO: listar_fila_verificacao'; exit 5 }
    $stats.total_fila = [int]$fila.total
    Write-Log ('Fila: ' + $stats.total_fila + ' evento(s) pendente(s)')

    if ($stats.total_fila -eq 0) {
        Write-Log 'FIM: fila vazia, nada a fazer'
        @{ data = $DateTag; total_fila = 0; lotes = 0 } | ConvertTo-Json | Set-Content $MetricsFile -Encoding UTF8
        exit 0
    }

    $itens = @($fila.itens)
    for ($i = 0; $i -lt $itens.Count; $i += $ChunkSize) {
        $fim = [Math]::Min($i + $ChunkSize - 1, $itens.Count - 1)
        $chunk = @($itens[$i..$fim])
        $stats.lotes++
        $label = 'verifasync-' + $stats.lotes

        # Prompt construido pelo Worker (fonte unica de verdade das regras do verificador) so para os ids deste chunk -
        # evita duplicar o template do prompt em PowerShell e mantem o system_prompt/user_prompt alinhados ao chunk exato.
        $chunkIds = @($chunk | ForEach-Object { $_.id })
        $chunkFila = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_fila_verificacao'; routine_key = $routineKey; ids = $chunkIds } -TimeoutSec 60
        if ($chunkFila.ok -ne $true -or -not $chunkFila.system_prompt) {
            Write-Log ('ERRO: nao consegui montar prompt do lote ' + $label + ' via listar_fila_verificacao(ids) - itens ficam na fila')
            $stats.erros_parse++
            Start-Sleep -Seconds $PauseSec
            continue
        }
        $promptTexto = $chunkFila.system_prompt + "`n`n" + $chunkFila.user_prompt + "`n`nResponda SOMENTE com o array JSON de veredictos, um por evento, na mesma ordem em que os eventos foram listados acima. Nenhum texto antes ou depois do JSON."
        $promptPath = Join-Path $LogDir ('verifasync_' + $label + '_' + $DateTag + '.txt')
        Set-Content $promptPath -Value $promptTexto -Encoding UTF8

        Write-Log ('Lote ' + $label + ': ' + $chunk.Count + ' evento(s) - ' + (($chunk | ForEach-Object { $_.empresa }) -join ', '))
        $result = Invoke-ClaudeBatch $promptPath $ModelVerificador
        if ($result.Tokens -gt 0) { $stats.tokens_total += $result.Tokens }

        if ($result.AuthFailure) {
            Write-Log ('ERRO CRITICO: claude CLI nao autenticado (sessao OAuth expirada/deslogada) no lote ' + $label + ' - reautentique com "claude /login". Abortando lotes restantes - itens ficam na fila.')
            $stats.erros_parse++
            $exitCode = 7
            Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
            break
        }

        if ($result.Refusal) {
            $categoria = if ($result.RefusalCategory) { $result.RefusalCategory } else { 'desconhecida (stop_details ausente no envelope)' }
            # Salva a saida bruta (mesmo padrao do branch de parse-falhou): se stop_details vier
            # ausente, o rawout e a unica evidencia para diagnosticar qual evento disparou o classificador.
            $rawOutPath = Join-Path $LogDir ('verifasync_rawout_refusal_' + $label + '_' + $DateTag + '.txt')
            Set-Content $rawOutPath -Value (($result.Output) -join "`n") -Encoding UTF8
            Write-Log ('AVISO: classificador de seguranca recusou o lote ' + $label + ' (' + $chunk.Count + ' evento(s); stop_reason=refusal, categoria=' + $categoria + ', modelo=' + $ModelVerificador + ') - possivel falso-positivo. Recusa e por conteudo do evento, nao por sessao - prosseguindo para o proximo lote. Itens deste lote ficam na fila (janela de releitura: 3 dias). Saida bruta em ' + $rawOutPath)
            if ($result.RefusalExplanation) { Write-Log ('  explicacao do classificador: ' + $result.RefusalExplanation) }
            $stats.refusals++
            Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds $PauseSec
            continue
        }

        $veredictos = Get-VeredictosArray $result.Output $chunk.Count
        if (-not $veredictos) {
            # Observabilidade: salva a saida bruta do modelo para diagnosticar o motivo do parse falhar
            # (contagem, JSON malformado, preambulo, truncamento). Sem isso o erro era cego.
            $rawOutPath = Join-Path $LogDir ('verifasync_rawout_' + $label + '_' + $DateTag + '.txt')
            Set-Content $rawOutPath -Value (($result.Output) -join "`n") -Encoding UTF8
            Write-Log ('ERRO: parse de veredictos falhou ou contagem nao bate no lote ' + $label +
                ' (esperado=' + $chunk.Count + ') - saida bruta em ' + $rawOutPath + ' - itens ficam na fila')
            $stats.erros_parse++
            Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds $PauseSec
            continue
        }

        $confirmarItens = @()
        for ($j = 0; $j -lt $chunk.Count; $j++) {
            $confirmarItens += @{
                id = $chunk[$j].id; empresa = $chunk[$j].empresa; semana = $chunk[$j].semana
                setor = $chunk[$j].setor; data_fila = $chunk[$j].data_fila; evento = $chunk[$j].evento
                veredicto = $veredictos[$j]
            }
        }

        try {
            $confirmResp = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'confirmar_verificacao'; routine_key = $routineKey; itens = $confirmarItens } -Depth 12 -TimeoutSec 60
            if ($confirmResp.ok -eq $true) {
                $stats.aprovados += [int]$confirmResp.resultado.aprovados
                $stats.rejeitados += [int]$confirmResp.resultado.rejeitados
                Write-Log ('LOTE_FECHADO|' + $label + '|aprovados=' + $confirmResp.resultado.aprovados + '|rejeitados=' + $confirmResp.resultado.rejeitados + '|erros=' + $confirmResp.resultado.erros)
            } else {
                Write-Log ('ERRO: confirmar_verificacao falhou no lote ' + $label + ' - ' + $confirmResp.erro)
            }
        } catch {
            Write-Log ('EXCECAO: confirmar_verificacao ' + $label + ' - ' + $_.Exception.Message)
        }

        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds $PauseSec
    }

    @{
        data = $DateTag; total_fila = $stats.total_fila; lotes = $stats.lotes
        aprovados = $stats.aprovados; rejeitados = $stats.rejeitados
        erros_parse = $stats.erros_parse; refusals = $stats.refusals; tokens_total_est = $stats.tokens_total
    } | ConvertTo-Json | Set-Content $MetricsFile -Encoding UTF8

    Write-Log ('FIM: fila=' + $stats.total_fila + ' lotes=' + $stats.lotes + ' aprovados=' + $stats.aprovados + ' rejeitados=' + $stats.rejeitados + ' erros_parse=' + $stats.erros_parse + ' refusals=' + $stats.refusals)

    if ($stats.erros_parse -gt 0) { $exitCode = 6 } elseif ($stats.refusals -gt 0) { $exitCode = 8 }
} catch {
    Write-Log ('ERRO FATAL: ' + $_.Exception.Message)
    $exitCode = 1
}

if ($exitCode -ne 0) { exit $exitCode }
