# test-capacidade1.ps1 - CAPACIDADE1: decisao de saldo_dia explicavel e coerente com SEM_TETO (F5).
# Replay do dia 21/10/2026 com as parcelas medidas. Offline, sem rotina, sem mutex, sem escrita em log real.
# Saida por exit code (0 = tudo passou).
$ErrorActionPreference = 'Continue'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $aqui 'lib\vixradar-custo.ps1')
. (Join-Path $aqui 'lib\vixradar-cobertura-diaria.ps1')
$falhas = 0
function Confere($nome, $cond) {
    if ($cond) { Write-Output ('OK    ' + $nome) } else { Write-Output ('FALHA ' + $nome); $script:falhas++ }
}

# Aritmetica de 21/10 no fechamento (22:54): a auditoria somou 2.204.668 e esqueceu a Agenda (631.910).
$auditoria = 1208459 + 566947 + 322296 + 106966
$real = $auditoria + 631910
Confere ('auditoria omitiu a Agenda: ' + $auditoria + ' vs real ' + $real + ' (teto 2.600.000)') ($auditoria -lt 2600000 -and $real -gt 2600000)

# Custo do dia de 21/10 com o circuito aberto (margem negativa).
$custo = @{ circuito_aberto = $true; margem = -236578; total_trabalho = $real; total_consumido = $real; teto = 2600000; margem_minima = 100000; mensuravel = $true }
$cfgSem = @{ TETO_DIA = 2600000; RESERVA_VERIFICACAO = 150000; MARGEM_MINIMA = 100000; SEM_TETO = 1 }
$cfgCom = @{ TETO_DIA = 2600000; RESERVA_VERIFICACAO = 150000; MARGEM_MINIMA = 100000; SEM_TETO = 0 }

# Ponta ruim (comportamento de 21/10): sem a regra, circuito aberto zerava o primario mesmo com SEM_TETO.
$antigoDisp = ((-not $false) -and (-not $custo.circuito_aberto))
Confere 'ANTES: regra antiga declarava primario indisponivel com SEM_TETO=1 (a falha)' (-not $antigoDisp)

# Ponta boa: SEM_TETO + claude-subscription => disponivel, orcamento amplo, motivo explicito.
$a = Get-VixCapacidadePrimario $custo $cfgSem 'claude-subscription' $false 150000
Confere 'DEPOIS: SEM_TETO + assinatura => primario disponivel' ($a.PrimarioDisponivel -eq $true -and $a.OrcamentoPrimario -eq 100000000 -and $a.MotivoPrimario -eq 'sem_teto_assinatura')
Confere 'booleanos registrados (circuito aberto visivel, sem_teto)' ($a.CircuitoAberto -eq $true -and $a.SemTeto -eq $true -and $a.DisjuntorAberto -eq $false -and $a.Margem -eq -236578)

# Teto ligado: circuito aberto continua bloqueando, e o motivo nomeia a causa real.
$b = Get-VixCapacidadePrimario $custo $cfgCom 'claude-subscription' $false 150000
Confere 'SEM_TETO=0: circuito aberto bloqueia com motivo correto' ($b.PrimarioDisponivel -eq $false -and $b.OrcamentoPrimario -eq 0 -and $b.MotivoPrimario -eq 'circuito_do_dia_aberto_teto_esgotado')

# Provedor pago nunca ganha SEM_TETO.
$c = Get-VixCapacidadePrimario $custo $cfgSem 'openrouter' $false 150000
Confere 'openrouter mantem o teto mesmo com SEM_TETO=1' ($c.PrimarioDisponivel -eq $false -and $c.SemTeto -eq $false)
$c2 = Get-VixCapacidadePrimario $custo $cfgSem 'codex' $false 150000
Confere 'codex mantem o teto mesmo com SEM_TETO=1' ($c2.PrimarioDisponivel -eq $false -and $c2.SemTeto -eq $false)

# Disjuntor do provider aberto bloqueia sempre, inclusive com SEM_TETO.
$d = Get-VixCapacidadePrimario @{ circuito_aberto = $false; margem = 500000 } $cfgSem 'claude-subscription' $true 150000
Confere 'disjuntor aberto bloqueia mesmo com SEM_TETO' ($d.PrimarioDisponivel -eq $false -and $d.OrcamentoPrimario -eq 0 -and $d.MotivoPrimario -eq 'disjuntor_do_provider_aberto')

