# test-bridge-deepseek.ps1 - BRIDGE-DEEPSEEK1 (2026-09-23) e COLETOR-PS1.
#
# Cobre tres coisas, tudo offline e sem rede:
#   1. A decisao da ponte: prazo declarado obrigatorio, virada de data, e o gate do provider.
#   2. O isolamento de namespace do endpoint deepseek no adapter - em especial que o slug do
#      OpenRouter (VIXRADAR_OPENROUTER_MODEL_FULL, que HOJE vale 'deepseek/deepseek-v4-pro-0813'
#      no ambiente do operador) nao vaze para o endpoint direto, que rejeitaria com 422.
#   3. O parser do coletor e o formato do bloco de evidencia.
#
# Prova reversa: o caso C3 falha contra o codigo anterior a esta mudanca, porque
# Test-VixLlmProviderPermiteRotina tratava 'deepseek' como reservado e devolvia $false sempre.
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-bridge-deepseek.ps1

$ErrorActionPreference = 'Continue'
$script:okN = 0
$script:fal = 0
function Assert([bool]$cond, [string]$msg) {
    if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) }
    else { $script:fal++; Write-Host ('  FALHA ' + $msg) }
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'lib\vixradar-llm-provider.ps1')
. (Join-Path $root 'lib\vixradar-openrouter.ps1')
. (Join-Path $root 'lib\vixradar-coletor.ps1')

# Fotografa o escopo User ANTES de qualquer coisa e devolve no fim. Sem isso o teste apaga
# configuracao real da maquina: VIXRADAR_LLM_PROVIDER e VIXRADAR_OPENROUTER_MODEL_FULL vivem no
# escopo User (gravados pelo DRIFTPROVIDER1) e e de la que o Task Scheduler le. Medido em 23/09:
# a primeira versao desta suite zerou os dois no User e a rotina agendada passaria a sair com
# provider none. Escopo Machine fica fora de proposito: escrever nele exige elevacao.
$script:VariaveisTeste = @('VIXRADAR_LLM_PROVIDER','VIXRADAR_LLM_ENDPOINT','VIXRADAR_DEEPSEEK_BRIDGE_ATE','VIXRADAR_OPENROUTER_MODEL_FULL')
$script:OriginaisUser = @{}
foreach ($n in $script:VariaveisTeste) { $script:OriginaisUser[$n] = [Environment]::GetEnvironmentVariable($n, 'User') }

