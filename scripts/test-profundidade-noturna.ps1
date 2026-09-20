# test-profundidade-noturna.ps1 - PROFUNDIDADE-NOTURNA1, offline e deterministico.
#
# Prova a selecao adaptativa de tier da noturna (lib\vixradar-profundidade.ps1) sem rede, sem
# Worker, sem rotina real e sem tocar em log/lock de producao. Os cinco cenarios de fechamento
# semanal rodam como laco puro sobre o proprio seletor, entao o teste prova o codigo que roda
# em producao e nao uma copia da regra.
#
# ASCII puro (PowerShell 5.1 e pwsh 7). Sai com exit 1 em qualquer FAIL.
$ErrorActionPreference = 'Continue'
$pass = 0
$fail = 0

function Assert-True([bool]$cond, [string]$nome) {
    if ($cond) { $script:pass++; Write-Host ('PASS: ' + $nome) }
    else { $script:fail++; Write-Host ('FAIL: ' + $nome) }
}

function Assert-Igual($esperado, $obtido, [string]$nome) {
    $ok = ($esperado -eq $obtido)
    if ($ok) { $script:pass++; Write-Host ('PASS: ' + $nome + ' (' + $obtido + ')') }
    else { $script:fail++; Write-Host ('FAIL: ' + $nome + ' esperado=' + $esperado + ' obtido=' + $obtido) }
}

$Lib = Join-Path $PSScriptRoot 'lib\vixradar-profundidade.ps1'
if (-not (Test-Path $Lib)) { Write-Host ('FAIL: lib nao encontrada em ' + $Lib); exit 1 }
. $Lib

# --- carta deterministico ------------------------------------------------------------------
# 104 emissores, gap crescente (12h a 12*104 h) e EWS ciclico. Todo desempate e previsivel.
function New-Carteira([int]$N = 104, [string]$Tier = 'LIGHT') {
    $out = @()
    for ($i = 1; $i -le $N; $i++) {
        $out += [pscustomobject]@{
            empresa             = 'EMISSOR ' + $i.ToString('000')
            tier                = $Tier
            ews_score           = 40 - (($i * 7) % 40)
            horas_desde_analise = [double](12 * $i)
            ultimo_tier         = $null
            ultima_origem       = $null
        }
    }
    return ,$out
}

$CustoFull  = 31068.75
$CustoLight = 6023.82
$Cap        = [int64]700000
$SEGUNDA    = [datetime]'2026-09-14'   # segunda-feira

# --- cenario 1: cinco noites fecham 104/104 --------------------------------------------------
# Laco puro: cada noite chama o seletor, grava os FULL da noite no mapa da semana, e a noite
# seguinte parte do mapa atualizado. Sem matinal, para isolar a garantia do noturno.
$car1 = New-Carteira 104
$semana1 = @{}
$hist1 = @()
for ($n = 0; $n -lt 5; $n++) {
    $dia = $SEGUNDA.AddDays($n)
    $noites = Get-VixDiasUteisRestantes $dia
    $sel = Select-VixProfundidadeNoturna -Emissores $car1 -FullSemana $semana1 -BaseCarteira 104 `
        -NoitesRestantes $noites -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
    foreach ($e in $sel.Full) { $semana1[(Get-NomeNormalizado $e.empresa)] = $dia.ToString('yyyy-MM-dd') }
    $hist1 += [pscustomobject]@{ dia = $dia.ToString('yyyy-MM-dd'); noites = $noites; full = $sel.Full.Count; light = $sel.Light.Count; estimado = $sel.Meta.estimado_trabalho }
}
Assert-Igual 104 $semana1.Count 'C1 cinco noites fecham os 104 com pelo menos um FULL'
Assert-Igual 104 ($hist1 | ForEach-Object { $_.full } | Measure-Object -Sum).Sum 'C1 soma de FULL das cinco noites e exatamente 104'
Assert-Igual '21,21,21,21,20' (($hist1 | ForEach-Object { $_.full }) -join ',') 'C1 distribuicao por noite e 21/21/21/21/20'
Assert-True (@($hist1 | Where-Object { $_.estimado -gt $Cap }).Count -eq 0) 'C1 estimativa pre-lote nunca passa do cap em nenhuma das cinco noites'

# --- cenario 2: FULL confirmado da matinal e creditado --------------------------------------
# Dez emissores vindos do ledger real da matinal. A regra nao le ultimo_tier do plano, que
# deixaria de mostrar o FULL se uma analise LIGHT posterior fosse gravada para o mesmo emissor.
$car2 = New-Carteira 104
$full2 = Merge-VixFullSemana -FullSemana @{} -EmissoresFull @($car2 | Select-Object -First 10) -Data $SEGUNDA
Assert-Igual 10 $full2.Count 'C2 creditos de FULL confirmado da matinal entram na uniao semanal'
$sel2 = Select-VixProfundidadeNoturna -Emissores $car2 -FullSemana $full2 -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
Assert-Igual 94 $sel2.Meta.faltam_na_semana 'C2 faltam cai de 104 para 94 com os dez creditados'
Assert-Igual 19 $sel2.Meta.min_full_noite 'C2 minimo da noite cai para ceil(94/5)'
Assert-True (@($sel2.Full | Where-Object { $full2.ContainsKey((Get-NomeNormalizado $_.empresa)) }).Count -eq 0) 'C2 quem ja tem FULL na semana nao e escolhido para FULL de novo'

# --- cenario 2B: credito semanal e uniao por emissor -----------------------------------------
# Reproducao offline de 14-18/09. A matinal fez 16 FULL na quinta e 4 na sexta, mas so quatro
# NOMES eram novos no conjunto semanal. Os outros 16 ja estavam no conjunto FULL_SEMANA vindo
# das noites anteriores. A producao recebe as listas reais do ledger, nunca as contagens 16/4.
$semana2B = @{}
$hist2B = @()
for ($n = 0; $n -lt 3; $n++) {
    $dia = $SEGUNDA.AddDays($n)
    $sel = Select-VixProfundidadeNoturna -Emissores (New-Carteira 104) -FullSemana $semana2B -BaseCarteira 104 `
        -NoitesRestantes (Get-VixDiasUteisRestantes $dia) -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
    foreach ($e in $sel.Full) { $semana2B[(Get-NomeNormalizado $e.empresa)] = $dia.ToString('yyyy-MM-dd') }
    $hist2B += [pscustomobject]@{ full = $sel.Full.Count; light = $sel.Light.Count; estimado = $sel.Meta.estimado_trabalho }
}
# Quinta: 13 repetidos e tres novos. Sexta: tres repetidos e um novo. Sao 20 FULL brutos e
# exatamente quatro creditos semanais novos, por identidade do emissor.
$matinalQui = @('EMISSOR 042','EMISSOR 043','EMISSOR 044','EMISSOR 045','EMISSOR 046','EMISSOR 047','EMISSOR 048','EMISSOR 049','EMISSOR 050','EMISSOR 051','EMISSOR 052','EMISSOR 053','EMISSOR 054','EMISSOR 001','EMISSOR 002','EMISSOR 003')
$semana2B = Merge-VixFullSemana -FullSemana $semana2B -EmissoresFull $matinalQui -Data ($SEGUNDA.AddDays(3))
$qui = $SEGUNDA.AddDays(3)
$selQui = Select-VixProfundidadeNoturna -Emissores (New-Carteira 104) -FullSemana $semana2B -BaseCarteira 104 `
    -NoitesRestantes (Get-VixDiasUteisRestantes $qui) -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
foreach ($e in $selQui.Full) { $semana2B[(Get-NomeNormalizado $e.empresa)] = $qui.ToString('yyyy-MM-dd') }
$hist2B += [pscustomobject]@{ full = $selQui.Full.Count; light = $selQui.Light.Count; estimado = $selQui.Meta.estimado_trabalho }
$matinalSex = @('EMISSOR 042','EMISSOR 043','EMISSOR 044','EMISSOR 004')
$sex = $SEGUNDA.AddDays(4)
$semana2B = Merge-VixFullSemana -FullSemana $semana2B -EmissoresFull $matinalSex -Data $sex
$selSex = Select-VixProfundidadeNoturna -Emissores (New-Carteira 104) -FullSemana $semana2B -BaseCarteira 104 `
    -NoitesRestantes (Get-VixDiasUteisRestantes $sex) -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
