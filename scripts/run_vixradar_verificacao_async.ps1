# run_vixradar_verificacao_async.ps1 - Dreno da fila de verificacao assincrona (radar:verif_fila:{data})
# Roda via Claude Code (assinatura mensal) em vez do Worker chamar a API Anthropic paga por token.
# NOTA (2026-07-13): v4.9.152 — migrado de pay-per-token para assinatura Claude Code.
# ANTHROPIC_API_KEY e removida do ambiente em Invoke-ClaudeBatch; claude -p usa OAuth.
# Motivo: saldo pre-pago esgotou 3x em 10 dias (03/07, 04/07, 10/07), interrompendo cobertura.
# Get-AnthropicApiKey e demais guards permanecem no codigo para eventual retorno a pay-per-token.
# Programado para rodar pouco depois de vixradar-matinal (10h BRT) e vixradar-noturno (18h BRT).
# 'Continue' obrigatorio: regra do CLAUDE.md do VIX Radar. Com 'Stop' o script
# aborta antes do 'exit' e o Task Scheduler/Claude Desktop perde o codigo de saida.
$ErrorActionPreference = 'Continue'
# Encoding UTF-8 na captura do stdout do 'claude' (higiene, alinhado ao noturno/matinal).
# NOTA: a falha de parse dos veredictos (2026-07-05) NAO era encoding - era o extrator ingenuo
# com LastIndexOf(']') casando com ']' de links markdown que o modelo anexa depois do JSON.
# Corrigido em Get-VeredictosArray/Get-BalancedJson (varredura balanceada).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot    = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito'
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

# Orcamento de token (2026-07-17): esta rotina era a UNICA das quatro sem teto nenhum — o token
# era somado para relatorio e nunca decidia nada. Medido em 16/07: 773.392 tokens para 18 eventos,
# 55% do consumo do dia inteiro e mais que o hard cap da noturna (700k). Como o limite da assinatura
# e semanal, o estouro nao aparece aqui: volta 1-2 dias depois como "weekly limit" abortando
# matinal/noturna — o erro recorrente que o operador via.
#
# Calibragem (deliberada, contra o real de 16/07): 773.392 / 5 lotes = ~155k por lote de 4, ou seja
# ~15k de boot + ~35k por evento. Um cap apertado (testado com 400k) deferiria 10 dos 18 eventos
# TODO DIA — e como a fila recebe eventos novos diariamente, ela cresceria sem limite: trocaria o
# estouro de token por uma fila que nunca drena, que e pior. Os 773k sao o custo legitimo de
# verificar 18 eventos com Sonnet + busca web, e o verificador e o gate que impede evento errado
# de entrar no painel: raciona-lo e desligar a qualidade para economizar.
# Entao o teto protege contra ANOMALIA (fila represada, dreno duplicado, loop), nao raciona o dia
# normal: 900k cobre a fila tipica com folga (~20 eventos); 1,3M corta so o que e anormal.
# NAO RESOLVIDO AQUI (estrutural, fica em PENDENCIAS): ~35k/evento e caro, e parte da fila e
# duplicata semantica do mesmo fato (W29 tem 7 eventos da Oncoclinicas para 2 fatos reais) — ou
# seja, paga-se Sonnet para verificar o mesmo fato varias vezes. Atacar a dedup reduz o custo na
# origem; mexer no cap so evita o desastre.
$TokenTarget  = 900000
$TokenHardCap = 1300000

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
# Ver run_vixradar_noturno_claude.ps1 para o achado completo: --mcp-config inline perdia as
# aspas em contexto de execucao agendada, quebrando 100% das chamadas. Arquivo elimina a fragilidade.
Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding UTF8

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Write-Host $line
    # Retry com backoff: incidente 2026-07-17 (noturna) - lock de arquivo por instancia concorrente
    # fazia Add-Content sem try/catch derrubar a rotina inteira (ErrorActionPreference Stop).
    # Reincidencia sustentada 2026-07-18 (LOGLOCK1-REC, PENDENCIAS.md): lock ocupado 7+ min
    # seguidos (suspeita OneDrive/SearchIndexer). Backoff exponencial ate 8 tentativas
    # (200/400/800/1600/2000x4ms ~= 11s no pior caso) amplia a janela para locks curtos/medios
    # sem travar a rotina. Lock persistente/de minutos ainda degrada para Write-Host (transcript
    # captura), nunca derruba a rotina. Mitigacao parcial, nao a causa raiz (excluir logs/ do
    # sync do OneDrive seria a correcao completa, fora do escopo de codigo).
    for ($i = 1; $i -le 8; $i++) {
        try {
            Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
            return
        } catch {
            if ($i -eq 8) { Write-Host "FALHA Write-Log (Add-Content, $i tentativas): $($_.Exception.Message)" }
            else { Start-Sleep -Milliseconds ([Math]::Min(200 * [Math]::Pow(2, $i - 1), 2000)) }
        }
    }
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
    # v4.9.187: fallback de leitura de SKILL.md removido (recomendacao PENDENCIAS.md 2026-08-03).
    # O SKILL.md em scheduled-tasks/ pode conter chave velha apos rotacao. Env var e canonica.
    # Trim (2026-08-05): o Worker compara com !== exato e NAO normaliza (worker.js ~16354).
    # Chave colada com quebra de linha ou espaco final produz 403 indistinguivel do 403 de
    # chave revogada - a causa mais barata de descartar antes de acusar rotacao.
    if ($env:ROUTINE_API_KEY) {
        $k = $env:ROUTINE_API_KEY.Trim()
        if ($k.Length -eq 0) { throw 'ROUTINE_API_KEY definida porem vazia apos trim.' }
        if ($k -ne $env:ROUTINE_API_KEY) {
            Write-Log 'AVISO: ROUTINE_API_KEY tinha espaco/quebra de linha nas bordas - usando o valor sem eles.'
        }
        return $k
    }
    throw 'ROUTINE_API_KEY nao definida. Configure: $env:ROUTINE_API_KEY = "<chave>"'
}

