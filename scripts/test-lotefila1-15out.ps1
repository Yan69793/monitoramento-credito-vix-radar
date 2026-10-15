# test-lotefila1-15out.ps1 - LOTEFILA1 (2026-10-15). Prova offline e sem token dos dois defeitos
# da fila de lotes do motor medidos na matinal de 15/10 10:06:
#   D1 emissor retido para escalada sumia (sem ANALISADO, sem DEFERIDO) quando o ultimo lote
#      barato saia por `continue`: a montagem da escalada ficava no fim do corpo do laco.
#      Log real: `RECONCILIACAO_DIA ... sem_registro=1 ... sem_registro_nomes=Pao de Acucar (GPA)`.
#   D2 lote encolhido por orcamento fechava a faixa ($capAtingido) pela ESTIMATIVA, antes de rodar:
#      312.500 estimado, 21.416 real, 19 emissores de maior EWS DEFERIDOS com 378.584 livres.
# Partes:
#   A estrutura do laco REAL (AST), duas pontas: motor de HEAD (ou -MotorAntigo) reprova, motor
#     atual aprova.
#   B replay da matinal de 15/10 com as funcoes REAIS de admissao (lib/vixradar-cobertura.ps1) e
#     um MODELO da politica de fila (antiga x nova). B e modelo, nao o laco: prova a aritmetica
#     da admissao e que a politica nova nunca admite lote acima do cap.
#   C o log real de 15/10 ainda mostra os dois sintomas (ancora do replay).
# ASCII puro, PowerShell 5.1. Saida: exit 0 = tudo verde, 1 = alguma falha.

