# test-cobertura-fallback-claude.ps1 - COBFALLBACK1 (2026-10-14). Prova offline e sem token do
# EXECUTOR do fallback Claude da cobertura diaria (modo -CoberturaFallbackClaude do motor):
#   A opt-in VIXRADAR_COBERTURA_FALLBACK_CLAUDE (so '1' liga)
#   B saldo CLAUDE_FALLBACK_DIA (teto ausente, gasto, nao mensuravel)
#   C registro de gasto do dia em disco (monotono por execucao, tentados, ilegivel fail-closed)
#   D selecao de alvos a partir do relatorio (so CLAUDE_FALLBACK, ledger, tentados, saldo)
#   E preparo em ordem de custo (INERTE / NADA_A_FAZER / INCIDENTE / EXECUTAR, auth e sonda
#     injetadas e contadas: nada que custe token roda antes de haver alvo que cabe)
#   F contrato relatorio -> executor pelo arquivo real do fechamento (Invoke-VixCobDiariaFechamento)
#   G guardas estruturais no motor (parse, gate no topo, ProviderOverride, sem stub, sem fechamento)
#   H motor de verdade em processo filho: inerte sem a flag; com a flag o gate de provider 'none'
#     continua bloqueando (exit 86) antes de mutex, rede ou token
# Toda guarda nas duas pontas. ASCII puro, PowerShell 5.1. exit 0 = verde, 1 = falha.

