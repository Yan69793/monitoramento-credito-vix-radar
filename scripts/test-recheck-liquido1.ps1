# test-recheck-liquido1.ps1 - RECHECKLIQUIDO1 (2026-10-22), offline.
# Prova que pendentes_obrigatorios conta o recheck pelo estado FINAL de cada emissor na
# execucao, e nao pelos disparos do portao. Caso real: noturna de 21/10, 4 disparos
# (Bradesco, VLI, MRS, Itausa), 3 resolvidos no FULL da mesma noite, 1 inconclusivo.
# Extrai por AST as funcoes REAIS do motor. ASCII puro (PS 5.1 e pwsh 7), sem rede, sem Worker.
param([string]$LogReal = '')
$ErrorActionPreference = 'Continue'
$fail = 0; $pass = 0
function Assert-Rl([bool]$cond, [string]$nome) {
    if ($cond) { $script:pass++; Write-Host ('PASS: ' + $nome) } else { $script:fail++; Write-Host ('FAIL: ' + $nome) }
}
function Get-FuncDefsFromText([string]$Texto, [string[]]$Names) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Texto, [ref]$tokens, [ref]$errors)
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $out = @{}
    foreach ($name in $Names) { $f = $defs | Where-Object { $_.Name -eq $name } | Select-Object -First 1; if ($f) { $out[$name] = $f.Extent.Text } }
    return $out
}

$Raiz = Split-Path $PSScriptRoot -Parent
$MotorPath = Join-Path $Raiz 'scripts\run_vixradar_varredura.ps1'
$motor = [System.IO.File]::ReadAllText($MotorPath, [System.Text.Encoding]::UTF8)
$defs = Get-FuncDefsFromText $motor @('Get-NomeNormalizado', 'Update-VixRecheckExecucao')
Assert-Rl ($defs.ContainsKey('Update-VixRecheckExecucao')) 'S0 motor atual define Update-VixRecheckExecucao'
foreach ($k in $defs.Keys) { Invoke-Expression $defs[$k] }

$itausa = 'Ita' + [char]0xFA + 'sa'
$mrs = 'MRS Log' + [char]0xED + 'stica'

Write-Host '== Cenario 21/10 (sequencia da noturna) =='
$m = @{}
$eventos = 0
foreach ($e in @('Bradesco', 'VLI', $mrs)) { Update-VixRecheckExecucao $m $e $true; $eventos++ }
foreach ($e in @('Bradesco', 'VLI', $mrs)) { Update-VixRecheckExecucao $m $e $false }
Update-VixRecheckExecucao $m $itausa $true; $eventos++
Assert-Rl ($eventos -eq 4) 'C1 regra antiga (disparos) daria 4'
Assert-Rl ($m.Count -eq 1) ('C2 estado final da execucao = 1 pendente (obtido ' + $m.Count + ')')
Assert-Rl (@($m.Values) -contains $itausa) 'C3 o pendente que sobra e a Itausa'

Write-Host '== Duas pontas =='
$m2 = @{}
Update-VixRecheckExecucao $m2 'Vibra Energia' $true
Assert-Rl ($m2.Count -eq 1) 'D1 ponta ruim: pendente nunca resolvido continua contando'
Update-VixRecheckExecucao $m2 'Vibra Energia' $true
Assert-Rl ($m2.Count -eq 1) 'D2 mesmo emissor disparando duas vezes conta uma'
Update-VixRecheckExecucao $m2 'Light' $false
Assert-Rl ($m2.Count -eq 1) 'D3 resolver quem nao estava pendente nao desconta outro'
Update-VixRecheckExecucao $m2 'VIBRA ENERGIA' $false
Assert-Rl ($m2.Count -eq 0) 'D4 ponta boa: resolucao no mesmo nome normalizado zera'
$m3 = @{}
Update-VixRecheckExecucao $m3 $itausa $true
Update-VixRecheckExecucao $m3 'Itausa' $false
Assert-Rl ($m3.Count -eq 0) 'D5 acento nao separa o mesmo emissor'

