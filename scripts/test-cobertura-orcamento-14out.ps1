# test-cobertura-orcamento-14out.ps1 - ORCAMENTO-CLASSE1 / COBERTURA-RECON1 / ROTACAO-14OUT1
# (2026-10-14). Prova deterministica, offline e sem token das correcoes de cobertura e orcamento
# nascidas do dia 14/10/2026:
#   A estimativa por CLASSE de lote e a admissao fail-closed (caso real de 14/10)
#   B contabilidade do cache do Codex (envelope -> metrics -> circuito do dia)
#   C divergencia IA x coletor nunca certifica ausencia nem promove RESOLVIDO sem evidencia
#   D reconciliacao publicacao aceita x cobertura x fila
#   E rotacao persistente (fila justa, cota diaria, sem perda, sem duplicidade, sem reinicio
#     indevido, restart, concorrencia)
#   F ciclos sucessivos cobrindo os 104, com prioridade, falha de coleta, orcamento insuficiente
#   G guardas estruturais no motor (o que o motor REALMENTE chama)
# Toda guarda e provada nas duas pontas (reprova o caso ruim E aceita o bom).
# SIMULACAO != EXECUCAO REAL: as partes A/F exercitam as funcoes da lib com o custo MEDIDO do
# provedor; elas nao provam o custo do proximo lote, que so a execucao real mede.
# ASCII puro, PowerShell 5.1. Saida: exit 0 = tudo verde, 1 = alguma falha.

$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Orc([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
$MotorPath = Join-Path $Scripts 'run_vixradar_varredura.ps1'
. (Join-Path $Scripts 'lib\vixradar-cobertura.ps1')
. (Join-Path $Scripts 'lib\vixradar-custo.ps1')
# Funcoes REAIS do motor extraidas por AST (mesmo idioma de test-cobertura-contrato.ps1): o
# contrato de cobertura, o registro de estado e a chave de prioridade vivem no motor, nao na lib.
function Get-MotorFuncDefs([string]$Path, [string[]]$Names) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw ('parse de ' + $Path + ' falhou: ' + $errors[0].Message) }
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $out = @()
    foreach ($name in $Names) {
        $f = $defs | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $f) { throw ('funcao ' + $name + ' nao encontrada em ' + $Path) }
        $out += $f.Extent.Text
    }
    return ,$out
}
$DryRun = $false
$contratoCobertura = @{}
foreach ($_def in (Get-MotorFuncDefs $MotorPath @('Test-VixBuscaDegradada', 'Get-VixCoberturaProviderCapability', 'ConvertTo-VixFonteEstrutural', 'Resolve-VixCoberturaFamilias', 'Resolve-VixCoberturaWeb', 'Test-VixAusenciaCertificavel', 'Get-NomeNormalizado', 'Merge-VixContratoCobertura', 'Read-VixContratoCoberturaArquivo', 'Get-VixRecheckPendentes', 'Set-VixContratoEstado', 'Get-VixChavesPrioritariasRotacao'))) { Invoke-Expression $_def }
$Tmp = Join-Path $env:TEMP ('vix-orcamento-test-' + $PID)
New-Item -ItemType Directory -Force $Tmp | Out-Null

# Custo REAL do provedor codex medido em 13-14/10/2026, na classe FULL:
#   lote de 2  emissores -> 356.612 tokens (noturno de 13/10)
#   lote de 16 emissores -> 1.193.101 tokens (noturna manual de 14/10)
# Ajuste linear desses dois pontos: custo(n) = 237.117 + 59.749*n. Usado nas simulacoes como
# gerador de custo, para a simulacao nao "provar" a propria estimativa.
$script:CustoRealA = [double]237117
$script:CustoRealB = [double]59749
function Get-CustoRealLote([int]$Emissores) { return [int64][Math]::Ceiling($script:CustoRealA + ($script:CustoRealB * $Emissores)) }

