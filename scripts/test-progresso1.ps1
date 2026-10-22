# test-progresso1.ps1 - PROGRESSO1: checkpoint por lote e deteccao de lote abandonado (F2/F3).
# Inclui a prova pedida na auditoria: processo MORTO (Stop-Process) no meio do lote 2 deixa o lote em voo
# registrado, o lote 1 fechado nao e acusado, e a retomada e reportada uma unica vez (idempotente).
# Usa processo filho proprio e pasta temporaria. Nao toca rotina real, mutex ou log real.
# Saida por exit code (0 = tudo passou).
$ErrorActionPreference = 'Continue'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $aqui 'lib\vixradar-progresso.ps1')
$falhas = 0
function Confere($nome, $cond) {
    if ($cond) { Write-Output ('OK    ' + $nome) } else { Write-Output ('FALHA ' + $nome); $script:falhas++ }
}
$tmp = Join-Path $env:TEMP ('progresso1_' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$path = Get-VixProgressoPath $tmp 'noturno' '20261021'
Confere 'nome do arquivo segue <rotina>_progresso_<data>.jsonl' ((Split-Path $path -Leaf) -eq 'noturno_progresso_20261021.jsonl')

# Processo filho: fecha o lote 1, inicia o lote 2 e fica vivo ate ser morto de fora.
$lib = Join-Path $aqui 'lib\vixradar-progresso.ps1'
$cmd = ". '" + $lib + "'; " +
    "Add-VixProgresso -Path '" + $path + "' -Evento 'LOTE_INICIO' -Lote 'full-1' -Empresas @('Alfa','Beta') | Out-Null; " +
    "Add-VixProgresso -Path '" + $path + "' -Evento 'LOTE_FECHADO' -Lote 'full-1' -Empresas @('Alfa','Beta') -Extra @{ ok = 2; fail = 0; tokens = 1000 } | Out-Null; " +
    "Add-VixProgresso -Path '" + $path + "' -Evento 'LOTE_INICIO' -Lote 'full-2' -Empresas @('Gama','Delta') | Out-Null; " +
    "Start-Sleep -Seconds 120"
$exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$p = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', $cmd) -WindowStyle Hidden -PassThru
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 30) {
    $ev = @(Read-VixProgresso $path)
    if (@($ev | Where-Object { $_.evento -eq 'LOTE_INICIO' -and $_.lote -eq 'full-2' }).Count -gt 0) { break }
    Start-Sleep -Milliseconds 300
}
$antes = @(Get-VixProgressoAbandonado $path)
Confere 'com o processo VIVO nada e acusado como abandonado' ($antes.Count -eq 0)
Stop-Process -Id $p.Id -Force
Start-Sleep -Milliseconds 800

# Ponta ruim: morto no meio do lote 2.
$ab = @(Get-VixProgressoAbandonado $path)
Confere ('processo morto: lote 2 em voo detectado (n=' + $ab.Count + ')') ($ab.Count -eq 1 -and $ab[0].lote -eq 'full-2')
Confere 'emissores do lote em voo preservados' ((@($ab[0].empresas) -join ',') -eq 'Gama,Delta')
Confere 'lote 1 fechado nao e acusado' (@($ab | Where-Object { $_.lote -eq 'full-1' }).Count -eq 0)

# Ponta boa: a retomada e reportada uma unica vez (idempotente).
$null = Add-VixProgresso -Path $path -Evento 'RETOMADA' -Lote 'full-2' -Empresas @('Gama', 'Delta') -Extra @{ pid_abandonado = [int]$ab[0].pid; inicio_abandonado = ('' + $ab[0].ts) }
$dep = @(Get-VixProgressoAbandonado $path)
Confere 'depois de RETOMADA registrada, nao repete o aviso' ($dep.Count -eq 0)

# PID reaproveitado: mesmo PID vivo, mas com outro inicio => conta como morto.
$path2 = Get-VixProgressoPath $tmp 'matinal' '20261021'
$linhaReuso = '{"ts":"2026-10-21T20:00:00Z","evento":"LOTE_INICIO","pid":' + $PID + ',"pid_inicio_utc":"2001-01-01T00:00:00.0000000Z","lote":"full-9","empresas":["X"]}' + "`n"
[System.IO.File]::AppendAllText($path2, $linhaReuso)
$reuso = @(Get-VixProgressoAbandonado $path2)
Confere 'PID reaproveitado por outro processo e tratado como morto' ($reuso.Count -eq 1)

# Instancia viva (este proprio processo, inicio igual) nunca e abandono.
$path3 = Get-VixProgressoPath $tmp 'sentinela' '20261021'
$null = Add-VixProgresso -Path $path3 -Evento 'LOTE_INICIO' -Lote 'sonnet-1' -Empresas @('Y')
Confere 'instancia viva (mesmo PID e inicio) nao e abandono' (@(Get-VixProgressoAbandonado $path3).Count -eq 0)

# Kill durante a escrita: ultima linha truncada e ignorada, o resto continua legivel.
$path4 = Get-VixProgressoPath $tmp 'noturno' '20261022'
[System.IO.File]::AppendAllText($path4, '{"ts":"2026-10-22T20:00:00Z","evento":"LOTE_INICIO","pid":999999,"lote":"full-1","empresas":["Z"]}' + "`n" + '{"ts":"2026-10-22T20:01:00Z","evento":"LOTE_FE')
$trunc = @(Read-VixProgresso $path4)
Confere 'linha truncada pelo kill e ignorada' ($trunc.Count -eq 1)
Confere 'lote com PID inexistente e acusado' (@(Get-VixProgressoAbandonado $path4).Count -eq 1)

# Fail-open: caminho nulo nao lanca.
Confere 'caminho nulo devolve falso sem lancar' ((Add-VixProgresso -Path $null -Evento 'LOTE_INICIO') -eq $false)

# Estatico: motor registra inicio, fechamento e retomada.
$f = Get-Content -LiteralPath (Join-Path $aqui 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
Confere 'motor: LOTE_INICIO antes da chamada' ($f.Contains("-Evento 'LOTE_INICIO'"))
Confere 'motor: LOTE_FECHADO apos o fechamento do lote' ($f.Contains("-Evento 'LOTE_FECHADO'"))
Confere 'motor: RETOMADA logada na partida' ($f.Contains("Write-Log ('RETOMADA|lote_em_voo_abandonado="))

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ('RESULTADO: falhas=' + $falhas)
exit $falhas
