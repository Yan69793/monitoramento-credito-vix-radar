# test-capfaixa1-16out.ps1 - CAPFAIXA1 (2026-10-16). Prova offline e sem token do defeito da
# noturna de 16/10 18:14: o primeiro lote (FULL, 2 emissores, envelope 787.037) nao cabia no cap
# de 700.000, o ramo `CAP pre-lote` fechava a faixa ($capAtingido) e os 3 lotes baratos seguintes
# (90.360, 90.360, 32.915) eram DEFERIDOS com acum=0. Resultado: 0 analisados, 0 tokens.
# Partes:
#   A estrutura do laco REAL (AST), duas pontas: motor de HEAD (ou -MotorAntigo) reprova, motor
#     atual aprova. O ramo `$__cabem -le 0` nao pode atribuir $capAtingido nem $capEscaladaFechado.
#   B replay da fila de 16/10 com as funcoes REAIS de admissao (lib/vixradar-cobertura.ps1) e um
#     MODELO da politica (fecha x nao fecha). B e modelo, nao o laco.
#   C o log real de 16/10 ainda mostra o sintoma (ancora do replay).
# ASCII puro, PowerShell 5.1. Saida: exit 0 = tudo verde, 1 = alguma falha.

param([string]$LogDir = '', [string]$MotorAntigo = '')
$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Cf([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
$Projeto = Split-Path $Scripts -Parent
$MotorPath = Join-Path $Scripts 'run_vixradar_varredura.ps1'
if (-not $LogDir) { $LogDir = Join-Path $Projeto 'logs\routines' }
. (Join-Path $Scripts 'lib\vixradar-cobertura.ps1')

function Get-CapFaixaEstrutura([string]$Path) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    $r = @{ parse_ok = ($errors.Count -eq 0); achou = $false; fecha = $true; defere = $false }
    if (-not $r.parse_ok) { return $r }
    $ifs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$__cabem -le 0' }, $true))
    if ($ifs.Count -eq 0) { return $r }
    $r.achou = $true
    $corpo = $ifs[0].Clauses[0].Item2
    $atrib = @($corpo.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -match '^\$(capAtingido|capEscaladaFechado)$' }, $true))
    $r.fecha = ($atrib.Count -gt 0)
    $r.defere = ($corpo.Extent.Text -match '\$pendingDeferred\.Add')
    return $r
}

Write-Host '== A estrutura do laco real =='
$atual = Get-CapFaixaEstrutura $MotorPath
Assert-Cf ($atual.parse_ok -and $atual.achou) 'A1 motor atual parseia e tem o ramo CAP pre-lote'
Assert-Cf (-not $atual.fecha) 'A2 motor atual: CAP pre-lote nao fecha a faixa pela estimativa'
Assert-Cf $atual.defere 'A3 motor atual: CAP pre-lote continua deferindo o lote que nao cabe'
$antigoPath = $MotorAntigo
$tmpAntigo = $null
if (-not $antigoPath) {
    $tmpAntigo = Join-Path ([System.IO.Path]::GetTempPath()) ('capfaixa1_head_' + [guid]::NewGuid().ToString('N') + '.ps1')
    $src = & git -C $Projeto show 'HEAD:scripts/run_vixradar_varredura.ps1' 2>$null
    if ($LASTEXITCODE -eq 0 -and $src) { [System.IO.File]::WriteAllText($tmpAntigo, ($src -join "`r`n"), (New-Object System.Text.UTF8Encoding($true))); $antigoPath = $tmpAntigo }
}
if ($antigoPath -and (Test-Path -LiteralPath $antigoPath)) {
    $ant = Get-CapFaixaEstrutura $antigoPath
    Assert-Cf ($ant.achou -and $ant.fecha) 'A4 motor anterior (HEAD) reprova: CAP pre-lote fechava a faixa'
} else {
    Assert-Cf $false 'A4 motor anterior indisponivel para a ponta ruim'
}
if ($tmpAntigo -and (Test-Path -LiteralPath $tmpAntigo)) { Remove-Item -LiteralPath $tmpAntigo -Force }

