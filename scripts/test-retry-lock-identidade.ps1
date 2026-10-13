# test-retry-lock-identidade.ps1 - prova do RETRYLOCK1 (2026-10-09).
#
# Incidente 09/10/2026: a noturna terminou as 18:09:03 (FIM: escrito) e o retry das 21:30:05
# registrou "VIVA: log atualizado ha 0 min, execucao em andamento. Pulo." - a recuperacao
# automatica nunca relancou nada. Causa raiz: a prova de vida era o mtime do log, e o proprio
# preflight do retry (apply-preflight-tasks.ps1 registra o retry com GuardLogPattern = log da
# rotina) carimba a primeira linha desse log ANTES de invocar o alvo - o mtime fica sempre fresco.
#
# Esta suite prova as duas pontas:
#   A) log com mtime FRESCO e SEM lock vivo -> o retry RELANCA (o defeito de 09/10 nao volta);
#   B) lock com PID VIVO (mesmo StartTime) -> o retry PULA (nao duplica execucao real);
#   C) lock com PID morto -> relanca;
#   D) lock com PID reutilizado (StartTime diferente) -> relanca.
# Offline: o "relancamento" e um stub .ps1 inerte (-RunnerOverride), -SemAlerta suprime o POST.
# ASCII puro, PS 5.1.
$ErrorActionPreference = 'Continue'

$script:ok = 0; $script:fal = 0
function Assert([bool]$c, [string]$m) { if ($c) { $script:ok++; Write-Host ('  OK    ' + $m) } else { $script:fal++; Write-Host ('  FALHA ' + $m) } }

$retryScript = Join-Path $PSScriptRoot 'retry-vixradar.ps1'
$lockLib     = Join-Path $PSScriptRoot 'lib\vixradar-lock.ps1'
. $lockLib

$providerOriginal = $env:VIXRADAR_LLM_PROVIDER
$env:VIXRADAR_LLM_PROVIDER = 'claude-subscription'

