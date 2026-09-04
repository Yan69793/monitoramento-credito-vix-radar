# vixradar-claude-auth.ps1 - Decide como o `claude -p` se autentica nas rotinas.
# ASCII puro por design: e dot-sourced por scripts que rodam sob powershell.exe 5.1.
#
# Politica, nesta ordem:
#   1. VIXRADAR_ANTHROPIC_AUTH_TOKEN  token longevo de `claude setup-token` (OAuth de um ano
#      pela doc oficial). Nao vence em 24h, entao e o unico modo de assinatura que
#      sobrevive ao Task Scheduler. Vencimento: registrar SOMENTE a data que o operador
#      informar (campo TOKEN_LONGEVO_VENCE, yyyy-MM-dd, em logs\routines\custo-config.json);
#      nunca inferir da data de emissao.
#   2. OAuth do credential store do CLI (`claude login`). Expira em ~24h.
#   3. VIXRADAR_ANTHROPIC_API_KEY     chave paga, pay-per-token. Ultimo recurso.
#
# TOKENVAR1 (2026-09-02): o token longevo entra no processo como CLAUDE_CODE_OAUTH_TOKEN,
# a variavel que o CLI documenta para o token de `setup-token` (precedencia 5, acima do
# OAuth de /login). ANTHROPIC_AUTH_TOKEN e Bearer cru para gateway (precedencia 2) e
# recusava o token de assinatura: o modo assinatura-token nunca tinha sido aceito em
# log nenhum ate esta data. --bare nao le CLAUDE_CODE_OAUTH_TOKEN; as rotinas nao usam --bare.
#
# Configurar o token longevo (valor nunca em argumento de linha de comando nem no chat):
#   claude setup-token
#   $t = Read-Host -AsSecureString 'Token do claude setup-token'
#   [Environment]::SetEnvironmentVariable('VIXRADAR_ANTHROPIC_AUTH_TOKEN', [System.Net.NetworkCredential]::new('', $t).Password, 'User')
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
    # Remove-Item elimina a variavel do bloco de ambiente do processo. Atribuir $null
    # deixa string vazia, que o binario nativo claude.exe pode tratar como "ausente"
    # e resolver pelo registro do Windows, onde ANTHROPIC_AUTH_TOKEN de agregador
    # (OpenRouter/DeepSeek) contamina a autenticacao e trava a sonda (ago/2026).
    Remove-Item Env:\ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
    # TOKENVAR1: sai do processo e so volta no modo assinatura-token, mais abaixo.
    Remove-Item Env:\CLAUDE_CODE_OAUTH_TOKEN -ErrorAction SilentlyContinue
    # Limpar variaveis de modelo que o Claude Code pode injetar no ambiente do
    # processo. Elas contaminam o Test-VixClaudeAmbienteLimpo (incidente 04/08)
    # mas nao afetam o `claude -p` com --model explicito.
    Remove-Item Env:\ANTHROPIC_DEFAULT_SONNET_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_DEFAULT_HAIKU_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:\ANTHROPIC_MODEL -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_SUBAGENT_MODEL -ErrorAction SilentlyContinue
    # Blinda contra o registro nos 3 escopos. O claude.exe le GetEnvironmentVariable
    # direto do registro User quando a variavel de processo nao existe, e o token de
    # agregador (sk-or-v1-...) no registro User envenena a autenticacao Anthropic.
    # $null DELETA a chave do registro (nao seta vazio). O token de agregador sera
    # removido permanentemente do registro User, nao da para coexistir com as rotinas.
    [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', '', 'Process')
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', '', 'Process')
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_OAUTH_TOKEN', '', 'Process')
    [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', $null, 'User')
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $null, 'User')
    # Vars de alias de modelo saem do bloco de ambiente DESTE processo, para que o
    # claude.exe filho nao as herde. Defesa em profundidade: as rotinas ja passam
    # --model com o ID completo (nao alias), entao a tabela de alias nao deveria ser
    # consultada de qualquer forma.
    # DIFERENCA DELIBERADA vs os tokens acima: NAO tocamos no registro User/Machine.
    # Esses valores sao configuracao legitima do operador para o REPL interativo
    # (economia de custo, ver CLAUDE.md). Apagar o registro quebraria o REPL dele para
    # resolver um problema que as rotinas nao tem. Foi confundir as duas coisas que
    # cegou a fila de verificacao por ~24h em 04-05/08.
    # LIMITE CONHECIDO: se a var existir no registro User, o claude.exe ainda pode
    # resolve-la de la quando ausente no processo - mesma mecanica descrita acima para
    # o token. Aqui isso e aceitavel porque --model explicito torna o alias inerte.
    foreach ($__vixModeloVar in @('ANTHROPIC_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL',
                                  'ANTHROPIC_DEFAULT_SONNET_MODEL','CLAUDE_CODE_SUBAGENT_MODEL')) {
        Remove-Item -Path "Env:\$__vixModeloVar" -ErrorAction SilentlyContinue
    }
    if ($script:VixAuthModo -eq 'assinatura-token') {
        # TOKENVAR1: variavel documentada para o token de `claude setup-token`.
        $env:CLAUDE_CODE_OAUTH_TOKEN = $script:VixAuthToken
    } elseif ($script:VixAuthModo -eq 'api') {
        $env:ANTHROPIC_API_KEY = $script:VixAuthChave
    }
    # Modo 'assinatura' fica sem as tres: o CLI usa o proprio credential store do OAuth.
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

function Get-VixSessionLimitAcao {
    # SESSIONLIMIT1 (04/09/2026): tabela de decisao PURA para limite de uso da assinatura.
    # Vive aqui, separada de Invoke-ClaudeBatch, exatamente para poder ser provada sem
    # invocar o CLI. A regra que ela codifica, na ordem:
    #   1. limite que voltou DEPOIS de ja termos esperado o reset -> escalar (esperar de novo
    #      so queimaria o teto de parede e a rotina morreria igual);
    #   2. reset ilegivel (limite semanal, "resets Sunday", sem HH:MM) -> escalar, porque
    #      esperar as cegas nao tem prazo;
    #   3. reset conhecido que CABE no tempo de espera disponivel -> esperar, porque a
    #      assinatura ja esta paga e a chave avulsa custa por token;
    #   4. reset conhecido que NAO cabe -> escalar.
    # Devolve { Acao; EsperaMin; Motivo }. Acao em:
    #   'esperar' | 'escalar_persistiu' | 'escalar_sem_reset' | 'escalar_reset_longe'
    param(
        [Parameter(Mandatory)][datetime]$Agora,
        $ResetAt,
        [Parameter(Mandatory)][double]$EsperaDisponivelMin,
        [bool]$JaEsperou = $false
    )
    if ($JaEsperou) {
        return [PSCustomObject]@{ Acao = 'escalar_persistiu'; EsperaMin = 0; Motivo = 'limite de sessao persistiu APOS a espera do reset' }
    }
    if ($null -eq $ResetAt) {
        return [PSCustomObject]@{ Acao = 'escalar_sem_reset'; EsperaMin = 0; Motivo = 'limite de sessao sem horario de reset legivel (provavel limite semanal)' }
    }
    $esperaMin = ([datetime]$ResetAt - $Agora).TotalMinutes + 2
    if ($esperaMin -le 0) { $esperaMin = 2 }
    if ($esperaMin -le $EsperaDisponivelMin) {
        return [PSCustomObject]@{ Acao = 'esperar'; EsperaMin = $esperaMin; Motivo = ('aguardar reset real ate ' + ([datetime]$ResetAt).ToString('HH:mm')) }
    }
    return [PSCustomObject]@{ Acao = 'escalar_reset_longe'; EsperaMin = $esperaMin; Motivo = ('reset em ' + [Math]::Round($esperaMin, 1) + ' min nao cabe no teto de parede (' + [Math]::Round($EsperaDisponivelMin, 1) + ' min disponiveis)') }
}

function Invoke-VixClaudeAuthEscalateForcado([string]$Motivo) {
    # ESCALADAFORCADA1 (04/09/2026). Mesmo corpo de Invoke-VixClaudeAuthEscalate, SEM a
    # exigencia de Test-VixClaudeAuthFailure.
    #
    # Existe porque ha DUAS regex de falha de auth em arquivos diferentes e elas divergem.
    # O motor (run_vixradar_varredura.ps1, $script:AuthFailRegex) cobre 'hit your.*limit' e
    # 'weekly limit'. A daqui (Test-VixClaudeAuthFailure) NAO cobre nenhuma das duas, de
    # proposito: limite de uso nao e credencial invalida, e trocar de credencial por limite
    # de sessao seria gasto desnecessario quando basta esperar o reset. O efeito colateral e
    # que o motor classificava limite de sessao como falha de auth, chamava a escalada, e a
    # lib recusava em silencio. Foi isso na noite de 03/09 as 21h38: a chave paga estava no
    # registro, o limite era de assinatura, e ninguem escalou. A rotina morreu apos
    # @(0,30,60) segundos de backoff.
    #
    # O chamador decide QUANDO forcar (limite sem reset conhecido, reset longe demais para o
    # teto de parede, ou limite que persiste depois da espera). Aqui so se executa a troca,
    # sempre com motivo registrado, porque escalada e gasto real por token.
    if ($script:VixAuthModo -ne 'assinatura' -and $script:VixAuthModo -ne 'assinatura-token') { return $false }
    $modoAnterior = $script:VixAuthModo
    if (-not $script:VixAuthChave) {
        Write-VixAuthLog ('AUTH: escalada forcada pedida (' + $Motivo + ') e nao ha chave paga para assumir.')
        return $false
    }
    $script:VixAuthModo = 'api'
    Set-VixClaudeAuthEnv
    Write-VixAuthLog ('AUTH: escalada FORCADA de ' + $modoAnterior + ' para chave paga. Motivo: ' + $Motivo + '. Lotes seguintes sao pay-per-token.')
    return $true
}

function Get-VixClaudeAuthModo {
    if ($script:VixAuthModo) { return $script:VixAuthModo }
    return 'indefinido'
}

function Send-VixRoutineAlert {
    # AUTHWEEK1 (2026-08-14): as 3 rotinas Claude Desktop tem LastTaskResult congelado,
    # o Monitor-Tasks nao as enxerga. Quando a sonda de auth detecta limite semanal ou
    # credencial invalida, a propria rotina avisa o admin via action=notificar_rotina
    # do Worker no momento do abort. Falha aqui nao derruba a rotina, so registra aviso.
    param(
        [string]$Rotina,
        [string]$Motivo,
        [string]$RoutineKey,
        [string]$WorkerUrl = 'https://api.vixradar.com/'
    )
    if (-not $RoutineKey) {
        Write-VixAuthLog 'AVISO: alerta de rotina nao enviado (rotina sem routine_key).'
        return $false
    }
    try {
        $body = @{
            action = 'notificar_rotina'
            routine_key = $RoutineKey
            rotina = $Rotina
            motivo = $Motivo
        } | ConvertTo-Json -Compress
        $r = Invoke-RestMethod -Uri $WorkerUrl -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 30
        if ($r -and $r.ok -eq $true) {
            # NOTIFYDEDUP-LOG1 (02/09): o Worker deduplica 1/dia por rotina e responde
            # {ok:true, enviado:false, dedup:true}; a lib dizia "admin notificado" mesmo assim.
            # Enviado de verdade e so enviado:true. Sem o campo (Worker antigo), assume enviado.
            if ($r.PSObject.Properties['enviado'] -and $r.enviado -ne $true) {
                Write-VixAuthLog ('ALERTA: NAO enviado, dedup do Worker (rotina=' + $Rotina + ' ja avisada hoje).')
                return $false
            }
            Write-VixAuthLog ('ALERTA: admin notificado (notificar_rotina, rotina=' + $Rotina + ').')
            return $true
        }
        Write-VixAuthLog ('AVISO: notificar_rotina respondeu ok:false. ' + ($r.erro | Out-String))
        return $false
    } catch {
        Write-VixAuthLog ('AVISO: falha ao notificar admin (notificar_rotina): ' + $_.Exception.Message)
        return $false
    }
}
