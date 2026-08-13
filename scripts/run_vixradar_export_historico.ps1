# run_vixradar_export_historico.ps1
# VIX Radar - fundacao de dados do motor preditivo (plano 2026-07-11, nota 51).
# Exporta diariamente o estado preditivo do KV de producao para data/historico/YYYY-MM-DD/,
# antes que os TTLs do KV (serie 90d, ews:hist 120d, zscores 7d, predictive 14d) apaguem o
# historico que o backtest/treino do v2 vai precisar.
#
# Conteudo do dump diario (delta, ~100-300 KB):
#   predictive.json    <- KV predictive_v1:latest (inclui model_version/schema_v)
#   zscores.json       <- KV anbima:zscores (pode faltar se TTL venceu - aviso, nao erro)
#   ews_ranking.json   <- GET publico ?op=ews (ranking de todos os emissores)
#   series_delta.json  <- ultimo ponto de mercado:serie:{empresa} por emissor
#   manifest.json      <- contagens, model_version, erros, duracao
# Domingo (ou -Seed): grava tambem series_full.json.gz (series completas, ~252 pts/emissor)
# para verificacao de integridade e backfill.
#
# Regras do projeto respeitadas: encoding UTF-8 rigido nos 2 sentidos (classe de bug mojibake
# recorrente), sem exit 0 com dump vazio, mutex contra duplicata, janela temporal UTC-3,
# log em logs/routines/. Falha de um dia e auto-recuperavel por ~90d (proximo run le a serie
# completa de novo).
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\run_vixradar_export_historico.ps1" [-Seed] [-DryRun]

param(
    [switch]$DryRun,
    [switch]$Seed
)

# 'Continue' obrigatorio: regra do CLAUDE.md do VIX Radar. Com 'Stop' o script
# aborta antes do 'exit' e o Task Scheduler reporta LastTaskResult 0 com falha real.
$ErrorActionPreference = 'Continue'

# Encoding UTF-8 nos dois sentidos (stdout do wrangler volta com acentos de nomes de emissor)
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$ProjectRoot = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito'
$ApiDir      = Join-Path $ProjectRoot 'api'
$NamespaceId = 'c6805b8d8a7b468e9f854ab4f91fb93a'   # RADAR_KV (api/wrangler.toml)
# Marca 401/403 vindo da API. Declarado aqui e nao so dentro de Get-KvValue para o script
# seguir correto caso alguem adicione Set-StrictMode depois.
$script:KvAuthFalhou = $false
$HealthUrl   = 'https://radar-credito-api.prospects-intel.workers.dev'
$LogDir      = Join-Path $ProjectRoot 'logs\routines'

# Janela temporal em UTC-3
$NowBrt  = (Get-Date).ToUniversalTime().AddHours(-3)
$DataRef = $NowBrt.ToString('yyyy-MM-dd')
$Stamp   = $NowBrt.ToString('yyyyMMdd_HHmmss')
$Domingo = ($NowBrt.DayOfWeek -eq 'Sunday')

# Garantir que CLOUDFLARE_API_TOKEN e o do registry, nao o herdado do processo.
# O env var do processo pode conter token antigo (sem permissao KV Storage) enquanto
# o registry User ja foi atualizado. O wrangler le o env var primeiro, depois o OAuth
# de ~/.wrangler/config/default.toml (que expira em ~24h). Fonte da verdade: registry.
$tokenDoRegistry = [Environment]::GetEnvironmentVariable('CLOUDFLARE_API_TOKEN', 'User')
if (-not $tokenDoRegistry) {
    $tokenDoRegistry = [Environment]::GetEnvironmentVariable('CLOUDFLARE_API_TOKEN', 'Machine')
}
if ($tokenDoRegistry) {
    $env:CLOUDFLARE_API_TOKEN = $tokenDoRegistry
} elseif (-not $env:CLOUDFLARE_API_TOKEN) {
    Write-Log 'AVISO: CLOUDFLARE_API_TOKEN ausente no registry e no ambiente. Wrangler dependera de OAuth.'
}

$OutRoot = Join-Path $ProjectRoot 'data\historico'
if ($DryRun) { $OutRoot = Join-Path $ProjectRoot 'data\historico\.dryrun' }
$OutDir  = Join-Path $OutRoot $DataRef

New-Item -ItemType Directory -Force -Path $LogDir, $OutDir | Out-Null
$LogPath = Join-Path $LogDir ("vixradar-export_{0}.log" -f $Stamp)

