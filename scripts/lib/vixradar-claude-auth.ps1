# vixradar-claude-auth.ps1 - Decide como o `claude -p` se autentica nas rotinas.
# ASCII puro por design: e dot-sourced por scripts que rodam sob powershell.exe 5.1.
#
# Politica, nesta ordem:
#   1. VIXRADAR_ANTHROPIC_AUTH_TOKEN  token longevo de `claude setup-token`. Nao expira em
#      24h, entao e o unico modo de assinatura que sobrevive ao Task Scheduler.
#   2. OAuth do credential store do CLI (`claude login`). Expira em ~24h.
#   3. VIXRADAR_ANTHROPIC_API_KEY     chave paga, pay-per-token. Ultimo recurso.
#
# Configurar o token longevo:
#   claude setup-token
#   [Environment]::SetEnvironmentVariable('VIXRADAR_ANTHROPIC_AUTH_TOKEN','<token>','User')
#
# Por que variavel propria e nao ANTHROPIC_AUTH_TOKEN: o incidente 73 nasceu justamente de
# um ANTHROPIC_AUTH_TOKEN herdado do registry apontando para agregador. A guarda continua
# apagando o que vem do ambiente. Token que o operador colocou na variavel propria e
# intencao explicita, e so pode chegar na API oficial porque a base URL e reescrita sempre.
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
    # 'Not logged in' entrou em 30/07 20h: o CLI usa essa mensagem quando nao ha credencial
    # NENHUMA, e 'OAuth session expired' so quando havia uma e venceu. Sem cobrir as duas, um
    # logout classificava como falha generica e a escalada de meio de execucao nao disparava.
    return ($Saida -match 'OAuth session expired|Failed to authenticate|not authenticated|Not logged in|Please run /login|Invalid API key|authentication_error|invalid_api_key')
}

function Get-VixAnthropicAuthToken {
    # Token longevo de assinatura, gerado por `claude setup-token`. Lido de uma variavel
    # PROPRIA e nunca do ANTHROPIC_AUTH_TOKEN ambiente.
    #
    # A distincao e o ponto: o incidente 73 nasceu de ANTHROPIC_AUTH_TOKEN herdado do
    # registry apontando para agregador. A guarda continua apagando o que vem do ambiente.
    # Um token que o operador colocou aqui de proposito e outra coisa, e so pode ir para a
    # API oficial, porque ANTHROPIC_BASE_URL e reescrito em toda invocacao.
    $candidatos = @(
        $env:VIXRADAR_ANTHROPIC_AUTH_TOKEN,
        [Environment]::GetEnvironmentVariable('VIXRADAR_ANTHROPIC_AUTH_TOKEN', 'User')
    )
    foreach ($c in $candidatos) { if ($c) { return $c } }
    return $null
}

function Set-VixClaudeAuthEnv {
    # Aplica o modo ja decidido. Chamar antes de CADA invocacao do claude, porque o
    # ambiente do processo pode ter sido mexido entre lotes.
    $env:ANTHROPIC_BASE_URL = 'https://api.anthropic.com'
    # Zera sempre primeiro: o que vale e o que este helper decidir, nunca o herdado.
    $env:ANTHROPIC_AUTH_TOKEN = $null
    $env:ANTHROPIC_API_KEY = $null
    if ($script:VixAuthModo -eq 'assinatura-token') {
        $env:ANTHROPIC_AUTH_TOKEN = $script:VixAuthToken
    } elseif ($script:VixAuthModo -eq 'api') {
        $env:ANTHROPIC_API_KEY = $script:VixAuthChave
    }
    # Modo 'assinatura' fica sem as duas: o CLI usa o proprio credential store do OAuth.
}

