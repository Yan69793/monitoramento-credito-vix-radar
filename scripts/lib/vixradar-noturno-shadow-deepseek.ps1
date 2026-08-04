# vixradar-noturno-shadow-deepseek.ps1
# Shadow-only: Claude grava no Worker; DeepSeek reclassifica com as MESMAS fontes do Claude.
# Nunca submete ao Worker. ASCII puro (dot-source por PS 5.1 se preciso).
#
# Ativar:
#   -ShadowDeepSeek no run_vixradar_noturno_claude.ps1
#   ou env User/Process: VIXRADAR_NOTURNO_SHADOW_DEEPSEEK=1
# Chave:
#   DEEPSEEK_API_KEY ou VIXRADAR_DEEPSEEK_API_KEY (User ou Process)

Set-Variable -Name VixShadowDsApiBase -Value 'https://api.deepseek.com' -Scope Script -Force
Set-Variable -Name VixShadowDsModelFlash -Value 'deepseek-v4-flash' -Scope Script -Force
Set-Variable -Name VixShadowDsModelPro -Value 'deepseek-v4-pro' -Scope Script -Force

function Get-VixDeepSeekApiKey {
    $candidatos = @(
        $env:VIXRADAR_DEEPSEEK_API_KEY,
        [Environment]::GetEnvironmentVariable('VIXRADAR_DEEPSEEK_API_KEY', 'User'),
        $env:DEEPSEEK_API_KEY,
        [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User')
    )
    foreach ($c in $candidatos) {
        if ($c -and $c.Trim().Length -gt 10) { return $c.Trim() }
    }
    return $null
}

function Test-VixNoturnoShadowDeepSeekEnabled([switch]$SwitchOn) {
    if ($SwitchOn) { return $true }
    $v = $env:VIXRADAR_NOTURNO_SHADOW_DEEPSEEK
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable('VIXRADAR_NOTURNO_SHADOW_DEEPSEEK', 'User') }
    if (-not $v) { return $false }
    return ($v -match '^(1|true|yes|on)$')
}

function Test-VixShadowUrlPrimaria([string]$url) {
    if (-not $url) { return $false }
    $u = $url.Trim()
    if ($u -notmatch '^https?://') { return $false }
    # dominio raiz / homepage / busca generica
    if ($u -match 'https?://[^/]+/?$') { return $false }
    if ($u -match 'google\.[^/]+/search|bing\.com/search|duckduckgo\.com') { return $false }
    return $true
}

function Get-VixShadowClassif([object]$res) {
    if (-not $res) { return 'AUSENTE' }
    $c = '' + $res.classificacao_geral
    if ($c) { return $c.ToUpperInvariant() }
    if (@($res.eventos).Count -gt 0) { return 'RELEVANTE' }
    return 'ECO'
}

function Compare-VixNoturnoShadow([object]$claudeRes, [object]$dsRes) {
    $cClass = Get-VixShadowClassif $claudeRes
    $dClass = Get-VixShadowClassif $dsRes
    $cEv = @($claudeRes.eventos)
    $dEv = @($dsRes.eventos)
    $cUrlsBad = 0
    $dUrlsBad = 0
    $cMemoGap = 0
    $dMemoGap = 0
    foreach ($ev in $cEv) {
        if (($ev.classificacao -eq 'CRITICO' -or $ev.classificacao -eq 'RELEVANTE') -and -not (Test-VixShadowUrlPrimaria ('' + $ev.fonte_primaria))) {
            $cUrlsBad++
        }
        if ($ev.classificacao -eq 'CRITICO' -or $ev.classificacao -eq 'RELEVANTE') {
            if (-not ('' + $ev.memo_acontecimento).Trim()) { $cMemoGap++ }
            if (-not ('' + $ev.memo_importancia_credito).Trim()) { $cMemoGap++ }
            if (-not ('' + $ev.memo_monitorar).Trim()) { $cMemoGap++ }
        }
    }
    foreach ($ev in $dEv) {
        if (($ev.classificacao -eq 'CRITICO' -or $ev.classificacao -eq 'RELEVANTE') -and -not (Test-VixShadowUrlPrimaria ('' + $ev.fonte_primaria))) {
            $dUrlsBad++
        }
        if ($ev.classificacao -eq 'CRITICO' -or $ev.classificacao -eq 'RELEVANTE') {
            if (-not ('' + $ev.memo_acontecimento).Trim()) { $dMemoGap++ }
            if (-not ('' + $ev.memo_importancia_credito).Trim()) { $dMemoGap++ }
            if (-not ('' + $ev.memo_monitorar).Trim()) { $dMemoGap++ }
        }
    }
    $diverge = ($cClass -ne $dClass)
    $criticoDiv = $false
    if ($cClass -eq 'CRITICO' -or $dClass -eq 'CRITICO') {
        if ($cClass -ne $dClass) { $criticoDiv = $true }
    }
    return [pscustomobject]@{
        claude_classif     = $cClass
        deepseek_classif   = $dClass
        classif_match      = (-not $diverge)
        diverge            = $diverge
        critico_divergente = $criticoDiv
        claude_n_eventos   = $cEv.Count
        deepseek_n_eventos = $dEv.Count
        claude_url_invalida = $cUrlsBad
        deepseek_url_invalida = $dUrlsBad
        claude_memo_gap    = $cMemoGap
        deepseek_memo_gap  = $dMemoGap
    }
}

