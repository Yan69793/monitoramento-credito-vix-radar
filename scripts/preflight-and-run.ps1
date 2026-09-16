# preflight-and-run.ps1 - guarda de execucao das rotinas agendadas deste repositorio.
#
# POR QUE ESTE ARQUIVO EXISTE
# As tarefas agendadas chamavam direto o script da rotina. Se a arvore estivesse quebrada
# (marcador de conflito commitado, .ps1 com sintaxe de PS 6/7 que o powershell.exe 5.1 nao
# parseia), a rotina subia, morria no meio e o Task Scheduler reportava o que o script
# conseguisse reportar - em varios casos LastTaskResult 0 com falha real. O guarda e o ponto
# unico por onde os pontos de entrada passam, e ele recusa ANTES de tocar no alvo.
#
# CONTRATO
#   - Varredura estatica do SUPERSETO de .ps1 do repo (git ls-files + git ls-files --others
#     --exclude-standard, menos as exclusoes lidas do disco em lint-encoding.ps1) sob
#     powershell.exe 5.1. Nunca de lista declarada: dot-source e montado com Join-Path em
#     runtime, entao lista declarada daria verde com dependencia quebrada.
#   - Recusa dura (exit 89) e o alvo NAO executa se qualquer arquivo do superseto nao parseia
#     no 5.1, contem marcador de conflito (^<<<<<<< / ^>>>>>>>) ou se o linter reprova.
#   - Fail-closed: se o parser de referencia nao puder rodar (powershell.exe fora do PATH,
#     timeout, saida ilegivel), RECUSA. Guarda que pula em silencio quando nao consegue checar
#     esta reprovado por definicao.
#   - Arvore apenas SUJA e conteudo que parseia = modo degradado com ALERTA, nao recusa. A
#     sujeira e o modo de operacao atual do repo; recusar por sujeira pura bloquearia a
#     operacao legitima.
#   - Primeira linha do log da rotina: head=<sha> branch=<ref> dirty=<n> linter=<RISCO>,
#     gravada antes de invocar o alvo (ver Add-PreflightStampDeferido na lib para as rotinas
#     cujo log tem carimbo de hora no proprio nome).
#   - O exit do alvo e propagado sem alteracao.
#
# USO (o alvo vai em -GuardTarget; os argumentos do alvo seguem sem traducao nenhuma):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\preflight-and-run.ps1 `
#     -GuardTarget scripts\run_vixradar_matinal_claude.ps1 `
#     -GuardName 'VIXRadar-Matinal' `
#     -GuardLogPattern 'logs\routines\vixradar-matinal_{yyyyMMdd}.log'
#
#   Com argumentos do alvo:
#     ... -GuardTarget scripts\run_claude_routine.ps1 -GuardName 'Szuchmacher-AgendaMacro-Claude' `
#         -GuardLogPattern 'logs\routines\agenda-macro-szuchmacher_{yyyyMMdd}.log' `
#         -RoutineId atualizar-agenda-macro-szuchmacher
#
# Parametros do guarda comecam todos com -Guard para nao colidir com argumento de rotina.
#
# EXIT
#   89  = o guarda recusou (alvo NAO executado). Motivo impresso e registrado em
#         logs\preflight\preflight_<data>.log
#   124 = o alvo estourou -GuardTimeoutSec e foi morto com a arvore
#   N   = exit do alvo, propagado
param(
    [Parameter(Mandatory = $true)][string]$GuardTarget,
    [string]$GuardName = '',
    [string]$GuardLogPattern = '',
    [string]$GuardRepoRoot = '',
    [int]$GuardTimeoutSec = 14400,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$GuardTargetArgs
)

$ErrorActionPreference = 'Continue'

$RecusaCode = 89
$lib = Join-Path $PSScriptRoot 'lib\vixradar-preflight.ps1'

function Stop-GuardLoc {
    # Recusa que NAO depende da lib: usada quando a propria lib nao carrega (merge conflict nela,
    # sintaxe que o 5.1 nao parseia). Sem esta funcao o guarda ficaria sem nenhuma funcao definida
    # e o exit cairia em 0 no fim do bloco - o pior resultado possivel, porque parece sucesso.
    param([string]$Motivo)
    $msg = 'PREFLIGHT RECUSA (exit 89): ' + $Motivo
    Write-Host $msg
    [Console]::Error.WriteLine($msg)
    exit $RecusaCode
}

if (-not (Test-Path -LiteralPath $lib)) { Stop-GuardLoc ('lib ausente: ' + $lib) }
$erroLib = ''
try { . $lib } catch { $erroLib = $_.Exception.Message }
if ($erroLib) { Stop-GuardLoc ('lib nao carregou: ' + $erroLib) }

