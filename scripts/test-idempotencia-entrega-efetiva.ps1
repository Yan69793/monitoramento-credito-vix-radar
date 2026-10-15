# test-idempotencia-entrega-efetiva.ps1 - IDEMEFETIVA1 (2026-10-15), prova de duas pontas.
#
# Incidente: noturna oficial de 14/10 18:05 e retries de 21:30 e 23:20 fecharam com
# `Fila aplicada: 0` e exit 6 com cap de 700.000 livre. A idempotencia do motor contava toda linha
# OK| do dia como trabalho feito, inclusive os 72 DEFERIDO por orcamento da execucao das 02:28.
# A regra certa ja existia no vigia e no monitor (DEFERIDO-NAO-E-ENTREGA1, 04/09), mas o motor
# tinha copia propria. A correcao poe as quatro pontas na mesma funcao da lib do vigia.
#
# O que esta suite prova (sem rede, sem token, sem tocar producao, sem executar a rotina):
#   A. regra antiga reproduz o defeito (104 travados) e a nova reabre so os 72 DEFERIDO
#   B. o BLOCO REAL de idempotencia do motor (extraido do .ps1 e executado) faz o mesmo, com a
#      flag VIXRADAR_COBERTURA_DIARIA ausente (nao depende do controle diario)
#   C. entrega efetiva nunca e reprocessada (sem duplicidade), submit recusado reabre
#   D. vigia do retry e monitor nao contam submit recusado nem DEFERIDO como entrega
#   E. reconciliacao do dia fecha os 104 em classes disjuntas; emissor sem registro reprova
#   F. reconciliacao por execucao: as 4 divergencias de 14/10 eram de escopo; divergencia real
#      (ledger sem contrato) continua reprovando
#   G. resultado: tudo entregue antes = OK; elegivel sem entrega = FALHA; cap cortando = PARCIAL
#   H. guardas estaticas: nenhuma copia local da regra sobrou no motor, no monitor e no vigia
#   R. replay do log REAL de 14/10, quando presente (evidencia, nao fixture)
# ASCII puro, PowerShell 5.1 e 7.
$ErrorActionPreference = 'Continue'
$Root = Split-Path $PSScriptRoot -Parent
$LibDir = Join-Path $PSScriptRoot 'lib'
. (Join-Path $LibDir 'vixradar-watchdog.ps1')
. (Join-Path $LibDir 'vixradar-cobertura.ps1')