param([string]$LogDir = '', [string]$MotorAntigo = '')
$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Lf([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
$Projeto = Split-Path $Scripts -Parent
$MotorPath = Join-Path $Scripts 'run_vixradar_varredura.ps1'
if (-not $LogDir) { $LogDir = Join-Path $Projeto 'logs\routines' }
. (Join-Path $Scripts 'lib\vixradar-cobertura.ps1')

function Get-LoteFilaEstrutura([string]$Path) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    $r = @{ parse_ok = ($errors.Count -eq 0); achou = $false; cond_monta = $false; monta_primeiro = $false
            continue_antes_monta = 0; reduz_achado = $false; reduz_defere = $true; reduz_fecha = $true; reduz_reenfileira = $false }
    if (-not $r.parse_ok) { return $r }
    $loops = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.WhileStatementAst] -and $n.Condition.Extent.Text -match '\$__filaLotes\.Count' }, $true))
    if ($loops.Count -eq 0) { return $r }
    $w = $loops[0]; $r.achou = $true
    $r.cond_monta = ($w.Condition.Extent.Text -match '-not\s+\$__escaladaMontada')
    $stm = @($w.Body.Statements)
    $monta = $null
    foreach ($s in $stm) {
        if ($s -is [System.Management.Automation.Language.IfStatementAst] -and $s.Clauses[0].Item1.Extent.Text -match '\$__filaLotes\.Count -eq 0 -and -not \$__escaladaMontada') { $monta = $s; break }
    }
    if ($null -ne $monta) { $r.monta_primeiro = [object]::ReferenceEquals($stm[0], $monta) }
    # `continue` do PROPRIO laco (fora de laco aninhado) antes da montagem = caminho que pula por cima dela.
    $conts = @($w.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ContinueStatementAst] }, $true))
    foreach ($c in $conts) {
        $p = $c.Parent; $aninhado = $false
        while ($null -ne $p -and -not [object]::ReferenceEquals($p, $w)) {
            if ($p -is [System.Management.Automation.Language.LoopStatementAst]) { $aninhado = $true; break }
            $p = $p.Parent
        }
        if ($aninhado) { continue }
        $dentroMonta = ($null -ne $monta -and $c.Extent.StartOffset -ge $monta.Extent.StartOffset -and $c.Extent.EndOffset -le $monta.Extent.EndOffset)
        if ($dentroMonta) { continue }
        if ($null -eq $monta -or $c.Extent.StartOffset -lt $monta.Extent.StartOffset -or $monta.Extent.StartOffset -gt $stm[0].Extent.StartOffset) { $r.continue_antes_monta++ }
    }
    $reds = @($w.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$__cabem -lt $job.Chunk.Count' }, $true))
    if ($reds.Count -gt 0) {
        $t = $reds[0].Clauses[0].Item2.Extent.Text
        # Ignora comentarios: so o codigo conta.
        $cod = (($t -split "`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $r.reduz_achado = $true
        $r.reduz_defere = ($cod -match '\$pendingDeferred\.Add')
        $r.reduz_fecha = ($cod -match '\$capAtingido = \$true')
        $r.reduz_reenfileira = ($cod -match '\$__filaLotes\.Insert\(0,') -and ($cod -match '\$jobs\.Insert\(')
    }
    return $r
}

Write-Host '== A estrutura do laco real, duas pontas =='
$tmpAntigo = ''
if (-not $MotorAntigo) {
    $tmpAntigo = Join-Path ([IO.Path]::GetTempPath()) ('lotefila1_head_' + $PID + '.ps1')
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        Push-Location $Projeto
        try { $txt = & git show 'HEAD:scripts/run_vixradar_varredura.ps1' 2>$null; if ($LASTEXITCODE -eq 0) { [IO.File]::WriteAllText($tmpAntigo, (($txt) -join "`r`n"), (New-Object Text.UTF8Encoding($true))) } } finally { Pop-Location }
    }
    $MotorAntigo = $tmpAntigo
}
$novo = Get-LoteFilaEstrutura $MotorPath
Assert-Lf ($novo.parse_ok -and $novo.achou) 'A0 motor atual parseia e o laco de lotes existe'
Assert-Lf $novo.cond_monta 'A1 o laco so termina com a escalada montada (condicao inclui -not $__escaladaMontada)'
Assert-Lf $novo.monta_primeiro 'A2 a montagem da escalada e o PRIMEIRO passo do corpo do laco'
Assert-Lf ($novo.continue_antes_monta -eq 0) 'A3 nenhum continue do laco pula a montagem'
Assert-Lf ($novo.reduz_achado -and -not $novo.reduz_defere) 'A4 lote encolhido nao defere o resto pela estimativa'
Assert-Lf ($novo.reduz_achado -and -not $novo.reduz_fecha) 'A5 lote encolhido nao fecha a faixa antes de rodar'
Assert-Lf $novo.reduz_reenfileira 'A6 o resto volta a frente da fila e entra em $jobs (alcance do aborto por auth)'
if ($MotorAntigo -and (Test-Path -LiteralPath $MotorAntigo)) {
    $velho = Get-LoteFilaEstrutura $MotorAntigo
    Assert-Lf ($velho.parse_ok -and $velho.achou) 'A7 motor antigo parseia e o laco existe (base da ponta reprovada)'
    $reprovaD1 = (-not $velho.cond_monta) -and (-not $velho.monta_primeiro)
    $reprovaD2 = $velho.reduz_defere -and $velho.reduz_fecha -and (-not $velho.reduz_reenfileira)
    Assert-Lf $reprovaD1 'A8 a guarda REPROVA o motor antigo em D1 (montagem no fim, pulada por continue)'
    Assert-Lf $reprovaD2 'A9 a guarda REPROVA o motor antigo em D2 (defere e fecha a faixa pela estimativa)'
} else {
    Assert-Lf $false 'A7 motor antigo disponivel para a ponta reprovada (git show HEAD ou -MotorAntigo)'
}
if ($tmpAntigo -and (Test-Path -LiteralPath $tmpAntigo)) { Remove-Item -LiteralPath $tmpAntigo -Force -ErrorAction SilentlyContinue }

Write-Host '== B replay da matinal de 15/10 com a admissao real (modelo da fila) =='
# Numeros do log real: cap 400000, default codex 250000 com margem 1.25 => 312500/emissor
# (`fonte=classe_BARATO:default+margem125`), 20 emissores em 5 lotes de 4, consumo real 21416.
$cap = [int64]400000
$modelo = Get-VixModeloLoteClasse -Amostras @() -DefaultEmissor 250000 -PisoEmissor 0 -Margem 1.25
$fila20 = @(1..20 | ForEach-Object { 'E' + $_ })
$real = [int64]21416
function Invoke-FilaModelo([string]$Politica) {
    $fila = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt 20; $i += 4) { $fila.Add(@($fila20[$i..($i + 3)])) }
    $acum = [int64]0; $rodou = 0; $deferidos = 0; $fechada = $false; $maxAdmitido = [int64]0; $pass = 0
    while ($fila.Count -gt 0 -and $pass -lt 200) {
        $pass++
        $chunk = @($fila[0]); $fila.RemoveAt(0)
        $cabem = if ($fechada) { 0 } else { Get-VixEmissoresQueCabemModelo -Modelo $modelo -Acum $acum -Cap $cap -Chunk $chunk.Count }
        if ($cabem -le 0) { $deferidos += $chunk.Count; $fechada = $true; continue }
        if ($cabem -lt $chunk.Count) {
            $fora = @($chunk | Select-Object -Skip $cabem); $chunk = @($chunk | Select-Object -First $cabem)
            if ($Politica -eq 'antiga') { $deferidos += $fora.Count; $fechada = $true } else { $fila.Insert(0, $fora) }
        }
        $est = Get-VixEstimativaLoteClasse -Modelo $modelo -Emissores $chunk.Count
        if (($acum + $est) -gt $maxAdmitido) { $maxAdmitido = $acum + $est }
        $acum += ($real * $chunk.Count); $rodou += $chunk.Count
    }
    return @{ rodou = $rodou; deferidos = $deferidos; acum = $acum; max_admitido = $maxAdmitido; passadas = $pass }
}
$ant = Invoke-FilaModelo 'antiga'
$nov = Invoke-FilaModelo 'nova'
Write-Host ('  antiga: rodou=' + $ant.rodou + ' deferidos=' + $ant.deferidos + ' acum=' + $ant.acum + ' | nova: rodou=' + $nov.rodou + ' deferidos=' + $nov.deferidos + ' acum=' + $nov.acum + ' max_admitido=' + $nov.max_admitido)
Assert-Lf ($ant.rodou -eq 1 -and $ant.deferidos -eq 19) 'B1 politica antiga reproduz o log real (1 roda, 19 DEFERIDOS)'
Assert-Lf ($nov.rodou -gt $ant.rodou) 'B2 politica nova roda mais emissores com o mesmo cap'
Assert-Lf ($nov.max_admitido -le $cap) 'B3 politica nova nunca admite lote com acum+estimativa acima do cap'
Assert-Lf (($nov.rodou + $nov.deferidos) -eq 20) 'B4 todo emissor tem desfecho (rodou ou DEFERIDO), nenhum some'
Assert-Lf ($nov.passadas -lt 200) 'B5 a fila termina (cada passada roda 1+ ou defere o lote)'
# Ponta boa do lado do orcamento: com consumo real IGUAL a estimativa, a nova nao roda mais que a antiga cabe.
$real = [int64]312500
$antE = Invoke-FilaModelo 'antiga'; $novE = Invoke-FilaModelo 'nova'
Assert-Lf ($novE.rodou -eq $antE.rodou -and $novE.max_admitido -le $cap) 'B6 estimativa exata: politica nova roda o mesmo que a antiga (nao inventa orcamento)'

