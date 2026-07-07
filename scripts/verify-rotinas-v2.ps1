# Valida artefatos rotina-v2 (local) e opcionalmente endpoint live pós-deploy
param(
    [switch]$Live,
    [string]$WorkerUrl = 'https://api.vixradar.com'
)

$ErrorActionPreference = 'Stop'
$root = 'E:\Diretorio\Claude\Monitoramento de Credito'
$fail = 0

function Assert-Check($cond, $msg) {
    if ($cond) { Write-Output "PASS: $msg" }
    else { Write-Output "FAIL: $msg"; $script:fail++ }
}

Write-Output '=== verify-rotinas-v2 (local) ==='

# 1. wrangler.toml - deriva o bundle ATIVO do campo main (nunca hardcodear versao;
#    isso e o que ficou stale em v4.9.143 enquanto prod ja estava em v4.9.148)
$wrangler = Join-Path $root 'api\wrangler.toml'
$activeBundle = $null
if (Test-Path $wrangler) {
    $toml = Get-Content $wrangler -Raw
    if ($toml -match 'main\s*=\s*"(v4\.9\.[0-9]+\.js)"') { $activeBundle = $Matches[1] }
    Assert-Check ($null -ne $activeBundle) 'wrangler main aponta para bundle v4.9.x.js'
    Assert-Check ($toml -match 'VARREDURA_CRON_AI_ENABLED\s*=\s*"false"') 'VARREDURA_CRON_AI_ENABLED=false'
}

