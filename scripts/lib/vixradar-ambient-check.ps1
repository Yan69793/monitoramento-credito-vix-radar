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
            if ($settings.model -and $settings.model -notmatch '^claude-') {
                return "settings.json model=$($settings.model) (esperado prefixo claude-)"
            }
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
            # Guardar saida para diagnostico
            $probeErrFile = Join-Path $env:TEMP ('wsprobe_err_' + $PID + '.txt')
            $saida | Out-File -FilePath $probeErrFile -Encoding UTF8
        }
    } catch {
        $ok = $false
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    return $ok
}