$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Cf([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
. (Join-Path $Scripts 'lib\vixradar-cobertura.ps1')
. (Join-Path $Scripts 'lib\vixradar-cobertura-diaria.ps1')

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ('vix-cobfallback-' + $PID)
if (Test-Path -LiteralPath $Tmp) { Remove-Item -LiteralPath $Tmp -Recurse -Force }
New-Item -ItemType Directory -Path $Tmp | Out-Null
$Dia = '20261014'

function New-Dir([string]$Nome) { $d = Join-Path $Tmp $Nome; New-Item -ItemType Directory -Path $d -Force | Out-Null; return $d }
function Set-Teto([string]$Dir, [int64]$Teto) { [IO.File]::WriteAllText((Join-Path $Dir 'custo-config.json'), ('{"CLAUDE_FALLBACK_DIA":' + $Teto + '}'), (New-Object System.Text.UTF8Encoding($false))) }
function New-Passo([string]$Emp, [string]$Passo, [string]$Tier, [int64]$Custo, [string]$Estado = 'PENDENTE_IA') {
    return [ordered]@{ empresa = $Emp; estado = $Estado; motivo = 'NOVIDADE:evidencia_nova'; passo = $Passo; tier = $Tier; custo = $Custo; motivo_passo = 'x' }
}
function Set-Relatorio([string]$Dir, [string]$Data, [object[]]$Passos) {
    $r = [ordered]@{ data = $Data; status = 'INCIDENTE_CRITICO'; proximos_passos = @($Passos) }
    [IO.File]::WriteAllText((Join-Path $Dir ('cobertura_diaria_relatorio_' + $Dia + '.json')), ($r | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
}
# Stubs contados: provam que auth/sonda (que custam token na vida real) nao rodam antes da hora.
$script:NAuth = 0; $script:NSonda = 0
$script:AuthResp = @{ ok = $true; modo = 'assinatura'; motivo = 'modo_assinatura' }
$script:SondaResp = @{ ok = $true; motivo = 'ok' }
$AuthFn = { $script:NAuth++; return $script:AuthResp }
$SondaFn = { $script:NSonda++; return $script:SondaResp }
function Reset-Stubs { $script:NAuth = 0; $script:NSonda = 0; $script:AuthResp = @{ ok = $true; modo = 'assinatura'; motivo = 'modo_assinatura' }; $script:SondaResp = @{ ok = $true; motivo = 'ok' } }
function Invoke-Prep([string]$Dir, [string]$Flag = '1', [bool]$Dry = $false) {
    return (Invoke-VixCobFallbackPreparo -LogDir $Dir -DateTag $Dia -FlagValor $Flag -AuthFn $AuthFn -SondaFn $SondaFn -DryRun $Dry)
}
$IncNome = 'incidente_cobertura_fallback_' + $Dia + '.json'

Write-Host 'A. opt-in'
Assert-Cf (Test-VixCobFallbackFlag '1') 'A1 "1" liga'
Assert-Cf (Test-VixCobFallbackFlag ' 1 ') 'A2 " 1 " liga (trim)'
Assert-Cf (-not (Test-VixCobFallbackFlag '')) 'A3 ausente nao liga'
Assert-Cf (-not (Test-VixCobFallbackFlag '0')) 'A4 "0" nao liga'
Assert-Cf (-not (Test-VixCobFallbackFlag 'true')) 'A5 "true" nao liga (so o literal 1)'
Assert-Cf (-not (Test-VixCobFallbackFlag '11')) 'A6 "11" nao liga'

Write-Host 'B. saldo'
Assert-Cf ((Get-VixCobFallbackSaldo -Teto 0 -Gasto 0) -eq 0) 'B1 teto nao declarado => saldo 0 (fail-closed)'
Assert-Cf ((Get-VixCobFallbackSaldo -Teto 1000 -Gasto 300) -eq 700) 'B2 teto 1000 gasto 300 => 700 (ponta boa)'
Assert-Cf ((Get-VixCobFallbackSaldo -Teto 1000 -Gasto 1500) -eq 0) 'B3 gasto acima do teto => 0, nunca negativo'
Assert-Cf ((Get-VixCobFallbackSaldo -Teto 1000 -Gasto 0 -Mensuravel $false) -eq 0) 'B4 gasto nao mensuravel => 0'

Write-Host 'C. registro de gasto do dia'
$dC = New-Dir 'c'
$gp = Get-VixCobFallbackGastoPath $dC $Dia
$c1 = Set-VixCobFallbackGastoExecucao -Path $gp -DateTag $Dia -Execucao 'e1' -Tokens 100 -Tentados @('Raizen')
Assert-Cf ($c1.Gasto -eq 100 -and $c1.Mensuravel) 'C1 primeira execucao grava 100'
$c2 = Set-VixCobFallbackGastoExecucao -Path $gp -DateTag $Dia -Execucao 'e1' -Tokens 80
Assert-Cf ($c2.Gasto -eq 100) 'C2 mesma execucao com valor menor nao reduz (monotono)'
$c3 = Set-VixCobFallbackGastoExecucao -Path $gp -DateTag $Dia -Execucao 'e1' -Tokens 250
Assert-Cf ($c3.Gasto -eq 250) 'C3 mesma execucao com valor maior substitui, nao soma'
$c4 = Set-VixCobFallbackGastoExecucao -Path $gp -DateTag $Dia -Execucao 'e2' -Tokens 50 -Tentados @('Vale')
Assert-Cf ($c4.Gasto -eq 300) 'C4 duas execucoes somam (250 + 50)'
$gC = Read-VixCobFallbackGasto $gp $Dia
Assert-Cf ($gC.tentados.ContainsKey((ConvertTo-VixChaveEmissor 'Raizen')) -and $gC.tentados.ContainsKey((ConvertTo-VixChaveEmissor 'Vale'))) 'C5 tentados das duas execucoes persistidos'
$c6 = Set-VixCobFallbackGastoExecucao -Path $gp -DateTag $Dia -Execucao 'e2' -Tokens 60 -Mensuravel $false
Assert-Cf (-not $c6.Mensuravel) 'C6 execucao nao mensuravel contamina o resumo'
$c7 = Set-VixCobFallbackGastoExecucao -Path $gp -DateTag $Dia -Execucao 'e2' -Tokens 70 -Mensuravel $true
Assert-Cf (-not $c7.Mensuravel) 'C7 nao mensuravel nao volta a mensuravel na mesma execucao'
$dC2 = New-Dir 'c2'
$gp2 = Get-VixCobFallbackGastoPath $dC2 $Dia
[IO.File]::WriteAllText($gp2, '{ isto nao e json', (New-Object System.Text.UTF8Encoding($false)))
$gI = Read-VixCobFallbackGasto $gp2 $Dia
$rI = Get-VixCobFallbackResumoGasto $gI
Assert-Cf ($gI.ilegivel -and (-not $rI.Mensuravel) -and ((Get-VixCobFallbackSaldo -Teto 1000 -Gasto $rI.Gasto -Mensuravel $rI.Mensuravel) -eq 0)) 'C8 arquivo ilegivel => saldo 0 (nao vira zero gasto)'
$thr = $false
try { $null = Set-VixCobFallbackGastoExecucao -Path $gp2 -DateTag $Dia -Execucao 'e9' -Tokens 1 } catch { $thr = $true }
Assert-Cf ($thr -and ((Get-Content -LiteralPath $gp2 -Raw) -eq '{ isto nao e json')) 'C9 arquivo ilegivel nao e sobrescrito (lanca, chamador fecha o cap)'

Write-Host 'D. selecao de alvos'
$ledD = New-VixCobDiariaLedger $Dia
$ledD.emissores[(ConvertTo-VixChaveEmissor 'Gerdau')] = @{ empresa = 'Gerdau'; estado = 'VERIFICADO_ANALISADO' }
$relD = [pscustomobject]@{ data = $Dia; proximos_passos = @(
    [pscustomobject](New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300),
    [pscustomobject](New-Passo 'Vale' 'CLAUDE_FALLBACK' 'BARATO' 100),
    [pscustomobject](New-Passo 'Rumo' 'IA_PRIMARIA' 'BARATO' 100),
    [pscustomobject](New-Passo 'Gerdau' 'CLAUDE_FALLBACK' 'FULL' 300),
    [pscustomobject](New-Passo 'PRIO' 'CLAUDE_FALLBACK' 'FULL' 300),
    [pscustomobject](New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300),
    [pscustomobject](New-Passo 'Usiminas' 'CLAUDE_FALLBACK' 'FULL' 0),
    [pscustomobject](New-Passo 'Eletrobras' 'INSUFICIENCIA' 'FULL' 300)
) }
$tent = @{}; $tent[(ConvertTo-VixChaveEmissor 'PRIO')] = @{ empresa = 'PRIO' }
$d1 = Select-VixCobFallbackAlvos -Relatorio $relD -Ledger $ledD -DateTag $Dia -Saldo 450 -Tentados $tent
$nomesD1 = @($d1.Alvos | ForEach-Object { $_.empresa })
Assert-Cf (($nomesD1 -join ',') -eq 'Raizen,Vale' -and $d1.SaldoRestante -eq 50) 'D1 saldo 450 => Raizen(FULL 300) + Vale(BARATO 100), na ordem do relatorio, restam 50'
Assert-Cf ($d1.Candidatos -eq 5) 'D2 candidatos = so CLAUDE_FALLBACK sem duplicar (Raizen, Vale, Gerdau, PRIO, Usiminas)'
$motD = @{}; foreach ($f in @($d1.Fora)) { $motD[$f.empresa] = $f.motivo }
Assert-Cf ($motD['Gerdau'] -eq 'ja_verificado') 'D3 quem ja fechou no ledger sai (ja_verificado)'
Assert-Cf ($motD['PRIO'] -eq 'ja_tentado_hoje') 'D4 quem o fallback ja enviou hoje nao repete'
Assert-Cf ($motD['Usiminas'] -eq 'custo_ou_tier_desconhecido_fail_closed') 'D5 custo 0 => fora, fail-closed'
Assert-Cf (-not ($nomesD1 -contains 'Rumo') -and -not ($nomesD1 -contains 'Eletrobras')) 'D6 IA_PRIMARIA e INSUFICIENCIA nao sao alvo do Claude'
$d7 = Select-VixCobFallbackAlvos -Relatorio $relD -Ledger $ledD -DateTag $Dia -Saldo 350 -Tentados $tent
$motD7 = @{}; foreach ($f in @($d7.Fora)) { $motD7[$f.empresa] = $f.motivo }
Assert-Cf ((@($d7.Alvos | ForEach-Object { $_.empresa }) -join ',') -eq 'Raizen' -and $motD7['Vale'] -eq 'saldo_claude_insuficiente') 'D7 saldo 350 => so Raizen; Vale fica por saldo (as duas pontas com D1)'
$d8 = Select-VixCobFallbackAlvos -Relatorio $relD -Ledger $ledD -DateTag $Dia -Saldo 299 -Tentados $tent
Assert-Cf ((@($d8.Alvos | ForEach-Object { $_.empresa }) -join ',') -eq 'Vale' -and $d8.Motivo -eq 'ok') 'D8 saldo 299 => FULL nao cabe, BARATO seguinte ainda cabe (nao para no primeiro)'
$d9 = Select-VixCobFallbackAlvos -Relatorio $relD -Ledger $ledD -DateTag $Dia -Saldo 50 -Tentados $tent
Assert-Cf (@($d9.Alvos).Count -eq 0 -and $d9.Motivo -like 'nada_coube:*saldo_claude_insuficiente*') 'D9 saldo 50 => nada cabe, motivo nomeado'
$d10 = Select-VixCobFallbackAlvos -Relatorio ([pscustomobject]@{ data = '20261013'; proximos_passos = $relD.proximos_passos }) -Ledger $ledD -DateTag $Dia -Saldo 9999
Assert-Cf (@($d10.Alvos).Count -eq 0 -and $d10.Motivo -eq 'relatorio_de_outro_dia_20261013') 'D10 relatorio de ontem nao vale hoje'
$d11 = Select-VixCobFallbackAlvos -Relatorio $null -DateTag $Dia -Saldo 9999
Assert-Cf ($d11.Motivo -eq 'relatorio_ausente') 'D11 sem relatorio, sem alvo'

Write-Host 'E. preparo em ordem de custo'
$dE1 = New-Dir 'e1'; Set-Teto $dE1 1000; Set-Relatorio $dE1 $Dia @((New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300)); Reset-Stubs
$antes = @(Get-ChildItem -LiteralPath $dE1).Count
$e1 = Invoke-Prep $dE1 ''
Assert-Cf ($e1.Acao -eq 'INERTE' -and $e1.Motivo -eq 'flag_desligada' -and $script:NAuth -eq 0 -and $script:NSonda -eq 0 -and @(Get-ChildItem -LiteralPath $dE1).Count -eq $antes) 'E1 sem flag => INERTE, zero auth, zero sonda, zero arquivo escrito'
$e1b = Invoke-Prep $dE1 '0'
Assert-Cf ($e1b.Acao -eq 'INERTE' -and $script:NAuth -eq 0) 'E1b flag "0" => INERTE'
$dE2 = New-Dir 'e2'; Set-Relatorio $dE2 $Dia @((New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300)); Reset-Stubs
$e2 = Invoke-Prep $dE2
Assert-Cf ($e2.Acao -eq 'INERTE' -and $e2.Motivo -eq 'teto_claude_fallback_nao_declarado' -and $script:NAuth -eq 0) 'E2 flag ligada sem CLAUDE_FALLBACK_DIA => INERTE (teto nao se inventa)'
$dE3 = New-Dir 'e3'; Set-Teto $dE3 1000; Reset-Stubs
$e3 = Invoke-Prep $dE3
Assert-Cf ($e3.Acao -eq 'NADA_A_FAZER' -and $e3.Motivo -eq 'relatorio_ausente' -and $script:NAuth -eq 0) 'E3 sem relatorio => NADA_A_FAZER, sem auth'
$dE4 = New-Dir 'e4'; Set-Teto $dE4 1000; Set-Relatorio $dE4 $Dia @((New-Passo 'Rumo' 'IA_PRIMARIA' 'BARATO' 100)); Reset-Stubs
$e4 = Invoke-Prep $dE4
Assert-Cf ($e4.Acao -eq 'NADA_A_FAZER' -and $e4.Motivo -eq 'sem_pendente_claude_fallback' -and $script:NAuth -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $dE4 $IncNome))) 'E4 nenhum CLAUDE_FALLBACK => NADA_A_FAZER, sem incidente'
$dE5 = New-Dir 'e5'; Set-Teto $dE5 1000; Set-Relatorio $dE5 $Dia @((New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300)); Reset-Stubs
$null = Set-VixCobFallbackGastoExecucao -Path (Get-VixCobFallbackGastoPath $dE5 $Dia) -DateTag $Dia -Execucao 'antes' -Tokens 900
$e5 = Invoke-Prep $dE5
$inc5 = $null; if (Test-Path -LiteralPath (Join-Path $dE5 $IncNome)) { $inc5 = Get-Content -LiteralPath (Join-Path $dE5 $IncNome) -Raw | ConvertFrom-Json }
Assert-Cf ($e5.Acao -eq 'INCIDENTE' -and $e5.Motivo -like 'nada_coube:*saldo_claude_insuficiente*' -and $e5.Saldo -eq 100 -and $script:NAuth -eq 0 -and $script:NSonda -eq 0) 'E5 saldo 100 < custo 300 => INCIDENTE antes de qualquer auth/sonda'
Assert-Cf ($null -ne $inc5 -and $inc5.motivo -eq $e5.Motivo -and $inc5.detalhe.saldo -eq 100 -and @($inc5.detalhe.fora).Count -eq 1) 'E6 incidente gravado com motivo, saldo e pendente fora'
$dE7 = New-Dir 'e7'; Set-Teto $dE7 1000; Set-Relatorio $dE7 $Dia @((New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300)); Reset-Stubs
$script:AuthResp = @{ ok = $false; modo = 'api'; motivo = 'modo_api' }
$e7 = Invoke-Prep $dE7
Assert-Cf ($e7.Acao -eq 'INCIDENTE' -and $e7.Motivo -eq 'assinatura_indisponivel_api' -and $script:NAuth -eq 1 -and $script:NSonda -eq 0 -and (Test-Path -LiteralPath (Join-Path $dE7 $IncNome))) 'E7 auth em chave paga (api) => INCIDENTE, sem sonda (ANTHROPIC_API_PAYG)'
Remove-Item -LiteralPath (Join-Path $dE7 $IncNome) -Force; Reset-Stubs
$script:SondaResp = @{ ok = $false; motivo = 'session_limit' }
$e8 = Invoke-Prep $dE7
Assert-Cf ($e8.Acao -eq 'INCIDENTE' -and $e8.Motivo -eq 'claude_no_limite_session_limit' -and $script:NSonda -eq 1 -and (Test-Path -LiteralPath (Join-Path $dE7 $IncNome))) 'E8 sonda com limite de sessao => INCIDENTE claude_no_limite'
Reset-Stubs; $script:SondaResp = @{ ok = $false; motivo = 'rate_limit_transitorio' }
$e9 = Invoke-Prep $dE7
Assert-Cf ($e9.Motivo -eq 'claude_no_limite_rate_limit_transitorio') 'E9 sonda com 429 => INCIDENTE claude_no_limite'
Reset-Stubs; $script:SondaResp = @{ ok = $false; motivo = 'erro_desconhecido' }
$e10 = Invoke-Prep $dE7
Assert-Cf ($e10.Acao -eq 'INCIDENTE' -and $e10.Motivo -eq 'sonda_falhou_erro_desconhecido') 'E10 sonda com falha generica => INCIDENTE com o motivo da sonda'
$dE11 = New-Dir 'e11'; Set-Teto $dE11 1000; Set-Relatorio $dE11 $Dia @((New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300), (New-Passo 'Vale' 'CLAUDE_FALLBACK' 'BARATO' 100)); Reset-Stubs
$e11 = Invoke-Prep $dE11
Assert-Cf ($e11.Acao -eq 'EXECUTAR' -and @($e11.Alvos).Count -eq 2 -and $e11.Saldo -eq 1000 -and $script:NAuth -eq 1 -and $script:NSonda -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $dE11 $IncNome))) 'E11 tudo pronto => EXECUTAR com 2 alvos e SEM incidente (ponta boa do E5-E10)'
$dE12 = New-Dir 'e12'; Set-Teto $dE12 1000; Set-Relatorio $dE12 $Dia @((New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300)); Reset-Stubs
$e12 = Invoke-Prep $dE12 '1' $true
Assert-Cf ($e12.Acao -eq 'INCIDENTE' -or $e12.Acao -eq 'EXECUTAR') 'E12 dry-run passa pelo mesmo preparo'
$null = Set-VixCobFallbackGastoExecucao -Path (Get-VixCobFallbackGastoPath $dE12 $Dia) -DateTag $Dia -Execucao 'x' -Tokens 950; Reset-Stubs
$e12b = Invoke-Prep $dE12 '1' $true
Assert-Cf ($e12b.Acao -eq 'INCIDENTE' -and (Test-Path -LiteralPath (Join-Path $dE12 ('DRYRUN_' + $IncNome))) -and -not (Test-Path -LiteralPath (Join-Path $dE12 $IncNome))) 'E13 incidente em dry-run sai com prefixo DRYRUN_, nunca no nome real'
$dE14 = New-Dir 'e14'; Set-Teto $dE14 1000; Set-Relatorio $dE14 $Dia @((New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300)); Reset-Stubs
$null = Register-VixCobDiaria -Path (Get-VixCobDiariaPath $dE14 $Dia) -DateTag $Dia -Empresa 'Raizen' -Estado 'VERIFICADO_SEM_NOVIDADE' -Fontes @(
    [pscustomobject]@{ familia = 'emissor'; timestamp = '2026-10-14T14:00:00Z'; status_http = 200; classificacao = 'ok' },
    [pscustomobject]@{ familia = 'divida'; timestamp = '2026-10-14T14:00:00Z'; status_http = 200; classificacao = 'ok' },
    [pscustomobject]@{ familia = 'fato'; timestamp = '2026-10-14T14:00:00Z'; status_http = 200; classificacao = 'ok' }) -Agora ([datetime]::SpecifyKind([datetime]'2026-10-14T15:00:00', [DateTimeKind]::Utc))
