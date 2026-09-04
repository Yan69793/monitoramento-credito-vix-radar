# run_vixradar_agenda_semanal.ps1 - Atualiza o calendario de divulgacao trimestral (top 20 stale/semana)
# CAUSA RAIZ CORRIGIDA (2026-08-18, FASE 2 de governanca das rotinas):
# Ate esta versao, a rotina rodava via run_claude_routine.ps1 (catalogo generico) com
# --tools 'WebSearch,WebFetch' - essa flag SUBSTITUI o conjunto de ferramentas do modelo,
# nao soma, entao o Bash desaparecia. A SKILL.md antiga mandava o proprio Claude rodar
# curl.exe contra o Worker. Sem shell, os logs de 2026-08-10 e 2026-08-16 mostram o modelo
# relatando "nao tenho shell" e "nao consigo executar curl", mas o wrapper genérico gravava
# FIM: concluido com exit 0 do mesmo jeito (do ponto de vista do PowerShell, claude -p tinha
# retornado 0 - respondeu texto, so que o texto era uma desculpa). Confirmado ao vivo em
# 18/08: listar_calendario_stale devolveu 20 emissores com atualizado_em:null e trimestre
# vencido (Equatorial, CEMIG, Eletrobras, Engie, etc.) - calendario parado desde antes de 10/08.
#
# Correcao estrutural (nao so liberar Bash): este script, como run_vixradar_verificacao_async.ps1
# (referencia de qualidade da FASE 1), faz TODA a I/O com o Worker em PowerShell puro
# (Invoke-WorkerJsonUtf8). O `claude -p` so entra para pesquisar (WebSearch/WebFetch) e
# devolver JSON estruturado por lote - nunca mais precisa de shell para tocar o Worker.
#
# 'Continue' obrigatorio: regra do CLAUDE.md do VIX Radar. Com 'Stop' o script aborta antes
# do 'exit' e o Task Scheduler perde o codigo de saida real.
#
# CLAUDE-FREE-MIGRATION (2026-09-04): -ForceClaude so o operador passa, em chamada manual
# explicita com VIXRADAR_LLM_PROVIDER='claude-manual'. O Task Scheduler nunca passa essa
# flag; sem ela o gate abaixo bloqueia com exit 86 antes de gastar qualquer token.
param(
    [switch]$ForceClaude
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot   = 'E:\Diretorio\Claude\Monitoramento de Credito'
$WorkerUrl     = 'https://api.vixradar.com'
$LogDir        = Join-Path $ProjectRoot 'logs\routines'
$DateTag       = Get-Date -Format 'yyyyMMdd'
$LogFile       = Join-Path $LogDir ('vixradar-agenda-semanal_' + $DateTag + '.log')
$MetricsFile   = Join-Path $LogDir ('agenda-semanal_metrics_' + $DateTag + '.json')
$McpConfigFile = Join-Path $LogDir 'mcp-empty.json'

$Model          = 'claude-sonnet-4-6'
$ModelFallback  = 'claude-sonnet-4-6'
$ChunkSize      = 4
$PauseSec       = 2
$LimiteStale    = 20

# Calibragem inicial (2026-08-18, primeira versao com execucao real - revisar apos o primeiro
# run ao vivo, mesmo padrao de honestidade do comentario equivalente em
# run_vixradar_verificacao_async.ps1). Estimativa por lote de 4 empresas: ~15k boot + ~25k por
# empresa (pesquisa de calendario com cross-check de 2 fontes e mais barata que verificacao
# adversarial de evento de credito, que calibrou ~35k/evento). Como a rotina e semanal e o pior
# caso de hard-cap e "fica stale mais uma semana" (sem risco de fila represada, ao contrario da
# verificacao-async), o cap pode ser conservador.
$TokenTarget  = 400000
$TokenHardCap = 600000

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding UTF8

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Write-Host $line
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

function Get-RoutineKey {
    # Mesma hidratacao das outras rotinas (ROTA1, 2026-08-18): registro User e a fonte da
    # verdade apos rotacao de chave, hidratar sempre, nao so quando o env esta ausente.
    $doRegistro = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    if ($doRegistro) {
        $k = $doRegistro.Trim()
        if ($k.Length -eq 0) { throw 'ROUTINE_API_KEY no registro vazia apos trim.' }
        if ($k -ne $doRegistro) { Write-Log 'AVISO: ROUTINE_API_KEY do registro tinha espaco/quebra de linha nas bordas - usando o valor sem eles.' }
        return $k
    }
    if ($env:ROUTINE_API_KEY) {
        $k = $env:ROUTINE_API_KEY.Trim()
        if ($k.Length -eq 0) { throw 'ROUTINE_API_KEY definida porem vazia apos trim.' }
        if ($k -ne $env:ROUTINE_API_KEY) { Write-Log 'AVISO: ROUTINE_API_KEY tinha espaco/quebra de linha nas bordas - usando o valor sem eles.' }
        return $k
    }
    throw 'ROUTINE_API_KEY nao definida. Configure: $env:ROUTINE_API_KEY = "<chave>"'
}

. (Join-Path $PSScriptRoot 'lib\vixradar-claude-auth.ps1')
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')
Assert-VixLibFunctions @('Set-VixClaudeAuthEnv', 'Test-VixClaudeAmbienteLimpo', 'Test-VixWebSearchProbe', 'Send-VixRoutineAlert', 'Initialize-VixClaudeAuth', 'Get-VixClaudeAuthModo', 'Invoke-VixClaudeAuthEscalate')

function Test-ClaudeAuthFailure([string[]]$outputLines) {
    $texto = ($outputLines -join "`n")
    return $texto -match '(?i)not logged in|please run /login|disabled claude subscription|use an anthropic api key instead|weekly limit|hit your.*limit|credit balance is too low|insufficient.*credit'
}

# Identico ao padrao de run_vixradar_verificacao_async.ps1 (mesmas flags de economia/isolamento
# ja validadas em producao). WebSearch/WebFetch apenas - este script nunca precisa de Bash
# porque toda I/O com o Worker roda aqui em PowerShell, nao dentro da sessao do claude -p.
function Invoke-ClaudeBatch([string]$promptPath, [string]$ModeloChamada) {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $stderrFile = Join-Path $LogDir ('agendasem_stderr_' + $DateTag + '_' + $PID + '.txt')
    $raw = $null; $exitCode = 1
    $fallbackArgs = @()
    if ($ModelFallback -and $ModeloChamada -ne $ModelFallback) { $fallbackArgs = @('--fallback-model', $ModelFallback) }
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        Set-VixClaudeAuthEnv
        $raw = Get-Content $promptPath -Raw -Encoding UTF8 | claude -p `
            --model $ModeloChamada `
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
    try {
        $jsonLine = @($raw) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
        if ($jsonLine) {
            $json = $jsonLine | ConvertFrom-Json
            if ($null -ne $json.result) { $textOut = @(('' + $json.result) -split "`n") }
            if ($json.usage) {
                $tokens = [int]$json.usage.input_tokens + [int]$json.usage.output_tokens `
                    + [int]$json.usage.cache_creation_input_tokens + [int]$json.usage.cache_read_input_tokens
            }
        }
    } catch {
        Write-Log ('AVISO: parse do envelope JSON falhou (' + $_.Exception.Message + ') - tokens DESCONHECIDO')
    }
    $authFail = Test-ClaudeAuthFailure $textOut
    return @{ Output = $textOut; ExitCode = $exitCode; Tokens = $tokens; AuthFailure = $authFail }
}

# Mesmo varredor balanceado de run_vixradar_verificacao_async.ps1: robusto contra o modelo
# envolver a resposta em cerca ```json e anexar texto/links depois do array.
function Get-BalancedJson([string]$scan) {
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

function Get-CalendarioArray($outputLines) {
    $texto = ($outputLines -join "`n").Trim()
    $fence = [regex]::Match($texto, '```(?:json)?\s*([\s\S]*?)```')
    $scan = if ($fence.Success) { $fence.Groups[1].Value } else { $texto }
    $bruto = Get-BalancedJson $scan
    if (-not $bruto) { return $null }
    try { $parsed = $bruto | ConvertFrom-Json } catch { return $null }
    return ,@($parsed)
}

function Invoke-WorkerJsonUtf8 {
    # Worker responde application/json SEM charset - PS 5.1 decodificaria como ISO-8859-1 e
    # corromperia acentos (nome de emissor). Le bytes crus e decoda UTF-8 explicitamente.
    param([string]$Uri, $BodyObj, [int]$TimeoutSec = 120, [int]$Depth = 16)
    $params = @{ Uri = $Uri; Method = 'Post'; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    $params.ContentType = 'application/json; charset=utf-8'
    $params.Body = [System.Text.Encoding]::UTF8.GetBytes(($BodyObj | ConvertTo-Json -Depth $Depth -Compress))
    $resp = Invoke-WebRequest @params
    return ([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
}

function New-PromptLote([array]$Empresas) {
    $listaTxt = ($Empresas | ForEach-Object {
        $alvos = ($_.trimestres_alvo | ForEach-Object { $_.periodo + ' (prevista ' + $_.data_prevista + ', status atual ' + $_.status_validacao + ')' }) -join '; '
        '- ' + $_.empresa + ' [setor: ' + $_.setor + '] - trimestres a confirmar: ' + $alvos
    }) -join "`n"

    return @"
Voce mantem o calendario de divulgacao de resultados trimestrais de emissores de credito
privado brasileiros. Para CADA empresa da lista abaixo, busque a data oficial (ou confirme a
ja conhecida) de divulgacao dos trimestres indicados.

Empresas deste lote:
$listaTxt

ORDEM OBRIGATORIA DE FONTES (CALVAL-V2, nunca pular etapa):
- R1: RI oficial da companhia ("NOME_EMPRESA" resultados 2026 site:ri. ou portal investidor)
- R2: CVM ("NOME_EMPRESA" site:rad.cvm.gov.br resultado OR DFP OR ITR)
- R3: B3/comunicado corporativo ("NOME_EMPRESA" calendario resultados site:b3.com.br OR comunicado)
- R4: secundarias, SO para cross-check, nunca como fonte primaria (infomoney, moneytimes, investidor10)

Regras:
- Confirme a data em pelo menos 2 fontes independentes quando possivel. Divergencia entre
  fontes deve ser reportada em observacao_divergencia, nunca resolvida por palpite.
- Nunca inventar data. Sem data publicada, devolva o periodo sem data_prevista (campo ausente
  ou null), nunca estime por padrao historico da companhia.
- Maximo 3 buscas por empresa. Sem confirmacao apos isso, devolva o que achou (mesmo que so
  R1 sem cross-check) com observacao_divergencia explicando a lacuna.
- trimestre_fiscal:true quando o exercicio fiscal nao segue o ano-calendario; mantenha o
  periodo exatamente como a companhia publica (ex.: 3T25F).

Responda SOMENTE com um array JSON, um objeto por empresa, NA MESMA ORDEM da lista acima.
Nenhum texto antes ou depois do JSON. Schema exato de cada objeto:

[
  {
    "empresa": "NOME_EMPRESA exatamente como veio na lista acima",
    "trimestres": [
      {
        "periodo": "2T26",
        "data_prevista": "2026-08-12",
        "horario": "apos_fechamento",
        "status": "agendado",
        "fonte": "https://ri.empresa.com.br/resultados",
        "url_fonte_primaria": "https://ri.empresa.com.br/resultados",
        "fonte_secundaria": "moneytimes.com.br",
        "url_fonte_secundaria": "https://www.moneytimes.com.br/...",
        "fontes_secundarias": [{"fonte":"moneytimes.com.br","url":"https://..."}],
        "divergencias": [],
        "observacao_divergencia": null,
        "data_ultima_verificacao": "$(Get-Date -Format 'yyyy-MM-dd')",
        "trimestre_fiscal": false
      }
    ]
  }
]

Se nao achar nenhuma data para nenhum trimestre pedido de uma empresa, devolva
"trimestres": [] para ela (nunca omita a empresa do array).
"@
}

# CLAUDE-FREE-MIGRATION (2026-09-04): a agenda pesquisa com claude (WebSearch + JSON por
# lote). Sem provider manual forcado, bloqueia com exit 86 antes do mutex e do preflight.
if (-not (Test-VixLlmPermiteClaude -ForceClaude:$ForceClaude)) {
    Write-Log (Get-VixLlmBloqueadoMsg 'run_vixradar_agenda_semanal.ps1')
    exit $VixLlmBloqueadoExit
}

$__mutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-agenda-semanal')
if (-not $__mutex.WaitOne(0)) {
    Write-Log 'ABORT: outra instancia da agenda semanal ja esta em execucao (mutex ocupado) - saindo limpo em 0 tokens'
    exit 0
}

$inicioIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
Write-Log ('INICIO: agenda-semanal meta=' + $TokenTarget + ' hard=' + $TokenHardCap)

# PREFLIGHT: Worker antes de Claude, mesma ordem barata-antes-de-cara do resto da familia.
try {
    $health = Invoke-RestMethod -Uri $WorkerUrl -Method Get -TimeoutSec 30
    Write-Log ('Health versao=' + $health.versao + ' kv=' + $health.bindings.kv + ' telemetria=' + $health.bindings.telemetria)
    $versaoWorker = $health.versao
} catch {
    Write-Log ('ERRO: health ' + $_.Exception.Message)
    exit 3
}

try { $routineKey = Get-RoutineKey } catch { Write-Log $_.Exception.Message; exit 4 }

$stats = @{ stale_inicial = 0; atualizados = 0; pulados = 0; mismatch = 0; erros = 0; lotes = 0; tokens_total = 0 }
$exitCode = 0

try {
    # Passo 1: listar_calendario_stale - leitura, serve de teste de credencial e de dado.
    try {
        $stale = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'listar_calendario_stale'; routine_key = $routineKey; limite = $LimiteStale } -TimeoutSec 45
    } catch {
        $st = 0
        if ($_.Exception.Response) { $st = [int]$_.Exception.Response.StatusCode }
        if ($st -eq 403) {
            Write-Log 'ERRO FATAL: ROUTINE_API_KEY rejeitada pelo Worker (HTTP 403). Nenhum token de LLM foi gasto.'
            exit 8
        }
        Write-Log ('ERRO FATAL: listar_calendario_stale falhou (HTTP ' + $st + '): ' + $_.Exception.Message)
        exit 8
    }
    if ($stale.ok -ne $true) { Write-Log 'ERRO FATAL: listar_calendario_stale respondeu ok:false'; exit 8 }
    $stats.stale_inicial = [int]$stale.total
    Write-Log ('Preflight: ROUTINE_API_KEY aceita. Emissores stale=' + $stats.stale_inicial + '. Nenhum token de LLM gasto ate aqui.')

    if ($stats.stale_inicial -eq 0) {
        Write-Log 'FIM: agenda-semanal | nenhum emissor stale esta semana'
        @{ data = $DateTag; stale_inicial = 0 } | ConvertTo-Json | Set-Content $MetricsFile -Encoding UTF8
        exit 0
    }

    # Ambiente + WebSearch so testados DEPOIS do preflight barato, mesma ordem da async.
    Initialize-VixClaudeAuth -McpConfigFile $McpConfigFile | Out-Null
    if ((Get-VixClaudeAuthModo) -eq 'nenhum') {
        Write-Log 'ERRO FATAL: nenhuma credencial Claude disponivel. Abortando antes do primeiro lote.'
        exit 5
    }
    $ambientViolacao = Test-VixClaudeAmbienteLimpo
    if ($ambientViolacao) {
        Write-Log ('ERRO FATAL: ambiente contaminado detectado - ' + $ambientViolacao)
        exit 6
    }
    if (-not (Test-VixWebSearchProbe $McpConfigFile)) {
        Write-Log 'ERRO FATAL: probe WebSearch falhou - ferramenta de busca indisponivel.'
        exit 7
    }
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Log 'ERRO: claude.exe ausente'
        exit 2
    }

    $emissores = @($stale.emissores)
    for ($i = 0; $i -lt $emissores.Count; $i += $ChunkSize) {
        $fim = [Math]::Min($i + $ChunkSize - 1, $emissores.Count - 1)
        $chunk = @($emissores[$i..$fim])
        $stats.lotes++
        $label = 'agendasem-' + $stats.lotes

        $estLote = 15000 + ($chunk.Count * 25000)
        if (($stats.tokens_total + $estLote) -ge $TokenHardCap) {
            $restantes = $emissores.Count - $i
            Write-Log ('HARD CAP pre-lote: acum=' + $stats.tokens_total + ' est=' + $estLote + ' >= ' + $TokenHardCap + ' - lote ' + $label + ' e ' + $restantes + ' emissor(es) ficam stale para a proxima execucao')
            $stats.pulados += $restantes
            break
        }

        $promptTexto = New-PromptLote $chunk
        $promptPath = Join-Path $LogDir ('agendasem_' + $label + '_' + $DateTag + '.txt')
        Set-Content $promptPath -Value $promptTexto -Encoding UTF8

        Write-Log ('Lote ' + $label + ': ' + $chunk.Count + ' empresa(s) - ' + (($chunk | ForEach-Object { $_.empresa }) -join ', '))
        $result = Invoke-ClaudeBatch $promptPath $Model
        if ($result.Tokens -gt 0) {
            $stats.tokens_total += $result.Tokens
        } else {
            $stats.tokens_total += $estLote
            Write-Log ('AVISO: tokens do lote ' + $label + ' DESCONHECIDOS - cobrando estimativa ' + $estLote + ' contra o cap; acum=' + $stats.tokens_total)
        }

        if ($result.AuthFailure) {
            Write-Log ('ERRO CRITICO: claude CLI nao autenticado no lote ' + $label + ' - abortando lotes restantes. ' + ($chunk.Count) + ' emissor(es) deste lote e os restantes ficam stale.')
            $null = Send-VixRoutineAlert -Rotina 'agenda-semanal' -Motivo 'claude CLI nao autenticado ou limite semanal atingido - calendario nao atualizado' -RoutineKey $routineKey
            $stats.pulados += ($emissores.Count - $i)
            $exitCode = 7
            Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
            break
        }

        $itens = Get-CalendarioArray $result.Output
        if (-not $itens -or $itens.Count -eq 0) {
            $rawOutPath = Join-Path $LogDir ('agendasem_rawout_' + $label + '_' + $DateTag + '.txt')
            Set-Content $rawOutPath -Value (($result.Output) -join "`n") -Encoding UTF8
            Write-Log ('ERRO: parse do lote ' + $label + ' falhou - saida bruta em ' + $rawOutPath + ' - ' + $chunk.Count + ' emissor(es) ficam stale')
            $stats.erros += $chunk.Count
            Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds $PauseSec
            continue
        }

        $nomesEsperados = @($chunk | ForEach-Object { $_.empresa })
        foreach ($item in $itens) {
            $nomeResp = ('' + $item.empresa).Trim()
            $nomeCanonico = $nomesEsperados | Where-Object { $_ -eq $nomeResp } | Select-Object -First 1
            if (-not $nomeCanonico) {
                $nomeCanonico = $nomesEsperados | Where-Object { $_.ToLowerInvariant() -eq $nomeResp.ToLowerInvariant() } | Select-Object -First 1
            }
            if (-not $nomeCanonico) {
                Write-Log ('MISMATCH: lote ' + $label + ' devolveu empresa "' + $nomeResp + '" que nao bate com nenhuma pedida (' + ($nomesEsperados -join ', ') + ') - pulando, nao posta com nome errado')
                $stats.mismatch++
                continue
            }
            $trimestres = @($item.trimestres)
            if ($trimestres.Count -eq 0) {
                Write-Log ('SEM_DATA: ' + $nomeCanonico + ' - modelo nao achou trimestres, nada a postar')
                $stats.pulados++
                continue
            }
            try {
                $upd = Invoke-WorkerJsonUtf8 -Uri $WorkerUrl -BodyObj @{ action = 'atualizar_calendario_emissor'; routine_key = $routineKey; empresa = $nomeCanonico; trimestres = $trimestres } -Depth 12 -TimeoutSec 60
                if ($upd.ok -eq $true -and [int]$upd.trimestres_count -ge 1) {
                    Write-Log ('OK|' + $nomeCanonico + '|trimestres_count=' + $upd.trimestres_count)
                    $stats.atualizados++
                } else {
                    Write-Log ('ERRO: atualizar_calendario_emissor recusou ' + $nomeCanonico + ' - ' + ($upd.erro | Out-String))
                    $stats.erros++
                }
            } catch {
                Write-Log ('EXCECAO: atualizar_calendario_emissor ' + $nomeCanonico + ' - ' + $_.Exception.Message)
                $stats.erros++
            }
        }

        Remove-Item $promptPath -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds $PauseSec
    }

    $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $resultadoTxt = if ($stats.erros -gt 0) { 'PARCIAL' } else { 'OK' }
    $pendentes = $stats.stale_inicial - $stats.atualizados - $stats.mismatch - $stats.erros
    if ($pendentes -lt 0) { $pendentes = 0 }

    @{
        data = $DateTag; stale_inicial = $stats.stale_inicial; lotes = $stats.lotes
        atualizados = $stats.atualizados; pulados = $stats.pulados; mismatch = $stats.mismatch
        erros = $stats.erros; tokens_total_est = $stats.tokens_total
    } | ConvertTo-Json | Set-Content $MetricsFile -Encoding UTF8

    Write-Log ('FIM: agenda-semanal | stale_inicial=' + $stats.stale_inicial + ' atualizados=' + $stats.atualizados + ' pulados=' + $stats.pulados + ' mismatch=' + $stats.mismatch + ' erros=' + $stats.erros + ' lotes=' + $stats.lotes + ' tokens=' + $stats.tokens_total)
    Write-Log ('ROTINA_RESUMO|vixradar-agenda-semanal|local|' + $inicioIso + '|' + $fimIso + '|' + $resultadoTxt + '|' + $stats.atualizados + '|' + $stats.erros + '|' + $pendentes + '|' + $versaoWorker)

    if ($stats.erros -gt 0) { $exitCode = 6 }
} catch {
    Write-Log ('ERRO FATAL: ' + $_.Exception.Message)
    $exitCode = 1
}

if ($exitCode -ne 0) { exit $exitCode }