foreach ($e in $selSex.Full) { $semana2B[(Get-NomeNormalizado $e.empresa)] = $sex.ToString('yyyy-MM-dd') }
$hist2B += [pscustomobject]@{ full = $selSex.Full.Count; light = $selSex.Light.Count; estimado = $selSex.Meta.estimado_trabalho }
Assert-Igual 66 ($selQui.Meta.ja_full_semana) 'C2B quinta conta 63 noturnos mais tres nomes novos da matinal, nao 16'
Assert-Igual 19 $selQui.Meta.min_full_noite 'C2B quinta calcula ceil(38/2) a partir da uniao semanal'
Assert-Igual 18 $selSex.Meta.min_full_noite 'C2B sexta calcula ceil(18/1) depois de um unico nome novo da matinal'
Assert-Igual '21,21,21,19,18' (($hist2B | ForEach-Object { $_.full }) -join ',') 'C2B distribuicao historica usa uniao, 21/21/21/19/18'
Assert-Igual '7,7,7,18,23' (($hist2B | ForEach-Object { $_.light }) -join ',') 'C2B sobra do cap vira 7/7/7/18/23 LIGHT'
Assert-Igual 104 $semana2B.Count 'C2B FULL_SEMANA fecha 104 nomes unicos, nao soma 20 creditos brutos da matinal'
Assert-True (@($hist2B | Where-Object { $_.estimado -gt $Cap }).Count -eq 0) 'C2B cada noite permanece dentro do cap de 700000'

# --- cenario 2C: estado semanal vem apenas de ledger confirmado -------------------------------
$tmp2C = Join-Path $env:TEMP ('vix-profundidade-ledger-' + $PID)
New-Item -ItemType Directory -Force -Path $tmp2C | Out-Null
@(
    '2026-09-17 10:00:00 OK|EMISSOR 042|FULL|ECO|0|true|ANALISADO|0'
    '2026-09-17 10:01:00 OK|EMISSOR 043|FULL|ECO|0|false|ANALISADO|0'
    '2026-09-17 10:02:00 DRYRUN|EMISSOR 044|FULL|ECO|0|true|ANALISADO|0'
    '2026-09-17 10:03:00 OK|EMISSOR 045|LIGHT|ECO|0|true|ANALISADO|0'
) | Set-Content (Join-Path $tmp2C 'vixradar-matinal_20260917.log') -Encoding UTF8
@('2026-09-16 18:00:00 OK|EMISSOR 041|FULL|ECO|0|true|ANALISADO|0') | Set-Content (Join-Path $tmp2C 'vixradar-noturno_20260916.log') -Encoding UTF8
$full2C = Get-VixFullConfirmadosDoLedger $tmp2C 'matinal' ([datetime]'2026-09-17')
$semana2C = Get-VixFullSemanaDosLedgers $tmp2C ([datetime]'2026-09-17')
Assert-Igual 1 @($full2C).Count 'C2C leitor aceita so FULL com submit confirmado, nunca DRYRUN ou submit false'
Assert-Igual 2 $semana2C.Count 'C2C semana une os FULL reais de noturno e matinal por emissor'
Remove-Item -LiteralPath $tmp2C -Recurse -Force -ErrorAction SilentlyContinue

# --- cenario 3: nenhum overlap evitavel com a matinal do dia ---------------------------------
$car3 = New-Carteira 104
$cobertosHoje = @{}
# 30 emissores ja analisados hoje por outra rotina: 20 pelo matinal, 10 pelo noturno anterior
for ($i = 0; $i -lt 30; $i++) {
    $cobertosHoje[(Get-NomeNormalizado $car3[$i].empresa)] = 'matinal'
}
$sel3 = Select-VixProfundidadeNoturna -Emissores $car3 -FullSemana @{} -CobertosHoje $cobertosHoje -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
$overlap = @($sel3.Full + $sel3.Light | Where-Object { $cobertosHoje.ContainsKey((Get-NomeNormalizado $_.empresa)) })
Assert-Igual 0 $overlap.Count 'C3 quem a matinal cobriu hoje nao recebe FULL nem LIGHT no noturno'
Assert-Igual 74 $sel3.Meta.elegiveis 'C3 elegiveis caem de 104 para 74 com os 30 cobertos hoje'

