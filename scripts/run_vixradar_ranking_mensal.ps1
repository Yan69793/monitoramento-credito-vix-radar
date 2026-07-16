# run_vixradar_ranking_mensal.ps1
# VIX Radar - monitor mensal de ranking SEO (Google BR via WebSearch do claude -p).
# Mede a posicao de vixradar.com vs concorrentes num kit de keywords (scripts/seo/keywords.json),
# compara com a baseline anterior (scripts/seo/ranking_state.json) e alerta em caso de:
#   - ultrapassagem (concorrente que nao estava a frente passou a frente)
#   - queda propria >= queda_minima_posicoes ou saida do top 10
#   - entrada de concorrente no top 10 em keyword onde vixradar esta ausente
# Canais de alerta: nota Obsidian (sempre) + e-mail Resend (se RESEND_API_KEY presente) + toast Windows.
# Exit codes: 0 ok · 1 medicao invalida · 7 falha de auth do claude -p · 8 refusal do modelo.
# Regras do projeto: sem exit 0 silencioso com medicao vazia; janela temporal em UTC-3; stderr com sufixo PID.
#
# Uso manual: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\run_vixradar_ranking_mensal.ps1" [-DryRun] [-Quiet]

param(
    [switch]$DryRun,
    [switch]$Quiet,
    [string]$Model = 'claude-haiku-4-5-20251001'
)

$ErrorActionPreference = 'Stop'

# Encoding UTF-8 nos dois sentidos do pipe com claude.exe (contramedida ao erro historico
# de mojibake OEM850: sem isto, acentos das keywords corrompem na ida e na volta)
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$CfgPath     = Join-Path $ProjectRoot 'scripts\seo\keywords.json'
$StatePath   = Join-Path $ProjectRoot 'scripts\seo\ranking_state.json'
$HistPath    = Join-Path $ProjectRoot 'logs\seo\ranking_history.jsonl'
$LogDir      = Join-Path $ProjectRoot 'logs\routines'
$VaultSeoDir = Join-Path $ProjectRoot 'Obsidian VIX Radar\SEO'

if ($DryRun) {
    $StatePath = Join-Path $ProjectRoot 'scripts\seo\ranking_state.dryrun.json'
    $HistPath  = Join-Path $ProjectRoot 'logs\seo\ranking_history.dryrun.jsonl'
}

# Janela temporal em UTC-3 (regra do projeto - nunca UTC puro)
$NowBrt  = (Get-Date).ToUniversalTime().AddHours(-3)
$Stamp   = $NowBrt.ToString('yyyyMMdd_HHmmss')
$MesRef  = $NowBrt.ToString('yyyy-MM')
$DataRef = $NowBrt.ToString('yyyy-MM-dd')

New-Item -ItemType Directory -Force -Path $LogDir, (Split-Path $HistPath -Parent), $VaultSeoDir | Out-Null
$LogPath = Join-Path $LogDir ("vixradar-ranking_{0}.log" -f $Stamp)
$RawOut  = Join-Path $LogDir ("vixradar-ranking_{0}_rawout.txt" -f $Stamp)
$StdErr  = Join-Path $LogDir ("vixradar-ranking_{0}_stderr_{1}.txt" -f $Stamp, $PID)

function Write-Log([string]$Msg) {
    $line = ('[{0}] {1}' -f ((Get-Date).ToUniversalTime().AddHours(-3).ToString('yyyy-MM-dd HH:mm:ss')), $Msg)
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Write-Output $line
}

# Mutex contra instancia duplicada (padrao noturno)
$mutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-ranking-mensal')
if (-not $mutex.WaitOne(0)) {
    Write-Log 'AVISO: instancia duplicada detectada - abortando esta instancia'
    exit 0
}

