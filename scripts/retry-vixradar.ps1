# retry-vixradar.ps1 - Retry automatico das rotinas VIX (noturno/matinal)
# quando a execucao via Claude Desktop nao entrega (sem linha FIM: valida no
# log do dia). ASCII puro (Task Scheduler, powershell.exe 5.1).
#
# Contexto (17/08/2026): as rotinas migraram do Task Scheduler para sessoes
# agendadas do Claude Desktop. A sessao entra em idle no meio do cascade e a
# rotina morre sem rastro (noturno 16/08, matinal 14/08). Este script roda via
# Task Scheduler apos a janela (noturno 13:30 diario, matinal 21:30 dias uteis;
# INVERSAO-CD1 25/08: o nome "noturno" roda de manha, "matinal" a noite) e, se o
# log do dia nao tem FIM valido, relanca a rotina via claude CLI usando
# run_claude_routine.ps1 (o pre-flight dele limpa o ambiente que quebrou o CLI
# em 04/08 e sonda WebSearch antes de rodar).
#
# Seguranca contra duplicata: a SKILL da rotina (Passo 0) tem lock de 3h e
# mutex. Execucao Desktop ainda viva segura o lock, o retry aborta limpo.
param(
    [Parameter(Mandatory)]
    [ValidateSet('vixradar-noturno', 'vixradar-matinal')]
    [string]$RoutineId,
    [string]$WorkerUrl = 'https://api.vixradar.com/'
)

$ErrorActionPreference = 'Continue'

$VixRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$Runner  = Join-Path $VixRoot 'scripts\run_claude_routine.ps1'
$LogDir  = Join-Path $VixRoot 'logs\routines'
$DateTag = Get-Date -Format 'yyyyMMdd'
$RotLog  = Join-Path $LogDir ($RoutineId + '_' + $DateTag + '.log')
$RetLog  = Join-Path $LogDir ('retry-' + $RoutineId + '_' + $DateTag + '.log')

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Add-Content -Path $RetLog -Value $line -Encoding UTF8
    Write-Host $line
}

# WATCHDOG-NAOINICIOU1 (auditoria 2026-08-29): rotina que nao iniciou era
# silencio total (exit 0), e o gap de 28/08 (app do Claude Desktop fechado)
# passou sem alerta nenhum. O retry roda DEPOIS da janela da rotina, entao log
# ausente no horario do retry significa sessao que nao disparou. Vira falha +
# alerta via action=notificar_rotina (mesmo canal do watch-vixradar-health.ps1,
# ROTINAGAP1), com dedup do Worker por rotina/dia (NOTIFYRL1). Sem relancamento:
# app fechado nao vai entregar de novo; o alerta e a acao correta.
if (-not (Test-Path $RotLog)) {
    $motivo = 'Rotina ' + $RoutineId + ' nao deixou log ate ' + (Get-Date -Format 'HH:mm') + ' BRT (janela do dia ja passou). Sessao Claude Desktop pode nao ter disparado (app fechado ou cron perdido).'
    Write-Log "SEM LOG: $RotLog nao existe, rotina nao iniciou. ALERTA."
    $rk = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
    if (-not $rk) {
        Write-Log 'AVISO: ROUTINE_API_KEY ausente do escopo User, alerta nao enviado'
    } else {
        try {
            $p = @{ action='notificar_rotina'; routine_key=$rk; rotina=('retry-' + $RoutineId); motivo=$motivo }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($p | ConvertTo-Json -Compress))
            Invoke-WebRequest -Uri $WorkerUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 30 -UseBasicParsing | Out-Null
            Write-Log 'ALERTA ROTINA enviado (dedup do Worker limita a 1/dia por rotina)'
        } catch {
            Write-Log ('AVISO: falha ao alertar rotina faltante: ' + $_.Exception.Message)
        }
    }
    exit 1
}

$conteudo = Get-Content $RotLog -Raw -Encoding UTF8

