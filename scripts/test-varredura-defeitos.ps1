# test-varredura-defeitos.ps1 - D1/D4/D3/D2, offline via funcoes reais do motor.
# ASCII puro para PowerShell 5.1.
$ErrorActionPreference = 'Continue'
$fail = 0
$pass = 0

function Assert-True([bool]$cond, [string]$nome) {
    if ($cond) { $script:pass++; Write-Host ('PASS: ' + $nome) }
    else { $script:fail++; Write-Host ('FAIL: ' + $nome) }
}

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

# Caminho do motor derivado do PROPRIO checkout. Era 'E:\Diretorio\Claude\...' (maquina do
# operador): no runner do CI o ParseFile lancava antes do primeiro assert e a suite morria com
# exit=1 sem imprimir nada (medido em 5/5 execucoes do gate, 12 a 14/09/2026).
$MotorPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\run_vixradar_varredura.ps1'
foreach ($_def in (Get-MotorFuncDefs $MotorPath @('Get-NomeNormalizado', 'Get-VixLockState', 'Get-VixResumoLedger', 'Get-VixCodexUsageProbe', 'Get-VixCoberturaProviderCapability', 'Test-VixBuscaDegradada', 'ConvertTo-VixFonteEstrutural', 'Resolve-VixCoberturaFamilias', 'Get-VixDrenoTexto', 'Invoke-VixDrenoPosRotina', 'Get-VixDeferidoMotivo', 'Get-VixDeferidosTexto', 'Get-VixCoberturaIncompletaTexto', 'Get-VixDrenoAlerta', 'Set-VixMetricsDrenoExit'))) { Invoke-Expression $_def }

# Stub de log: as funcoes do motor escrevem por Write-Log, que os testes trocam pela coleta.
$script:LinhasLog = @()
function Write-Log([string]$m) { $script:LinhasLog += $m }

