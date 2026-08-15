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

# HEALTHWATCH2 (auditoria 2026-08-15): a versao esperada era hardcoded no parametro e
# ficava stale a cada deploy - em 14/08 o vigia marcou "degradado" o dia inteiro
# (prod v4.9.194 vs esperada v4.9.193), gerando alertas falsos por horas. Agora a
# versao esperada deriva do api\wrangler.toml (fonte canonica do repo), que e o mesmo
# arquivo que o deploy atualiza; o parametro vira so fallback.
try {
    $linhaMain = Select-String -Path (Join-Path $Root 'api\wrangler.toml') -Pattern '^main\s*=\s*"v([0-9.]+)\.js"' | Select-Object -First 1
    if ($linhaMain -and $linhaMain.Matches[0].Groups[1].Value) {
        $VersaoEsperada = 'v' + $linhaMain.Matches[0].Groups[1].Value
    }
} catch { }
# HEALTHWATCH2b (revisao 15/08): o toml e apontado ANTES do deploy terminar, entao o
# vigia via "esperada v4.9.195 vs producao v4.9.194" e mandava e-mail falso a cada
# deploy. Se o toml foi alterado ha menos de 10 minutos, o cheque de versao fica
# suprimido nesta rodada (deploy em curso); passados 10 min sem deploy, o desvio
# volta a ser alarmado como "deploy fora do processo ou drift".
$TomlRecente = $false
try {
    $tomlItem = Get-Item -LiteralPath (Join-Path $Root 'api\wrangler.toml')
    if ($tomlItem -and ((Get-Date) - $tomlItem.LastWriteTime).TotalMinutes -lt 10) { $TomlRecente = $true }
} catch { }
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

# ROTINAGAP1 (auditoria 2026-08-15): sessao Claude Desktop que nao dispara nao deixa
# rastro nenhum - a matinal perdeu 13 e 14/08 em silencio total. Se o log do dia da
# rotina esperada nao existe apos o horario de execucao, avisa via action=notificar_rotina.
# O dedup por rotina/dia do Worker (NOTIFYRL1) garante no maximo 1 aviso por dia.
$agoraR = Get-Date
$hojeF = $agoraR.ToString('yyyyMMdd')
$logMat = Join-Path $Root ('logs\routines\vixradar-matinal_' + $hojeF + '.log')
$logVer = Join-Path $Root ('logs\routines\vixradar-verificacao-async_' + $hojeF + '.log')
$logNot = Join-Path $Root ('logs\routines\vixradar-noturno_' + $hojeF + '.log')
# ROTINAGAP1 revisao 15/08: o elseif cego perdia a ausencia da verificacao-async quando
# matinal e verificacao faltavam no mesmo dia. Agora cada ausencia vira um alerta proprio
# com nome de rotina distinto (watch-health-<rotina>), porque o dedup do Worker e POR NOME
# de rotina por dia (NOTIFYRL1) e um nome unico faria o segundo alerta ser engolido.
$rotinasFaltantes = @()
if ($agoraR.DayOfWeek -notin @('Saturday', 'Sunday')) {
    if ($agoraR.Hour -ge 12 -and -not (Test-Path $logMat)) { $rotinasFaltantes += 'matinal' }
    if ($agoraR.Hour -ge 12 -and -not (Test-Path $logVer)) { $rotinasFaltantes += 'verificacao-async' }
}
if ($agoraR.Hour -ge 19 -and $agoraR.Minute -ge 30 -and -not (Test-Path $logNot)) { $rotinasFaltantes += 'noturno' }
if ($rotinasFaltantes.Count -gt 0) {
    $rk = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    foreach ($rotinaFaltante in $rotinasFaltantes) {
        Write-WatchLog ('ROTINA FALTANTE: ' + $rotinaFaltante + ' sem log hoje')
        if (-not $rk) {
            Write-WatchLog ('AVISO: ROUTINE_API_KEY ausente do escopo User, alerta nao enviado')
            continue
        }
        try {
            $p2 = @{
                action       = 'notificar_rotina'
                routine_key  = $rk
                rotina       = 'watch-health-' + $rotinaFaltante
                motivo       = ('Rotina ' + $rotinaFaltante + ' nao deixou log ate ' + $agoraR.ToString('HH:mm') + ' BRT. Sessao Claude Desktop pode nao ter disparado.')
            }
            $b2 = [System.Text.Encoding]::UTF8.GetBytes(($p2 | ConvertTo-Json -Compress))
            Invoke-WebRequest -Uri $WorkerUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $b2 -TimeoutSec 30 -UseBasicParsing | Out-Null
            Write-WatchLog ('ALERTA ROTINA enviado (dedup do Worker limita a 1/dia por rotina)')
        } catch {
            Write-WatchLog ('AVISO: falha ao alertar rotina faltante: ' + $_.Exception.Message)
        }
    }
    exit 0
}
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
    if ($snap.versao -and $snap.versao -ne $VersaoEsperada -and -not $TomlRecente) {
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
