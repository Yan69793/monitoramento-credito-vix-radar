# test-session-limit-policy.ps1 - prova de duas pontas da politica de limite de sessao
# (SESSIONLIMIT1 / TETOPAREDE1 / ESCALADAFORCADA1, 04/09/2026). Sem rede, sem token, sem
# tocar producao. ASCII puro, PS 5.1.
#
# O incidente que gerou tudo: 03/09/2026 21h38, o retry da noturna morreu com
# "You've hit your session limit - resets 11pm" depois de 3 tentativas em 3 minutos. A chave
# paga estava no registro. Ninguem esperou o reset e ninguem escalou, porque HAVIA DUAS
# regex de falha de auth em arquivos diferentes: a do motor casava 'hit your ... limit', a
# da lib nao, e a lib era quem decidia a escalada. O caso D abaixo e esse cenario exato.
$ErrorActionPreference = 'Continue'
$LibDir = Join-Path $PSScriptRoot 'lib'
. (Join-Path $LibDir 'vixradar-claude-auth.ps1')
. (Join-Path $LibDir 'vixradar-ambient-check.ps1')

$script:okN = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

$agora = Get-Date -Year 2026 -Month 9 -Day 3 -Hour 21 -Minute 38 -Second 0

# ============================================================
Write-Host '=== A: tabela de decisao, ramo a ramo ==='
$a1 = Get-VixSessionLimitAcao -Agora $agora -ResetAt $agora.AddMinutes(82) -EsperaDisponivelMin 150 -JaEsperou $false
Assert ($a1.Acao -eq 'esperar') ('A1: PONTA BOA - reset em 82 min com 150 disponiveis -> esperar (obtido ' + $a1.Acao + ')')
Assert ([Math]::Round($a1.EsperaMin) -eq 84) ('A2: espera = reset + 2 min de folga = 84 (obtido ' + [Math]::Round($a1.EsperaMin) + ')')

$a3 = Get-VixSessionLimitAcao -Agora $agora -ResetAt $agora.AddMinutes(400) -EsperaDisponivelMin 150 -JaEsperou $false
Assert ($a3.Acao -eq 'escalar_reset_longe') ('A3: PONTA RUIM - reset em 400 min nao cabe em 150 -> escalar (obtido ' + $a3.Acao + ')')

$a4 = Get-VixSessionLimitAcao -Agora $agora -ResetAt $null -EsperaDisponivelMin 150 -JaEsperou $false
Assert ($a4.Acao -eq 'escalar_sem_reset') ('A4: reset ilegivel (limite semanal) -> escalar, nunca esperar as cegas (obtido ' + $a4.Acao + ')')

$a5 = Get-VixSessionLimitAcao -Agora $agora -ResetAt $agora.AddMinutes(10) -EsperaDisponivelMin 150 -JaEsperou $true
Assert ($a5.Acao -eq 'escalar_persistiu') ('A5: limite voltou APOS a espera -> escalar mesmo com reset perto (obtido ' + $a5.Acao + ')')

# Fronteira exata: espera == disponivel ainda espera; 1 min a mais escala.
$a6 = Get-VixSessionLimitAcao -Agora $agora -ResetAt $agora.AddMinutes(148) -EsperaDisponivelMin 150 -JaEsperou $false
Assert ($a6.Acao -eq 'esperar') ('A6: fronteira - espera 150 == disponivel 150 -> esperar (obtido ' + $a6.Acao + ')')
$a7 = Get-VixSessionLimitAcao -Agora $agora -ResetAt $agora.AddMinutes(149) -EsperaDisponivelMin 150 -JaEsperou $false
Assert ($a7.Acao -eq 'escalar_reset_longe') ('A7: fronteira - espera 151 > disponivel 150 -> escalar (obtido ' + $a7.Acao + ')')

# Teto de parede zerado (rotina ja gastou o orcamento): nunca espera.
$a8 = Get-VixSessionLimitAcao -Agora $agora -ResetAt $agora.AddMinutes(5) -EsperaDisponivelMin 0 -JaEsperou $false
Assert ($a8.Acao -eq 'escalar_reset_longe') ('A8: sem tempo de parede sobrando, nem reset de 5 min justifica esperar (obtido ' + $a8.Acao + ')')

