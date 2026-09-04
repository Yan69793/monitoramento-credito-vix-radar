# test-idempotencia-janela.ps1 - prova de duas pontas da idempotencia por JANELA da noturna
# (RECOVERY-JANELA1, 03/09/2026). Cobre Get-VixJanelaInicioRotina e
# Get-VixLedgerEmissoresNaJanela (lib/vixradar-watchdog.ps1) e confirma que a skill e o
# vigia (Test-VixLedgerEntregueNaJanela) concordam sobre a MESMA janela. Sem rede, sem
# token, sem tocar producao. ASCII puro, PS 5.1.
#
# Caso A e o incidente real de 03/09/2026: recuperacao manual das 09:07 fechou 103 OK| e a
# invocacao agendada das 18:15 pulou tudo pela regra antiga (regex por dia civil). A regra
# nova tem que devolver 103 pendentes nesse cenario e 0 pendentes na segunda invocacao da
# mesma janela (caso B), que e a duplicata que a idempotencia existe para evitar.
$ErrorActionPreference = 'Continue'
$LibDir = Join-Path $PSScriptRoot 'lib'
. (Join-Path $LibDir 'vixradar-watchdog.ps1')

$script:okN = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

$plano = @()
for ($i = 1; $i -le 103; $i++) { $plano += ('Emissor' + $i) }

function New-Ledger([string]$Dia, [string]$HoraBase, [int]$De, [int]$Ate, [string]$Status) {
    # Linhas OK| no formato do Passo 10 da skill, carimbadas a partir de HoraBase, 1 por minuto
    # dentro da mesma hora (segundos variam para nao colidir).
    $sb = New-Object System.Text.StringBuilder
    $h = [int]$HoraBase.Substring(0, 2); $m = [int]$HoraBase.Substring(3, 2)
    $k = 0
    for ($i = $De; $i -le $Ate; $i++) {
        $mm = $m + [int][math]::Floor($k / 60); $ss = $k % 60
        $ts = ('{0} {1:00}:{2:00}:{3:00}' -f $Dia, $h, $mm, $ss)
        $cls = 'ECO'; if ($Status -eq 'DEFERIDO') { $cls = '-' }
        [void]$sb.AppendLine($ts + ' OK|Emissor' + $i + '|FULL|' + $cls + '|0|true|' + $Status)
        $k++
    }
    return $sb.ToString()
}

# Regra ANTIGA da skill (Passo 4 antes de RECOVERY-JANELA1): qualquer OK| do dia conta.
function Get-VistosRegraAntiga([string]$Conteudo) {
    $v = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($l in ($Conteudo -split "`r?`n")) {
        $m = [regex]::Match($l, '^[\d-]+ [\d:]+ OK\|([^|]+)\|')
        if ($m.Success) { [void]$v.Add($m.Groups[1].Value.Trim()) }
    }
    return $v
}

function Get-Pendentes([string[]]$Plano, [string[]]$Vistos) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($v in @($Vistos)) { if ($v) { [void]$set.Add($v) } }
    $p = @()
    foreach ($e in $Plano) { if (-not $set.Contains($e)) { $p += $e } }
    return $p
}

$dia = '2026-09-03'
$dataLog = Get-Date -Year 2026 -Month 9 -Day 3 -Hour 0 -Minute 0 -Second 0

# ============================================================
Write-Host '=== 0: Get-VixJanelaInicioRotina ==='
# Comparacao por string: Get-Date com -Hour/-Minute/-Second mantem os milissegundos do
# relogio atual, entao -eq entre dois Get-Date "iguais" falha por ms (achado na 1a rodada).
$j1 = Get-VixJanelaInicioRotina -Agora (Get-Date -Year 2026 -Month 9 -Day 3 -Hour 18 -Minute 15 -Second 7) -JanelaHora 18
Assert ($j1.ToString('yyyy-MM-dd HH:mm:ss') -eq '2026-09-03 18:00:00') ('0a: 18:15 -> janela comeca 18:00 (obtido ' + $j1.ToString('yyyy-MM-dd HH:mm:ss') + ')')
$j2 = Get-VixJanelaInicioRotina -Agora (Get-Date -Year 2026 -Month 9 -Day 3 -Hour 21 -Minute 30 -Second 0) -JanelaHora 18
Assert ($j2.ToString('yyyy-MM-dd HH:mm:ss') -eq '2026-09-03 18:00:00') ('0b: 21:30 (retry) -> mesma janela 18:00 (obtido ' + $j2.ToString('yyyy-MM-dd HH:mm:ss') + ')')
$j3 = Get-VixJanelaInicioRotina -Agora (Get-Date -Year 2026 -Month 9 -Day 3 -Hour 9 -Minute 7 -Second 0) -JanelaHora 18
Assert ($j3.ToString('yyyy-MM-dd HH:mm:ss') -eq '2026-09-03 00:00:00') ('0c: 09:07 (recuperacao) -> janela = dia inteiro 00:00 (obtido ' + $j3.ToString('yyyy-MM-dd HH:mm:ss') + ')')