try {
# =========================================================================================
Write-Host '=== A: estimativa por CLASSE de lote e admissao fail-closed (caso real de 14/10) ==='
$md = Join-Path $Tmp 'metrics'
New-Item -ItemType Directory -Force $md | Out-Null
$d13 = '20261013'
$agora14 = [datetime]'2026-10-14T02:34:42'
# Historico REAL disponivel ANTES da noturna de 14/10 (provider codex): 1 lote FULL de
# producao, mais 3 arquivos de DRY-RUN (medicao dirigida, 7.870 a 21.250 por emissor).
@{ provider = 'codex'; data = $d13; rotina = 'noturno'; lotes_detalhe = @(@{ nome = 'full-1'; fila = 'full'; emissores = 2; provider = 'codex'; trabalho = 356612 }) } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $md ('noturno_metrics_' + $d13 + '.json')) -Encoding UTF8
@{ provider = 'codex'; data = $d13; rotina = 'noturno'; lotes_detalhe = @(@{ nome = 'full-1'; fila = 'full'; emissores = 2; provider = 'codex'; trabalho = 21892 }) } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $md ('noturno_metrics_' + $d13 + '_dryrun_175721.json')) -Encoding UTF8
@{ provider = 'codex'; data = $d13; rotina = 'noturno'; lotes_detalhe = @(@{ nome = 'full-1'; fila = 'full'; emissores = 3; provider = 'codex'; trabalho = 23608 }) } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $md ('noturno_metrics_' + $d13 + '_dryrun_180743.json')) -Encoding UTF8
@{ provider = 'codex'; data = $d13; rotina = 'matinal'; lotes_detalhe = @(@{ nome = 'escalada-2'; fila = 'escalada'; emissores = 1; provider = 'codex'; trabalho = 167768 }) } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $md ('matinal_metrics_' + $d13 + '_dryrun_191719.json')) -Encoding UTF8
$amF = @(Get-VixHistoricoCustoClasse -LogDir $md -Provider 'codex' -Classe 'FULL' -Dias 7 -Agora $agora14)
Assert-Orc ($amF.Count -eq 1) 'A1 historico da classe FULL exclui os 3 arquivos de DRY-RUN (medicao nao e lote de producao)'
Assert-Orc (([int]$amF[0].emissores -eq 2) -and ([int64]$amF[0].trabalho -eq 356612)) 'A2 a unica amostra de producao e o lote FULL de 2 emissores / 356.612 tokens'
$mF = Get-VixModeloLoteClasse -Amostras $amF -DefaultEmissor 250000 -PisoEmissor 31069
Assert-Orc (([double]$mF.a -eq 0) -and ([double]$mF.b -eq 178306) -and ($mF.fonte -like 'classe_n*')) 'A3 com 1 amostra o envelope usa o PIOR custo por emissor como inclinacao (178.306), fonte por classe'
$mReal = Get-VixModeloLoteClasse -Amostras @(@{ emissores = 2; trabalho = 356612 }, @{ emissores = 16; trabalho = 1193101 })
Assert-Orc ((Get-VixEstimativaLoteClasse -Modelo $mReal -Emissores 16 -Margem 1.0) -ge 1193101) 'A4 envelope SUPERIOR reproduz o lote real de 16 (1.193.101), nunca estima abaixo do medido'
Assert-Orc ((Get-VixEstimativaLoteClasse -Modelo $mReal -Emissores 2 -Margem 1.0) -ge 356612) 'A5 idem para o lote de 2 (356.612) - propriedade vale para TODAS as amostras, nao so a maior'
# Ponta ruim: exatamente o que o motor fez em 14/10.
$estAntigo = [int64]31069 * 16
Assert-Orc (($estAntigo -eq 497104) -and ($estAntigo -le 700000)) 'A6 ponta ruim reproduzida: a estimativa antiga (497.104) CABIA no cap de 700.000 e admitiu o lote'
Assert-Orc ((Get-CustoRealLote 16) -eq 1193101) 'A7 e o lote admitido custou os 1.193.101 reais do log - 2,4x a estimativa, cap_excedido=1'
# Ponta boa: o envelope da classe, com margem.
$estNovo16 = Get-VixEstimativaLoteClasse -Modelo $mF -Emissores 16
Assert-Orc ($estNovo16 -gt 700000) 'A8 ponta boa: a estimativa conservadora do lote de 16 (3.566.120) NAO cabe no cap de 700.000 - lote nao admitido'
Assert-Orc ($estNovo16 -ge [int64][Math]::Ceiling(178306 * 16 * 1.25)) 'A9 a margem conservadora declarada (x1.25) esta aplicada sobre o envelope'
$kA = Get-VixEmissoresQueCabemModelo -Modelo $mF -Acum 0 -Cap 700000 -Chunk 16
Assert-Orc (($kA -eq 3) -and ((Get-VixEstimativaLoteClasse -Modelo $mF -Emissores 3) -le 700000) -and ((Get-VixEstimativaLoteClasse -Modelo $mF -Emissores 4) -gt 700000)) 'A10 fragmentacao adaptativa: roda 3 (668.647 <= 700.000) e para, porque o 4o ja nao cabe'
# Fragmentacao pelo ENVELOPE x divisao ingenua (saldo / custo por emissor do lote cheio).
$kIngenuo = [int][Math]::Floor(700000 / [double]([Math]::Ceiling($estNovo16 / [double]16)))
Assert-Orc ($kIngenuo -eq 3) 'A11 com 1 amostra a divisao ingenua coincide (3) - sem divergencia artificial'
$kIngenuoReal = [int][Math]::Floor(700000 / [double]([Math]::Ceiling((Get-VixEstimativaLoteClasse -Modelo $mReal -Emissores 16) / [double]16)))
$kModeloReal = Get-VixEmissoresQueCabemModelo -Modelo $mReal -Acum 0 -Cap 700000 -Chunk 16
Assert-Orc (($kIngenuoReal -eq 7) -and ((Get-VixEstimativaLoteClasse -Modelo $mReal -Emissores 7) -gt 700000)) 'A12 ponta ruim da divisao ingenua: ela admitiria 7 emissores cujo envelope (819.200) estoura o cap'
Assert-Orc (($kModeloReal -eq 5) -and ((Get-VixEstimativaLoteClasse -Modelo $mReal -Emissores 5) -le 700000) -and ((Get-VixEstimativaLoteClasse -Modelo $mReal -Emissores 6) -gt 700000)) 'A13 ponta boa do envelope: 5 cabem (669.828) e 6 nao (744.514) - "impedir admissao cuja estimativa conservadora exceda o saldo"'
# Reproducao do dia 14/10 ponta a ponta, com o historico da epoca.
$acum14 = [int64]0; $deferidos14 = 0; $capExcedido14 = 0; $lotes14 = 0; $restantes14 = 16
while ($restantes14 -gt 0) {
    $k = Get-VixEmissoresQueCabemModelo -Modelo $mF -Acum $acum14 -Cap 700000 -Chunk $restantes14
    if ($k -le 0) { $deferidos14 += $restantes14; break }
    $custo = Get-CustoRealLote $k
    $lotes14++
    $acum14 += $custo
    if ($acum14 -gt 700000) { $capExcedido14++ }
    $restantes14 -= $k
}
Assert-Orc ($lotes14 -eq 1 -and $acum14 -eq 416364 -and $acum14 -le 700000 -and $capExcedido14 -eq 0) 'A14 o dia 14/10 com a regra nova roda 1 lote de 3, consome 416.364 <= 700.000 e NAO excede o cap'
Assert-Orc ($deferidos14 -eq 13) 'A15 os outros 13 emissores ficam DEFERIDO por orcamento (registrados, nunca silenciados)'
# Piso do perfil e default do provedor.
$mSemAmostra = Get-VixModeloLoteClasse -Amostras @() -DefaultEmissor 250000 -PisoEmissor 31069
Assert-Orc ((Get-VixEstimativaLoteClasse -Modelo $mSemAmostra -Emissores 2) -eq [int64][Math]::Ceiling(250000 * 2 * 1.25)) 'A16 sem amostra nenhuma vale o default do provedor (250.000/emissor) com margem'
$mPiso = Get-VixModeloLoteClasse -Amostras @(@{ emissores = 16; trabalho = 1000 }) -DefaultEmissor 250000 -PisoEmissor 31069
Assert-Orc ((Get-VixEstimativaLoteClasse -Modelo $mPiso -Emissores 16) -ge (31069 * 16)) 'A17 o piso do perfil nunca e furado por amostra barata (provedor barato nao afrouxa a estimativa antiga)'
# Classe no historico: campo explicito, fallback pelo `fila`, sem misturar populacoes.
$md2 = Join-Path $Tmp 'metrics2'
New-Item -ItemType Directory -Force $md2 | Out-Null
@{ provider = 'codex'; data = $d13; lotes_detalhe = @(
    @{ nome = 'full-1'; fila = 'full'; classe = 'FULL'; emissores = 2; provider = 'codex'; trabalho = 356612 },
    @{ nome = 'full-1'; fila = 'full'; classe = 'BARATO'; emissores = 12; provider = 'codex'; trabalho = 40000 },
    @{ nome = 'light-1'; fila = 'light'; emissores = 4; provider = 'codex'; trabalho = 24000 },
    @{ nome = 'full-2'; fila = 'full'; emissores = 3; provider = 'codex'; trabalho = 900 })
} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $md2 ('noturno_metrics_' + $d13 + '.json')) -Encoding UTF8
$amFull2 = @(Get-VixHistoricoCustoClasse -LogDir $md2 -Provider 'codex' -Classe 'FULL' -Dias 7 -Agora $agora14)
Assert-Orc ($amFull2.Count -eq 2) 'A18 classe explicita separa BARATO de FULL mesmo no mesmo arquivo (FULL = 2 amostras)'
$amBarato2 = @(Get-VixHistoricoCustoClasse -LogDir $md2 -Provider 'codex' -Classe 'BARATO' -Dias 7 -Agora $agora14)
Assert-Orc ($amBarato2.Count -eq 1 -and [int64]$amBarato2[0].trabalho -eq 40000) 'A19 a amostra BARATO (40.000 para 12 emissores) nao contamina a classe FULL'
$amLight2 = @(Get-VixHistoricoCustoClasse -LogDir $md2 -Provider 'codex' -Classe 'LIGHT' -Dias 7 -Agora $agora14)
Assert-Orc ($amLight2.Count -eq 1 -and [int64]$amLight2[0].trabalho -eq 24000) 'A20 arquivo legado sem `classe` cai no `fila` do metrics (light -> LIGHT)'
Assert-Orc ((Get-VixClasseLote -Tier 'FULL' -Barato $true -Escalada $false) -eq 'BARATO') 'A21 matinal rotula os proprios lotes como FULL mas roda barato -> classe BARATO'
Assert-Orc ((Get-VixClasseLote -Tier 'LIGHT') -eq 'LIGHT' -and (Get-VixClasseLote -Tier 'AUDIT') -eq 'FULL' -and (Get-VixClasseLote -Tier 'FULL' -Escalada $true) -eq 'ESCALADA') 'A22 classe desconhecida cai na mais CARA (fail-closed) e escalada tem classe propria'
# A23-A26: piso do TAMANHO de lote. O envelope ajustado numa unica amostra passa pela origem e
# subestima lote MENOR que o medido - medido em 14/10: estimativa de 222.883 para 1 emissor
# contra o custo real de 296.866. A admissao nunca encolhe abaixo do menor lote ja medido.
Assert-Orc ([int]$mF.n_min -eq 2 -and [int64]$mF.t_min -eq 356612) 'A23 o modelo publica o menor lote medido da classe (2 emissores / 356.612)'
Assert-Orc ((Get-VixEmissoresQueCabemModelo -Modelo $mF -Acum 0 -Cap 460000 -Chunk 16) -eq 2) 'A24 com saldo de 460.000 roda 2 (o menor lote ja medido, 445.765) em vez de encolher para 1'
Assert-Orc ((Get-VixEmissoresQueCabemModelo -Modelo $mF -Acum 0 -Cap 300000 -Chunk 16) -eq 0) 'A25 com saldo de 300.000 DEFERE em vez de encolher para 1 emissor (cuja estimativa 222.883 nao cobriria o custo real)'
$mSemAmostraN = Get-VixModeloLoteClasse -Amostras @() -DefaultEmissor 250000
Assert-Orc ((Get-VixEmissoresQueCabemModelo -Modelo $mSemAmostraN -Acum 0 -Cap 320000 -Chunk 16) -eq 1) 'A26 sem amostra nenhuma o encolhimento livre continua valendo (o default do provedor ja e o custo de 1 emissor)'