function New-VixNoturnoShadowPrompt {
    param(
        [object]$EmissorSlim,
        [object]$ClaudeResultado,
        [string]$JanelaInicio,
        [string]$JanelaFim,
        [string]$Fila  # rapida | aprofundada
    )
    $empJson = ($EmissorSlim | ConvertTo-Json -Depth 8 -Compress)
    $claudeJson = ($ClaudeResultado | ConvertTo-Json -Depth 12 -Compress)
    $regrasBusca = if ($Fila -eq 'aprofundada') {
        'Fila APROFUNDADA: julgue com profundidade. Nao invente busca nova. Use so fontes_consultadas e CVM abaixo.'
    } else {
        'Fila RAPIDA: triagem. Nao invente busca nova. Use so fontes_consultadas e CVM abaixo.'
    }
    return @"
Voce e o analisador SHADOW do VIX Radar (credito privado BR). NAO tem acesso a web.
Reclassifique o emissor usando APENAS: (1) dados do emissor/CVM, (2) fontes_consultadas ja coletadas pelo Claude, (3) janela.
$regrasBusca

JANELA: $JanelaInicio a $JanelaFim

REGRAS DE EVENTO (iguais ao primary):
- CRITICO/RELEVANTE exigem fonte_primaria = URL profunda (nao homepage, nao busca).
- data_evento dentro da JANELA (YYYY-MM-DD; data_aproximada true se preciso).
- Sem URL valida ou fora da janela: watchlist em cobertura_nota, eventos=[].
- CRITICO/RELEVANTE exigem memo_acontecimento, memo_importancia_credito, memo_monitorar em portugues completo.
- ECO/NENHUM: cobertura_nota 1 frase, eventos=[].
- Nao redescobrir historico REX/RJ se contexto ja traz; foque delta na janela.

SAIDA: uma unica linha, sem markdown, sem backticks, sem narrativa:
RESULTADO|<empresa exatamente como no JSON de entrada>|<json compacto>

Formato do json:
{"classificacao_geral":"CRITICO|RELEVANTE|ECO|NENHUM","sem_eventos":true,"cobertura_nota":"...","eventos":[],"fontes_consultadas":[...]}
Pode copiar/adaptar fontes_consultadas do Claude (nao invente resultados de busca).

EMISSOR:
$empJson

RESULTADO_CLAUDE (referencia de evidencias; voce pode divergir na classificacao):
$claudeJson
"@
}

function Invoke-VixDeepSeekChat {
    param(
        [string]$ApiKey,
        [string]$Model,
        [string]$UserPrompt,
        [int]$TimeoutSec = 120
    )
    $uri = $script:VixShadowDsApiBase.TrimEnd('/') + '/chat/completions'
    $bodyObj = @{
        model = $Model
        temperature = 0.2
        max_tokens = 4096
        messages = @(
            @{ role = 'system'; content = 'Voce devolve somente linha RESULTADO|empresa|json. Portugues BR nos campos de card. Sem markdown.' }
            @{ role = 'user'; content = $UserPrompt }
        )
    }
    $body = $bodyObj | ConvertTo-Json -Depth 8 -Compress
    $headers = @{
        Authorization = 'Bearer ' + $ApiKey
        'Content-Type' = 'application/json; charset=utf-8'
    }
    # Invoke-RestMethod: corpo UTF8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    try {
        $resp = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $bytes -TimeoutSec $TimeoutSec
    } catch {
        return @{ Ok = $false; Error = $_.Exception.Message; Content = $null; Usage = $null; Model = $Model }
    }
    $content = $null
    try {
        $content = '' + $resp.choices[0].message.content
    } catch {
        return @{ Ok = $false; Error = 'resposta sem choices[0].message.content'; Content = $null; Usage = $null; Model = $Model }
    }
    $usage = $null
    if ($resp.usage) {
        $usage = @{
            prompt_tokens = [int]$resp.usage.prompt_tokens
            completion_tokens = [int]$resp.usage.completion_tokens
            total_tokens = [int]$resp.usage.total_tokens
        }
    }
    return @{ Ok = $true; Error = $null; Content = $content; Usage = $usage; Model = $Model }
}

