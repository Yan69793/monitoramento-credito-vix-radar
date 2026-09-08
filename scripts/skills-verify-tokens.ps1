# Verificacao pos-fix de tokens (skills no system prompt)
# Uso: pwsh -File scripts/skills-verify-tokens.ps1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$limits = @{
    HomeActiveMax = 30
    VixActiveMax = 65
    HomeTokensMax = 2500
    VixTokensMax = 5500
}

function Invoke-GrokInspect {
    # EAPLOCAL1 (2026-09-01): 'Stop' + '2>&1' em 'grok inspect' aborraria o script no PS 5.1
    # se o CLI escrever stderr. E pior: morte no shell vira exit 1 identico ao alerta real de
    # limite (exit 1 da L91 original), entao falha de execucao virava alerta de conteudo.
    # Isola com Continue local e sinaliza falha via ExitCode, para a logica abaixo tratar
    # como "nao conseguiu medir", nao como "estourou limite".
    $eapAnterior = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $out = grok inspect --json 2>&1 | Out-String
        $rc = $LASTEXITCODE
        return [PSCustomObject]@{ Output = $out; ExitCode = $rc }
    } finally {
        $ErrorActionPreference = $eapAnterior
    }
}

function Get-SkillMetrics($cwd) {
    Push-Location $cwd
    try {
        $r = Invoke-GrokInspect
        if (-not $r.Output -or $r.ExitCode -ne 0) {
            return $null  # nao conseguiu medir; caller trata como "sem dados", nao como alerta
        }
        $j = $r.Output | ConvertFrom-Json
        $active = @($j.skills | Where-Object { -not $_.disabled })
        $chars = ($active | ForEach-Object { $_.description.Length } | Measure-Object -Sum).Sum
        [PSCustomObject]@{
            Cwd = $cwd
            Total = $j.skills.Count
            Active = $active.Count
            Project = @($active | Where-Object { $_.source.type -eq 'project' }).Count
            TokensApprox = [math]::Round($chars / 4)
            VixSkills = @(
                'sprite-health', 'vix-radar-audit', 'vix-radar-next-steps',
                'vix-radar-session-briefing', 'wrangler', 'workers-best-practices'
            )
        }
    } finally {
        Pop-Location
    }
}

function Test-VixProjectSkills($metrics) {
    Push-Location $projectRoot
    try {
        $r = Invoke-GrokInspect
        if (-not $r.Output -or $r.ExitCode -ne 0) {
            return $null  # nao conseguiu medir; caller trata como "nao verificado"
        }
        $j = $r.Output | ConvertFrom-Json
        $names = $j.skills | Where-Object { -not $_.disabled } | Select-Object -ExpandProperty name
        $required = @(
            'sprite-health', 'vix-radar-audit', 'vix-radar-next-steps',
            'vix-radar-session-briefing', 'wrangler', 'workers-best-practices'
        )
        $missing = $required | Where-Object { $_ -notin $names }
        return $missing
    } finally {
        Pop-Location
    }
}

$homeMetrics = Get-SkillMetrics 'C:\Users\User'
$vixMetrics = Get-SkillMetrics $projectRoot
$missing = Test-VixProjectSkills $vixMetrics

$alerts = @()
$unverified = @()

# EAPLOCAL2 (2026-09-01): grok que falhou ao executar (exit != 0) volta como $null — e o
# defeito que este script tinha, falha de execucao elevada a alerta de conteudo. Aqui
# separa os dois: nao mediu != estourou limite.
if (-not $homeMetrics) { $unverified += 'HOME (grok inspect nao retornou dados)' }
if (-not $vixMetrics)  { $unverified += 'VIX (grok inspect nao retornou dados)' }
if ($null -eq $missing) { $unverified += 'VIX skills ausentes (nao verificado: grok falhou)' }

if ($homeMetrics -and $homeMetrics.Active -gt $limits.HomeActiveMax) {
    $alerts += "HOME skills ativas $($homeMetrics.Active) > limite $($limits.HomeActiveMax)"
}
if ($homeMetrics -and $homeMetrics.TokensApprox -gt $limits.HomeTokensMax) {
    $alerts += "HOME tokens~ $($homeMetrics.TokensApprox) > limite $($limits.HomeTokensMax)"
}
if ($vixMetrics -and $vixMetrics.Active -gt $limits.VixActiveMax) {
    $alerts += "VIX skills ativas $($vixMetrics.Active) > limite $($limits.VixActiveMax)"
}
if ($vixMetrics -and $vixMetrics.TokensApprox -gt $limits.VixTokensMax) {
    $alerts += "VIX tokens~ $($vixMetrics.TokensApprox) > limite $($limits.VixTokensMax)"
}
if ($missing -and $missing.Count -gt 0) {
    $alerts += "VIX skills ausentes: $($missing -join ', ')"
}

Write-Output '=== skills-verify-tokens ==='
if ($homeMetrics -and $vixMetrics) {
    Write-Output "HOME: $($homeMetrics.Active)/$($homeMetrics.Total) ativas | tokens~ $($homeMetrics.TokensApprox)"
    Write-Output "VIX:  $($vixMetrics.Active)/$($vixMetrics.Total) ativas | projeto $($vixMetrics.Project) | tokens~ $($vixMetrics.TokensApprox)"
} else {
    Write-Output $unverified
}

$schedOk = (Test-Path 'C:\Users\User\.claude\scheduled-tasks\vixradar-noturno\SKILL.md') -and
           (Test-Path 'C:\Users\User\.claude\scheduled-tasks\vixradar-matinal\SKILL.md')
Write-Output "Scheduled tasks matinal/noturno: $(if ($schedOk) { 'OK' } else { 'FAIL' })"

# EAPLOCAL3: nao mediu e um estado de ferramenta, nao um limite estourado. Reporta com um
# exit proprio (2) para o chamador distinguir de alerta real de limite (1) e de OK (0).
if ($alerts.Count -gt 0) {
    Write-Output 'ALERTAS:'
    $alerts | ForEach-Object { Write-Output "  - $_" }
    Write-Output 'Acao: reiniciar sessao; conferir config.toml; nao rodar import-claude/sk sync'
    exit 1
}
if ($unverified.Count -gt 0) {
    Write-Output 'NAO VERIFICADO (grok inspect falhou, sem alerta de limite):'
    $unverified | ForEach-Object { Write-Output "  - $_" }
    exit 2
}

Write-Output 'PASS: limites dentro do esperado'
exit 0