Write-Host '== D1 lock: PID vivo bloqueia, morto ou reutilizado e orfao =='
$tmp = Join-Path $env:TEMP ('vix-d1-' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$lock = Join-Path $tmp 'teste.lock'
$self = Get-Process -Id $PID
$selfStart = $self.StartTime.ToUniversalTime().ToString('o')
Set-Content -LiteralPath $lock -Value ("pid=$PID`ninicio_utc=$selfStart") -Encoding UTF8
$live = Get-VixLockState $lock 30
Assert-True ($live.bloqueia -and ($live.motivo -eq 'LOCK_VIVO')) 'D1a: PID vivo com inicio igual bloqueia'
Set-Content -LiteralPath $lock -Value ("pid=999999`ninicio_utc=$selfStart") -Encoding UTF8
$dead = Get-VixLockState $lock 30
Assert-True ((-not $dead.bloqueia) -and ($dead.motivo -eq 'LOCK_ORFAO_PID_MORTO')) 'D1b: PID morto e LOCK_ORFAO, assume sem remover manualmente'
Set-Content -LiteralPath $lock -Value ("pid=$PID`ninicio_utc=2000-01-01T00:00:00.0000000Z") -Encoding UTF8
$reused = Get-VixLockState $lock 30
Assert-True ((-not $reused.bloqueia) -and ($reused.motivo -eq 'LOCK_ORFAO_PID_REUTILIZADO')) 'D1c: PID reutilizado por inicio divergente e LOCK_ORFAO'

Write-Host '== D4 total: vem do ledger do dia, nao dos contadores da execucao =='
$ledger = Join-Path $tmp 'dia.log'
@(
    '2026-09-12 10:00:00 OK|Empresa A|FULL|NENHUM|0|True|ANALISADO|0'
    '2026-09-12 10:01:00 OK|Empresa B|SKIP|-|0|True|SKIP|0'
    '2026-09-12 10:02:00 OK|Empresa A|FULL|NENHUM|0|True|ANALISADO|0'
    '2026-09-12 10:03:00 OK|Empresa C|FULL|-|0|False|DEFERIDO|0'
) | Set-Content -LiteralPath $ledger -Encoding UTF8
$sumario = Get-VixResumoLedger $ledger
Assert-True ($sumario.total -eq 3) 'D4: Total do dia conta emissor unico do ledger, inclusive reinicio, e ignora contador atual'
Assert-True ($sumario.analisados -eq 1 -and $sumario.skips -eq 1 -and $sumario.deferidos -eq 1) 'D4b: resumo vem dos status gravados no ledger'

Write-Host '== D3 Codex: usage e medida so quando o JSON a emite =='
$usage = Get-VixCodexUsageProbe @('{"type":"turn.completed","usage":{"input_tokens":12,"output_tokens":34,"cache_creation_input_tokens":5,"cache_read_input_tokens":6}}')
Assert-True ($usage.mensuravel -and $usage.parcelas.input -eq 12 -and $usage.parcelas.output -eq 34) 'D3a: usage emitida pelo codex e capturada'
$unmeasured = Get-VixCodexUsageProbe @('{"type":"turn.completed"}')
Assert-True ((-not $unmeasured.mensuravel) -and $null -eq $unmeasured.parcelas) 'D3b: sem usage emitida publica NAO_MENSURAVEL, nunca zero'

Write-Host '== D2 cobertura: somente capability declarada pode nao ter HTTP =='
function New-Fonte([string]$prov, $http) {
    return [pscustomobject]@{ familia = 'emissor'; query = 'Empresa contexto'; timestamp = '2026-09-12T18:00:00Z'; provedor = $prov; status_http = $http; resultado = 'sem fato novo na janela'; classificacao = 'ok' }
}
$codexFonte = ConvertTo-VixFonteEstrutural (New-Fonte 'codex:web_search' $null)
Assert-True ($codexFonte.ok -and ($codexFonte.motivo -eq 'ok_sem_http_provider') -and $codexFonte.cobertura_parcial) 'D2a: codex declarado aceita status_http null e marca contrato parcial'
$openrouterSemHttp = ConvertTo-VixFonteEstrutural (New-Fonte 'openrouter:web_search' $null)
Assert-True ((-not $openrouterSemHttp.ok) -and ($openrouterSemHttp.motivo -eq 'sem_prova_sem_status_http')) 'D2b: provider HTTP sem status continua rejeitado'
$desconhecido = ConvertTo-VixFonteEstrutural (New-Fonte 'desconhecido:web_search' 200)
Assert-True ((-not $desconhecido.ok) -and ($desconhecido.motivo -eq 'sem_prova_provedor_desconhecido')) 'D2c: provider desconhecido continua rejeitado'
$codexSemCampo = [pscustomobject]@{ familia = 'emissor'; query = 'Empresa contexto'; timestamp = '2026-09-12T18:00:00Z'; provedor = 'codex:web_search'; resultado = 'sem fato novo na janela'; classificacao = 'ok' }
$semCampo = ConvertTo-VixFonteEstrutural $codexSemCampo
Assert-True ((-not $semCampo.ok) -and ($semCampo.motivo -eq 'sem_prova_sem_status_http')) 'D2d: status_http ausente continua rejeitado mesmo para codex'
$familias = [pscustomobject]@{ fontes_consultadas = @(
    (New-Fonte 'codex:web_search' $null),
    [pscustomobject]@{ familia = 'divida'; query = 'Empresa divida'; timestamp = '2026-09-12T18:00:00Z'; provedor = 'codex:web_search'; status_http = $null; resultado = 'sem fato novo'; classificacao = 'ok' },
    [pscustomobject]@{ familia = 'fato'; query = 'Empresa CVM'; timestamp = '2026-09-12T18:00:00Z'; provedor = 'codex:web_search'; status_http = $null; resultado = 'sem fato novo'; classificacao = 'ok' }
) }
$cobertura = Resolve-VixCoberturaFamilias $familias
Assert-True ($cobertura.ok -and $cobertura.cobertura_parcial -and (($cobertura.contratos_provedor -join ',') -eq 'cobertura_parcial_provider_codex')) 'D2d: cobertura parcial traz contrato especifico do provider'

Write-Host '== D2 retry Codex: o prompt preserva provider e excecao declarada =='
$tokensPrompt = $null; $errorsPrompt = $null
$motorAst = [System.Management.Automation.Language.Parser]::ParseFile($MotorPath, [ref]$tokensPrompt, [ref]$errorsPrompt)
$retryCalls = $motorAst.FindAll({
    param($n)
    if ($n -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
    if ($n.CommandElements.Count -lt 2 -or $n.CommandElements[0].Extent.Text -ne 'New-BatchPrompt') { return $false }
    return ($n.Extent.Text -match '\$missing')
}, $true)
Assert-True (($retryCalls.Count -eq 1) -and ($retryCalls[0].Extent.Text -match '\$janFim\s+\$fonteProvedor\s+-Ultra:\$job\.Ultra')) 'D2e: retry repassa fonteProvedor ao New-BatchPrompt'
$promptDef = $motorAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-BatchPrompt' }, $true) | Select-Object -First 1
$promptText = if ($promptDef) { $promptDef.Extent.Text } else { '' }
Assert-True (($promptText -match '"provedor":"\$FonteProvedor:web_search\|web_fetch"') -and ($promptText -match 'somente provedor "codex" pode emitir "status_http":null') -and ($promptText -match 'Todo outro provedor exige status_http inteiro 2xx')) 'D2f: prompt do retry Codex declara codex:web_search|web_fetch e excecao sem HTTP'

Write-Host '== D5 dreno pos-rotina: exit != 0 nunca sai como "concluido" =='
# DRENOMUDO1 (2026-09-13): em 13/09 o log do motor disse "POS-MATINAL: dreno concluido (exit=5)"
# com a fila de verificacao NAO drenada. Prova de duas pontas do texto real que vai ao log.
$d5ok = Get-VixDrenoTexto -Rotina 'matinal' -ExitCode 0
$d5falha = Get-VixDrenoTexto -Rotina 'matinal' -ExitCode 5
Assert-True (($d5ok -eq 'POS-MATINAL: dreno concluido (exit=0)')) ('D5a: exit 0 mantem a palavra concluido (' + $d5ok + ')')
Assert-True (($d5falha -match 'FALHOU') -and ($d5falha -match 'exit=5') -and ($d5falha -match 'NAO foi drenada')) ('D5b: exit 5 diz FALHOU com o codigo (' + $d5falha + ')')
Assert-True (-not ($d5falha -match 'concluido')) 'D5c: exit 5 nao carrega a palavra concluido (ponta ruim do comportamento antigo)'
Assert-True ((Get-VixDrenoTexto -Rotina 'noturno' -ExitCode 1) -eq 'POS-NOTURNO: dreno FALHOU (exit=1) - a fila de verificacao NAO foi drenada') 'D5d: rotulo acompanha a rotina e o codigo'

Write-Host '== D6 dreno pos-rotina: processo filho de verdade, exit code lido =='
# DRENOMUDO1: teste de texto nao prova Start-Process nem o exit code do filho. Aqui sobe um
# script de apoio que sai com codigo conhecido e confere o que a funcao devolve e o que ela
# escreve no log. Sem rede, sem token, sem tocar a fila real.
$stubOk = Join-Path $tmp 'stub-dreno-ok.ps1'
$stubFalha = Join-Path $tmp 'stub-dreno-falha.ps1'
Set-Content -LiteralPath $stubOk -Value 'exit 0' -Encoding ASCII
Set-Content -LiteralPath $stubFalha -Value 'exit 5' -Encoding ASCII
$script:LinhasLog = @()
$exitOk = Invoke-VixDrenoPosRotina -ScriptPath $stubOk -Rotina 'matinal'
Assert-True ($exitOk -eq 0) ('D6a: filho com exit 0 devolve 0 (recebido=' + $exitOk + ')')
Assert-True (($script:LinhasLog -join "`n") -match 'POS-MATINAL: dreno concluido \(exit=0\)') 'D6a2: log do exit 0 diz concluido'
Assert-True (-not (($script:LinhasLog -join "`n") -match 'ERRO DRENO')) 'D6a3: exit 0 nao escreve ERRO DRENO'
$script:LinhasLog = @()
$exitFalha = Invoke-VixDrenoPosRotina -ScriptPath $stubFalha -Rotina 'matinal'
Assert-True ($exitFalha -eq 5) ('D6b: filho com exit 5 devolve 5 (recebido=' + $exitFalha + ')')
Assert-True (($script:LinhasLog -join "`n") -match 'POS-MATINAL: dreno FALHOU \(exit=5\)') 'D6b2: log do exit 5 diz FALHOU'
Assert-True (($script:LinhasLog -join "`n") -match 'ERRO DRENO') 'D6b3: exit 5 escreve a linha ERRO DRENO que o vigia le'
Assert-True (-not (($script:LinhasLog -join "`n") -match 'concluido')) 'D6b4: exit 5 nao escreve a palavra concluido'
$script:LinhasLog = @()
$exitAusente = Invoke-VixDrenoPosRotina -ScriptPath (Join-Path $tmp 'nao-existe.ps1') -Rotina 'matinal'
Assert-True ($exitAusente -ne 0) ('D6c: script ausente nao devolve sucesso (recebido=' + $exitAusente + ')')

Write-Host '== D7 COBERTURAAUTH1: motivo do deferimento - duas causas, duas rotulagens =='
# 14/09/2026: a noturna analisou 45/104, deferiu 24 e fechou com
# `DEFERIDOS: ok=24 falha=0 total=24 motivo=cap_efetivo (378424/700000 realizados)`. O cap de
# tokens NUNCA foi alcancado - o corte veio do limite de sessao da assinatura no lote light-4.
# Prova de duas pontas do texto real que vai ao log.
Assert-True ((Get-VixDeferidoMotivo -AbortoAuth $false) -eq 'cap_efetivo') 'D7a: sem aborto de auth o motivo e cap_efetivo (corte planejado)'
Assert-True ((Get-VixDeferidoMotivo -AbortoAuth $true) -eq 'limite_sessao_assinatura') 'D7b: aborto de auth vira limite_sessao_assinatura'
$d7cap = Get-VixDeferidosTexto -Motivo 'cap_efetivo' -Ok 24 -Falha 0 -Total 24 -TokensRealizados 378424 -CapEfetivo 700000
Assert-True ($d7cap -eq 'DEFERIDOS: ok=24 falha=0 total=24 motivo=cap_efetivo (378424/700000 realizados)') ('D7c: corte planejado mantem o texto historico byte a byte (' + $d7cap + ')')
$d7auth = Get-VixDeferidosTexto -Motivo 'limite_sessao_assinatura' -Ok 24 -Falha 0 -Total 24 -TokensRealizados 378424 -CapEfetivo 700000 -LotesNaoProcessados 1
Assert-True (($d7auth -match 'motivo=limite_sessao_assinatura') -and ($d7auth -match 'o cap NAO foi a causa') -and ($d7auth -match 'lotes_nao_processados=1')) ('D7d: corte por assinatura nomeia a causa e os lotes nao processados (' + $d7auth + ')')
Assert-True (-not ($d7auth -match 'motivo=cap_efetivo')) 'D7e: corte por assinatura NAO carrega o rotulo cap_efetivo (ponta ruim do comportamento antigo)'

Write-Host '== D8 COBERTURAAUTH1: declaracao observavel e acionavel da cobertura incompleta =='
$d8cap = Get-VixCoberturaIncompletaTexto -Rotina 'noturno' -Motivo 'cap_efetivo' -Deferidos 24 -Plano 104 -LotesNaoProcessados 0
Assert-True ($d8cap -eq '') 'D8a: cauda planejada por cap NAO vira COBERTURA_INCOMPLETA (nao fabrica alarme diario)'
$d8auth = Get-VixCoberturaIncompletaTexto -Rotina 'noturno' -Motivo 'limite_sessao_assinatura' -Deferidos 24 -Plano 104 -LotesNaoProcessados 1 -DetalheAuth 'limite de uso da assinatura atingido'
Assert-True (($d8auth -match 'COBERTURA_INCOMPLETA') -and ($d8auth -match '24/104') -and ($d8auth -match 'motivo=limite_sessao_assinatura') -and ($d8auth -match 'lotes_nao_processados=1')) ('D8b: cobertura incompleta diz quantos, por que e quantos lotes (' + $d8auth + ')')
Assert-True (($d8auth -match 'DECISAO:') -and ($d8auth -match 'prioridade garantida na proxima execucao') -and ($d8auth -match '_token_cap_deferred=true') -and ($d8auth -match 'deferred_prioritario') -and ($d8auth -match 'nao esperar o reset') -and ($d8auth -match 'nao inventar cota')) 'D8c: a decisao registrada vai escrita na linha (deferir com prioridade, sem esperar reset, sem inventar cota)'
Assert-True ((Get-VixCoberturaIncompletaTexto -Rotina 'noturno' -Motivo 'limite_sessao_assinatura' -Deferidos 0 -Plano 104) -eq '') 'D8d: sem deferido nao ha declaracao'

Write-Host '== D9 DRENOMUDO1: desfecho do dreno no contrato do dia (arquivo real) =='
# Ponta ruim medida em 14/09: o metrics do dia dizia dreno_exit=null (matinal e noturno) com
# `POS-NOTURNO: dreno FALHOU (exit=5)` no log, porque o contrato era escrito antes do dreno rodar.
$met = Join-Path $tmp 'metrics-dreno.json'
'{"data":"20260914","rotina":"noturno","analisados":45,"dreno_exit":null}' | Set-Content -LiteralPath $met -Encoding UTF8
$okSet = Set-VixMetricsDrenoExit -MetricsPath $met -ExitCode 5
$depois = Get-Content -LiteralPath $met -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($okSet -and ([int]$depois.dreno_exit -eq 5)) ('D9a: exit 5 entra no metrics do dia (dreno_exit=' + $depois.dreno_exit + ')')
Assert-True (([int]$depois.analisados -eq 45) -and ($depois.rotina -eq 'noturno')) 'D9b: a correcao preserva os outros campos do contrato do dia'
$null = Set-VixMetricsDrenoExit -MetricsPath $met -ExitCode 0
Assert-True (([int](Get-Content -LiteralPath $met -Raw -Encoding UTF8 | ConvertFrom-Json).dreno_exit) -eq 0) 'D9c: dreno que drenou grava 0, nunca null'
$antesTxt = Get-Content -LiteralPath $met -Raw -Encoding UTF8
$rNull = Set-VixMetricsDrenoExit -MetricsPath $met -ExitCode $null
$depoisTxt = Get-Content -LiteralPath $met -Raw -Encoding UTF8
Assert-True ((-not $rNull) -and ($antesTxt -eq $depoisTxt)) 'D9d: execucao que nao tentou o dreno ($null) nao toca no arquivo'
Assert-True (-not (Set-VixMetricsDrenoExit -MetricsPath (Join-Path $tmp 'nao-existe.json') -ExitCode 5)) 'D9e: arquivo ausente devolve false e nunca lanca'
Assert-True (((Get-VixDrenoAlerta $null) -eq '') -and ((Get-VixDrenoAlerta 0) -eq '')) 'D9f: dreno nao tentado ou bem sucedido nao gera alerta'
$al = Get-VixDrenoAlerta 5
Assert-True (($al -match 'ALERTA_DRENO') -and ($al -match 'exit=5') -and ($al -match 'NAO foi drenada')) ('D9g: exit 5 levanta ALERTA_DRENO proprio do motor (' + $al + ')')

Write-Host '== D10 DRENOMUDO1: ordem no fonte - o dreno roda ANTES do contrato do dia =='
$motorTxt = Get-Content -LiteralPath $MotorPath -Raw -Encoding UTF8
$posDreno = $motorTxt.IndexOf('drenando fila de verificacao')
$posMet = $motorTxt.IndexOf('} | ConvertTo-Json -Depth 6 | Set-Content $MetricsFile')
$posFim = $motorTxt.IndexOf("' duracao_sec=' + [Math]::Round")
Assert-True (($posDreno -gt 0) -and ($posMet -gt 0) -and ($posFim -gt 0)) 'D10a: os tres marcos existem no fonte (bloco do dreno, metrics, linha FIM)'
Assert-True (($posDreno -lt $posMet) -and ($posDreno -lt $posFim)) ('D10b: dreno ANTES do metrics e do FIM (dreno@' + $posDreno + ' metrics@' + $posMet + ' fim@' + $posFim + ')')

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ('RESULTADO: pass=' + $pass + ' fail=' + $fail)
if ($fail -gt 0) { exit 1 } else { exit 0 }