# ============================================================
Write-Host '=== A: caso real 03/09 - ledger fechado 09:20-09:33, invocacao 18:15 ==='
$ledA = (New-Ledger $dia '09:20' 1 58 'ANALISADO') + (New-Ledger $dia '09:31' 59 103 'DEFERIDO') +
        "$dia 09:32:29 DEFERIDOS: ok=45 falha=0 total=45 motivo=cap de sessao (628855/700000 realizados)`n" +
        "$dia 09:33:03 FIM: noturno concluido. Total do dia 103/103. analisados=58 skip=0 deferidos=45 submits_aceitos=103`n" +
        "$dia 09:34:14 RUNNER_FIM: claude exit 0 (entrega e julgada pelo ledger OK| da skill, nao por este exit code)`n"
$rA = Get-VixLedgerEmissoresNaJanela -Conteudo $ledA -JanelaInicio $j1
$pendA = Get-Pendentes $plano $rA.Emissores
Assert ($rA.LinhasOK -eq 103) ('A1: 103 linhas OK| lidas (obtido ' + $rA.LinhasOK + ')')
Assert ($rA.NaJanela -eq 0) ('A2: 0 emissores na janela 18:00 (obtido ' + $rA.NaJanela + ')')
Assert ($rA.ForaDaJanela -eq 103) ('A3: 103 emissores fora da janela (obtido ' + $rA.ForaDaJanela + ')')
Assert ($pendA.Count -eq 103) ('A4: regra NOVA -> 103 pendentes, a invocacao 18h PROCESSA (obtido ' + $pendA.Count + ')')
$antigaA = Get-VistosRegraAntiga $ledA
$pendAntigaA = Get-Pendentes $plano @($antigaA)
Assert ($pendAntigaA.Count -eq 0) ('A5: prova reversa - regra ANTIGA dava 0 pendentes e pulava tudo (obtido ' + $pendAntigaA.Count + ')')
$vigiaA = Test-VixLedgerEntregueNaJanela -Conteudo $ledA -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
Assert ($vigiaA.Entregue -eq $false) ('A6: vigia concorda - nao entregue na janela 18:00 (Entregue=' + $vigiaA.Entregue + ', ledger=' + $vigiaA.LedgerNaJanela + ')')

# ============================================================
Write-Host '=== B: dia normal - 103 OK| as 18:20-18:45, segunda invocacao (retry) 21:30 ==='
$ledB = (New-Ledger $dia '18:20' 1 103 'ANALISADO') +
        "$dia 18:46:00 FIM: noturno concluido. Total do dia 103/103. analisados=103 skip=0 deferidos=0 submits_aceitos=103`n"
$rB = Get-VixLedgerEmissoresNaJanela -Conteudo $ledB -JanelaInicio $j2
$pendB = Get-Pendentes $plano $rB.Emissores
Assert ($rB.NaJanela -eq 103) ('B1: 103 na janela (obtido ' + $rB.NaJanela + ')')
Assert ($pendB.Count -eq 0) ('B2: 0 pendentes -> segunda invocacao na MESMA janela skipa (obtido ' + $pendB.Count + ')')
$vigiaB = Test-VixLedgerEntregueNaJanela -Conteudo $ledB -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
Assert ($vigiaB.Entregue -eq $true) ('B3: vigia concorda - entregue (Entregue=' + $vigiaB.Entregue + ')')