function Parse-VixShadowResultadoLine {
    param([string]$Text, [string]$EmpresaEsperada)
    if (-not $Text) { return $null }
    $lines = $Text -split "`r?`n"
    foreach ($line in $lines) {
        $t = ('' + $line).Trim()
        # strip markdown fences if model desobedece
        if ($t -match '^```') { continue }
        if ($t -match '^RESULTADO\|([^|]+)\|(\{.*\})\s*$') {
            $nome = $Matches[1].Trim()
            try {
                $obj = $Matches[2] | ConvertFrom-Json
                return @{ Empresa = $nome; Resultado = $obj; ParseOk = $true }
            } catch {
                return @{ Empresa = $nome; Resultado = $null; ParseOk = $false; ParseError = $_.Exception.Message }
            }
        }
    }
    # fallback: JSON puro no corpo
    $trim = $Text.Trim()
    if ($trim.StartsWith('{')) {
        try {
            $obj = $trim | ConvertFrom-Json
            return @{ Empresa = $EmpresaEsperada; Resultado = $obj; ParseOk = $true; ParseMode = 'json_puro' }
        } catch {}
    }
    return @{ Empresa = $EmpresaEsperada; Resultado = $null; ParseOk = $false; ParseError = 'sem linha RESULTADO|' }
}

function Get-VixShadowEmissorSlim([object]$Emp) {
    $docs = @()
    if ($Emp.cvm_documentos) {
        $docs = @($Emp.cvm_documentos | Select-Object -First 3 | ForEach-Object {
            $assunto = '' + $_.assunto
            if ($assunto.Length -gt 100) { $assunto = $assunto.Substring(0, 100) }
            [pscustomobject]@{ categoria = $_.categoria; assunto = $assunto; data = $_.data; link = $_.link }
        })
    }
    $ctx = '' + $Emp.contexto_historico
    if ($ctx.Length -gt 400) { $ctx = $ctx.Substring(0, 400) }
    return [pscustomobject]@{
        empresa = $Emp.empresa
        setor = $Emp.setor
        tier = $Emp.tier
        ews_score = $Emp.ews_score
        cvm_novos = $Emp.cvm_novos
        cvm_documentos = $docs
        contexto_historico = $ctx
    }
}