$exitCode = 0
try {
    Write-Log ("INICIO ranking mensal - mes de referencia {0} (DryRun={1})" -f $MesRef, [bool]$DryRun)

    if (-not (Test-Path $CfgPath)) { Write-Log 'ERRO: keywords.json ausente'; exit 1 }
    $cfg = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $dominioProprio = $cfg.dominio_proprio
    $concorrentes   = @($cfg.concorrentes)
    $keywords       = @($cfg.keywords)
    if ($keywords.Count -lt 1) { Write-Log 'ERRO: kit de keywords vazio'; exit 1 }
    Write-Log ("Config: {0} keywords, {1} concorrentes, dominio proprio {2}" -f $keywords.Count, $concorrentes.Count, $dominioProprio)

    # ---------------------------------------------------------------
    # 1. MEDICAO - claude -p com WebSearch retorna top 10 por keyword
    # ---------------------------------------------------------------
    $resultados = $null
    $instrumento = 'claude-websearch'

    if ($DryRun) {
        Write-Log 'DryRun: gerando medicao sintetica (sem chamada ao claude)'
        $resultados = @()
        foreach ($kw in $keywords) {
            $top = @('exemplo-a.com.br', 'comdinheiro.com.br', 'exemplo-c.com', 'vixradar.com', 'exemplo-d.com.br')
            $resultados += [pscustomobject]@{ keyword = $kw; top = $top }
        }
    } else {
        $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
        if (-not $claudeCmd) { Write-Log 'ERRO: claude.exe ausente no PATH'; exit 1 }
        if (-not $env:ANTHROPIC_API_KEY) {
            Write-Log 'AVISO: ANTHROPIC_API_KEY ausente - claude -p usara assinatura (limite semanal)'
        }

        $kwList = ($keywords | ForEach-Object { '- ' + $_ }) -join "`n"
        $prompt = @"
Voce e um medidor de ranking de busca. Para CADA termo da lista abaixo, execute UMA busca com a ferramenta WebSearch usando o termo exatamente como escrito (busca em portugues, contexto Brasil) e registre os dominios dos 10 primeiros resultados organicos, na ordem em que aparecem.

Termos:
$kwList

Regras:
- Um WebSearch por termo, sem repetir nem reformular o termo.
- Extraia apenas o dominio registrado de cada resultado (ex.: "conteudos.xpi.com.br", "vixradar.com"), na ordem.
- Ate 10 dominios por termo; se houver menos resultados, liste os que existirem.
- Nao filtre nem reordene: a ordem retornada pela busca e o dado.
- Responda SOMENTE com JSON valido, sem markdown, sem comentario, neste formato exato:
{"instrumento":"claude-websearch","resultados":[{"keyword":"<termo>","top":["dominio1","dominio2"]}]}
"@
        Write-Log ("Invocando claude -p (modelo {0}, {1} keywords)..." -f $Model, $keywords.Count)
        $raw = ''
        try {
            # ErrorActionPreference local Continue: em PS 5.1, '2>>arquivo' com Stop converte
            # stderr do claude.exe em NativeCommandError e aborta chamada valida.
            $eapAnterior = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $raw = ($prompt | claude -p --model $Model --tools 'WebSearch,WebFetch' 2>>$StdErr | Out-String)
            $ErrorActionPreference = $eapAnterior
        } catch {
            Write-Log ('ERRO: excecao ao invocar claude -p: ' + $_.Exception.Message)
            exit 1
        }
        $claudeExit = $LASTEXITCODE
        Set-Content -Path $RawOut -Value $raw -Encoding UTF8

        # Guardas (padrao verificacao_async): auth-failure e refusal nunca viram exit 0
        $authPatterns = @('Invalid API key', 'Please run /login', 'OAuth token has expired', 'authentication_error')
        foreach ($p in $authPatterns) {
            if ($raw -match [regex]::Escape($p)) { Write-Log ("ERRO AUTH: padrao '{0}' no output - exit 7" -f $p); exit 7 }
        }
        if ($raw -match 'stop_reason.{0,5}refusal' -or $raw.Trim() -eq 'REFUSAL') {
            Write-Log 'ERRO REFUSAL: modelo recusou a tarefa - exit 8 (rawout preservado)'; exit 8
        }
        if ($claudeExit -ne 0) { Write-Log ("ERRO: claude -p exit {0} - ver stderr {1}" -f $claudeExit, $StdErr); exit 1 }
        if ([string]::IsNullOrWhiteSpace($raw)) { Write-Log 'ERRO: output vazio do claude -p (possivel falha silenciosa)'; exit 1 }

        # Extrai envelope JSON (modelo pode envolver em texto/markdown)
        $iStart = $raw.IndexOf('{'); $iEnd = $raw.LastIndexOf('}')
        if ($iStart -lt 0 -or $iEnd -le $iStart) { Write-Log 'ERRO: nenhum JSON no output - ver rawout'; exit 1 }
        try {
            $envelope = $raw.Substring($iStart, $iEnd - $iStart + 1) | ConvertFrom-Json
        } catch {
            Write-Log ('ERRO: JSON invalido no output (' + $_.Exception.Message + ') - ver rawout'); exit 1
        }
        $resultados = @($envelope.resultados)
    }

    if (-not $resultados -or @($resultados).Count -lt 1) { Write-Log 'ERRO: medicao sem resultados'; exit 1 }
    Write-Log ("Medicao valida: {0} keywords retornadas" -f @($resultados).Count)

    # Pareamento keyword -> resultado: por texto exato; fallback por indice (protege contra
    # eco normalizado/corrompido do termo pelo modelo, mantendo o kit da config como canonico)
    $resultadosArr = @($resultados)
    $pareados = @()
    for ($k = 0; $k -lt $keywords.Count; $k++) {
        $match = $resultadosArr | Where-Object { [string]$_.keyword -eq $keywords[$k] } | Select-Object -First 1
        if (-not $match -and $k -lt $resultadosArr.Count) { $match = $resultadosArr[$k] }
        if ($match) {
            $pareados += [pscustomobject]@{ keyword = $keywords[$k]; top = @($match.top) }
        } else {
            Write-Log ("AVISO: sem resultado para keyword '{0}'" -f $keywords[$k])
        }
    }
    $resultados = $pareados
    if (@($resultados).Count -lt 1) { Write-Log 'ERRO: pareamento keyword/resultado vazio'; exit 1 }

    # ---------------------------------------------------------------
    # 2. POSICOES - dominio proprio e concorrentes por keyword
    # ---------------------------------------------------------------
    function Get-Posicao([object[]]$Top, [string]$Dominio) {
        for ($i = 0; $i -lt $Top.Count; $i++) {
            if ([string]$Top[$i] -like ('*' + $Dominio + '*')) { return ($i + 1) }
        }
        return $null
    }

    $posicoes = @()
    foreach ($r in $resultados) {
        $top = @($r.top)
        $conc = @{}
        foreach ($c in $concorrentes) {
            $pc = Get-Posicao -Top $top -Dominio $c
            if ($null -ne $pc) { $conc[$c] = $pc }
        }
        $posicoes += [pscustomobject]@{
            keyword      = [string]$r.keyword
            propria      = (Get-Posicao -Top $top -Dominio $dominioProprio)
            concorrentes = $conc
            top          = $top
        }
    }

    # ---------------------------------------------------------------
    # 3. COMPARACAO com baseline anterior - deteccao de ultrapassagem
    # ---------------------------------------------------------------
    $quedaMin = 2
    if ($cfg.alerta -and $cfg.alerta.queda_minima_posicoes) { $quedaMin = [int]$cfg.alerta.queda_minima_posicoes }
    $alertas = @()
    $baselineMode = $true
    $anterior = $null

    if (Test-Path $StatePath) {
        try { $anterior = Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $anterior = $null }
    }
    if ($anterior -and $anterior.instrumento -eq $instrumento) {
        $baselineMode = $false
        foreach ($atual in $posicoes) {
            $prev = $anterior.posicoes | Where-Object { $_.keyword -eq $atual.keyword } | Select-Object -First 1
            if (-not $prev) { continue }

            $prevOwn = 99; if ($null -ne $prev.propria)  { $prevOwn = [int]$prev.propria }
            $curOwn  = 99; if ($null -ne $atual.propria) { $curOwn  = [int]$atual.propria }

            # Queda propria
            if ($prevOwn -le 10 -and $curOwn -eq 99) {
                $alertas += ("[{0}] vixradar SAIU do top 10 (era #{1})" -f $atual.keyword, $prevOwn)
            } elseif ($curOwn -gt $prevOwn -and ($curOwn - $prevOwn) -ge $quedaMin -and $curOwn -le 10) {
                $alertas += ("[{0}] queda propria: #{1} para #{2}" -f $atual.keyword, $prevOwn, $curOwn)
            }

            # Ultrapassagem / entrada de concorrente
            foreach ($c in $concorrentes) {
                $prevC = 99
                if ($prev.concorrentes -and $prev.concorrentes.PSObject.Properties[$c]) { $prevC = [int]$prev.concorrentes.$c }
                $curC = 99
                if ($atual.concorrentes.ContainsKey($c)) { $curC = [int]$atual.concorrentes[$c] }
                if ($curC -eq 99) { continue }

                $estavaAtras = ($prevC -ge $prevOwn)
                $agoraNaFrente = ($curC -lt $curOwn)
                if ($estavaAtras -and $agoraNaFrente) {
                    if ($prevOwn -le 10) {
                        $alertas += ("[{0}] ULTRAPASSAGEM: {1} (#{2}) passou vixradar (#{3}, antes #{4})" -f $atual.keyword, $c, $curC, $curOwn, $prevOwn)
                    } elseif ($prevC -eq 99) {
                        $alertas += ("[{0}] concorrente {1} ENTROU no top 10 (#{2}); vixradar ausente" -f $atual.keyword, $c, $curC)
                    }
                }
            }
        }
    } else {
        if ($anterior) { Write-Log 'AVISO: instrumento da baseline mudou - rebaseline sem alertas neste ciclo' }
        Write-Log 'Baseline: primeira medicao com este instrumento - sem comparacao neste ciclo'
    }

    # ---------------------------------------------------------------
    # 4. PERSISTENCIA - estado, historico JSONL, nota Obsidian
    # ---------------------------------------------------------------
    $estado = [pscustomobject]@{
        data        = $DataRef
        mes         = $MesRef
        instrumento = $instrumento
        posicoes    = $posicoes
    }
    $estado | ConvertTo-Json -Depth 8 | Set-Content -Path $StatePath -Encoding UTF8
    ($estado | ConvertTo-Json -Depth 8 -Compress) | Add-Content -Path $HistPath -Encoding UTF8
    Write-Log ("Estado gravado em {0}; historico em {1}" -f $StatePath, $HistPath)

    $notaPath = Join-Path $VaultSeoDir ("Ranking SEO {0}.md" -f $MesRef)
    if ($DryRun) { $notaPath = Join-Path $VaultSeoDir ("Ranking SEO {0} (dryrun).md" -f $MesRef) }
    $nl = [Environment]::NewLine
    $nota = "# Ranking SEO - $MesRef$nl$nl"
    $nota += "Gerado por run_vixradar_ranking_mensal.ps1 em $DataRef (instrumento: $instrumento; modelo: $Model; DryRun: $([bool]$DryRun)).$nl$nl"
    if ($baselineMode) {
        $nota += "**Baseline criada neste ciclo - sem comparacao com mes anterior.**$nl$nl"
    } elseif ($alertas.Count -gt 0) {
        $nota += "## ALERTAS ($($alertas.Count))$nl$nl"
        foreach ($a in $alertas) { $nota += "- $a$nl" }
        $nota += $nl
    } else {
        $nota += "Sem ultrapassagem nem queda relevante vs mes anterior.$nl$nl"
    }
    $nota += "| Keyword | vixradar | Concorrente mais bem posicionado |$nl|---|---|---|$nl"
    foreach ($p in $posicoes) {
        $own = '-'; if ($null -ne $p.propria) { $own = '#' + $p.propria }
        $melhorConc = '-'
        if ($p.concorrentes.Count -gt 0) {
            $best = $p.concorrentes.GetEnumerator() | Sort-Object Value | Select-Object -First 1
            $melhorConc = ('{0} (#{1})' -f $best.Key, $best.Value)
        }
        $nota += "| $($p.keyword) | $own | $melhorConc |$nl"
    }
    Set-Content -Path $notaPath -Value $nota -Encoding UTF8
    Write-Log ("Nota Obsidian gravada: {0}" -f $notaPath)

    # ---------------------------------------------------------------
    # 5. ALERTA - e-mail Resend + toast (somente se houver alertas)
    # ---------------------------------------------------------------
    if ($alertas.Count -gt 0) {
        Write-Log ("ALERTAS: {0}" -f $alertas.Count)
        foreach ($a in $alertas) { Write-Log ('  ' + $a) }

        if ($env:RESEND_API_KEY) {
            try {
                $emailPara = 'szuchmacheryan@gmail.com'
                $emailDe   = 'VIX Radar <onboarding@resend.dev>'
                if ($cfg.alerta) {
                    if ($cfg.alerta.email_para) { $emailPara = [string]$cfg.alerta.email_para }
                    if ($cfg.alerta.email_de)   { $emailDe   = [string]$cfg.alerta.email_de }
                }
                $htmlItens = ($alertas | ForEach-Object { '<li>' + $_ + '</li>' }) -join ''
                $body = @{
                    from    = $emailDe
                    to      = @($emailPara)
                    subject = ("VIX Radar - ranking: {0} alerta(s) em {1}" -f $alertas.Count, $MesRef)
                    html    = ('<p>Monitor mensal de ranking SEO detectou:</p><ul>' + $htmlItens + '</ul><p>Detalhes na nota Obsidian "Ranking SEO ' + $MesRef + '".</p>')
                } | ConvertTo-Json -Depth 4
                Invoke-RestMethod -Uri 'https://api.resend.com/emails' -Method Post -ContentType 'application/json' `
                    -Headers @{ Authorization = ('Bearer ' + $env:RESEND_API_KEY) } -Body $body | Out-Null
                Write-Log ('E-mail de alerta enviado para ' + $emailPara)
            } catch {
                Write-Log ('AVISO: falha ao enviar e-mail Resend: ' + $_.Exception.Message)
            }
        } else {
            Write-Log 'AVISO: RESEND_API_KEY ausente - alerta por e-mail NAO enviado. Setar com: [Environment]::SetEnvironmentVariable(''RESEND_API_KEY'',''re_...'',''User'')'
        }

        if (-not $Quiet) {
            try {
                [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
                $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
                $textos = $template.GetElementsByTagName('text')
                $textos.Item(0).AppendChild($template.CreateTextNode('VIX Radar - alerta de ranking')) | Out-Null
                $textos.Item(1).AppendChild($template.CreateTextNode(("{0} alerta(s) no monitor SEO de {1}. Ver nota Obsidian." -f $alertas.Count, $MesRef))) | Out-Null
                $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
                [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('VIX Radar').Show($toast)
                Write-Log 'Toast exibido'
            } catch {
                Write-Log ('AVISO: toast indisponivel neste host: ' + $_.Exception.Message)
            }
        }
    } else {
        Write-Log 'Sem alertas neste ciclo'
    }

    # Metricas (padrao das rotinas)
    $metrics = [pscustomobject]@{
        data        = $DataRef
        mes         = $MesRef
        keywords    = @($posicoes).Count
        alertas     = $alertas.Count
        baseline    = $baselineMode
        instrumento = $instrumento
        dry_run     = [bool]$DryRun
        exit        = 0
    }
    $metrics | ConvertTo-Json | Set-Content -Path (Join-Path $LogDir ("vixradar-ranking_metrics_{0}.json" -f $Stamp)) -Encoding UTF8

    Write-Log ("FIM: ok - {0} keywords, {1} alertas, baseline={2}" -f @($posicoes).Count, $alertas.Count, $baselineMode)
    $exitCode = 0
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
exit $exitCode