Write-Host '== Ligacao no motor =='
Assert-Rl ($motor -match '\$stats\.recheck_pendentes_final \+ \[int\]\$stats\.submit_fail' -or $motor -match '\[int\]\$stats\.recheck_pendentes_final \+ \[int\]\$stats\.submit_fail') 'L1 pendentes_obrigatorios usa recheck_pendentes_final'
Assert-Rl (-not ($motor -match '\[int\]\$stats\.cobertura_deferidos \+ \[int\]\$stats\.submit_fail')) 'L2 formula nao soma mais os disparos'
Assert-Rl ($motor -match 'cobertura_deferidos\+\+\s*\r?\n\s*Update-VixRecheckExecucao \$recheckExecucao \$emp\.empresa \$true') 'L3 disparo do portao marca pendente'
Assert-Rl ($motor -match 'if \(\$__concluida -and -not \$__decAus\.recheck\) \{ Remove-VixPendenteSeguro \$emp\.empresa; Update-VixRecheckExecucao \$recheckExecucao \$emp\.empresa \$false \}') 'L4 so analise concluida sem recheck desmarca'
Assert-Rl ($motor -match '\$recheckExecucao = @\{\}') 'L5 mapa inicializado'

Write-Host '== Ponta ruim contra o HEAD =='
$head = ''
try { $head = (& git -C $Raiz show 'HEAD:scripts/run_vixradar_varredura.ps1' 2>$null) -join "`n" } catch { }
if ($head) {
    Assert-Rl ($head -match '\[int\]\$stats\.cobertura_deferidos \+ \[int\]\$stats\.submit_fail') 'H1 HEAD soma disparos (reproduz o 4 de 21/10)'
    Assert-Rl (-not ((Get-FuncDefsFromText $head @('Update-VixRecheckExecucao')).ContainsKey('Update-VixRecheckExecucao'))) 'H2 HEAD nao tem a funcao'
} else { Write-Host 'SKIP: git indisponivel para ler o HEAD' }

if ($LogReal -and (Test-Path -LiteralPath $LogReal)) {
    Write-Host '== Replay do log real (ultima execucao do arquivo) =='
    $linhas = [System.IO.File]::ReadAllLines($LogReal, [System.Text.Encoding]::UTF8)
    $ini = 0
    for ($i = 0; $i -lt $linhas.Count; $i++) { if ($linhas[$i] -match ' ESCALADA_FULL: ativo=') { $ini = $i } }
    $mr = @{}; $disp = 0; $fimPend = -1; $fimInc = -1
    for ($i = $ini; $i -lt $linhas.Count; $i++) {
        $l = $linhas[$i]
        if ($l -match ' RECHECK_PENDENTE\|([^|]+)\|') { Update-VixRecheckExecucao $mr $Matches[1] $true; $disp++ }
        elseif ($l -match ' RECHECK_RESOLVIDO\|([^|]+)\|') { Update-VixRecheckExecucao $mr $Matches[1] $false }
        if ($l -match ' FIM: .*\bpendentes_obrigatorios=(\d+)') { $fimPend = [int]$Matches[1] }
        if ($l -match ' FIM: .*\bcontrato_inconclusivo=(\d+)') { $fimInc = [int]$Matches[1] }
    }
    Write-Host ('replay: disparos=' + $disp + ' final=' + $mr.Count + ' FIM_pendentes=' + $fimPend + ' FIM_contrato_inconclusivo=' + $fimInc + ' restantes=' + (@($mr.Values) -join ','))
    Assert-Rl ($fimPend -eq $disp) 'R1 o FIM gravado bate com a regra antiga (disparos)'
    Assert-Rl ($mr.Count -eq $fimInc) 'R2 a regra nova bate com o contrato do dia (INCONCLUSIVO)'
}

Write-Host ('RESULTADO: pass=' + $pass + ' fail=' + $fail)
if ($fail -gt 0) { exit 1 }
exit 0