function Limpar-Env {
    foreach ($n in $script:VariaveisTeste) {
        Remove-Item ("Env:\" + $n) -ErrorAction SilentlyContinue
        try { [Environment]::SetEnvironmentVariable($n, $null, 'User') } catch { }
    }
}
function Restaurar-Env {
    foreach ($n in $script:VariaveisTeste) {
        Remove-Item ("Env:\" + $n) -ErrorAction SilentlyContinue
        try { [Environment]::SetEnvironmentVariable($n, $script:OriginaisUser[$n], 'User') } catch { }
    }
}
Limpar-Env

Write-Host '=== A: Test-VixDeepSeekBridgeValida (prazo declarado obrigatorio) ==='
$env:VIXRADAR_DEEPSEEK_BRIDGE_ATE = $null
Assert (-not (Test-VixDeepSeekBridgeValida).ok) 'A1: sem prazo declarado a ponte NAO liga (fail-closed)'
$env:VIXRADAR_DEEPSEEK_BRIDGE_ATE = 'ontem'
Assert (-not (Test-VixDeepSeekBridgeValida).ok) 'A2: prazo invalido NAO liga'
$env:VIXRADAR_DEEPSEEK_BRIDGE_ATE = ''
Assert (-not (Test-VixDeepSeekBridgeValida).ok) 'A3: string vazia NAO liga'
$env:VIXRADAR_DEEPSEEK_BRIDGE_ATE = '2026-09-26'
Assert (Test-VixDeepSeekBridgeValida -Agora ([datetime]'2026-09-23T08:00:00')).ok 'A4: prazo futuro valido liga'
Assert (Test-VixDeepSeekBridgeValida -Agora ([datetime]'2026-09-26T23:59:00')).ok 'A5: o proprio dia declarado conta ate o fim dele'
Assert (-not (Test-VixDeepSeekBridgeValida -Agora ([datetime]'2026-09-27T00:01:00')).ok) 'A6: depois do dia declarado a ponte expira (virada de data)'
Assert (-not (Test-VixDeepSeekBridgeValida -Agora ([datetime]'2026-10-01T00:00:00')).ok) 'A7: bem depois continua expirada'
$motivoExp = (Test-VixDeepSeekBridgeValida -Agora ([datetime]'2026-09-27T00:01:00')).motivo
Assert ($motivoExp -match 'expirada') 'A8: o motivo da expiracao nomeia o problema'

Write-Host '=== B: Test-VixUsaLlmAdapterHttp (roteia para o adapter, nao para o claude CLI) ==='
$env:VIXRADAR_LLM_PROVIDER = 'openrouter'
Assert (Test-VixUsaLlmAdapterHttp) 'B1: openrouter usa o adapter HTTP'
$env:VIXRADAR_LLM_PROVIDER = 'deepseek'
Assert (Test-VixUsaLlmAdapterHttp) 'B2: deepseek usa o adapter HTTP (senao cairia no ramo claude)'
$env:VIXRADAR_LLM_PROVIDER = 'claude-subscription'
Assert (-not (Test-VixUsaLlmAdapterHttp)) 'B3: claude-subscription NAO usa o adapter'
$env:VIXRADAR_LLM_PROVIDER = 'none'
Assert (-not (Test-VixUsaLlmAdapterHttp)) 'B4: none NAO usa o adapter'
$env:VIXRADAR_LLM_PROVIDER = 'claude-manual'
Assert (-not (Test-VixUsaLlmAdapterHttp)) 'B5: claude-manual NAO usa o adapter'

Write-Host '=== C: gate do provider com deepseek (prova reversa em C3) ==='
$env:VIXRADAR_LLM_PROVIDER = 'deepseek'
$env:VIXRADAR_DEEPSEEK_BRIDGE_ATE = $null
Assert (-not (Test-VixLlmProviderPermiteRotina -OpenRouterAdapterHabilitado:$true)) 'C1: deepseek sem prazo declarado fica bloqueado'
$env:VIXRADAR_DEEPSEEK_BRIDGE_ATE = '2026-09-01'
Assert (-not (Test-VixLlmProviderPermiteRotina -OpenRouterAdapterHabilitado:$true)) 'C2: deepseek com prazo vencido fica bloqueado'
$env:VIXRADAR_DEEPSEEK_BRIDGE_ATE = '2026-12-31'
Assert (Test-VixLlmProviderPermiteRotina -OpenRouterAdapterHabilitado:$true) 'C3: deepseek com prazo valido e adapter pronto LIBERA (falha no codigo anterior)'
Assert (-not (Test-VixLlmProviderPermiteRotina -OpenRouterAdapterHabilitado:$false)) 'C4: deepseek sem adapter pronto fica bloqueado'
Assert (-not (Test-VixLlmProviderPermiteRotina -ForceClaude)) 'C5: deepseek nao vira caminho claude nem com -ForceClaude'

Write-Host '=== D: namespace do endpoint deepseek (isolamento do slug OpenRouter) ==='
$env:VIXRADAR_LLM_PROVIDER = 'deepseek'
$env:VIXRADAR_LLM_ENDPOINT = $null
Assert ((Get-VixLlmEndpoint) -eq 'openrouter') 'D1: sem VIXRADAR_LLM_ENDPOINT o endpoint e openrouter (default preservado)'
Assert (Test-VixLlmEndpointTemBusca) 'D2: openrouter TEM server tools de busca'
$env:VIXRADAR_LLM_ENDPOINT = 'deepseek'
Assert ((Get-VixLlmEndpoint) -eq 'deepseek') 'D3: VIXRADAR_LLM_ENDPOINT=deepseek troca o endpoint'
Assert (-not (Test-VixLlmEndpointTemBusca)) 'D4: deepseek NAO tem server tools de busca (o fato que motiva o coletor)'
$env:VIXRADAR_OPENROUTER_MODEL_FULL = 'deepseek/deepseek-v4-pro-0813'
$mFull = Get-VixOpenRouterModel 'FULL'
Assert ($mFull -eq 'deepseek-v4-pro') ('D5: o slug do OpenRouter NAO vaza para o endpoint direto (obtido: ' + $mFull + ')')
Assert ($mFull -notmatch '/') 'D6: o id do modelo no endpoint deepseek nao tem barra'
$mLgt = Get-VixOpenRouterModel 'LIGHT'
Assert ($mLgt -eq 'deepseek-flash') ('D7: tier LIGHT resolve para deepseek-flash (obtido: ' + $mLgt + ')')
Assert ((Get-VixLlmEndpointBase) -eq 'https://api.deepseek.com/v1/chat/completions') 'D8: a base URL aponta para a DeepSeek direta'
$h = Get-VixOpenRouterHttpHeaders
Assert (@($h.Keys).Count -eq 0) 'D9: cabecalhos do OpenRouter nao sao enviados ao endpoint deepseek'
# Stub local, sem depender de DEEPSEEK_API_KEY real nem tocar no escopo User.
function Get-VixOpenRouterApiKey { return 'sk-fake-deepseek-test' }
$chave = Get-VixOpenRouterApiKey
Assert ($chave -eq 'sk-fake-deepseek-test') 'D10: teste do endpoint deepseek usa chave fake local'
$env:VIXRADAR_LLM_ENDPOINT = 'openrouter'
Assert ((Get-VixOpenRouterModel 'FULL') -eq 'deepseek/deepseek-v4-pro-0813') 'D11: de volta ao openrouter o slug e lido normalmente (nao quebrei o caminho antigo)'

Write-Host '=== D2: payload minimo da DeepSeek, sem contrato OpenRouter ==='
$env:VIXRADAR_LLM_ENDPOINT = 'deepseek'
$promptDeepSeek = Join-Path $env:TEMP ('deepseek-body-' + $PID + '.txt')
Set-Content -Path $promptDeepSeek -Value 'Prompt offline para inspecao de JSON.' -Encoding UTF8
$script:DeepSeekBody = ''
function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
    $script:DeepSeekBody = $JsonBody
    return @{ Status = 200; Body = '{"id":"x","model":"deepseek-v4-pro","choices":[{"index":0,"message":{"role":"assistant","content":"[]"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1}}'; Erro = '' }
}
$rDeepSeek = Invoke-VixOpenRouterLote -PromptPath $promptDeepSeek -RetryDelays @(0) -FallbackRetryDelays @(0)
$bodyDeepSeek = $script:DeepSeekBody | ConvertFrom-Json
Assert ($rDeepSeek.ExitCode -eq 0) 'D12: stub da DeepSeek aceita o lote sem chave real'
Assert ($null -eq $bodyDeepSeek.PSObject.Properties['reasoning']) 'D13: body DeepSeek nao leva objeto reasoning do OpenRouter'
Assert ($null -eq $bodyDeepSeek.PSObject.Properties['provider']) 'D14: body DeepSeek nao leva objeto provider do OpenRouter'
Assert ($null -eq $bodyDeepSeek.PSObject.Properties['tools']) 'D15: body DeepSeek nao leva server tools do OpenRouter'
Assert ($bodyDeepSeek.reasoning_effort -eq 'none') 'D16: body DeepSeek usa reasoning_effort none'
Remove-Item $promptDeepSeek -Force -ErrorAction SilentlyContinue
$env:VIXRADAR_LLM_ENDPOINT = 'openrouter'

Write-Host '=== E: coletor PowerShell (parser offline) ==='
$ac = [char]0xED
$fixture = @"
<?xml version="1.0"?>
<rss version="2.0"><channel>
<item>
  <title>Emissor X negocia d$($ac)vida de R\$ 2 bi</title>
  <link>https://news.google.com/rss/articles/OPACO123</link>
  <pubDate>Mon, 21 Sep 2026 18:21:06 GMT</pubDate>
  <source url="https://valor.globo.com">Valor Econ</source>
</item>
<item>
  <title>Sem fonte declarada</title>
  <link>https://news.google.com/rss/articles/OPACO456</link>
  <pubDate>Sun, 20 Sep 2026 08:00:00 GMT</pubDate>
</item>
</channel></rss>
"@
$itens = @(ConvertFrom-VixColetorRss $fixture)
Assert ($itens.Count -eq 2) 'E1: parser le os dois itens do feed'
Assert ($itens[0].dominio -eq 'valor.globo.com') 'E2: o dominio vem de <source url>, nao do link do Google'
Assert ($itens[0].veiculo -eq 'Valor Econ') 'E3: o veiculo vem do texto de <source>'
Assert ($itens[1].dominio -eq '') 'E4: item sem <source> devolve dominio vazio em vez de quebrar'
Assert ($itens[0].titulo -match 'd.vida') 'E5: o texto acentuado sobrevive ao parser'
Assert ($itens[0].data_utc.Year -eq 2026) 'E6: pubDate vira data UTC'
Assert (@(ConvertFrom-VixColetorRss 'nao e xml').Count -eq 0) 'E7: entrada invalida devolve vazio sem lancar'
Assert (@(ConvertFrom-VixColetorRss '').Count -eq 0) 'E8: entrada vazia devolve vazio'
$vazia = Format-VixColetorEvidenciaTexto ([pscustomobject]@{ duracao_ms = 10; janela_dias = 7; cobertura = 0; total = 0; erros = @(); evidencias = @() })
Assert ($vazia -match 'EVIDENCIA_VAZIA') 'E9: coleta vazia e rotulada como vazia (nao como erro)'
Assert ($vazia -match 'proibido inventar') 'E10: a coleta vazia instrui explicitamente a nao inventar evento'
Assert ((Format-VixColetorEvidenciaTexto $null) -match 'indisponivel') 'E11: coleta nula e tratada'
$uma = Format-VixColetorEvidenciaTexto ([pscustomobject]@{ duracao_ms = 10; janela_dias = 7; cobertura = 1; total = 1; erros = @(); evidencias = @([pscustomobject]@{ familia='F2'; familia_nome='divida_emissao'; data='2026-09-21'; veiculo='Valor'; dominio='valor.globo.com'; titulo='T' }) })
Assert ($uma -match '\[F2 divida_emissao\]') 'E12: o bloco de evidencia carrega a familia'
Assert ($uma -match 'valor\.globo\.com') 'E13: o bloco de evidencia carrega o dominio (o Worker classifica por ele)'
$script:ColetorResposta = [pscustomobject]@{ Status = 503; Corpo = '' }
function Invoke-VixColetorRss { param([string]$Query, [int]$TimeoutSec = 0) return $script:ColetorResposta }
$indisponivelHttp = Get-VixColetorEvidencia -Empresa 'Emissor X' -SleepMs 0
Assert (-not $indisponivelHttp.disponivel -and $indisponivelHttp.erros.Count -eq 3) 'E14: HTTP fora de 200 marca coleta indisponivel'
Assert ((Format-VixColetorEvidenciaTexto $indisponivelHttp) -match 'EVIDENCIA_INDISPONIVEL') 'E15: HTTP fora de 200 nao vira evidencia vazia'
$script:ColetorResposta = [pscustomobject]@{ Status = 200; Corpo = 'xml quebrado' }
$indisponivelXml = Get-VixColetorEvidencia -Empresa 'Emissor X' -SleepMs 0
Assert (-not $indisponivelXml.disponivel -and $indisponivelXml.motivo_indisponibilidade -match 'XML invalido') 'E16: XML invalido marca coleta indisponivel'
$script:ColetorResposta = [pscustomobject]@{ Status = 200; Corpo = '<rss version="2.0"><channel></channel></rss>' }
$vaziaReal = Get-VixColetorEvidencia -Empresa 'Emissor X' -SleepMs 0
Assert ($vaziaReal.disponivel -and $vaziaReal.total -eq 0) 'E17: RSS valido sem item e ausencia legitima de resultado'
Assert ((Format-VixColetorEvidenciaTexto $vaziaReal) -match 'EVIDENCIA_VAZIA') 'E18: RSS valido vazio conserva o marcador EVIDENCIA_VAZIA'

Write-Host '=== F: regra de ASCII e parser dos arquivos novos ==='
$colPath = Join-Path $root 'lib\vixradar-coletor.ps1'
$bytes = [System.IO.File]::ReadAllBytes($colPath)
$naoAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
Assert ($naoAscii -eq 0) 'F1: vixradar-coletor.ps1 e ASCII puro (os acentos entram por code point)'
foreach ($p in @('lib\vixradar-llm-provider.ps1','lib\vixradar-coletor.ps1','lib\vixradar-openrouter.ps1')) {
    $e = $null; $t = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $p), [ref]$t, [ref]$e)
    Assert (@($e).Count -eq 0) ('F2: ' + $p + ' parseia sem erro')
}

Restaurar-Env
Write-Host ''
Write-Host '=== G: o escopo User ficou igual ao que era antes da suite ==='
foreach ($n in $script:VariaveisTeste) {
    $agora = [Environment]::GetEnvironmentVariable($n, 'User')
    Assert (('' + $agora) -eq ('' + $script:OriginaisUser[$n])) ('G: escopo User de ' + $n + ' preservado')
}

Write-Host ''
Write-Host ('RESULTADO: ok=' + $script:okN + ' falha=' + $script:fal)
if ($script:fal -gt 0) { exit 1 }
exit 0