# ============================================================
Write-Host '=== C: sem log do dia ==='
$rC = Get-VixLedgerEmissoresNaJanela -Conteudo '' -JanelaInicio $j1
$pendC = Get-Pendentes $plano $rC.Emissores
Assert ($rC.NaJanela -eq 0 -and $rC.LinhasOK -eq 0) 'C1: conteudo vazio -> 0 linhas, 0 na janela'
Assert ($pendC.Count -eq 103) ('C2: 103 pendentes (obtido ' + $pendC.Count + ')')

# ============================================================
Write-Host '=== D: recuperacao de manha + passada da noite interrompida no 40, retry 21:30 ==='
$ledD = $ledA + (New-Ledger $dia '18:20' 1 40 'ANALISADO')
$rD = Get-VixLedgerEmissoresNaJanela -Conteudo $ledD -JanelaInicio $j2
$pendD = Get-Pendentes $plano $rD.Emissores
Assert ($rD.NaJanela -eq 40) ('D1: 40 na janela (obtido ' + $rD.NaJanela + ')')
Assert ($pendD.Count -eq 63) ('D2: 63 pendentes -> retry retoma sem refazer os 40 (obtido ' + $pendD.Count + ')')
Assert (($pendD -contains 'Emissor41') -and -not ($pendD -contains 'Emissor40')) 'D3: Emissor40 pulado, Emissor41 pendente'
$vigiaD = Test-VixLedgerEntregueNaJanela -Conteudo $ledD -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
Assert ($vigiaD.Entregue -eq $false) ('D4: vigia concorda - 40 < 90, nao entregue ainda (Entregue=' + $vigiaD.Entregue + ')')

# ============================================================
Write-Host '=== E: reexecucao manual de manha (11:00) apos recuperacao 09:07 ==='
# Este caso media DUAS coisas de uma vez e so uma mudou em 04/09.
# O que NAO mudou e o que ele existe para provar: antes das 18h a janela e o dia inteiro,
# entao as linhas das 09:2x entram na contagem em vez de ficarem "fora da janela". Os 58
# ANALISADO continuam sendo pulados, exatamente como antes.
# O que mudou, de proposito (DEFERIDO-NAO-E-ENTREGA1): os 45 que o cap adiou deixaram de
# contar como entregues, entao a reexecucao das 11:00 agora PROCESSA a cauda adiada. Antes
# ela saia em no-op com o orcamento do dia ainda disponivel. A assercao antiga era
# 'pendentes -eq 0', e trocar so o numero esconderia a mudanca: as duas propriedades ficam
# afirmadas separadamente abaixo.
$jE = Get-VixJanelaInicioRotina -Agora (Get-Date -Year 2026 -Month 9 -Day 3 -Hour 11 -Minute 0 -Second 0) -JanelaHora 18
$rE = Get-VixLedgerEmissoresNaJanela -Conteudo $ledA -JanelaInicio $jE
$pendE = Get-Pendentes $plano $rE.Emissores
Assert ($rE.ForaDaJanela -eq 0 -and $rE.NaJanela -eq 58) ('E1: janela = dia inteiro, os 58 ANALISADO das 09:2x contam e sao pulados (obtido fora=' + $rE.ForaDaJanela + ' naJanela=' + $rE.NaJanela + ')')
Assert ($pendE.Count -eq 45 -and $rE.DeferidosNaJanela -eq 45) ('E2: os 45 adiados pelo cap ficam pendentes, a reexecucao trabalha (obtido pendentes=' + $pendE.Count + ' deferidos=' + $rE.DeferidosNaJanela + ')')

# ============================================================
Write-Host '=== F: linhas que NAO sao ledger nao contam ==='
$ledF = "$dia 18:30:00 DRYRUN|Emissor1|FULL|ECO|0|false|ANALISADO`n" +
        "$dia 18:30:01 ALVO Emissor2 tier=FULL cvm_novos=0`n" +
        "OK|2026-08-28|braskem|rad.cvm|Braskem|APROVADO`n" +
        "$dia 18:30:02 OK|Emissor3|FULL|ECO|0|true|ANALISADO`n"
$rF = Get-VixLedgerEmissoresNaJanela -Conteudo $ledF -JanelaInicio $j1
Assert ($rF.LinhasOK -eq 1 -and $rF.NaJanela -eq 1 -and ($rF.Emissores -contains 'Emissor3')) ('F1: so a linha OK| com carimbo conta (obtido linhas=' + $rF.LinhasOK + ' naJanela=' + $rF.NaJanela + ')')