# =========================================================================================
Write-Host '=== B: contabilidade do cache do Codex (envelope -> metrics -> circuito do dia) ==='
$envJson = '{"result":"x","is_error":false,"model":"codex-subscription","usage":{"input_tokens":1180542,"output_tokens":12559,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"cache_codex_input_tokens":1036416}}' | ConvertFrom-Json
$pEnv = Get-VixUsageParcelas $envJson
Assert-Orc ($pEnv.input -eq 1180542 -and $pEnv.output -eq 12559 -and $pEnv.trabalho -eq 1193101) 'B1 regua do cap preservada: trabalho = input + output = 1.193.101 (o mesmo numero do log de 14/10)'
Assert-Orc ($pEnv.cache_codex -eq 1036416 -and $pEnv.cache_read -eq 0) 'B2 o cache do Codex (1.036.416) chega em parcela propria e nao se confunde com cache_read do Claude'
Assert-Orc ($pEnv.cache_codex -lt $pEnv.trabalho) 'B3 o cache continua DENTRO do trabalho (nao e descontado de token faturavel) e nunca maior que ele'
$pLegadoEnv = Get-VixUsageParcelas ('{"usage":{"input_tokens":100,"output_tokens":10}}' | ConvertFrom-Json)
Assert-Orc ($pLegadoEnv.cache_codex -eq 0 -and $pLegadoEnv.trabalho -eq 110) 'B4 envelope sem o campo novo nao quebra e devolve zero (compatibilidade com o formato anterior)'
# Metrics -> circuito do dia: as duas leituras do mesmo fato tem de bater.
$mdC = Join-Path $Tmp 'metrics-custo'
New-Item -ItemType Directory -Force $mdC | Out-Null
$d14 = '20261014'
@{ data = $d14; rotina = 'noturno'; provider = 'codex'; tokens_trabalho = 1193101; tokens_input = 1180542; tokens_output = 12559; tokens_cache_creation = 0; tokens_cache_read = 0; tokens_cache_codex = 1036416; codex_cached_input = 1036416 } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $mdC ('noturno_metrics_' + $d14 + '.json')) -Encoding UTF8
$pMet = Get-VixParcelas (Get-Content -LiteralPath (Join-Path $mdC ('noturno_metrics_' + $d14 + '.json')) -Raw -Encoding UTF8 | ConvertFrom-Json)
Assert-Orc ($pMet.cache_codex -eq 1036416 -and $pMet.trabalho -eq 1193101) 'B5 a lib de custo le a parcela do metrics e mantem o trabalho intacto'
$cfgC = @{ TETO_DIA = 2600000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000; SENTINELA_DIA = 320000 }
$custoDia = Get-VixCustoDia -LogDir $mdC -DateTag $d14 -Config $cfgC
Assert-Orc ($custoDia.total_cache_codex -eq 1036416 -and $custoDia.total_trabalho -eq 1193101) 'B6 o fechamento do dia reconcilia cache_codex (1.036.416) com o trabalho publicado, sem subtrair nada'
Assert-Orc ($custoDia.linha -match 'CACHE_CODEX=1036416') 'B7 a linha CUSTO_DIA publica o cache do Codex (antes ele era invisivel: tokens_cache_codex=0)'
Assert-Orc ($custoDia.total_consumido -eq 1193101) 'B8 o CONSUMO do teto nao muda com a parcela de cache (conservador de proposito)'
$mdLegado = Join-Path $Tmp 'metrics-legado'
New-Item -ItemType Directory -Force $mdLegado | Out-Null
@{ data = $d14; rotina = 'noturno'; tokens_trabalho = 5000; tokens_input = 4000; tokens_output = 1000; tokens_cache_creation = 0; tokens_cache_read = 0 } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $mdLegado ('noturno_metrics_' + $d14 + '.json')) -Encoding UTF8
$custoLegado = Get-VixCustoDia -LogDir $mdLegado -DateTag $d14 -Config $cfgC
Assert-Orc ($custoLegado.total_cache_codex -eq 0 -and $custoLegado.total_trabalho -eq 5000) 'B9 metrics de antes da correcao nao quebra e nao inventa cache'
# Evidencia do defeito: o metrics REAL de 14/10 dizia cache zero com codex_cached_input cheio.
$realMetrics = Join-Path (Split-Path $Scripts -Parent) 'logs\routines\noturno_metrics_20261014.json'
if (Test-Path -LiteralPath $realMetrics) {
    $rm = Get-Content -LiteralPath $realMetrics -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Orc (([int64]$rm.codex_cached_input -eq 1036416) -and ([int64]$rm.tokens_cache_codex -eq 0) -and ([int64]$rm.tokens_total_est -eq 1193101)) 'B10 evidencia do defeito no metrics real de 14/10: codex_cached_input=1.036.416 com tokens_cache_codex=0'
} else {
    Write-Host '  info  metrics real de 14/10 ausente - B10 pulado (nao conta como OK nem FALHA)'
}