Write-Host '== C ancora no log real de 15/10 =='
$logM = Join-Path $LogDir 'vixradar-matinal_20261015.log'
if (Test-Path -LiteralPath $logM) {
    $l = Get-Content -LiteralPath $logM -Encoding UTF8
    Assert-Lf (@($l | Where-Object { $_ -match 'ESCALADA_DECISAO\|P.o de A.+car \(GPA\)\|escalar=1' }).Count -eq 1) 'C1 GPA foi retida para escalada na matinal real'
    Assert-Lf (@($l | Where-Object { $_ -match 'ESCALADA_LOTE:' }).Count -eq 0) 'C2 a escalada nunca foi montada na matinal real (sintoma D1)'
    Assert-Lf (@($l | Where-Object { $_ -match 'sem_registro=1 .*GPA' }).Count -eq 1) 'C3 RECONCILIACAO_DIA real acusa GPA sem registro'
    Assert-Lf (@($l | Where-Object { $_ -match 'CAP pre-lote: acum=21416 ' }).Count -eq 4) 'C4 os 4 lotes seguintes cairam em CAP pre-lote com acum=21416 (sintoma D2)'
} else {
    Write-Host ('  (log ' + $logM + ' ausente, parte C nao avaliada)')
}

Write-Host ('RESULTADO: ' + $script:Ok + ' OK, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
