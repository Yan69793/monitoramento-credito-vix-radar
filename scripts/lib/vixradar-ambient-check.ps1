# vixradar-ambient-check.ps1 - Pre-flight de ambiente para rotinas Claude.
# ASCII puro por design: dot-sourced por scripts que rodam sob powershell.exe 5.1.
#
# Detecta variaveis de ambiente que apontam para agregador de LLM ou nome de modelo
# nao-Claude. O incidente de 27/07 aconteceu porque ANTHROPIC_BASE_URL apontava para
# api.deepseek.com e os nomes de modelo Claude eram roteados para deepseek-v4-pro,
# sem erro. Esta guarda aborta antes de queimar um token.

function Test-VixClaudeAmbienteLimpo {
    # Devolve $null se limpo, ou uma string com a violacao encontrada.
    $varsParaChecar = @(
        @{Name='ANTHROPIC_BASE_URL';       Check='BaseURL';   Esperado='api.anthropic.com'},
        @{Name='ANTHROPIC_MODEL';           Check='Modelo';    Esperado='claude-'},
        @{Name='ANTHROPIC_DEFAULT_HAIKU_MODEL'; Check='Modelo'; Esperado='claude-'},
        @{Name='ANTHROPIC_DEFAULT_SONNET_MODEL'; Check='Modelo'; Esperado='claude-'},
        @{Name='CLAUDE_CODE_SUBAGENT_MODEL'; Check='Modelo';    Esperado='claude-'}
    )

    foreach ($v in $varsParaChecar) {
        $valor = [Environment]::GetEnvironmentVariable($v.Name, 'User')
        if (-not $valor) { $valor = [Environment]::GetEnvironmentVariable($v.Name, 'Machine') }
        if (-not $valor) { $valor = (Get-Item -Path "Env:$($v.Name)" -ErrorAction SilentlyContinue).Value }
        if (-not $valor) { continue }

        if ($v.Check -eq 'BaseURL') {
            if ($valor -notmatch [regex]::Escape($v.Esperado)) {
                return "ANTHROPIC_BASE_URL=$valor (esperado $($v.Esperado))"
            }
        } elseif ($v.Check -eq 'Modelo') {
            if ($valor -notmatch '^claude-') {
                return "$($v.Name)=$valor (esperado prefixo claude-)"
            }
        }
    }

    # Tambem checar o settings.json do Claude Code: se houver bloco 'env' ou 'model'
    # com roteamento de agregador, o problema pode vir de la (incidente 27/07).
    $settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            # NOTA: nao checamos settings.json model porque esse campo controla o REPL
            # interativo do Claude Code, nao o `claude -p`. As rotinas sempre passam
            # --model explicito e o Set-VixClaudeAuthEnv ja reescreve ANTHROPIC_BASE_URL.
            # Checar model aqui bloqueava rotina legítima (04/08: 3 execucoes perdidas).
            if ($settings.env) {
                $envBaseUrl = $settings.env.ANTHROPIC_BASE_URL
                if ($envBaseUrl -and $envBaseUrl -notmatch 'api\.anthropic\.com') {
                    return "settings.json env.ANTHROPIC_BASE_URL=$envBaseUrl (esperado api.anthropic.com)"
                }
            }
        } catch {
            # settings.json ilegivel nao e falha de ambiente - seguir.
        }
    }

    return $null
}

function ConvertTo-VixWsProbeResetAt {
    # Extrai o horario de reset do texto REAL do erro (ex.: "resets 10:40pm
    # (America/Sao_Paulo)"). Nunca chumbar horario (INCIDENTE-FRESHNESS2,
    # 02/09/2026: o retry das 21:30 abortou por 429 sem ler o reset real).
    # Hora ja passada hoje faz rollover para amanha. Texto sem HH:MM am/pm
    # (ex.: limite semanal "resets Sunday") devolve $null - reset desconhecido,
    # o chamador trata como "sem espera, direto para contingencia".
    param(
        [string]$Texto,
        [datetime]$Agora = (Get-Date)
    )
    if (-not $Texto) { return $null }
    $m = [regex]::Match($Texto, '(?i)resets\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)')
    if (-not $m.Success) { return $null }
    $hora = [int]$m.Groups[1].Value
    $min = 0
    if ($m.Groups[2].Success) { $min = [int]$m.Groups[2].Value }
    $ampm = $m.Groups[3].Value.ToLowerInvariant()
    if ($hora -eq 12) { $hora = 0 }
    if ($ampm -eq 'pm') { $hora += 12 }
    $candidato = Get-Date -Year $Agora.Year -Month $Agora.Month -Day $Agora.Day -Hour $hora -Minute $min -Second 0 -Millisecond 0
    if ($candidato -le $Agora) { $candidato = $candidato.AddDays(1) }
    return $candidato
}

