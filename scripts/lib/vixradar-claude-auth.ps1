# vixradar-claude-auth.ps1 - Decide como o `claude -p` se autentica nas rotinas.
# ASCII puro por design: e dot-sourced por scripts que rodam sob powershell.exe 5.1.
#
# Politica: assinatura (OAuth) primeiro, chave paga so quando o OAuth nao responde.
#
# Por que existe:
#   - Ate 2026-07-30 a escolha era binaria e ficava triplicada nos tres scripts de
#     rotina. Cada correcao de auth precisava ser aplicada tres vezes, e foi assim que
#     o incidente 73 (roteamento de provedor) exigiu tres edicoes identicas.
#   - Pay-per-token puro gasta dinheiro todo dia. Assinatura pura derrubou as rotinas
#     em 29-30/07, porque o OAuth expira em ~24h e o Task Scheduler nao tem sessao
#     interativa para renovar. Nenhum dos dois extremos serve sozinho.
#
# A sondagem e gratuita nos dois desfechos: roda com ANTHROPIC_API_KEY limpa, entao ou
# passa pelo OAuth (sem custo por token) ou falha na autenticacao consumindo 0 token.
# Ela nunca toca a API paga.
#
# PROVEDOR FIXADO (incidente 73): ANTHROPIC_BASE_URL e sempre reescrito para a API
# oficial antes de qualquer chamada. Sem isso, base URL de agregador no ambiente aceita
# nome de modelo Claude e devolve outro modelo, sem erro, mantendo o carimbo no log.

Set-Variable -Name VixAuthPrefixoValido -Value 'sk-ant-' -Scope Script -Force

function Write-VixAuthLog([string]$Mensagem) {
    # Usa o Write-Log do script chamador quando existe, para a linha cair no log da
    # rotina. Fora dele (teste manual) cai no console em vez de sumir.
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $Mensagem }
    else { Write-Host $Mensagem }
}

function Get-VixAnthropicApiKey {
    # So aceita chave no formato Anthropic. Chave de agregador e recusada e registrada:
    # em 30/07 uma base URL de agregador servia deepseek-v4-flash para pedido de
    # claude-sonnet-4-6, e o log carimbava Claude.
    $candidatos = @(
        $env:VIXRADAR_ANTHROPIC_API_KEY,
        [Environment]::GetEnvironmentVariable('VIXRADAR_ANTHROPIC_API_KEY', 'User'),
        $env:ANTHROPIC_API_KEY,
        [Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY', 'User')
    )
    foreach ($c in $candidatos) {
        if ($c -and $c.StartsWith($script:VixAuthPrefixoValido)) { return $c }
        if ($c) {
            $pref = $c.Substring(0, [Math]::Min(7, $c.Length))
            Write-VixAuthLog ('AVISO: chave ignorada, prefixo ' + $pref + ' nao e Anthropic (esperado ' + $script:VixAuthPrefixoValido + ').')
        }
    }
    return $null
}

function Test-VixClaudeAuthFailure([string]$Saida) {
    # Distingue falha de credencial de qualquer outro exit != 0 (rate limit, timeout,
    # congestionamento). So falha de credencial justifica trocar de modo de auth.
    if (-not $Saida) { return $false }
    return ($Saida -match 'OAuth session expired|Failed to authenticate|not authenticated|Invalid API key|authentication_error|invalid_api_key')
}

function Set-VixClaudeAuthEnv {
    # Aplica o modo ja decidido. Chamar antes de CADA invocacao do claude, porque o
    # ambiente do processo pode ter sido mexido entre lotes.
    $env:ANTHROPIC_BASE_URL = 'https://api.anthropic.com'
    $env:ANTHROPIC_AUTH_TOKEN = $null
    if ($script:VixAuthModo -eq 'assinatura') {
        $env:ANTHROPIC_API_KEY = $null
    } else {
        $env:ANTHROPIC_API_KEY = $script:VixAuthChave
    }
}

function Initialize-VixClaudeAuth {
    # Decide UMA vez por execucao. Chamado de novo, devolve a decisao em cache, para nao
    # sondar a cada lote.
    param(
        [string]$ModeloSonda = 'claude-haiku-4-5-20251001',
        [string]$McpConfigFile
    )

    if ($script:VixAuthDecidido) { return $script:VixAuthModo }

    $script:VixAuthChave = Get-VixAnthropicApiKey

    $env:ANTHROPIC_BASE_URL = 'https://api.anthropic.com'
    $env:ANTHROPIC_AUTH_TOKEN = $null
    $env:ANTHROPIC_API_KEY = $null

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $saida = ''
    $code = 1
    try {
        # Nao usar $args: e variavel automatica do PowerShell, reatribuir confunde o binder.
        $claudeArgs = @('-p', '--model', $ModeloSonda, '--output-format', 'json', '--no-session-persistence')
        if ($McpConfigFile -and (Test-Path -LiteralPath $McpConfigFile)) {
            $claudeArgs += @('--strict-mcp-config', '--mcp-config', $McpConfigFile)
        }
        $saida = ('ok' | & claude @claudeArgs 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } catch {
        $saida = $_.Exception.Message
        $code = 1
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    $sondaOk = ($code -eq 0 -and $saida -notmatch '"is_error"\s*:\s*true')

    if ($sondaOk) {
        $script:VixAuthModo = 'assinatura'
        Write-VixAuthLog 'AUTH: assinatura (OAuth) respondeu - rodando sem custo por token.'
    } elseif ($script:VixAuthChave) {
        $script:VixAuthModo = 'api'
        $motivo = if (Test-VixClaudeAuthFailure $saida) { 'sessao OAuth expirada ou deslogada' } else { ('sonda falhou exit=' + $code) }
        Write-VixAuthLog ('AUTH: assinatura indisponivel (' + $motivo + '). Caindo para chave paga (pay-per-token).')
        Write-VixAuthLog 'AUTH: para voltar a assinatura, rodar `claude login` num terminal interativo.'
    } else {
        $script:VixAuthModo = 'nenhum'
        Write-VixAuthLog 'ERRO AUTH: assinatura indisponivel e nenhuma chave sk-ant- configurada.'
        Write-VixAuthLog 'ERRO AUTH: rodar `claude login`, ou definir VIXRADAR_ANTHROPIC_API_KEY. A rotina vai falhar nos lotes.'
    }

    $script:VixAuthDecidido = $true
    Set-VixClaudeAuthEnv
    return $script:VixAuthModo
}

function Invoke-VixClaudeAuthEscalate([string]$Saida) {
    # Escalada no meio da execucao: o OAuth pode vencer durante um lote longo. Troca para
    # a chave paga e devolve $true para o chamador repetir a tentativa. Sem isso a rotina
    # perderia todos os lotes restantes, que foi o comportamento de 29-30/07.
    if ($script:VixAuthModo -ne 'assinatura') { return $false }
    if (-not (Test-VixClaudeAuthFailure $Saida)) { return $false }
    if (-not $script:VixAuthChave) {
        Write-VixAuthLog 'AUTH: OAuth caiu no meio da execucao e nao ha chave paga para assumir.'
        return $false
    }
    $script:VixAuthModo = 'api'
    Set-VixClaudeAuthEnv
    Write-VixAuthLog 'AUTH: OAuth caiu no meio da execucao. Escalado para chave paga; lotes seguintes sao pay-per-token.'
    return $true
}

function Get-VixClaudeAuthModo {
    if ($script:VixAuthModo) { return $script:VixAuthModo }
    return 'indefinido'
}
