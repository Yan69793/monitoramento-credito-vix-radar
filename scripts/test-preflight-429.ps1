# test-preflight-429.ps1 - prova de duas pontas da politica de 429 session limit
# (INCIDENTE-FRESHNESS2, A1/A2/G2). Cobre Get-VixWsProbeClassificacao,
# ConvertTo-VixWsProbeResetAt e Invoke-VixWebSearchPreflight. Usa stub claude.cmd
# controlado por variaveis de ambiente (nenhum pedido real, nenhum token gasto).
# ASCII puro, PowerShell 5.1.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')

$script:okN = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

# --- stubs das dependencias externas (isolam o alvo, mesmo padrao de test-wsprobe-diagnostic.ps1) ---
$script:LogLines = New-Object System.Collections.Generic.List[string]
function Write-Log([string]$msg) { $script:LogLines.Add($msg) }

function Set-VixClaudeAuthEnv { }

$script:StubTemKey = $false
$script:ApiKeyChamadas = 0
# O prefixo fica separado do resto de proposito: o gate 3 (segredo) do
# pre-commit reprova qualquer literal contiguo com cara de chave, e ele nao tem
# como distinguir fixture de teste de chave real. Mesmo padrao ja usado em
# test-wsprobe-diagnostic.ps1. Nenhum destes valores e chave de verdade.
$script:PrefixoFake = 'sk-'
function Get-VixAnthropicApiKey {
    $script:ApiKeyChamadas++
    if ($script:StubTemKey) { return ($script:PrefixoFake + 'ant-api03-STUBTESTKEYNAOREAL000000') }
    return $null
}

$script:AlertChamadas = New-Object System.Collections.Generic.List[hashtable]
function Send-VixRoutineAlert {
    param([string]$Rotina, [string]$Motivo, [string]$RoutineKey, [string]$WorkerUrl)
    $script:AlertChamadas.Add(@{ Rotina = $Rotina; Motivo = $Motivo })
    return $true
}

# --- stub do claude.cmd: emite o conteudo de VIX_STUB_OUTFILE (stdout) e VIX_STUB_ERRFILE
#     (stderr, opcional), com exit code VIX_STUB_EXIT. VIX_STUB_MARKER, se setado, faz o
#     stub responder OK (sucesso) a partir da SEGUNDA chamada (simula recuperacao apos
#     o reset). VIX_STUB_CALLLOG acumula uma linha por chamada, para contar invocacoes.
$tmp = Join-Path $env:TEMP ('vixpreflight429_' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$stubPath = Join-Path $tmp 'claude.cmd'
$stub = @'
@echo off
if not "%VIX_STUB_CALLLOG%"=="" echo call >> "%VIX_STUB_CALLLOG%"
if "%VIX_STUB_MARKER%"=="" goto emit
if exist "%VIX_STUB_MARKER%" goto emit_ok
type nul > "%VIX_STUB_MARKER%"
:emit
if not "%VIX_STUB_ERRFILE%"=="" type "%VIX_STUB_ERRFILE%" 1>&2
type "%VIX_STUB_OUTFILE%"
exit /b %VIX_STUB_EXIT%
:emit_ok
echo 12345.67
exit /b 0
'@
Set-Content -LiteralPath $stubPath -Value $stub -Encoding Ascii
$env:PATH = $tmp + ';' + $env:PATH
$cmdClaude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $cmdClaude -or $cmdClaude.Source -notlike ($tmp + '\*')) {
    Write-Host 'FALHA_preamble: stub claude nao esta no topo do PATH; abortando sem tocar o binario real.'
    exit 2
}