# Contracto da lib conferido funcao por funcao: dot-source de arquivo quebrado nao e erro
# terminante sob $ErrorActionPreference='Continue', entao a unica prova confiavel de que a lib
# entrou inteira e a existencia das funcoes que o guarda usa.
$obrigatorias = @(
    'Resolve-PreflightRepoRoot', 'Resolve-PreflightPowerShell', 'Invoke-PreflightProcess',
    'Quote-PreflightArg', 'Get-PreflightGitState', 'Get-PreflightScan', 'Get-PreflightLinterRisco',
    'Test-PreflightLogDeferido', 'Resolve-PreflightLogPath', 'Write-PreflightStampLog',
    'Add-PreflightStampDeferido', 'Add-PreflightAudit'
)
foreach ($fn in $obrigatorias) {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
        Stop-GuardLoc ('lib carregou sem a funcao ' + $fn + '; confira ' + $lib)
    }
}

function Stop-PreflightRecusa {
    param([string]$Motivo, [string]$Root = '', [string]$Nome = '')
    $msg = 'PREFLIGHT RECUSA (exit 89): ' + $Motivo
    Write-Host $msg
    [Console]::Error.WriteLine($msg)
    if ($Root) {
        try {
            Add-PreflightAudit -Root $Root -Linha ('decisao=RECUSA89 nome=' + $Nome + ' target=' + $GuardTarget + ' motivo=' + $Motivo) | Out-Null
        } catch {
            # Auditoria direta, sem lib: a recusa nunca pode deixar de ser registrada.
            try {
                $dir = Join-Path $Root 'logs\preflight'
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                Add-Content -LiteralPath (Join-Path $dir ('preflight_' + (Get-Date -Format 'yyyyMMdd') + '.log')) -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' decisao=RECUSA89 nome=' + $Nome + ' target=' + $GuardTarget + ' motivo=' + $Motivo) -Encoding UTF8
            } catch { }
        }
    }
    exit $RecusaCode
}

$inicio = Get-Date
$nome = $GuardName
if (-not $nome) { $nome = [System.IO.Path]::GetFileNameWithoutExtension($GuardTarget) }