# --- cenario 4: a sobra do cap vira LIGHT ----------------------------------------------------
$car4 = New-Carteira 104
$sel4 = Select-VixProfundidadeNoturna -Emissores $car4 -FullSemana @{} -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
Assert-Igual 21 $sel4.Meta.full_noite 'C4 FULL da noite e o minimo da semana, nao o que o cap paga (22)'
Assert-Igual 7 $sel4.Meta.light_noite 'C4 sobra de 47556 tokens vira 7 LIGHT'
Assert-True ($sel4.Meta.light_noite -gt 0) 'C4 a sobra e de fato usada, e nao descartada'
Assert-True ($sel4.Meta.estimado_trabalho -le $Cap) 'C4 FULL mais LIGHT cabem no cap'

# --- cenario 5: cap apertado reduz FULL e nunca estoura --------------------------------------
$car5 = New-Carteira 104
foreach ($capApertado in @(0, 31068, 62137, 310687, 700000, 5000000)) {
    $selC = Select-VixProfundidadeNoturna -Emissores $car5 -FullSemana @{} -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo ([int64]$capApertado) -CustoFull $CustoFull -CustoLight $CustoLight
    Assert-True ($selC.Meta.estimado_trabalho -le $capApertado) ('C5 estimativa nunca passa do cap de ' + $capApertado)
    Assert-True ($selC.Full.Count + $selC.Light.Count -le 104) ('C5 selecao nao duplica nem inventa emissor com cap ' + $capApertado)
}
$selZero = Select-VixProfundidadeNoturna -Emissores $car5 -FullSemana @{} -BaseCarteira 104 -NoitesRestantes 1 -CapEfetivo ([int64]0) -CustoFull $CustoFull -CustoLight $CustoLight
Assert-Igual 0 $selZero.Full.Count 'C5 cap zero nao seleciona nenhum FULL'
Assert-Igual 0 $selZero.Light.Count 'C5 cap zero nao seleciona nenhum LIGHT'

# --- cenario 6: sexta fecha o que sobrou -----------------------------------------------------
# Quatro noites de FULL deixam 20 para a ultima noite util, e a sexta pede os 20 de uma vez.
$car6 = New-Carteira 104
$semana6 = @{}
for ($n = 0; $n -lt 4; $n++) {
    $dia = $SEGUNDA.AddDays($n)
    $sel = Select-VixProfundidadeNoturna -Emissores $car6 -FullSemana $semana6 -BaseCarteira 104 -NoitesRestantes (Get-VixDiasUteisRestantes $dia) -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
    foreach ($e in $sel.Full) { $semana6[(Get-NomeNormalizado $e.empresa)] = $dia.ToString('yyyy-MM-dd') }
}
$sexta = $SEGUNDA.AddDays(4)
$sel6 = Select-VixProfundidadeNoturna -Emissores $car6 -FullSemana $semana6 -BaseCarteira 104 -NoitesRestantes (Get-VixDiasUteisRestantes $sexta) -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
Assert-Igual 1 $sel6.Meta.noites_restantes 'C6 sexta tem uma noite util restante'
Assert-Igual 20 $sel6.Meta.full_noite 'C6 a ultima noite pede os 20 que faltam'
Assert-True ($sel6.Meta.full_noite -le $sel6.Meta.cap_paga_full) 'C6 os 20 ainda cabem no cap'

# --- cenario 7: SKIP nunca entra, em tier nenhum ---------------------------------------------
$car7 = New-Carteira 104
for ($i = 0; $i -lt 26; $i++) { $car7[$i].tier = 'SKIP' }
$sel7 = Select-VixProfundidadeNoturna -Emissores $car7 -FullSemana @{} -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
Assert-Igual 78 $sel7.Meta.elegiveis 'C7 os 26 SKIP ficam de fora da elegibilidade'
$comSkip = @($sel7.Full + $sel7.Light | Where-Object { $_.tier -eq 'SKIP' })
Assert-Igual 0 $comSkip.Count 'C7 SKIP nao aparece em nenhum lote selecionado'

# --- cenario 8: tier aplicado nunca troca ----------------------------------------------------
# Monta os lotes dos dois tiers e confere rotulo, modelo, prompt e ausencia de sobreposicao.
$sel8 = Select-VixProfundidadeNoturna -Emissores (New-Carteira 104) -FullSemana @{} -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
$jobsFull = New-VixJobsPorTier -Selecionados $sel8.Full -Tier 'FULL' -Chunk 16 -Model 'claude-sonnet-4-6' -Skill 'noturno-batch-sonnet.md' -Ultra $false -Provedor 'claude-sonnet-routine'
$jobsLight = New-VixJobsPorTier -Selecionados $sel8.Light -Tier 'LIGHT' -Chunk 15 -Model 'claude-haiku-4-5-20251001' -Skill 'noturno-batch-haiku.md' -Ultra $true -Provedor 'claude-haiku-routine'
$emFull = @($jobsFull | ForEach-Object { $_.Chunk } | ForEach-Object { Get-NomeNormalizado $_.empresa })
$emLight = @($jobsLight | ForEach-Object { $_.Chunk } | ForEach-Object { Get-NomeNormalizado $_.empresa })
Assert-Igual $sel8.Full.Count $emFull.Count 'C8 todos os FULL selecionados entram em lote FULL'
Assert-Igual $sel8.Light.Count $emLight.Count 'C8 todos os LIGHT selecionados entram em lote LIGHT'
$sobrepostos = @($emFull | Where-Object { $emLight -contains $_ })
Assert-Igual 0 $sobrepostos.Count 'C8 nenhum emissor aparece em lote FULL e LIGHT ao mesmo tempo'
$rotuloErrado = @($jobsFull | Where-Object { $_.Tier -ne 'FULL' -or $_.Name -ne 'full' -or $_.Model -notlike '*sonnet*' })
Assert-Igual 0 $rotuloErrado.Count 'C8 lote FULL carrega tier, nome e modelo aprofundados'
$rotuloErrado2 = @($jobsLight | Where-Object { $_.Tier -ne 'LIGHT' -or $_.Name -ne 'light' -or $_.Model -notlike '*haiku*' })
Assert-Igual 0 $rotuloErrado2.Count 'C8 lote LIGHT carrega tier, nome e modelo rapidos'
$fatiado = @($jobsFull | Where-Object { $_.Chunk.Count -gt 16 })
Assert-Igual 0 $fatiado.Count 'C8 nenhum lote FULL passa do chunk de 16'

