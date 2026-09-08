# test-openrouter-adapter.ps1 - testes unitarios OFFLINE do adapter OpenRouter (Fase B D1).
# Nenhuma rede, nenhuma chave real: o Send-VixOpenRouterHttp e sobrescrito por stub apos o
# dot-source. Cobre: normalizacao de envelope (usage claude-style), classificacao de status
# retryable, resolucao de modelo/chave, composicao do body (tools/provider), falha 401 dura
# com linha de erro SEM corpo (sem falso positivo no parser de auth Anthropic do motor) e
# retry bounded ate sucesso. Exit real. Roda no PowerShell 5.1 e no pwsh 7.
#
# Uso: pwsh -NoProfile -File scripts\test-openrouter-adapter.ps1
#      powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-openrouter-adapter.ps1

$ErrorActionPreference = 'Continue'
$script:falhas = 0
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'lib\vixradar-openrouter.ps1')

function Assert-True([bool]$cond, [string]$name) {
    if ($cond) { Write-Host ('PASS ' + $name) }
    else { Write-Host ('FAIL ' + $name); $script:falhas++ }
}

# chave FAKE so para exercitar caminho de codigo; nunca sai em stdout, nunca vai a rede.
$env:OPENROUTER_API_KEY = 'or-fake-teste-' + $PID

$promptTmp = Join-Path $env:TEMP ('or-test-prompt-' + $PID + '.txt')
Set-Content -Path $promptTmp -Value 'Prompt de teste sem rede.' -Encoding UTF8

