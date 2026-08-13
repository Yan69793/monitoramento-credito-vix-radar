# watch-vixradar-health.ps1
# Vigia de health do VIX Radar para rodar fora de sessao (Task Scheduler).
# Cada execucao: 2 polls do health publico com 20s de intervalo. Se qualquer um
# vier degradado (ok:false, verificador_ok:false, versao != esperada ou HTTP != 200),
# envia e-mail via action=email_enviar do Worker (admin_senha do DPAPI), com
# reenvio a cada -ReenvioMin minutos enquanto o problema persistir.
#
# Motivo (HEALTHWATCH1, 2026-08-13): clientes ativos durante o dia e o alarme
# mais rapido era o canonical-test (6h) + monitor-tasks (07h00). Em 12-13/08 o
# health ficou vermelho por ~18h antes do primeiro e-mail. Este vigia fecha a
# janela para ~15 min em horario comercial (task Seg-Sex 08:00-20:00).
#
# Registrar:  powershell.exe -NoProfile -File scripts\watch-vixradar-health.ps1 -Register
# Testar:     powershell.exe -NoProfile -File scripts\watch-vixradar-health.ps1
# Task:       VIXRadar-Health-Watch, Seg-Sex 08:00-20:00 a cada 15 min.
# Saida:      logs\watch-health\watch_YYYYMMDD.log
#
# Regras PS 5.1: conteudo ASCII apenas (sem BOM), ErrorActionPreference
# Continue, exit real no final (contrato com o Task Scheduler). Exit 0 sempre:
# o canal de alerta deste vigia e o proprio e-mail, e exit nao-zero faria o
# monitor-tasks de 07h00 re-alertar o mesmo problema no dia seguinte.

param(
    [switch]$Register,
    [string]$VersaoEsperada = 'v4.9.193',
    [string]$WorkerUrl = 'https://api.vixradar.com/',
    [string]$To = 'szuchmacheryan@gmail.com',
    [int]$ReenvioMin = 60
)
$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root 'logs\watch-health'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$EstadoFile = Join-Path $LogDir 'estado.json'

function Write-WatchLog([string]$Msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Msg
    Add-Content -Path (Join-Path $LogDir ('watch_' + (Get-Date -Format 'yyyyMMdd') + '.log')) -Value $line -Encoding UTF8
}

if ($Register) {
    $taskName = 'VIXRadar-Health-Watch'
    $scriptPath = $PSCommandPath
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $scriptPath + '"')
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 08:00
    $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At 08:00 -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Hours 12)).Repetition
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-WatchLog ('REGISTRADO: ' + $taskName + ' Seg-Sex 08:00-20:00 a cada 15 min, esperado v' + $VersaoEsperada.TrimStart('v'))
    Write-Output ('Task ' + $taskName + ' registrada.')
    exit 0
}

function Get-VixHealthSnapshot {
    try {
        $resp = Invoke-WebRequest -Uri ($WorkerUrl + '?_=' + (Get-Date -Format 'yyyyMMddHHmmssfff')) -TimeoutSec 20 -UseBasicParsing
        $code = [int]$resp.StatusCode
        $json = $resp.Content | ConvertFrom-Json
        return [PSCustomObject]@{
            code        = $code
            ok          = $json.ok
            verificador = $json.verificador_ok
            versao      = $json.versao
        }
    } catch {
        return [PSCustomObject]@{ code = 0; ok = $false; verificador = $false; versao = '' }
    }
}

$degradado = $false
$detalhe = ''
$snap = $null
for ($i = 0; $i -lt 2; $i++) {
    $snap = Get-VixHealthSnapshot
    if ($snap.code -ne 200) {
        $degradado = $true
        $detalhe = ('HTTP ' + $snap.code + ' (Worker inalcancavel ou erro)')
        break
    }
    if ($snap.ok -ne $true -or $snap.verificador -ne $true) {
        $degradado = $true
        $detalhe = ('ok=' + $snap.ok + ' verificador_ok=' + $snap.verificador + ' versao=' + $snap.versao)
        break
    }
    if ($snap.versao -and $snap.versao -ne $VersaoEsperada) {
        $degradado = $true
        $detalhe = ('versao ' + $snap.versao + ' != esperada ' + $VersaoEsperada + ' (deploy fora do processo ou drift)')
        break
    }
    Start-Sleep -Seconds 20
}

if (-not $degradado) {
    Write-WatchLog ('OK code=' + $snap.code + ' ok=' + $snap.ok + ' verificador=' + $snap.verificador + ' versao=' + $snap.versao)
    exit 0
}

# Degradado: loga sempre, envia e-mail com dedup por -ReenvioMin.
Write-WatchLog ('DEGRADADO: ' + $detalhe)

$agora = Get-Date
$ultimoAlerta = $null
if (Test-Path $EstadoFile) {
    try {
        $est = Get-Content $EstadoFile -Raw | ConvertFrom-Json
        if ($est.last_alert) { $ultimoAlerta = [DateTime]$est.last_alert }
    } catch { }
}
$podeEnviar = (-not $ultimoAlerta) -or (($agora - $ultimoAlerta).TotalMinutes -ge $ReenvioMin)
if (-not $podeEnviar) {
    Write-WatchLog ('AVISO: problema persiste, reenvio de e-mail suprimido (proximo em ' + [int]($ReenvioMin - ($agora - $ultimoAlerta).TotalMinutes) + ' min)')
    exit 0
}

try {
    $credScript = Join-Path $Root 'api\Get-VixAdminCredential.ps1'
    if (-not (Test-Path $credScript)) { throw ('credencial ausente: ' + $credScript) }
    $adminSenha = & $credScript -AsPlainText
    if (-not $adminSenha) { throw 'Get-VixAdminCredential.ps1 devolveu vazio' }

    $html = '<h2>VIX Radar - health degradado</h2>' +
            '<p>Vigia HEALTHWATCH1 detectou problema em ' + $agora.ToString('yyyy-MM-dd HH:mm:ss') + ' na maquina ' + $env:COMPUTERNAME + ':</p>' +
            '<p><b>' + $detalhe + '</b></p>' +
            '<p>Health publico: ' + $WorkerUrl + '</p>'

    $payload = @{
        action       = 'email_enviar'
        admin_senha  = $adminSenha
        assunto      = 'VIX Radar - health degradado (' + $detalhe + ')'
        html         = $html
        destinatario = $To
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 6 -Compress))
    $resp = Invoke-WebRequest -Uri $WorkerUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 30 -UseBasicParsing
    $data = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
    if ($data.ok) {
        Write-WatchLog ('ALERTA ENVIADO para ' + $To)
        @{ last_alert = $agora.ToString('o') } | ConvertTo-Json -Compress | Set-Content -Path $EstadoFile -Encoding ASCII
    } else {
        Write-WatchLog ('AVISO: Worker recusou envio: ' + $data.erro)
    }
} catch {
    Write-WatchLog ('AVISO: falha ao enviar alerta: ' + $_.Exception.Message)
}
exit 0
