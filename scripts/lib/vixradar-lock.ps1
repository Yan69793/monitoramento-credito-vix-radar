# vixradar-lock.ps1 - identidade de execucao das rotinas (fonte unica de "a rotina esta viva?").
# ASCII puro (PowerShell 5.1). Dot-source: . (Join-Path $ScriptsDir 'lib\vixradar-lock.ps1')
#
# LOCKIDENT1 (2026-10-09): ate aqui a prova de vida era a idade do ARQUIVO DE LOG, e ela
# mente. scripts\preflight-and-run.ps1 carimba a primeira linha do log da rotina ANTES de
# invocar o alvo, e apply-preflight-tasks.ps1 registra o RETRY com GuardLogPattern apontando
# para o log da PROPRIA rotina (logs\routines\vixradar-noturno_{yyyyMMdd}.log). Resultado:
# toda execucao do retry deixa o mtime do log em "agora" e a heuristica de 15 min lia
# "VIVA: execucao em andamento" para uma noturna que havia terminado horas antes. Medido
# em 09/10/2026: noturna terminou 18:09:03 (FIM escrito), o retry das 21:30:05 viu
# "log atualizado ha 0 min" e pulou - recuperacao automatica morta ha dias.
#
# A fonte de verdade passa a ser o LOCK que o motor escreve no inicio da execucao
# (run_vixradar_varredura.ps1) com `pid` e `inicio_utc`. O lock prova IDENTIDADE: so bloqueia
# quando o processo que o escreveu continua vivo COM o mesmo StartTime. PID sozinho pode ser
# reutilizado pelo Windows depois de um crash, entao a comparacao de inicio e obrigatoria.
#
# Contrato das funcoes:
#   Get-VixLockState  -Path <lock> [-AbandonoMin <n>] -> objeto { bloqueia; motivo; pid; inicio_utc }
#                       motivos: LOCK_ORFAO_AUSENTE|ILEGIVEL|PID_INVALIDO|INICIO_INVALIDO|
#                                PID_MORTO|PROCESSO_INACESSIVEL|PID_REUTILIZADO, ou LOCK_VIVO.
#   Test-VixRotinaAtiva -LockPath <lock> [-AbandonoMin <n>] -> objeto { ativa; motivo; pid }
#
# Compatibilidade: Get-VixLockState tem a MESMA assinatura e a MESMA semantica da copia que
# vivia dentro de run_vixradar_varredura.ps1; aquela copia foi removida e este lib passou a
# ser a unica implementacao (evita divergencia entre motor e retry).

function Get-VixLockState([string]$Path, [int]$AbandonoMin) {
    $out = [pscustomobject]@{ bloqueia = $false; motivo = 'LOCK_ORFAO_AUSENTE'; pid = $null; inicio_utc = $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $out }
    $dados = @{}
    try {
        foreach ($linha in @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)) {
            if ($linha -match '^([^=]+)=(.*)$') { $dados[$Matches[1].Trim().ToLowerInvariant()] = $Matches[2].Trim() }
        }
    } catch { $out.motivo = 'LOCK_ORFAO_ILEGIVEL'; return $out }
    $pidLock = 0
    if (-not $dados.ContainsKey('pid') -or -not [int]::TryParse($dados['pid'], [ref]$pidLock) -or $pidLock -le 0) {
        $out.motivo = 'LOCK_ORFAO_PID_INVALIDO'; return $out
    }
    $inicioTxt = ''
    if ($dados.ContainsKey('inicio_utc')) { $inicioTxt = $dados['inicio_utc'] }
    elseif ($dados.ContainsKey('inicio')) { $inicioTxt = $dados['inicio'] }
    $inicioLock = [datetime]::MinValue
    if (-not $inicioTxt -or -not [datetime]::TryParse($inicioTxt, [ref]$inicioLock)) {
        $out.motivo = 'LOCK_ORFAO_INICIO_INVALIDO'; $out.pid = $pidLock; return $out
    }
    $out.pid = $pidLock
    $out.inicio_utc = $inicioLock.ToUniversalTime()
    try { $proc = Get-Process -Id $pidLock -ErrorAction Stop }
    catch { $out.motivo = 'LOCK_ORFAO_PID_MORTO'; return $out }
    try { $inicioProc = $proc.StartTime.ToUniversalTime() }
    catch { $out.motivo = 'LOCK_ORFAO_PROCESSO_INACESSIVEL'; return $out }
    if ([math]::Abs(($inicioProc - $out.inicio_utc).TotalSeconds) -gt 2) {
        $out.motivo = 'LOCK_ORFAO_PID_REUTILIZADO'; return $out
    }
    $out.bloqueia = $true
    $out.motivo = 'LOCK_VIVO'
    return $out
}

# Resposta curta para quem so precisa decidir "relanco ou nao": ativa e o mesmo sinal que
# bloqueia o motor, e por isso o retry pode confiar nele sem reinterpretar idade de arquivo.
function Test-VixRotinaAtiva([string]$LockPath, [int]$AbandonoMin = 30) {
    $st = Get-VixLockState -Path $LockPath -AbandonoMin $AbandonoMin
    return [pscustomobject]@{ ativa = [bool]$st.bloqueia; motivo = $st.motivo; pid = $st.pid }
}