function Get-VixWsProbeClassificacao {
    # Classifica a falha da sonda em 4 categorias, a partir do JSON real de
    # --output-format json (campos is_error, api_error_status, result) e do
    # texto puro. Nunca converte todo 429 em "WebSearch indisponivel"
    # (INCIDENTE-FRESHNESS2: essa conversao generica escondeu um 429 de limite
    # de sessao da assinatura atras do rotulo de ferramenta quebrada).
    # Devolve objeto { Motivo; ResetAt }. Motivo em:
    #   'ok' | 'session_limit' | 'rate_limit_transitorio' | 'websearch_indisponivel' | 'erro_desconhecido'
    param(
        [string]$Saida,
        [string]$StderrTxt,
        [datetime]$Agora = (Get-Date)
    )
    $textoCompleto = ([string]$Saida + "`n" + [string]$StderrTxt)
    $resultTexto = $null
    try {
        $json = $Saida | ConvertFrom-Json -ErrorAction Stop
        if ($json.result) { $resultTexto = [string]$json.result }
    } catch { }
    if (-not $resultTexto) { $resultTexto = $textoCompleto }

    # 429 so conta quando vem como STATUS, nao como numero solto no texto: o
    # payload do CLI carrega contadores (duration_ms, tokens) que podem conter
    # "429" por acaso e rotulariam um erro desconhecido como rate limit.
    $is429 = ($textoCompleto -match '"api_error_status"\s*:\s*429' `
        -or $textoCompleto -match '(?i)\b(status|code|http)\D{0,3}429\b' `
        -or $textoCompleto -match '(?i)429\s*(too many requests|rate.?limit)' `
        -or $textoCompleto -match '(?i)rate.?limit')
    $ehLimiteAssinatura = ($resultTexto -match '(?i)hit your (session|usage|weekly) limit')

    $iAgudo = [char]0x00ED
    $falhaBuscaIndisponivel = ($textoCompleto -match "indisponivel|indispon${iAgudo}vel|WebSearch.*indispon|search.*unavailable|ferramenta.*busca.*falha")

    if ($ehLimiteAssinatura) {
        $resetAt = ConvertTo-VixWsProbeResetAt -Texto $resultTexto -Agora $Agora
        return [PSCustomObject]@{ Motivo = 'session_limit'; ResetAt = $resetAt }
    }
    if ($is429) {
        return [PSCustomObject]@{ Motivo = 'rate_limit_transitorio'; ResetAt = $null }
    }
    if ($falhaBuscaIndisponivel) {
        return [PSCustomObject]@{ Motivo = 'websearch_indisponivel'; ResetAt = $null }
    }
    return [PSCustomObject]@{ Motivo = 'erro_desconhecido'; ResetAt = $null }
}

function Test-VixWebSearchProbe([string]$McpConfigFile) {
    # Probe de WebSearch: busca trivial para validar que a ferramenta de busca
    # esta funcional antes de queimar tokens em lotes. Em 27/07 todas as buscas
    # retornavam "WebSearch indisponivel (modelo deepseek-v4-flash)" e os emissores
    # foram submetidos com cobertura zero. Esta sonda teria abortado em 3s.
    # Custo: ~2k tokens. Devolve $true se ok, $false se falhou.
    #
    # RUN429DGN1 + INCIDENTE-FRESHNESS2 (02/09/2026): alem do booleano, deixa em
    # escopo de script $script:VixWsProbeMotivo e $script:VixWsProbe429ResetAt
    # (ver Get-VixWsProbeClassificacao), para o chamador (Invoke-VixWebSearchPreflight)
    # decidir esperar o reset em vez de abortar todo 429 como "indisponivel".

    $script:VixWsProbeMotivo = 'ok'
    $script:VixWsProbe429ResetAt = $null

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $ok = $false
    try {
        Set-VixClaudeAuthEnv
        $probePrompt = 'Qual a cotacao de fechamento do IBOVESPA hoje? Responda so com o valor numerico.'
        $stderrFile = Join-Path $env:TEMP ('wsprobe_' + $PID + '.txt')
        # RUN429DGN1: enquanto nao houver amostra real do erro 429 (session limit) da
        # sonda WebSearch, preservar a evidencia para destravar o wait-and-continue.
        # Sanitiza linhas de saida para nao gravar secret (chave de API, Bearer etc).
        $funcaoSanitizar = {
            param([string]$Texto)
            if (-not $Texto) { return '' }
            # Remove valores que parecem segredo: sk-ant-* / sk-*, Bearer <token>,
            # e qualquer bloco env=<valor> que o CLI possa ecoar.
            $Texto = [regex]::Replace($Texto, '(?i)(sk-[A-Za-z0-9\-_]{8,})', '<REDIGIDO>')
            $Texto = [regex]::Replace($Texto, '(?i)(Bearer\s+)[A-Za-z0-9\._\-]+', '$1<REDIGIDO>')
            $Texto = [regex]::Replace($Texto, '(?i)((?:ANTHROPIC_(?:API_KEY|AUTH_TOKEN)|CLAUDE_CODE_OAUTH_TOKEN|ROUTINE_KEY)\s*=\s*).+', '$1<REDIGIDO>')
            return $Texto
        }
        $claudeArgs = @('-p', '--model', 'claude-haiku-4-5-20251001', '--output-format', 'json',
            '--tools', 'WebSearch,WebFetch', '--no-session-persistence')
        if ($McpConfigFile -and (Test-Path -LiteralPath $McpConfigFile)) {
            $claudeArgs += @('--strict-mcp-config', '--mcp-config', $McpConfigFile)
        }
        $saida = ($probePrompt | & claude @claudeArgs 2>$stderrFile | Out-String)
        $code = $LASTEXITCODE

        if ($code -eq 0 -and $saida) {
            # Sonda bem-sucedida: o modelo respondeu com algo. Validar que nao e
            # mensagem de indisponibilidade da ferramenta de busca NEM um corpo de
            # falha (is_error:true / api_error_status) que o CLI tenha devolvido com
            # exit 0. INCIDENTE-FRESHNESS2 (G2): o exit code nao e confiavel para
            # decidir sucesso, so o corpo JSON e.
            $iAgudo = [char]0x00ED
            $falhaBusca = ($saida -match "indisponivel|indispon${iAgudo}vel|WebSearch.*indispon|search.*unavailable|ferramenta.*busca.*falha")
            $falhaJson = $false
            try {
                $jsonProbe = $saida | ConvertFrom-Json -ErrorAction Stop
                if ($jsonProbe.is_error -eq $true) { $falhaJson = $true }
                elseif ($jsonProbe.PSObject.Properties['api_error_status'] -and $jsonProbe.api_error_status) { $falhaJson = $true }
            } catch { }
            if (-not $falhaBusca -and -not $falhaJson) {
                $ok = $true
            }
        }
        if (-not $ok) {
            # Guardar saida para diagnostico. RUN429DGN1: alem do stdout, gravar o
            # exit code e o stderr (hoje descartados) para registrar qualquer 429 de
            # session limit com seu reset, sem redigir secret. Nome com data para
            # preservar amostras de varias execucoes no mesmo dia (guarda-nao-perde).
            $stderrTxt = ''
            if (Test-Path -LiteralPath $stderrFile) {
                try { $stderrTxt = (Get-Content -LiteralPath $stderrFile -Raw -Encoding UTF8 -ErrorAction Stop) } catch { $stderrTxt = '' }
            }
            $probeErrFile = Join-Path $env:TEMP ('wsprobe_diag_' + $(Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + $PID + '.log')
            $diagnostico = @(
                ('code=' + $code)
                '--- stdout ---'
                (& $funcaoSanitizar $saida)
                '--- stderr ---'
                (& $funcaoSanitizar $stderrTxt)
            ) -join "`n"
            $diagnostico | Out-File -FilePath $probeErrFile -Encoding UTF8

            $classificacao = Get-VixWsProbeClassificacao -Saida $saida -StderrTxt $stderrTxt
            $script:VixWsProbeMotivo = $classificacao.Motivo
            $script:VixWsProbe429ResetAt = $classificacao.ResetAt
        }
    } catch {
        $ok = $false
        if ($script:VixWsProbeMotivo -eq 'ok') { $script:VixWsProbeMotivo = 'erro_desconhecido' }
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    return $ok
}

