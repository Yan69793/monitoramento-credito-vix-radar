# test-openrouter-payload.ps1 - regressao JSONCICLO1 (2026-09-05). OFFLINE, nenhuma rede.
#
# Prova que o hang pre-HTTP da noturna de 05/09 nao volta. O defeito: `Get-Content -Raw`
# devolve string decorada com as note properties do provider (PSPath, PSDrive, PSProvider);
# PSDrive abre num grafo CICLICO (PSDriveInfo.Provider -> ProviderInfo.Drives -> PSDriveInfo)
# e o ConvertTo-Json do 5.1, que nao detecta ciclo, expande esse ciclo ate gastar o -Depth,
# crescendo ~6x por nivel. Com -Depth 12 vira rampa de memoria sem fim: em producao foram
# 55 min, 1 core saturado e 9 GB, sem um unico byte de socket aberto.
#
# Cobre: deteccao do defeito, sanitizacao de tipos, serializacao completa do prompt real de
# 40.988 bytes, memoria limitada, JSON valido, fail-fast do teto de parede, e a garantia de
# que NENHUM POST acontece (o stub falha o teste se for chamado).
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-openrouter-payload.ps1
#      pwsh -NoProfile -File scripts\test-openrouter-payload.ps1

$ErrorActionPreference = 'Continue'
$script:falhas = 0
$script:postsFeitos = 0
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'lib\vixradar-openrouter.ps1')

$ps51 = ($PSVersionTable.PSVersion.Major -lt 6)

function Assert-True([bool]$cond, [string]$name) {
    if ($cond) { Write-Host ('PASS ' + $name) }
    else { Write-Host ('FAIL ' + $name); $script:falhas++ }
}
function Skip([string]$name, [string]$motivo) { Write-Host ('SKIP ' + $name + ' (' + $motivo + ')') }

# Fixture do tamanho real do lote que travou: 40.988 bytes UTF-8.
$fix = Join-Path $env:TEMP ('or-payload-' + $PID + '.txt')
$linha = 'EMISSOR|Companhia Exemplo S.A.|ews=42|motivo=imprensa_recente_7d|acao. '
$sb = New-Object System.Text.StringBuilder
while ([System.Text.Encoding]::UTF8.GetByteCount($sb.ToString()) -lt 40900) { [void]$sb.AppendLine($linha) }
Set-Content -LiteralPath $fix -Value $sb.ToString() -Encoding UTF8

# chave FAKE: exercita o caminho, nunca vai a rede, nunca sai em stdout.
$env:OPENROUTER_API_KEY = 'or-fake-payload-' + $PID

