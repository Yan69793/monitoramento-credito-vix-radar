# test-quota-esgotada-failclosed.ps1 - COTAESGOTADA1 (2026-09-16).
#
# Prova, em PowerShell 5.1 e SEM rede, o comportamento do motor quando a cota da
# assinatura esta CONFIRMADAMENTE esgotada e nao ha chave paga autorizada:
#   (a) limite de sessao/assinatura e classificado como cota confirmada;
#   (b) o desfecho e fail-closed (ALERTA_AUTH, que o vigia converte no codigo 9004);
#   (c) nenhum retry artificial e disparado (uma chamada ao CLI, zero espera);
#   (d) nenhum caminho de fallback pago/PAYG e acionado;
#   (e) o deferimento carrega motivo operacional claro e honesto;
#   (f) o parser segue valido e a saida e ASCII.
#
# Metodo: as funcoes REAIS do motor (scripts/run_vixradar_varredura.ps1) e das libs sao
# extraidas por AST e executadas nesta suite. O unico elemento falsificado e o binario
# `claude` (um claude.cmd que conta invocacoes e devolve o envelope de cota esgotada) e o
# orcamento de parede, que e fixado para o fixture ser deterministico. As sete funcoes de
# decisao puras sao chamadas de verdade, com os valores do incidente.
#
# Nao faz: ler token/chave, tocar o registro do Windows, chamar a rede, invocar claude real,
# escrever em logs de producao. Tudo vive em %TEMP% e e apagado no fim.
#
# Uso:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-quota-esgotada-failclosed.ps1
#   ... -MotorPath <caminho de outra copia do motor>   (prova antes/depois do patch)
# Saida: linhas 'OK'/'FALHA' por assert e uma linha final
#   'RESULTADO: ok=N falha=M'; exit 1 quando M > 0.
param(
    [string]$MotorPath = ''
)

$ErrorActionPreference = 'Continue'

$ScriptsDir = $PSScriptRoot
$Raiz       = Split-Path $ScriptsDir -Parent
if (-not $MotorPath) { $MotorPath = Join-Path $Raiz 'scripts\run_vixradar_varredura.ps1' }
$AuthLib    = Join-Path $Raiz 'scripts\lib\vixradar-claude-auth.ps1'
$AmbLib     = Join-Path $Raiz 'scripts\lib\vixradar-ambient-check.ps1'
$LlmLib     = Join-Path $Raiz 'scripts\lib\vixradar-llm-provider.ps1'
$WatchLib   = Join-Path $Raiz 'scripts\lib\vixradar-watchdog.ps1'

$script:okN = 0
$script:fal = 0
function Assert([bool]$cond, [string]$msg) {
    if ($cond) { $script:okN++; Write-Host ('  OK    ' + $msg) }
    else { $script:fal++; Write-Host ('  FALHA ' + $msg) }
}

# ---------------------------------------------------------------- helpers de AST
function Get-AstDe([string]$Path) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    return [pscustomobject]@{ Ast = $ast; Erros = @($errors) }
}

function Get-ParseErros([string]$Path) {
    return (Get-AstDe $Path).Erros.Count
}

function Get-FuncDefsTexto([string]$Path) {
    $r = Get-AstDe $Path
    if ($r.Erros.Count -gt 0) { throw ('parse de ' + $Path + ' falhou: ' + $r.Erros[0].Message) }
    $defs = $r.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    # Emite uma definicao por objeto (sem aninhar array: @() nao achata e o foreach
    # receberia a lista inteira como se fosse uma unica definicao).
    foreach ($d in $defs) { $d.Extent.Text }
}

function Get-AtribTexto([string]$Path, [string]$Esquerda) {
    $r = Get-AstDe $Path
    $a = $r.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $Esquerda }, $true) | Select-Object -First 1
    if (-not $a) { throw ('atribuicao ' + $Esquerda + ' nao encontrada em ' + $Path) }
    return $a.Extent.Text
}

function Test-AsciiPuro([string]$Path) {
    foreach ($b in [System.IO.File]::ReadAllBytes($Path)) { if ($b -gt 127) { return $false } }
    return $true
}