function Reset-VixTestState {
    $script:LogLines.Clear()
    $script:AlertChamadas.Clear()
    $script:ApiKeyChamadas = 0
    $script:SlepCalls = New-Object System.Collections.Generic.List[int]
    Remove-Item Env:\VIX_STUB_MARKER -ErrorAction SilentlyContinue
    Remove-Item Env:\VIX_STUB_ERRFILE -ErrorAction SilentlyContinue
    $env:VIX_STUB_CALLLOG = Join-Path $tmp ('calllog_' + [guid]::NewGuid().ToString('N') + '.txt')
    Remove-Item -LiteralPath $env:VIX_STUB_CALLLOG -ErrorAction SilentlyContinue
}
function Get-VixTestCallCount {
    if (Test-Path -LiteralPath $env:VIX_STUB_CALLLOG) { return (Get-Content -LiteralPath $env:VIX_STUB_CALLLOG).Count }
    return 0
}
function Write-VixOutFile([string]$Conteudo) {
    $p = Join-Path $tmp ('out_' + [guid]::NewGuid().ToString('N') + '.json')
    Set-Content -LiteralPath $p -Value $Conteudo -Encoding UTF8
    return $p
}
$sleepRecorder = { param($seg) $script:SlepCalls.Add($seg) }
function Get-VixRelogio([string]$HoraMin) {
    # HoraMin formato 'HH:mm', data fixa para o teste (2026-09-03).
    $partes = $HoraMin.Split(':')
    return Get-Date -Year 2026 -Month 9 -Day 3 -Hour ([int]$partes[0]) -Minute ([int]$partes[1]) -Second 0 -Millisecond 0
}