$tmp = Join-Path $env:TEMP ('vixretrylock_' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$dateTag = Get-Date -Format 'yyyyMMdd'
$logRot  = Join-Path $tmp ('vixradar-noturno_' + $dateTag + '.log')
$lockRot = Join-Path $tmp ('vixradar-noturno_' + $dateTag + '.lock')
$retLog  = Join-Path $tmp ('retry-vixradar-noturno_' + $dateTag + '.log')
$stub    = Join-Path $tmp 'stub_runner.ps1'

$procVivo = $null
try {
    Set-Content -LiteralPath $stub -Value "param([string]`$RoutineId, [string]`$Fallback429 = 'x')`nWrite-Output 'stub inerte'`nexit 0" -Encoding UTF8

    # ---------- 0: unitario da lib ----------
    Write-Host '=== 0: lib\vixradar-lock.ps1 (unitario) ==='
    $semLock = Get-VixLockState -Path (Join-Path $tmp 'nao_existe.lock') -AbandonoMin 0
    Assert ($semLock.bloqueia -eq $false -and $semLock.motivo -eq 'LOCK_ORFAO_AUSENTE') '0a: lock ausente -> nao bloqueia (LOCK_ORFAO_AUSENTE)'

    $lockMau = Join-Path $tmp 'mau.lock'
    Set-Content -LiteralPath $lockMau -Value 'sem_pid_aqui=1' -Encoding UTF8
    Assert (((Get-VixLockState -Path $lockMau -AbandonoMin 0).motivo) -eq 'LOCK_ORFAO_PID_INVALIDO') '0b: lock sem pid -> LOCK_ORFAO_PID_INVALIDO'

    # Processo vivo REAL: filho que dorme, para o lock ter PID + StartTime validos.
    $procVivo = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 60') -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 700
    $inicioVivo = $procVivo.StartTime.ToUniversalTime().ToString('o')
    # PID comprovadamente morto: processo iniciado e encerrado aqui mesmo.
    $procMorto = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-Command','exit 0') -PassThru -WindowStyle Hidden
    $pidMorto = $procMorto.Id
    try { $procMorto.WaitForExit(5000) | Out-Null } catch { }
    Start-Sleep -Milliseconds 400

    Set-Content -LiteralPath $lockMau -Value ("source=teste`nrotina=noturno`npid=" + $procVivo.Id + "`ninicio_utc=" + $inicioVivo) -Encoding UTF8
    $stVivo = Get-VixLockState -Path $lockMau -AbandonoMin 0
    Assert ($stVivo.bloqueia -eq $true -and $stVivo.motivo -eq 'LOCK_VIVO') '0c: PID vivo com StartTime igual -> LOCK_VIVO (bloqueia)'
    Assert ((Test-VixRotinaAtiva -LockPath $lockMau -AbandonoMin 0).ativa -eq $true) '0d: Test-VixRotinaAtiva.ativa = true'

    Set-Content -LiteralPath $lockMau -Value ("source=teste`nrotina=noturno`npid=" + $pidMorto + "`ninicio_utc=2026-01-01T00:00:00Z") -Encoding UTF8
    Assert (((Get-VixLockState -Path $lockMau -AbandonoMin 0).motivo) -eq 'LOCK_ORFAO_PID_MORTO') ('0e: PID morto (' + $pidMorto + ') -> LOCK_ORFAO_PID_MORTO')
    Set-Content -LiteralPath $lockMau -Value ("source=teste`nrotina=noturno`npid=" + $procVivo.Id + "`ninicio_utc=2020-01-01T00:00:00Z") -Encoding UTF8
    Assert (((Get-VixLockState -Path $lockMau -AbandonoMin 0).motivo) -eq 'LOCK_ORFAO_PID_REUTILIZADO') '0f: PID vivo com StartTime diferente -> LOCK_ORFAO_PID_REUTILIZADO'

    function Invoke-RetryT ([string]$rotulo) {
        Remove-Item -LiteralPath $retLog -Force -ErrorAction SilentlyContinue
        & powershell.exe -NoProfile -File $retryScript -RoutineId vixradar-noturno -RunnerOverride $stub -LogDirOverride $tmp -SemAlerta | Out-Null
        $exit = $LASTEXITCODE
        $txt = if (Test-Path $retLog) { Get-Content -LiteralPath $retLog -Raw -Encoding UTF8 } else { '' }
        return [pscustomobject]@{ Exit = $exit; Log = $txt; Rotulo = $rotulo }
    }
    function New-LogRotinaParadoFresh() {
        # Log do dia SEM entrega, com mtime FRESCO (como o preflight do retry deixa).
        Set-Content -LiteralPath $logRot -Value ('2026-10-09 18:05:04 INICIO: noturno (motor Task Scheduler)') -Encoding UTF8
        (Get-Item $logRot).LastWriteTime = (Get-Date).AddSeconds(-5)
    }

    # ---------- A: o defeito de 09/10 ----------
    Write-Host ''
    Write-Host '=== A: log com mtime FRESCO e SEM lock vivo -> RELANCA (defeito de 09/10) ==='
    Remove-Item -LiteralPath $lockRot -Force -ErrorAction SilentlyContinue
    New-LogRotinaParadoFresh
    $rA = Invoke-RetryT 'A'
    Assert (-not ($rA.Log -match 'VIVA: log atualizado')) 'A1: NAO pula mais por mtime fresco (a linha do incidente nao aparece)'
    Assert ($rA.Log -match 'SEM ENTREGA: sem execucao viva') 'A2: decide por identidade ("sem execucao viva")'
    Assert ($rA.Log -match 'RETRY EXIT:') 'A3: chegou ao relancamento de verdade'
    Assert ($rA.Exit -eq 1) ('A4: exit 1 quando o relancamento nao entrega (obtido ' + $rA.Exit + ')')

    # ---------- B: lock vivo -> pula ----------
    Write-Host ''
    Write-Host '=== B: lock com PID VIVO -> PULA (nao duplica execucao) ==='
    New-LogRotinaParadoFresh
    Set-Content -LiteralPath $lockRot -Value ("source=run_vixradar_varredura.ps1`nrotina=noturno`npid=" + $procVivo.Id + "`ninicio_utc=" + $inicioVivo) -Encoding UTF8
    $rB = Invoke-RetryT 'B'
    Assert ($rB.Exit -eq 0) ('B1: exit 0 (pulou limpo, obtido ' + $rB.Exit + ')')
    Assert ($rB.Log -match 'VIVA: lock') 'B2: registra VIVA pelo LOCK (nao pelo mtime)'
    Assert ($rB.Log -match 'LOCK_VIVO') 'B3: motivo e LOCK_VIVO'
    Assert (-not ($rB.Log -match 'RETRY EXIT:')) 'B4: nenhum relancamento com execucao viva'

    # ---------- C: PID morto -> relanca ----------
    Write-Host ''
    Write-Host '=== C: lock com PID MORTO -> RELANCA ==='
    New-LogRotinaParadoFresh
    Set-Content -LiteralPath $lockRot -Value ("source=run_vixradar_varredura.ps1`nrotina=noturno`npid=" + $pidMorto + "`ninicio_utc=2026-01-01T00:00:00Z") -Encoding UTF8
    $rC = Invoke-RetryT 'C'
    Assert ($rC.Log -match 'LOCK_ORFAO_PID_MORTO') 'C1: motivo LOCK_ORFAO_PID_MORTO'
    Assert ($rC.Log -match 'RETRY EXIT:') 'C2: relancou mesmo com lock orfao de PID morto'

    # ---------- D: PID reutilizado -> relanca ----------
    Write-Host ''
    Write-Host '=== D: lock com PID REUTILIZADO (StartTime diferente) -> RELANCA ==='
    New-LogRotinaParadoFresh
    Set-Content -LiteralPath $lockRot -Value ("source=run_vixradar_varredura.ps1`nrotina=noturno`npid=" + $procVivo.Id + "`ninicio_utc=2020-01-01T00:00:00Z") -Encoding UTF8
    $rD = Invoke-RetryT 'D'
    Assert ($rD.Log -match 'LOCK_ORFAO_PID_REUTILIZADO') 'D1: motivo LOCK_ORFAO_PID_REUTILIZADO'
    Assert ($rD.Log -match 'RETRY EXIT:') 'D2: relancou (PID reutilizado nao conta como vida)'

    # ---------- E: estatico ----------
    Write-Host ''
    Write-Host '=== E: o retry nao volta a julgar vida por mtime (estatico) ==='
    $srcRetry = Get-Content -LiteralPath $retryScript -Raw -Encoding UTF8
    Assert (-not ($srcRetry -match 'LastWriteTime\)\.TotalMinutes')) 'E1: heuristica "log mexeu nos ultimos 15 min" removida do julgamento de vida'
    Assert ($srcRetry -match 'Test-VixRotinaAtiva') 'E2: o retry usa a lib de lock'
    Assert ($srcRetry -match 'vixradar-lock\.ps1') 'E3: o retry carrega lib\vixradar-lock.ps1'

    Write-Host ''
    Write-Host '=== F: o motor e o retry usam a MESMA implementacao de lock ==='
    $srcMotor = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
    Assert ($srcMotor -match 'vixradar-lock\.ps1') 'F1: o motor carrega a lib de lock compartilhada'
    Assert (-not ($srcMotor -match "function Get-VixLockState")) 'F2: o motor NAO redefine Get-VixLockState (fonte unica, sem divergencia)'
}
finally {
    $env:VIXRADAR_LLM_PROVIDER = $providerOriginal
    if ($procVivo) { try { Stop-Process -Id $procVivo.Id -Force -ErrorAction SilentlyContinue } catch { } }
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