# --- cenario 9: semana e utilidade -----------------------------------------------------------
Assert-Igual '20260914' (Get-VixSemanaChave $SEGUNDA) 'C9 segunda 14/09 abre a semana 20260914'
Assert-Igual '20260914' (Get-VixSemanaChave ([datetime]'2026-09-19')) 'C9 sabado 19/09 pertence a mesma semana'
Assert-Igual '20260921' (Get-VixSemanaChave ([datetime]'2026-09-21')) 'C9 segunda seguinte abre semana nova'
Assert-Igual 5 (Get-VixDiasUteisRestantes $SEGUNDA) 'C9 segunda tem cinco noites uteis'
Assert-Igual 2 (Get-VixDiasUteisRestantes ([datetime]'2026-09-17')) 'C9 quinta tem duas noites uteis'
Assert-Igual 0 (Get-VixDiasUteisRestantes ([datetime]'2026-09-19')) 'C9 sabado tem zero noite util'
Assert-Igual 0 (Get-VixDiasUteisRestantes ([datetime]'2026-09-20')) 'C9 domingo tem zero noite util'

# --- cenario 10: determinismo ----------------------------------------------------------------
# A mesma entrada rodada duas vezes devolve exatamente a mesma escolha, na mesma ordem.
$selA = Select-VixProfundidadeNoturna -Emissores (New-Carteira 104) -FullSemana @{} -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
$selB = Select-VixProfundidadeNoturna -Emissores (New-Carteira 104) -FullSemana @{} -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
Assert-Igual (($selA.Full | ForEach-Object { $_.empresa }) -join '|') (($selB.Full | ForEach-Object { $_.empresa }) -join '|') 'C10 ordem dos FULL e deterministica'
Assert-Igual (($selA.Light | ForEach-Object { $_.empresa }) -join '|') (($selB.Light | ForEach-Object { $_.empresa }) -join '|') 'C10 ordem dos LIGHT e deterministica'

# --- cenario 11: motor usa ledger real e os dois tiers ---------------------------------------
$Runner = Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1'
$runnerTxt = if (Test-Path $Runner) { Get-Content -LiteralPath $Runner -Raw -Encoding UTF8 } else { '' }
Assert-True ($runnerTxt -match "lib\\vixradar-profundidade\.ps1") 'C11 motor carrega a lib de profundidade explicitamente'
Assert-True ($runnerTxt -match 'Get-VixFullSemanaDosLedgers') 'C11 motor reconstrui FULL_SEMANA pelos ledgers reais'
Assert-True ($runnerTxt -match 'Get-VixFullConfirmadosDoLedger') 'C11 motor une os FULL confirmados da matinal do dia'
Assert-True ($runnerTxt -match 'Select-VixProfundidadeNoturna') 'C11 motor calcula faltam e minFull pela uniao semanal antes dos lotes'
Assert-True ($runnerTxt -match 'New-VixJobsPorTier') 'C11 motor cria lotes distintos FULL e LIGHT'
Assert-True ($runnerTxt -match 'Invoke-VixOpenRouterLote -PromptPath \$promptPath -Tier \$Tier') 'C11 executor OpenRouter recebe o tier do lote, nao o perfil LIGHT'
Assert-True ($runnerTxt -match 'Invoke-ClaudeBatch \$promptPath \$job\.Model \$job\.Chunk\.Count \$job\.Tier') 'C11 executor repassa o tier aplicado ao lote'
Assert-True (-not ($runnerTxt -match 'GAP_MAX')) 'C11 nao existe gate GAP_MAX no motor'

# --- D1: cauda nao selecionada vira DEFERIDO -----------------------------------------------
# A cauda e quem entrou na decisao e nao foi escolhido para FULL nem LIGHT. Sem isto o emissor
# fica em limbo e o ledger nao fecha.
$carD1 = New-Carteira 104
$selD1 = Select-VixProfundidadeNoturna -Emissores $carD1 -FullSemana @{} -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
$filaD1 = @($selD1.Full) + @($selD1.Light)
$caudaD1 = Get-VixCaudaRotacao -AnalyzeList $carD1 -Fila $filaD1 -CapAtingido $false -TokenHardCap $Cap -CircuitoAberto $false
Assert-Igual (104 - $filaD1.Count) $caudaD1.Emissores.Count 'D1 a cauda e exatamente quem nao foi selecionado para FULL nem LIGHT'
Assert-Igual 'rotacao_semanal' $caudaD1.Motivo 'D1 a cauda sem corte de cap sai com motivo rotacao_semanal'
$naoCobertos = @($caudaD1.Emissores | Where-Object { $filaD1 -contains $_ })
Assert-Igual 0 $naoCobertos.Count 'D1 nenhum emissor da cauda esta tambem na fila'
$nomesCauda = @($caudaD1.Emissores | ForEach-Object { Get-NomeNormalizado $_.empresa })
$nomesFila = @($filaD1 | ForEach-Object { Get-NomeNormalizado $_.empresa })
Assert-Igual 104 (@($nomesCauda + $nomesFila | Sort-Object -Unique).Count) 'D1 cauda mais fila fecham os 104 sem repetir nome'

