# test-log-fallback-ledger.ps1 - LOGFALLBACK1 (2026-10-15), prova de duas pontas.
#
# Incidente: na noturna de 15/10 (01:30), das 01:36:47 em diante outro processo segurou
# logs/routines/vixradar-noturno_20261015.log. O Write-Log esgotou as 8 tentativas e gravou em
# vixradar-noturno_20261015_fallback_22888.log, onde ficaram 103 das 104 linhas OK| e o FIM.
# Todo leitor do ledger lia so o principal: RECONCILIACAO_DIA saiu entregues=1 sem_registro=103,
# e a execucao seguinte do dia reprocessaria Movida e Totvs (ja ANALISADO) sem ver os 101 DEFERIDO.
#
# O que esta suite prova (sem rede, sem token, sem tocar producao, sem executar a rotina):
#   A. leitura antiga (so o principal) reproduz o defeito; Get-VixLogDiaLinhas une os dois
#   B. o BLOCO REAL de idempotencia do motor trava Movida/Totvs/Camil e reabre os 101 DEFERIDO
#   C. a LINHA REAL de RECONCILIACAO_DIA do motor fecha em 104
#   D. sem duplicar linha, ordem cronologica, arquivos de outro dia/dryrun/cobfallback fora
#   E. vigia (retry e Test-EntregaPorLog) ve o FIM e o ledger do fallback; so-fallback conta
#   F. sem fallback o resultado e identico ao Get-Content do principal (nao muda o caso normal)
#   G. guardas estaticas: nenhum leitor do log do dia sobrou com Get-Content direto
#   R. replay dos dois logs REAIS de 15/10, quando presentes (evidencia, nao fixture)
# ASCII puro, PowerShell 5.1 e 7.
$ErrorActionPreference = 'Continue'
$Root = Split-Path $PSScriptRoot -Parent
$LibDir = Join-Path $PSScriptRoot 'lib'
. (Join-Path $LibDir 'vixradar-watchdog.ps1')