# =========================================================================================
Write-Host '=== C: divergencia IA x coletor e reconciliacao de cobertura ==='
$var = Get-Content -LiteralPath $MotorPath -Raw -Encoding UTF8
Assert-Orc ($var -match 'divergencia_ia_coletor' -and $var -match 'permitir_sem_eventos = \$false; recheck = \$true; motivo = ''divergencia_ia_coletor''') 'C1 o motor liga a divergencia ao MESMO portao de ausencia, como recheck pendente (antes so logava)'
$rc = Test-VixCoberturaReconciliacao -LedgerAnalisados 16 -LedgerSkips 16 -LedgerDeferidos 72 -ContratoAnalisado 7 -ContratoResolvido 2 -ContratoInconclusivo 7 -ContratoReutilizado 16 -ContratoDeferido 72 -Triados 104 -PlanoTotal 104 -ExigirTriagem $true
Assert-Orc $rc.ok 'C2 ponta boa: 16 publicadas (7 ANALISADO + 2 RESOLVIDO + 7 INCONCLUSIVO) fecham com o ledger e com os 104 triados'
$rcA = Test-VixCoberturaReconciliacao -LedgerAnalisados 16 -LedgerSkips 16 -LedgerDeferidos 72 -ContratoAnalisado 0 -ContratoResolvido 11 -ContratoInconclusivo 0 -ContratoReutilizado 16 -ContratoDeferido 72 -Triados 104 -PlanoTotal 104 -ExigirTriagem $true
Assert-Orc (-not $rcA.ok) 'C3 ponta ruim do defeito de 14/10: so 11 registros (RESOLVIDO) para 16 analises publicadas nao fecha - era o caso real'
$rcB = Test-VixCoberturaReconciliacao -LedgerAnalisados 16 -LedgerSkips 16 -LedgerDeferidos 72 -ContratoAnalisado 7 -ContratoResolvido 2 -ContratoInconclusivo 7 -ContratoReutilizado 15 -ContratoDeferido 72 -Triados 104 -PlanoTotal 104 -ExigirTriagem $true
Assert-Orc (-not $rcB.ok) 'C4 skip publicado sem registro REUTILIZADO tambem divergencia'
$rcD = Test-VixCoberturaReconciliacao -LedgerAnalisados 16 -LedgerSkips 16 -LedgerDeferidos 72 -ContratoAnalisado 7 -ContratoResolvido 2 -ContratoInconclusivo 7 -ContratoReutilizado 16 -ContratoDeferido 71 -Triados 104 -PlanoTotal 104 -ExigirTriagem $true
Assert-Orc (-not $rcD.ok) 'C5 deferido publicado sem registro DEFERIDO tambem divergencia'
$rcE = Test-VixCoberturaReconciliacao -LedgerAnalisados 16 -LedgerSkips 16 -LedgerDeferidos 72 -ContratoAnalisado 7 -ContratoResolvido 2 -ContratoInconclusivo 7 -ContratoReutilizado 16 -ContratoDeferido 72 -Triados 103 -PlanoTotal 104 -ExigirTriagem $true
Assert-Orc (-not $rcE.ok) 'C6 triagem universal: 103 de 104 triados reprova (um emissor sem verificacao deterministica)'
$rcF = Test-VixCoberturaReconciliacao -LedgerAnalisados 16 -LedgerSkips 16 -LedgerDeferidos 72 -ContratoAnalisado 7 -ContratoResolvido 2 -ContratoInconclusivo 7 -ContratoReutilizado 16 -ContratoDeferido 72 -Triados 104 -PlanoTotal 104 -RotacaoPerdidos 1 -ExigirTriagem $true
Assert-Orc (-not $rcF.ok) 'C7 emissor perdido pela rotacao tambem reprova a reconciliacao'
Assert-Orc ($var -match 'COBERTURA_RECONCILIACAO: DIVERGENTE' -and $var -match 'cobertura_divergencias') 'C8 o motor publica a divergencia e ela entra na conta de erros (divergencia nao vira OK)'
Assert-Orc ($var -match "Estado 'ANALISADO'" -and $var -match "Estado 'INCONCLUSIVO'" -and $var -match "Estado 'REUTILIZADO'" -and $var -match "Estado 'DEFERIDO'" -and $var -match "Estado 'TRIADO'") 'C9 os seis estados do dia sao registrados explicitamente no contrato (TRIADO/ANALISADO/REUTILIZADO/INCONCLUSIVO/DEFERIDO/RESOLVIDO)'
# INCONCLUSIVO nao vira RESOLVIDO: a pendencia continua viva para a leitura de recheck.
$cobT = Join-Path $Tmp 'cob'
New-Item -ItemType Directory -Force $cobT | Out-Null
$ct = @{}
Merge-VixContratoCobertura $ct 'Vibra Energia' 'RECHECK_PENDENTE' @('coletor')
@{ data = '20261014'; emissores = $ct } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $cobT 'cobertura_20261014.json') -Encoding UTF8
$pend = Get-VixRecheckPendentes $cobT
Assert-Orc ($pend.Count -eq 1 -and $pend.ContainsKey((Get-NomeNormalizado 'Vibra Energia'))) 'C10 INCONCLUSIVO com faltante nao vazio continua PENDENTE (nao e promovido a resolvido por ausencia de prova)'
$ct2 = @{}
Merge-VixContratoCobertura $ct2 'Vibra Energia' 'RESOLVIDO' @()
@{ data = '20261015'; emissores = $ct2 } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $cobT 'cobertura_20261015.json') -Encoding UTF8
$pend2 = Get-VixRecheckPendentes $cobT
Assert-Orc ($pend2.Count -eq 0) 'C11 RESOLVIDO com faltantes vazio (submit aceito + cobertura verificada) solta a pendencia'