$e14 = Invoke-Prep $dE14
Assert-Cf ($e14.Acao -eq 'NADA_A_FAZER' -and $e14.Motivo -eq 'todos_ja_verificados' -and $script:NAuth -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $dE14 $IncNome))) 'E14 alvo ja fechou no ledger depois do relatorio => NADA_A_FAZER, sem incidente'
$dE15 = New-Dir 'e15'; Set-Teto $dE15 1000; Set-Relatorio $dE15 $Dia @((New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300)); Reset-Stubs
$null = Set-VixCobFallbackGastoExecucao -Path (Get-VixCobFallbackGastoPath $dE15 $Dia) -DateTag $Dia -Execucao 'x' -Tokens 10 -Mensuravel $false
$e15 = Invoke-Prep $dE15
Assert-Cf ($e15.Acao -eq 'INCIDENTE' -and $e15.Saldo -eq 0 -and $e15.Motivo -like '*:gasto_nao_mensuravel') 'E15 gasto do dia nao mensuravel => saldo 0 e INCIDENTE nomeando a causa'
$dE16 = New-Dir 'e16'; Set-Teto $dE16 1000; Set-Relatorio $dE16 $Dia @((New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300)); Reset-Stubs
$null = Set-VixCobFallbackGastoExecucao -Path (Get-VixCobFallbackGastoPath $dE16 $Dia) -DateTag $Dia -Execucao 'x' -Tokens 300 -Tentados @('Raizen')
$e16 = Invoke-Prep $dE16
Assert-Cf ($e16.Acao -eq 'INCIDENTE' -and $e16.Motivo -eq 'nada_coube:ja_tentado_hoje' -and $script:NAuth -eq 0) 'E16 alvo ja tentado hoje e ainda aberto => nao repete chamada, vira incidente'