function Invoke-VixNoturnoShadowDeepSeekOne {
    param(
        [string]$ApiKey,
        [object]$Emp,
        [object]$ClaudeResultado,
        [string]$JanelaInicio,
        [string]$JanelaFim,
        [string]$Fila,          # rapida | aprofundada
        [string]$JsonlPath,
        [string]$BatchLabel
    )
    $model = if ($Fila -eq 'aprofundada') { $script:VixShadowDsModelPro } else { $script:VixShadowDsModelFlash }
    $slim = Get-VixShadowEmissorSlim $Emp
    # Claude evidencia para o shadow: fontes + classif + eventos (sem rebuscar)
    $claudePack = [pscustomobject]@{
        classificacao_geral = $ClaudeResultado.classificacao_geral
        sem_eventos = $ClaudeResultado.sem_eventos
        cobertura_nota = $ClaudeResultado.cobertura_nota
        eventos = @($ClaudeResultado.eventos)
        fontes_consultadas = @($ClaudeResultado.fontes_consultadas)
    }
    $prompt = New-VixNoturnoShadowPrompt -EmissorSlim $slim -ClaudeResultado $claudePack -JanelaInicio $JanelaInicio -JanelaFim $JanelaFim -Fila $Fila
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $api = Invoke-VixDeepSeekChat -ApiKey $ApiKey -Model $model -UserPrompt $prompt
    $sw.Stop()
    $parsed = $null
    $cmp = $null
    $status = 'ok'
    if (-not $api.Ok) {
        $status = 'api_fail'
    } else {
        $parsed = Parse-VixShadowResultadoLine -Text $api.Content -EmpresaEsperada $Emp.empresa
        if (-not $parsed.ParseOk -or -not $parsed.Resultado) {
            $status = 'parse_fail'
        } else {
            $cmp = Compare-VixNoturnoShadow -claudeRes $ClaudeResultado -dsRes $parsed.Resultado
        }
    }
    $rec = [ordered]@{
        ts = (Get-Date).ToString('o')
        batch = $BatchLabel
        empresa = $Emp.empresa
        setor = $Emp.setor
        tier = $Emp.tier
        ews_score = $Emp.ews_score
        fila = $Fila
        model_deepseek = $model
        status = $status
        api_error = $api.Error
        parse_ok = [bool]($parsed -and $parsed.ParseOk)
        parse_error = if ($parsed) { $parsed.ParseError } else { $null }
        latency_ms = $sw.ElapsedMilliseconds
        usage = $api.Usage
        compare = $cmp
        claude_classif = Get-VixShadowClassif $ClaudeResultado
        deepseek_classif = if ($parsed -and $parsed.Resultado) { Get-VixShadowClassif $parsed.Resultado } else { $null }
        deepseek_cobertura_nota = if ($parsed -and $parsed.Resultado) { '' + $parsed.Resultado.cobertura_nota } else { $null }
        deepseek_raw_excerpt = if ($api.Content) { ('' + $api.Content).Substring(0, [Math]::Min(500, ('' + $api.Content).Length)) } else { $null }
        # NAO grava no Worker - flag explicita
        submitted = $false
        shadow_only = $true
    }
    $line = ($rec | ConvertTo-Json -Depth 10 -Compress)
    try {
        Add-Content -Path $JsonlPath -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        # retry uma vez
        Start-Sleep -Milliseconds 200
        Add-Content -Path $JsonlPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    return [pscustomobject]$rec
}

function Write-VixNoturnoShadowSummary {
    param(
        [string]$JsonlPath,
        [string]$SummaryPath,
        [string]$DateTag
    )
    $rows = @()
    if (Test-Path $JsonlPath) {
        Get-Content $JsonlPath -Encoding UTF8 | ForEach-Object {
            $t = $_.Trim()
            if (-not $t) { return }
            try { $rows += ($t | ConvertFrom-Json) } catch {}
        }
    }
    $n = $rows.Count
    $parseOk = @($rows | Where-Object { $_.parse_ok }).Count
    $apiFail = @($rows | Where-Object { $_.status -eq 'api_fail' }).Count
    $diverge = @($rows | Where-Object { $_.compare -and $_.compare.diverge }).Count
    $critDiv = @($rows | Where-Object { $_.compare -and $_.compare.critico_divergente }).Count
    $match = @($rows | Where-Object { $_.compare -and $_.compare.classif_match }).Count
    $dsCrit = @($rows | Where-Object { $_.deepseek_classif -eq 'CRITICO' }).Count
    $clCrit = @($rows | Where-Object { $_.claude_classif -eq 'CRITICO' }).Count
    $dsUrlBad = 0
    $clUrlBad = 0
    $tokens = 0
    foreach ($r in $rows) {
        if ($r.compare) {
            $dsUrlBad += [int]$r.compare.deepseek_url_invalida
            $clUrlBad += [int]$r.compare.claude_url_invalida
        }
        if ($r.usage -and $r.usage.total_tokens) { $tokens += [int]$r.usage.total_tokens }
    }
    $pendAdj = @($rows | Where-Object { $_.compare -and $_.compare.critico_divergente } | ForEach-Object {
        [pscustomobject]@{
            empresa = $_.empresa
            claude = $_.claude_classif
            deepseek = $_.deepseek_classif
            pendente_adjudicacao = $true
        }
    })
    $summary = [ordered]@{
        data = $DateTag
        shadow_only = $true
        submitted_deepseek = $false
        n_comparacoes = $n
        parse_ok = $parseOk
        parse_ok_pct = if ($n -gt 0) { [Math]::Round(100.0 * $parseOk / $n, 1) } else { 0 }
        api_fail = $apiFail
        classif_match = $match
        classif_diverge = $diverge
        critico_divergente = $critDiv
        claude_critico_count = $clCrit
        deepseek_critico_count = $dsCrit
        claude_url_invalida_total = $clUrlBad
        deepseek_url_invalida_total = $dsUrlBad
        tokens_deepseek_total = $tokens
        pendente_adjudicacao = @($pendAdj)
        jsonl = $JsonlPath
        criterio_promocao = '2 semanas + critico_divergente aceitavel com adjudicacao humana; so entao hybrid B'
    }
    ($summary | ConvertTo-Json -Depth 6) | Set-Content -Path $SummaryPath -Encoding UTF8
    return [pscustomobject]$summary
}