function Write-Log([string]$Msg) {
    $line = ('[{0}] {1}' -f ((Get-Date).ToUniversalTime().AddHours(-3).ToString('yyyy-MM-dd HH:mm:ss')), $Msg)
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    # Console.WriteLine (nao Write-Output): esta funcao e chamada dentro de funcoes que
    # retornam valor - Write-Output contaminaria o retorno via pipeline.
    [Console]::WriteLine($line)
}

function Write-JsonFile([string]$Path, [string]$Content) {
    # WriteAllText com UTF-8 sem BOM - nunca Out-File/> (mojibake em PS 5.1)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

# encodeURIComponent fiel ao JS (kvSerieKey usa encodeURIComponent(lower(trim)) - api/v4.9.149.js:10291).
# EscapeDataString do .NET diverge em !'()* - implementar a tabela do JS: nao escapa A-Za-z0-9 -_.!~*'()
function ConvertTo-UriComponent([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
    $unreserved = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*''()'
    foreach ($b in $bytes) {
        $c = [char]$b
        if ($b -lt 128 -and $unreserved.IndexOf($c) -ge 0) { [void]$sb.Append($c) }
        else { [void]$sb.AppendFormat('%{0:X2}', $b) }
    }
    return $sb.ToString()
}

function Get-KvValue([string]$Key) {
    # Retorna a string do valor, ou $null se a chave nao existir / falhar.
    # ErrorActionPreference local Continue: em PS 5.1, '2>arquivo' com Stop converte o
    # banner de stderr do npx/wrangler em NativeCommandError e mata a chamada valida.
    $ErrorActionPreference = 'Continue'
    $stderrFile = Join-Path $env:TEMP ("kvget_{0}_{1}.err" -f $PID, [System.IO.Path]::GetRandomFileName())
    try {
        Push-Location $ApiDir
        $raw = (& npx wrangler kv key get $Key --namespace-id $NamespaceId --remote 2>$stderrFile | Out-String)
        $code = $LASTEXITCODE
        Pop-Location
        if ($code -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
            $errHead = ''
            $errFull = ''
            if (Test-Path $stderrFile) {
                $errHead = ((Get-Content $stderrFile -TotalCount 2 -ErrorAction SilentlyContinue) -join ' | ')
                # Casar o padrao no arquivo inteiro, nao no $errHead. O PS 5.1 quebra o stderr
                # nativo na largura do console, e o '- 401: Unauthorized' do wrangler cai na
                # terceira linha, fora das duas que vao para o log.
                $errFull = (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue)
            }
            Write-Log ("  kvget '{0}': exit={1}, len={2}, stderr: {3}" -f $Key, $code, ([string]$raw).Trim().Length, $errHead)
            # 2026-07-30: em 30/07 01:46 esta funcao devolveu $null por 401 Unauthorized e o
            # chamador acusou "pipeline nao rodou?", mandando o diagnostico para o lado errado.
            # Falha de credencial e falha de dado exigem acoes opostas, entao separam-se aqui.
            if ($errFull -match '\b401\b|\b403\b|Unauthorized|Forbidden|Authentication') {
                $script:KvAuthFalhou = $true
                Write-Log '  CAUSA: credencial recusada pela API (401/403). Nao e ausencia de dado no KV.'
                Write-Log '  Verificar CLOUDFLARE_API_TOKEN: precisa da permissao Workers KV Storage na conta.'
            }
            return $null
        }
        # wrangler pode prefixar banner - extrair do primeiro delimitador JSON em diante
        $iObj = $raw.IndexOf('{'); $iArr = $raw.IndexOf('[')
        $i = if ($iObj -lt 0) { $iArr } elseif ($iArr -lt 0) { $iObj } else { [Math]::Min($iObj, $iArr) }
        if ($i -lt 0) { return $raw.Trim() }
        return $raw.Substring($i).Trim()
    } catch {
        Write-Log ("  kvget '{0}': EXCECAO {1}: {2}" -f $Key, $_.Exception.GetType().Name, $_.Exception.Message)
        if ((Get-Location).Path -eq $ApiDir) { Pop-Location }
        return $null
    } finally {
        Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-export-historico')
if (-not $mutex.WaitOne(0)) {
    Write-Log 'AVISO: instancia duplicada detectada - abortando esta instancia'
    exit 0
}

$t0 = Get-Date
$erros = @()
try {
    $modoFull = ($Seed -or $Domingo)
    Write-Log ("INICIO export historico - data {0} (DryRun={1}, Seed={2}, domingo={3})" -f $DataRef, [bool]$DryRun, [bool]$Seed, $Domingo)

    if ($DryRun) {
        # Fluxo sintetico: valida escrita/encoding/manifest sem tocar producao.
        # Acento construido em runtime ([char]0x00ED = i-agudo) - literal acentuado em .ps1
        # sem BOM mojibaka no parse do PS 5.1 (convencao do projeto: ps1 sem acentos).
        $iAgudo = [string][char]0x00ED
        $nomeAcentuado = 'Oncocl' + $iAgudo + 'nicas'
        $nomeAcentuado2 = 'Ra' + $iAgudo + 'zen'
        $predRaw = '{"schema_v":2,"modelo":"rule_v1+logistic_v2","run_date":"' + $DataRef + '","emissores":[{"name":"' + $nomeAcentuado + '","predictive_v1":{"score":61,"ews_score":61}},{"name":"' + $nomeAcentuado2 + '","predictive_v1":{"score":40,"ews_score":38}}]}'
        $zscoresRaw = '{"' + $nomeAcentuado + '":{"z_spread":2.1}}'
        $ewsRaw = '{"ok":true,"ranking":[{"empresa":"' + $nomeAcentuado + '","score":61}]}'
    } else {
        $npx = Get-Command npx -ErrorAction SilentlyContinue
        if (-not $npx) { Write-Log 'ERRO: npx ausente no PATH'; exit 1 }

        # Pre-voo KV: valida acesso antes de qualquer operacao de dados. O erro 401/403
        # aparece so no segundo kvget em diante (o primeiro as vezes e cacheado), e sem
        # esta guarda o script descobre a falha so depois de parcialmente executado.
        # Custa ~2s e evita o cenario de 30/07: 4 dias falhando com a mesma causa.
        Write-Log 'Pre-voo KV: validando acesso...'
        $predRaw = Get-KvValue 'predictive_v1:latest'
        if ($script:KvAuthFalhou) {
            Write-Log 'ERRO FATAL: token CLOUDFLARE_API_TOKEN sem permissao Workers KV Storage.'
            Write-Log 'ERRO FATAL: abrir https://dash.cloudflare.com, conta Szuchmacher, conceder Workers KV Storage ao token.'
            Write-Log 'ERRO FATAL: export cancelado. Nada foi gravado.'
            exit 5
        }
        if (-not $predRaw) {
            Write-Log 'ERRO: predictive_v1:latest ausente/ilegivel no KV - sem base para o dump (pipeline preditivo nao rodou?)'
            exit 1
        }
        Write-Log 'Pre-voo KV: OK.'

        $zscoresRaw = Get-KvValue 'anbima:zscores'
        if (-not $zscoresRaw) { $erros += 'anbima:zscores ausente (TTL 7d vencido ou sync nao rodou)'; Write-Log 'AVISO: anbima:zscores ausente' }

        # op=ews exige JWT (401 para anonimo) - nao exportado; o ews_score diario por emissor
        # ja vem dentro do payload predictive_v1:latest.
        $ewsRaw = $null
    }

    if ($predRaw -isnot [string] -or [string]::IsNullOrWhiteSpace($predRaw)) { Write-Log 'ERRO: predRaw invalido (nao-string ou vazio)'; exit 1 }
    $pred = $predRaw | ConvertFrom-Json
    if (-not $pred.emissores -or @($pred.emissores).Count -lt 1) { Write-Log 'ERRO: payload predictive sem emissores'; exit 1 }
    $emissores = @($pred.emissores | ForEach-Object { [string]$_.name })
    Write-Log ("Predictive ok: {0} emissores, modelo {1} (run_date {2})" -f $emissores.Count, $pred.modelo, $pred.run_date)

    Write-JsonFile (Join-Path $OutDir 'predictive.json') $predRaw
    if ($zscoresRaw) { Write-JsonFile (Join-Path $OutDir 'zscores.json') $zscoresRaw }
    if ($ewsRaw)     { Write-JsonFile (Join-Path $OutDir 'ews_ranking.json') $ewsRaw }

    # ------- Series ANBIMA por emissor -------
    $delta = @{}
    $full  = @{}
    $comSerie = 0; $semSerie = 0
    foreach ($emp in $emissores) {
        if ($DryRun) {
            $serieRaw = '[{"data":"' + $DataRef + '","spread_bps":150,"n_papeis":3}]'
        } else {
            $key = 'mercado:serie:' + (ConvertTo-UriComponent ($emp.ToLowerInvariant().Trim()))
            $serieRaw = Get-KvValue $key
        }
        if (-not $serieRaw) { $semSerie++; continue }
        try {
            $serie = $serieRaw | ConvertFrom-Json
            # Valor KV = {registros:[...], ...} (carregarSerie no Worker); fallback p/ array puro
            $arr = @($serie.registros)
            if ($arr.Count -lt 1) { $arr = @($serie) }
            if ($arr.Count -lt 1) { $semSerie++; continue }
            $comSerie++
            $delta[$emp] = $arr[-1]
            if ($modoFull) { $full[$emp] = $arr }
        } catch {
            $semSerie++
            $erros += ("serie de '{0}' com JSON invalido" -f $emp)
        }
    }
    Write-Log ("Series: {0} com serie, {1} sem serie (cobertura ANBIMA parcial e esperada)" -f $comSerie, $semSerie)
    if (-not $DryRun -and $comSerie -eq 0) { Write-Log 'ERRO: NENHUM emissor com serie - falha sistemica (credencial wrangler? namespace?)'; exit 1 }

    Write-JsonFile (Join-Path $OutDir 'series_delta.json') (($delta | ConvertTo-Json -Depth 6 -Compress))

    if ($modoFull -and $full.Count -gt 0) {
        $fullJson = $full | ConvertTo-Json -Depth 8 -Compress
        $gzPath = Join-Path $OutDir 'series_full.json.gz'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($fullJson)
        $fs = [System.IO.File]::Create($gzPath)
        try {
            $gz = New-Object System.IO.Compression.GzipStream($fs, [System.IO.Compression.CompressionMode]::Compress)
            $gz.Write($bytes, 0, $bytes.Length); $gz.Dispose()
        } finally { $fs.Dispose() }
        Write-Log ("series_full.json.gz gravado ({0} emissores, {1:N0} bytes brutos)" -f $full.Count, $bytes.Length)
    }

    # ------- Manifest -------
    $arquivos = @(Get-ChildItem $OutDir -File | Where-Object { $_.Name -ne 'manifest.json' } | ForEach-Object { @{ nome = $_.Name; bytes = $_.Length } })
    $manifest = [pscustomobject]@{
        data          = $DataRef
        gerado_em_brt = $NowBrt.ToString('yyyy-MM-dd HH:mm:ss')
        model_version = ('{0} (schema_v {1})' -f $pred.modelo, $pred.schema_v)
        run_date_pipeline = $pred.run_date
        modo          = if ($modoFull) { 'full' } else { 'delta' }
        emissores     = $emissores.Count
        com_serie     = $comSerie
        sem_serie     = $semSerie
        erros         = $erros
        dry_run       = [bool]$DryRun
        duracao_s     = [int]((Get-Date) - $t0).TotalSeconds
    }
    Write-JsonFile (Join-Path $OutDir 'manifest.json') ($manifest | ConvertTo-Json -Depth 4)

    # Metricas no padrao das rotinas
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $LogDir ("vixradar-export_metrics_{0}.json" -f $Stamp)) -Encoding UTF8

    Write-Log ("FIM: ok - {0} arquivos em {1} ({2}s, modo {3}, {4} avisos)" -f $arquivos.Count, $OutDir, $manifest.duracao_s, $manifest.modo, $erros.Count)

    # AUTOCOMMIT-HISTORICO1 (2026-08-11): commit restrito a $OutDir (o dia exportado
    # agora). NUNCA 'git add -A' -- o working tree deste repo frequentemente tem
    # outras mudancas soltas (scripts, notas) que nao sao desta rotina. Falha aqui
    # e AVISO, nunca falha da rotina: o dado ja foi exportado com sucesso acima.
    if (-not $DryRun) {
        try {
            git -C $ProjectRoot add -- $OutDir
            if ($LASTEXITCODE -ne 0) { throw "git add saiu $LASTEXITCODE" }
            $temStaged = git -C $ProjectRoot diff --cached --name-only -- $OutDir
            if ($temStaged) {
                git -C $ProjectRoot commit -m ("chore(data): historico {0}" -f $DataRef) -- $OutDir | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "git commit saiu $LASTEXITCODE" }
                Write-Log ("Commit automatico OK: data/historico/{0}" -f $DataRef)
            } else {
                Write-Log "Commit automatico: nada novo (dia ja sincronizado)."
            }
        } catch {
            Write-Log ("AVISO: commit automatico do historico falhou - {0}" -f $_.Exception.Message)
        }
    }

    exit 0
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