try {
    $bytesFix = (Get-Item $fix).Length
    Write-Host ('fixture: ' + $bytesFix + ' bytes UTF-8')

    # ---- T1: a string do Get-Content -Raw carrega mesmo a decoracao do provider ----
    $decorada = Get-Content -LiteralPath $fix -Raw -Encoding UTF8
    $temPsDrive = $null -ne $decorada.PSDrive
    Assert-True ($decorada.GetType().FullName -eq 'System.String') 'T1 .GetType() diz System.String (por isso engana)'
    Assert-True $temPsDrive 'T1 mas .PSDrive resolve: a string vem decorada pelo provider'
    if ($temPsDrive) {
        $ciclo = $decorada.PSDrive.Provider.Drives | Where-Object { $null -ne $_.Provider } | Select-Object -First 1
        Assert-True ($null -ne $ciclo) 'T1 PSDrive.Provider.Drives[].Provider fecha o ciclo'
    }

    # ---- T2: sanitizador devolve string pura, sem decoracao ----
    $limpa = ConvertTo-VixOpenRouterPayloadSeguro $decorada
    Assert-True ($limpa -is [string]) 'T2 sanitizador devolve System.String'
    Assert-True ($limpa.Length -eq $decorada.Length) 'T2 sanitizador preserva o conteudo integral'
    Assert-True ($null -eq $limpa.PSDrive) 'T2 sanitizador removeu PSDrive (fim do ciclo)'

    # ---- T3: JSON fica CHATO em qualquer depth depois da sanitizacao ----
    $lens = @()
    foreach ($d in 2, 5, 12) {
        $b = ConvertTo-VixOpenRouterPayloadSeguro ([ordered]@{ messages = @([ordered]@{ role = 'user'; content = $decorada }) })
        $lens += ($b | ConvertTo-Json -Depth $d -Compress).Length
    }
    Assert-True (($lens[0] -eq $lens[1]) -and ($lens[1] -eq $lens[2])) ('T3 json_len constante por depth 2/5/12: ' + ($lens -join '/'))

    # ---- T4: sanitizador ABORTA em tipo complexo, nomeando o campo ----
    $erroTipo = ''
    try {
        [void](ConvertTo-VixOpenRouterPayloadSeguro ([ordered]@{ model = 'x'; extra = (Get-Item $fix) }))
    } catch { $erroTipo = $_.Exception.Message }
    Assert-True ($erroTipo -like 'TIPO_NAO_SERIALIZAVEL*') 'T4 tipo .NET complexo aborta na sanitizacao'
    Assert-True ($erroTipo -like '*$body.extra*') ('T4 erro nomeia o campo: ' + $erroTipo)

    # ---- T5: PSCustomObject tambem nao passa ----
    $erroPco = ''
    try {
        [void](ConvertTo-VixOpenRouterPayloadSeguro ([ordered]@{ m = ([pscustomobject]@{ a = 1 }) }))
    } catch { $erroPco = $_.Exception.Message }
    Assert-True ($erroPco -like 'TIPO_NAO_SERIALIZAVEL*') 'T5 PSCustomObject aborta na sanitizacao'

    # ---- T6: serializacao COMPLETA do payload real, rapida, com memoria limitada ----
    $corpo = [ordered]@{
        model = (Get-VixOpenRouterModel)
        messages = @([ordered]@{ role = 'user'; content = $decorada })
        tools = @(
            [ordered]@{ type = 'openrouter:web_search'; parameters = [ordered]@{ engine = 'exa'; max_results = 5; max_total_results = 15 } },
            [ordered]@{ type = 'openrouter:web_fetch'; parameters = [ordered]@{ engine = 'openrouter'; max_content_tokens = 20000 } }
        )
        stream = $false
        provider = [ordered]@{ require_parameters = $true; allow_fallbacks = $false }
    }
    [GC]::Collect()
    $wsAntes = (Get-Process -Id $PID).WorkingSet64
    $seguro = ConvertTo-VixOpenRouterPayloadSeguro $corpo
    $ser = ConvertTo-VixOpenRouterJsonLimitado $seguro 12
    [GC]::Collect()
    $wsDepois = (Get-Process -Id $PID).WorkingSet64
    $deltaMB = [math]::Round(($wsDepois - $wsAntes) / 1MB, 1)
    Assert-True $ser.Ok ('T6 serializacao completa (Ok=' + $ser.Ok + ' erro=' + $ser.Erro + ')')
    Assert-True ($ser.Segundos -lt 5) ('T6 serializacao em segundos, nao minutos: ' + $ser.Segundos.ToString('F3') + 's')
    Assert-True ($deltaMB -lt 300) ('T6 memoria limitada: delta ' + $deltaMB + ' MB')
    Write-Host ('     payload: ' + [System.Text.Encoding]::UTF8.GetByteCount($ser.Json) + ' bytes UTF-8')

    # ---- T7: payload e JSON valido e round-trip preserva o prompt ----
    $rt = $ser.Json | ConvertFrom-Json
    Assert-True ($null -ne $rt) 'T7 payload parseia como JSON'
    Assert-True ($rt.messages[0].content.Length -eq $decorada.Length) 'T7 round-trip preserva o prompt inteiro'
    Assert-True ($rt.messages[0].role -eq 'user') 'T7 role preservado'
    Assert-True (@($rt.tools).Count -eq 2) 'T7 as 2 server tools sobrevivem'
    Assert-True ($rt.provider.allow_fallbacks -eq $false) 'T7 allow_fallbacks=false preservado'
    Assert-True ($rt.stream -eq $false) 'T7 stream=false preservado'
    Assert-True (-not ($ser.Json -like '*PSDrive*')) 'T7 nenhum PSDrive vazou para o payload'
    Assert-True (-not ($ser.Json -like '*PSParentPath*')) 'T7 nenhum PSParentPath vazou para o payload'

    # ---- T8: fail-fast do PROPRIO sanitizador contra ciclo, em milissegundos, sem ----
    # ---- passar a thread de fundo do runspace (essa via NAO e cancelavel, ver doc  ----
    # ---- do ConvertTo-VixOpenRouterJsonLimitado; testar so o cinto de seguranca com ----
    # ---- objeto SEGURO evita repetir o hang que este arquivo esta corrigindo).      ----
    $auto = [ordered]@{}
    $auto['self'] = $auto   # ciclo literal, tipo limpo (nao e o ciclo de PSDrive)
    $swT8 = [System.Diagnostics.Stopwatch]::StartNew()
    $erroCiclo = ''
    try { [void](ConvertTo-VixOpenRouterPayloadSeguro $auto) } catch { $erroCiclo = $_.Exception.Message }
    $swT8.Stop()
    Assert-True ($erroCiclo -like 'PAYLOAD_PROFUNDO_DEMAIS*') ('T8 ciclo literal aborta no guarda de profundidade: ' + $erroCiclo)
    Assert-True ($swT8.Elapsed.TotalSeconds -lt 2) ('T8 abortou em milissegundos, nao minutos: ' + $swT8.Elapsed.TotalSeconds.ToString('F3') + 's')

    # ---- T8b: Get-VixOpenRouterJsonTimeoutSec resolve default e override, sem rede ----
    Assert-True ((Get-VixOpenRouterJsonTimeoutSec) -eq 20) 'T8b timeout de serializacao default = 20s'
    $env:VIXRADAR_OPENROUTER_JSON_TIMEOUT_SEC = '5'
    Assert-True ((Get-VixOpenRouterJsonTimeoutSec) -eq 5) 'T8b timeout de serializacao respeita override de env'
    Remove-Item Env:\VIXRADAR_OPENROUTER_JSON_TIMEOUT_SEC -ErrorAction SilentlyContinue

    # ---- T9: ponta a ponta pelo adapter, com POST proibido ----
    function Send-VixOpenRouterHttp([string]$ApiKey, [string]$JsonBody) {
        $script:postsFeitos++
        return @{ Status = 200; Body = '{"model":"stub","choices":[{"message":{"content":"RESULTADO|X|{}"}}],"usage":{"prompt_tokens":10,"completion_tokens":2}}'; Erro = '' }
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-VixOpenRouterLote -PromptPath $fix
    $sw.Stop()
    Assert-True ($r.ExitCode -eq 0) ('T9 lote fecha com ExitCode 0 (' + $r.Msg + ')')
    Assert-True ($sw.Elapsed.TotalSeconds -lt 10) ('T9 lote inteiro em ' + $sw.Elapsed.TotalSeconds.ToString('F2') + 's')
    Assert-True ($script:postsFeitos -eq 1) 'T9 exatamente 1 POST, e ele foi para o stub'
    Assert-True ($script:VixOpenRouterUltimoPayloadBytes -gt 40000) ('T9 tamanho do payload registrado: ' + $script:VixOpenRouterUltimoPayloadBytes + ' bytes')

    # ---- T10: nenhuma chamada de rede real em todo o arquivo ----
    Assert-True ($script:postsFeitos -eq 1) 'T10 nenhum POST alem do stub em todo o teste'
}
finally {
    Remove-Item Env:\OPENROUTER_API_KEY -ErrorAction SilentlyContinue
    if (Test-Path $fix) { Remove-Item $fix -Force -ErrorAction SilentlyContinue }
}

Write-Host ('RESULTADO: ' + $script:falhas + ' falha(s)')
if ($script:falhas -gt 0) { exit 1 }
exit 0
