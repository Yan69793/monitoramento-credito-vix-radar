# test-monitor-funcoes.ps1 - guarda generica contra a classe do OR402-DEGRADA1.
#
# Em 11/09 o monitor-tasks.ps1 passou a CHAMAR Get-VixDegradado402 e a funcao nunca foi
# escrita. Com $ErrorActionPreference = 'Continue' o cmdlet inexistente so registra
# CommandNotFoundException, o foreach iterava zero vezes e o aviso nunca saiu, por dias,
# sem ninguem ver. Em 13/09 a mesma armadilha foi arriscada de novo com Get-VixDrenoFalha.
#
# Esta guarda fecha a classe inteira: toda funcao *-Vix* que o monitor chama precisa existir
# em um dos arquivos que ele proprio carrega (o monitor ou as libs que ele dot-sourceia).
# Nao executa nada, so faz AST dos arquivos. ASCII puro, PS 5.1, sem rede.
$ErrorActionPreference = 'Continue'
$script:ok = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:ok++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

$scriptDir = $PSScriptRoot
$monitorPath = Join-Path $scriptDir 'monitor-tasks.ps1'
$src = Get-Content $monitorPath -Raw -Encoding UTF8

function Get-FuncoesDefinidas([string]$path) {
    $toks = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$toks, [ref]$errs)
    if (@($errs).Count -gt 0) { throw ('parse de ' + $path + ' falhou: ' + $errs[0].Message) }
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    return @($defs | ForEach-Object { $_.Name })
}

# Libs que o monitor carrega: lidas do proprio fonte, nunca de lista chumbada aqui, para a
# guarda acompanhar o monitor se ele passar a carregar outra lib.
$libs = @()
foreach ($m in [regex]::Matches($src, "Join-Path\s+\`$ScriptDir\s+'lib\\([^']+)'")) { $libs += ('lib\' + $m.Groups[1].Value) }
$arquivos = @('monitor-tasks.ps1') + @($libs | Select-Object -Unique)
Write-Host ('=== fontes carregadas pelo monitor: ' + ($arquivos -join ', ') + ' ===')

$definidas = @()
foreach ($f in $arquivos) {
    $p = Join-Path $scriptDir $f
    if (-not (Test-Path $p)) { Write-Host ('  FALHA arquivo declarado no monitor nao existe: ' + $f); $script:fal++; continue }
    $definidas += (Get-FuncoesDefinidas $p)
}
$definidas = @($definidas | Select-Object -Unique)

# Nomes chamados no monitor que tem cara de funcao do projeto.
$toks2 = $null; $errs2 = $null
$astMon = [System.Management.Automation.Language.Parser]::ParseFile($monitorPath, [ref]$toks2, [ref]$errs2)
$cmds = $astMon.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
$chamadas = @()
foreach ($c in $cmds) {
    if ($c.CommandElements.Count -lt 1) { continue }
    $nome = $c.GetCommandName()
    if (-not $nome) { continue }
    if ($nome -match '-Vix') { $chamadas += $nome }
}
$chamadas = @($chamadas | Select-Object -Unique | Sort-Object)

Write-Host ('=== ' + $chamadas.Count + ' funcao(oes) do projeto chamadas pelo monitor ===')
$orfaos = @()
foreach ($n in $chamadas) {
    if ($definidas -contains $n) { Write-Host ('  OK    ' + $n + ' definida em um dos ' + $arquivos.Count + ' arquivo(s) carregado(s)') }
    else { Write-Host ('  FALHA ' + $n + ' CHAMADA E NAO DEFINIDA em nenhum arquivo que o monitor carrega'); $orfaos += $n }
}
Assert ($orfaos.Count -eq 0) ('nenhuma chamada orfa (orfas=' + $orfaos.Count + $(if ($orfaos.Count -gt 0) { ' -> ' + ($orfaos -join ', ') } else { '' }) + ')')
Assert ($chamadas.Count -gt 5) ('guarda esta lendo o monitor de verdade (chamadas=' + $chamadas.Count + ')')
Assert ($definidas.Count -gt 10) ('guarda esta lendo as libs de verdade (funcoes definidas=' + $definidas.Count + ')')

# Ponta ruim declarada: o conjunto de definidas nao pode conter nome inventado, senao a
# guarda passaria por acidente (comparacao sempre verdadeira) em vez de por leitura real.
Assert (-not ($definidas -contains 'Get-VixFuncaoQueNaoExiste')) 'ponta ruim: nome inventado nao esta no conjunto de definidas'

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