# --- D1/D2: o ledger fecha 104/104 ---------------------------------------------------------
# Simula uma noite inteira: 26 SKIP no plano, 21 FULL, 7 LIGHT, e a cauda DEFERIDO. O contrato
# do dia exige SKIP + ANALISADO + DEFERIDO = 104.
$carLed = New-Carteira 104
for ($i = 0; $i -lt 26; $i++) { $carLed[$i].tier = 'SKIP' }
$selLed = Select-VixProfundidadeNoturna -Emissores $carLed -FullSemana @{} -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
$filaLed = @($selLed.Full) + @($selLed.Light)
$caudaLed = Get-VixCaudaRotacao -AnalyzeList $carLed -Fila $filaLed -CapAtingido $false -TokenHardCap $Cap -CircuitoAberto $false
$nSkipLed = @($carLed | Where-Object { $_.tier -eq 'SKIP' }).Count
$nAnalisadoLed = $filaLed.Count
$nDeferidoLed = $caudaLed.Emissores.Count
Assert-Igual 104 ($nSkipLed + $nAnalisadoLed + $nDeferidoLed) 'D1 ledger fecha SKIP + selecionados + deferidos = 104'
Assert-Igual (78 - $filaLed.Count) $caudaLed.Emissores.Count 'D1 a cauda e o resto dos 78 elegiveis depois dos selecionados'
$caudaComSkipLed = @($caudaLed.Emissores | Where-Object { $_.tier -eq 'SKIP' })
Assert-Igual 0 $caudaComSkipLed.Count 'D1 SKIP nao entra na cauda de rotacao'
Assert-Igual 78 ($nAnalisadoLed + $nDeferidoLed) 'D1 os 78 elegiveis se dividem entre selecionados e deferidos, sem sobra'

# --- D1: CIRCUITO_ABERTO poe todo nao-SKIP em DEFERIDO -------------------------------------
# Com o cap zerado o seletor nao escolhe ninguem e a cauda e a lista inteira, com a causa real
# (cap), nao a rotacao. E o que o texto de CIRCUITO_ABERTO sempre prometeu.
$carCA = New-Carteira 104
for ($i = 0; $i -lt 26; $i++) { $carCA[$i].tier = 'SKIP' }
$selCA = Select-VixProfundidadeNoturna -Emissores $carCA -FullSemana @{} -BaseCarteira 104 -NoitesRestantes 5 -CapEfetivo ([int64]0) -CustoFull $CustoFull -CustoLight $CustoLight
$filaCA = @($selCA.Full) + @($selCA.Light)
$caudaCA = Get-VixCaudaRotacao -AnalyzeList $carCA -Fila $filaCA -CapAtingido $false -TokenHardCap ([int64]0) -CircuitoAberto $true
Assert-Igual 0 $filaCA.Count 'D1 CIRCUITO_ABERTO nao seleciona nenhum lote'
Assert-Igual 78 $caudaCA.Emissores.Count 'D1 CIRCUITO_ABERTO manda os 78 elegiveis para DEFERIDO'
Assert-Igual 'cap_efetivo' $caudaCA.Motivo 'D1 com circuito aberto o motivo e cap, nunca rotacao'
$nSkipCA = @($carCA | Where-Object { $_.tier -eq 'SKIP' }).Count
Assert-Igual 104 ($nSkipCA + $caudaCA.Emissores.Count) 'D1 CIRCUITO_ABERTO fecha os 104 entre SKIP e DEFERIDO'
# Cap estourado no meio da execucao tem o mesmo tratamento da cauda que sobrou.
$caudaMeio = Get-VixCaudaRotacao -AnalyzeList $carCA -Fila @() -CapAtingido $true -TokenHardCap $Cap -CircuitoAberto $false
Assert-Igual 'cap_efetivo' $caudaMeio.Motivo 'D1 cap atingido no meio tambem muda o motivo da cauda para cap'

# --- D2: restart no mesmo dia nao recompra FULL ja concluido -------------------------------
# Reproducao exata do caso do card: 63 FULL confirmados de segunda a quarta, 21 FULL confirmados
# pelo PROPRIO noturno hoje, restart na quinta. A uniao semanal tem de dar 84, faltam 20 e o
# minimo da noite ceil(20/2) = 10.
$tmpD2 = Join-Path $env:TEMP ('vix-profundidade-restart-' + $PID)
New-Item -ItemType Directory -Force -Path $tmpD2 | Out-Null
function LinhaFull([string]$nome, [string]$dia) { return ($dia + ' 18:00:00 OK|' + $nome + '|FULL|ECO|0|true|ANALISADO|0') }
$blocos = @(
    @{ dia = '2026-09-14'; de = 1;  ate = 21 }
    @{ dia = '2026-09-15'; de = 22; ate = 42 }
    @{ dia = '2026-09-16'; de = 43; ate = 63 }
    @{ dia = '2026-09-17'; de = 64; ate = 84 }
)
foreach ($b in $blocos) {
    $linhas = @()
    for ($i = $b.de; $i -le $b.ate; $i++) { $linhas += (LinhaFull ('EMISSOR ' + $i.ToString('000')) $b.dia) }
    Set-Content -LiteralPath (Join-Path $tmpD2 ('vixradar-noturno_' + ($b.dia -replace '-', '') + '.log')) -Value $linhas -Encoding UTF8
}
# O dia de hoje tem, alem dos 21 do noturno, a matinal com 3 FULL, um deles ja creditado.
@(
    (LinhaFull 'EMISSOR 001' '2026-09-17'),
    (LinhaFull 'EMISSOR 002' '2026-09-17'),
    (LinhaFull 'EMISSOR 003' '2026-09-17')
) | Set-Content -LiteralPath (Join-Path $tmpD2 'vixradar-matinal_20260917.log') -Encoding UTF8