# ============================================================
# DEFERIDO-NAO-E-ENTREGA1 (04/09/2026). Cenario que o caso A NAO cobre: a passada da
# NOITE fecha dentro da janela com parte analisada e parte adiada pelo cap. Pela regra
# antiga as duas contavam igual, entao uma segunda invocacao na mesma janela via 103
# processados e saia em no-op sem tocar na cauda adiada.
Write-Host '=== G: passada das 18:20 com cauda adiada pelo cap, segunda invocacao na MESMA janela ==='
$ledG = (New-Ledger $dia '18:20' 1 58 'ANALISADO') + (New-Ledger $dia '18:40' 59 103 'DEFERIDO') +
        "$dia 18:41:29 DEFERIDOS: ok=45 falha=0 total=45 motivo=cap_efetivo (628855/700000 realizados)`n" +
        "$dia 18:42:03 FIM: noturno concluido. Total do dia 103/103. analisados=58 skip=0 deferidos=45 submits_aceitos=103`n"
$rG = Get-VixLedgerEmissoresNaJanela -Conteudo $ledG -JanelaInicio $j2
$pendG = Get-Pendentes $plano $rG.Emissores
Assert ($rG.LinhasOK -eq 103) ('G1: 103 linhas OK| lidas (obtido ' + $rG.LinhasOK + ')')
Assert ($rG.NaJanela -eq 58) ('G2: PONTA BOA - so os 58 ANALISADO contam como entregues (obtido ' + $rG.NaJanela + ')')
Assert ($rG.DeferidosNaJanela -eq 45) ('G3: PONTA RUIM - 45 DEFERIDO reconhecidos e separados (obtido ' + $rG.DeferidosNaJanela + ')')
Assert ($pendG.Count -eq 45) ('G4: 45 pendentes -> a segunda invocacao PROCESSA a cauda adiada (obtido ' + $pendG.Count + ')')
Assert (($pendG -contains 'Emissor59') -and -not ($pendG -contains 'Emissor58')) 'G5: Emissor58 (analisado) pulado, Emissor59 (adiado) pendente'
$antigaG = Get-VistosRegraAntiga $ledG
$pendAntigaG = Get-Pendentes $plano @($antigaG)
Assert ($pendAntigaG.Count -eq 0) ('G6: prova reversa - regra ANTIGA dava 0 pendentes e nao tocava na cauda (obtido ' + $pendAntigaG.Count + ')')

Write-Host '=== H: ponta boa do mesmo cenario - 103 ANALISADO na janela nao gera repique ==='
$ledH = (New-Ledger $dia '18:20' 1 103 'ANALISADO')
$rH = Get-VixLedgerEmissoresNaJanela -Conteudo $ledH -JanelaInicio $j2
$pendH = Get-Pendentes $plano $rH.Emissores
Assert ($rH.NaJanela -eq 103 -and $rH.DeferidosNaJanela -eq 0) ('H1: 103 entregues, 0 adiados (obtido naJanela=' + $rH.NaJanela + ' deferidos=' + $rH.DeferidosNaJanela + ')')
Assert ($pendH.Count -eq 0) ('H2: 0 pendentes -> segunda invocacao segue skipando quando tudo foi analisado (obtido ' + $pendH.Count + ')')

Write-Host '=== I: SKIP continua contando como entrega (foi avaliado e submetido de proposito) ==='
$ledI = (New-Ledger $dia '18:20' 1 103 'SKIP')
$rI = Get-VixLedgerEmissoresNaJanela -Conteudo $ledI -JanelaInicio $j2
Assert ($rI.NaJanela -eq 103 -and $rI.DeferidosNaJanela -eq 0) ('I1: 103 SKIP contam como entregues (obtido naJanela=' + $rI.NaJanela + ')')

Write-Host '=== J: ledger antigo sem campo status nao e reprocessado retroativamente ==='
$ledJ = "$dia 18:30:02 OK|Emissor1|FULL|ECO|0|true`n$dia 18:30:03 OK|Emissor2|FULL|ECO|0|true`n"
$rJ = Get-VixLedgerEmissoresNaJanela -Conteudo $ledJ -JanelaInicio $j2
Assert ($rJ.NaJanela -eq 2 -and $rJ.DeferidosNaJanela -eq 0) ('J1: linha de 6 campos conta como entrega (obtido naJanela=' + $rJ.NaJanela + ')')

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