function Invoke-VixWebSearchPreflight {
    # Pre-flight completo de WebSearch com politica de 429 (INCIDENTE-FRESHNESS2,
    # decisao do operador 03/09/2026): assinatura primeiro, espera pelo reset real
    # ate um teto, chave paga so como contingencia (nunca automatico para falha
    # que nao seja limite de sessao da propria assinatura).
    #
    # Devolve objeto { Ok; Motivo; Escalou; ExitCode; EsperouMin }.
    # $SleepFunc e $RelogioFunc existem para o teste injetar tempo controlado,
    # sem dormir de verdade nem depender do relogio real da maquina.
    param(
        [string]$McpConfigFile,
        [string]$Rotina = 'rotina',
        [string]$RoutineKey,
        [ValidateSet('ChavePaga', 'Nenhum')][string]$Fallback429 = 'ChavePaga',
        [int]$MaxEsperaMin = 120,
        [int]$MargemMin = 5,
        [int]$FatiaSeg = 60,
        [int]$MaxResondasRateLimit = 3,
        [scriptblock]$SleepFunc = { param($seg) Start-Sleep -Seconds $seg },
        [scriptblock]$RelogioFunc = { Get-Date }
    )

    if (Test-VixWebSearchProbe -McpConfigFile $McpConfigFile) {
        return [PSCustomObject]@{ Ok = $true; Motivo = 'ok'; Escalou = $false; ExitCode = 0; EsperouMin = 0 }
    }
    $motivo = $script:VixWsProbeMotivo
    $resetAt = $script:VixWsProbe429ResetAt

    if ($motivo -eq 'rate_limit_transitorio') {
        for ($i = 1; $i -le $MaxResondasRateLimit; $i++) {
            Write-Log ('PRE-FLIGHT: rate limit transitorio, re-sondando (' + $i + '/' + $MaxResondasRateLimit + ') em ' + $FatiaSeg + 's')
            & $SleepFunc $FatiaSeg
            if (Test-VixWebSearchProbe -McpConfigFile $McpConfigFile) {
                return [PSCustomObject]@{ Ok = $true; Motivo = 'ok'; Escalou = $false; ExitCode = 0; EsperouMin = [Math]::Round($i * $FatiaSeg / 60.0, 1) }
            }
        }
        Write-Log 'ERRO PRE-FLIGHT: rate limit transitorio persistente apos re-sondas'
        return [PSCustomObject]@{ Ok = $false; Motivo = 'rate_limit_transitorio'; Escalou = $false; ExitCode = 5; EsperouMin = [Math]::Round($MaxResondasRateLimit * $FatiaSeg / 60.0, 1) }
    }

    if ($motivo -eq 'websearch_indisponivel') {
        Write-Log 'ERRO PRE-FLIGHT: WebSearch indisponivel'
        return [PSCustomObject]@{ Ok = $false; Motivo = 'websearch_indisponivel'; Escalou = $false; ExitCode = 5; EsperouMin = 0 }
    }

    if ($motivo -eq 'session_limit') {
        $esperouMin = 0
        if ($resetAt) {
            $agora = & $RelogioFunc
            $waitMin = ($resetAt - $agora).TotalMinutes + $MargemMin
            if ($waitMin -gt 0 -and $waitMin -le $MaxEsperaMin) {
                Write-Log ('PRE-FLIGHT: 429 session limit, reset previsto ' + $resetAt.ToString('HH:mm') + ' BRT, aguardando ' + [Math]::Round($waitMin, 1) + ' min (teto ' + $MaxEsperaMin + ' min)')
                $restanteSeg = [int]([Math]::Ceiling($waitMin * 60))
                while ($restanteSeg -gt 0) {
                    $fatia = [Math]::Min($FatiaSeg, $restanteSeg)
                    & $SleepFunc $fatia
                    $restanteSeg -= $fatia
                }
                $esperouMin = [Math]::Round($waitMin, 1)
                if (Test-VixWebSearchProbe -McpConfigFile $McpConfigFile) {
                    Write-Log ('PRE-FLIGHT: WebSearch funcional apos espera de ' + $esperouMin + ' min')
                    return [PSCustomObject]@{ Ok = $true; Motivo = 'ok'; Escalou = $false; ExitCode = 0; EsperouMin = $esperouMin }
                }
                Write-Log 'PRE-FLIGHT: 429 session limit persiste apos o reset esperado.'
                $motivo = $script:VixWsProbeMotivo
                $resetAt = $script:VixWsProbe429ResetAt
                if ($motivo -ne 'session_limit') {
                    # Depois de esperar, a sonda falhou por outro motivo (ex.: WebSearch
                    # indisponivel de verdade). Trata pelo motivo novo, sem contingencia.
                    Write-Log ('ERRO PRE-FLIGHT: apos espera, motivo mudou para ' + $motivo)
                    return [PSCustomObject]@{ Ok = $false; Motivo = $motivo; Escalou = $false; ExitCode = 5; EsperouMin = $esperouMin }
                }
            } elseif ($waitMin -gt $MaxEsperaMin) {
                Write-Log ('PRE-FLIGHT: 429 session limit, reset previsto ' + $resetAt.ToString('HH:mm') + ' BRT, alem do teto de ' + $MaxEsperaMin + ' min - sem espera.')
            } else {
                Write-Log ('PRE-FLIGHT: 429 session limit, reset previsto ' + $resetAt.ToString('HH:mm') + ' BRT ja no passado - sem espera.')
            }
        } else {
            Write-Log 'PRE-FLIGHT: 429 session limit, reset desconhecido (limite semanal ou texto nao reconhecido) - sem espera.'
        }

        $resetTxt = 'desconhecido'
        if ($resetAt) { $resetTxt = $resetAt.ToString('HH:mm') }

        if ($Fallback429 -eq 'ChavePaga') {
            $chave = $null
            if (Get-Command Get-VixAnthropicApiKey -ErrorAction SilentlyContinue) { $chave = Get-VixAnthropicApiKey }
            if ($chave) {
                # Chave paga vive so no ambiente deste PROCESSO (Set-VixClaudeAuthEnv
                # abaixo), nunca em escopo User - o proprio Set-VixClaudeAuthEnv ja
                # apaga ANTHROPIC_API_KEY do registro User antes de aplicar o modo.
                Write-Log ('ALERTA_AUTH: 429 session limit da assinatura (reset ' + $resetTxt + '), escalando para chave paga.')
                $script:VixAuthModo = 'api'
                $script:VixAuthChave = $chave
                if (Get-Command Set-VixClaudeAuthEnv -ErrorAction SilentlyContinue) { Set-VixClaudeAuthEnv }
                if ($RoutineKey -and (Get-Command Send-VixRoutineAlert -ErrorAction SilentlyContinue)) {
                    $null = Send-VixRoutineAlert -Rotina $Rotina -Motivo ('ALERTA_AUTH: 429 session limit da assinatura (reset ' + $resetTxt + '), escalado para chave paga') -RoutineKey $RoutineKey
                }
                return [PSCustomObject]@{ Ok = $true; Motivo = 'session_limit'; Escalou = $true; ExitCode = 0; EsperouMin = $esperouMin }
            }
            Write-Log ('ERRO PRE-FLIGHT: 429 session limit (reset ' + $resetTxt + ') sem contingencia (nenhuma chave paga configurada).')
            if ($RoutineKey -and (Get-Command Send-VixRoutineAlert -ErrorAction SilentlyContinue)) {
                $null = Send-VixRoutineAlert -Rotina $Rotina -Motivo ('ERRO PRE-FLIGHT: 429 session limit (reset ' + $resetTxt + ') sem chave paga configurada') -RoutineKey $RoutineKey
            }
            return [PSCustomObject]@{ Ok = $false; Motivo = 'session_limit_sem_contingencia'; Escalou = $false; ExitCode = 5; EsperouMin = $esperouMin }
        }

        Write-Log ('ERRO PRE-FLIGHT: 429 session limit (reset ' + $resetTxt + ') - fallback desativado (-Fallback429 Nenhum).')
        if ($RoutineKey -and (Get-Command Send-VixRoutineAlert -ErrorAction SilentlyContinue)) {
            $null = Send-VixRoutineAlert -Rotina $Rotina -Motivo ('ERRO PRE-FLIGHT: 429 session limit (reset ' + $resetTxt + ') - fallback desativado') -RoutineKey $RoutineKey
        }
        return [PSCustomObject]@{ Ok = $false; Motivo = 'session_limit_sem_contingencia'; Escalou = $false; ExitCode = 5; EsperouMin = $esperouMin }
    }

    Write-Log ('ERRO PRE-FLIGHT: falha nao classificada na sonda WebSearch (motivo=' + $motivo + ')')
    return [PSCustomObject]@{ Ok = $false; Motivo = 'erro_desconhecido'; Escalou = $false; ExitCode = 5; EsperouMin = 0 }
}