# Fluxo completo: o proximo passo do pendente e o motivo propagado.
$pBom = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -PrimarioDisponivel ([bool]$a.PrimarioDisponivel) -OrcamentoPrimario ([int64]$a.OrcamentoPrimario) -CustoBarato 112412 -CustoFull 141917 -MotivoPrimario $a.MotivoPrimario
Confere 'pendente com SEM_TETO vira IA_PRIMARIA (nao fica sem IA)' ($pBom.Passo -eq 'IA_PRIMARIA')
$pRuim = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -PrimarioDisponivel ([bool]$b.PrimarioDisponivel) -OrcamentoPrimario ([int64]$b.OrcamentoPrimario) -CustoBarato 112412 -CustoFull 141917 -MotivoPrimario $b.MotivoPrimario
Confere ('teto esgotado: INSUFICIENCIA com a causa real (' + $pRuim.Motivo + ')') ($pRuim.Passo -eq 'INSUFICIENCIA' -and $pRuim.Motivo -like 'primario_indisponivel_circuito_do_dia_aberto_teto_esgotado*')
$pLeg = Get-VixCobDiariaProximoPasso -Estado 'PENDENTE_IA' -PrimarioDisponivel $false -OrcamentoPrimario 0 -CustoBarato 112412 -CustoFull 141917
Confere 'compat: sem MotivoPrimario o motivo antigo continua primario_indisponivel*' ($pLeg.Motivo -like 'primario_indisponivel*')

# ---------- CAPACIDADE2: SEM_TETO so opera com claude-subscription e nunca libera consumo PAGO ----------
# Provider EFETIVO: desvio de boot para OpenRouter nao herda o claude-subscription da env.
Confere 'efetivo: env claude-subscription sem desvio => claude-subscription' ((Get-VixProviderEfetivo 'claude-subscription' $false $false) -eq 'claude-subscription')
Confere 'efetivo: desvio de boot para OpenRouter => openrouter' ((Get-VixProviderEfetivo 'claude-subscription' $true $false) -eq 'openrouter')
Confere 'efetivo: codex => codex' ((Get-VixProviderEfetivo 'claude-subscription' $false $true) -eq 'codex')
# A falha provada: com a env dizendo claude-subscription e a rotina desviada para OpenRouter, SEM_TETO valia.
Confere 'ANTES: provider da env liberava SEM_TETO em rotina desviada para o OpenRouter (a falha)' (Test-VixSemTeto $cfgSem 'claude-subscription')
$efOr = Get-VixProviderEfetivo 'claude-subscription' $true $false
Confere 'DEPOIS: SEM_TETO NAO vale para rotina desviada para o OpenRouter' (-not (Test-VixSemTeto $cfgSem $efOr))
Confere 'DEPOIS: SEM_TETO NAO vale para codex' (-not (Test-VixSemTeto $cfgSem (Get-VixProviderEfetivo 'codex' $false $true)))
Confere 'SEM_TETO vale so para claude-subscription efetivo' (Test-VixSemTeto $cfgSem (Get-VixProviderEfetivo 'claude-subscription' $false $false))
Confere 'sem nenhum provider valido SEM_TETO nao vale' (-not (Test-VixSemTeto $cfgSem ''))
# A decisao de capacidade da cobertura usa o efetivo: rotina desviada para OpenRouter com circuito aberto fica sem saldo.
$cOr = Get-VixCapacidadePrimario $custo $cfgSem $efOr $false 150000
Confere 'cobertura: rotina desviada para OpenRouter nao ganha SEM_TETO (circuito aberto bloqueia)' ($cOr.PrimarioDisponivel -eq $false -and $cOr.SemTeto -eq $false -and $cOr.OrcamentoPrimario -eq 0)

# Fallback pago por lote: com SEM_TETO o cap some, entao o fallback pago exige o teto normal do dia com margem.
$pagoFechado = Test-VixFallbackPagoPermitido @{ circuito_aberto = $true } $true
Confere 'fallback pago BLOQUEADO com SEM_TETO e teto do dia esgotado' ($pagoFechado.Permitido -eq $false -and $pagoFechado.Motivo -like 'sem_teto_nao_libera_consumo_pago*')
$pagoMargem = Test-VixFallbackPagoPermitido @{ circuito_aberto = $false; mensuravel = $true } $true
Confere 'fallback pago liberado com SEM_TETO apenas se o teto normal tem margem E o custo e mensuravel' ($pagoMargem.Permitido -eq $true -and $pagoMargem.Motivo -eq 'teto_do_dia_com_margem')