# ============================================================
Write-Host '=== B: leitura do reset REAL do texto do erro (nunca chumbado) ==='
$txt11pm = "You've hit your session limit - resets 11pm (America/Sao_Paulo)"
$r11 = ConvertTo-VixWsProbeResetAt -Texto $txt11pm -Agora $agora
Assert ($null -ne $r11 -and $r11.ToString('HH:mm') -eq '23:00') ('B1: "resets 11pm" -> 23:00 (obtido ' + $(if ($r11) { $r11.ToString('HH:mm') } else { 'null' }) + ')')
$rSem = ConvertTo-VixWsProbeResetAt -Texto "You've hit your weekly limit - resets Sunday" -Agora $agora
Assert ($null -eq $rSem) 'B2: PONTA RUIM - "resets Sunday" nao tem HH:MM, devolve null (o chamador escala)'

# ============================================================
Write-Host '=== C: classificacao separa limite de assinatura de ferramenta quebrada ==='
$jsonLimite = '{"is_error":true,"api_error_status":429,"result":"' + "You've hit your session limit - resets 11pm (America/Sao_Paulo)" + '"}'
$cLim = Get-VixWsProbeClassificacao -Saida $jsonLimite -StderrTxt '' -Agora $agora
Assert ($cLim.Motivo -eq 'session_limit') ('C1: 429 com "hit your session limit" -> session_limit (obtido ' + $cLim.Motivo + ')')
Assert ($null -ne $cLim.ResetAt -and $cLim.ResetAt.ToString('HH:mm') -eq '23:00') ('C2: ResetAt vem junto da classificacao (obtido ' + $(if ($cLim.ResetAt) { $cLim.ResetAt.ToString('HH:mm') } else { 'null' }) + ')')

# ============================================================
Write-Host '=== D: o incidente real de 03/09 21h38, ponta a ponta ==='
# 21h38, reset as 23h00, retry lancado as 21h30 (8 min decorridos do PT4H).
$decorridoMin = 8
$dispD = 240 - $decorridoMin - 60 - 30   # mesma conta de Get-VixEsperaDisponivelMin
$cD = Get-VixWsProbeClassificacao -Saida $jsonLimite -StderrTxt '' -Agora $agora
$aD = Get-VixSessionLimitAcao -Agora $agora -ResetAt $cD.ResetAt -EsperaDisponivelMin $dispD -JaEsperou $false
Assert ($dispD -eq 142) ('D1: teto de parede as 21h38 deixa 142 min de espera (obtido ' + $dispD + ')')
Assert ($aD.Acao -eq 'esperar') ('D2: a rotina ESPERA ate 23h02 em vez de morrer (obtido ' + $aD.Acao + ')')
Assert ([Math]::Round($aD.EsperaMin) -eq 84) ('D3: espera de 84 min, cabe nos 142 (obtido ' + [Math]::Round($aD.EsperaMin) + ')')
# Prova reversa: a regex da lib NAO classifica isso como falha de credencial, que e
# exatamente por que Invoke-VixClaudeAuthEscalate recusava e ninguem escalava.
Assert (-not (Test-VixClaudeAuthFailure $jsonLimite)) 'D4: prova reversa - Test-VixClaudeAuthFailure NAO casa limite de sessao, por isso a escalada antiga recusava'

# ============================================================
Write-Host '=== E: escalada forcada respeita o estado da credencial ==='
$script:VixAuthModo = 'assinatura-token'
$script:VixAuthChave = $null
Assert ((Invoke-VixClaudeAuthEscalateForcado 'teste sem chave') -eq $false) 'E1: PONTA RUIM - sem chave paga a escalada recusa e nao mente sucesso'
Assert ($script:VixAuthModo -eq 'assinatura-token') ('E2: modo intacto apos recusa (obtido ' + $script:VixAuthModo + ')')

$script:VixAuthModo = 'api'
$script:VixAuthChave = 'sk-ant-teste'
Assert ((Invoke-VixClaudeAuthEscalateForcado 'teste ja na chave') -eq $false) 'E3: ja na chave paga, nao ha para onde escalar'

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