function Test-TemNaoAscii([string]$Path) {
    return (-not (Test-AsciiPuro $Path))
}

# Regra do repo (scripts/lint-encoding.ps1, Gate 1): arquivo .ps1 com byte nao-ASCII
# PRECISA de BOM UTF-8 no primeiro byte, senao o PowerShell 5.1 le como ANSI e corrompe.
# Nao e "ASCII puro": o motor e a lib de ambiente tem BOM e alguns travessoes em comentario.
function Test-TemBomUtf8([string]$Path) {
    $b = [System.IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 3) { return $false }
    return ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

function Test-LinhaAscii([string]$Texto) {
    foreach ($c in $Texto.ToCharArray()) { if ([int]$c -gt 127) { return $false } }
    return $true
}

# ---------------------------------------------------------------- carrega o codigo REAL
# libs reais (auth/ambient ja dot-sourceiam a lib de provider)
. $AuthLib
. $AmbLib

# TODAS as funcoes do motor, sem executar uma linha do corpo principal. Extrair todas
# (e nao uma lista fixa) mantem a suite de pe se o patch criar funcao nova no caminho.
foreach ($def in @(Get-FuncDefsTexto $MotorPath)) { Invoke-Expression $def }
# So as funcoes de vigia usadas aqui (nao dot-sourcar a lib inteira).
foreach ($def in @(Get-FuncDefsTexto $WatchLib)) {
    if ($def -match '(?m)^\s*function\s+Get-VixAlertasAuth\b') { Invoke-Expression $def }
}

$DryRun = $false
Invoke-Expression (Get-AtribTexto $MotorPath '$script:AuthFailRegex')
Invoke-Expression (Get-AtribTexto $MotorPath '$AlertaAuthTag')

# ---------------------------------------------------------------- stubs declarados
# Substituicoes DELIBERADAS, todas registradas:
#   Write-Log / Write-Safe / Update-VixLock -> capturam em memoria (nada em logs de producao)
#   Set-VixClaudeAuthEnv -> o corpo real APAGA chaves ANTHROPIC_* do registro User e injeta a
#     credencial paga quando existe chave; efeito colateral inaceitavel numa suite. O stub so
#     REGISTRA com que estado de credencial a funcao foi chamada.
#   Start-Sleep -> conta os segundos que o motor pediria (nenhuma espera real na suite)
#   Get-VixEsperaDisponivelMin -> orcamento de parede fixado pelo fixture; -1 usa o real.
$script:LogLinhas   = New-Object System.Collections.ArrayList
$script:AuthLog     = New-Object System.Collections.ArrayList
$script:SleepsSeg   = 0
$script:AuthEnvN    = 0
$script:AuthEnvPaga = 0
$script:LogArquivo  = ''

function Write-Log([string]$msg) {
    $linha = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    [void]$script:LogLinhas.Add($linha)
    if ($script:LogArquivo) { Add-Content -Path $script:LogArquivo -Value $linha -Encoding UTF8 -ErrorAction SilentlyContinue }
}
function Write-Safe([string]$msg) { }
function Update-VixLock { }
function Write-VixAuthLog([string]$msg) { [void]$script:AuthLog.Add([string]$msg) }
function Set-VixClaudeAuthEnv {
    $script:AuthEnvN++
    if ($script:VixAuthChave) { $script:AuthEnvPaga++ }
}
function Start-Sleep {
    param([int]$Seconds = 0, [switch]$Milliseconds)
    if ($Milliseconds) { $script:SleepsSeg += ($Seconds / 1000.0) } else { $script:SleepsSeg += $Seconds }
}
$script:BudgetFixado  = -1.0
$script:BudgetReal    = (Get-Command Get-VixEsperaDisponivelMin -CommandType Function).ScriptBlock
function Get-VixEsperaDisponivelMin {
    if ($script:BudgetFixado -ge 0) { return [double]$script:BudgetFixado }
    return [double](& $script:BudgetReal)
}

# ---------------------------------------------------------------- fixtures em %TEMP%
$FakeDir     = Join-Path $env:TEMP ('vix-cota-fixture-' + $PID)
$LogDirFake  = Join-Path $FakeDir 'logs'
$FakeClaude  = Join-Path $FakeDir 'claude.cmd'
$FakePayload = Join-Path $FakeDir 'payload.json'
$FakeErrPay  = Join-Path $FakeDir 'payload_err.txt'
$FakeCont    = Join-Path $FakeDir 'chamadas.txt'
$PromptFile  = Join-Path $FakeDir 'prompt.txt'
$DateTag     = Get-Date -Format 'yyyyMMdd'
if (Test-Path $FakeDir) { Remove-Item $FakeDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $FakeDir, $LogDirFake | Out-Null
Set-Content -Path $PromptFile -Value 'lote de teste (a suite nao consome este conteudo)' -Encoding ASCII
Set-Content -Path $FakePayload -Value '{"is_error":true}' -Encoding ASCII
Set-Content -Path $FakeErrPay -Value '' -Encoding ASCII

# claude falso: conta a chamada, imprime o envelope de cota e sai com 1 (mesmo contrato do
# CLI real em falha: stdout com o envelope --output-format json e exit != 0). O payload de
# stderr permite o fixture em que a cota so aparece fora do stdout.
$cmd = @(
    '@echo off',
    ('>>"' + $FakeCont + '" echo CHAMADA'),
    ('type "' + $FakePayload + '"'),
    ('type "' + $FakeErrPay + '" 1>&2'),
    'exit /b 1'
) -join "`r`n"
Set-Content -Path $FakeClaude -Value $cmd -Encoding ASCII
$env:PATH = $FakeDir + ';' + $env:PATH

$Perfil        = @{ prefix = 'vixradar-teste-cota' }
$LogDir        = $LogDirFake
$McpConfigFile = Join-Path $FakeDir 'mcp-empty.json'
Set-Content -Path $McpConfigFile -Value '{"mcpServers":{}}' -Encoding ASCII

# Estado de credencial do cenario: token de assinatura presente, chave paga inexistente.
$env:VIXRADAR_LLM_PROVIDER = 'claude-subscription'
$script:VixAuthModo = 'assinatura-token'
$script:VixAuthChave = $null
$script:VixUsaCodex = $false
$script:VixUsaOpenRouter = $false
$script:VixInicioProcesso = (Get-Date)

$chamadasClaude = (Get-Command claude -ErrorAction SilentlyContinue)
$caminhoClaude = ''
if ($chamadasClaude) { $caminhoClaude = '' + $chamadasClaude.Source }
Assert ($caminhoClaude -like ($FakeDir + '*')) ('H1: PATH sombreia o claude real com o fixture (' + $caminhoClaude + ')')

# ============================================================
Write-Host '=== A: cota da assinatura e classificada como CONFIRMADA (nao transiente) ==='
$jsonSessao = '{"is_error":true,"api_error_status":429,"result":"You''ve hit your session limit - resets 11pm (America/Sao_Paulo)"}'
$jsonSemanal = '{"is_error":true,"api_error_status":429,"result":"You''ve hit your weekly limit - resets Sunday"}'
$agora = Get-Date -Year 2026 -Month 9 -Day 16 -Hour 16 -Minute 0 -Second 0

$a1 = Get-VixWsProbeClassificacao -Saida $jsonSessao -StderrTxt '' -Agora $agora
Assert ($a1.Motivo -eq 'session_limit') ('A1: 429 com "hit your session limit" -> session_limit (obtido ' + $a1.Motivo + ')')
Assert ($null -ne $a1.ResetAt -and $a1.ResetAt.ToString('HH:mm') -eq '23:00') 'A2: o reset REAL vem lido do texto (23:00)'

$a2 = Get-VixWsProbeClassificacao -Saida $jsonSemanal -StderrTxt '' -Agora $agora
Assert ($a2.Motivo -eq 'session_limit') ('A3: limite semanal -> session_limit (obtido ' + $a2.Motivo + ')')
Assert ($null -eq $a2.ResetAt) 'A4: limite semanal sem HH:MM -> reset ilegivel (null), nunca chutado'

$a3 = Get-VixWsProbeClassificacao -Saida '{"api_error_status":429}' -StderrTxt '429 too many requests' -Agora $agora
Assert ($a3.Motivo -eq 'rate_limit_transitorio') ('A5: prova reversa - 429 SEM texto de cota nao e cota esgotada (obtido ' + $a3.Motivo + ')')

$a4 = Get-VixFailoverClasse -Status 429 -Corpo $jsonSessao -RespostaOk $false
Assert ($a4 -eq 'quota-exhausted') ('A6: a classe provider-agnostic do mesmo fato e quota-exhausted (obtido ' + $a4 + ')')

Assert (Test-VixClaudeSessionLimit $jsonSessao) 'A7: a lib de auth reconhece o limite de sessao'
Assert (-not (Test-VixClaudeAuthFailure $jsonSessao)) 'A8: prova reversa - limite de cota NAO e credencial invalida (nao se troca credencial por cota)'

$a5 = Get-ClaudeAuthMotivo @(('' + $jsonSessao))
Assert ($a5 -like 'limite de uso da assinatura atingido*') ('A9: o motivo nomeia a causa real (obtido ' + $a5 + ')')

# ============================================================
Write-Host '=== B: reset fora do teto -> fail-closed, nunca retry no mesmo recurso ==='
$b1 = Get-VixSessionLimitAcao -Agora $agora -ResetAt $agora.AddMinutes(1240.7) -EsperaDisponivelMin 148.4 -JaEsperou $false
Assert ($b1.Acao -eq 'escalar_reset_longe') ('B1: reset de 1242.7 min com 148.4 disponiveis -> escalar_reset_longe (obtido ' + $b1.Acao + ')')
Assert ($b1.Motivo -match 'nao cabe no teto de parede') ('B2: motivo explicito do teto de parede (' + $b1.Motivo + ')')

$b2 = Get-VixSessionLimitAcao -Agora $agora -ResetAt $null -EsperaDisponivelMin 148.4 -JaEsperou $false
Assert ($b2.Acao -eq 'escalar_sem_reset') ('B3: reset ilegivel -> escalar_sem_reset (obtido ' + $b2.Acao + ')')

$b3 = Get-VixSessionLimitAcao -Agora $agora -ResetAt $agora.AddMinutes(30) -EsperaDisponivelMin 0 -JaEsperou $false
Assert ($b3.Acao -eq 'escalar_reset_longe') ('B4: teto de parede zerado nunca espera, mesmo com reset perto (obtido ' + $b3.Acao + ')')

$b4 = Get-VixFailoverDecisao -Classe 'quota-exhausted' -TentativasMesmoRecurso 1 -TemFallbackElegivel $false -PaygTetoEstourado $true
Assert ($b4 -eq 'fail-closed') ('B5: quota-exhausted sem fallback e com teto PAYG estourado -> fail-closed (obtido ' + $b4 + ')')
$b5 = Get-VixFailoverDecisao -Classe 'quota-exhausted' -TentativasMesmoRecurso 1 -TemFallbackElegivel $false -PaygTetoEstourado $false
Assert ($b5 -eq 'fail-closed') ('B6: quota-exhausted NUNCA vira retry, mesmo com teto PAYG integro (obtido ' + $b5 + ')')
$b6 = Get-VixFailoverDecisao -Classe 'transient' -TentativasMesmoRecurso 1 -TemFallbackElegivel $false -PaygTetoEstourado $false
Assert ($b6 -eq 'retry') ('B7: prova reversa - transient com teto integro ainda pode retry, a funcao nao e constante (obtido ' + $b6 + ')')

Assert (Test-VixPaygTetoEstourado) 'B8: com VIXRADAR_TETO_PAYG_DIARIO ausente/vazio o teto PAYG esta estourado (fail-closed)'
$b7 = Get-VixBacklogMotivo -TemFallbackElegivel $false -PaygTetoEstourado $true -Classe 'quota-exhausted'
Assert ($b7 -eq 'teto_payg_diario') ('B9: o motivo do backlog e operacional, nao vago (obtido ' + $b7 + ')')

# ============================================================
Write-Host '=== D: nenhum caminho de fallback pago/PAYG esta armado ==='
$d1 = Get-VixAnthropicApiKey
Assert ($null -eq $d1) 'D1: sob claude-subscription a chave paga devolve null (PAYG desarmado)'
$temAviso = $false
foreach ($l in $script:AuthLog) { if ($l -match 'NAO autorizada') { $temAviso = $true } }
Assert $temAviso 'D2: a recusa da chave paga fica registrada, nao silenciosa'

$script:VixAuthModo = 'assinatura-token'
$script:VixAuthChave = $null
$d2 = Invoke-VixClaudeAuthEscalateForcado 'teste de cota esgotada'
Assert ($d2 -eq $false) 'D3: escalada FORCADA sem chave paga recusa e nao mente sucesso'
Assert ($script:VixAuthModo -eq 'assinatura-token') ('D4: modo de auth intacto apos a recusa (obtido ' + $script:VixAuthModo + ')')
$d3 = Invoke-VixClaudeAuthEscalate $jsonSessao
Assert ($d3 -eq $false) 'D5: escalada normal nao troca credencial por limite de cota'

# ============================================================
Write-Host '=== C/B/D ponta a ponta: o lote real com cota esgotada (claude falso) ==='
$parametros = (Get-Command Invoke-ClaudeBatch -CommandType Function).Parameters
$obrigatoriosNovos = @($parametros.Values | Where-Object { $_.IsMandatory -and @('promptPath', 'Model') -notcontains $_.Name })
Assert ($obrigatoriosNovos.Count -eq 0) ('H2: contrato de Invoke-ClaudeBatch preservado (parametros obrigatorios novos: ' + ($obrigatoriosNovos.Name -join ',') + ')')

function Invoke-CenarioCota {
    param([string]$Nome, [string]$Payload, [double]$Budget, [string]$PayloadErr = '')
    [void]$script:LogLinhas.Clear()
    $script:SleepsSeg = 0
    $script:AuthEnvN = 0
    $script:AuthEnvPaga = 0
    Set-Content -Path $FakePayload -Value $Payload -Encoding ASCII
    Set-Content -Path $FakeErrPay -Value $PayloadErr -Encoding ASCII
    Remove-Item $FakeCont -Force -ErrorAction SilentlyContinue
    $script:BudgetFixado = $Budget
    $script:VixAuthModo = 'assinatura-token'
    $script:VixAuthChave = $null
    $script:VixUsaCodex = $false
    $script:VixUsaOpenRouter = $false
    $script:VixInicioProcesso = (Get-Date)
    $script:LogArquivo = Join-Path $LogDirFake ('vixradar-noturno_' + $DateTag + '.log')
    if (Test-Path $script:LogArquivo) { Remove-Item $script:LogArquivo -Force }
    $r = Invoke-ClaudeBatch -promptPath $PromptFile -Model 'claude-haiku-4-5-20251001'
    $n = 0
    if (Test-Path $FakeCont) { $n = @(Get-Content $FakeCont).Count }
    $achados = @(Get-VixAlertasAuth -RotinasLogDir $LogDirFake -Dias @(Get-Date))
    return [pscustomobject]@{
        Nome = $Nome; Resultado = $r; Chamadas = $n; Sleeps = $script:SleepsSeg
        Log = @($script:LogLinhas); AuthEnvN = $script:AuthEnvN; AuthEnvPaga = $script:AuthEnvPaga
        Modo = $script:VixAuthModo; AlertasAuth = $achados.Count
    }
}

if ($obrigatoriosNovos.Count -eq 0) {
    # Fixture 1 - limite SEMANAL (reset ilegivel): orcamento de parede REAL do motor.
    $s1 = Invoke-CenarioCota -Nome 'semanal' -Payload $jsonSemanal -Budget (-1.0)
    Assert ($s1.Chamadas -eq 1) ('C1: cota esgotada -> UMA invocacao do CLI, nao tres (obtido ' + $s1.Chamadas + ')')
    Assert ($s1.Sleeps -eq 0) ('C2: zero espera artificial entre tentativas (obtido ' + $s1.Sleeps + 's)')
    Assert ($s1.Resultado.AuthFailure -eq $true) 'B10: o lote sai marcado como falha de cota (o motor converte em exit 7)'
    Assert ($s1.Resultado.Escalou -eq $false) 'D6: o lote nao reporta escalada paga'
    Assert ($s1.Modo -eq 'assinatura-token') ('D7: terminou ainda na assinatura (obtido ' + $s1.Modo + ')')
    Assert ($s1.AuthEnvPaga -eq 0) 'D8: nenhuma aplicacao de credencial paga (chave ausente em toda invocacao)'
    Assert ($s1.AlertasAuth -eq 1) ('B11: exatamente UMA linha ALERTA_AUTH no log da rotina (o que o vigia conta como 9004); obtido ' + $s1.AlertasAuth)
    $linhaAlerta = ''
    foreach ($l in $s1.Log) { if ($l -match 'ALERTA_AUTH') { $linhaAlerta = $l } }
    Assert ($linhaAlerta -match 'sem chave paga para assumir') ('B12: a linha diz a causa e a ausencia de fallback (' + $linhaAlerta + ')')
    $linhasOk = 0
    foreach ($l in $s1.Log) { if (Test-LinhaAscii $l) { $linhasOk++ } }
    Assert ($linhasOk -eq $s1.Log.Count) ('F4: toda a saida de log do cenario e ASCII (' + $linhasOk + '/' + $s1.Log.Count + ')')
    Write-Host ('  [evidencia] claude chamadas=' + $s1.Chamadas + ' | sleeps=' + $s1.Sleeps + 's | linhas de log do lote:')
    foreach ($l in $s1.Log) { Write-Host ('    ' + $l) }

    # Fixture 2 - limite de SESSAO com reset que nao cabe no teto (orcamento fixado em 0).
    $s2 = Invoke-CenarioCota -Nome 'reset_longe' -Payload $jsonSessao -Budget 0.0
    Assert ($s2.Chamadas -eq 1) ('C3: reset fora do teto -> UMA invocacao do CLI, nao tres (obtido ' + $s2.Chamadas + ')')
    Assert ($s2.Sleeps -eq 0) ('C4: zero espera artificial no ramo "nao cabe no teto" (obtido ' + $s2.Sleeps + 's)')
    $logTxt = ($s2.Log -join "`n")
    Assert ($logTxt -match 'nao cabe no teto de parede') 'B13: o abandono do lote cita o teto de parede'
    Assert ($s2.AlertasAuth -eq 1) ('B14: exatamente UMA linha ALERTA_AUTH (obtido ' + $s2.AlertasAuth + ')')
    Assert ($s2.Resultado.AuthFailure -eq $true) 'B15: fail-closed preservado (AuthFailure)'
    Assert ($s2.AuthEnvPaga -eq 0) 'D9: nenhuma aplicacao de credencial paga no ramo de reset distante'

    # Fixture 3 - a cota so aparece no STDERR (stdout traz so o status). A regex do motor roda
    # no stdout ja parseado; sem fail-closed explicito o lote morreria calado, sem deferimento.
    $s3 = Invoke-CenarioCota -Nome 'stderr' -Payload '{"is_error":true,"api_error_status":429}' -Budget 0.0 -PayloadErr ("You've hit your session limit - resets 11pm (America/Sao_Paulo)")
    Assert ($s3.Chamadas -eq 1) ('C5: cota no stderr -> UMA invocacao do CLI (obtido ' + $s3.Chamadas + ')')
    Assert ($s3.Resultado.AuthFailure -eq $true) 'B16: cota declarada so no stderr ainda vira fail-closed (nao morre calada)'
    Assert ($s3.AlertasAuth -eq 1) ('B17: e o vigia ve exatamente UMA linha ALERTA_AUTH (obtido ' + $s3.AlertasAuth + ')')
}
$script:BudgetFixado = -1.0

# ============================================================
Write-Host '=== E: o deferimento carrega motivo operacional claro e honesto ==='
$e1 = Get-VixDeferidoMotivo $true
Assert ($e1 -eq 'limite_sessao_assinatura') ('E1: aborto por cota da assinatura tem motivo proprio (obtido ' + $e1 + ')')
$e2 = Get-VixDeferidoMotivo $false
Assert ($e2 -eq 'cap_efetivo') ('E2: corte planejado por cap segue com o rotulo historico (obtido ' + $e2 + ')')
$e3 = Get-VixDeferidosTexto -Motivo 'limite_sessao_assinatura' -Ok 0 -Falha 1 -Total 4 -TokensRealizados 47069 -CapEfetivo 700000 -LotesNaoProcessados 3
Assert ($e3 -match 'motivo=limite_sessao_assinatura') ('E3: a linha DEFERIDOS nomeia a causa (obtido ' + $e3 + ')')
Assert ($e3 -match 'o cap NAO foi a causa') 'E4: a linha nega explicitamente o cap como causa'
Assert ($e3 -match 'lotes_nao_processados=3') 'E5: quantos lotes ficaram sem chamada fica explicito'
$e4 = Get-VixCoberturaIncompletaTexto -Rotina 'noturno' -Motivo 'limite_sessao_assinatura' -Deferidos 24 -Plano 104 -LotesNaoProcessados 3 -DetalheAuth 'limite de uso da assinatura atingido'
Assert ($e4 -like 'COBERTURA_INCOMPLETA: noturno nao varreu 24/104*') ('E6: a cobertura incompleta e declarada com numeros (obtido ' + $e4 + ')')
Assert ($e4 -match 'nao inventar cota') 'E7: a declaracao proibe inventar disponibilidade'
Assert ($e4 -match 'deferred_prioritario') 'E8: a prioridade garantida na proxima execucao esta escrita'
$e5 = Get-VixCoberturaIncompletaTexto -Rotina 'noturno' -Motivo 'cap_efetivo' -Deferidos 24 -Plano 104
Assert ($e5 -eq '') 'E9: corte planejado nao vira alarme de cobertura incompleta'

# ============================================================
Write-Host '=== F: parser valido e arquivos ASCII ==='
foreach ($p in @($MotorPath, $AuthLib, $AmbLib, $LlmLib)) {
    Assert ((Get-ParseErros $p) -eq 0) ('F1: ' + (Split-Path $p -Leaf) + ' parseia sem erro no PS 5.1')
    $nome = Split-Path $p -Leaf
    $ok = ((-not (Test-TemNaoAscii $p)) -or (Test-TemBomUtf8 $p))
    Assert $ok ('F2: ' + $nome + ' respeita a regra do repo (nao-ASCII exige BOM UTF-8)')
}
Assert (Test-AsciiPuro $PSCommandPath) 'F3: esta suite tambem e ASCII puro'

$f1 = Get-ParsedResultados @('RESULTADO|Petrobras|{"classificacao":"RELEVANTE"}', 'LOTE_RESUMO|buscas=3', 'ANOTA|teste')
Assert ($f1.Map.Count -eq 1) ('F5: o parser do motor segue lendo RESULTADO| (obtido ' + $f1.Map.Count + ' emissor)')
Assert ($f1.Buscas -eq 3) ('F6: LOTE_RESUMO|buscas= segue lido (obtido ' + $f1.Buscas + ')')
$f2 = Get-ParsedResultados @('RESULTADO|X|{ nao e json }')
Assert ($null -ne $f2) 'F7: RESULTADO com JSON invalido nao derruba o parser'

# ============================================================
Remove-Item $FakeDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ('RESULTADO: ok=' + $script:okN + ' falha=' + $script:fal)
if ($script:fal -gt 0) { exit 1 }
exit 0