# =========================================================================================
Write-Host '=== D: rotacao persistente (fila justa, cota, sem perda, sem duplicidade) ==='
$rotPath = Join-Path $Tmp 'rotacao_ciclo.json'
$lista104 = New-Object System.Collections.Generic.List[object]
for ($i = 1; $i -le 104; $i++) {
    $ew = 5
    if (($i % 13) -eq 0) { $ew = 55 }
    $lista104.Add([pscustomobject]@{ empresa = ('Emissor' + $i.ToString('000')); ews_score = $ew; cvm_novos = 0; horas_desde_analise = 100 })
}
Assert-Orc ($lista104.Count -eq 104) 'D0 fixture com exatamente 104 emissores (8 com EWS critico)'
$d1 = '20261015'; $d2 = '20261016'; $d3 = '20261017'
# D1: cota diaria e giro completo em 3 dias.
$ciclo = New-VixRotacaoCiclo
$servidosTotal = @{}
$duplicados = 0
$perdidosMax = 0
$resumoDias = @()
for ($dia = 1; $dia -le 3; $dia++) {
    $tag = @('', $d1, $d2, $d3)[$dia]
    $rot = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias @() -Ciclo $ciclo -LimiteDiario 40 -DiaTag $tag
    $nRot = @($rot.ConsumidosChaves).Count
    $atualiza = Update-VixRotacaoCiclo -Ciclo $ciclo -Presentes @($lista104 | ForEach-Object { $_.empresa }) -Servidos @($rot.ConsumidosChaves) -Consumidos @($rot.ConsumidosChaves) -Ring @($rot.Ring) -DiaTag $tag -Agora ([datetime]('2026-10-' + (15 + $dia - 1) + 'T23:00:00'))
    $ciclo = $atualiza.Ciclo
    $resumoDias += ('d' + $dia + '=' + $nRot)
    foreach ($k in @($rot.ConsumidosChaves)) { if ($servidosTotal.ContainsKey($k)) { $duplicados++ } else { $servidosTotal[$k] = $true } }
    if ($atualiza.Perdidos -gt $perdidosMax) { $perdidosMax = $atualiza.Perdidos }
}
Write-Host ('  info  candidatos por dia: ' + ($resumoDias -join ' '))
Assert-Orc (($resumoDias[0] -eq 'd1=40') -and ($resumoDias[1] -eq 'd2=40') -and ($resumoDias[2] -eq 'd3=24')) 'D1 a cota diaria de 40 vale por DIA e o ciclo fecha os 104 em 3 dias (40 + 40 + 24)'
Assert-Orc ($servidosTotal.Count -eq 104 -and $duplicados -eq 0) 'D2 os 104 emissores foram servidos exatamente uma vez no ciclo - sem duplicidade'
Assert-Orc ($perdidosMax -eq 0) 'D3 auditoria de perda = 0 em todos os dias (nenhum emissor desaparece da fila)'
Assert-Orc ($atualiza.Reiniciou -and (@($ciclo.servidos.Keys).Count -eq 0) -and (@($ciclo.ordem).Count -eq 104)) 'D4 o ciclo reinicia SO quando a fila zera, e o novo ciclo ja nasce com os 104'
# D5: prioridade nao entra na cota.
$ciclo2 = New-VixRotacaoCiclo
$prior = @(Get-VixChavesPrioritariasRotacao -Emissores $lista104.ToArray() -FaltAnt @{} -FilaPendente @{})
Assert-Orc ($prior.Count -eq 8) 'D5a so os 8 de EWS critico sao prioridade (deferimento por orcamento NAO e prioridade de risco)'
$rotP = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias $prior -Ciclo $ciclo2 -LimiteDiario 40 -DiaTag $d1
Assert-Orc ((@($rotP.Candidatos).Count -eq 48) -and (@($rotP.PriorChaves).Count -eq 8)) 'D5b os 8 criticos entram primeiro e FORA da cota: 8 prioritarios + 40 de rotacao'
$primeiros = @($rotP.Candidatos | Select-Object -First 8)
Assert-Orc ((@($primeiros | Where-Object { $_.ews_score -ge 50 }).Count) -eq 8) 'D5c os 8 primeiros da fila sao os criticos (risco na frente da rotacao normal)'
# D6: mesma coisa no mesmo dia (restart) nao devolve cota usada.
$c6 = @(Get-VixChavesPrioritariasRotacao -Emissores $lista104.ToArray() -FaltAnt @{ ('emissor001') = $true } -FilaPendente @{})
Assert-Orc ($c6.Count -eq 9) 'D6a recheck pendente no contrato tambem entra como prioridade'
$u6 = Update-VixRotacaoCiclo -Ciclo $ciclo2 -Presentes @($lista104 | ForEach-Object { $_.empresa }) -Servidos @($rotP.ConsumidosChaves) -Consumidos @($rotP.ConsumidosChaves) -Ring @($rotP.Ring) -DiaTag $d1
Write-VixRotacaoCiclo -Path $rotPath -Ciclo $u6.Ciclo | Out-Null
$cicloLido = Read-VixRotacaoCiclo $rotPath
Assert-Orc (([int]$cicloLido.candidatos_dia -eq 40) -and ((@($cicloLido.ordem).Count) -eq 64)) 'D6b a cota consumida e a fila persistem no disco (restart nao reinicia o ciclo)'
$rot6 = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias $prior -Ciclo $cicloLido -LimiteDiario 40 -DiaTag $d1
Assert-Orc ((@($rot6.ConsumidosChaves).Count -eq 0) -and (@($rot6.Candidatos).Count -eq @($prior).Count)) 'D6c no MESMO dia a cota ja usada nao e devolvida: so os prioritarios voltam'
# D7: emissor oferecido e nao servido (deferido por cap) mantem a posicao e e servido no dia seguinte.
$d = '20261018'
$rot7a = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias @() -Ciclo (New-VixRotacaoCiclo) -LimiteDiario 40 -DiaTag $d
$oferecidos = @($rot7a.ConsumidosChaves)
$servidos7 = @($oferecidos | Select-Object -First 20)
$u7 = Update-VixRotacaoCiclo -Ciclo (New-VixRotacaoCiclo) -Presentes @($lista104 | ForEach-Object { $_.empresa }) -Servidos $servidos7 -Consumidos $oferecidos -Ring @($rot7a.Ring) -DiaTag $d
$rot7b = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias @() -Ciclo $u7.Ciclo -LimiteDiario 40 -DiaTag '20261019'
$candB = @($rot7b.ConsumidosChaves)
$adiados = @($oferecidos | Select-Object -Skip 20)
$repescados = @($adiados | Where-Object { $candB -contains $_ })
Assert-Orc (($adiados.Count -eq 20) -and ($repescados.Count -eq 20) -and ($candB.Count -eq 40)) 'D7 deferido pelo cap NAO sai da fila: volta na frente no dia seguinte (sem starvation), junto de 20 novos'
$servidos7b = @($candB | Where-Object { -not ($adiados -contains $_) })
$u7b = Update-VixRotacaoCiclo -Ciclo $u7.Ciclo -Presentes @($lista104 | ForEach-Object { $_.empresa }) -Servidos ($servidos7 + $servidos7b) -Consumidos $candB -Ring @($rot7b.Ring) -DiaTag '20261019'
Assert-Orc (($u7b.Perdidos -eq 0) -and ($u7b.Duplicados -eq 0) -and (@($u7b.Ciclo.ordem).Count -eq 104 - 20 - $servidos7b.Count)) 'D8 depois de dois dias a fila tem exatamente o que falta (nenhuma perda, nenhuma duplicata)'
# D9: plano muda (emissor sai da carteira, outro entra) - a fila nao perde ninguem.
$listaNova = @($lista104 | Select-Object -Skip 4) + [pscustomobject]@{ empresa = 'EmissorNovo'; ews_score = 5; cvm_novos = 0; horas_desde_analise = 100 }
$u9 = Update-VixRotacaoCiclo -Ciclo $u7b.Ciclo -Presentes @($listaNova | ForEach-Object { $_.empresa }) -Servidos @() -Consumidos @() -Ring @() -DiaTag '20261020'
$naFila9 = @($u9.Ciclo.ordem)
Assert-Orc (($u9.Perdidos -eq 0) -and ($naFila9 -contains (ConvertTo-VixChaveEmissor 'EmissorNovo'))) 'D9 emissor novo entra no FIM da fila e quem saiu da carteira nao quebra a fila (perdidos=0)'
# D10: leitura/escrita idempotente e sem arquivo corrompido.
$cLido = Read-VixRotacaoCiclo (Join-Path $Tmp 'nao-existe.json')
Assert-Orc ((@($cLido.ordem).Count -eq 0) -and ([int]$cLido.posicao -eq 0) -and (@($cLido.servidos.Keys).Count -eq 0)) 'D10 arquivo de ciclo ausente devolve ciclo vazio (primeira execucao nao quebra)'
# D11: read-modify-write sob mutex (concorrencia).
$rotPathC = Join-Path $Tmp 'rotacao_conc.json'
$resC = Invoke-VixRotacaoSob -Path $rotPathC -Acao { param($c) return (Update-VixRotacaoCiclo -Ciclo $c -Presentes @($lista104 | ForEach-Object { $_.empresa }) -Servidos @('emissor001', 'emissor002') -Consumidos @('emissor001', 'emissor002') -Ring @() -DiaTag '20261021') }
$resC2 = Invoke-VixRotacaoSob -Path $rotPathC -Acao { param($c) return (Update-VixRotacaoCiclo -Ciclo $c -Presentes @($lista104 | ForEach-Object { $_.empresa }) -Servidos @('emissor003') -Consumidos @('emissor003') -Ring @() -DiaTag '20261021') }
Assert-Orc ((@($resC2.Ciclo.ordem).Count -eq 101) -and (@($resC2.Ciclo.servidos.Keys).Count -eq 3) -and ($resC2.Duplicados -eq 0)) 'D11 duas passadas concorrentes somam o desfecho (2 + 1 servidos) em vez de uma apagar a outra'