Write-Host 'F. contrato relatorio -> executor (arquivo real do fechamento)'
foreach ($caso in @(@{ n = 'f1'; cl = $true }, @{ n = 'f2'; cl = $false })) {
    $dF = New-Dir $caso.n; Set-Teto $dF 500000; Reset-Stubs
    $lp = Get-VixCobDiariaPath $dF $Dia
    $null = Set-VixCobDiariaUniverso -Path $lp -DateTag $Dia -Nomes @('Raizen') -Total 1 -Fonte 'teste'
    $null = Register-VixCobDiaria -Path $lp -DateTag $Dia -Empresa 'Raizen' -Estado 'PENDENTE_IA' -Motivo 'NOVIDADE:evidencia_nova' -Rotina 'noturno'
    $cap = @{ PrimarioDisponivel = $false; OrcamentoPrimario = [int64]0; CustoBarato = [int64]20000; CustoFull = [int64]180000; ClaudeHabilitado = [bool]$caso.cl; ClaudeLimiteAtingido = $false; OrcamentoClaude = [int64]500000 }
    $null = Invoke-VixCobDiariaFechamento -LogDir $dF -DateTag $Dia -Rotina 'teste' -Capacidade $cap
    $eF = Invoke-Prep $dF
    if ($caso.cl) {
        Assert-Cf ($eF.Acao -eq 'EXECUTAR' -and @($eF.Alvos).Count -eq 1 -and $eF.Alvos[0].empresa -eq 'Raizen' -and $eF.Alvos[0].tier -eq 'BARATO' -and $eF.Alvos[0].custo -eq 20000) 'F1 fechamento com Claude habilitado => relatorio CLAUDE_FALLBACK => executor pega Raizen BARATO 20000'
    } else {
        Assert-Cf ($eF.Acao -eq 'NADA_A_FAZER' -and $eF.Motivo -eq 'sem_pendente_claude_fallback') 'F2 fechamento com Claude desligado => INSUFICIENCIA no relatorio => executor nao chama o Claude'
    }
}