try {
    # ---- T1: envelope com cache (prompt 100, cached 30, output 25) ----
    $resp1 = '{"id":"x","model":"deepseek/deepseek-v4-flash-latest","choices":[{"index":0,"message":{"role":"assistant","content":"RESULTADO|EMPRESA|{\"ok\":1}\nFIM: lote_ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":25,"prompt_tokens_details":{"cached_tokens":30},"server_tool_use":{"web_search_requests":2}}}' | ConvertFrom-Json
    $e1 = ConvertTo-VixOpenRouterEnvelope $resp1
    Assert-True ($e1.result -like 'RESULTADO*') 'T1 envelope: .result preservado'
    Assert-True ($e1.usage.input_tokens -eq 70) 'T1 envelope: input = prompt 100 - cached 30 = 70'
    Assert-True ($e1.usage.output_tokens -eq 25) 'T1 envelope: output = completion 25'
    Assert-True ($e1.usage.cache_read_input_tokens -eq 30) 'T1 envelope: cache_read = cached 30'
    Assert-True ($e1.usage.cache_creation_input_tokens -eq 0) 'T1 envelope: cache_creation = 0'

    # ---- T2: envelope sem cache ----
    $resp2 = '{"id":"x","model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"ola"},"finish_reason":"stop"}],"usage":{"prompt_tokens":40,"completion_tokens":9}}' | ConvertFrom-Json
    $e2 = ConvertTo-VixOpenRouterEnvelope $resp2
    Assert-True ($e2.usage.input_tokens -eq 40 -and $e2.usage.cache_read_input_tokens -eq 0) 'T2 envelope: sem cached, input = prompt 40, cache_read 0'

    # ---- T3: classificacao de status ----
    Assert-True (Test-VixOpenRouterStatusRetryable 408) 'T3 retryable: 408'
    Assert-True (Test-VixOpenRouterStatusRetryable 429) 'T3 retryable: 429'
    Assert-True (Test-VixOpenRouterStatusRetryable 500) 'T3 retryable: 500'
    Assert-True (Test-VixOpenRouterStatusRetryable 524) 'T3 retryable: 524'
    Assert-True (Test-VixOpenRouterStatusRetryable 529) 'T3 retryable: 529'
    Assert-True (Test-VixOpenRouterStatusRetryable 0) 'T3 retryable: transporte (0)'
    Assert-True (-not (Test-VixOpenRouterStatusRetryable 401)) 'T3 nao retryable: 401'
    Assert-True (-not (Test-VixOpenRouterStatusRetryable 402)) 'T3 nao retryable: 402'
    Assert-True (-not (Test-VixOpenRouterStatusRetryable 403)) 'T3 nao retryable: 403'
    Assert-True (-not (Test-VixOpenRouterStatusRetryable 400)) 'T3 nao retryable: 400'
    Assert-True (-not (Test-VixOpenRouterStatusRetryable 200)) 'T3 nao retryable: 200'

    # ---- T4: resolucao de modelo (env sobrepoe default) ----
    Assert-True ((Get-VixOpenRouterModel) -eq 'deepseek/deepseek-v4-flash-0731') 'T4 modelo: default sem env'
    $env:VIXRADAR_OPENROUTER_MODEL = 'outro/sob-env'
    Assert-True ((Get-VixOpenRouterModel) -eq 'outro/sob-env') 'T4 modelo: env VIXRADAR_OPENROUTER_MODEL sobrepoe'
    Remove-Item Env:\VIXRADAR_OPENROUTER_MODEL -ErrorAction SilentlyContinue

    # ---- T5: pronto sem chave utilizavel = falha clara e sem segredo ----
    # A chave real vive no escopo User, entao ausencia e simulada sobrescrevendo a funcao
    # de resolucao (nao o env). Apos a prova, re-dot-source restaura as funcoes originais.
    function Get-VixOpenRouterApiKey { return '' }
    $pronto = Test-VixOpenRouterPronto
    Assert-True (-not $pronto.ok) 'T5 pronto: ok=false sem chave utilizavel'
    Assert-True ($pronto.motivo -notmatch 'or-fake-teste') 'T5 pronto: motivo sem valor de chave'
    . (Join-Path $root 'lib\vixradar-openrouter.ps1')

    # ---- T6: 200 ok, body composto, tools e provider, sem segredo no body, envelope parse ----
    $script:CapturedBody = ''
    $script:HttpCalls = 0
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
        $script:HttpCalls++
        $script:CapturedBody = $JsonBody
        $body = '{"id":"x","model":"deepseek/deepseek-v4-flash-latest","choices":[{"index":0,"message":{"role":"assistant","content":"RESULTADO|ACME|{\"ok\":1}\nFIM"},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":25,"prompt_tokens_details":{"cached_tokens":30},"server_tool_use":{"web_search_requests":2}}}'
        return @{ Status = 200; Body = $body; Erro = '' }
    }
    $r6 = Invoke-VixOpenRouterLote -PromptPath $promptTmp -RetryDelays @(0, 0, 0)
    Assert-True ($r6.ExitCode -eq 0) 'T6 lote: ExitCode 0 no 200'
    Assert-True ($r6.Linhas.Count -eq 1) 'T6 lote: 1 linha de envelope'
    Assert-True ($r6.Tokens -eq 95) 'T6 lote: trabalho = input70 + output25 = 95'
    Assert-True ($script:CapturedBody -notmatch [regex]::Escape('or-fake-teste')) 'T6 seguranca: chave NAO vai no body'
    Assert-True ($script:CapturedBody -match 'openrouter:web_search') 'T6 body: tool web_search presente'
    Assert-True ($script:CapturedBody -match 'openrouter:web_fetch') 'T6 body: tool web_fetch presente'
    Assert-True ($script:CapturedBody -match '"require_parameters":true') 'T6 body: provider.require_parameters=true'
    Assert-True ($script:CapturedBody -match '"allow_fallbacks":false') 'T6 body: provider.allow_fallbacks=false (sem fallback, nunca Anthropic)'
    Assert-True ($script:CapturedBody -match [regex]::Escape('deepseek/deepseek-v4-flash-0731')) 'T6 body: model default'
    $e6 = $r6.Linhas[0] | ConvertFrom-Json
    Assert-True ($e6.result -like 'RESULTADO|ACME*') 'T6 envelope: result do texto preservado'
    Assert-True ($e6.usage.input_tokens -eq 70 -and $e6.usage.cache_read_input_tokens -eq 30) 'T6 envelope: parcelas 4 via converter'

    # ---- T7: 401 duro -> sem retry, linha de erro SEM corpo (sem falso positivo de auth Anthropic) ----
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
        $script:HttpCalls++
        return @{ Status = 401; Body = '{"error":{"message":"Invalid API key (fake test)"}}'; Erro = '' }
    }
    $script:HttpCalls = 0
    $r7 = Invoke-VixOpenRouterLote -PromptPath $promptTmp -RetryDelays @(0, 0, 0)
    Assert-True ($r7.ExitCode -ne 0) 'T7 401: ExitCode != 0'
    Assert-True ($script:HttpCalls -eq 1) 'T7 401: exatamente 1 chamada (sem retry em 401)'
    Assert-True ($r7.Linhas[0] -eq 'OPENROUTER_FALHA_COD=401') 'T7 401: linha de erro so com codigo'
    Assert-True ($r7.Linhas[0] -notmatch 'Invalid API key') 'T7 401: corpo de erro nao vaza na linha (parser de auth Anthropic do motor nao dispara)'
    Assert-True ($r7.Msg -match 'Invalid API key') 'T7 401: motivo completo vai so no Msg (log)'

    # ---- T8: 500 retrya e depois 200 ok ----
    $script:HttpCalls = 0
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
        $script:HttpCalls++
        if ($script:HttpCalls -eq 1) { return @{ Status = 500; Body = '{"error":{"message":"upstream erro (fake)"}}'; Erro = '' } }
        $body = '{"id":"x","model":"deepseek/deepseek-v4-flash-latest","choices":[{"index":0,"message":{"role":"assistant","content":"RESULTADO|ACME|{\"ok\":1}\nFIM"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}'
        return @{ Status = 200; Body = $body; Erro = '' }
    }
    $r8 = Invoke-VixOpenRouterLote -PromptPath $promptTmp -RetryDelays @(0, 0, 0)
    Assert-True ($r8.ExitCode -eq 0) 'T8 500->200: ExitCode 0 apos retry'
    Assert-True ($script:HttpCalls -eq 2) 'T8 500->200: 2 chamadas (retry bounded funcionou)'

    # ---- T9: transporte (stub lancando) retrya e falha no fim com codigo 0 ----
    $script:HttpCalls = 0
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
        $script:HttpCalls++
        return @{ Status = 0; Body = ''; Erro = 'timeout fake (teste)' }
    }
    $r9 = Invoke-VixOpenRouterLote -PromptPath $promptTmp -RetryDelays @(0, 0, 0) -FallbackRetryDelays @(0, 0, 0)
    Assert-True ($r9.ExitCode -ne 0) 'T9 timeout: ExitCode != 0 apos esgotar retries'
    Assert-True ($script:HttpCalls -eq 6) 'T9 timeout: 3 primario + 3 fallback (todas retryable)'
    Assert-True ($r9.Msg -match 'erro de transporte') 'T9 timeout: Msg explica causa'

    # ---- T10: chave ausente utilizavel (mesma tecnica de override do T5) ----
    function Get-VixOpenRouterApiKey { return '' }
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) { return @{ Status = 200; Body = '{}'; Erro = '' } }
    $r10 = Invoke-VixOpenRouterLote -PromptPath $promptTmp -RetryDelays @(0, 0, 0)
    Assert-True ($r10.ExitCode -ne 0) 'T10 sem chave: ExitCode != 0'
    Assert-True ($r10.Msg -eq 'OPENROUTER_API_KEY ausente') 'T10 sem chave: Msg identifica ausencia'
    Assert-True ($r10.Linhas[0] -eq 'OPENROUTER_FALHA_COD=1') 'T10 sem chave: linha de erro padrao'

    # ---- T11: default de modelo concreto e rejeicao de alias ~latest ----
    Assert-True ((Get-VixOpenRouterModel) -eq 'deepseek/deepseek-v4-flash-0731') 'T11 modelo: default = 0731'
    Assert-True ((Get-VixOpenRouterModel) -notmatch '~') 'T11 modelo: sem alias ~ no default'
    $env:VIXRADAR_OPENROUTER_MODEL = '~deepseek/deepseek-v4-flash-latest'
    Assert-True ((Get-VixOpenRouterModel) -eq 'deepseek/deepseek-v4-flash-0731') 'T11 modelo: alias ~ rejeitado -> default'
    $env:VIXRADAR_OPENROUTER_MODEL = 'deepseek/deepseek-v4-flash-latest'
    Assert-True ((Get-VixOpenRouterModel) -eq 'deepseek/deepseek-v4-flash-0731') 'T11 modelo: sufixo -latest rejeitado -> default'
    Remove-Item Env:\VIXRADAR_OPENROUTER_MODEL -ErrorAction SilentlyContinue

    # ---- T12: fallback default e rejeicao de fallback invalido ----
    Assert-True ((Get-VixOpenRouterFallbackModel) -eq 'deepseek/deepseek-v4-flash') 'T12 fallback: default = deepseek-v4-flash'
    $env:VIXRADAR_OPENROUTER_FALLBACK_MODEL = 'claude-sonnet-4-6'
    Assert-True ($null -eq (Get-VixOpenRouterFallbackModel)) 'T12 fallback: id sem vendor -> null'
    $env:VIXRADAR_OPENROUTER_FALLBACK_MODEL = '~deepseek/deepseek-v4-flash-latest'
    Assert-True ($null -eq (Get-VixOpenRouterFallbackModel)) 'T12 fallback: alias ~ -> null'
    Remove-Item Env:\VIXRADAR_OPENROUTER_FALLBACK_MODEL -ErrorAction SilentlyContinue

    # Restaura Get-VixOpenRouterApiKey (T10 sobrescreveu para vazio) antes dos lotes reais.
    . (Join-Path $root 'lib\vixradar-openrouter.ps1')

    # ---- T13: 429 -> retry bounded -> 200, com metadados novos ----
    $script:HttpCalls = 0
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
        $script:HttpCalls++
        if ($script:HttpCalls -eq 1) { return @{ Status = 429; Body = '{"error":{"message":"Provider returned error"}}'; Erro = ''; RetryAfter = '' } }
        $body = '{"id":"x","model":"deepseek/deepseek-v4-flash-0731","choices":[{"index":0,"message":{"role":"assistant","content":"RESULTADO|ACME|{\"ok\":1}\nFIM"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}'
        return @{ Status = 200; Body = $body; Erro = ''; RetryAfter = '' }
    }
    $r13 = Invoke-VixOpenRouterLote -PromptPath $promptTmp -RetryDelays @(0, 0, 0) -FallbackRetryDelays @(0, 0, 0)
    Assert-True ($r13.ExitCode -eq 0) 'T13 429->200: ExitCode 0'
    Assert-True ($script:HttpCalls -eq 2) 'T13 429->200: 2 chamadas (retry bounded)'
    Assert-True ($r13.Intentos -eq 2) 'T13: Intentos=2'
    Assert-True ($r13.Modelo -eq 'deepseek/deepseek-v4-flash-0731') 'T13: Modelo=0731'
    Assert-True (-not $r13.FallbackUsado) 'T13: sem fallback usado'

    # ---- T14: 400 modelo invalido -> sem retry e sem fallback ----
    $script:HttpCalls = 0
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
        $script:HttpCalls++
        return @{ Status = 400; Body = '{"error":{"message":"claude-sonnet-4-6 is not a valid model ID"}}'; Erro = ''; RetryAfter = '' }
    }
    $r14 = Invoke-VixOpenRouterLote -PromptPath $promptTmp -RetryDelays @(0, 0, 0) -FallbackRetryDelays @(0, 0, 0)
    Assert-True ($r14.ExitCode -ne 0) 'T14 400: ExitCode != 0'
    Assert-True ($script:HttpCalls -eq 1) 'T14 400: 1 chamada (sem retry/fallback)'
    Assert-True ($r14.Msg -match 'OPENROUTER_HTTP_STATUS=400') 'T14 400: status no Msg'

    # ---- T15: Retry-After respeitado e capturado ----
    Assert-True ((Get-VixOpenRouterRetryAfterSec '60' 5) -eq 60) 'T15 Retry-After: 60 segundos'
    Assert-True ((Get-VixOpenRouterRetryAfterSec '999' 5) -eq 120) 'T15 Retry-After: cap 120'
    Assert-True ((Get-VixOpenRouterRetryAfterSec 'abc' 5) -eq 5) 'T15 Retry-After: invalido -> default'
    $script:HttpCalls = 0
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
        $script:HttpCalls++
        if ($script:HttpCalls -eq 1) { return @{ Status = 429; Body = '{"error":{"message":"Provider returned error"}}'; Erro = ''; RetryAfter = '1' } }
        $body = '{"id":"x","model":"deepseek/deepseek-v4-flash-0731","choices":[{"index":0,"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1}}'
        return @{ Status = 200; Body = $body; Erro = ''; RetryAfter = '' }
    }
    $r15 = Invoke-VixOpenRouterLote -PromptPath $promptTmp -RetryDelays @(0, 0, 0) -FallbackRetryDelays @(0, 0, 0)
    Assert-True ($r15.ExitCode -eq 0) 'T15 429+RetryAfter->200: ok'
    Assert-True ($r15.RetryAfter -eq '1') 'T15 RetryAfter: capturado = 1'

    # ---- T16: fallback explicito quando primario esgota 429 ----
    $env:VIXRADAR_OPENROUTER_FALLBACK_MODEL = 'deepseek/deepseek-v4-flash'
    $script:HttpCalls = 0
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
        $script:HttpCalls++
        if ($script:HttpCalls -le 3) { return @{ Status = 429; Body = '{"error":{"message":"Provider returned error"}}'; Erro = ''; RetryAfter = '' } }
        $body = '{"id":"x","model":"deepseek/deepseek-v4-flash","choices":[{"index":0,"message":{"role":"assistant","content":"RESULTADO|ACME|{\"ok\":1}\nFIM"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}'
        return @{ Status = 200; Body = $body; Erro = ''; RetryAfter = '' }
    }
    $r16 = Invoke-VixOpenRouterLote -PromptPath $promptTmp -RetryDelays @(0, 0, 0) -FallbackRetryDelays @(0, 0, 0)
    Assert-True ($r16.ExitCode -eq 0) 'T16 fallback: ok apos esgotar primario'
    Assert-True ($script:HttpCalls -eq 4) 'T16 fallback: 3 primario + 1 fallback'
    Assert-True ($r16.FallbackUsado -eq $true) 'T16 fallback: FallbackUsado=true'
    Assert-True ($r16.Modelo -eq 'deepseek/deepseek-v4-flash') 'T16 fallback: Modelo=fallback'
    Remove-Item Env:\VIXRADAR_OPENROUTER_FALLBACK_MODEL -ErrorAction SilentlyContinue

    # ---- T17: 2xx com resultado vazio -> semantico, sem falso sucesso ----
    $env:VIXRADAR_OPENROUTER_FALLBACK_MODEL = 'invalido'
    $script:HttpCalls = 0
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
        $script:HttpCalls++
        $body = '{"id":"x","model":"deepseek/deepseek-v4-flash-0731","choices":[{"index":0,"message":{"role":"assistant","content":""},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1}}'
        return @{ Status = 200; Body = $body; Erro = ''; RetryAfter = '' }
    }
    $r17 = Invoke-VixOpenRouterLote -PromptPath $promptTmp -RetryDelays @(0, 0, 0) -FallbackRetryDelays @(0, 0, 0)
    Assert-True ($r17.ExitCode -ne 0) 'T17 vazio: ExitCode != 0'
    Assert-True ($script:HttpCalls -eq 3) 'T17 vazio: 3 tentativas (sem fallback invalido)'
    Assert-True ($r17.Linhas[0] -eq 'OPENROUTER_EMPTY_RESULT') 'T17 vazio: linha semantica'
    Remove-Item Env:\VIXRADAR_OPENROUTER_FALLBACK_MODEL -ErrorAction SilentlyContinue

. (Join-Path $root 'lib\vixradar-openrouter.ps1')
}
finally {
    Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\VIXRADAR_OPENROUTER_MODEL -ErrorAction SilentlyContinue
    if (Test-Path $promptTmp) { Remove-Item $promptTmp -Force -ErrorAction SilentlyContinue }
}

Write-Host ('RESULTADO: ' + $script:falhas + ' falha(s)')
if ($script:falhas -gt 0) { exit 1 }
exit 0