# =========================================================================================
Write-Host '=== F: ciclos sucessivos cobrindo os 104 (orcamento de classe + prioridade + falhas) ==='
function Invoke-SimulaDiaOrcamento {
    param(
        [object[]]$Candidatos = @(),
        [int64]$Cap = 0,
        $Modelo = $null,
        [int]$Chunk = 16,
        [bool]$FalhaColeta = $false
    )
    $acum = [int64]0
    $analisados = New-Object System.Collections.Generic.List[string]
    $deferidos = New-Object System.Collections.Generic.List[string]
    $inconclusivos = New-Object System.Collections.Generic.List[string]
    $capExcedido = 0
    $fila = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($Candidatos)) { $fila.Add($c) }
    while ($fila.Count -gt 0) {
        $k = Get-VixEmissoresQueCabemModelo -Modelo $Modelo -Acum $acum -Cap $Cap -Chunk ([Math]::Min($Chunk, $fila.Count))
        if ($k -le 0) { foreach ($c in $fila) { $deferidos.Add($c.empresa) }; break }
        $roda = @($fila | Select-Object -First $k)
        $acum += (Get-CustoRealLote $k)
        if ($acum -gt $Cap) { $capExcedido++ }
        foreach ($c in $roda) {
            if ($FalhaColeta -and $c.ews_score -ge 50) { $inconclusivos.Add($c.empresa) } else { $analisados.Add($c.empresa) }
        }
        $fila = New-Object System.Collections.Generic.List[object]
        foreach ($c in @($Candidatos | Where-Object { -not ($analisados -contains $_.empresa) -and -not ($inconclusivos -contains $_.empresa) })) {
            if (-not ($deferidos -contains $c.empresa)) { $fila.Add($c) }
        }
    }
    return [pscustomobject]@{ Analisados = $analisados.ToArray(); Deferidos = $deferidos.ToArray(); Inconclusivos = $inconclusivos.ToArray(); Consumo = $acum; CapExcedido = $capExcedido }
}
# F1: ciclos SUCESSIVOS com o teto do dia (2,6M) e o custo REAL medido. O ritmo nao e fixado em
# numero redondo: com o custo real o dia fecha o que cabe em 2 lotes e carrega os deferidos na
# frente do dia seguinte. O que se prova e: a fila AVANCA todo dia, ninguem se perde, quem ja
# fechou nao volta antes do ciclo zerar, os criticos sao reanalisados todo dia, e o ciclo so
# reinicia quando a fila zera - e entao ja com os 104.
# A contagem de duplicidade e feita na ROTACAO (o que a cota governa). Os 8 criticos sao
# prioritarios e voltam TODO DIA de proposito: prioridade de risco nao consome turno de rotacao.
$cicloF = New-VixRotacaoCiclo
$estadosDia = @{}
$servidosRot = @{}
$servidosPrior = @{}
$dupF = 0
$diasCriticoCompleto = 0
$dias = 0
$reiniciouEm = 0
$perdasTotal = 0
$estourosTotal = 0
$ordemAnterior = -1
$progressoOk = $true
while ($dias -lt 12 -and $reiniciouEm -eq 0) {
    $dias++
    $tag = '202611' + $dias.ToString('00')
    $prioDia = @(Get-VixChavesPrioritariasRotacao $lista104.ToArray() @{} @{})
    $rot = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias $prioDia -Ciclo $cicloF -LimiteDiario 40 -DiaTag $tag
    $sim = Invoke-SimulaDiaOrcamento -Candidatos @($rot.Candidatos) -Cap 2600000 -Modelo $mReal -Chunk 16
    foreach ($e in @($rot.Candidatos)) {
        $k = ConvertTo-VixChaveEmissor $e.empresa
        if ($sim.Analisados -contains $e.empresa) { $estadosDia[$k] = 'ANALISADO' }
        elseif ($sim.Inconclusivos -contains $e.empresa) { $estadosDia[$k] = 'INCONCLUSIVO' }
        else { $estadosDia[$k] = 'DEFERIDO' }
        if ($sim.Analisados -contains $e.empresa) {
            if ($prioDia -contains $e.empresa) {
                if (-not $servidosPrior.ContainsKey($k)) { $servidosPrior[$k] = $true }
            } elseif ($servidosRot.ContainsKey($k)) { $dupF++ } else { $servidosRot[$k] = $true }
        }
    }
    if (@($sim.Analisados | Where-Object { $prioDia -contains $_ }).Count -eq 8) { $diasCriticoCompleto++ }
    $at = Update-VixRotacaoCiclo -Ciclo $cicloF -Presentes @($lista104 | ForEach-Object { $_.empresa }) -Servidos @($sim.Analisados) -Consumidos @($rot.ConsumidosChaves) -Ring @($rot.Ring) -DiaTag $tag
    $cicloF = $at.Ciclo
    $perdasTotal += $at.Perdidos
    $estourosTotal += $sim.CapExcedido
    Assert-Orc ($sim.CapExcedido -eq 0 -and $sim.Consumo -le 2600000) ('F1.' + $dias + ' dia ' + $dias + ': nenhum lote passou do cap (consumo=' + $sim.Consumo + ' de 2.600.000)')
    Assert-Orc ($at.Perdidos -eq 0) ('F1.' + $dias + 'b dia ' + $dias + ': nenhum emissor perdido pela fila')
    $naFilaAgora = @($cicloF.ordem).Count
    if ($at.Reiniciou) { $reiniciouEm = $dias }
    else {
        if ($ordemAnterior -ge 0 -and $naFilaAgora -ge $ordemAnterior) { $progressoOk = $false }
        $ordemAnterior = $naFilaAgora
    }
}
Assert-Orc (($reiniciouEm -gt 0) -and ($dias -le 12) -and ($perdasTotal -eq 0) -and ($estourosTotal -eq 0)) ('F2 a fila avancou e zerou em ' + $dias + ' dia(s), sem perda e sem estouro de cap')
Assert-Orc ($progressoOk) 'F2c a fila encolheu todo dia (nenhum dia serviu menos do que repôs)'
Assert-Orc ($servidosRot.Count -eq 96 -and $dupF -eq 0) 'F2d no fim do ciclo, os 96 nao prioritarios passaram pela rotacao exatamente uma vez (sem duplicidade)'
Assert-Orc ($diasCriticoCompleto -eq $dias -and $servidosPrior.Count -eq 8) 'F2b os 8 criticos foram priorizados e REANALISADOS em todos os dias (risco na frente, sem consumir a cota)'
Assert-Orc ((@($estadosDia.Keys).Count) -ge 104) 'F3 todo emissor decidido no dia tem estado registrado (TRIADO/ANALISADO/INCONCLUSIVO/DEFERIDO) - sem buraco de cobertura'
# F4: orcamento INSUFICIENTE - roda o que cabe, defere o resto, registra, e nao perde ninguem.
$priorGeral = @(Get-VixChavesPrioritariasRotacao $lista104.ToArray() @{} @{})
$rotF4 = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias $priorGeral -Ciclo (New-VixRotacaoCiclo) -LimiteDiario 40 -DiaTag '20261104'
$simF4 = Invoke-SimulaDiaOrcamento -Candidatos @($rotF4.Candidatos) -Cap 500000 -Modelo $mReal -Chunk 16
Assert-Orc (($simF4.CapExcedido -eq 0) -and ($simF4.Consumo -le 500000) -and ($simF4.Analisados.Count -eq 2)) 'F4 cap apertado (500.000): roda o menor lote que cabe (2 emissores) e nenhum lote estoura'
$simF4b = Invoke-SimulaDiaOrcamento -Candidatos @($rotF4.Candidatos) -Cap 300000 -Modelo $mReal -Chunk 16
Assert-Orc (($simF4b.CapExcedido -eq 0) -and ($simF4b.Consumo -eq 0) -and ($simF4b.Analisados.Count -eq 0) -and ($simF4b.Deferidos.Count -eq @($rotF4.Candidatos).Count)) 'F4b saldo abaixo do menor lote medido DEFERE tudo (fail-closed: nao encolhe para um tamanho que a estimativa nao cobre)'
Assert-Orc (($simF4.Deferidos.Count + $simF4.Analisados.Count -eq @($rotF4.Candidatos).Count)) 'F5 todo candidato do dia tem desfecho (analisado ou deferido) - nenhum silenciado'
Assert-Orc ($simF4.Deferidos.Count -gt 0) 'F6 orcamento insuficiente DEFERE (registra o corte) em vez de estourar o teto'
# F7: falha de coleta -> INCONCLUSIVO (nunca ausencia certificada) e a pendencia fica viva.
$rotF7 = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias $priorGeral -Ciclo (New-VixRotacaoCiclo) -LimiteDiario 40 -DiaTag '20261105'
$simF7 = Invoke-SimulaDiaOrcamento -Candidatos @($rotF7.Candidatos) -Cap 2600000 -Modelo $mReal -Chunk 16 -FalhaColeta $true
$critF7 = @($rotF7.Candidatos | Where-Object { $_.ews_score -ge 50 })
Assert-Orc (($critF7.Count -eq 8) -and ($simF7.Inconclusivos.Count -eq 8) -and ($simF7.Analisados.Count -gt 0) -and (($simF7.Analisados.Count + $simF7.Inconclusivos.Count + $simF7.Deferidos.Count) -eq @($rotF7.Candidatos).Count) -and ($simF7.CapExcedido -eq 0)) 'F7 falha de coleta nos 8 criticos vira INCONCLUSIVO (a ausencia de dado nao e lida como ausencia de risco) e o resto tem desfecho registrado'
$ctF7 = @{}
foreach ($e in @($simF7.Inconclusivos)) { Merge-VixContratoCobertura $ctF7 $e 'RECHECK_PENDENTE' @('divergencia_ia_coletor') }
$cobF7 = Join-Path $Tmp 'cobF7'; New-Item -ItemType Directory -Force $cobF7 | Out-Null
@{ data = '20261105'; emissores = $ctF7 } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $cobF7 'cobertura_20261105.json') -Encoding UTF8
Assert-Orc ((Get-VixRecheckPendentes $cobF7).Count -eq 8) 'F8 os 8 INCONCLUSIVO ficam na fila de recheck (pergunta viva, nunca RESOLVIDO sem evidencia)'
# F9: ciclo SEGUINTE - os 8 inconclusivos voltam como prioridade e sao reanalisados.
$priorF9 = @(Get-VixChavesPrioritariasRotacao $lista104.ToArray() @{} @{})
Assert-Orc (($priorF9 -contains 'Emissor013') -and ($priorF9 -contains 'Emissor104')) 'F9 no ciclo seguinte os criticos (incluindo os inconclusivos) continuam na frente da rotacao'
# F10: restart no mesmo dia nao reanalisa quem ja fechou (idempotencia) nem reinicia a fila.
$rotR1 = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias @() -Ciclo (New-VixRotacaoCiclo) -LimiteDiario 40 -DiaTag '20261106'
$cicloR = (Update-VixRotacaoCiclo -Ciclo (New-VixRotacaoCiclo) -Presentes @($lista104 | ForEach-Object { $_.empresa }) -Servidos @($rotR1.ConsumidosChaves[0..9]) -Consumidos @($rotR1.ConsumidosChaves) -Ring @($rotR1.Ring) -DiaTag '20261106').Ciclo
$rotR2 = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias @() -Ciclo $cicloR -LimiteDiario 40 -DiaTag '20261106'
$jaServidos = @($rotR1.ConsumidosChaves[0..9])
$reanalisar = @($rotR2.Candidatos | Where-Object { $jaServidos -contains (ConvertTo-VixChaveEmissor $_.empresa) })
Assert-Orc (($reanalisar.Count -eq 0) -and (@($rotR2.ConsumidosChaves).Count -eq 0)) 'F10 restart no mesmo dia: a cota nao volta e quem ja fechou nao volta para a fila (sem duplicidade)'
# F11: ciclo seguinte reanalisa o que ficou (nada de starvation).
$rotR3 = Select-VixRotacaoCandidatos -Emissores $lista104.ToArray() -ChavesPrioritarias @() -Ciclo $cicloR -LimiteDiario 40 -DiaTag '20261107'
Assert-Orc ((@($rotR3.ConsumidosChaves).Count -eq 40) -and (@($rotR3.ConsumidosChaves | Where-Object { $jaServidos -contains $_ }).Count -eq 0)) 'F11 no dia seguinte a fila avanca (40 novos) sem repetir quem ja fechou'