Write-Host 'G. guardas estruturais no motor'
$motorPath = Join-Path $Scripts 'run_vixradar_varredura.ps1'
$tok = $null; $err = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($motorPath, [ref]$tok, [ref]$err)
Assert-Cf (@($err).Count -eq 0) ('G1 motor parseia sem erro (' + @($err).Count + ' erro(s))')
$m = Get-Content -LiteralPath $motorPath -Raw -Encoding UTF8
Assert-Cf ($m -match '\[switch\]\$CoberturaFallbackClaude') 'G2 parametro -CoberturaFallbackClaude existe'
$iGate = $m.IndexOf("if (('' + `$__cfFlag).Trim() -ne '1')")
$iTrans = $m.IndexOf('Start-Transcript -Path')
$iLogDir = $m.IndexOf('New-Item -ItemType Directory -Force -Path $LogDir')
Assert-Cf ($iGate -gt 0 -and $iGate -lt $iTrans -and $iGate -lt $iLogDir) 'G3 gate de inercia antes de transcript e de criar diretorio de log'
Assert-Cf ($m -match "GetEnvironmentVariable\('VIXRADAR_COBERTURA_FALLBACK_CLAUDE', 'Process'\)" -and $script:VixCobFallbackFlagNome -eq 'VIXRADAR_COBERTURA_FALLBACK_CLAUDE') 'G4 motor e lib leem a MESMA variavel'
Assert-Cf ($m -match "\`$script:VixCobFallbackProvider = ''") 'G5 fora do modo o override e vazio (chamada identica a anterior)'
$nOv = ([regex]::Matches($m, 'Invoke-ClaudeBatch \$(promptPath|retryPath) \$job\.Model \$(job\.Chunk\.Count|missing\.Count) \$job\.Tier -ProviderOverride \$script:VixCobFallbackProvider')).Count
$nSem = ([regex]::Matches($m, 'Invoke-ClaudeBatch \$(promptPath|retryPath) \$job\.Model \$(job\.Chunk\.Count|missing\.Count) \$job\.Tier\s*\r?\n')).Count
Assert-Cf ($nOv -eq 2 -and $nSem -eq 0) ('G6 lote e retry passam o ProviderOverride (com=' + $nOv + ' sem=' + $nSem + ')')
$iGateProv = $m.IndexOf('Test-VixLlmProviderPermiteRotina -ForceClaude')
$iOverProc = $m.IndexOf("SetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', 'claude-subscription', 'Process')")
Assert-Cf ($iGateProv -gt 0 -and $iOverProc -gt $iGateProv) 'G7 gate de provider REAL roda antes do override de processo (none continua bloqueando)'
Assert-Cf ($m -match 'if \(-not \$__cfSemSubmit\) \{\s*\r?\n\s*try \{ \$r = Submit-CapDeferred') 'G8 deferido do fallback nao envia stub ao Worker'
Assert-Cf ($m -match 'if \(\$script:VixCobFallbackModo\) \{[\s\S]{0,4000}?\} elseif \(\$script:VixCobDiariaPath\) \{\s*\r?\n\s*try \{\s*\r?\n\s*\$__cdProv') 'G9 fallback nao reescreve o relatorio de fechamento do dia'
$iRest = $m.IndexOf("SetEnvironmentVariable('VIXRADAR_LLM_PROVIDER', `$script:VixCobFallbackProviderOriginal, 'Process')")
$iDreno = $m.IndexOf('Invoke-VixDrenoPosRotina -ScriptPath $verifScript')
Assert-Cf ($iRest -gt 0 -and $iRest -lt $iDreno) 'G10 provider do processo restaurado antes do dreno (filho nao herda o Claude)'
Assert-Cf ($m -match 'if \(\$script:VixCobFallbackModo\) \{\s*\r?\n\s*# COBFALLBACK1: preparo[\s\S]*?\} elseif \(\$script:VixUsaOpenRouter\) \{') 'G11 boot do fallback vem antes (e no lugar) do boot OpenRouter/Codex/Claude normal'
Assert-Cf ($m -match 'Invoke-VixCobFallbackPreparo -LogDir \$LogDir -DateTag \$DateTag -FlagValor \(Get-VixCobFallbackFlagValor\)') 'G12 motor chama o preparo da lib (regra unica)'
Assert-Cf ($m -match 'Update-VixCobFallbackGastoSeguro -Tentados') 'G13 gasto e tentados registrados antes de cada lote'
Assert-Cf ($m -match '\$TokenHardCap = \[int64\]\$script:VixCobFallbackSaldo') 'G14 cap do fallback = saldo CLAUDE_FALLBACK_DIA'
Assert-Cf ($m -match "OrcamentoClaude = \[int64\]\`$__cdOrcCl") 'G15 fechamento decide com o SALDO do Claude, nao com o teto cheio'
Assert-Cf ($m -match "if \(\`$script:VixCobFallbackModo\) \{ \`$skipQueue = @\(\) \}") 'G16 fallback nao reenvia SKIP'

