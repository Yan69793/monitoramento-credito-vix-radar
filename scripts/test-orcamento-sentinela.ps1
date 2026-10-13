# test-orcamento-sentinela.ps1 - prova do CIRCUITOSENTINELA1 (2026-10-09).
#
# Reproduz o dia 09/10/2026 com dados sinteticos e prova as DUAS pontas:
#   (A) ANTES: o FIM da sentinela contava tentativa que falhou por provedor como trabalho.
#       16 execucoes somaram 10.558.736 tokens de "trabalho" para 0 analise, o circuito do
#       dia abriu e a noturna (104) e a matinal (22) deferiram tudo.
#   (B) DEPOIS: token de lote falho sai do TRABALHO ENTREGUE (vai para tokens_falha_provider,
#       visivel no FIM) e a sentinela respeita a reserva das outras rotinas
#       (Get-VixDisponivelSentinela).
#   (D) CUSTOFALHA-TETO1 (2026-10-10): custo e retry sao eixos separados. O token do lote que
#       falhou nao e trabalho entregue - mas foi CONSUMIDO e por isso entra no teto do dia
#       (total_consumido = tokens= + tokens_falha_provider=). Antes desta correcao o teto via
#       apenas tokens=, entao 10.558.736 tokens queimados em laco de falha deixavam a margem
#       aparente em 1.299.000 e a sentinela seguia disparando sem limite. As assercoes 2b2/2c/2d
#       e 6q2/6r abaixo foram atualizadas de "falha nao afeta o circuito" para o contrato correto.
#   (C) FALHAPROVIDERDIA1 (2026-10-10): um FIM do dia com lotes_falha_provider>0 faz a
#       sentinela sair antes do modelo. Dia sem esse FIM segue, limitado aos 350.000.
#       O teto do custo-config.json nao muda.
#
# Offline puro: nenhum token, nenhuma rede, nenhum POST. So lib\vixradar-custo.ps1
# e a funcao da sentinela, extraida por AST (a rotina inteira nao roda).
# ASCII puro, PS 5.1.
param(
    # COBERTURA-13OUT1: permite provar a guarda 7 contra um arquivo operativo sintetico (duas
    # pontas). Vazio = o arquivo operativo real em logs\routines\custo-config.json.
    [string]$CustoConfigPath = ''
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1')

$script:ok = 0; $script:fal = 0
function Assert([bool]$c, [string]$m) { if ($c) { $script:ok++; Write-Host ('  OK    ' + $m) } else { $script:fal++; Write-Host ('  FALHA ' + $m) } }

# Os 16 valores reais lidos das linhas FIM: da sentinela em 09/10/2026 (vixradar-sentinela_20261009.log).
# A soma confere com o CUSTO_DIA de producao: sentinela=10558736.
$reais = @(415141,661386,447988,472035,713452,501424,923927,681300,1316168,675239,637848,762778,776998,524073,731087,317892,0)
$somaReal = 0; foreach ($v in $reais) { $somaReal += $v }

$tmp = Join-Path $env:TEMP ('vixorcamento_' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$dateTag = '20261009'
$cfgOld = @{ TETO_DIA = 1300000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000 }

try {
    Write-Host '=== 0: a serie real de 09/10 fecha em 10.558.736 (reproducao) ==='
    Assert ($somaReal -eq 10558736) ('0: soma das 16 execucoes = ' + $somaReal + ' (esperado 10558736)')

    Write-Host ''
    Write-Host '=== 1: formato ANTIGO do FIM (tentativa falha contada como trabalho) ==='
    $logAntigo = Join-Path $tmp ('vixradar-sentinela_' + $dateTag + '.log')
    $linhasAntigas = @()
    foreach ($v in $reais) { $linhasAntigas += ('2026-10-09 17:56:27 FIM: sentinela resultado=FALLO_PROVEEDOR. tokens=' + $v + ' analisados=0 submit_fail=0 deferidos=4 sem_resultado=4 excedente_worker=5 buscas=0 backlog=True lotes_ok=0 lotes_falha_provider=1') }
    Set-Content -LiteralPath $logAntigo -Value $linhasAntigas -Encoding UTF8
    $totAntigo = Get-VixTokensSentinela -LogDir $tmp -DateTag $dateTag
    Assert ($totAntigo -eq 10558736) ('1a: Get-VixTokensSentinela le o formato antigo = ' + $totAntigo)

    $custoAntigo = Get-VixCustoDia -LogDir $tmp -DateTag $dateTag -Config $cfgOld
    Assert ($custoAntigo.total_trabalho -eq 10558736) ('1b: total do dia = ' + $custoAntigo.total_trabalho + ' (o defeito medido em producao)')
    Assert ($custoAntigo.circuito_aberto -eq $true) '1c: o circuito do dia ABRE com o formato antigo (paralisa noturna e matinal)'
    $dispAntigo = Get-VixDisponivelSentinela -Custo $custoAntigo -Config $cfgOld
    Assert ($dispAntigo -eq 0) ('1d: orcamento restante da sentinela = 0 (obtido ' + $dispAntigo + ')')

    Write-Host ''
    Write-Host '=== 2: formato NOVO do FIM (falha de provedor fora do trabalho) ==='
    $logNovo = Join-Path $tmp ('vixradar-sentinela_' + $dateTag + '.log')
    $linhasNovas = @()
    foreach ($v in $reais) { $linhasNovas += ('2026-10-09 17:56:27 FIM: sentinela resultado=FALLO_PROVEEDOR. tokens=0 analisados=0 submit_fail=0 deferidos=4 sem_resultado=4 excedente_worker=5 buscas=0 backlog=True lotes_ok=0 lotes_falha_provider=1 tokens_falha_provider=' + $v) }
    Set-Content -LiteralPath $logNovo -Value $linhasNovas -Encoding UTF8
    $totNovo = Get-VixTokensSentinela -LogDir $tmp -DateTag $dateTag
    Assert ($totNovo -eq 0) ('2a: Get-VixTokensSentinela NAO soma tokens_falha_provider (obtido ' + $totNovo + ')')

    $custoNovo = Get-VixCustoDia -LogDir $tmp -DateTag $dateTag -Config $cfgOld
    Assert ($custoNovo.total_trabalho -eq 0) ('2b: trabalho do dia = ' + $custoNovo.total_trabalho + ' (falha de provedor nao vira trabalho entregue)')
    Assert ($custoNovo.total_consumido -eq 10558736) ('2b2: CONSUMO do dia = ' + $custoNovo.total_consumido + ' (a falha foi cobrada, conta no teto)')
    Assert ($custoNovo.circuito_aberto -eq $true) '2c: o circuito ABRE pelo consumo (CUSTOFALHA-TETO1)'
    $dispNovo = Get-VixDisponivelSentinela -Custo $custoNovo -Config $cfgOld
    Assert ($dispNovo -eq 0) ('2d: com 10.558.736 consumidos a sentinela fica em 0 (obtido ' + $dispNovo + ')')

    Write-Host ''
    Write-Host '=== 3: compatibilidade - tokens= real continua contado ==='
    Set-Content -LiteralPath $logNovo -Value @('2026-10-09 10:00:00 FIM: sentinela resultado=OK. tokens=1234 analisados=4 deferidos=0 lotes_ok=1 lotes_falha_provider=0 tokens_falha_provider=99') -Encoding UTF8
    Assert ((Get-VixTokensSentinela -LogDir $tmp -DateTag $dateTag) -eq 1234) '3a: tokens= real e somado (1234); tokens_falha_provider ignorado'

    Write-Host ''
    Write-Host '=== 4: a sentinela nao come o orcamento das outras rotinas ==='
    $c1 = @{ total_trabalho = [int64]700000; por_rotina = @{ sentinela = @{ trabalho = [int64]0 }; noturno = @{ trabalho = [int64]700000 } } }
    Assert ((Get-VixDisponivelSentinela -Custo $c1 -Config $cfgOld) -eq 0) '4a: noturna ja gastou 700k -> sentinela fica em 0 (nao paralisa, nao invade)'
    $c2 = @{ total_trabalho = [int64]0; por_rotina = @{ sentinela = @{ trabalho = [int64]0 } } }
    Assert ((Get-VixDisponivelSentinela -Custo $c2 -Config $cfgOld) -eq 350000) '4b: dia limpo -> 350k para a sentinela'
    $c3 = @{ total_trabalho = [int64]200000; por_rotina = @{ sentinela = @{ trabalho = [int64]200000 } } }
    Assert ((Get-VixDisponivelSentinela -Custo $c3 -Config $cfgOld) -eq 150000) '4c: sentinela ja gastou 200k no dia -> sobra 150k'

    Write-Host ''
    Write-Host '=== 5: o gate esta ligado ao script da sentinela (estatico) ==='
    $src = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'run_vixradar_sentinela.ps1') -Raw -Encoding UTF8
    Assert ($src -match 'Get-VixDisponivelSentinela') '5a: a sentinela usa a formula unica de orcamento'
    Assert ($src -match 'CIRCUITO_SENTINELA_FECHADO') '5b: existe o caminho de aborto por falta de orcamento (fail-closed, backlog intacto)'
    Assert ($src -match 'tokens_falha_provider') '5c: o FIM registra tokens_falha_provider (consumo visivel, fora do teto)'
    # CONTABILIDADEIGUAL1 (2026-10-13): a linha de log tem de reportar o numero que DECIDE. Ela
    # descontava `trabalho` enquanto Get-VixDisponivelSentinela desconta `consumo` (que inclui o
    # lote que falhou por provedor e gastou de verdade) - num dia com falha o CIRCUITO_DIA mostrava
    # folga que o circuito nao tinha. As duas pontas: o campo novo aparece e o antigo nao sobrou.
    Assert ($src -match "\[int64\]\`$__sentinelaRot\.consumo") '5d: o log CIRCUITO_DIA le consumo, o mesmo campo que decide o orcamento'
    Assert ($src -notmatch "\`$__gastoOutras = \[int64\]\`$__custoDiaSentinela\.total_trabalho") '5e: ponta oposta: o total do log nao voltou a ser o de trabalho'

    Write-Host ''
    Write-Host '=== 6: FALHAPROVIDERDIA1 - dia com falha nao chama o modelo; dia limpo segue ==='
    $sentPath = Join-Path $PSScriptRoot 'run_vixradar_sentinela.ps1'
    $tkS = $null; $erS = $null
    $astS = [System.Management.Automation.Language.Parser]::ParseFile($sentPath, [ref]$tkS, [ref]$erS)
    Assert ($erS.Count -eq 0) ('6a: sentinela faz parse sem erro (' + $erS.Count + ')')
    $defGuarda = $astS.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-VixSentinelaFalhaProviderNoDia' }, $true) | Select-Object -First 1
    Assert ($null -ne $defGuarda) '6b: a funcao que le o log do dia existe'
    if ($defGuarda) { Invoke-Expression $defGuarda.Extent.Text }

    $tagDia = '20261010'
    $logFalha = Join-Path $tmp ('falha_' + $tagDia + '.log')
    $linhaFalha = '2026-10-10 10:25:00 FIM: sentinela resultado=FALLO_PROVEEDOR. tokens=0 analisados=0 submit_fail=0 deferidos=4 sem_resultado=4 excedente_worker=5 buscas=0 backlog=True lotes_ok=0 lotes_falha_provider=1 tokens_falha_provider=415141'
    Set-Content -LiteralPath $logFalha -Value @($linhaFalha) -Encoding UTF8
    $decideFalha = Test-VixSentinelaFalhaProviderNoDia $logFalha
    Write-Host ('  info  dia com FALLO_PROVEEDOR: guarda=' + $decideFalha + ' chama_modelo=' + (-not $decideFalha))
    Assert ($decideFalha -eq $true) '6c: um FIM com lotes_falha_provider=1 faz a guarda disparar (modelo nao e chamado)'

    $logMisto = Join-Path $tmp ('misto_' + $tagDia + '.log')
    $linhaOk = '2026-10-10 09:25:00 FIM: sentinela resultado=OK. tokens=1000 analisados=2 deferidos=0 lotes_ok=1 lotes_falha_provider=0 tokens_falha_provider=0'
    Set-Content -LiteralPath $logMisto -Value @($linhaOk, $linhaFalha) -Encoding UTF8
    $decideMisto = Test-VixSentinelaFalhaProviderNoDia $logMisto
    Write-Host ('  info  dia com OK e depois uma falha: guarda=' + $decideMisto + ' chama_modelo=' + (-not $decideMisto))
    Assert ($decideMisto -eq $true) '6d: um lote falho no dia basta, mesmo se outro FIM do dia foi OK'

    $logLimpo = Join-Path $tmp ('vixradar-sentinela_' + $tagDia + '.log')
    $linhaSemGatilho = '2026-10-10 09:25:00 FIM: sentinela sem gatilho. tokens=0 analisados=0 motivo=sem_novidade'
    $linhaOkZero = '2026-10-10 09:55:00 FIM: sentinela resultado=OK. tokens=0 analisados=0 deferidos=0 lotes_ok=1 lotes_falha_provider=0 tokens_falha_provider=999999'
    Set-Content -LiteralPath $logLimpo -Value @($linhaSemGatilho, $linhaOkZero) -Encoding UTF8
    $decideLimpo = Test-VixSentinelaFalhaProviderNoDia $logLimpo
    Write-Host ('  info  dia sem falha de provedor: guarda=' + $decideLimpo + ' chama_modelo=' + (-not $decideLimpo))
    Assert ($decideLimpo -eq $false) '6e: dia sem lotes_falha_provider>0 nao dispara a guarda (segue o caminho normal)'
    Assert ((Test-VixSentinelaFalhaProviderNoDia (Join-Path $tmp 'log_que_nao_existe.log')) -eq $false) '6f: log ausente (primeiro disparo do dia) nao dispara a guarda'

    $logSoAdiada = Join-Path $tmp ('adiada_' + $tagDia + '.log')
    $linhaAdiada = '2026-10-10 10:55:00 FIM: sentinela resultado=ADIADA_FALHA_PROVIDER. tokens=0 analisados=0 submit_fail=0 deferidos=0 sem_resultado=0 excedente_worker=5 buscas=0 backlog=True lotes_ok=0 lotes_falha_provider=0 motivo=falha_provider_ja_no_dia'
    Set-Content -LiteralPath $logSoAdiada -Value @($linhaAdiada) -Encoding UTF8
    Assert ((Test-VixSentinelaFalhaProviderNoDia $logSoAdiada) -eq $false) '6g: o FIM da propria saida (lotes_falha_provider=0) nao trava o dia sozinho'

    $guardaIf = $astS.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Extent.Text -match 'Test-VixSentinelaFalhaProviderNoDia \$LogFile' }, $true) | Select-Object -First 1
    Assert ($null -ne $guardaIf) '6h: o if da guarda esta no script, lendo o log do dia'
    $fimGuarda = 0
    if ($guardaIf) { $fimGuarda = [int]$guardaIf.Extent.EndLineNumber }
    $corpoGuarda = ''
    if ($guardaIf) { $corpoGuarda = $guardaIf.Extent.Text }
    Assert ($corpoGuarda -match 'tokens=0') '6i: a saida da guarda grava tokens=0'
    Assert ($corpoGuarda -match 'backlog=True') '6j: a saida da guarda deixa o backlog ligado'
    Assert ($corpoGuarda -match 'exit 0') '6k: a guarda sai antes de montar lote (exit 0)'
    Assert ($corpoGuarda -match 'Write-State') '6l: a guarda regrava o estado com backlog, nao drena o plano'
    Assert (-not ($corpoGuarda -match 'Invoke-ClaudeBatchSentinela')) '6m: o bloco da guarda nao chama o modelo'

    $comandosAst = @($astS.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
    function Get-MenorLinhaComando($lista, [string]$nome) {
        $menor = 0
        foreach ($c in @($lista)) {
            if ($c.GetCommandName() -eq $nome) {
                $ln = [int]$c.Extent.StartLineNumber
                if ($menor -eq 0 -or $ln -lt $menor) { $menor = $ln }
            }
        }
        return $menor
    }
    $linModelo = Get-MenorLinhaComando $comandosAst 'Invoke-ClaudeBatchSentinela'
    $linPrompt = Get-MenorLinhaComando $comandosAst 'New-BatchPromptSentinela'
    $linSonda = Get-MenorLinhaComando $comandosAst 'Test-VixWebSearchProbe'
    $linDisp = Get-MenorLinhaComando $comandosAst 'Get-VixDisponivelSentinela'
    Write-Host ('  info  guarda termina na linha ' + $fimGuarda + '; montar lote=' + $linPrompt + '; sonda=' + $linSonda + '; modelo=' + $linModelo + '; orcamento=' + $linDisp)
    Assert (($fimGuarda -gt 0) -and ($linPrompt -gt $fimGuarda)) ('6n: a guarda termina (linha ' + $fimGuarda + ') antes de montar lote (linha ' + $linPrompt + ')')
    Assert (($linSonda -gt $fimGuarda) -and ($linModelo -gt $fimGuarda)) ('6o: sonda (linha ' + $linSonda + ') e modelo (linha ' + $linModelo + ') ficam depois da guarda')
    Assert ($linDisp -gt $fimGuarda) ('6p: dia limpo ainda passa pelo orcamento do dia (linha ' + $linDisp + ')')

    $custoLimpo = Get-VixCustoDia -LogDir $tmp -DateTag $tagDia -Config $cfgOld
    $dispLimpo = Get-VixDisponivelSentinela -Custo $custoLimpo -Config $cfgOld
    Assert ($custoLimpo.total_trabalho -eq 0) ('6q: trabalho=' + $custoLimpo.total_trabalho + ' (tokens_falha_provider nao entra no TRABALHO entregue)')
    Assert ($custoLimpo.total_consumido -eq 999999) ('6q2: CONSUMO do dia = ' + $custoLimpo.total_consumido + ' (o teto ve a falha, CUSTOFALHA-TETO1)')
    Assert ($dispLimpo -eq 0) ('6r: com 999.999 consumidos a sentinela fica em 0 (obtido ' + $dispLimpo + ')')

    $logConta = Join-Path $tmp ('vixradar-sentinela_' + $tagDia + '.log')
    Set-Content -LiteralPath $logConta -Value @($linhaFalha, $linhaAdiada) -Encoding UTF8
    $totSkip = Get-VixTokensSentinela -LogDir $tmp -DateTag $tagDia
    Assert ($totSkip -eq 0) ('6s: falha + saida adiada somam trabalho ' + $totSkip + ' (esperado 0; tokens_falha_provider nao entra)')
    Assert ((Test-VixSentinelaFalhaProviderNoDia $logConta) -eq $true) '6t: com a falha ainda no log, o disparo seguinte continua sem modelo'

    Write-Host ''
    Write-Host '=== 7: o teto operativo bate com o teto DECLARADO (nenhuma mudanca silenciosa) ==='
    # COBERTURA-13OUT1 (2026-10-13): o 7a exigia 1300000 fixo e reprovava desde 12/10, quando o
    # operador subiu o TETO_DIA para 2600000 e registrou o motivo no _doc do arquivo operativo.
    # Trocar o 1300000 por 2600000 aqui so moveria o numero magico. A guarda agora compara o
    # arquivo operativo (logs/, fora do git) com a declaracao VERSIONADA
    # scripts/custo-teto-declarado.json, que guarda valor, data e motivo. Qualquer divergencia
    # entre os dois continua reprovando, inclusive alteracao silenciosa do teto.
    $cfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs\routines\custo-config.json'
    if ($CustoConfigPath) { $cfgPath = $CustoConfigPath }
    $cfgJson = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $decl = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custo-teto-declarado.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host ('  info  operativo TETO_DIA=' + $cfgJson.TETO_DIA + ' RESERVA_NOTURNO=' + $cfgJson.RESERVA_NOTURNO + ' RESERVA_VERIFICACAO=' + $cfgJson.RESERVA_VERIFICACAO + ' MARGEM_MINIMA=' + $cfgJson.MARGEM_MINIMA)
    Write-Host ('  info  declarado TETO_DIA=' + $decl.TETO_DIA + ' (ultima decisao ' + (@($decl.historico)[-1]).data + ')')
    Assert ([int64]$cfgJson.TETO_DIA -eq [int64]$decl.TETO_DIA) ('7a: TETO_DIA operativo = ' + $cfgJson.TETO_DIA + ' (declarado ' + $decl.TETO_DIA + ')')
    Assert ([int64]$cfgJson.RESERVA_NOTURNO -eq [int64]$decl.RESERVA_NOTURNO) ('7b: RESERVA_NOTURNO = ' + $cfgJson.RESERVA_NOTURNO + ' (declarado ' + $decl.RESERVA_NOTURNO + ')')
    Assert ([int64]$cfgJson.RESERVA_VERIFICACAO -eq [int64]$decl.RESERVA_VERIFICACAO) ('7c: RESERVA_VERIFICACAO = ' + $cfgJson.RESERVA_VERIFICACAO + ' (declarado ' + $decl.RESERVA_VERIFICACAO + ')')
    Assert ([int64]$cfgJson.MARGEM_MINIMA -eq [int64]$decl.MARGEM_MINIMA) ('7d: MARGEM_MINIMA = ' + $cfgJson.MARGEM_MINIMA + ' (declarado ' + $decl.MARGEM_MINIMA + ')')
    Assert ((@($decl.historico)[-1]).TETO_DIA -eq $decl.TETO_DIA -and ('' + (@($decl.historico)[-1]).motivo).Length -gt 20) '7a2: a declaracao traz data e motivo da ultima mudanca do teto'
    Assert (('' + $cfgJson._doc) -match [regex]::Escape('' + $decl.TETO_DIA)) '7a3: o _doc do arquivo operativo registra o valor em vigor'
    $libSrc = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1') -Raw -Encoding UTF8
    # O default da lib e o FALLBACK de arquivo ilegivel. Ele fica em 1300000 de proposito: se o
    # arquivo operativo some, o teto cai, nunca sobe. A divergencia com o operativo e esperada e
    # e conferida aqui como relacao (default <= declarado), nao escondida.
    Assert ($libSrc -match 'TETO_DIA = 1300000') '7e: o default da biblioteca continua 1300000'
    Assert (1300000 -le [int64]$decl.TETO_DIA) '7e2: fallback da lib e mais conservador que o teto declarado (arquivo ilegivel reduz o teto)'
    Assert ($libSrc -match 'RESERVA_NOTURNO = 700000') '7f: a reserva da noite na biblioteca continua 700000'
    Assert (-not ($src -match 'Set-Content[^\r\n]*custo-config')) '7g: a sentinela nao grava o arquivo de teto'
    Assert ([int64]$cfgJson.SENTINELA_DIA -eq [int64]$decl.SENTINELA_DIA -and [int64]$decl.SENTINELA_DIA -gt 0) '7h: SENTINELA_DIA operativo bate com o declarado'

    Write-Host ''
    Write-Host '=== 8: limite diario proprio da sentinela (ORCAMENTO-13OUT7), duas pontas ==='
    $c8 = @{ TETO_DIA = 2600000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000; SENTINELA_DIA = 320000 }
    $mk = { param($sent) @{ mensuravel = $true; total_consumido = [int64]$sent; por_rotina = @{ sentinela = @{ trabalho = [int64]$sent; consumo = [int64]$sent } } } }
    $d0 = Get-VixDisponivelSentinela -Custo (& $mk 0) -Config $c8
    $d1 = Get-VixDisponivelSentinela -Custo (& $mk 156293) -Config $c8
    $d2 = Get-VixDisponivelSentinela -Custo (& $mk 312586) -Config $c8
    Assert ($d0 -eq 320000) ("8a: dia zerado libera o limite proprio inteiro (" + $d0 + ")")
    Assert ($d1 -eq 163707) ("8b: apos 1 emissor restam " + $d1 + " (cabe o 2o de 156293)")
    Assert ($d2 -eq 7414 -and $d2 -lt 156293) ("8c: apos 2 emissores resta " + $d2 + ", nao admite o 3o")
    $c8b = @{}; foreach ($k in $c8.Keys) { $c8b[$k] = $c8[$k] }; $c8b.Remove('SENTINELA_DIA')
    $dSem = Get-VixDisponivelSentinela -Custo (& $mk 600000) -Config $c8b
    Assert ($dSem -gt 320000) ("8d: sem SENTINELA_DIA vale so a sobra do dia (" + $dSem + "), prova de que o limite e que contem")
    Assert (([int64]$c8.TETO_DIA) -eq 2600000) '8e: o TETO_DIA global nao foi alterado'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
