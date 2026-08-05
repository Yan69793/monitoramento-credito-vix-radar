# vixradar-ambient-check.ps1 - Pre-flight de ambiente para rotinas Claude.
# ASCII puro por design: dot-sourced por scripts que rodam sob powershell.exe 5.1.
#
# Detecta variaveis de ambiente que apontam para agregador de LLM ou nome de modelo
# nao-Claude. O incidente de 27/07 aconteceu porque ANTHROPIC_BASE_URL apontava para
# api.deepseek.com e os nomes de modelo Claude eram roteados para deepseek-v4-pro,
# sem erro. Esta guarda aborta antes de queimar um token.
#
# -ModeloFixadoNaChamada (2026-08-05): opt-in para chamadores imunes a roteamento por
# nome de modelo. Em 04/08 o operador fixou model=deepseek-v4-pro no ~/.claude/settings.json
# de proposito (economia no REPL, ver CLAUDE.md) e a guarda abortou o dreno da fila de
# verificacao 3x. ~22 eventos ficaram presos >12h -> verificador_ok=false -> health ok=false
# por ~24h. O ambiente estava certo; a guarda e que era larga demais PARA AQUELE chamador.
#
# Quem pode usar o switch: invocacoes que passam --model com ID COMPLETO (nao alias, entao
# a tabela ANTHROPIC_DEFAULT_*_MODEL nao e consultada) E --setting-sources project (que NAO
# carrega o ~/.claude/settings.json global - o arquivo que esta guarda inspeciona).
#
# Quem NAO pode: run_claude_routine.ps1 monta claudeArgs sem --setting-sources e com --model
# condicional. Para ele o settings.json global VALE e o check continua load-bearing. Por isso
# o default e a checagem completa: afrouxar em bloco reabriria o 27/07 justamente ali.
#
# ANTHROPIC_BASE_URL e checado SEMPRE, com ou sem switch. Esse e o vetor real do 73: com base
# URL de agregador, Haiku e Sonnet colapsam no mesmo modelo, silenciosamente.

function Test-VixClaudeAmbienteLimpo {
    param(
        # Ver cabecalho. Passe SOMENTE se a invocacao usa --model com ID completo E
        # --setting-sources project. O switch afeta APENAS os checks de nome de modelo.
        # NB: o catch do settings.json virou fail-closed para TODOS os chamadores nesta
        # mesma mudanca - isso independe do switch.
        [switch]$ModeloFixadoNaChamada
    )
    # Devolve $null se limpo, ou uma string com a violacao encontrada.
    $varsParaChecar = @(
        @{Name='ANTHROPIC_BASE_URL';       Check='BaseURL';   Esperado='api.anthropic.com'}
    )
    if (-not $ModeloFixadoNaChamada) {
        $varsParaChecar += @(
            @{Name='ANTHROPIC_MODEL';           Check='Modelo';    Esperado='claude-'},
            @{Name='ANTHROPIC_DEFAULT_HAIKU_MODEL'; Check='Modelo'; Esperado='claude-'},
            @{Name='ANTHROPIC_DEFAULT_SONNET_MODEL'; Check='Modelo'; Esperado='claude-'},
            @{Name='CLAUDE_CODE_SUBAGENT_MODEL'; Check='Modelo';    Esperado='claude-'}
        )
    }

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
            if (-not $ModeloFixadoNaChamada -and $settings.model -and $settings.model -notmatch '^claude-') {
                return "settings.json model=$($settings.model) (esperado prefixo claude-)"
            }
            if ($settings.env) {
                $envBaseUrl = $settings.env.ANTHROPIC_BASE_URL
                if ($envBaseUrl -and $envBaseUrl -notmatch 'api\.anthropic\.com') {
                    return "settings.json env.ANTHROPIC_BASE_URL=$envBaseUrl (esperado api.anthropic.com)"
                }
            }
        } catch {
            # FAIL-CLOSED. A versao anterior engolia o erro e devolvia "ambiente limpo":
            # settings.json corrompido apontando para agregador PASSAVA pela guarda.
            # Buraco real, nao teorico: o hook que mantem esse arquivo
            # (guard-settings-json.ps1) ja foi visto morrendo com ParserError - guarda de
            # escrita quebrada somada a guarda de leitura fail-open e uma janela aberta.
            return "settings.json ilegivel ($($_.Exception.Message)) - nao da para validar roteamento"
        }
    }

    return $null
}

function Get-VixModeloEnvInfo {
    # Observabilidade pura: NUNCA aborta, so descreve. Existe porque
    # -ModeloFixadoNaChamada tira os nomes de modelo do caminho de abort; sem este
    # relato o operador trocaria falso-positivo por ponto cego. Se um dia o roteamento
    # por alias voltar a morder, o log tem o valor que estava em vigor na hora.
    $vars = @('ANTHROPIC_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL',
              'ANTHROPIC_DEFAULT_SONNET_MODEL','CLAUDE_CODE_SUBAGENT_MODEL')
    $achados = @()
    foreach ($n in $vars) {
        $escopo = 'User'
        $valor = [Environment]::GetEnvironmentVariable($n, 'User')
        if (-not $valor) { $escopo = 'Machine'; $valor = [Environment]::GetEnvironmentVariable($n, 'Machine') }
        if (-not $valor) { $escopo = 'Process'; $valor = (Get-Item -Path "Env:$n" -ErrorAction SilentlyContinue).Value }
        if ($valor -and $valor -notmatch '^claude-') { $achados += ($n + '=' + $valor + ' (' + $escopo + ')') }
    }
    $settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($settings.model -and $settings.model -notmatch '^claude-') {
                $achados += ('settings.json model=' + $settings.model)
            }
        } catch {
            $achados += 'settings.json ilegivel'
        }
    }
    if ($achados.Count -eq 0) { return $null }
    return ($achados -join '; ')
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
