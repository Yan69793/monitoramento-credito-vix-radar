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

function Test-VixWebSearchProbe([string]$McpConfigFile) {
    # Probe de WebSearch: busca trivial para validar que a ferramenta de busca
    # esta funcional antes de queimar tokens em lotes. Em 27/07 todas as buscas
    # retornavam "WebSearch indisponivel (modelo deepseek-v4-flash)" e os emissores
    # foram submetidos com cobertura zero. Esta sonda teria abortado em 3s.
    # Custo: ~2k tokens. Devolve $true se ok, $false se falhou.

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
            # mensagem de indisponibilidade da ferramenta de busca.
            $iAgudo = [char]0x00ED
            $falhaBusca = ($saida -match "indisponivel|indispon${iAgudo}vel|WebSearch.*indispon|search.*unavailable|ferramenta.*busca.*falha")
            if (-not $falhaBusca) {
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
        }
    } catch {
        $ok = $false
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    return $ok
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