function Test-VixHeadlessTools {
    # Prova real (CLI de verdade, nao stub) de que a linha de comando headless da
    # rotina (Get-VixRunnerClaudeArgs) da acesso a PowerShell/Bash, Read, Write,
    # Agent e WebSearch SEM prompt de permissao pendurado. INCIDENTE-FRESHNESS2,
    # A6 (decisao do operador 03/09/2026): "--tools default" sozinho nao basta,
    # e preciso provar disponibilidade E autorizacao antes de confiar a noturna
    # real a essa linha. $ClaudeArgsStreamJson vem de
    # Get-VixRunnerClaudeArgs -OutputFormat stream-json (contem -p, --verbose,
    # --permission-mode, --allowedTools, --add-dir, --tools/--mcp-config).
    # Nao altera nada fora de %TEMP%; nao toca o repo.
    param(
        [Parameter(Mandatory)][string[]]$ClaudeArgsStreamJson,
        [string]$ProjectRoot,
        [string]$ModeloSonda = 'claude-haiku-4-5-20251001'
    )
    $resultado = [PSCustomObject]@{
        Ok = $false; ToolsFaltando = @(); PermissionDenials = @(); ProvaPS = $false
        ProvaLeitura = $false; ProvaEscrita = $false; ProvaBusca = $false; Erro = $null
    }
    $tmp = Join-Path $env:TEMP ('vixheadless_' + $PID + '_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $readFile = Join-Path $tmp 'read_marker.txt'
    $writeFile = Join-Path $tmp 'write_marker.txt'
    $outFile = Join-Path $tmp 'stream_out.jsonl'
    $errFile = Join-Path $tmp 'stream_err.txt'
    try {
        'MARCADOR_LEITURA_OK' | Set-Content -LiteralPath $readFile -Encoding UTF8 -NoNewline
        Remove-Item -LiteralPath $writeFile -ErrorAction SilentlyContinue

        $prompt = 'Prova de capacidade headless. NAO altere nada fora de ' + $tmp + '. Faca exatamente, em ordem: ' +
            '1) rode via shell (PowerShell ou Bash) um comando que imprima a string MARCADOR_PS_OK. ' +
            '2) leia o arquivo ' + $readFile + ' e confirme que contem MARCADOR_LEITURA_OK. ' +
            '3) escreva a string MARCADOR_ESCRITA_OK (sem mais nada) no arquivo ' + $writeFile + ', criando-o. ' +
            '4) dispare UM subagente (Agent, subagent_type general-purpose) que faca UMA WebSearch trivial (a palavra teste) e devolva a palavra MARCADOR_BUSCA_OK se a busca respondeu com resultado, ou MARCADOR_BUSCA_FALHOU se nao respondeu. ' +
            'Ao final, imprima SOMENTE esta linha, sem mais nada antes ou depois: ' +
            'PROVA|<MARCADOR_PS_OK ou FALTOU>|<MARCADOR_LEITURA_OK ou FALTOU>|<MARCADOR_ESCRITA_OK ou FALTOU>|<MARCADOR_BUSCA_OK ou MARCADOR_BUSCA_FALHOU ou FALTOU>'

        $fullArgs = $ClaudeArgsStreamJson + @('--model', $ModeloSonda)
        $prevLoc = Get-Location
        if ($ProjectRoot -and (Test-Path $ProjectRoot)) { Set-Location -LiteralPath $ProjectRoot }
        try {
            $prompt | & claude @fullArgs 1>$outFile 2>$errFile
        } finally {
            Set-Location -LiteralPath $prevLoc
        }

        $toolsInit = $null
        $isErrorFinal = $null
        $permissionDenials = @()
        $textoFinal = ''
        if (Test-Path -LiteralPath $outFile) {
            foreach ($linha in (Get-Content -LiteralPath $outFile -Encoding UTF8)) {
                if (-not $linha) { continue }
                try { $obj = $linha | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                if ($obj.type -eq 'system' -and $obj.subtype -eq 'init' -and $null -eq $toolsInit) {
                    $toolsInit = @($obj.tools)
                }
                if ($obj.type -eq 'result') {
                    $isErrorFinal = $obj.is_error
                    if ($obj.permission_denials) { $permissionDenials = @($obj.permission_denials) }
                    if ($obj.result) { $textoFinal = [string]$obj.result }
                }
            }
        }

        if ($null -eq $toolsInit) {
            $resultado.Erro = 'system/init nao encontrado no stream (claude nao respondeu no formato esperado)'
            return $resultado
        }
        # 'Agent' e o nome de USUARIO/doc do dispatch de subagente; no evento
        # system/init do stream-json o CLI lista a ferramenta como 'Task' (medido
        # 03/09/2026: --allowedTools com 'Agent' ja autoriza o Task real, ProvaBusca
        # confirma dispatch funcional - so a checagem de presenca na lista precisa do
        # nome interno certo, senao acusa falta de algo que na verdade funciona).
        $exigidas = @('PowerShell_ou_Bash', 'Read', 'Write', 'Edit', 'Task_ou_Agent', 'WebSearch', 'WebFetch')
        $faltando = @()
        foreach ($t in $exigidas) {
            if ($t -eq 'PowerShell_ou_Bash') {
                if (-not (($toolsInit -contains 'PowerShell') -or ($toolsInit -contains 'Bash'))) { $faltando += 'PowerShell/Bash' }
                continue
            }
            if ($t -eq 'Task_ou_Agent') {
                if (-not (($toolsInit -contains 'Task') -or ($toolsInit -contains 'Agent'))) { $faltando += 'Agent(Task)' }
                continue
            }
            if (-not ($toolsInit -contains $t)) { $faltando += $t }
        }
        $resultado.ToolsFaltando = $faltando
        $resultado.PermissionDenials = $permissionDenials

        $m = [regex]::Match($textoFinal, 'PROVA\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)')
        if ($m.Success) {
            $resultado.ProvaPS = ($m.Groups[1].Value -match 'MARCADOR_PS_OK')
            $resultado.ProvaLeitura = ($m.Groups[2].Value -match 'MARCADOR_LEITURA_OK')
            $resultado.ProvaEscrita = ($m.Groups[3].Value -match 'MARCADOR_ESCRITA_OK')
            $resultado.ProvaBusca = ($m.Groups[4].Value -match 'MARCADOR_BUSCA_OK')
        }
        # A escrita e conferida no disco, nao so no texto que o modelo devolveu -
        # o modelo poderia alegar sucesso sem ter escrito de verdade.
        if (Test-Path -LiteralPath $writeFile) {
            $conteudoEscrita = (Get-Content -LiteralPath $writeFile -Raw -ErrorAction SilentlyContinue)
            if ($conteudoEscrita -notmatch 'MARCADOR_ESCRITA_OK') { $resultado.ProvaEscrita = $false }
        } else {
            $resultado.ProvaEscrita = $false
        }

        $resultado.Ok = ($faltando.Count -eq 0) -and ($permissionDenials.Count -eq 0) -and
            $resultado.ProvaPS -and $resultado.ProvaLeitura -and $resultado.ProvaEscrita -and $resultado.ProvaBusca -and
            ($isErrorFinal -ne $true)
    } catch {
        $resultado.Erro = $_.Exception.Message
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
    return $resultado
}

function Assert-VixLibFunctions([string[]]$RequiredFunctions) {
    # Valida que as funcoes esperadas das libs dot-sourced estao presentes.
    # Adicionado apos o incidente de 04-05/08/2026: o commit 2b025b0 removeu
    # Get-VixModeloEnvInfo e o parametro -ModeloFixadoNaChamada sem atualizar
    # todos os call sites, e o run_vixradar_verificacao_async.ps1 quebrou
    # silenciosamente por ~24h ate o health check acusar fila atrasada.
    # Esta funcao garante que esse erro nao se repete: se alguem remover uma
    # funcao e esquecer um call site, o script morre aqui com erro claro,
    # em vez de morrer no meio de um lote sem log.
    $missing = @()
    foreach ($fn in $RequiredFunctions) {
        if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
            $missing += $fn
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host "ERRO FATAL: funcao(oes) ausente(s) apos dot-source das libs: $($missing -join ', ')"
        Write-Host 'ERRO FATAL: lib/vixradar-claude-auth.ps1 ou lib/vixradar-ambient-check.ps1 nao exportam as funcoes esperadas.'
        Write-Host 'ERRO FATAL: um commit removeu/renomeou funcao sem atualizar todos os call sites. Corrija e reexecute.'
        exit 97
    }
}