Write-Host 'H. motor em processo filho (sem rede, sem token)'
function Invoke-MotorFilho([string[]]$MotorArgs, [hashtable]$EnvExtra) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $motorPath + '" ' + ($MotorArgs -join ' ')
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    foreach ($k in $EnvExtra.Keys) { $psi.EnvironmentVariables[$k] = $EnvExtra[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd(); $null = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Exit = $p.ExitCode; Out = $out; Pid = $p.Id }
}
$LogReal = Join-Path (Split-Path $Scripts -Parent) 'logs\routines'
$hoje = Get-Date -Format 'yyyyMMdd'
$antesH = @(Get-ChildItem -LiteralPath $LogReal -Filter ('*cobfallback*' + $hoje + '*') -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
$h1 = Invoke-MotorFilho @('-Rotina', 'noturno', '-CoberturaFallbackClaude', '-DryRun') @{ VIXRADAR_COBERTURA_FALLBACK_CLAUDE = '0' }
$depoisH1 = @(Get-ChildItem -LiteralPath $LogReal -Filter ('*cobfallback*' + $hoje + '*') -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
Assert-Cf ($h1.Exit -eq 0 -and $h1.Out -match 'COBFALLBACK_INERTE' -and $depoisH1.Count -eq $antesH.Count) ('H1 sem flag: exit ' + $h1.Exit + ', COBFALLBACK_INERTE, nenhum arquivo cobfallback criado')
$h2 = Invoke-MotorFilho @('-Rotina', 'matinal', '-CoberturaFallbackClaude', '-DryRun') @{ VIXRADAR_COBERTURA_FALLBACK_CLAUDE = '1' }
Assert-Cf ($h2.Exit -eq 1) ('H2 modo sobre a matinal recusado (exit ' + $h2.Exit + ')')
# CIRUNNER1 (2026-10-16): H3/H4 passam do gate do topo e o motor escreve em $ProjectRoot, que e
# caminho fixo de producao (E:\...). No runner do GitHub o drive nao existe, cada Write-Log tenta
# 8 vezes com backoff e a suite estourava os 180s do CI. Pulo nomeado SO quando GITHUB_ACTIONS=true
# e a raiz de producao esta ausente; na maquina local a ausencia continua reprovando.
$emCI = ($env:GITHUB_ACTIONS -eq 'true')
$raizProd = 'E:\Diretorio\Claude\Monitoramento de Credito'
if ($emCI -and -not (Test-Path -LiteralPath $raizProd)) {
    Write-Host '  PULADO H3/H4: raiz de producao fixa do motor ausente no runner de CI (estado de maquina)'
} else {
# Com a flag ligada o gate do topo passa; provider 'none' no processo filho tem de bloquear no gate
# de provider (exit 86), antes de mutex, lock, rede, auth ou token. Arquivos que o filho cria (log
# do dry-run e transcript, com o PID dele no nome) sao removidos em seguida.
$h3 = Invoke-MotorFilho @('-Rotina', 'noturno', '-CoberturaFallbackClaude', '-DryRun') @{ VIXRADAR_COBERTURA_FALLBACK_CLAUDE = '1'; VIXRADAR_LLM_PROVIDER = 'none' }
$criados = @(Get-ChildItem -LiteralPath $LogReal -Filter ('*cobfallback*' + $hoje + '*' + $h3.Pid + '*') -ErrorAction SilentlyContinue)
$logH3 = ''
foreach ($c in $criados) { if ($c.Name -like '*.log') { $logH3 += (Get-Content -LiteralPath $c.FullName -Raw) } }
Assert-Cf ($h3.Exit -eq 86 -and $h3.Out -notmatch 'COBFALLBACK_INERTE') ('H3 com flag: passa o gate do topo e o provider none bloqueia com exit 86 (exit ' + $h3.Exit + ')')
Assert-Cf ($logH3 -notmatch 'COBFALLBACK_PREPARO' -and $logH3 -notmatch 'LOCK_OK') 'H4 bloqueio 86 acontece antes do preparo e do lock'
foreach ($c in $criados) { Remove-Item -LiteralPath $c.FullName -Force -ErrorAction SilentlyContinue }
}

Write-Host 'I. evidencia individual dos 104, DEFERIDO nunca verificado, falha do Claude sem ocultar pendencia'
$AgoraI = [datetime]::SpecifyKind([datetime]'2026-10-14T15:00:00', [DateTimeKind]::Utc)
$fontesI = @(
    [pscustomobject]@{ familia = 'emissor'; timestamp = '2026-10-14T14:00:00Z'; status_http = 200; classificacao = 'ok' },
    [pscustomobject]@{ familia = 'divida'; timestamp = '2026-10-14T14:00:00Z'; status_http = 200; classificacao = 'ok' },
    [pscustomobject]@{ familia = 'fato'; timestamp = '2026-10-14T14:00:00Z'; status_http = 200; classificacao = 'ok' })
$dI = New-Dir 'i'; $lpI = Get-VixCobDiariaPath $dI $Dia
$nomes104 = @(1..104 | ForEach-Object { 'Emissor ' + $_ })
$null = Set-VixCobDiariaUniverso -Path $lpI -DateTag $Dia -Nomes $nomes104 -Total 104 -Fonte 'teste'
foreach ($n in @($nomes104 | Select-Object -First 102)) { $null = Register-VixCobDiaria -Path $lpI -DateTag $Dia -Empresa $n -Estado 'VERIFICADO_SEM_NOVIDADE' -Fontes $fontesI -Agora $AgoraI }
# 103o: DEFERIDO pela noturna (PENDENTE). 104o: analise do Claude SEM fonte nenhuma.
$null = Register-VixCobDiaria -Path $lpI -DateTag $Dia -Empresa 'Emissor 103' -Estado 'PENDENTE' -Motivo 'deferido:cap_efetivo' -Rotina 'noturno'
$rA = Register-VixCobDiaria -Path $lpI -DateTag $Dia -Empresa 'Emissor 104' -Estado 'VERIFICADO_ANALISADO' -Motivo 'analise:NENHUM' -Rotina 'cobfallback' -Fontes @() -Analise ([ordered]@{ submit_ok = $true; classificacao = 'NENHUM' }) -Agora $AgoraI
$resI = Get-VixCobDiariaResumo -Ledger (Read-VixCobDiaria $lpI $Dia) -UniversoMinimo 104
Assert-Cf ((-not $resI.ok) -and $resI.verificados -eq 102 -and @($resI.pendentes).Count -eq 2) 'I1 102 verificados + DEFERIDO + analise sem fonte => 102/104, ok=false (DEFERIDO nao e verificado)'
Assert-Cf ($rA.Estado -eq 'PENDENTE_IA' -and $rA.Prova -eq 'analise_sem_fontes') 'I2 analise do Claude sem fonte individual nao vira terminal (PENDENTE_IA)'
$rB = Register-VixCobDiaria -Path $lpI -DateTag $Dia -Empresa 'Emissor 104' -Estado 'VERIFICADO_ANALISADO' -Motivo 'analise:NENHUM' -Rotina 'cobfallback' -Fontes $fontesI -Analise ([ordered]@{ submit_ok = $false; classificacao = 'NENHUM' }) -Agora $AgoraI
Assert-Cf ($rB.Estado -eq 'PENDENTE_IA' -and $rB.Prova -eq 'submit_nao_aceito') 'I3 analise com fonte mas submit recusado tambem nao fecha'
$null = Register-VixCobDiaria -Path $lpI -DateTag $Dia -Empresa 'Emissor 104' -Estado 'VERIFICADO_ANALISADO' -Motivo 'analise:NENHUM' -Rotina 'cobfallback' -Fontes $fontesI -Analise ([ordered]@{ submit_ok = $true; classificacao = 'NENHUM' }) -Agora $AgoraI
$resI2 = Get-VixCobDiariaResumo -Ledger (Read-VixCobDiaria $lpI $Dia) -UniversoMinimo 104
Assert-Cf ((-not $resI2.ok) -and $resI2.verificados -eq 103 -and @($resI2.pendentes).Count -eq 1 -and $resI2.pendentes[0].empresa -eq 'Emissor 103') 'I4 com evidencia individual 103/104; o DEFERIDO segue pendente e bloqueia o 104/104'
$null = Register-VixCobDiaria -Path $lpI -DateTag $Dia -Empresa 'Emissor 103' -Estado 'VERIFICADO_ANALISADO' -Motivo 'analise:NENHUM' -Rotina 'cobfallback' -Fontes $fontesI -Analise ([ordered]@{ submit_ok = $true; classificacao = 'NENHUM' }) -Agora $AgoraI
$resI3 = Get-VixCobDiariaResumo -Ledger (Read-VixCobDiaria $lpI $Dia) -UniversoMinimo 104
Assert-Cf ($resI3.ok -and $resI3.verificados -eq 104 -and $resI3.universo_total -eq 104) 'I5 ponta boa: os 104 com evidencia individual => ok, 104/104'
$dI6 = New-Dir 'i6'; $lp6 = Get-VixCobDiariaPath $dI6 $Dia
$null = Set-VixCobDiariaUniverso -Path $lp6 -DateTag $Dia -Nomes @(1..104 | ForEach-Object { 'E ' + $_ }) -Total 104 -Fonte 'teste'
foreach ($n in @(1..103 | ForEach-Object { 'E ' + $_ })) { $null = Register-VixCobDiaria -Path $lp6 -DateTag $Dia -Empresa $n -Estado 'VERIFICADO_SEM_NOVIDADE' -Fontes $fontesI -Agora $AgoraI }
$res6 = Get-VixCobDiariaResumo -Ledger (Read-VixCobDiaria $lp6 $Dia) -UniversoMinimo 104
Assert-Cf ((-not $res6.ok) -and @($res6.omitidos).Count -eq 1 -and $res6.omitidos[0] -eq 'E 104') 'I6 emissor sem registro algum e omitido e bloqueia o 104/104'

# Falha do Claude: classe pela regra unica, limite so para cota, pendente PENDENTE_IA, fechamento INSUFICIENCIA.
Assert-Cf ((Get-VixCobFallbackFalhaClasse 'You have hit your session limit, resets 3am') -eq 'cota') 'I7 "hit your limit" => cota'
Assert-Cf ((Get-VixCobFallbackFalhaClasse 'HTTP 429 too many requests') -eq 'cota') 'I8 429 => cota'
Assert-Cf ((Get-VixCobFallbackFalhaClasse 'Not logged in - please run /login') -eq 'auth') 'I9 nao autenticado => auth'
Assert-Cf ((Get-VixCobFallbackFalhaClasse 'connection reset') -eq 'transitoria') 'I10 erro generico => transitoria'
$dI11 = New-Dir 'i11'; $gp11 = Get-VixCobFallbackGastoPath $dI11 $Dia
$null = Set-VixCobFallbackGastoExecucao -Path $gp11 -DateTag $Dia -Execucao 'x' -Tokens 10 -Falha 'cota'
Assert-Cf (Get-VixCobFallbackLimiteAtingido (Read-VixCobFallbackGasto $gp11 $Dia)) 'I11 cota registrada => ClaudeLimiteAtingido verdadeiro'
$null = Set-VixCobFallbackGastoExecucao -Path $gp11 -DateTag $Dia -Execucao 'x' -Tokens 20
Assert-Cf (Get-VixCobFallbackLimiteAtingido (Read-VixCobFallbackGasto $gp11 $Dia)) 'I12 gravar gasto sem informar falha NAO apaga a cota'
$null = Set-VixCobFallbackGastoExecucao -Path $gp11 -DateTag $Dia -Execucao 'x' -Tokens 30 -Falha 'auth'
Assert-Cf (-not (Get-VixCobFallbackLimiteAtingido (Read-VixCobFallbackGasto $gp11 $Dia))) 'I13 auth e falha mas nao e limite (ponta oposta de I11)'
$null = Set-VixCobFallbackGastoExecucao -Path $gp11 -DateTag $Dia -Execucao 'x' -Tokens 40 -Falha 'cota'
$null = Set-VixCobFallbackGastoExecucao -Path $gp11 -DateTag $Dia -Execucao 'x' -Tokens 50 -Falha ''
Assert-Cf (-not (Get-VixCobFallbackLimiteAtingido (Read-VixCobFallbackGasto $gp11 $Dia))) 'I14 lote entregue depois limpa a cota'
$dI15 = New-Dir 'i15'; $lp15 = Get-VixCobDiariaPath $dI15 $Dia; Set-Teto $dI15 500000
$null = Set-VixCobDiariaUniverso -Path $lp15 -DateTag $Dia -Nomes @('Raizen') -Total 1 -Fonte 'teste'
$null = Register-VixCobDiaria -Path $lp15 -DateTag $Dia -Empresa 'Raizen' -Estado 'PENDENTE_IA' -Motivo 'NOVIDADE:evidencia_nova' -Rotina 'noturno'
$mot15 = Get-VixCobFallbackMotivoPendente 'limite_sessao_assinatura' 'cota'
$r15 = Register-VixCobDiaria -Path $lp15 -DateTag $Dia -Empresa 'Raizen' -Estado 'PENDENTE_IA' -Motivo $mot15 -Rotina 'cobfallback'
$cap15 = @{ PrimarioDisponivel = $false; OrcamentoPrimario = [int64]0; CustoBarato = [int64]20000; CustoFull = [int64]180000; ClaudeHabilitado = $true; ClaudeLimiteAtingido = $true; OrcamentoClaude = [int64]500000 }
$f15 = Invoke-VixCobDiariaFechamento -LogDir $dI15 -DateTag $Dia -Fechamento -Rotina 'teste' -Capacidade $cap15
$p15 = @($f15.Relatorio.proximos_passos)[0]
Assert-Cf ($r15.Estado -eq 'PENDENTE_IA' -and $p15.motivo -like 'claude_fallback_falhou:limite_sessao_assinatura:cota') 'I15 falha do Claude deixa PENDENTE_IA com motivo e classe no ledger'
Assert-Cf ($p15.passo -eq 'INSUFICIENCIA' -and $p15.motivo_passo -like '*claude_no_limite*' -and $f15.Status -eq 'INCIDENTE_CRITICO' -and $f15.Exit -eq 20 -and -not $f15.Ok) 'I16 fechamento: INSUFICIENCIA + INCIDENTE_CRITICO exit 20, nunca sucesso'
$cap15b = @{} + $cap15; $cap15b.ClaudeLimiteAtingido = $false
$f15b = Invoke-VixCobDiariaFechamento -LogDir $dI15 -DateTag $Dia -Rotina 'teste' -Capacidade $cap15b
Assert-Cf (@($f15b.Relatorio.proximos_passos)[0].passo -eq 'CLAUDE_FALLBACK') 'I17 ponta oposta: sem limite o mesmo pendente volta a ser CLAUDE_FALLBACK'
$dI18 = New-Dir 'i18'; Set-Teto $dI18 1000; Set-Relatorio $dI18 $Dia @((New-Passo 'Raizen' 'CLAUDE_FALLBACK' 'FULL' 300)); Reset-Stubs
$script:SondaResp = @{ ok = $false; motivo = 'rate_limit_transitorio' }
$e18 = Invoke-Prep $dI18
Assert-Cf ($e18.Acao -eq 'INCIDENTE' -and (Get-VixCobFallbackLimiteAtingido (Read-VixCobFallbackGasto (Get-VixCobFallbackGastoPath $dI18 $Dia) $Dia))) 'I18 429 na sonda vira incidente E estado do dia (fechamento enxerga o limite)'
Assert-Cf ($m -match 'Set-VixCobFallbackFalhaClasse' -and ([regex]::Matches($m, 'Set-VixCobFallbackFalhaClasse \(')).Count -ge 3) 'I19 motor classifica a falha nos 3 pontos (lote recusado, falha de provedor, retry recusado)'
Assert-Cf ($m -match "-Estado 'PENDENTE_IA' -Motivo \(Get-VixCobFallbackMotivoPendente") 'I20 motor registra o nao fechado do fallback como PENDENTE_IA com motivo'
Assert-Cf ($m -match 'ClaudeLimiteAtingido = \[bool\]\(Get-VixCobFallbackLimiteAtingido') 'I21 fechamento alimenta ClaudeLimiteAtingido com o estado real'
Assert-Cf ($m -notmatch "VIXRADAR_COBERTURA_DIARIA', 'Process'\)\s*\r?\n\s*if \(-not \`$__flagCobD\) \{ \`$__flagCobD = '1'") 'I22 modo sombra da cobertura diaria nao e forcado pelo executor'

Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: ' + $script:Ok + ' ok, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