function Test-VixClaudeSonda([string]$ModeloSonda, [string]$McpConfigFile) {
    # Chamada trivial so para saber se a credencial em vigor e aceita. Devolve um objeto
    # com o resultado e a saida crua, para o chamador nomear o motivo da recusa.
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
    return [PSCustomObject]@{
        Ok    = ($code -eq 0 -and $saida -notmatch '"is_error"\s*:\s*true')
        Code  = $code
        Saida = $saida
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
    $script:VixAuthToken = Get-VixAnthropicAuthToken

    # Ordem: token longevo de assinatura, depois OAuth do credential store, depois chave
    # paga. As duas primeiras nao cobram por token, e a sonda de cada uma e gratuita: ou
    # e aceita pela assinatura, ou e recusada consumindo 0 token. Nenhuma toca a API paga.

    if ($script:VixAuthToken) {
        $script:VixAuthModo = 'assinatura-token'
        Set-VixClaudeAuthEnv
        $r = Test-VixClaudeSonda $ModeloSonda $McpConfigFile
        if ($r.Ok) {
            Write-VixAuthLog 'AUTH: token longevo de assinatura aceito - rodando sem custo por token.'
            $script:VixAuthDecidido = $true
            return $script:VixAuthModo
        }
        # Token configurado e recusado e sintoma, nao detalhe: alguem colocou ali de
        # proposito e ele parou de valer. Nomear no log em vez de degradar em silencio.
        Write-VixAuthLog 'AVISO AUTH: VIXRADAR_ANTHROPIC_AUTH_TOKEN esta configurado mas foi recusado. Regerar com `claude setup-token`.'
    }

    $script:VixAuthModo = 'assinatura'
    Set-VixClaudeAuthEnv
    $r = Test-VixClaudeSonda $ModeloSonda $McpConfigFile
    if ($r.Ok) {
        Write-VixAuthLog 'AUTH: assinatura (OAuth) respondeu - rodando sem custo por token.'
        $script:VixAuthDecidido = $true
        return $script:VixAuthModo
    }

    if ($script:VixAuthChave) {
        $script:VixAuthModo = 'api'
        $motivo = if (Test-VixClaudeAuthFailure $r.Saida) { 'sessao OAuth expirada ou deslogada' } else { ('sonda falhou exit=' + $r.Code) }
        Write-VixAuthLog ('AUTH: assinatura indisponivel (' + $motivo + '). Caindo para chave paga (pay-per-token).')
        Write-VixAuthLog 'AUTH: para voltar a assinatura, rodar `claude setup-token` (token longevo, sobrevive ao Task Scheduler) ou `claude login`.'

        # Probe a chave paga antes de confiar nela. A sonda da assinatura nao cobra token,
        # mas a da chave paga consome ~2k tokens. Custo aceitavel: a alternativa e perder
        # 120k+ tokens num lote que vai falhar com 401 em 3 retries, como em 31/07.
        Set-VixClaudeAuthEnv
        $keyProbe = Test-VixClaudeSonda $ModeloSonda $McpConfigFile
        if ($keyProbe.Ok) {
            Write-VixAuthLog 'AUTH: chave paga validada. Prosseguindo pay-per-token.'
        } else {
            $errPreview = $keyProbe.Saida -replace "[`n`r]+", ' '
            if ($errPreview.Length -gt 200) { $errPreview = $errPreview.Substring(0, 200) }
            Write-VixAuthLog ('ERRO AUTH: chave paga recusada (exit=' + $keyProbe.Code + '). ' + $errPreview)
            Write-VixAuthLog 'ERRO AUTH: nenhuma credencial disponivel. A rotina vai falhar nos lotes.'
            $script:VixAuthModo = 'nenhum'
        }
    } else {
        $script:VixAuthModo = 'nenhum'
        Write-VixAuthLog 'ERRO AUTH: assinatura indisponivel e nenhuma chave sk-ant- configurada.'
        Write-VixAuthLog 'ERRO AUTH: rodar `claude setup-token`, ou definir VIXRADAR_ANTHROPIC_API_KEY. A rotina vai falhar nos lotes.'
    }

    $script:VixAuthDecidido = $true
    Set-VixClaudeAuthEnv
    return $script:VixAuthModo
}

function Invoke-VixClaudeAuthEscalate([string]$Saida) {
    # Escalada no meio da execucao: a credencial de assinatura pode vencer durante um lote
    # longo. Troca para a chave paga e devolve $true para o chamador repetir a tentativa.
    # Sem isso a rotina perderia todos os lotes restantes, que foi o de 29-30/07.
    # Cobre os DOIS modos de assinatura: OAuth do credential store e token longevo.
    if ($script:VixAuthModo -ne 'assinatura' -and $script:VixAuthModo -ne 'assinatura-token') { return $false }
    if (-not (Test-VixClaudeAuthFailure $Saida)) { return $false }
    $modoAnterior = $script:VixAuthModo
    if (-not $script:VixAuthChave) {
        Write-VixAuthLog ('AUTH: ' + $modoAnterior + ' caiu no meio da execucao e nao ha chave paga para assumir.')
        return $false
    }
    $script:VixAuthModo = 'api'
    Set-VixClaudeAuthEnv
    Write-VixAuthLog ('AUTH: ' + $modoAnterior + ' caiu no meio da execucao. Escalado para chave paga; lotes seguintes sao pay-per-token.')
    return $true
}

function Get-VixClaudeAuthModo {
    if ($script:VixAuthModo) { return $script:VixAuthModo }
    return 'indefinido'
}
