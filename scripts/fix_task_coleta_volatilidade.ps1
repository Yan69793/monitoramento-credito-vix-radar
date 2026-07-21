# fix_task_coleta_volatilidade.ps1
# Corrige VOLTASK1: a Action da tarefa VIXRadar-Coleta-Volatilidade tem aspas
# escapadas literais (-File \"...\"), o que quebra o path no primeiro espaco e
# faz a tarefa falhar em toda execucao (LastTaskResult 0x41303). A tarefa roda
# com RunLevel=Highest, entao alterar exige janela de administrador.
#
# Uso (PowerShell COMO ADMINISTRADOR):
#   pwsh -File "E:\Diretorio\Claude\Monitoramento de Credito\scripts\fix_task_coleta_volatilidade.ps1"
#
# Idempotente: se ja estiver correto, so reporta e sai.

$ErrorActionPreference = 'Stop'
$TaskName = 'VIXRadar-Coleta-Volatilidade'
$ScriptPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_coleta_volatilidade.ps1'

$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object System.Security.Principal.WindowsPrincipal($id)).IsInRole(
    [System.Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'ERRO: rode esta janela como Administrador (a tarefa e RunLevel=Highest).' -ForegroundColor Red
    return
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
$argsAtual = $task.Actions[0].Arguments
Write-Host "Arguments antes: $argsAtual"

if ($argsAtual -notmatch '\\"') {
    Write-Host 'Ja esta sem aspas escapadas. Nada a fazer.' -ForegroundColor Green
    return
}

# backup do XML atual
$bk = Join-Path $env:TEMP ("VIXRadar-Coleta-Volatilidade_bk_{0}.xml" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Export-ScheduledTask -TaskName $TaskName | Out-File $bk -Encoding utf8
Write-Host "Backup do XML em: $bk"

$exe = $task.Actions[0].Execute
$novoArgs = "-NoProfile -NonInteractive -WindowStyle Hidden -File `"$ScriptPath`""
$novaAction = New-ScheduledTaskAction -Execute $exe -Argument $novoArgs
Set-ScheduledTask -TaskName $TaskName -Action $novaAction | Out-Null

$depois = (Get-ScheduledTask -TaskName $TaskName).Actions[0].Arguments
Write-Host "Arguments depois: $depois"
if ($depois -match '\\"') {
    Write-Host 'FALHOU: aspas escapadas ainda presentes.' -ForegroundColor Red
    return
}
Write-Host 'OK: Action corrigida.' -ForegroundColor Green

# valida o parsing de fato, disparando a tarefa uma vez
Write-Host 'Disparando a tarefa uma vez para validar...'
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 8
$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host ("LastTaskResult: 0x{0:X} (0 = sucesso; era 0x41303 = nunca rodou)" -f $info.LastTaskResult)