# 2. Worker bundle ativo (path derivado do wrangler.toml acima)
if ($activeBundle) {
    $workerActive = Join-Path $root ('api\' + $activeBundle)
    Assert-Check (Test-Path $workerActive) "$activeBundle existe"
    if (Test-Path $workerActive) {
        $w = Get-Content $workerActive -Raw
        Assert-Check ($w -match 'listar_plano_rotina') 'endpoint listar_plano_rotina'
        Assert-Check ($w -match 'montarPlanoRotina') 'funcao montarPlanoRotina'
        Assert-Check ($w -match 'varreduraCronAiHabilitada') 'flag varreduraCronAiHabilitada'
        $bundleVersao = $activeBundle -replace '\.js$', ''
        Assert-Check ($w -match [regex]::Escape($bundleVersao)) "WORKER_VERSAO $bundleVersao"
    }
} else {
    Assert-Check $false 'nao foi possivel derivar bundle ativo do wrangler.toml'
}

# 3. SKILL.md v2
$skillMat = 'C:\Users\User\.claude\scheduled-tasks\vixradar-matinal\SKILL.md'
$skillNot = 'C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\SKILL.md'
$core = 'C:\Users\User\.claude\scheduled-tasks\_shared\rotina-v2-core.md'
Assert-Check (Test-Path $core) 'rotina-v2-core.md'
if (Test-Path $skillMat) {
    $m = Get-Content $skillMat -Raw
    Assert-Check ($m -match 'listar_plano_rotina') 'matinal usa listar_plano_rotina'
    Assert-Check ($m -notmatch '9 rodadas de busca') 'matinal sem 9 rodadas legado'
    Assert-Check ($m -match 'SKIP') 'matinal documenta SKIP'
    Assert-Check ($m -match '120') 'matinal documenta meta 120k'
    Assert-Check ($m -match '180') 'matinal documenta hard cap 180k'
    Assert-Check ($m -match 'Haiku') 'matinal documenta Haiku'
}
if (Test-Path $skillNot) {
    $n = Get-Content $skillNot -Raw
    Assert-Check ($n -match '500') 'noturno documenta meta 500k'
    Assert-Check ($n -match '700') 'noturno documenta hard cap 700k'
    Assert-Check ($n -match 'Haiku') 'noturno documenta Haiku'
    Assert-Check ($n -notmatch 'obrigatoriamente.*9 rodadas') 'noturno sem 9 rodadas obrigatorias'
}

# 4. ROUTINE_KEY
$key = $null
if (Test-Path $skillNot) {
    $raw = Get-Content $skillNot -Raw
    if ($raw -match 'ROUTINE_KEY\s*=\s*(\S+)') { $key = $Matches[1] }
}
if (-not $key -and $env:ROUTINE_API_KEY) { $key = $env:ROUTINE_API_KEY }
Assert-Check ($null -ne $key) 'ROUTINE_KEY disponivel'

# 5. Emissores 103 (live baseline)
if ($key) {
    $body103 = @{ action = 'listar_todos_emissores'; routine_key = $key } | ConvertTo-Json -Compress
    try {
        $r103 = Invoke-RestMethod -Uri $WorkerUrl -Method Post -ContentType 'application/json' -Body $body103 -TimeoutSec 30
        Assert-Check ($r103.ok -eq $true -and $r103.total -eq 103) "listar_todos_emissores 103/103 em $WorkerUrl"
    } catch {
        Write-Output "FAIL: listar_todos_emissores - $($_.Exception.Message)"
        $fail++
    }
}

# 6. Live: listar_plano_rotina (rodar com -Live pos-deploy, contra o bundle ativo)
if ($Live -and $key) {
    Write-Output '=== verify-rotinas-v2 (live) ==='
    foreach ($modo in @('matinal', 'noturno')) {
        $body = @{ action = 'listar_plano_rotina'; routine_key = $key; modo = $modo } | ConvertTo-Json -Compress
        if ($modo -eq 'matinal') { $body = (@{ action = 'listar_plano_rotina'; routine_key = $key; modo = $modo; top_n = 15 } | ConvertTo-Json -Compress) }
        try {
            $plan = Invoke-RestMethod -Uri $WorkerUrl -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 120
            $expTotal = if ($modo -eq 'noturno') { 103 } else { 15 }
            Assert-Check ($plan.ok -eq $true -and $plan.versao -eq 'rotina-v2') "plano $modo rotina-v2"
            Assert-Check ($plan.total -eq $expTotal) "plano $modo total=$($plan.total) esperado=$expTotal"
            Assert-Check ($plan.buscas_estimadas -lt $plan.buscas_full_legacy) "plano $modo economia buscas"
            Assert-Check ($plan.varredura_cron_ai -eq $false) 'varredura_cron_ai=false em prod'
            Write-Output "  tiers $($modo): $($plan.contagem_tiers | ConvertTo-Json -Compress)"
            Write-Output "  buscas: $($plan.buscas_estimadas)/$($plan.buscas_full_legacy) economia $($plan.economia_pct)%"
        } catch {
            Write-Output "FAIL: listar_plano_rotina $modo - $($_.Exception.Message)"
            $fail++
        }
    }
} elseif (-not $Live) {
    Write-Output 'SKIP live: use -Live apos deploy'
}

# 7. Orquestradores (SKIP PS1 + lotes)
$cleanup = Join-Path $root 'scripts\cleanup-rotina-artifacts.ps1'
Assert-Check (Test-Path $cleanup) 'cleanup-rotina-artifacts.ps1 existe'

$orchNot = Join-Path $root 'scripts\run_vixradar_noturno_claude.ps1'
$batchNotH = Join-Path $root 'scripts\noturno-batch-haiku.md'
$batchNotS = Join-Path $root 'scripts\noturno-batch-sonnet.md'
Assert-Check (Test-Path $orchNot) 'run_vixradar_noturno_claude.ps1 orquestrado'
Assert-Check (Test-Path $batchNotH) 'noturno-batch-haiku.md existe'
Assert-Check (Test-Path $batchNotS) 'noturno-batch-sonnet.md existe'
if (Test-Path $orchNot) {
    $o = Get-Content $orchNot -Raw
    Assert-Check ($o -match 'Submit-SkipEmissor') 'noturno SKIP via PS1'
    Assert-Check ($o -match 'TokenTarget\s*=\s*500000') 'noturno meta 500k tokens'
    Assert-Check ($o -match 'TokenHardCap\s*=\s*700000') 'noturno hard cap 700k'
    Assert-Check ($o -match 'ModelHaiku') 'noturno roteia Haiku'
    Assert-Check ($o -match 'Build-LlmQueues') 'noturno fila sonnet/haiku'
    Assert-Check ($o -notmatch '--add-dir \$ProjectRoot') 'noturno sem add-dir ProjectRoot'
    Assert-Check ($o -match 'cleanup-rotina-artifacts') 'noturno chama cleanup disco'
    Assert-Check ($o -match 'Sem arquivos locais') 'noturno proibe artefatos locais'
}

$orchMat = Join-Path $root 'scripts\run_vixradar_matinal_claude.ps1'
$batchMatH = Join-Path $root 'scripts\matinal-batch-haiku.md'
$batchMatS = Join-Path $root 'scripts\matinal-batch-sonnet.md'
$estMat = Join-Path $root 'scripts\_archive\estimate-matinal-tokens.ps1'
Assert-Check (Test-Path $orchMat) 'run_vixradar_matinal_claude.ps1 orquestrado'
Assert-Check (Test-Path $batchMatH) 'matinal-batch-haiku.md existe'
Assert-Check (Test-Path $batchMatS) 'matinal-batch-sonnet.md existe'
Assert-Check (Test-Path $estMat) 'estimate-matinal-tokens.ps1 existe (ferramenta auxiliar, arquivada - nao e dependencia de runtime)'
if (Test-Path $orchMat) {
    $m = Get-Content $orchMat -Raw
    Assert-Check ($m -match 'Submit-SkipEmissor') 'matinal SKIP via PS1'
    Assert-Check ($m -match 'TokenTarget\s*=\s*120000') 'matinal meta 120k tokens'
    Assert-Check ($m -match 'TokenHardCap\s*=\s*180000') 'matinal hard cap 180k'
    Assert-Check ($m -match 'top_n\s*=\s*\$TopN') 'matinal plano top_n=15'
    Assert-Check ($m -match '_matinal\s*=\s*\$true') 'matinal flag _matinal'
    Assert-Check ($m -match 'ModelHaiku') 'matinal roteia Haiku'
    Assert-Check ($m -match 'Build-LlmQueues') 'matinal fila sonnet/haiku'
    Assert-Check ($m -notmatch '--add-dir \$ProjectRoot') 'matinal sem add-dir ProjectRoot'
    Assert-Check ($m -match 'cleanup-rotina-artifacts') 'matinal chama cleanup disco'
    Assert-Check ($m -match 'Sem arquivos locais') 'matinal proibe artefatos locais'
}

# 8. Cloud routines (Remote — PC desligado OK)
$cloudManifest = 'C:\Users\User\.claude\scheduled-tasks\cloud-routines-manifest.json'
$cloudReg = Join-Path $root 'scripts\register-cloud-routines.ps1'
$matCloud = 'C:\Users\User\.claude\scheduled-tasks\vixradar-matinal\ROUTINES-CLOUD.md'
$notCloud = 'C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\ROUTINES-CLOUD.md'
Assert-Check (Test-Path $cloudReg) 'register-cloud-routines.ps1 atalho existe'
Assert-Check (Test-Path $matCloud) 'matinal ROUTINES-CLOUD.md existe'
Assert-Check (Test-Path $notCloud) 'noturno ROUTINES-CLOUD.md existe'
if (Test-Path $matCloud) {
    $mc = Get-Content $matCloud -Raw
    Assert-Check ($mc -match 'Sem subagentes') 'matinal cloud proibe subagentes'
    Assert-Check ($mc -match 'listar_plano_rotina') 'matinal cloud usa plano Worker'
}
if (Test-Path $notCloud) {
    $nc = Get-Content $notCloud -Raw
    Assert-Check ($nc -match 'PROIBIDO Task') 'noturno cloud proibe Task'
    Assert-Check ($nc -match '500k') 'noturno cloud meta 500k'
}

# 9. Dev skills projeto (execute-plan + superpowers)
$installDev = Join-Path $root 'scripts\_archive\install-project-dev-skills.ps1'
$grokCfg = Join-Path $root '.grok\config.toml'
Assert-Check (Test-Path $installDev) 'install-project-dev-skills.ps1 existe (setup one-off, arquivado - nao e dependencia de runtime)'
Assert-Check (Test-Path $grokCfg) '.grok/config.toml existe'
if (Test-Path $grokCfg) {
    $gc = Get-Content $grokCfg -Raw
    Assert-Check ($gc -match 'superpowers') 'projeto habilita plugin superpowers'
}
$ep = Join-Path $root '.claude\skills\execute-plan\SKILL.md'
$sp = Join-Path $root '.claude\skills\using-superpowers\SKILL.md'
Assert-Check (Test-Path $ep) 'execute-plan no projeto'
Assert-Check (Test-Path $sp) 'using-superpowers no projeto'

# 10. Windows Task Scheduler (fallback local — PC ligado)
$regAll = Join-Path $root 'scripts\register-all-routines-scheduler.ps1'
$runGeneric = Join-Path $root 'scripts\run_claude_routine.ps1'
Assert-Check (Test-Path $regAll) 'register-all-routines-scheduler.ps1 existe'
Assert-Check (Test-Path $runGeneric) 'run_claude_routine.ps1 existe'
foreach ($tn in @(
    'VIXRadar-AgendaSemanal', 'VIXRadar-Matinal', 'VIXRadar-Noturno',
    'Szuchmacher-AgendaMacro-Claude', 'Szuchmacher-FechamentoDiario', 'Szuchmacher-FechamentoWatchdog'
)) {
    try {
        $st = Get-ScheduledTask -TaskName $tn -ErrorAction Stop
        $nr = (Get-ScheduledTaskInfo -TaskName $tn).NextRunTime
        Assert-Check ($st.State -eq 'Ready') "Task Scheduler $tn Ready"
        Assert-Check ($null -ne $nr) "Task Scheduler $tn NextRun definido"
    } catch {
        Assert-Check $false "Task Scheduler $tn ausente"
    }
}

Write-Output "=== resultado: $($fail) falha(s) ==="
if ($fail -gt 0) { exit 1 }
exit 0