# FIMREAL: mesma leitura do monitor-tasks.ps1, linha FIM: com contador >= minimo
# significa entrega do dia. Noturno: min 90 de 103. Matinal: min 12 de 15-19.
#
# O denominador e OPCIONAL no 3o padrao (2026-08-19). A matinal escreveu tres
# formatos em quatro dias porque o SKILL.md dela, ao contrario do noturno, nunca
# exigiu formato fixo: "19/19 emissores processados" (17/08), "20/20 processados"
# (18/08) e "19 emissores processados" (15/08, sem denominador). Este ultimo nao
# casava e teria gerado retry falso, mesmo modo de falha que queimou uma sessao
# Claude Desktop em 17/08. Causa raiz fechada no SKILL.md da matinal (Passo 12,
# formato exigido igual ao do noturno); este regex e a guarda para log ja escrito
# e para drift futuro do formato.
$fims = [regex]::Matches($conteudo, '(?m)(?<!SHADOW_)FIM:\s*(.*?)\r?$')
$entregue = $false
foreach ($m in $fims) {
    $linha = $m.Groups[1].Value
    $n = -1
    if ($linha -match 'submit_ok=(\d+)') { $n = [int]$Matches[1] }
    elseif ($linha -match 'Total do dia (\d+)/\d+') { $n = [int]$Matches[1] }
    elseif ($linha -match '(\d+)(?:/\d+)?(?:\s+\S+)?\s+processados') { $n = [int]$Matches[1] }
    elseif ($linha -match 'processados=(\d+)') { $n = [int]$Matches[1] }
    if ($n -ge 12 -and $RoutineId -eq 'vixradar-matinal') { $entregue = $true; break }
    if ($n -ge 90 -and $RoutineId -eq 'vixradar-noturno') { $entregue = $true; break }
}

if ($entregue) {
    Write-Log "OK: log do dia tem FIM valido, entrega feita. Nada a fazer."
    exit 0
}

# ROTINACEGA2 (2026-08-19): fallback por contagem de nome unico, o mesmo que o
# monitor-tasks.ps1 usa. Aplicado aqui tambem de proposito: os dois leem o MESMO
# sinal, e sem isto um dia entregue sem linha FIM: (aconteceu em 11/08 e 14/08,
# 103 de 103 emissores sem linha de fecho) faria este watchdog relancar a rotina
# inteira a toa, que e o incidente caro de 17/08 se repetindo.
#
# O ledger OK| e evidencia mais confiavel que a linha de fecho: escrito por
# emissor logo apos cada submit confirmado, nao depende do modelo lembrar de
# fechar. Conferido contra os 14 logs reais de 19/08: onde o contador do FIM:
# parseia, ele bate exato com a contagem de nome unico.
$minimoLedger = 90
if ($RoutineId -eq 'vixradar-matinal') { $minimoLedger = 12 }
$vistos = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($m in [regex]::Matches($conteudo, '(?m)^[\d-]+ [\d:]+ OK\|([^|]+)\|')) {
    $nome = $m.Groups[1].Value.Trim()
    if ($nome) { [void]$vistos.Add($nome) }
}
if ($vistos.Count -ge $minimoLedger) {
    Write-Log ("OK POR LEDGER: sem FIM: valido, mas o ledger OK| tem " + $vistos.Count + " emissores distintos com submit confirmado (minimo " + $minimoLedger + "). Dia entregue, nao relanco.")
    exit 0
}
Write-Log ("Ledger OK| tem " + $vistos.Count + " emissor(es) distinto(s), minimo " + $minimoLedger + " - nao confirma entrega.")

# Execucao Desktop pode estar viva e lenta. Se o log mexeu nos ultimos 15 min,
# a rotina esta em andamento agora. O lock da skill decidiria no Passo 0, mas
# nao gastamos um run inteiro para descobrir.
$idadeMin = ((Get-Date) - (Get-Item $RotLog).LastWriteTime).TotalMinutes
if ($idadeMin -lt 15) {
    Write-Log "VIVA: log atualizado ha $([int]$idadeMin) min, execucao em andamento. Pulo."
    exit 0
}

Write-Log "SEM ENTREGA: log parado ha $([int]$idadeMin) min. Relancando $RoutineId via claude CLI."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Runner -RoutineId $RoutineId
$exit = $LASTEXITCODE
Write-Log "RETRY EXIT: $exit"
exit $exit
