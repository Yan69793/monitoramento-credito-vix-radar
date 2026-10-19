# test-plantao-matinal.ps1 - prova de duas pontas do PLANTAO1 (2026-10-19)
#
# Prova a regra pura de lib\vixradar-plantao.ps1, a mesma que o motor e o monitor usam:
# decisao do dia, linha FIM do plantao, exit da matinal e evidencia de entrega do monitor.
# Mais checagens estruturais de que motor, Sentinela e monitor chamam a lib.
# Sem rede, sem token. Saida: JSON no fim e exit 0 so com tudo verde.
$ErrorActionPreference = 'Continue'
$ScriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptsDir 'lib\vixradar-plantao.ps1')

$script:ok = 0; $script:falhas = New-Object System.Collections.Generic.List[string]
function Assert-Igual($nome, $esperado, $obtido) {
    if ("$esperado" -eq "$obtido") { $script:ok++; Write-Output ("OK   " + $nome) }
    else { $script:falhas.Add($nome); Write-Output ("FAIL " + $nome + " esperado=[" + $esperado + "] obtido=[" + $obtido + "]") }
}
function Get-Dia([string]$s) { return [datetime]::ParseExact($s, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }

# 1. Decisao do dia
$fer = Get-VixFeriadosB3
Assert-Igual 'sabado 17/10 e fim_de_semana' 'fim_de_semana' (Get-VixModoDia (Get-Dia '2026-10-17') $fer)
Assert-Igual 'domingo 18/10 e fim_de_semana' 'fim_de_semana' (Get-VixModoDia (Get-Dia '2026-10-18') $fer)
Assert-Igual 'segunda 12/10 feriado e feriado' 'feriado' (Get-VixModoDia (Get-Dia '2026-10-12') $fer)
Assert-Igual 'domingo 15/11 feriado vence fds' 'feriado' (Get-VixModoDia (Get-Dia '2026-11-15') $fer)
Assert-Igual 'segunda 19/10 e util' 'util' (Get-VixModoDia (Get-Dia '2026-10-19') $fer)
Assert-Igual 'sexta 16/10 e util' 'util' (Get-VixModoDia (Get-Dia '2026-10-16') $fer)

# 2. Sabado quieto: Sentinela sai 0 sem gatilho -> plantao OK em 0 token, exit 0
$fimQuieto = '2026-10-17 10:06:20 FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=plantao_sem_novidade'
$lq = Get-VixPlantaoFimLinha 'fim_de_semana' 0 $fimQuieto
Assert-Igual 'quieto: resultado OK' $true ($lq -match 'resultado=OK ')
Assert-Igual 'quieto: tokens=0' $true ($lq -match ' tokens=0 ')
Assert-Igual 'quieto: motivo copiado' $true ($lq -match 'motivo_sentinela=plantao_sem_novidade$')
Assert-Igual 'quieto: exit 0' 0 (Get-VixPlantaoExit 0 $fimQuieto)

# 3. Sabado com evento e analise incompleta: exit 10 -> PARCIAL, exit 10
$fimParcial = '2026-10-17 10:20:00 FIM: sentinela resultado=PARCIAL. tokens=150000 analisados=1 submit_fail=0 deferidos=1'
$lp = Get-VixPlantaoFimLinha 'fim_de_semana' 10 $fimParcial
Assert-Igual 'evento parcial: resultado PARCIAL' $true ($lp -match 'resultado=PARCIAL ')
Assert-Igual 'evento parcial: analisados=1' $true ($lp -match ' analisados=1 ')
Assert-Igual 'evento parcial: exit 10' 10 (Get-VixPlantaoExit 10 $fimParcial)

# 4. Ponta ruim: exit 0 mas Sentinela sem FIM (morreu antes) nunca vira OK
$lsf = Get-VixPlantaoFimLinha 'feriado' 0 ''
Assert-Igual 'sem FIM: resultado FALHA' $true ($lsf -match 'resultado=FALHA ')
Assert-Igual 'sem FIM: exit 1' 1 (Get-VixPlantaoExit 0 '')
Assert-Igual 'health fora: exit 3 e FALHA' $true ((Get-VixPlantaoFimLinha 'feriado' 3 'FIM: sentinela abortada. tokens=0 analisados=0 motivo=health_inacessivel') -match 'resultado=FALHA ')
Assert-Igual 'provider bloqueado: BLOQUEADO' 'BLOQUEADO' (Get-VixPlantaoResultado 86)

# 5. Ultimo FIM da Sentinela no log (ignora SHADOW_FIM e pega o mais recente)
$linhasLog = @('2026-10-17 10:06:01 INICIO: sentinela teto=8', '2026-10-17 10:06:02 SHADOW_FIM: sentinela x', '2026-10-17 10:06:03 FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=colisao_matinal', '2026-10-17 10:07:00 FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=plantao_sem_novidade')
Assert-Igual 'ultimo FIM e o mais recente' $true ((Get-VixSentinelaUltimoFim $linhasLog) -match 'plantao_sem_novidade$')
Assert-Igual 'log sem FIM devolve vazio' '' (Get-VixSentinelaUltimoFim @('2026-10-17 10:06:01 INICIO: sentinela', '2026-10-17 10:06:02 SHADOW_FIM: sentinela x'))

# 6. Monitor: aceita OK e PARCIAL, reprova FALHA e ausencia
$entOk = Get-VixPlantaoEntrega ("2026-10-17 10:06:00 PLANTAO: x`r`n2026-10-17 10:07:01 " + $lq)
Assert-Igual 'monitor: OK entregue' $true $entOk.Entregue
Assert-Igual 'monitor: modo lido' 'fim_de_semana' $entOk.Modo
Assert-Igual 'monitor: PARCIAL entregue' $true (Get-VixPlantaoEntrega ('2026-10-17 10:20:01 ' + $lp)).Entregue
Assert-Igual 'monitor: FALHA nao entregue' $false (Get-VixPlantaoEntrega ('2026-10-12 10:07:00 ' + $lsf)).Entregue
Assert-Igual 'monitor: log sem plantao e null' $true ($null -eq (Get-VixPlantaoEntrega '2026-10-17 10:14:41 FIM: matinal concluido. Total do dia 22/22'))
Assert-Igual 'monitor: vale a ultima linha' $true (Get-VixPlantaoEntrega ("2026-10-17 10:07:00 " + $lsf + "`r`n2026-10-17 11:00:00 " + $lq)).Entregue

# 7. Estrutura: motor, Sentinela e monitor usam a lib e o modo
$motor = Get-Content -LiteralPath (Join-Path $ScriptsDir 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
$sent  = Get-Content -LiteralPath (Join-Path $ScriptsDir 'run_vixradar_sentinela.ps1') -Raw -Encoding UTF8
$mon   = Get-Content -LiteralPath (Join-Path $ScriptsDir 'monitor-tasks.ps1') -Raw -Encoding UTF8
Assert-Igual 'motor carrega a lib' $true ($motor -match [regex]::Escape("lib\vixradar-plantao.ps1"))
Assert-Igual 'motor chama Sentinela -Plantao' $true ($motor -match "'-Plantao'")
Assert-Igual 'motor sem lista de feriado inline' $false ($motor -match "\`$feriados = @\(")
Assert-Igual 'sentinela tem param Plantao' $true ($sent -match '\[switch\]\$Plantao')
# SENTINELASHA1 (19/10): a decisao do plantao saiu para lib\vixradar-sentinela-portao.ps1; a tabela
# completa (cego antes de quieto, backlog nao dispara) e provada em test-sentinela-portao.ps1.
Assert-Igual 'sentinela: plantao decidido pelo portao' $true ($sent -match '-Plantao \(\[bool\]\$Plantao\)')
Assert-Igual 'sentinela: plantao preserva pending' $true ($sent -match 'Write-State \$workerLm \$zipLmParaEstado \$pendingAnterior \$streak')
Assert-Igual 'sentinela: cego sai exit 3' $true ($sent -match "Acao -eq 'cego'")
Assert-Igual 'fonte cega (exit 3) vira FALHA no plantao' 'FALHA' (Get-VixPlantaoResultado 3)
Assert-Igual 'monitor carrega a lib' $true ($mon -match [regex]::Escape("lib\vixradar-plantao.ps1"))
Assert-Igual 'monitor julga plantao' $true ($mon -match 'Get-VixPlantaoEntrega')

$res = [ordered]@{ suite = 'test-plantao-matinal'; ok = $script:ok; falhas = $script:falhas.Count; nomes_falha = @($script:falhas) }
Write-Output ($res | ConvertTo-Json -Compress)
if ($script:falhas.Count -gt 0) { exit 1 }
exit 0