# ---------------------------------------------------------------------------
# 0. Raiz. Sem raiz nao ha log de auditoria: recusa seca.
# ---------------------------------------------------------------------------
$root = $GuardRepoRoot
if ($root) {
    if (-not (Test-Path -LiteralPath $root)) { Stop-PreflightRecusa -Motivo ('raiz informada inexistente: ' + $root) -Nome $nome }
    $root = (Resolve-Path -LiteralPath $root).Path
} else {
    $root = Resolve-PreflightRepoRoot -StartDir $PSScriptRoot
}
if (-not $root) { Stop-PreflightRecusa -Motivo 'nao foi possivel resolver a raiz do repositorio git (fail-closed)' -Nome $nome }
$root = $root.TrimEnd('\')

# ---------------------------------------------------------------------------
# 1. Alvo. Tem de existir e estar DENTRO da arvore que o guarda varre: o guarda so responde
#    pelo que ele verifica.
# ---------------------------------------------------------------------------
$target = $GuardTarget
if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path $root $GuardTarget }
if (-not (Test-Path -LiteralPath $target)) { Stop-PreflightRecusa -Motivo ('alvo inexistente: ' + $target) -Root $root -Nome $nome }
$target = (Resolve-Path -LiteralPath $target).Path
if (-not $target.StartsWith(($root + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
    Stop-PreflightRecusa -Motivo ('alvo fora do repositorio varrido: ' + $target + ' (raiz=' + $root + ')') -Root $root -Nome $nome
}

# ---------------------------------------------------------------------------
# 2. Parser de referencia. Sem ele nao ha verificacao possivel: fail-closed.
# ---------------------------------------------------------------------------
$psExe = Resolve-PreflightPowerShell
if (-not $psExe) {
    Stop-PreflightRecusa -Motivo 'powershell.exe nao resolve no PATH; sem o parser 5.1 de referencia o guarda nao pode verificar o superseto (fail-closed)' -Root $root -Nome $nome
}

# ---------------------------------------------------------------------------
# 3. Varredura do superseto.
# ---------------------------------------------------------------------------
$t0 = Get-Date
$scan = Get-PreflightScan -Root $root -PowerShellExe $psExe
$scanMs = [int]((Get-Date) - $t0).TotalMilliseconds
if (-not $scan.Ok) {
    Stop-PreflightRecusa -Motivo ('varredura do superseto NAO pode ser executada (fail-closed): ' + $scan.Erro) -Root $root -Nome $nome
}
$conflitos = @(@($scan.Json.conflito) | Where-Object { $_ })
$parses = @(@($scan.Json.parse) | Where-Object { $_ })
if ($conflitos.Count -gt 0 -or $parses.Count -gt 0) {
    $detalhe = @()
    foreach ($c in $conflitos) { $detalhe += ('conflito: ' + $c) }
    foreach ($p in $parses) { $detalhe += ('parse(' + $p.erros + '): ' + $p.arquivo + ' -> ' + $p.primeiro) }
    Stop-PreflightRecusa -Motivo ('arvore reprovada na varredura estatica (' + $detalhe.Count + ' arquivo(s)): ' + ($detalhe -join ' | ')) -Root $root -Nome $nome
}
$superset = [int]$scan.Json.superset

# ---------------------------------------------------------------------------
# 4. Linter canonico (RISCO). Executado, nunca recalculado aqui.
# ---------------------------------------------------------------------------
$lin = Get-PreflightLinterRisco -Root $root -PowerShellExe $psExe
if (-not $lin.Ok) {
    Stop-PreflightRecusa -Motivo ('linter NAO pode ser executado (fail-closed): ' + $lin.Erro) -Root $root -Nome $nome
}
if ($lin.Risco -gt 0) {
    Stop-PreflightRecusa -Motivo ('linter reprovou a arvore: RISCO=' + $lin.Risco) -Root $root -Nome $nome
}
$risco = [int]$lin.Risco

# ---------------------------------------------------------------------------
# 5. Estado do git e linha do guarda.
# ---------------------------------------------------------------------------
$git = Get-PreflightGitState -Root $root
if (-not $git) { Stop-PreflightRecusa -Motivo 'estado do git ilegivel (fail-closed)' -Root $root -Nome $nome }
$stamp = 'head=' + $git.Head + ' branch=' + $git.Branch + ' dirty=' + $git.Dirty + ' linter=' + $risco

$modo = 'normal'
if ($git.Dirty -gt 0) {
    $modo = 'degradado'
    Write-Host ('PREFLIGHT AVISO: arvore suja (dirty=' + $git.Dirty + ') - modo degradado, o conteudo parseia e a execucao segue') -ForegroundColor Yellow
}
if (-not $GuardLogPattern) {
    Write-Host 'PREFLIGHT AVISO: -GuardLogPattern ausente; o carimbo vai so para logs\preflight (a rotina nao recebe a primeira linha)' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 6. Carimbo no log da rotina, ANTES de invocar o alvo.
# ---------------------------------------------------------------------------
$deferido = Test-PreflightLogDeferido -Pattern $GuardLogPattern
$onde = 'sem-pattern'
if ($GuardLogPattern -and -not $deferido) {
    $onde = Write-PreflightStampLog -Path (Resolve-PreflightLogPath -Root $root -Pattern $GuardLogPattern -Agora (Get-Date)) -StampLine $stamp -Agora (Get-Date)
}
Add-PreflightAudit -Root $root -Linha ('inicio nome=' + $nome + ' target=' + $target + ' ' + $stamp + ' superset=' + $superset + ' scan_ms=' + $scanMs + ' modo=' + $modo + ' log=' + $onde + ' args=[' + (@($GuardTargetArgs) -join ' ') + ']') | Out-Null

Write-Host ('PREFLIGHT OK: ' + $stamp + ' superset=' + $superset + ' scan_ms=' + $scanMs + ' modo=' + $modo) -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# 7. Alvo. Console herdado (saida em tempo real), exit propagado.
# ---------------------------------------------------------------------------
$argLine = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (Quote-PreflightArg $target)
foreach ($a in @($GuardTargetArgs)) {
    if ($null -eq $a) { continue }
    if (('' + $a).Trim() -eq '') { continue }
    $argLine += ' ' + (Quote-PreflightArg ([string]$a))
}
$r = Invoke-PreflightProcess -Exe $psExe -ArgumentLine $argLine -TimeoutSec $GuardTimeoutSec -WorkingDirectory (Split-Path -Parent $target) -SemRedirecionar

if ($r.Timeout) {
    Add-PreflightAudit -Root $root -Linha ('fim nome=' + $nome + ' exit=124 timeout=' + $GuardTimeoutSec + 's') | Out-Null
    exit $script:PreflightExitTimeout
}

if ($deferido) {
    $ondeDepois = Add-PreflightStampDeferido -Root $root -Pattern $GuardLogPattern -StampLine $stamp -Inicio $inicio -Agora (Get-Date)
    Add-PreflightAudit -Root $root -Linha ('carimbo-deferido nome=' + $nome + ' resultado=' + $ondeDepois) | Out-Null
}

$dur = [int]((Get-Date) - $inicio).TotalSeconds
Add-PreflightAudit -Root $root -Linha ('fim nome=' + $nome + ' exit=' + $r.Exit + ' dur=' + $dur + 's') | Out-Null
exit $r.Exit