Write-Host '== B replay da noturna de 16/10 com a admissao real =='
$cap = [int64]700000
# Envelopes do log real: FULL 393.519/emissor (n_min 2), BARATO 6.024/emissor (lote de 15 = 90.360).
# FULL com 3 amostras (classe_n3 no log) e menor lote medido de 2: abaixo dele o envelope nao vale.
$amFull = @(@{ emissores = 2; trabalho = 629630 }, @{ emissores = 3; trabalho = 944445 }, @{ emissores = 4; trabalho = 1259260 })
$mFull = Get-VixModeloLoteClasse -Amostras $amFull -DefaultEmissor 314815
$mBar = Get-VixModeloLoteClasse -Amostras @() -DefaultEmissor 4819
$fila = @(
    @{ nome = 'full-1'; modelo = $mFull; n = 2; real = 300000 },
    @{ nome = 'light-2'; modelo = $mBar; n = 15; real = 40000 },
    @{ nome = 'light-3'; modelo = $mBar; n = 15; real = 40000 },
    @{ nome = 'light-4'; modelo = $mBar; n = 3; real = 12000 }
)
function Invoke-CapFaixaModelo([string]$Politica) {
    $acum = [int64]0; $rodou = 0; $deferidos = 0; $fechada = $false; $maxAdm = [int64]0
    foreach ($l in $fila) {
        $cabem = if ($fechada) { 0 } else { Get-VixEmissoresQueCabemModelo -Modelo $l.modelo -Acum $acum -Cap $cap -Chunk $l.n }
        if ($cabem -le 0) { $deferidos += $l.n; if ($Politica -eq 'antiga') { $fechada = $true }; continue }
        $est = [int64](Get-VixEstimativaLoteClasse -Modelo $l.modelo -Emissores $cabem)
        if (($acum + $est) -gt $maxAdm) { $maxAdm = $acum + $est }
        $deferidos += ($l.n - $cabem)
        $acum += [int64]$l.real; $rodou += $cabem
    }
    return @{ rodou = $rodou; deferidos = $deferidos; acum = $acum; max_admitido = $maxAdm }
}
$a = Invoke-CapFaixaModelo 'antiga'
$n = Invoke-CapFaixaModelo 'nova'
Write-Host ('  antiga: rodou=' + $a.rodou + ' deferidos=' + $a.deferidos + ' | nova: rodou=' + $n.rodou + ' deferidos=' + $n.deferidos + ' acum=' + $n.acum + ' max_admitido=' + $n.max_admitido)
Assert-Cf ($a.rodou -eq 0 -and $a.deferidos -eq 35) 'B1 politica antiga reproduz o log real (0 roda, 35 DEFERIDOS)'
Assert-Cf ($n.rodou -eq 33) 'B2 politica nova roda os 33 emissores dos lotes baratos'
Assert-Cf ($n.max_admitido -le $cap) 'B3 politica nova nunca admite lote com acum+estimativa acima do cap'
Assert-Cf (($n.rodou + $n.deferidos) -eq 35) 'B4 todo emissor tem desfecho, nenhum some'
$capCurto = [int64]50000
$cap = $capCurto
$nc = Invoke-CapFaixaModelo 'nova'
Assert-Cf ($nc.max_admitido -le $capCurto -and $nc.rodou -lt 33) 'B5 cap curto: politica nova continua respeitando o cap (nao inventa orcamento)'
$cap = [int64]700000

Write-Host '== C ancora no log real de 16/10 =='
$logN = Join-Path $LogDir 'vixradar-noturno_20261016.log'
if (Test-Path -LiteralPath $logN) {
    $l = @(Get-Content -LiteralPath $logN -Encoding UTF8)
    Assert-Cf (@($l | Where-Object { $_ -match 'CAP pre-lote: acum=0 ' }).Count -eq 4) 'C1 os 4 lotes da noturna real cairam em CAP pre-lote com acum=0'
    Assert-Cf (@($l | Where-Object { $_ -match 'CAP pre-lote: acum=0 est=90360 ' }).Count -eq 2) 'C2 lotes baratos de 90.360 foram deferidos contra cap de 700.000'
    Assert-Cf (@($l | Where-Object { $_ -match 'FIM: noturno .*analisados_execucao=0 .*tokens=0 ' }).Count -eq 1) 'C3 FIM real: 0 analisados e 0 tokens'
} else {
    Write-Host '  (log de 16/10 ausente, parte C pulada)'
}

Write-Host '== D SEMTETO1: teto desligado so com Claude da assinatura e SEM_TETO=1 =='
. (Join-Path $Scripts 'lib\vixradar-custo.ps1')
Assert-Cf (Test-VixSemTeto -Config @{ SEM_TETO = 1 } -Provider 'claude-subscription') 'D1 SEM_TETO=1 + claude-subscription desliga o teto'
Assert-Cf (-not (Test-VixSemTeto -Config @{ SEM_TETO = 1 } -Provider 'codex')) 'D2 codex mantem o teto mesmo com SEM_TETO=1'
Assert-Cf (-not (Test-VixSemTeto -Config @{ SEM_TETO = 1 } -Provider 'openrouter')) 'D3 openrouter (pago) mantem o teto'
Assert-Cf (-not (Test-VixSemTeto -Config @{ SEM_TETO = 0 } -Provider 'claude-subscription')) 'D4 SEM_TETO=0 mantem o teto'
Assert-Cf (-not (Test-VixSemTeto -Config @{ TETO_DIA = 2600000 } -Provider 'claude-subscription')) 'D5 config sem a chave mantem o teto'
$tmpCfg = Join-Path ([System.IO.Path]::GetTempPath()) ('semteto1_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpCfg | Out-Null
[System.IO.File]::WriteAllText((Join-Path $tmpCfg 'custo-config.json'), '{"TETO_DIA":2600000,"SEM_TETO":1}')
$cfgLida = Get-VixCustoConfig $tmpCfg
Remove-Item -LiteralPath $tmpCfg -Recurse -Force
Assert-Cf ($cfgLida.ContainsKey('SEM_TETO') -and [int64]$cfgLida.SEM_TETO -eq 1) 'D6 Get-VixCustoConfig le SEM_TETO do arquivo'
$motorTxt = [System.IO.File]::ReadAllText($MotorPath)
# CAPACIDADE2 (22/10/2026): "provider ativo" passou a ser o EFETIVO (desvio de boot para OpenRouter nao herda
# o claude-subscription da env). O literal antigo, que liberava SEM_TETO em consumo pago, nao pode voltar.
Assert-Cf ($motorTxt -match 'Test-VixSemTeto -Config \$custoCfg -Provider \(Get-VixProviderEfetivo \(Get-VixLlmProvider\) \(\[bool\]\$script:VixUsaOpenRouter\) \(\[bool\]\$script:VixUsaCodex\)\)') 'D7 motor decide pelo Test-VixSemTeto com o provider EFETIVO'
Assert-Cf (-not ($motorTxt -match 'Test-VixSemTeto -Config \$custoCfg -Provider \(Get-VixLlmProvider\) \}')) 'D7b literal antigo (provider so da env) nao pode voltar'

Write-Host ('RESULTADO: ok=' + $script:Ok + ' falhas=' + $script:Falhas)
if ($script:Falhas -gt 0) { exit 1 }
exit 0