$script:okN = 0; $script:fal = 0
function Assert-Ief([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

# Regra ANTIGA do motor (HEAD 14ae05f, run_vixradar_varredura.ps1, bloco de idempotencia sem a
# lib da cobertura diaria): toda linha OK| do dia trava o emissor.
function Get-ProcessadosRegraAntiga([string[]]$Linhas) {
    $j = @{}
    foreach ($linha in @($Linhas)) { if ($linha -match 'OK\|([^|]+)\|') { $j[$Matches[1]] = $true } }
    return $j
}

# Fixture no formato do ledger de 14/10 02:28: 16 ANALISADO, 16 SKIP, 72 DEFERIDO, todos aceitos.
$universo = @(); for ($i = 1; $i -le 104; $i++) { $universo += ('Emissor' + $i) }
$ledger1402 = New-Object System.Collections.Generic.List[string]
for ($i = 1; $i -le 104; $i++) {
    $st = 'DEFERIDO'; $cls = '-'
    if ($i -le 16) { $st = 'ANALISADO'; $cls = 'ECO' } elseif ($i -le 32) { $st = 'SKIP' }
    $ledger1402.Add(('2026-10-14 02:{0:00}:{1:00} OK|Emissor{2}|FULL|{3}|0|true|{4}|0' -f (30 + [int][Math]::Floor($i / 60)), ($i % 60), $i, $cls, $st))
}
$linhas1402 = $ledger1402.ToArray()

Write-Host '=== A: regra antiga reproduz o defeito, regra nova reabre DEFERIDO ==='
$antiga = Get-ProcessadosRegraAntiga $linhas1402
Assert-Ief ($antiga.Count -eq 104) ('A1 DEFEITO reproduzido: regra antiga trava 104 de 104 (medido ' + $antiga.Count + ') - Fila aplicada: 0')
$nova = Get-VixIdempotenciaEntregas -Linhas $linhas1402
Assert-Ief (@($nova.Entregues).Count -eq 32) ('A2 regra nova trava so os 32 entregues (16 ANALISADO + 16 SKIP), medido ' + @($nova.Entregues).Count)
Assert-Ief (@($nova.ReabertosDeferido).Count -eq 72) ('A3 os 72 DEFERIDO voltam a ser elegiveis, medido ' + @($nova.ReabertosDeferido).Count)
Assert-Ief (@($nova.ReabertosSubmitFalho).Count -eq 0) 'A4 nenhum submit falho neste ledger'
Assert-Ief ((@($nova.Entregues) -contains 'Emissor1') -and (@($nova.Entregues) -contains 'Emissor32') -and -not (@($nova.Entregues) -contains 'Emissor33')) 'A5 fronteira certa: Emissor32 (SKIP) trava, Emissor33 (DEFERIDO) reabre'

Write-Host '=== B: bloco REAL de idempotencia do motor, executado ==='
$motorPath = Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1'
$motorTxt = [IO.File]::ReadAllText($motorPath)
$tok = $null; $perr = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($motorPath, [ref]$tok, [ref]$perr)
$fnNorm = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-NomeNormalizado' }, $true) | Select-Object -First 1
Assert-Ief ($null -ne $fnNorm) 'B0 Get-NomeNormalizado extraida do motor'
$ini = $motorTxt.IndexOf('    # Idempotencia por ledger do dia (v4.9.151)')
$fimMarca = '$script:VixElegiveisExec = @('
$fimIdx = $motorTxt.IndexOf($fimMarca, [Math]::Max(0, $ini))
$bloco = ''
if ($ini -ge 0 -and $fimIdx -gt $ini) { $eol = $motorTxt.IndexOf("`n", $fimIdx); $bloco = $motorTxt.Substring($ini, $eol - $ini) }
Assert-Ief ($bloco.Length -gt 0) ('B1 bloco de idempotencia localizado no motor (' + $bloco.Length + ' chars)')
Assert-Ief (-not ($bloco -match 'VixCobDiaria')) 'B2 bloco nao depende da flag/lib da cobertura diaria (correcao incondicional)'
Assert-Ief (-not ($bloco -match "-match 'OK\\\|\(\[\^\|\]\+\)\\\|'\) \{ \`$jaProcessados")) 'B3 bloco nao tem mais a copia local "toda linha OK| trava"'
function Invoke-BlocoIdempotencia([string[]]$Linhas, [object[]]$Emissores) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('ief_' + [guid]::NewGuid().ToString('N') + '.log')
    [IO.File]::WriteAllLines($tmp, $Linhas, (New-Object System.Text.UTF8Encoding($false)))
    $sb = [scriptblock]::Create($fnNorm.Extent.Text + "`n" + 'function Write-Log([string]$m) { $script:__logIef.Add($m) }' + "`n" + '$script:__logIef = New-Object System.Collections.Generic.List[string]' + "`n" + $bloco + "`n" + 'return @{ ja = $jaProcessados; eleg = $script:VixElegiveisExec; reab = $script:VixIdemReabertos; log = $script:__logIef.ToArray() }')
    $prevFlag = [Environment]::GetEnvironmentVariable('VIXRADAR_COBERTURA_DIARIA', 'Process')
    [Environment]::SetEnvironmentVariable('VIXRADAR_COBERTURA_DIARIA', $null, 'Process')
    try {
        $LogFile = $tmp; $Force = $false; $DryRun = $false; $plano = [pscustomobject]@{ emissores = $Emissores }
        $r = & $sb
    } finally { [Environment]::SetEnvironmentVariable('VIXRADAR_COBERTURA_DIARIA', $prevFlag, 'Process'); Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    return $r
}
$planoObj = @($universo | ForEach-Object { [pscustomobject]@{ empresa = $_; tier = 'FULL' } })
$rb = Invoke-BlocoIdempotencia $linhas1402 $planoObj
Assert-Ief ($rb.ja.Count -eq 32) ('B4 motor real trava 32, nao 104 (medido ' + $rb.ja.Count + ')')
Assert-Ief ($rb.eleg -eq 72) ('B5 elegiveis da execucao = 72 (medido ' + $rb.eleg + ') - a fila deixa de ser 0')
Assert-Ief ($rb.reab -eq 72) ('B6 reabertos_idempotencia = 72 (medido ' + $rb.reab + ')')
Assert-Ief ((@($rb.log) -join "`n") -match 'IDEMPOTENCIA_ENTREGA: entregues_hoje=32 reabertos_deferido=72 reabertos_submit_falho=0') 'B7 motor loga a decisao com os tres numeros'
$todos = @(); for ($i = 1; $i -le 104; $i++) { $todos += ('2026-10-14 18:{0:00}:{1:00} OK|Emissor{2}|FULL|ECO|1|true|ANALISADO|0' -f (6 + [int][Math]::Floor($i / 60)), ($i % 60), $i) }
$rb2 = Invoke-BlocoIdempotencia $todos $planoObj
Assert-Ief (($rb2.ja.Count -eq 104) -and ($rb2.eleg -eq 0)) ('B8 OUTRA PONTA: dia todo entregue trava 104 e elegiveis=0 (medido ' + $rb2.ja.Count + '/' + $rb2.eleg + ') - nenhuma reanalise')

Write-Host '=== C: sem duplicidade, submit recusado reabre ==='
# Montada antes: dentro de @(a, b + c) a virgula liga antes do +.
$linhaRaizenAcento = '2026-10-14 02:36:00 OK|Ra' + [char]0x00ED + 'zen|FULL|ECO|1|true|ANALISADO|0'
$c = Get-VixIdempotenciaEntregas -Linhas @(
    '2026-10-14 02:30:00 OK|Alfa|FULL|ECO|1|true|ANALISADO|0',
    '2026-10-14 18:10:00 OK|Alfa|FULL|-|0|true|DEFERIDO|0',
    '2026-10-14 02:31:00 OK|Beta|FULL|ECO|1|false|ANALISADO|0',
    '2026-10-14 02:32:00 OK|Gama|SKIP|-|0|false|SKIP|0',
    '2026-10-14 02:33:00 OK|Delta|FULL|-|0|false|DEFERIDO|0',
    '2026-10-14 02:34:00 OK|Epsilon|FULL|ECO|1',
    '2026-10-14 02:35:00 DRYRUN|Zeta|FULL|ECO|1|true|ANALISADO|0',
    $linhaRaizenAcento,
    '2026-10-14 18:20:00 OK|Raizen|FULL|-|0|true|DEFERIDO|0')
Assert-Ief ((@($c.Entregues) -contains 'Alfa') -and -not (@($c.ReabertosDeferido) -contains 'Alfa')) 'C1 ANALISADO aceito seguido de DEFERIDO continua entregue (nunca reanalisa)'
Assert-Ief ((@($c.ReabertosSubmitFalho) -contains 'Beta') -and (@($c.ReabertosSubmitFalho) -contains 'Gama')) 'C2 ANALISADO e SKIP com submit recusado reabrem (o Worker nao recebeu)'
Assert-Ief ((@($c.ReabertosDeferido) -contains 'Delta') -and -not (@($c.Entregues) -contains 'Delta')) 'C3 DEFERIDO com submit recusado reabre'
Assert-Ief (@($c.Entregues) -contains 'Epsilon') 'C4 linha legada sem status conta como entregue (historico nao reprocessa)'
Assert-Ief (-not (@($c.Entregues) -contains 'Zeta') -and -not (@($c.ReabertosDeferido) -contains 'Zeta')) 'C5 DRYRUN| nunca e ledger real'
Assert-Ief ((@($c.Entregues).Count -eq 3) -and -not (@($c.ReabertosDeferido) -match '^Raizen$')) ('C6 acento nao duplica: Raizen com e sem acento e o mesmo emissor entregue (entregues=' + @($c.Entregues).Count + ')')

Write-Host '=== D: vigia do retry e monitor ==='
$ana104Falso = @(); for ($i = 1; $i -le 104; $i++) { $ana104Falso += ('2026-10-14 18:{0:00}:{1:00} OK|Emissor{2}|FULL|ECO|0|false|ANALISADO|0' -f (6 + [int][Math]::Floor($i / 60)), ($i % 60), $i) }
$dataLog = Get-Date -Year 2026 -Month 10 -Day 14 -Hour 0 -Minute 0 -Second 0
$jD1 = Test-VixLedgerEntregueNaJanela -Conteudo ($ana104Falso -join "`n") -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
Assert-Ief ((-not $jD1.Entregue) -and $jD1.EfetivosNaJanela -eq 0 -and $jD1.SubmitFalhoNaJanela -eq 104) ('D1 104 ANALISADO recusados pelo Worker NAO confirmam entrega (efetivos=' + $jD1.EfetivosNaJanela + ' submit_falho=' + $jD1.SubmitFalhoNaJanela + ')')
$jD2 = Test-VixLedgerEntregueNaJanela -Conteudo ($todos -join "`n") -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
Assert-Ief ($jD2.Entregue -and $jD2.EfetivosNaJanela -eq 104) 'D2 OUTRA PONTA: 104 ANALISADO aceitos confirmam entrega'
$def104 = @(); for ($i = 1; $i -le 104; $i++) { $def104 += ('2026-10-14 18:{0:00}:{1:00} OK|Emissor{2}|FULL|-|0|true|DEFERIDO|0' -f (6 + [int][Math]::Floor($i / 60)), ($i % 60), $i) }
$jD3 = Test-VixLedgerEntregueNaJanela -Conteudo ($def104 -join "`n") -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
Assert-Ief ((-not $jD3.Entregue) -and $jD3.DeferidosNaJanela -eq 104) 'D3 104 DEFERIDO nao confirmam entrega'
$fimFalha = '2026-10-14 18:05:47 FIM: noturno concluido FALHA (sem_analise_efetiva). Total do dia 104/104 (ledger analisados=16 skip=16 deferidos=72). analisados_execucao=0 skip_execucao=0 deferidos_execucao=0 submits_aceitos=0 submit_ok=0 resultado=FALHA pendentes_obrigatorios=0'
$jD4 = Test-VixLedgerEntregueNaJanela -Conteudo $fimFalha -DataLog $dataLog -JanelaHora 18 -MinimoLedger 90
Assert-Ief (-not $jD4.Entregue) 'D4 FIM FALHA de 14/10 com "Total do dia 104/104" herdado nao vira entrega (sem sucesso falso no retry)'
$janD = Get-VixLedgerEmissoresNaJanela -Conteudo (@($ana104Falso[0], $todos[1], $def104[2]) -join "`n") -JanelaInicio $dataLog.AddHours(18)
Assert-Ief (($janD.NaJanela -eq 1) -and ($janD.DeferidosNaJanela -eq 1)) ('D5 ledger por janela: so o aceito conta como processado (na_janela=' + $janD.NaJanela + ')')
$monPath = Join-Path $PSScriptRoot 'monitor-tasks.ps1'
$tokM = $null; $errM = $null
$astM = [System.Management.Automation.Language.Parser]::ParseFile($monPath, [ref]$tokM, [ref]$errM)
$fnUni = $astM.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-VixEmissoresUnicos' }, $true) | Select-Object -First 1
. ([scriptblock]::Create($fnUni.Extent.Text))
Assert-Ief ((Get-VixEmissoresUnicos ($ana104Falso -join "`n")) -eq 0) 'D6 monitor (funcao real extraida): 104 submit recusado = 0 entregues'
Assert-Ief ((Get-VixEmissoresUnicos ($todos -join "`n")) -eq 104) 'D7 OUTRA PONTA: monitor conta 104 aceitos'

Write-Host '=== E: reconciliacao do dia contra o universo ==='
$e1 = Get-VixReconciliacaoUniverso -Universo $universo -Linhas $linhas1402
Assert-Ief (($e1.Universo -eq 104) -and ($e1.Entregues -eq 32) -and ($e1.Deferidos -eq 72) -and ($e1.SubmitFalho -eq 0) -and ($e1.SemRegistro -eq 0) -and ($e1.Soma -eq 104)) ('E1 14/10 apos 02:28: 32 entregues + 72 deferidos + 0 + 0 = 104 (soma ' + $e1.Soma + ')')
Assert-Ief ($e1.Fecha -and -not $e1.Completo) 'E2 fecha (todo emissor classificado) mas NAO completo: 72 nao entregues nao viram conclusao'
$e3 = Get-VixReconciliacaoUniverso -Universo $universo -Linhas @($linhas1402 | Select-Object -First 103)
Assert-Ief ((-not $e3.Fecha) -and $e3.SemRegistro -eq 1 -and (@($e3.SemRegistroNomes) -contains 'Emissor104')) 'E3 OUTRA PONTA: emissor sem linha nenhuma reprova e e nomeado'
$e4 = Get-VixReconciliacaoUniverso -Universo $universo -Linhas @($linhas1402 + @('2026-10-14 19:00:00 OK|Emissor40|FULL|ECO|1|true|ANALISADO|0', '2026-10-14 19:01:00 OK|Emissor41|FULL|ECO|1|false|ANALISADO|0', '2026-10-14 19:02:00 OK|Fora|FULL|ECO|1|true|ANALISADO|0'))
Assert-Ief (($e4.Entregues -eq 33) -and ($e4.SubmitFalho -eq 1) -and ($e4.Deferidos -eq 70) -and ($e4.Soma -eq 104) -and ($e4.ForaDoUniverso -eq 1)) ('E4 reprocesso: 33 entregues, 1 submit falho, 70 deferidos, soma 104, fora do universo 1 (medido ' + $e4.Entregues + '/' + $e4.SubmitFalho + '/' + $e4.Deferidos + ')')
$e5 = Get-VixReconciliacaoUniverso -Universo $universo -Linhas $todos
Assert-Ief ($e5.Fecha -and $e5.Completo) 'E5 OUTRA PONTA: 104 entregues = completo'

Write-Host '=== F: reconciliacao por execucao ==='
$fOld = Test-VixCoberturaReconciliacao -LedgerAnalisados 16 -LedgerSkips 16 -LedgerDeferidos 72 -ContratoAnalisado 0 -ContratoInconclusivo 0 -ContratoResolvido 0 -ContratoReutilizado 1 -ContratoDeferido 21 -Triados 22 -PlanoTotal 104 -ExigirTriagem $true
Assert-Ief (@($fOld.divergencias).Count -eq 4) ('F1 DEFEITO reproduzido: escopo dia x dia de 14/10 da 4 divergencias: ' + (@($fOld.divergencias) -join ' | '))
$fIdle = Test-VixReconciliacaoExecucao -LedgerExec @{} -ContratoExec @{} -TriadoPorChave @{} -Elegiveis @() -ExigirTriagem $true
Assert-Ief $fIdle.ok 'F2 execucao sem trabalho (tudo ja entregue) reconcilia: nada escrito, nada a cobrar'
$le = @{}; $ce = @{}; $tr = @{}; $el = @()
for ($i = 33; $i -le 104; $i++) { $k = 'Emissor' + $i; $el += $k; $tr[$k] = $true; if ($i -le 37) { $le[$k] = 'ANALISADO'; $ce[$k] = 'ANALISADO' } else { $le[$k] = 'DEFERIDO'; $ce[$k] = 'DEFERIDO' } }
$f3 = Test-VixReconciliacaoExecucao -LedgerExec $le -ContratoExec $ce -TriadoPorChave $tr -Elegiveis $el -ExigirTriagem $true
Assert-Ief ($f3.ok -and $f3.analisados -eq 5 -and $f3.deferidos -eq 67 -and $f3.triados -eq 72) ('F3 reprocesso com cap: 5 analisados + 67 deferidos, todos com contrato, triados 72/72 (ok=' + $f3.ok + ')')
$ce2 = $ce.Clone(); $ce2.Remove('Emissor33'); $ce2['Emissor34'] = 'TRIADO'
$f4 = Test-VixReconciliacaoExecucao -LedgerExec $le -ContratoExec $ce2 -TriadoPorChave $tr -Elegiveis $el -ExigirTriagem $true
Assert-Ief ((-not $f4.ok) -and ((@($f4.divergencias) -join ' ') -match 'ledger_sem_contrato=1\[Emissor33') -and ((@($f4.divergencias) -join ' ') -match 'estado_divergente=1\[Emissor34:ANALISADO>TRIADO')) ('F4 OUTRA PONTA: analise sem contrato e estado errado reprovam por nome: ' + (@($f4.divergencias) -join ' | '))
$tr2 = $tr.Clone(); $tr2['Emissor90'] = $false
$f5 = Test-VixReconciliacaoExecucao -LedgerExec $le -ContratoExec $ce -TriadoPorChave $tr2 -Elegiveis $el -ExigirTriagem $true
Assert-Ief ((-not $f5.ok) -and ((@($f5.divergencias) -join ' ') -match 'triados:71<72')) 'F5 elegivel nao triado reprova'

Write-Host '=== G: resultado sem conclusao falsa ==='
$g1 = Get-VixResultadoRotina -DryRun $false -TrabalhoZero $false -PlanoTotal 0 -Analisados 0 -Skips 0 -PendentesObrigatorios 0 -Erros 0
Assert-Ief ($g1.Resultado -eq 'OK') 'G1 elegiveis=0 (tudo entregue antes) = OK, nao FALHA sem_analise_efetiva'
$g2 = Get-VixResultadoRotina -DryRun $false -TrabalhoZero $false -PlanoTotal 72 -Analisados 0 -Skips 0 -PendentesObrigatorios 72 -Erros 0
Assert-Ief (($g2.Resultado -eq 'FALHA') -and $g2.Exit -eq 6) 'G2 72 elegiveis e nada entregue (cap esgotado) = FALHA exit 6, nunca OK'
$g3 = Get-VixResultadoRotina -DryRun $false -TrabalhoZero $false -PlanoTotal 72 -Analisados 5 -Skips 0 -PendentesObrigatorios 67 -Erros 0
Assert-Ief (($g3.Resultado -eq 'PARCIAL') -and $g3.Exit -eq 10) 'G3 cap respeitado cortando 67 = PARCIAL exit 10'
Assert-Ief ($motorTxt -match "PlanoTotal \`$__planoResultado" -and -not ($motorTxt -match "Get-VixResultadoRotina[^\r\n]*-PlanoTotal \`$planoTotal ")) 'G4 motor passa os elegiveis (nao o plano bruto) nas 3 chamadas de resultado'

Write-Host '=== H: guardas estaticas (regra unica) ==='
$wdTxt = [IO.File]::ReadAllText((Join-Path $LibDir 'vixradar-watchdog.ps1'))
$monTxt = [IO.File]::ReadAllText($monPath)
Assert-Ief ($fnUni.Extent.Text -match 'Get-VixLedgerLinhaEntrega') 'H1 monitor usa a regra unica'
Assert-Ief (([regex]::Matches($wdTxt, 'Get-VixLedgerLinhaEntrega ')).Count -ge 4) 'H2 vigia, ledger por janela, idempotencia e reconciliacao usam a regra unica'
Assert-Ief ($motorTxt -match "lib\\vixradar-watchdog\.ps1'\)" -and $motorTxt -match "'Get-VixIdempotenciaEntregas'") 'H3 motor carrega a lib do vigia e falha fechado sem a funcao'
Assert-Ief (-not ($monTxt -match 'camposOk\[6\]')) 'H4 monitor nao tem mais copia local do parse de status'
Assert-Ief ($motorTxt -match 'Test-VixReconciliacaoExecucao -LedgerExec' -and $motorTxt -match "'Test-VixReconciliacaoExecucao'") 'H5 motor reconcilia por execucao e exige a funcao no boot'
Assert-Ief ($motorTxt -match "entregues_dia=" -and $motorTxt -match "reconciliacao_dia=") 'H6 FIM publica entregues_dia (o "Total do dia" soma DEFERIDO)'

Write-Host '=== R: replay do log REAL de 14/10 (evidencia) ==='
$real = Join-Path $Root 'logs\routines\vixradar-noturno_20261014.log'
if (Test-Path -LiteralPath $real) {
    $todasReal = @(Get-Content -LiteralPath $real -Encoding UTF8)
    $ate1805 = @($todasReal | Where-Object { $_ -match '^2026-10-14 (0\d|1[0-7]):' -and $_ -match '^[\d-]+ [\d:]+ OK\|' })
    $antR = Get-ProcessadosRegraAntiga $ate1805
    $novR = Get-VixIdempotenciaEntregas -Linhas $ate1805
    Write-Host ('  log real: ' + $ate1805.Count + ' linhas OK| antes das 18:05; antiga trava ' + $antR.Count + '; nova trava ' + @($novR.Entregues).Count + ' e reabre ' + @($novR.ReabertosDeferido).Count + ' DEFERIDO + ' + @($novR.ReabertosSubmitFalho).Count + ' submit falho')
    Assert-Ief ($antR.Count -eq 104) 'R1 DEFEITO no log real: regra antiga trava os 104'
    Assert-Ief ((@($novR.Entregues).Count -eq 32) -and (@($novR.ReabertosDeferido).Count -eq 72)) 'R2 log real: regra nova trava 32 e reabre 72'
    $planoReal = Join-Path $Root 'logs\routines\noturno_plano_20261014.json'
    $univReal = @()
    if (Test-Path -LiteralPath $planoReal) { try { $univReal = @((Get-Content -LiteralPath $planoReal -Raw -Encoding UTF8 | ConvertFrom-Json).emissores | ForEach-Object { '' + $_.e }) } catch { $univReal = @() } }
    if ($univReal.Count -gt 0) {
        $rR = Get-VixReconciliacaoUniverso -Universo $univReal -Linhas $ate1805
        Write-Host ('  RECONCILIACAO_DIA real: universo=' + $rR.Universo + ' entregues=' + $rR.Entregues + ' deferidos=' + $rR.Deferidos + ' submit_falho=' + $rR.SubmitFalho + ' sem_registro=' + $rR.SemRegistro + ' soma=' + $rR.Soma + ' fecha=' + $rR.Fecha + ' fora=' + $rR.ForaDoUniverso)
        Assert-Ief ($rR.Soma -eq $rR.Universo) 'R3 log real: a soma das classes e o universo do plano'
    } else { Write-Host '  (plano real ausente: R3 nao avaliado)' }
} else { Write-Host '  (log real ausente nesta maquina: secao R nao avaliada, nao conta como OK)' }

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + ' OK, ' + $script:fal + ' FALHA')
if ($script:fal -gt 0) { exit 1 }
exit 0