$hojeD2 = [datetime]'2026-09-17'
$semanaOntemD2 = Get-VixFullSemanaDosLedgers $tmpD2 $hojeD2 -Ate $hojeD2.AddDays(-1)
Assert-Igual 63 $semanaOntemD2.Count 'D2 ate ontem a semana tem os 63 FULL dos tres dias anteriores'
$noturnoHojeD2 = Get-VixFullConfirmadosDoLedger $tmpD2 'noturno' $hojeD2
Assert-Igual 21 @($noturnoHojeD2).Count 'D2 o noturno de hoje ja tem 21 FULL confirmados'
$semanaHojeD2 = Get-VixFullSemanaDosLedgers $tmpD2 $hojeD2 -Ate $hojeD2
Assert-Igual 84 $semanaHojeD2.Count 'D2 lendo ate hoje a uniao semanal da 84, e nao 63'
# Os 3 FULL da matinal de hoje sao nomes que ja estavam na semana. Uniao por emissor, nunca
# soma de creditos brutos: o total tem de continuar 63 se so a matinal entrar.
$semanaSoMatinal = Merge-VixFullSemana -FullSemana $semanaOntemD2 -EmissoresFull @('EMISSOR 001', 'EMISSOR 002', 'EMISSOR 003') -Data $hojeD2
Assert-Igual 63 $semanaSoMatinal.Count 'D2 credito repetido da matinal nao incha a uniao semanal'
$selD2 = Select-VixProfundidadeNoturna -Emissores (New-Carteira 104) -FullSemana $semanaHojeD2 -BaseCarteira 104 -NoitesRestantes (Get-VixDiasUteisRestantes $hojeD2) -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
Assert-Igual 84 $selD2.Meta.ja_full_semana 'D2 o seletor enxerga os 84 ja creditados'
Assert-Igual 20 $selD2.Meta.faltam_na_semana 'D2 faltam cai para 20'
Assert-Igual 10 $selD2.Meta.min_full_noite 'D2 minFull vira ceil(20/2) = 10'
$repetidoD2 = @($selD2.Full | Where-Object { $semanaHojeD2.ContainsKey((Get-NomeNormalizado $_.empresa)) })
Assert-Igual 0 $repetidoD2.Count 'D2 nenhum FULL ja concluido hoje e recomprado pelo restart'
$carD2 = New-Carteira 104
$selD2b = Select-VixProfundidadeNoturna -Emissores $carD2 -FullSemana $semanaHojeD2 -BaseCarteira 104 -NoitesRestantes (Get-VixDiasUteisRestantes $hojeD2) -CapEfetivo $Cap -CustoFull $CustoFull -CustoLight $CustoLight
Assert-Igual 0 @($selD2b.Full | Where-Object { $semanaHojeD2.ContainsKey((Get-NomeNormalizado $_.empresa)) }).Count 'D2 a selecao de FULL nao repete nome ja creditado na semana'
Remove-Item -LiteralPath $tmpD2 -Recurse -Force -ErrorAction SilentlyContinue

# --- D3: custo com proveniencia declarada ---------------------------------------------------
$cf = Get-VixCustoEstimadoTier 'FULL'
$cl = Get-VixCustoEstimadoTier 'LIGHT'
Assert-Igual ([double]31068.75) $cf.Custo 'D3 o numero do FULL continua 31068.75'
Assert-Igual ([double]6023.82) $cl.Custo 'D3 o numero do LIGHT continua 6023.82'
Assert-Igual 'ESTIMATIVA_CONSERVADORA' $cf.Rotulo 'D3 o FULL vem rotulado como estimativa conservadora'
Assert-Igual $false $cf.Medido 'D3 o FULL declara que NAO e custo medido do lote noturno'
Assert-Igual 'FULL' $cf.Tier 'D3 AUDIT cai no mesmo custo do FULL'
Assert-Igual $cf.Custo (Get-VixCustoEstimadoTier 'AUDIT').Custo 'D3 AUDIT e FULL compartilham o custo aprofundado'
Assert-True ($cf.Ressenha -match 'chunk 16') 'D3 a ressalva nomeia a diferenca de chunk que faz o numero superestimar'
$libTxt3 = Get-Content -LiteralPath $Lib -Raw -Encoding UTF8
$ocorrencias = ([regex]::Matches($libTxt3, '31068\.75')).Count
Assert-Igual 1 $ocorrencias 'D3 o 31068.75 aparece uma unica vez na lib, dentro da funcao de custo'

# --- D4: prompt FULL carrega o contrato COBERTURA1 atual -----------------------------------
$skillFull = Join-Path $PSScriptRoot 'noturno-batch-sonnet.md'
Assert-True (Test-Path -LiteralPath $skillFull) 'D4 a skill do lote FULL existe no caminho que o motor usa'
$skillFullTxt = if (Test-Path -LiteralPath $skillFull) { Get-Content -LiteralPath $skillFull -Raw -Encoding UTF8 } else { '' }
foreach ($marcador in @('COBERTURA1', 'F1-emissor', 'F2-divida', 'F3-fato', 'FEEDRETRO1', 'FONTEDIVERG1', 'PROVAFALSA1', 'F3FETCH1')) {
    Assert-True ($skillFullTxt -match [regex]::Escape($marcador)) ('D4 skill FULL declara ' + $marcador)
}
Assert-True ($skillFullTxt -match 'sobrepoe') 'D4 skill FULL declara que COBERTURA1 sobrepoe o esquema de busca do arquivo'
Assert-True ($skillFullTxt -match 'tres familias|TRES familias|tres familias obrigatorias|nocao|NENHUM/ECO so vale com as TRES') 'D4 skill FULL exige as tres familias para certificar ausencia'
Assert-True (-not ($skillFullTxt -match 'max 3')) 'D4 o teto antigo de "max 3 buscas" saiu da skill FULL'
Assert-True (-not ($skillFullTxt -match 'R5')) 'D4 o esquema antigo de rodadas saiu da skill FULL'
Assert-True ($runnerTxt -match 'COBERTURA \(OBRIGATORIO, COBERTURA1\)') 'D4 o motor injeta COBERTURA1 no prompt de todo lote'
Assert-True ($runnerTxt -match 'noturno-batch-sonnet\.md') 'D4 o motor aponta o lote FULL para a skill nova'
Assert-True ($runnerTxt -match 'skill do lote FULL ausente') 'D4 existe boot gate de Test-Path para a skill FULL'
Assert-True ($runnerTxt -match 'contrato divergente do motor') 'D4 o boot gate confere os marcadores do contrato, nao so a existencia'
# Leitura do tier do perfil so pode sobrar no diagnostico de boot (MODELO_EFETIVO), que roda
# uma vez antes de existir lote. Dentro do caminho de lote o roteamento e sempre $job.Tier.
$leiturasPerfil = ([regex]::Matches($runnerTxt, 'Get-VixOpenRouterModel \$Perfil\.tier')).Count
Assert-Igual 1 $leiturasPerfil 'D4 so o diagnostico de boot le o modelo pelo tier do perfil'
$blocoBoot = [regex]::Match($runnerTxt, 'MODELO_EFETIVO:.*?Get-VixOpenRouterModel \$Perfil\.tier')
Assert-True (-not $blocoBoot.Success -or $blocoBoot.Index -lt $runnerTxt.IndexOf('function Invoke-ClaudeBatch')) 'D4 a unica leitura por perfil esta antes do caminho de lote'

