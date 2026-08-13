# check-gh-actions-health.ps1
# Verifica os 3 workflows de monitoria do GitHub Actions (canonical-test,
# frescor-check, scan-emergencia) e reporta runs falhas recentes.
#
# Motivo de existir (GHWL1, 2026-08-13): frescor-check e scan-emergencia ficaram
# cegos por 4 dias (403 por ADMIN_PASSWORD divergente entre GitHub Actions e o
# Worker) e nada acusou, porque nenhum monitor local le as runs do GitHub. Este
# script e o sinal que faltava. Chamar de monitor-tasks.ps1 ou manualmente.
#
# Requisitos: gh CLI autenticado (gh auth status). Saida: linhas por workflow,
# exit code = numero de workflows com a ultima run falha/404.
# Compativel com PowerShell 5.1 (Task Scheduler).

$ErrorActionPreference = 'Continue'

$workflows = @(
    @{ Nome = 'canonical-test';    Arquivo = 'canonical-test.yml' },
    @{ Nome = 'frescor-check';     Arquivo = 'frescor-check.yml' },
    @{ Nome = 'scan-emergencia';   Arquivo = 'scan-emergencia.yml' }
)

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Output 'GHWL1: gh CLI ausente no PATH. Impossivel verificar runs do GitHub Actions.'
    return
}

$falhas = 0
foreach ($wf in $workflows) {
    $run = gh run list --workflow $wf.Arquivo --limit 1 --json conclusion,status,createdAt,headSha --jq '.[0]' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $run) {
        Write-Output ('GHWL1: ' + $wf.Nome + ' - sem run visivel (gh falhou ou workflow nao existe)')
        $falhas++
        continue
    }
    $j = $run | ConvertFrom-Json
    $conclusao = $j.conclusion
    $estado = $j.status
    $criada = $j.createdAt
    $linha = 'GHWL1: ' + $wf.Nome + ' - estado=' + $estado + ' conclusao=' + $conclusao + ' criada=' + $criada
    if (($conclusao -eq 'failure') -or ($estado -eq 'in_progress' -and $null -eq $conclusao)) {
        Write-Output ($linha + ' <-- ATENCAO')
        $falhas++
    } else {
        Write-Output $linha
    }
}

Write-Output ('GHWL1: resumo - ' + $workflows.Count + ' workflows, ' + $falhas + ' com problema.')
return $falhas
