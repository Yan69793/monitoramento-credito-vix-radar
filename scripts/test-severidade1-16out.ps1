# test-severidade1-16out.ps1 - SEVERIDADE1 (2026-10-16). Regra unica de modelo por severidade
# para a matinal e a noturna quando o executor e o Claude da assinatura.
# Partes:
#   A classificacao, duas pontas por nivel (CRITICO, ALTO, MONITORADO).
#   B montagem dos lotes: ordem dos niveis, tamanho de lote, modelo e ordem interna preservada.
#   C replay do plano real da noturna de 16/10 (noturno_plano_20261016.json).
#   D ligacao no motor: as duas rotinas usam a regra so com $script:VixRegraSeveridade.
# ASCII puro, PowerShell 5.1. Saida: exit 0 = tudo verde, 1 = alguma falha.

param([string]$LogDir = '')
$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Sv([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
$Projeto = Split-Path $Scripts -Parent
if (-not $LogDir) { $LogDir = Join-Path $Projeto 'logs\routines' }
. (Join-Path $Scripts 'lib\vixradar-profundidade.ps1')
function New-EmissorSv([string]$Nome, [double]$Ews, [int]$Cvm = 0, [string[]]$Motivos = @('deferred_prioritario')) {
    return [pscustomobject]@{ empresa = $Nome; ews_score = $Ews; cvm_novos = $Cvm; motivos = $Motivos; tier = 'FULL' }
}

Write-Host '== A classificacao =='
Assert-Sv ((Get-VixSeveridadeEmissor (New-EmissorSv 'Oi' 55)).Nivel -eq 'CRITICO') 'A1 EWS 55 e CRITICO'
Assert-Sv ((Get-VixSeveridadeEmissor (New-EmissorSv 'X' 49.9)).Nivel -eq 'ALTO') 'A2 EWS 49,9 nao e CRITICO (fronteira)'
Assert-Sv ((Get-VixSeveridadeEmissor (New-EmissorSv 'Cosan' 36 1 @('cvm_delta_1'))).Nivel -eq 'CRITICO') 'A3 CVM novo com EWS 36 e CRITICO'
Assert-Sv ((Get-VixSeveridadeEmissor (New-EmissorSv 'Y' 30)).Nivel -eq 'ALTO') 'A4 EWS 30 e ALTO'
Assert-Sv ((Get-VixSeveridadeEmissor (New-EmissorSv 'Z' 29.9)).Nivel -eq 'MONITORADO') 'A5 EWS 29,9 sem gatilho e MONITORADO (fronteira)'
Assert-Sv ((Get-VixSeveridadeEmissor (New-EmissorSv 'W' 2 1 @('cvm_delta_1'))).Nivel -eq 'ALTO') 'A6 CVM novo com EWS baixo e ALTO'
Assert-Sv ((Get-VixSeveridadeEmissor (New-EmissorSv 'Taesa' 18 0 @('imprensa_recente_7d'))).Nivel -eq 'ALTO') 'A7 imprensa recente e ALTO'
Assert-Sv ((Get-VixSeveridadeEmissor (New-EmissorSv 'Itau' 0 0 @('setor_financeiro_full'))).Nivel -eq 'MONITORADO') 'A8 rotacao do setor financeiro sem gatilho e MONITORADO'
Assert-Sv ((Get-VixSeveridadeEmissor ([pscustomobject]@{ empresa = 'Sem campos' })).Nivel -eq 'MONITORADO') 'A9 emissor sem EWS nem motivos nao quebra e vira MONITORADO'

Write-Host '== B montagem dos lotes =='
$sel = @(
    (New-EmissorSv 'm1' 1), (New-EmissorSv 'c1' 55), (New-EmissorSv 'a1' 40), (New-EmissorSv 'm2' 0),
    (New-EmissorSv 'c2' 61), (New-EmissorSv 'c3' 50), (New-EmissorSv 'm3' 2), (New-EmissorSv 'a2' 31),
    (New-EmissorSv 'm4' 0), (New-EmissorSv 'm5' 0), (New-EmissorSv 'm6' 0), (New-EmissorSv 'm7' 0)
)
$jobs = @(New-VixJobsPorSeveridade -Selecionados $sel -ModelSonnet 'sonnet' -ModelHaiku 'haiku' -Skill 'skill.md' -Provedor 'p')
$niveis = @($jobs | ForEach-Object { $_.Severidade })
Assert-Sv (($niveis -join ',') -eq 'CRITICO,CRITICO,ALTO,MONITORADO,MONITORADO') 'B1 ordem CRITICO, ALTO, MONITORADO com lotes de 2, 4 e 6'
Assert-Sv ((@($jobs[0].Chunk | ForEach-Object { $_.empresa }) -join ',') -eq 'c1,c2') 'B2 ordem de entrada preservada dentro do nivel'
Assert-Sv ($jobs[0].Model -eq 'sonnet' -and $jobs[2].Model -eq 'sonnet' -and $jobs[3].Model -eq 'haiku') 'B3 CRITICO e ALTO no Sonnet, MONITORADO no Haiku'
Assert-Sv ((@($jobs | ForEach-Object { $_.Skill }) | Select-Object -Unique) -eq 'skill.md') 'B4 todos os niveis usam o mesmo roteiro profundo'
Assert-Sv ((@($jobs | ForEach-Object { $_.Tier }) | Select-Object -Unique) -eq 'FULL') 'B5 todos seguem FULL (ledger e cobertura semanal creditam igual)'
$tot = 0; foreach ($j in $jobs) { $tot += @($j.Chunk).Count }
Assert-Sv ($tot -eq $sel.Count) 'B6 nenhum emissor some nem duplica'
Assert-Sv (@(New-VixJobsPorSeveridade -Selecionados @() -ModelSonnet 's' -ModelHaiku 'h').Count -eq 0) 'B7 selecao vazia nao gera lote'

Write-Host '== B2 promocao do lote rapido =='
$pr = Select-VixPromocaoSeveridade -Full @((New-EmissorSv 'f1' 0)) -Light @((New-EmissorSv 'l1' 0), (New-EmissorSv 'Oi' 55), (New-EmissorSv 'l2' 1), (New-EmissorSv 'Cemig' 2 3 @('deferred_prioritario')))
Assert-Sv ((@($pr.Promovidos) -join ',') -eq 'Oi,Cemig') 'B8 CRITICO e ALTO saem do lote rapido'
Assert-Sv ((@($pr.Light | ForEach-Object { $_.empresa }) -join ',') -eq 'l1,l2') 'B9 MONITORADO continua no lote rapido, na ordem'
Assert-Sv ((@($pr.Full | ForEach-Object { $_.empresa }) -join ',') -eq 'f1,Oi,Cemig') 'B10 aprofundamento recebe os promovidos depois dos que ja estavam'
$pr0 = Select-VixPromocaoSeveridade -Full @() -Light @((New-EmissorSv 'l1' 0))
Assert-Sv ($pr0.Promovidos.Count -eq 0 -and $pr0.Light.Count -eq 1) 'B11 sem severidade alta nada muda'

Write-Host '== C replay do plano real de 16/10 =='
$planoPath = Join-Path $LogDir 'noturno_plano_20261016.json'
if (Test-Path -LiteralPath $planoPath) {
    $p = Get-Content -LiteralPath $planoPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $full = @($p.emissores | Where-Object { $_.t -eq 'FULL' } | ForEach-Object {
        $cvm = 0; if (('' + $_.m) -match 'cvm_delta_(\d+)') { $cvm = [int]$Matches[1] }
        New-EmissorSv ('' + $_.e) ([double]$_.ews) $cvm @('' + $_.m) })
    $rj = @(New-VixJobsPorSeveridade -Selecionados $full -ModelSonnet 'sonnet' -ModelHaiku 'haiku' -Skill 's' -Provedor 'p')
    $nS = 0; $nH = 0; $lS = 0; $lH = 0
    foreach ($j in $rj) { if ($j.Model -eq 'sonnet') { $nS += @($j.Chunk).Count; $lS++ } else { $nH += @($j.Chunk).Count; $lH++ } }
    Write-Host ('  plano FULL=' + $full.Count + ' sonnet=' + $nS + ' em ' + $lS + ' lotes, haiku=' + $nH + ' em ' + $lH + ' lotes')
    Assert-Sv (($nS + $nH) -eq $full.Count) 'C1 todo FULL do plano real tem lote'
    Assert-Sv ($nS -ge 4 -and $nS -lt $full.Count) 'C2 Sonnet fica com os graves (>= os 4 com EWS>=50) e nao com o plano inteiro'
    $nomesS = @($rj | Where-Object { $_.Model -eq 'sonnet' } | ForEach-Object { $_.Chunk } | ForEach-Object { $_.empresa })
    Assert-Sv (($nomesS -contains 'Oi') -and ($nomesS -contains 'Light') -and ($nomesS -contains 'Kora Sa' + [char]0xFA + 'de')) 'C3 Oi, Light e Kora ficam no Sonnet'
} else { Write-Host '  (plano de 16/10 ausente, parte C pulada)' }

Write-Host '== D ligacao no motor =='
$m = [System.IO.File]::ReadAllText((Join-Path $Scripts 'run_vixradar_varredura.ps1'))
Assert-Sv (([regex]::Matches($m, 'New-VixJobsPorSeveridade -Selecionados')).Count -eq 2) 'D1 matinal e noturna chamam a regra'
Assert-Sv ($m -match "\`$script:VixRegraSeveridade = \(\(Get-VixLlmProvider\) -eq 'claude-subscription'\)") 'D2 regra so liga com claude-subscription'
Assert-Sv (([regex]::Matches($m, 'if \(\$script:VixRegraSeveridade\) \{')).Count -ge 3) 'D3 caminho antigo preservado atras do mesmo interruptor (noturna, matinal, log)'
Assert-Sv ($m -match 'Select-VixPromocaoSeveridade -Full \$fullSelecionados -Light \$lightSelecionados') 'D4 noturna promove severidade alta do lote rapido antes de montar os lotes'
$ancora = Join-Path $LogDir 'vixradar-noturno_20261016.log'
if (Test-Path -LiteralPath $ancora) {
    $la = @(Get-Content -LiteralPath $ancora -Encoding UTF8 | Where-Object { $_ -match '^2026-10-16 20:42:25 ALVO (Oi|Kora Sa.de|P.o de A.+car \(GPA\)) .*tier_aplicado=LIGHT .*ews=55' })
    Assert-Sv ($la.Count -eq 3) 'D5 ancora: na rodada de 20:42 os 3 de EWS 55 tinham caido no lote rapido (o defeito)'
}

Write-Host ('RESULTADO: ok=' + $script:Ok + ' falhas=' + $script:Falhas)
if ($script:Falhas -gt 0) { exit 1 }
exit 0