# --- D1/D2/D3: amarras do motor -------------------------------------------------------------
Assert-True ($runnerTxt -match 'Get-VixCaudaRotacao') 'W1 o motor fecha a cauda pela funcao pura, nao por regra inline'
Assert-True ($runnerTxt -match 'Get-VixCustoEstimadoTier') 'W2 o motor le o custo pela funcao unica'
Assert-True ($runnerTxt -notmatch '31068\.75') 'W3 nao sobrou constante de custo solta no motor'
Assert-True ($runnerTxt -match '-Ate \$agoraProfundidade') 'W4 a leitura semanal vai ate hoje, nao ate ontem'
Assert-True ($runnerTxt -match 'Get-VixFullConfirmadosDoLedger \$LogDir ''noturno''') 'W5 o noturno de hoje entra no credito semanal'
Assert-True ($runnerTxt -match "_token_cap_deferred = \`$ehCorteDeCap") 'W6 rotacao nao marca _token_cap_deferred no Worker'
Assert-True ($runnerTxt -match 'deferred_rotacao') 'W7 o contador de deferido por rotacao existe no motor'

# --- TELEMETRIA: deferidos_cap exclui rotacao ----------------------------------------------
# A formula vive inline no motor. Em vez de provar por texto, o teste extrai a expressao REAL
# do fonte e executa com valores controlados - a mesma prova comportamental que o resto da
# suite usa. Se a formula mudar no motor, este teste acompanha; se alguem duplicar a conta em
# outro lugar, a unica-fonte abaixo reprova.
$exprCap = [regex]::Match($runnerTxt, '(?m)^\s*\$deferidosCap = (.+)$').Groups[1].Value
Assert-True ($exprCap -match 'Math\]::Max') 'T1 a formula de deferidos_cap existe no motor e usa max'
function Avaliar-Cap([int]$d, [int]$a, [int]$r) {
    $e = $exprCap
    $e = $e -replace '\$stats\.deferred_rotacao', "`$r"
    $e = $e -replace '\$stats\.deferred_auth', "`$a"
    $e = $e -replace '\$stats\.deferred\b', "`$d"
    return [int](Invoke-Expression $e)
}
Assert-Igual 0 (Avaliar-Cap 50 0 50) 'T2 deferred=50 auth=0 rotacao=50 resulta cap=0'
Assert-Igual 10 (Avaliar-Cap 50 10 30) 'T3 deferred=50 auth=10 rotacao=30 resulta cap=10'
Assert-Igual 50 (Avaliar-Cap 50 0 0) 'T4 sem rotacao nem auth o cap segue sendo o total de deferidos'
Assert-Igual 0 (Avaliar-Cap 0 0 0) 'T5 execucao sem deferido nenhum da cap=0'
Assert-Igual 0 (Avaliar-Cap 0 10 0) 'T6 contador negativo nao escapa: cap fica em 0'
Assert-Igual 0 (Avaliar-Cap 5 10 10) 'T7 mais causas que total nao gera cap negativo'
Assert-Igual 7 (Avaliar-Cap 30 0 23) 'T8 cap soma zero com rotacao e auth no mesmo dia'
$negativos = @()
foreach ($par in @(@(50, 0, 50), @(50, 10, 30), @(0, 10, 0), @(5, 10, 10), @(0, 0, 0), @(30, 0, 23))) {
    if ((Avaliar-Cap $par[0] $par[1] $par[2]) -lt 0) { $negativos += ($par -join '/') }
}
Assert-Igual 0 $negativos.Count 'T9 nenhuma combinacao devolve contador negativo'

# A conta aparece uma vez so no motor, e as duas pontas (metrics e FIM) leem dela.
$ocorrenciasFormula = ([regex]::Matches($runnerTxt, '\$stats\.deferred - \$stats\.deferred_auth')).Count
Assert-Igual 0 $ocorrenciasFormula 'T10 a formula antiga sem rotacao nao sobrou em lugar nenhum do motor'
Assert-Igual 3 ([regex]::Matches($runnerTxt, '\$deferidosCap')).Count 'T11 a variavel unica e definida uma vez e lida duas (metrics e FIM)'
# Comparacao por texto literal, nao por regex. Sao dois cantos do PowerShell que fazem a prova
# passar sem provar nada: em aspas duplas o `$` do regex expande como variavel, e um `''' ` no
# INICIO de aspas simples fecha a string cedo (o tokenizador le `''` como aspas escapada e o
# terceiro `'` como fim). Por isso os cifroes vao em variaveis de aspas simples e as aspas
# internas entram por concatenacao, sem ambiguidade.
$q = [char]39
$litCap = '$deferidosCap'
$litSt = '$stats.deferred_rotacao'
$needleMetricsCap = 'deferidos_cap = ' + $litCap
$needleFimCap = 'deferidos_cap=' + $q + ' + ' + $litCap
$needleFimRot = 'deferidos_rotacao=' + $q + ' + ' + $litSt
$needleMetricsRot = 'deferidos_rotacao = ' + $litSt
Assert-True ($runnerTxt.Contains($needleMetricsCap)) 'T12 o metrics JSON usa a variavel unica'
Assert-True ($runnerTxt.Contains($needleFimCap)) 'T13 a linha FIM usa a variavel unica, nao a conta inline'
Assert-True ($runnerTxt.Contains($needleFimRot)) 'T14 o FIM passa a expor deferidos_rotacao'
Assert-True ($runnerTxt.Contains($needleMetricsRot)) 'T15 o metrics JSON tambem expoe deferidos_rotacao'
# Prova das duas pontas: a mesma comparacao tem de ACEITAR a linha que le a variavel e REPROVAR
# a que recalcula. Sem a ponta ruim, T13 passaria com qualquer texto parecido com o certo.
$linhaBoa = 'deferidos_cap=' + $q + ' + ' + $litCap
$linhaFalsa = 'deferidos_cap= ' + $litSt + ' - $stats.deferred_auth'
Assert-True ($linhaBoa.Contains($needleFimCap)) 'T16 a comparacao aceita a linha que le a variavel'
Assert-True (-not $linhaFalsa.Contains($needleFimCap)) 'T17 a comparacao reprova a linha que recalcula a conta'