# C1 (auditoria 22/10): custo do dia NAO mensuravel subestima o gasto e deixa o circuito parecer fechado.
# Tres casos, duas pontas. Ponta ruim = a regra que so olhava circuito_aberto liberaria o pago nos casos 1 e 3.
$regraAntigaLiberaria = (-not [bool]@{ circuito_aberto = $false; mensuravel = $false }.circuito_aberto)
Confere 'C1 ANTES: a regra antiga (so circuito) liberaria o pago com custo nao mensuravel (a falha)' $regraAntigaLiberaria
$c1a = Test-VixFallbackPagoPermitido @{ circuito_aberto = $false; mensuravel = $false } $true
Confere 'C1.1 circuito fechado + mensuravel=false => BLOQUEADO' ($c1a.Permitido -eq $false -and $c1a.Motivo -eq 'sem_teto_nao_libera_consumo_pago_custo_do_dia_nao_mensuravel')
$c1b = Test-VixFallbackPagoPermitido @{ circuito_aberto = $false; mensuravel = $true } $true
Confere 'C1.2 circuito fechado + mensuravel=true => liberado (ponta boa)' ($c1b.Permitido -eq $true)
$c1c = Test-VixFallbackPagoPermitido @{ circuito_aberto = $false } $true
Confere 'C1.3 campo mensuravel ausente => BLOQUEADO (fail-closed)' ($c1c.Permitido -eq $false -and $c1c.Motivo -like '*nao_mensuravel')
# Com o objeto REAL de Get-VixCustoDia sobre um arquivo de metrics ilegivel (pasta temporaria).
$tmpC = Join-Path $env:TEMP ('capacidade1_c1_' + $PID); New-Item -ItemType Directory -Force -Path $tmpC | Out-Null
[System.IO.File]::WriteAllText((Join-Path $tmpC 'matinal_metrics_20261022.json'), '{{{ ilegivel', (New-Object System.Text.UTF8Encoding($false)))
$custoReal = Get-VixCustoDia $tmpC '20261022' $cfgSem
Confere ('C1.4 dado real: metrics ilegivel => mensuravel=false e circuito fechado (mensuravel=' + $custoReal.mensuravel + ' circuito=' + $custoReal.circuito_aberto + ')') (-not $custoReal.mensuravel -and -not $custoReal.circuito_aberto)
Confere 'C1.5 dado real: o guard bloqueia o pago nesse dia' ((Test-VixFallbackPagoPermitido $custoReal $true).Permitido -eq $false)
$tmpOk = Join-Path $env:TEMP ('capacidade1_c1ok_' + $PID); New-Item -ItemType Directory -Force -Path $tmpOk | Out-Null
$custoOk = Get-VixCustoDia $tmpOk '20261022' $cfgSem
Confere 'C1.6 dado real: dia sem gasto e sem arquivo ilegivel => mensuravel e o guard libera' ($custoOk.mensuravel -eq $true -and (Test-VixFallbackPagoPermitido $custoOk $true).Permitido -eq $true)
Remove-Item -LiteralPath $tmpC, $tmpOk -Recurse -Force -ErrorAction SilentlyContinue
$pagoSemInfo = Test-VixFallbackPagoPermitido $null $true
Confere 'fallback pago sem informacao de custo => bloqueado (fail-closed)' ($pagoSemInfo.Permitido -eq $false)
$pagoCapNormal = Test-VixFallbackPagoPermitido @{ circuito_aberto = $true } $false
Confere 'sem SEM_TETO a funcao nao interfere (o cap normal governa)' ($pagoCapNormal.Permitido -eq $true -and $pagoCapNormal.Motivo -eq 'cap_normal_governa')

# Estatico: o motor aplica o provider efetivo e o guard no fallback pago.
$fm = Get-Content -LiteralPath (Join-Path $aqui 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
Confere 'motor: SEM_TETO calculado com o provider efetivo' ($fm.Contains('Test-VixSemTeto -Config $custoCfg -Provider (Get-VixProviderEfetivo (Get-VixLlmProvider) ([bool]$script:VixUsaOpenRouter) ([bool]$script:VixUsaCodex))'))
Confere 'motor: fallback claude->OpenRouter passa pelo guard do teto' ($fm.Contains('Test-VixFallbackPagoPermitido (Get-VixCustoDia $LogDir $DateTag $custoCfg) ([bool]$script:VixSemTeto)') -and $fm.Contains('$__pagoOk.Permitido -and (Get-VixClaudeFallbackOpenRouterHabilitado)'))
Confere 'motor: fallback bloqueado registra FALLBACK_OPENROUTER_BLOQUEADO' ($fm.Contains('FALLBACK_OPENROUTER_BLOQUEADO'))
Confere 'motor: capacidade da cobertura usa o provider efetivo' ($fm.Contains('$__cdProv = ''' + "'" + ' + (Get-VixProviderEfetivo'))

# Estatico: o motor usa a funcao e loga os booleanos.
$f = Get-Content -LiteralPath (Join-Path $aqui 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
Confere 'motor usa Get-VixCapacidadePrimario' ($f.Contains('Get-VixCapacidadePrimario $__cdCusto $custoCfg $__cdProv'))
Confere 'COBDIARIA_CAPACIDADE loga disjuntor, circuito, sem_teto, margem e reserva' ($f.Contains("' disjuntor_aberto='") -and $f.Contains("' circuito_aberto='") -and $f.Contains("' sem_teto='") -and $f.Contains("' margem='") -and $f.Contains("' reserva='"))
Confere 'motor nao usa mais a formula antiga do primario' (-not $f.Contains('PrimarioDisponivel = ((-not $__disjuntor.aberto) -and (-not $__cdCusto.circuito_aberto))'))

Write-Output ('RESULTADO: falhas=' + $falhas)
exit $falhas
