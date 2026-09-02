# register-monitor-tasks.ps1
# Cria as tasks Monitor-Tasks (escopo VIX, 07:00) e Monitor-Tasks-Site (escopo Site, 07:05)
# no Windows Task Scheduler. Cada uma varre so as tasks do proprio projeto e reporta
# LastTaskResult nao-benigno em logs\monitor-tasks\ (MONITORCEGO1, MONITOR-PROJETOMISTO1).
#
# MONITORCEGO2 (2026-08-02): -SendEmail RELIGADO. O envio passa pelo action=email_enviar
# do Worker (ver monitor-tasks.ps1).
# MONITOR-PROJETOMISTO1 (2026-09-02): o e-mail "VIX Radar - N task(s) com falha" carregava
# tasks de outros projetos (01/09: AgendaAgent e FechamentoDiario). Agora sao dois vigias,
# um por escopo, e o e-mail so sai com erro novo ou escalado (dedup em estado.json).
#
# Reversao: Unregister-ScheduledTask -TaskName 'Monitor-Tasks' -Confirm:$false
#           Unregister-ScheduledTask -TaskName 'Monitor-Tasks-Site' -Confirm:$false
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\register-monitor-tasks.ps1"

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ScriptPath  = Join-Path $ProjectRoot 'scripts\monitor-tasks.ps1'

if (-not (Test-Path $ScriptPath)) { throw "Script nao encontrado: $ScriptPath" }

# LogonType Interactive e obrigatorio para o -SendEmail funcionar: a senha admin
# vem do DPAPI em escopo CurrentUser (api\Get-VixAdminCredential.ps1) e so
# decripta com o perfil do usuario carregado. Trocar para S4U ou Password quebra
# o alerta em silencio, que e exatamente o que estamos consertando.
$principal = New-ScheduledTaskPrincipal -UserId 'User' -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$defs = @(
    @{ Name = 'Monitor-Tasks';      At = '07:00'; Escopo = 'VIX';  Desc = 'VIX Radar - vigia diario de falha silenciosa no Task Scheduler, escopo VIX (VIXRadar-, Monitor-, Szuchmacher-RetryVix*), entrega por log das rotinas, ALERTA_AUTH e circuito de custo (MONITORCEGO1, MONITOR-PROJETOMISTO1).' },
    @{ Name = 'Monitor-Tasks-Site'; At = '07:05'; Escopo = 'Site'; Desc = 'Vigia diario de falha silenciosa no Task Scheduler, escopo Site (Szuchmacher-, MorningCall-, RadarQuant-, PME-, YanOS_), sem as tasks do VIX Radar (MONITOR-PROJETOMISTO1).' }
)
foreach ($d in $defs) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -Quiet -SendEmail -Escopo " + $d.Escopo)
    $trigger = New-ScheduledTaskTrigger -Daily -At $d.At
    $task = Register-ScheduledTask -TaskName $d.Name -TaskPath '\' `
        -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings `
        -Description $d.Desc -Force
    Write-Output "Task registrada: $($task.TaskName) (escopo $($d.Escopo), $($d.At))"
    $info = Get-ScheduledTaskInfo -TaskName $d.Name
    Write-Output "  Proxima execucao: $($info.NextRunTime)"
}