# --- LOG_MOTIVO: o texto do corte le a MESMA variavel (D6) ------------------------------------
# Uma noite de rotacao (deferidos_cap=0, deferidos_rotacao>0) escrevia `motivo=cap_efetivo` no
# log enquanto o metrics e a linha FIM do MESMO dia diziam rotacao_semanal. Diagnostico falso num
# lugar onde o operador le primeiro. A linha agora le $motivoDeferimentoEfetivo.
$litEfetivo = '$motivoDeferimentoEfetivo'
$litDeferido = '$motivoDeferido'
$litCall = 'Get-VixDeferidosTexto -Motivo '
$litOk = ' -Ok '
$needleCallBom = $litCall + $litEfetivo + $litOk
$needleCallVelho = $litCall + $litDeferido + $litOk
Assert-True ($runnerTxt.Contains($needleCallBom)) 'U1 o texto do corte le a variavel efetiva, nao o valor de partida'
Assert-True (-not $runnerTxt.Contains($needleCallVelho)) 'U2 a chamada antiga com o motivo de partida saiu do motor'
# O terminador ` -Ok ` da agulha negativa nao e decorativo. Hoje `$motivoDeferido` NAO e prefixo
# de `$motivoDeferimentoEfetivo` (divergem em `deferi|do` contra `deferi|mento`), entao as duas
# agulhas concordam no fonte real. Um nome futuro como `$motivoDeferidoEfetivo` reintroduziria a
# colisao de prefixo e ai a agulha curta passaria a ACEITAR a chamada antiga, deixando U2 verde
# sem provar nada. As tres linhas abaixo medem isso num fonte sintetico.
$fonteColisao = 'X Get-VixDeferidosTexto -Motivo ' + '$motivoDeferidoEfetivo' + ' -Ok Y'
Assert-True (-not $runnerTxt.Contains($litCall + $litDeferido)) 'U3 o fonte corrigido nao casa com a agulha curta'
Assert-True ($fonteColisao.Contains($litCall + $litDeferido)) 'U3a com nome prefixado a agulha curta daria falso positivo'
Assert-True (-not $fonteColisao.Contains($needleCallVelho)) 'U3b com o mesmo nome prefixado a agulha com terminador nao da falso positivo'
# Ordem: a definicao tem de vir ANTES do uso. $motivoDeferimentoEfetivo e um parametro Mandatory
# de Get-VixDeferidosTexto (linha 766), e Mandatory com $null ABRE PROMPT - numa tarefa agendada
# isso nao falha, trava.
$iDef = $runnerTxt.IndexOf($litEfetivo + ' = if (')
$iUso = $runnerTxt.IndexOf($needleCallBom)
Assert-True ($iDef -gt 0 -and $iUso -gt 0 -and $iDef -lt $iUso) 'U4 a definicao da variavel vem antes do uso no fonte'
Assert-Igual 1 ([regex]::Matches($runnerTxt, '\$motivoDeferimentoEfetivo = if \(').Count) 'U5 a variavel efetiva e definida uma unica vez (sem sobra da definicao antiga)'
Assert-Igual 1 ([regex]::Matches($runnerTxt, 'Get-VixDeferidosTexto -Motivo').Count) 'U6 existe um unico ponto que escreve a linha DEFERIDOS'
Assert-True ($runnerTxt.Contains('Get-VixCoberturaIncompletaTexto -Rotina ' + '$Rotina' + ' -Motivo ' + $litDeferido)) 'U7 a declaracao de cobertura incompleta segue lendo o motivo de partida (escopo: so o texto do corte mudou)'

# Prova comportamental: a expressao REAL e extraida do motor e executada com valores
# controlados. E esta saida que vai para a linha do log.
$exprMotivo = [regex]::Match($runnerTxt, '(?m)^\s*\$motivoDeferimentoEfetivo = (.+)$').Groups[1].Value
Assert-True ($exprMotivo -match 'rotacao_semanal') 'U8 a expressao do motivo efetivo existe no motor'
function Avaliar-MotivoEfetivo([int]$d, [int]$r, [string]$base) {
    $e = $exprMotivo
    $e = $e -replace '\$stats\.deferred_rotacao', "`$r"
    $e = $e -replace '\$stats\.deferred\b', "`$d"
    $e = $e -replace '\$motivoDeferido', ("'" + $base + "'")
    return [string](Invoke-Expression $e)
}
Assert-Igual 'rotacao_semanal' (Avaliar-MotivoEfetivo 50 50 'cap_efetivo') 'U9 noite so de rotacao: o log diz rotacao_semanal, nao cap_efetivo'
Assert-Igual 'cap_efetivo' (Avaliar-MotivoEfetivo 50 0 'cap_efetivo') 'U10 noite so de cap: o texto historico continua cap_efetivo'
Assert-Igual 'nenhum' (Avaliar-MotivoEfetivo 0 0 'cap_efetivo') 'U11 execucao sem deferido nao afirma corte nenhum'
Assert-Igual 'limite_sessao_assinatura' (Avaliar-MotivoEfetivo 50 30 'limite_sessao_assinatura') 'U12 corte misto com assinatura mantem a causa real'
Assert-Igual 'cap_efetivo' (Avaliar-MotivoEfetivo 50 10 'cap_efetivo') 'U13 rotacao parcial nao reescreve a causa da maioria'

# --- relatorio -------------------------------------------------------------------------------
Write-Host ''
Write-Host '--- simulacao de cinco noites (sem matinal) ---'
foreach ($h in $hist1) { Write-Host ('  ' + $h.dia + '  noites=' + $h.noites + '  FULL=' + $h.full + '  LIGHT=' + $h.light + '  estimado=' + $h.estimado + '/' + $Cap) }

$gapMax = 0
foreach ($e in (New-Carteira 104)) {
    if ($semana1.ContainsKey((Get-NomeNormalizado $e.empresa))) { continue }
    $d = [int][Math]::Floor([double]$e.horas_desde_analise / 24.0)
    if ($d -gt $gapMax) { $gapMax = $d }
}
Write-Host ('  emissores sem nenhum FULL na semana: ' + (104 - $semana1.Count))
Write-Host ''
Write-Host ('RESULTADO: pass=' + $pass + ' fail=' + $fail)
if ($fail -gt 0) { exit 1 }
exit 0