# Auth do `claude -p` mora em um lugar so (2026-07-30). Critico neste script: a verificacao
# adversarial pressupoe um SEGUNDO modelo desafiando o primeiro, e com base URL de agregador
# Haiku e Sonnet colapsavam no mesmo modelo, virando o modelo se auditando. O helper fixa a
# API oficial em toda invocacao. Politica: assinatura primeiro, chave paga se o OAuth falhar.
. (Join-Path $PSScriptRoot 'lib\vixradar-claude-auth.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')

# Assert-VixLibFunctions garante que funcoes removidas/renomeadas nas libs sem
# atualizar os call sites sao detectadas na hora, com erro claro, em vez de
# silenciosamente apos 24h como aconteceu em 04-05/08/2026.
Assert-VixLibFunctions @('Set-VixClaudeAuthEnv', 'Test-VixClaudeAmbienteLimpo', 'Test-VixWebSearchProbe')

function Get-AnthropicApiKey {
    # Mantida como fachada: ha chamadas antigas por este nome. A regra vive no helper.
    return (Get-VixAnthropicApiKey)
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
        # Auth resolvida no boot por Initialize-VixClaudeAuth: assinatura primeiro, chave paga
        # so se o OAuth nao responder. Reaplicada a cada lote porque o ambiente do processo
        # pode ter sido mexido no meio. Fixa a base URL oficial junto (incidente 73), o que
        # aqui e critico: com agregador, Haiku e Sonnet colapsavam no mesmo modelo.
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
            --exclude-dynamic-system-prompt-sections `
            @fallbackArgs 2>>$stderrFile
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            # Sem retry interno aqui, entao a escalada nao recupera ESTE lote. Ela troca o
            # modo para os lotes seguintes, que e a diferenca entre perder um e perder a fila
            # inteira quando o OAuth vence no meio da drenagem.
            $saidaFalha = ('' + $raw)
            if (Test-Path $stderrFile) { $saidaFalha += (' ' + (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue)) }
            Invoke-VixClaudeAuthEscalate $saidaFalha | Out-Null
        }
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
    # 2026-07-13: mesmo padrao de array-unwrapping do Split-IntoChunks (return sem virgula unaria
    # desembrulha array de 1 elemento) - hoje inofensivo pois o unico consumo indexa so [0], mas
    # preventivo contra uso futuro (foreach, checagem de .Count) reativar a classe de bug.
    return ,$arr
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

# Mutex (2026-07-17): esta era a unica das rotinas sem exclusao mutua, e a com MAIS gatilhos
# concorrentes: task VIXRadar-Verificacao-Async (10:20) + dreno inline pos-matinal + pos-noturno.
# Quase-colisao real em 15/07: POS-MATINAL as 10:16:08 e task as 10:20:02, 4 min de folga — so
# nao colidiu porque a fila estava vazia e o dreno durou 2s. Com fila cheia o dreno leva ~29 min
# (16/07: 18:39:38 -> 19:08:43), entao qualquer atraso da matinal faz as duas instancias drenarem
# os mesmos ids e pagarem o mesmo evento 2x. Mesmo padrao ja provado em noturno/matinal/export.
$__verifMutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-verifasync')
if (-not $__verifMutex.WaitOne(0)) {
    Write-Log 'ABORT: outra instancia do dreno ja esta em execucao (mutex ocupado) - saindo limpo em 0 tokens'
    exit 0
}

Write-Log ('INICIO: drenar fila de verificacao assincrona meta=' + $TokenTarget + ' hard=' + $TokenHardCap)

# PREFLIGHT DE CREDENCIAL (2026-08-05): Worker antes de Claude.
# A ordem anterior gastava Initialize-VixClaudeAuth + probe WebSearch (uma chamada
# `claude -p` real) antes de tocar no Worker, entao uma ROUTINE_API_KEY morta so
# aparecia depois do gasto. Pior: Invoke-WebRequest do PS 5.1 lanca excecao em 403 e o
# corpo {"erro":"Acesso negado."} fica preso dentro dela - no log o 403 de credencial
# ficava indistinguivel de rede caida. Health e chave sao GET/POST baratos, sem LLM;
# rodam primeiro e falham com causa nomeada. Confirmado 05/08: listar_fila_verificacao
# devolveu 403 a partir do host, com a chave que estava em disco.
try {
    $health = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 30
    Write-Log ('Health ' + $health.versao + ' verificador_ok=' + $health.verificador_ok)
} catch {
    Write-Log ('ERRO: health ' + $_.Exception.Message)
    exit 3
}

try { $routineKey = Get-RoutineKey } catch { Write-Log $_.Exception.Message; exit 4 }

# listar_todos_emissores: mesma guarda de routine_key dos endpoints da fila, somente
# leitura, sem efeito colateral e com total conferivel (103). E o teste canonico de
# chave usado nas auditorias do vault.
try {
    $__pfResp = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_todos_emissores'; routine_key = $routineKey } -TimeoutSec 45
} catch {
    $__pfStatus = 0
    if ($_.Exception.Response) { $__pfStatus = [int]$_.Exception.Response.StatusCode }
    if ($__pfStatus -eq 403) {
        Write-Log 'ERRO FATAL: ROUTINE_API_KEY rejeitada pelo Worker (HTTP 403 Acesso negado).'
        Write-Log 'ERRO FATAL: a chave existe no ambiente mas nao bate com o secret ROUTINE_API_KEY do Worker. Causas usuais: chave rotacionada em producao, aspas coladas junto do valor, valor truncado.'
        Write-Log 'ERRO FATAL: reexportar $env:ROUTINE_API_KEY e reexecutar. Nenhum token de LLM foi gasto.'
        exit 8
    }
    Write-Log ('ERRO FATAL: preflight de credencial falhou (HTTP ' + $__pfStatus + '): ' + $_.Exception.Message)
    exit 8
}
if ($__pfResp.ok -ne $true) {
    Write-Log 'ERRO FATAL: preflight de credencial respondeu ok:false sem erro HTTP - endpoint recusou a chamada.'
    exit 8
}
Write-Log ('Preflight: ROUTINE_API_KEY aceita pelo Worker (' + [int]$__pfResp.total + ' emissores). Nenhum token gasto ate aqui.')
# Sonda a assinatura uma vez e registra no log qual credencial serviu a execucao. A linha
# importa para proveniencia: em 30/07 o log carimbava Claude sem que isso fosse verificavel.
Initialize-VixClaudeAuth -McpConfigFile $McpConfigFile | Out-Null
if ((Get-VixClaudeAuthModo) -eq 'nenhum') {
    Write-Log 'ERRO FATAL: nenhuma credencial Claude disponivel (assinatura expirada, token longevo ausente, chave paga invalida ou ausente). Abortando antes do primeiro lote.'
    Write-Log 'ERRO FATAL: rode `claude setup-token` para token longevo ou defina VIXRADAR_ANTHROPIC_API_KEY com chave sk-ant-valida.'
    exit 5
}
# Alinhado com 2b025b0: a guarda perdeu o parametro -ModeloFixadoNaChamada e a funcao
# Get-VixModeloEnvInfo, mas as duas chamadas continuaram aqui. Sob $ErrorActionPreference
# 'Continue' isso nao mataria o script - e pior: parametro inexistente faz o bind falhar,
# $ambientViolacao fica $null e o `if` abaixo nunca dispara. A guarda inteira (incluindo
# ANTHROPIC_BASE_URL, o vetor real do 27/07) sairia de servico em silencio, com so um
# registro de erro no log. Chamada normalizada para a assinatura que a lib expoe hoje.
$ambientViolacao = Test-VixClaudeAmbienteLimpo
if ($ambientViolacao) {
    Write-Log "ERRO FATAL: ambiente contaminado detectado — $ambientViolacao"
    Write-Log 'ERRO FATAL: variavel de ambiente ou settings.json aponta para agregador/modelo nao-Claude.'
    Write-Log 'ERRO FATAL: corrija o ambiente e reexecute. Verificar: registry User/Machine, settings.json, env vars do processo.'
    exit 6
}
if (-not (Test-VixWebSearchProbe $McpConfigFile)) {
    Write-Log 'ERRO FATAL: probe WebSearch falhou - ferramenta de busca indisponivel.'
    Write-Log 'ERRO FATAL: verificar modelo configurado e conectividade. A execucao foi abortada antes do primeiro evento.'
    exit 7
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Log 'ERRO: claude.exe ausente'
    exit 2
}

$stats = @{ total_fila = 0; lotes = 0; aprovados = 0; rejeitados = 0; erros_parse = 0; refusals = 0; tokens_total = 0; tokens_desconhecidos = 0; deferred = 0; token_hard_hit = $false }
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

        # Hard cap PRE-lote (2026-07-17): mede antes de gastar, nao depois. Estimativa por lote =
        # boot (~15k) + eventos * 35k, ambos medidos no real de 16/07 (773.392 / 5 lotes de 4).
        # Deferir aqui e barato e reversivel: o item permanece na fila e o proximo dreno o pega —
        # ao contrario de deferir emissor na noturna, onde a cobertura do dia se perde.
        $estLote = 15000 + ($chunk.Count * 35000)
        if (($stats.tokens_total + $estLote) -ge $TokenHardCap) {
            Write-Log ('HARD CAP pre-lote: acum=' + $stats.tokens_total + ' est=' + $estLote + ' >= ' + $TokenHardCap + ' - lote ' + $label + ' e restantes deferred (' + ($itens.Count - $i) + ' evento(s) ficam na fila)')
            $stats.token_hard_hit = $true
            $stats.deferred += ($itens.Count - $i)
            break
        }

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

        # VERIFCACHE1 (2026-07-24): cache de verificacao no fluxo real.
        # O Worker retorna cache_hits (mapa id->veredicto). Itens com cache hit pulam o LLM
        # e vao direto para confirmar_verificacao, economizando ~35k tokens/evento.
        $confirmarItens = @()
        $cachedIds = @{}
        if ($chunkFila.cache_hits) {
            $chunkFila.cache_hits.PSObject.Properties | ForEach-Object { $cachedIds[$_.Name] = $_.Value }
        }
        $cacheHitCount = 0
        foreach ($item in $chunk) {
            if ($cachedIds.ContainsKey($item.id)) {
                $confirmarItens += @{
                    id = $item.id; empresa = $item.empresa; semana = $item.semana
                    setor = $item.setor; data_fila = $item.data_fila; evento = $item.evento
                    veredicto = $cachedIds[$item.id]
                }
                $cacheHitCount++
            }
        }
        if ($cacheHitCount -gt 0) {
            Write-Log ('CACHE_HITS|' + $label + '|' + $cacheHitCount + ' evento(s) do cache - ' + (($chunk | Where-Object { $cachedIds.ContainsKey($_.id) } | ForEach-Object { $_.empresa }) -join ', '))
            if (-not $stats.cache_hits) { $stats.cache_hits = 0 }
            $stats.cache_hits += $cacheHitCount
        }

        # Itens sem cache: fluxo LLM normal
        $nonCached = @($chunk | Where-Object { -not $cachedIds.ContainsKey($_.id) })
        if ($nonCached.Count -gt 0) {
            $nonCachedIds = @($nonCached | ForEach-Object { $_.id })
            # Se todo o chunk era cache hit, nao precisa de prompt LLM
            if ($nonCachedIds.Count -eq $chunkIds.Count) {
                # Nenhum cache hit — usa o prompt ja obtido (contem todos os itens)
                $promptChunkIds = $chunkIds
                $promptChunkFila = $chunkFila
            } else {
                # Cache parcial — re-obtem prompt so para os nao-cached
                $promptChunkIds = $nonCachedIds
                $promptChunkFila = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_fila_verificacao'; routine_key = $routineKey; ids = $nonCachedIds } -TimeoutSec 60
            }
            if ($promptChunkFila.ok -ne $true -or -not $promptChunkFila.system_prompt) {
                Write-Log ('ERRO: nao consegui montar prompt do lote ' + $label + ' (non-cached) - itens ficam na fila')
                $stats.erros_parse++
                Start-Sleep -Seconds $PauseSec
                continue
            }
            $promptTexto = $promptChunkFila.system_prompt + "`n`n" + $promptChunkFila.user_prompt + "`n`nResponda SOMENTE com o array JSON de veredictos, um por evento, na mesma ordem em que os eventos foram listados acima. Nenhum texto antes ou depois do JSON."
            $promptPath = Join-Path $LogDir ('verifasync_' + $label + '_' + $DateTag + '.txt')
            Set-Content $promptPath -Value $promptTexto -Encoding UTF8

            Write-Log ('Lote ' + $label + ': ' + $nonCached.Count + ' evento(s) [cache=' + $cacheHitCount + '] - ' + (($nonCached | ForEach-Object { $_.empresa }) -join ', '))
            $result = Invoke-ClaudeBatch $promptPath $ModelVerificador
            if ($result.Tokens -gt 0) {
                $stats.tokens_total += $result.Tokens
            } else {
                $stats.tokens_total += $estLote
                $stats.tokens_desconhecidos++
                Write-Log ('AVISO: tokens do lote ' + $label + ' DESCONHECIDOS (parse do envelope falhou) - cobrando estimativa ' + $estLote + ' contra o cap; acum=' + $stats.tokens_total)
            }

            if ($result.AuthFailure) {
                Write-Log ('ERRO CRITICO: claude CLI nao autenticado (sessao OAuth expirada/deslogada) no lote ' + $label + ' - reautentique com "claude /login". Abortando lotes restantes - itens ficam na fila.')
                $stats.erros_parse++
                $exitCode = 7
                Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
                break
            }

            if ($result.Refusal) {
                $categoria = if ($result.RefusalCategory) { $result.RefusalCategory } else { 'desconhecida (stop_details ausente no envelope)' }
                $rawOutPath = Join-Path $LogDir ('verifasync_rawout_refusal_' + $label + '_' + $DateTag + '.txt')
                Set-Content $rawOutPath -Value (($result.Output) -join "`n") -Encoding UTF8
                Write-Log ('AVISO: classificador de seguranca recusou o lote ' + $label + ' (' + $nonCached.Count + ' evento(s); stop_reason=refusal, categoria=' + $categoria + ', modelo=' + $ModelVerificador + ') - possivel falso-positivo. Recusa e por conteudo do evento, nao por sessao - prosseguindo para o proximo lote. Itens deste lote ficam na fila (janela de releitura: 3 dias). Saida bruta em ' + $rawOutPath)
                if ($result.RefusalExplanation) { Write-Log ('  explicacao do classificador: ' + $result.RefusalExplanation) }
                $stats.refusals++
                Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds $PauseSec
                continue
            }

            $veredictos = Get-VeredictosArray $result.Output $nonCached.Count
            if (-not $veredictos) {
                $rawOutPath = Join-Path $LogDir ('verifasync_rawout_' + $label + '_' + $DateTag + '.txt')
                Set-Content $rawOutPath -Value (($result.Output) -join "`n") -Encoding UTF8
                Write-Log ('ERRO: parse de veredictos falhou ou contagem nao bate no lote ' + $label +
                    ' (esperado=' + $nonCached.Count + ') - saida bruta em ' + $rawOutPath + ' - itens ficam na fila')
                $stats.erros_parse++
                Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds $PauseSec
                continue
            }

            for ($j = 0; $j -lt $nonCached.Count; $j++) {
                $confirmarItens += @{
                    id = $nonCached[$j].id; empresa = $nonCached[$j].empresa; semana = $nonCached[$j].semana
                    setor = $nonCached[$j].setor; data_fila = $nonCached[$j].data_fila; evento = $nonCached[$j].evento
                    veredicto = $veredictos[$j]
                }
            }
        } else {
            Write-Log ('Lote ' + $label + ': ' + $chunk.Count + ' evento(s) TODOS do cache - sem chamada LLM')
        }

        try {
            $confirmResp = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'confirmar_verificacao'; routine_key = $routineKey; itens = $confirmarItens } -Depth 12 -TimeoutSec 60
            if ($confirmResp.ok -eq $true) {
                $stats.aprovados += [int]$confirmResp.resultado.aprovados
                $stats.rejeitados += [int]$confirmResp.resultado.rejeitados
                Write-Log ('LOTE_FECHADO|' + $label + '|aprovados=' + $confirmResp.resultado.aprovados + '|rejeitados=' + $confirmResp.resultado.rejeitados + '|erros=' + $confirmResp.resultado.erros + '|cache=' + $cacheHitCount)
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

    Write-Log ('FIM: fila=' + $stats.total_fila + ' lotes=' + $stats.lotes + ' aprovados=' + $stats.aprovados + ' rejeitados=' + $stats.rejeitados + ' erros_parse=' + $stats.erros_parse + ' refusals=' + $stats.refusals + ' tokens=' + $stats.tokens_total + ' meta=' + $TokenTarget + ' hard=' + $TokenHardCap + ' hard_hit=' + $stats.token_hard_hit + ' deferred=' + $stats.deferred + ' tokens_desconhecidos=' + $stats.tokens_desconhecidos)

    if ($stats.erros_parse -gt 0) { $exitCode = 6 } elseif ($stats.refusals -gt 0) { $exitCode = 8 }
} catch {
    Write-Log ('ERRO FATAL: ' + $_.Exception.Message)
    $exitCode = 1
}

if ($exitCode -ne 0) { exit $exitCode }