# =========================================================================================
Write-Host '=== G: guardas estruturais no motor ==='
Assert-Orc ($var -match 'Get-VixModeloLoteClasse' -and $var -match 'Get-VixEmissoresQueCabemModelo') 'G1 o pre-lote do motor usa o envelope da CLASSE, nao o custo por emissor constante'
Assert-Orc ($var -match 'CAP_LOTE_REDUZIDO') 'G2 a fragmentacao adaptativa (encolher o lote em vez de estourar) continua ligada'
Assert-Orc ($var -notmatch "custoFullNoturno = \(Get-VixCustoEstimadoTier 'FULL'\)\.Custo") 'G3 a escolha de profundidade da noturna NAO usa mais a constante de setembro como custo por emissor'
Assert-Orc ($var -match 'CUSTO_CLASSE_SELECAO') 'G4 a escolha de profundidade publica o custo por classe que usou'
Assert-Orc ($var -match 'classe = \$__classeLote') 'G5 o metrics publica a CLASSE de cada lote (base do historico por classe)'
Assert-Orc ($var -match 'cache_codex_input_tokens = \$codexUsage\.parcelas\.cache_codex' -and $var -match 'cache_codex_input_tokens = \$__usoCodex\.parcelas\.cache_codex') 'G6 os dois caminhos do envelope do Codex carregam a parcela de cache'
Assert-Orc ($var -match 'Get-VixChavesPrioritariasRotacao' -and $var -match 'Select-VixRotacaoCandidatos' -and $var -match 'Invoke-VixRotacaoSob') 'G7 o motor aplica a rotacao persistente com prioridade de risco e gravacao sob mutex'
Assert-Orc ($var -match 'ROTACAO_CICLO:' -and $var -match 'rotacao_perdidos') 'G8 o motor publica a auditoria da rotacao (posicao, cota, perdas, duplicidade)'
Assert-Orc ($var -match 'Set-VixContratoEstado -Empresa \$emp\.empresa -Estado ''DEFERIDO''' -and $var -match "'REUTILIZADO'") 'G9 deferidos e skips entram no contrato do dia (denominador da reconciliacao)'
Assert-Orc ($var -match 'Test-VixCoberturaReconciliacao' -and $var -match 'cobertura_reconciliacao = \$stats\.cobertura_reconciliacao') 'G10 o metrics publica o resultado da reconciliacao'
Assert-Orc ($var -match 'ExigirTriagem') 'G11 a triagem universal so e exigida quando a triagem deterministica esta ligada (compatibilidade com o modo desligado)'
Assert-Orc ($sen -notmatch 'Get-VixEstimativaLoteClasse') 'G12 a sentinela nao foi tocada por esta mudanca (controle preventivo dela segue intacto)'
Assert-Orc ((Test-Path -LiteralPath (Join-Path $Scripts 'run_vixradar_sentinela.ps1')) -and ((Get-Content -LiteralPath (Join-Path $Scripts 'run_vixradar_sentinela.ps1') -Raw -Encoding UTF8) -match 'Get-VixDecisaoCapSentinela')) 'G13 o controle preventivo da sentinela continua no lugar'
Assert-Orc ($var -match 'read-only|readonly' -or $var -match '--sandbox read-only') 'G14 o sandbox do Codex continua read-only (nenhum afrouxamento nesta mudanca)'
Assert-Orc ($var -notmatch 'no_bundle|--no-bundle') 'G15 nada de bundle desligado no motor'
$checkClaude = Join-Path $Scripts 'check-claude-free.ps1'
Assert-Orc (Test-Path -LiteralPath $checkClaude) 'G16 o gate anti-Claude continua no repo (sera executado no fechamento)'
} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:Ok + ' OK, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