$script:okN = 0; $script:fal = 0
function Assert-Lfb([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }
$rxOk = '^[\d-]+ [\d:]+ OK\|'

# Leitura ANTIGA (HEAD 611158c): so o arquivo principal.
function Get-LinhasLeituraAntiga([string]$LogFile) {
    if (-not (Test-Path -LiteralPath $LogFile)) { return @() }
    return @(Get-Content -LiteralPath $LogFile -Encoding UTF8 -ErrorAction SilentlyContinue)
}

# ---------- fixture no formato do caso real ----------
$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('lfb_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($true)
$principal = Join-Path $tmpDir 'vixradar-noturno_20261015.log'
$fallback = Join-Path $tmpDir 'vixradar-noturno_20261015_fallback_22888.log'

$universo = New-Object System.Collections.Generic.List[string]
$universo.Add('Camil Alimentos'); $universo.Add('Movida'); $universo.Add('Totvs')
for ($i = 1; $i -le 101; $i++) { $universo.Add('Emissor' + $i) }

$linPri = New-Object System.Collections.Generic.List[string]
$linPri.Add('2026-10-15 01:30:29 COLETOR_PS: ativo=True')
$linPri.Add('2026-10-15 01:31:08 Plano {"SKIP":1,"LIGHT":5,"FULL":93,"AUDIT":5} total=104')
$linPri.Add('2026-10-15 01:31:10 OK|Camil Alimentos|SKIP|-|0|true|SKIP|0')
$linPri.Add('2026-10-15 01:36:47 TRIAGEM_SOMBRA|SLC Agricola|MATERIAL|x|segue_para_ia=1')
# o handle soltou por um instante: uma linha voltou ao principal no meio do fallback
$linPri.Add('2026-10-15 02:10:00 LINHA_NO_PRINCIPAL_NO_MEIO')

$linFb = New-Object System.Collections.Generic.List[string]
$linFb.Add('2026-10-15 01:36:55 COBDIARIA|Boa Safra Sementes|triagem|SEM_NOVIDADE')
$linFb.Add('2026-10-15 02:04:51 OK|Movida|FULL|INCONCLUSIVO|14|true|ANALISADO|0')
$linFb.Add('2026-10-15 02:06:08 OK|Totvs|FULL|ECO|1|true|ANALISADO|1')
# linha que ja esta no principal (duplicada entre arquivos): nao pode contar duas vezes
$linFb.Add('2026-10-15 01:31:10 OK|Camil Alimentos|SKIP|-|0|true|SKIP|0')
for ($i = 1; $i -le 101; $i++) { $linFb.Add(('2026-10-15 02:2{0}:{1:00} OK|Emissor{2}|FULL|-|0|true|DEFERIDO|0' -f [int][Math]::Floor($i / 60), ($i % 60), $i)) }
# FIM real de 15/10 (recortado): o Total do dia 1/104 ja era sintoma do mesmo defeito
$linFb.Add('2026-10-15 02:27:00 FIM: noturno concluido PARCIAL (pendentes_obrigatorios=1). Total do dia 1/104 (ledger analisados=0 skip=1 deferidos=0). analisados_execucao=2 skip_execucao=1 deferidos_execucao=101 submits_aceitos=104 submit_ok=2 submit_fail=0 resultado=PARCIAL pendentes_obrigatorios=1')
$linFb.Add('   at stack trace sem carimbo')
[IO.File]::WriteAllLines($principal, $linPri.ToArray(), $utf8)
[IO.File]::WriteAllLines($fallback, $linFb.ToArray(), $utf8)
# iscas que NAO podem entrar no dia da noturna
[IO.File]::WriteAllLines((Join-Path $tmpDir 'vixradar-noturno_20261015_dryrun.log'), @('2026-10-15 03:00:00 OK|Isca0|FULL|ECO|1|true|ANALISADO|0'), $utf8)
[IO.File]::WriteAllLines((Join-Path $tmpDir 'vixradar-noturno_20261015_dryrun_fallback_7.log'), @('2026-10-15 03:00:01 OK|Isca1|FULL|ECO|1|true|ANALISADO|0'), $utf8)
[IO.File]::WriteAllLines((Join-Path $tmpDir 'vixradar-noturno_20261014_fallback_5.log'), @('2026-10-14 23:00:00 OK|Isca2|FULL|ECO|1|true|ANALISADO|0'), $utf8)
[IO.File]::WriteAllLines((Join-Path $tmpDir 'vixradar-cobfallback_20261015_fallback_9.log'), @('2026-10-15 04:00:00 OK|Isca3|FULL|ECO|1|true|ANALISADO|0'), $utf8)
[IO.File]::WriteAllLines((Join-Path $tmpDir 'vixradar-noturno_20261015_fallback_abc.log'), @('2026-10-15 04:00:01 OK|Isca4|FULL|ECO|1|true|ANALISADO|0'), $utf8)

try {
Write-Host '=== 0: pre-condicao, a regra unica existe na lib ==='
foreach ($fnReq in @('Get-VixLogDiaArquivos', 'Get-VixLogDiaLinhas', 'Get-VixLogDiaConteudo')) { Assert-Lfb ($null -ne (Get-Command $fnReq -ErrorAction SilentlyContinue)) ('00 ' + $fnReq + ' definida em lib\vixradar-watchdog.ps1') }
Write-Host '=== A: leitura antiga reproduz o defeito, Get-VixLogDiaLinhas une os dois ==='
$antigas = @(Get-LinhasLeituraAntiga $principal | Where-Object { $_ -match $rxOk })
$recAnt = Get-VixReconciliacaoUniverso -Universo $universo.ToArray() -Linhas $antigas
Assert-Lfb (($recAnt.Entregues -eq 1) -and ($recAnt.SemRegistro -eq 103) -and -not $recAnt.Fecha) ('A1 DEFEITO reproduzido: leitura antiga da entregues=' + $recAnt.Entregues + ' sem_registro=' + $recAnt.SemRegistro + ' fecha=' + [int]$recAnt.Fecha)
$idAnt = Get-VixIdempotenciaEntregas -Linhas $antigas
Assert-Lfb ((-not (@($idAnt.Entregues) -contains 'Movida')) -and (-not (@($idAnt.Entregues) -contains 'Totvs')) -and (@($idAnt.ReabertosDeferido).Count -eq 0)) ('A2 DEFEITO reproduzido: leitura antiga nao trava Movida/Totvs (reanalise) e ve ' + @($idAnt.ReabertosDeferido).Count + ' DEFERIDO')
$novas = @(Get-VixLogDiaLinhas $principal | Where-Object { $_ -match $rxOk })
Assert-Lfb ($novas.Count -eq 104) ('A3 uniao tem 104 linhas OK| (1 principal + 103 fallback, a duplicada uma vez so), medido ' + $novas.Count)
$recNov = Get-VixReconciliacaoUniverso -Universo $universo.ToArray() -Linhas $novas
Assert-Lfb (($recNov.Universo -eq 104) -and ($recNov.Soma -eq 104) -and ($recNov.SemRegistro -eq 0) -and $recNov.Fecha) ('A4 reconciliacao fecha em 104: entregues=' + $recNov.Entregues + ' deferidos=' + $recNov.Deferidos + ' sem_registro=' + $recNov.SemRegistro + ' soma=' + $recNov.Soma)
Assert-Lfb (($recNov.Entregues -eq 3) -and ($recNov.Deferidos -eq 101)) 'A5 classes certas: 3 entregues (Camil SKIP, Movida, Totvs) e 101 deferidos'
$idNov = Get-VixIdempotenciaEntregas -Linhas $novas
Assert-Lfb ((@($idNov.Entregues) -contains 'Movida') -and (@($idNov.Entregues) -contains 'Totvs') -and (@($idNov.Entregues) -contains 'Camil Alimentos') -and (@($idNov.Entregues).Count -eq 3)) ('A6 Movida, Totvs e Camil travados (entregues=' + @($idNov.Entregues).Count + ')')
Assert-Lfb (@($idNov.ReabertosDeferido).Count -eq 101) ('A7 os 101 DEFERIDO reabrem, medido ' + @($idNov.ReabertosDeferido).Count)

Write-Host '=== B: bloco REAL de idempotencia do motor, executado contra os dois arquivos ==='
$motorPath = Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1'
$motorTxt = [IO.File]::ReadAllText($motorPath)
$tok = $null; $perr = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($motorPath, [ref]$tok, [ref]$perr)
$fnNorm = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-NomeNormalizado' }, $true) | Select-Object -First 1
$ini = $motorTxt.IndexOf('    # Idempotencia por ledger do dia (v4.9.151)')
$fimIdx = $motorTxt.IndexOf('$script:VixElegiveisExec = @(', [Math]::Max(0, $ini))
$bloco = ''
if ($ini -ge 0 -and $fimIdx -gt $ini) { $eol = $motorTxt.IndexOf("`n", $fimIdx); $bloco = $motorTxt.Substring($ini, $eol - $ini) }
Assert-Lfb (($null -ne $fnNorm) -and $bloco.Length -gt 0) ('B1 bloco de idempotencia e Get-NomeNormalizado extraidos do motor (' + $bloco.Length + ' chars)')
Assert-Lfb ($bloco -match 'Get-VixLogDiaLinhas \$LogFile') 'B2 bloco le o ledger pela funcao unica'
$sbB = [scriptblock]::Create($fnNorm.Extent.Text + "`n" + 'function Write-Log([string]$m) { $script:__logLfb.Add($m) }' + "`n" + '$script:__logLfb = New-Object System.Collections.Generic.List[string]' + "`n" + $bloco + "`n" + 'return @{ ja = $jaProcessados; eleg = $script:VixElegiveisExec; log = $script:__logLfb.ToArray() }')
$LogFile = $principal; $Force = $false; $DryRun = $false
$plano = [pscustomobject]@{ emissores = @($universo | ForEach-Object { [pscustomobject]@{ empresa = $_; tier = 'FULL' } }) }
$rb = & $sbB
Assert-Lfb (($rb.ja.Count -eq 3) -and $rb.ja.ContainsKey((& { . ([scriptblock]::Create($fnNorm.Extent.Text)); Get-NomeNormalizado 'Movida' })) -and $rb.ja.ContainsKey((& { . ([scriptblock]::Create($fnNorm.Extent.Text)); Get-NomeNormalizado 'Totvs' }))) ('B3 motor real trava 3 (Movida e Totvs entre eles), medido ' + $rb.ja.Count)
Assert-Lfb ($rb.eleg -eq 101) ('B4 elegiveis da proxima execucao = 101 DEFERIDO, medido ' + $rb.eleg)
Assert-Lfb ((@($rb.log) -join "`n") -match 'IDEMPOTENCIA_ENTREGA: entregues_hoje=3 reabertos_deferido=101 reabertos_submit_falho=0') 'B5 motor loga entregues_hoje=3 reabertos_deferido=101'

Write-Host '=== C: linha REAL de RECONCILIACAO_DIA do motor ==='
$mRec = [regex]::Match($motorTxt, '(?m)^\s*\$__reconDia = Get-VixReconciliacaoUniverso .*$')
Assert-Lfb ($mRec.Success -and ($mRec.Value -match 'Get-VixLogDiaLinhas \$LogFile')) 'C1 linha de RECONCILIACAO_DIA localizada e lendo pela funcao unica'
$__reconDia = $null
if ($mRec.Success) { $__reconDia = & ([scriptblock]::Create($mRec.Value.Trim() + "`n" + 'return $__reconDia')) }
Assert-Lfb (($null -ne $__reconDia) -and $__reconDia.Fecha -and ($__reconDia.Soma -eq 104) -and ($__reconDia.Entregues -eq 3) -and ($__reconDia.Deferidos -eq 101)) ('C2 RECONCILIACAO_DIA do motor: universo=' + $__reconDia.Universo + ' entregues=' + $__reconDia.Entregues + ' deferidos=' + $__reconDia.Deferidos + ' sem_registro=' + $__reconDia.SemRegistro + ' fecha=' + [int]$__reconDia.Fecha)

$fnRes = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-VixResumoLedger' }, $true) | Select-Object -First 1
$resLed = $null
if ($null -ne $fnRes) { $resLed = & ([scriptblock]::Create($fnNorm.Extent.Text + "`n" + $fnRes.Extent.Text + "`n" + 'Get-VixResumoLedger $LogFile')) }
Assert-Lfb (($null -ne $resLed) -and ($resLed.total -eq 104) -and ($resLed.analisados -eq 2) -and ($resLed.skips -eq 1) -and ($resLed.deferidos -eq 101)) ('C3 Get-VixResumoLedger real do motor (o "Total do dia" do FIM, que em 15/10 saiu 1/104): total=' + $resLed.total + ' analisados=' + $resLed.analisados + ' skip=' + $resLed.skips + ' deferidos=' + $resLed.deferidos)

Write-Host '=== D: sem duplicar, ordem cronologica, iscas fora ==='
$arqs = @(Get-VixLogDiaArquivos $principal)
Assert-Lfb (($arqs.Count -eq 2) -and ($arqs[0] -eq $principal) -and ((Split-Path $arqs[1] -Leaf) -eq 'vixradar-noturno_20261015_fallback_22888.log')) ('D1 arquivos do dia = principal + fallback_22888 (dryrun, outro dia, cobfallback e pid nao numerico fora), medido ' + $arqs.Count)
$todas = @(Get-VixLogDiaLinhas $principal)
Assert-Lfb ($todas.Count -eq ($linPri.Count + $linFb.Count - 1)) ('D2 total de linhas = soma menos a duplicada (' + $todas.Count + ')')
Assert-Lfb (-not (($todas -join "`n") -match 'Isca[0-4]\|')) 'D3 nenhuma linha de isca (Isca0..4) entrou'
$ixMov = [array]::IndexOf($todas, '2026-10-15 02:04:51 OK|Movida|FULL|INCONCLUSIVO|14|true|ANALISADO|0')
$ixMeio = [array]::IndexOf($todas, '2026-10-15 02:10:00 LINHA_NO_PRINCIPAL_NO_MEIO')
$ixFim = -1; for ($k = 0; $k -lt $todas.Count; $k++) { if ($todas[$k] -match 'FIM: noturno') { $ixFim = $k } }
Assert-Lfb (($ixMov -ge 0) -and ($ixMeio -gt $ixMov) -and ($ixFim -gt $ixMeio)) ('D4 ordem cronologica entre arquivos: Movida(' + $ixMov + ') < linha do principal 02:10(' + $ixMeio + ') < FIM(' + $ixFim + ')')
Assert-Lfb (($ixFim -ge 0) -and ($todas[$ixFim + 1] -eq '   at stack trace sem carimbo')) 'D5 linha sem carimbo fica colada na anterior do mesmo arquivo'
$dupDentro = Join-Path $tmpDir 'vixradar-matinal_20261015.log'
[IO.File]::WriteAllLines($dupDentro, @('2026-10-15 10:00:00 X', '2026-10-15 10:00:00 X'), $utf8)
Assert-Lfb (@(Get-VixLogDiaLinhas $dupDentro).Count -eq 2) 'D6 linha repetida DENTRO do mesmo arquivo e preservada (so a copia entre arquivos sai)'

Write-Host '=== E: vigia do retry e Test-EntregaPorLog ==='
$conteudoNovo = Get-VixLogDiaConteudo $principal
$jNovo = Test-VixLedgerEntregueNaJanela -Conteudo $conteudoNovo -DataLog ([datetime]'2026-10-15') -JanelaHora 0 -MinimoLedger 90
$jAnt = Test-VixLedgerEntregueNaJanela -Conteudo ((Get-LinhasLeituraAntiga $principal) -join "`r`n") -DataLog ([datetime]'2026-10-15') -JanelaHora 0 -MinimoLedger 90
Assert-Lfb (($jAnt.EfetivosNaJanela -eq 1) -and ($jAnt.DeferidosNaJanela -eq 0) -and ($jAnt.UltimoResultado -eq '')) ('E1 DEFEITO reproduzido: vigia antigo ve efetivos=' + $jAnt.EfetivosNaJanela + ' deferidos=' + $jAnt.DeferidosNaJanela + ' sem FIM')
Assert-Lfb (($jNovo.EfetivosNaJanela -eq 3) -and ($jNovo.DeferidosNaJanela -eq 101) -and ($jNovo.UltimoResultado -eq 'PARCIAL') -and $jNovo.Parcial -and -not $jNovo.Entregue) ('E2 vigia novo: efetivos=' + $jNovo.EfetivosNaJanela + ' deferidos=' + $jNovo.DeferidosNaJanela + ' resultado=' + $jNovo.UltimoResultado + ' entregue=' + $jNovo.Entregue)
$stE = Test-EntregaPorLog -Alvo ([datetime]'2026-10-15') -LogDir $tmpDir -Prefixo 'vixradar-noturno' -Rotulo 'Noturna'
Assert-Lfb (($null -eq $stE.motivo) -and ($stE.submitOk -eq 1)) ('E3 Test-EntregaPorLog acha o FIM que so existe no fallback (fims=' + $stE.submitOk + ')')
$soFbDir = Join-Path $tmpDir 'sofb'; New-Item -ItemType Directory -Path $soFbDir -Force | Out-Null
Copy-Item -LiteralPath $fallback -Destination (Join-Path $soFbDir 'vixradar-noturno_20261015_fallback_22888.log')
$soFbMain = Join-Path $soFbDir 'vixradar-noturno_20261015.log'
Assert-Lfb ((@(Get-VixLogDiaArquivos $soFbMain).Count -eq 1) -and ((Get-VixLogDiaConteudo $soFbMain).Length -gt 0)) 'E4 principal ausente e fallback presente: o dia NAO e "sem log" (retry e monitor)'
Assert-Lfb ((@(Get-VixLogDiaArquivos (Join-Path $soFbDir 'vixradar-matinal_20261015.log')).Count -eq 0) -and ((Get-VixLogDiaConteudo (Join-Path $soFbDir 'vixradar-matinal_20261015.log')) -eq '')) 'E5 OUTRA PONTA: sem principal e sem fallback continua "sem log"'

Write-Host '=== F: sem fallback, identico ao comportamento anterior ==='
$soPri = Join-Path $tmpDir 'sopri'; New-Item -ItemType Directory -Path $soPri -Force | Out-Null
$soPriLog = Join-Path $soPri 'vixradar-noturno_20261015.log'
Copy-Item -LiteralPath $principal -Destination $soPriLog
$a1 = @(Get-VixLogDiaLinhas $soPriLog); $a2 = @(Get-Content -LiteralPath $soPriLog -Encoding UTF8)
Assert-Lfb (($a1.Count -eq $a2.Count) -and (($a1 -join "`n") -ceq ($a2 -join "`n"))) ('F1 sem fallback: mesmas ' + $a1.Count + ' linhas, mesma ordem, do Get-Content do principal')

Write-Host '=== G: guardas estaticas (nenhum leitor do log do dia com Get-Content direto) ==='
$alvos = @(
    @{ f = 'run_vixradar_varredura.ps1'; rx = 'Get-Content[^\r\n|]*\$(LogFile|Path)\b' },
    @{ f = 'retry-vixradar.ps1'; rx = 'Get-Content[^\r\n|]*\$RotLog\b' },
    @{ f = 'monitor-tasks.ps1'; rx = 'Get-Content[^\r\n|]*\$logRot\b' },
    @{ f = 'lib\vixradar-watchdog.ps1'; rx = 'Get-Content[^\r\n|]*\$logPath\b' }
)
foreach ($al in $alvos) {
    $txtAl = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $al.f))
    $hits = [regex]::Matches($txtAl, $al.rx)
    Assert-Lfb ($hits.Count -eq 0) ('G ' + $al.f + ': leituras diretas do log do dia = ' + $hits.Count)
}
$txtProf = [IO.File]::ReadAllText((Join-Path $LibDir 'vixradar-profundidade.ps1'))
Assert-Lfb ($txtProf -match 'Get-VixLogDiaLinhas \$p') 'G lib\vixradar-profundidade.ps1: credito semanal FULL le pela funcao unica'
$txtMot = [IO.File]::ReadAllText($motorPath)
Assert-Lfb ($txtMot -match "'Get-VixLogDiaLinhas'\)\) \{") 'G motor falha fechado se a lib nao tiver Get-VixLogDiaLinhas'

Write-Host '=== R: replay dos logs REAIS de 15/10 ==='
$realDir = Join-Path $Root 'logs\routines'
$realPri = Join-Path $realDir 'vixradar-noturno_20261015.log'
$realUniv = Join-Path $realDir 'cobertura_diaria_20261015.json'
if ((Test-Path -LiteralPath $realPri) -and (Test-Path -LiteralPath (Join-Path $realDir 'vixradar-noturno_20261015_fallback_22888.log')) -and (Test-Path -LiteralPath $realUniv)) {
    $univReal = @((Get-Content -LiteralPath $realUniv -Raw -Encoding UTF8 | ConvertFrom-Json).universo | ForEach-Object { '' + $_ })
    $okAntR = @(Get-LinhasLeituraAntiga $realPri | Where-Object { $_ -match $rxOk })
    $okNovR = @(Get-VixLogDiaLinhas $realPri | Where-Object { $_ -match $rxOk })
    $rA = Get-VixReconciliacaoUniverso -Universo $univReal -Linhas $okAntR
    $rN = Get-VixReconciliacaoUniverso -Universo $univReal -Linhas $okNovR
    Write-Host ('  real antigo: universo=' + $rA.Universo + ' entregues=' + $rA.Entregues + ' deferidos=' + $rA.Deferidos + ' sem_registro=' + $rA.SemRegistro + ' fecha=' + [int]$rA.Fecha)
    Write-Host ('  real novo:   universo=' + $rN.Universo + ' entregues=' + $rN.Entregues + ' deferidos=' + $rN.Deferidos + ' submit_falho=' + $rN.SubmitFalho + ' sem_registro=' + $rN.SemRegistro + ' soma=' + $rN.Soma + ' fecha=' + [int]$rN.Fecha + ' fora_do_universo=' + $rN.ForaDoUniverso)
    Assert-Lfb (($rA.Entregues -eq 1) -and ($rA.SemRegistro -eq 103) -and -not $rA.Fecha) 'R1 DEFEITO real reproduzido: leitura antiga entregues=1 sem_registro=103'
    Assert-Lfb (($rN.Universo -eq 104) -and ($rN.Soma -eq 104) -and ($rN.SemRegistro -eq 0) -and $rN.Fecha) 'R2 RECONCILIACAO_DIA real com os dois arquivos fecha em 104'
    $iR = Get-VixIdempotenciaEntregas -Linhas $okNovR
    Assert-Lfb ((@($iR.Entregues) -contains 'Movida') -and (@($iR.Entregues) -contains 'Totvs')) ('R3 Movida e Totvs travados no dia real (entregues=' + @($iR.Entregues).Count + ')')
    Assert-Lfb (@($iR.ReabertosDeferido).Count -eq 101) ('R4 os 101 DEFERIDO reais reabrem, medido ' + @($iR.ReabertosDeferido).Count)
} else {
    Write-Host '  (logs reais de 15/10 ausentes, replay pulado)'
}
} catch {
    $script:fal++; Write-Host ('  FALHA excecao interrompeu a suite: ' + $_.Exception.Message)
} finally {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + ' OK, ' + $script:fal + ' FALHA')
if ($script:fal -gt 0) { exit 1 }
exit 0