try {
    # ============================================================
    Write-Host '=== Real0: JSON REAL capturado (wsprobe_err_3956.txt, 02/09/2026 21:30 BRT) ==='
    $jsonReal = '{"duration_api_ms":0,"stop_reason":"stop_sequence","session_id":"e4056ca0-1be3-431a-b16b-55e50f7d75f2","total_cost_usd":0,"usage":{"output_tokens_details":{"thinking_tokens":0},"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{},"permission_denials":[],"terminal_reason":"api_error","fast_mode_state":"off","fast_mode_disabled_reason":"sdk_opt_in_required","subagent_stats":{"spawned":0,"requested":{"background":0,"foreground":0,"unset":0},"started_in_background":0,"max_depth":0,"spawned_by_subagents":0,"completed":0,"failed":0,"killed":{"parent":0,"user":0,"system":0},"refused":{"depth_limit":0,"concurrency_limit":0,"budget":0},"by_type":{}},"is_error":true,"num_turns":1,"subtype":"success","api_error_status":429,"result":"You''ve hit your session limit - resets 10:40pm (America/Sao_Paulo)","type":"result","duration_ms":1679,"uuid":"dfe81e9c-2c3a-4e4e-95bf-c83e9d3860e7","queued_turn_count":0}'
    Reset-VixTestState
    $env:VIX_STUB_OUTFILE = Write-VixOutFile $jsonReal
    $env:VIX_STUB_EXIT = '1'
    $r0 = Test-VixWebSearchProbe
    Assert ($r0 -eq $false) 'Real0: sonda falha (nao vira sucesso)'
    Assert ($script:VixWsProbeMotivo -eq 'session_limit') ('Real0: motivo=session_limit (obtido: ' + $script:VixWsProbeMotivo + ')')
    Assert ($null -ne $script:VixWsProbe429ResetAt -and $script:VixWsProbe429ResetAt.ToString('HH:mm') -eq '22:40') ('Real0: reset parseado as 22:40 (obtido: ' + $script:VixWsProbe429ResetAt + ')')

    # ============================================================
    Write-Host '=== A: 429 reset em 20 min -> espera -> assinatura recupera ==='
    Reset-VixTestState
    $script:StubTemKey = $false
    $env:VIX_STUB_OUTFILE = Write-VixOutFile '{"is_error":true,"api_error_status":429,"result":"You have hit your session limit - resets 10:40pm (America/Sao_Paulo)","type":"result"}'
    $env:VIX_STUB_EXIT = '1'
    $env:VIX_STUB_MARKER = Join-Path $tmp ('marker_A_' + [guid]::NewGuid().ToString('N') + '.txt')
    Remove-Item -LiteralPath $env:VIX_STUB_MARKER -ErrorAction SilentlyContinue
    $relogioA = Get-VixRelogio '22:20'
    $rA = Invoke-VixWebSearchPreflight -Fallback429 ChavePaga -SleepFunc $sleepRecorder -RelogioFunc { $relogioA }.GetNewClosure()
    Assert ($rA.Ok -eq $true) ('A: Ok=true (obtido ' + $rA.Ok + ')')
    Assert ($rA.Motivo -eq 'ok') ('A: Motivo=ok apos espera (obtido ' + $rA.Motivo + ')')
    Assert ($rA.Escalou -eq $false) 'A: nao escalou para chave paga (recuperou pela assinatura)'
    Assert ($rA.EsperouMin -gt 0 -and $rA.EsperouMin -le 30) ('A: esperou ~25 min (obtido ' + $rA.EsperouMin + ')')
    Assert ((Get-VixTestCallCount) -eq 2) ('A: sondou exatamente 2 vezes, 1a falha + 2a recupera (obtido ' + (Get-VixTestCallCount) + ')')
    Assert ($script:ApiKeyChamadas -eq 0) 'A: nunca consultou chave paga (nao precisou)'

    # ============================================================
    Write-Host '=== B: 429 reset alem de 2h -> fallback API (sem esperar) ==='
    Reset-VixTestState
    $script:StubTemKey = $true
    $env:VIX_STUB_OUTFILE = Write-VixOutFile '{"is_error":true,"api_error_status":429,"result":"You have hit your session limit - resets 10:40pm (America/Sao_Paulo)","type":"result"}'
    $env:VIX_STUB_EXIT = '1'
    $relogioB = Get-VixRelogio '19:00'
    $rB = Invoke-VixWebSearchPreflight -Fallback429 ChavePaga -RoutineKey 'chave-teste' -Rotina 'vixradar-noturno' -SleepFunc $sleepRecorder -RelogioFunc { $relogioB }.GetNewClosure()
    Assert ($rB.Ok -eq $true) ('B: Ok=true via fallback (obtido ' + $rB.Ok + ')')
    Assert ($rB.Escalou -eq $true) 'B: escalou para chave paga'
    Assert ($script:SlepCalls.Count -eq 0) 'B: nenhuma espera (reset alem do teto)'
    Assert ((Get-VixTestCallCount) -eq 1) ('B: sondou 1 vez so (obtido ' + (Get-VixTestCallCount) + ')')
    Assert ($script:AlertChamadas.Count -eq 1 -and $script:AlertChamadas[0].Motivo -match 'ALERTA_AUTH') 'B: emitiu ALERTA_AUTH antes de usar chave paga'

    # ============================================================
    Write-Host '=== C: reset dentro de 2h + continua 429 apos reset -> fallback API ==='
    Reset-VixTestState
    $script:StubTemKey = $true
    $env:VIX_STUB_OUTFILE = Write-VixOutFile '{"is_error":true,"api_error_status":429,"result":"You have hit your session limit - resets 10:40pm (America/Sao_Paulo)","type":"result"}'
    $env:VIX_STUB_EXIT = '1'
    # sem VIX_STUB_MARKER: o stub SEMPRE responde 429, simulando persistencia apos o reset.
    $relogioC = Get-VixRelogio '22:20'
    $rC = Invoke-VixWebSearchPreflight -Fallback429 ChavePaga -SleepFunc $sleepRecorder -RelogioFunc { $relogioC }.GetNewClosure()
    Assert ($rC.Ok -eq $true) ('C: Ok=true via fallback apos persistir (obtido ' + $rC.Ok + ')')
    Assert ($rC.Escalou -eq $true) 'C: escalou para chave paga (persistiu apos a espera)'
    Assert ($script:SlepCalls.Count -gt 0) 'C: esperou antes de desistir e escalar'
    Assert ((Get-VixTestCallCount) -eq 2) ('C: sondou 2 vezes, a 2a ainda falhando (obtido ' + (Get-VixTestCallCount) + ')')

    # ============================================================
    Write-Host '=== D: sem chave paga + reset desconhecido (limite semanal) -> abort + alerta, sem espera ==='
    Reset-VixTestState
    $script:StubTemKey = $false
    $env:VIX_STUB_OUTFILE = Write-VixOutFile '{"is_error":true,"api_error_status":429,"result":"You have hit your weekly limit - resets Sunday","type":"result"}'
    $env:VIX_STUB_EXIT = '1'
    $relogioD = Get-VixRelogio '10:00'
    $rD = Invoke-VixWebSearchPreflight -Fallback429 ChavePaga -RoutineKey 'chave-teste' -Rotina 'vixradar-noturno' -SleepFunc $sleepRecorder -RelogioFunc { $relogioD }.GetNewClosure()
    Assert ($rD.Ok -eq $false) 'D: Ok=false (sem contingencia)'
    Assert ($rD.ExitCode -eq 5) ('D: ExitCode=5 (obtido ' + $rD.ExitCode + ')')
    Assert ($rD.Motivo -eq 'session_limit_sem_contingencia') ('D: motivo session_limit_sem_contingencia (obtido ' + $rD.Motivo + ')')
    Assert ($script:SlepCalls.Count -eq 0) 'D: reset desconhecido nao gera espera'
    Assert ($script:AlertChamadas.Count -eq 1) 'D: alerta emitido'
    $todoLog = ($script:LogLines -join "`n")
    Assert (-not ($todoLog -match 'sk-ant')) 'D: nenhum log contem prefixo de chave'

    # ============================================================
    Write-Host '=== E: WebSearch realmente indisponivel -> exit5, NUNCA chave paga ==='
    Reset-VixTestState
    $script:StubTemKey = $true
    $env:VIX_STUB_OUTFILE = Write-VixOutFile 'WebSearch indisponivel no momento (ferramenta fora do ar)'
    $env:VIX_STUB_EXIT = '0'
    $rE = Invoke-VixWebSearchPreflight -Fallback429 ChavePaga -SleepFunc $sleepRecorder -RelogioFunc { Get-VixRelogio '10:00' }
    Assert ($rE.Ok -eq $false) 'E: Ok=false'
    Assert ($rE.Motivo -eq 'websearch_indisponivel') ('E: motivo websearch_indisponivel (obtido ' + $rE.Motivo + ')')
    Assert ($rE.ExitCode -eq 5) 'E: ExitCode=5'
    Assert ($script:ApiKeyChamadas -eq 0) 'E: nunca considerou chave paga para WebSearch indisponivel de verdade'
    Assert ($script:AlertChamadas.Count -eq 0) 'E: nao alertou via Send-VixRoutineAlert (mensagem so no log local)'

    # ============================================================
    Write-Host '=== F: segredo nunca aparece no diagnostico ==='
    Reset-VixTestState
    $env:VIX_STUB_OUTFILE = Write-VixOutFile '{"is_error":true,"result":"unexpected internal failure","type":"result"}'
    $env:VIX_STUB_ERRFILE = Write-VixOutFile ('debug ANTHROPIC_API_KEY=' + $script:PrefixoFake + 'ant-api03-FAKESECRETVALUE123456789 Bearer abcd1234efgh')
    $env:VIX_STUB_EXIT = '1'
    Remove-Item -Path (Join-Path $env:TEMP 'wsprobe_diag_*.log') -Force -ErrorAction SilentlyContinue
    $antesF = @(Get-ChildItem -Path $env:TEMP -Filter 'wsprobe_diag_*.log' -ErrorAction SilentlyContinue | ForEach-Object Name)
    $rF = Test-VixWebSearchProbe
    Assert ($rF -eq $false) 'F: sonda falha (erro desconhecido)'
    Assert ($script:VixWsProbeMotivo -eq 'erro_desconhecido') ('F: motivo erro_desconhecido (obtido ' + $script:VixWsProbeMotivo + ')')
    $diagsF = @(Get-ChildItem -Path $env:TEMP -Filter 'wsprobe_diag_*.log' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin $antesF })
    Assert ($diagsF.Count -ge 1) 'F: diagnostico foi gravado'
    if ($diagsF.Count -ge 1) {
        $conteudoF = Get-Content -LiteralPath $diagsF[0].FullName -Raw -Encoding UTF8
        Assert (-not ($conteudoF -match 'FAKESECRETVALUE123456789')) 'F: chave sk-ant redigida (nao vaza literal)'
        Assert (-not ($conteudoF -match 'Bearer abcd1234')) 'F: Bearer redigido (nao vaza literal)'
        Assert ($conteudoF -match '<REDIGIDO>') 'F: marca de redacao presente'
        Remove-Item -LiteralPath $diagsF[0].FullName -Force -ErrorAction SilentlyContinue
    }

    # ============================================================
    Write-Host '=== G: sucesso normal -> nenhuma espera, nenhum fallback ==='
    Reset-VixTestState
    $env:VIX_STUB_OUTFILE = Write-VixOutFile '12345.67'
    $env:VIX_STUB_EXIT = '0'
    $rG = Invoke-VixWebSearchPreflight -Fallback429 ChavePaga -SleepFunc $sleepRecorder -RelogioFunc { Get-VixRelogio '10:00' }
    Assert ($rG.Ok -eq $true) 'G: Ok=true'
    Assert ($rG.Motivo -eq 'ok') 'G: Motivo=ok'
    Assert ($rG.EsperouMin -eq 0) 'G: EsperouMin=0'
    Assert ($script:SlepCalls.Count -eq 0) 'G: nenhuma chamada de espera'
    Assert ($script:ApiKeyChamadas -eq 0) 'G: nenhuma consulta a chave paga'
    Assert ((Get-VixTestCallCount) -eq 1) ('G: sondou 1 vez so (obtido ' + (Get-VixTestCallCount) + ')')

    # ============================================================
    Write-Host '=== G2a: rollover - reset ja passado hoje vira amanha ==='
    $agoraTarde = Get-VixRelogio '23:50'
    $resetRollover = ConvertTo-VixWsProbeResetAt -Texto 'resets 10:40pm (America/Sao_Paulo)' -Agora $agoraTarde
    Assert ($null -ne $resetRollover -and $resetRollover.Day -eq 4 -and $resetRollover.ToString('HH:mm') -eq '22:40') ('G2a: rollover para dia seguinte 22:40 (obtido ' + $resetRollover + ')')

    Write-Host '=== G2b: exit 0 e exit != 0 com o MESMO corpo 429 -> mesma classificacao ==='
    Reset-VixTestState
    $env:VIX_STUB_OUTFILE = Write-VixOutFile '{"is_error":true,"api_error_status":429,"result":"You have hit your session limit - resets 10:40pm (America/Sao_Paulo)","type":"result"}'
    $env:VIX_STUB_EXIT = '1'
    $rExit1 = Test-VixWebSearchProbe
    $motivoExit1 = $script:VixWsProbeMotivo
    Reset-VixTestState
    $env:VIX_STUB_OUTFILE = Write-VixOutFile '{"is_error":true,"api_error_status":429,"result":"You have hit your session limit - resets 10:40pm (America/Sao_Paulo)","type":"result"}'
    $env:VIX_STUB_EXIT = '0'
    $rExit0 = Test-VixWebSearchProbe
    $motivoExit0 = $script:VixWsProbeMotivo
    Assert ($rExit1 -eq $false -and $rExit0 -eq $false) ('G2b: sonda falha nos dois exit codes (exit1=' + $rExit1 + ' exit0=' + $rExit0 + ')')
    Assert ($motivoExit1 -eq $motivoExit0 -and $motivoExit1 -eq 'session_limit') ('G2b: mesma classificacao independente do exit code (exit1=' + $motivoExit1 + ' exit0=' + $motivoExit0 + ')')

    Write-Host '=== G2c: rate_limit_transitorio (429 sem texto de limite de assinatura) faz 3 re-sondas, sem chave paga ==='
    Reset-VixTestState
    $script:StubTemKey = $true
    $env:VIX_STUB_OUTFILE = Write-VixOutFile '{"is_error":true,"api_error_status":429,"result":"Rate limited by upstream, please retry","type":"result"}'
    $env:VIX_STUB_EXIT = '1'
    $rG2c = Invoke-VixWebSearchPreflight -Fallback429 ChavePaga -SleepFunc $sleepRecorder -RelogioFunc { Get-VixRelogio '10:00' }
    Assert ($rG2c.Ok -eq $false) 'G2c: Ok=false apos 3 re-sondas'
    Assert ($rG2c.Motivo -eq 'rate_limit_transitorio') ('G2c: motivo rate_limit_transitorio (obtido ' + $rG2c.Motivo + ')')
    Assert ((Get-VixTestCallCount) -eq 4) ('G2c: sondou 4 vezes (1 + 3 re-sondas, obtido ' + (Get-VixTestCallCount) + ')')
    Assert ($script:ApiKeyChamadas -eq 0) 'G2c: nunca considerou chave paga (motivo nao e session_limit)'
}
finally {
    Remove-Item Env:\VIX_STUB_OUTFILE, Env:\VIX_STUB_ERRFILE, Env:\VIX_STUB_EXIT, Env:\VIX_STUB_MARKER, Env:\VIX_STUB_CALLLOG -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP 'wsprobe_*.txt') -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP 'wsprobe_diag_*.log') -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:okN + '/' + ($script:okN + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
