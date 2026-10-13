# test-cobertura-recuperacao.ps1 - COBERTURA-13OUT1 parte 2 (2026-10-13)
# Prova deterministica, offline, sem token e sem rede, das camadas que ligam cobertura incompleta a
# quem opera: triagem deterministica, watchdog, retry, monitor, gate anti-Claude e recuperacao.
#   T triagem: relevancia do titulo, classes, revalidacao, coleta indisponivel nunca certifica
#   P portao de ausencia: o resultado deterministico passa no MESMO gate que a IA passa
#   C cache de coleta e registro da ultima analise de IA
#   W watchdog/retry: entrega PARCIAL reconhecida sem quebrar o conceito de entrega
#   M monitor: codigo 9010 e exit code do Agendador (guardas estruturais no fonte)
#   G gate anti-Claude: `claude --version` aceito, invocacao real continua reprovada
#   R recuperacao: 3 execucoes encadeadas, reinicio no meio, sem duplicacao e sem perda
# Toda guarda e provada nas duas pontas. ASCII puro, PowerShell 5.1. exit 0 = verde.
$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Rec([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
. (Join-Path $Scripts 'lib\vixradar-cobertura.ps1')
. (Join-Path $Scripts 'lib\vixradar-coletor.ps1')
. (Join-Path $Scripts 'lib\vixradar-watchdog.ps1')
$Tmp = Join-Path $env:TEMP ('vix-recuperacao-test-' + $PID)
New-Item -ItemType Directory -Force $Tmp | Out-Null

# Funcoes do motor (portao de ausencia) extraidas por AST, a mesma tecnica do test-varredura-defeitos.
$tk = $null; $er = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Scripts 'run_vixradar_varredura.ps1'), [ref]$tk, [ref]$er)
foreach ($fn in @('Get-VixCoberturaProviderCapability', 'Test-VixBuscaDegradada', 'ConvertTo-VixFonteEstrutural', 'Resolve-VixCoberturaFamilias', 'Resolve-VixCoberturaWeb', 'Test-VixAusenciaCertificavel')) {
    $d = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true) | Select-Object -First 1
    if ($d) { Invoke-Expression $d.Extent.Text } else { Write-Host ('  info  funcao do motor ausente: ' + $fn) }
}

function New-ColetaFake([string]$Empresa, [object[]]$Evid, [bool]$Disponivel = $true, $Brutos = $null) {
    $pf = @{ F1 = 0; F2 = 0; F3 = 0 }
    foreach ($e in $Evid) { $pf[$e.familia]++ }
    if ($null -eq $Brutos) { $Brutos = [ordered]@{ F1 = 40; F2 = 35; F3 = 20 } }
    return [pscustomobject]@{
        itens_brutos = $Brutos
        empresa = $Empresa; coletado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        queries = @(@{ familia = 'F1'; query = $Empresa }, @{ familia = 'F2'; query = ($Empresa + ' (divida)') }, @{ familia = 'F3'; query = ($Empresa + ' ("fato relevante")') })
        evidencias = $Evid; total = @($Evid).Count; por_familia = $pf; janela_dias = 7; duracao_ms = 10
        erros = $(if ($Disponivel) { @() } else { @('F2: HTTP 503') }); disponivel = $Disponivel
    }
}
$hoje = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
$velha = (Get-Date).ToUniversalTime().AddDays(-6).ToString('yyyy-MM-dd')
$delta = (Get-Date).ToUniversalTime().AddDays(-1).ToString('yyyy-MM-dd')

try {
Write-Host '=== T: triagem deterministica ==='
Assert-Rec (Test-VixMencionaEmissor 'CSN (CSNA3) poe siderurgica alema a venda' 'CSN') 'T1 manchete que cita o emissor conta'
Assert-Rec (-not (Test-VixMencionaEmissor 'Tombo da divida publica tira 1,3 mil milhoes das pensoes' 'Dasa')) 'T2 manchete que NAO cita o emissor e descartada (F2 generica de 13/10)'
$nomeGpa = ('P' + [char]0xE3 + 'o de A' + [char]0xE7 + [char]0xFA + 'car (GPA)')
Assert-Rec (Test-VixMencionaEmissor 'Justica aprova reestruturacao de dividas do GPA, dono do Pao de Acucar' $nomeGpa) 'T3 apelido entre parenteses e nome sem acento casam'
Assert-Rec (Test-VixMencionaEmissor ('Ra' + [char]0xED + 'zen pode atrair investidores') 'Raizen') 'T4 comparacao sem acento nas duas pontas'
Assert-Rec (-not (Test-VixMencionaEmissor 'Mrvz lanca produto' 'MRV Engenharia')) 'T5 palavra inteira: Mrvz nao casa com MRV'
$ev0 = @()
$colQuieta = New-ColetaFake 'Aegea Saneamento' $ev0
$t1 = Get-VixTriagemEmissor -Coleta $colQuieta -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 10 -Ews 0
Assert-Rec ($t1.Classe -eq 'QUIETO') 'T6 sem manchete nova, sem CVM, IA recente = QUIETO'
$colNova = New-ColetaFake 'CSN' @([pscustomobject]@{ familia = 'F1'; data = $hoje; veiculo = 'Money Times'; dominio = 'moneytimes.com.br'; titulo = 'CSN poe siderurgica alema a venda' })
$t2 = Get-VixTriagemEmissor -Coleta $colNova -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 10 -Ews 42
Assert-Rec ($t2.Classe -eq 'MATERIAL' -and @($t2.Novas).Count -eq 1) 'T7 ponta oposta: manchete nova do emissor = MATERIAL (vai para a IA com a pista)'
$colRuido = New-ColetaFake 'Dasa' @([pscustomobject]@{ familia = 'F2'; data = $hoje; veiculo = 'ECO'; dominio = 'eco.sapo.pt'; titulo = 'Tombo da divida publica tira 1,3 mil milhoes as pensoes' })
Assert-Rec ((Get-VixTriagemEmissor -Coleta $colRuido -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 10 -Ews 0).Classe -eq 'QUIETO') 'T8 ruido que nao cita o emissor nao tira o emissor do QUIETO'
$colAntiga = New-ColetaFake 'CSN' @([pscustomobject]@{ familia = 'F1'; data = $velha; veiculo = 'x'; dominio = 'x.com'; titulo = 'CSN antiga' })
Assert-Rec ((Get-VixTriagemEmissor -Coleta $colAntiga -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 10 -Ews 0).Classe -eq 'QUIETO') 'T9 manchete anterior ao delta nao conta'
Assert-Rec ((Get-VixTriagemEmissor -Coleta $colQuieta -DeltaInicio $delta -CvmNovos 2 -HorasDesdeIA 10 -Ews 0).Classe -eq 'MATERIAL') 'T10 documento CVM novo SEMPRE vai para a IA'
$tInd = Get-VixTriagemEmissor -Coleta (New-ColetaFake 'Aegea Saneamento' $ev0 $false) -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 10 -Ews 0
Assert-Rec ($tInd.Classe -eq 'INDISPONIVEL') 'T11 coleta incompleta (HTTP 503) NUNCA certifica ausencia'
Assert-Rec ((Get-VixTriagemEmissor -Coleta $null -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 10 -Ews 0).Classe -eq 'INDISPONIVEL') 'T12 coleta ausente = INDISPONIVEL'
Assert-Rec ((Get-VixTriagemEmissor -Coleta $colQuieta -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 130 -Ews 0).Classe -eq 'MATERIAL') 'T13 revalidacao: 130h sem IA volta para a IA mesmo quieto (limite 120h)'
Assert-Rec ((Get-VixTriagemEmissor -Coleta $colQuieta -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 60 -Ews 55).Classe -eq 'MATERIAL') 'T14 EWS >= 50 revalida a cada 48h (60h = IA)'
Assert-Rec ((Get-VixTriagemEmissor -Coleta $colQuieta -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA $null -Ews 0).Classe -eq 'MATERIAL') 'T15 sem registro de IA nunca e QUIETO (primeira vez passa pela IA)'
Assert-Rec ((Format-VixLeadsTriagem $t2) -match 'CSN poe siderurgica') 'T16 as pistas levam so manchetes novas do emissor'
$colVazia = New-ColetaFake 'Raizen' $ev0 $true ([ordered]@{ F1 = 0; F2 = 0; F3 = 0 })
$tV = Get-VixTriagemEmissor -Coleta $colVazia -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 10 -Ews 0
Assert-Rec ($tV.Classe -eq 'INDISPONIVEL' -and $tV.Motivo -eq 'f1_feed_vazio_suspeito') 'T17 HTTP 200 com feed F1 vazio (throttling) NAO e emissor quieto: vai para a IA'
$colSemBrutos = New-ColetaFake 'Raizen' $ev0
$colSemBrutos.PSObject.Properties.Remove('itens_brutos')
$tSB = Get-VixTriagemEmissor -Coleta $colSemBrutos -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 10 -Ews 0
Assert-Rec ($tSB.Classe -eq 'INDISPONIVEL' -and $tSB.Motivo -eq 'coleta_sem_itens_brutos') 'T18 coleta sem a contagem bruta (cache antigo) nao certifica'
$colJson = (New-ColetaFake 'Aegea Saneamento' $ev0) | ConvertTo-Json -Depth 6 | ConvertFrom-Json
Assert-Rec ((Get-VixTriagemEmissor -Coleta $colJson -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 10 -Ews 0).Classe -eq 'QUIETO') 'T19 ponta oposta: feed com itens e nada novo, lido do cache JSON, e QUIETO'

Write-Host '=== E: encoding do RSS (processo sem console UTF-8, como o Agendador) ==='
# Falha medida em 13/10: a mesma lista dava Raizen MATERIAL no terminal e QUIETO em processo oculto,
# porque o corpo do curl.exe passava pelo stdout e era decodificado pela pagina OEM do console.
$tituloAcento = 'Ra' + [char]0xED + 'zen pode atrair investidores'
$xmlAcento = '<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><item><title>' + $tituloAcento + ' - Fonte</title><pubDate>Tue, 13 Oct 2026 12:00:00 GMT</pubDate><source url="https://exemplo.com.br">Fonte</source></item></channel></rss>'
$bytesUtf8 = (New-Object System.Text.UTF8Encoding($false)).GetBytes($xmlAcento)
$ponta1 = [Text.Encoding]::GetEncoding(850).GetString($bytesUtf8)
$itensRuim = @(ConvertFrom-VixColetorRss $ponta1)
Assert-Rec ($itensRuim.Count -eq 1 -and -not (Test-VixMencionaEmissor $itensRuim[0].titulo 'Raizen')) 'E1 ponta ruim reproduzida: corpo decodificado pela pagina OEM 850 perde o casamento do nome (era o falso-quieto)'
$script:CurlBytes = $bytesUtf8
function curl.exe {
    $a = @($args)
    $i = [Array]::IndexOf($a, '-o')
    if ($i -ge 0) { [IO.File]::WriteAllBytes([string]$a[$i + 1], $script:CurlBytes) }
    return '200'
}
$encAntes = [Console]::OutputEncoding
try { [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(850) } catch { }
$resp = Invoke-VixColetorRss -Query 'Raizen'
try { [Console]::OutputEncoding = $encAntes } catch { }
Assert-Rec ($resp.Status -eq 200) 'E2 status HTTP lido do stdout (ASCII), corpo do arquivo'
$itensBom = @(ConvertFrom-VixColetorRss $resp.Corpo)
Assert-Rec ($itensBom.Count -eq 1 -and $itensBom[0].titulo -like ('*' + [char]0xED + '*') -and (Test-VixMencionaEmissor $itensBom[0].titulo 'Raizen')) 'E3 ponta boa: com console em OEM 850 o titulo sai UTF-8 correto e o nome casa'
$script:CurlBytes = @([byte[]](0xEF, 0xBB, 0xBF) + $bytesUtf8)
$respBom = Invoke-VixColetorRss -Query 'Raizen'
Assert-Rec (@(ConvertFrom-VixColetorRss $respBom.Corpo).Count -eq 1) 'E4 BOM UTF-8 no corpo e removido antes do parse'
Remove-Item function:\curl.exe -ErrorAction SilentlyContinue
Assert-Rec (@(Get-ChildItem -Path ([IO.Path]::GetTempPath()) -Filter 'vixcol_*.xml' -ErrorAction SilentlyContinue).Count -eq 0) 'E5 nenhum arquivo temporario do coletor sobra'

Write-Host '=== P: portao de ausencia ==='
$resQ = [pscustomobject](New-VixResultadoDeterministico -Empresa 'Aegea Saneamento' -Coleta $colQuieta -Triagem $t1 -DeltaInicio $delta)
$cert = Test-VixAusenciaCertificavel $resQ
Assert-Rec ($cert.permitir_sem_eventos -and $cert.motivo -eq 'cobertura_valida') 'P1 o resultado deterministico passa no MESMO gate de ausencia da IA (3 familias, HTTP 200)'
Assert-Rec (@($resQ.fontes_consultadas).Count -eq 3 -and $resQ.sem_eventos -and $resQ._triagem -eq 'QUIETO_DETERMINISTICO') 'P2 tres fontes estruturais e marca de triagem'
$resRuim = [pscustomobject](New-VixResultadoDeterministico -Empresa 'X' -Coleta $colQuieta -Triagem $t1)
foreach ($f in @($resRuim.fontes_consultadas)) { $f.provedor = 'coletor-inventado' }
Assert-Rec (-not (Test-VixAusenciaCertificavel $resRuim).permitir_sem_eventos) 'P3 ponta ruim: provedor fora da allowlist NAO certifica ausencia'
$resSemHttp = [pscustomobject](New-VixResultadoDeterministico -Empresa 'X' -Coleta $colQuieta -Triagem $t1)
foreach ($f in @($resSemHttp.fontes_consultadas)) { $f.status_http = $null }
Assert-Rec (-not (Test-VixAusenciaCertificavel $resSemHttp).permitir_sem_eventos) 'P4 ponta ruim: coletor sem status_http real NAO certifica (nao herda a excecao do codex)'
$resIncomp = [pscustomobject](New-VixResultadoDeterministico -Empresa 'X' -Coleta $colQuieta -Triagem $t1)
$resIncomp.fontes_consultadas = @($resIncomp.fontes_consultadas | Select-Object -First 2)
Assert-Rec (-not (Test-VixAusenciaCertificavel $resIncomp).permitir_sem_eventos) 'P5 ponta ruim: familia faltando NAO certifica'
Assert-Rec (@(Get-VixFontesColetor (New-ColetaFake 'X' $ev0 $false)).Count -eq 0) 'P6 coleta indisponivel nao gera fonte nenhuma'

Write-Host '=== C: cache de coleta e ultima analise de IA ==='
$cp = Join-Path $Tmp 'coleta_cache.json'
Save-VixColetaCache -Path $cp -Coleta $colQuieta
$cc = Get-VixColetaCacheada -Path $cp -Empresa 'Aegea Saneamento' -TtlMin 180
Assert-Rec ($null -ne $cc -and $cc.disponivel -and $cc.por_familia['F1'] -eq 0) 'C1 coleta valida e reaproveitada na mesma janela'
Assert-Rec ($null -eq (Get-VixColetaCacheada -Path $cp -Empresa 'Aegea Saneamento' -TtlMin 180 -Agora ((Get-Date).AddHours(4)))) 'C2 ponta oposta: fora do TTL de 180 min nao reaproveita'
$cpi = Join-Path $Tmp 'coleta_indisp.json'
Save-VixColetaCache -Path $cpi -Coleta (New-ColetaFake 'Aegea Saneamento' $ev0 $false)
Assert-Rec (-not (Test-Path $cpi)) 'C3 coleta indisponivel nunca e gravada no cache (falha nao vira medicao)'
Save-VixColetaCache -Path $cp -Coleta $colNova
Assert-Rec ($null -ne (Get-VixColetaCacheada -Path $cp -Empresa 'CSN') -and $null -ne (Get-VixColetaCacheada -Path $cp -Empresa 'Aegea Saneamento')) 'C4 gravar um emissor nao apaga os outros'
$ui = Join-Path $Tmp 'ultima_ia.json'
Assert-Rec ($null -eq (Get-VixHorasDesdeIA -Path $ui -Empresa 'CSN')) 'C5 sem registro e sem plano = desconhecido (null, nunca recente)'
Assert-Rec ((Get-VixHorasDesdeIA -Path $ui -Empresa 'CSN' -HorasPlano 51.8) -eq 51.8) 'C6 sem registro local usa a semente do plano do Worker'
Set-VixUltimaIA -Path $ui -Empresa 'CSN' -Quando (Get-Date).AddHours(-30)
$h = Get-VixHorasDesdeIA -Path $ui -Empresa 'CSN' -HorasPlano 999
Assert-Rec ($h -gt 29 -and $h -lt 31) 'C7 registro local vence a semente (30h, nao 999h)'
Set-VixUltimaIA -Path $ui -Empresa 'Oi'
Assert-Rec ((Get-VixHorasDesdeIA -Path $ui -Empresa 'CSN') -gt 29) 'C8 gravar um emissor nao apaga o outro'

Write-Host '=== W: watchdog e retry reconhecem entrega PARCIAL ==='
$d0 = Get-Date
$dia = $d0.ToString('yyyy-MM-dd')
function New-LogMatinal([string]$Fim, [int]$Efetivos, [int]$Deferidos) {
    $l = @(); $i = 0
    for ($k = 0; $k -lt $Efetivos; $k++) { $i++; $l += ($dia + ' 10:30:00 OK|E' + $i + '|FULL|NENHUM|0|true|ANALISADO|0') }
    for ($k = 0; $k -lt $Deferidos; $k++) { $i++; $l += ($dia + ' 10:31:00 OK|E' + $i + '|FULL|-|0|true|DEFERIDO|0') }
    $l += ($dia + ' 10:40:00 ' + $Fim)
    return ($l -join "`n")
}
$fimParcial = 'FIM: matinal concluido PARCIAL (pendentes_obrigatorios=17). Total do dia 22/22 (ledger analisados=4 skip=1 deferidos=17). analisados_execucao=4 skip_execucao=1 submit_ok=4 resultado=PARCIAL pendentes_obrigatorios=17'
$fimOk = 'FIM: matinal concluido. Total do dia 22/22 (ledger analisados=21 skip=1 deferidos=0). analisados_execucao=21 skip_execucao=1 submit_ok=21 resultado=OK pendentes_obrigatorios=0'
$jP = Test-VixLedgerEntregueNaJanela -Conteudo (New-LogMatinal $fimParcial 5 17) -DataLog $d0 -JanelaHora 0 -MinimoLedger 12
Assert-Rec ($jP.Entregue -and $jP.Parcial -and $jP.UltimoResultado -eq 'PARCIAL' -and $jP.PendentesObrigatorios -eq 17) 'W1 matinal de 13/10: entregue E parcial, com 17 pendentes (antes parecia entrega completa)'
$jO = Test-VixLedgerEntregueNaJanela -Conteudo (New-LogMatinal $fimOk 22 0) -DataLog $d0 -JanelaHora 0 -MinimoLedger 12
Assert-Rec ($jO.Entregue -and -not $jO.Parcial -and $jO.UltimoResultado -eq 'OK') 'W2 ponta oposta: cobertura completa = entregue e NAO parcial'
$fimLegado = 'FIM: matinal concluido. Total do dia 22/22 (ledger analisados=22 skip=0 deferidos=0). analisados_execucao=22 skip_execucao=0 submit_ok=22'
$jL = Test-VixLedgerEntregueNaJanela -Conteudo (New-LogMatinal $fimLegado 22 0) -DataLog $d0 -JanelaHora 0 -MinimoLedger 12
Assert-Rec ($jL.Entregue -and -not $jL.Parcial -and $jL.UltimoResultado -eq '') 'W3 FIM antigo sem o campo resultado= segue como antes (compatibilidade)'
$jZ = Test-VixLedgerEntregueNaJanela -Conteudo (New-LogMatinal 'FIM: matinal concluido FALHA (sem_analise_efetiva). Total do dia 22/22 (ledger analisados=0 skip=0 deferidos=22). analisados_execucao=0 skip_execucao=0 submit_ok=0 resultado=FALHA pendentes_obrigatorios=22' 0 22) -DataLog $d0 -JanelaHora 0 -MinimoLedger 12
Assert-Rec ((-not $jZ.Entregue) -and $jZ.Parcial) 'W4 FALHA sem analise efetiva continua NAO entregue (o retry relanca como antes)'
$ret = Get-Content -LiteralPath (Join-Path $Scripts 'retry-vixradar.ps1') -Raw -Encoding UTF8
Assert-Rec ($ret -match 'julgamento\.Parcial' -and $ret -match 'ENTREGA_PARCIAL' -and $ret -match "if \(\`$julgamento\.Parcial\)[\s\S]{0,700}exit 0") 'W5 retry registra ENTREGA_PARCIAL e nao relanca (exit 0)'
Assert-Rec ($ret -notmatch "ENTREGA_PARCIAL[^\r\n]*OK:") 'W6 retry nao escreve "OK:" para entrega parcial'

Write-Host '=== M: monitor e Agendador (guardas estruturais) ==='
$mon = Get-Content -LiteralPath (Join-Path $Scripts 'monitor-tasks.ps1') -Raw -Encoding UTF8
Assert-Rec ($mon -match 'code\s+=\s+9010' -and $mon -match 'ENTREGA_PARCIAL') 'M1 monitor tem o codigo 9010 ENTREGA_PARCIAL'
Assert-Rec ($mon -match 'resultado=\(OK\|PARCIAL\|FALHA\)' -and $mon -match 'pendentes_obrigatorios=\(\\d\+\)') 'M2 monitor le resultado e pendentes da ULTIMA linha FIM'
Assert-Rec ($mon -match '\$BenignCodes = @\(0, 267009\)') 'M3 LastTaskResult 10 NAO e benigno: o Agendador marca a task como falha (nao vira OK silencioso)'
$pre = Get-Content -LiteralPath (Join-Path $Scripts 'preflight-and-run.ps1') -Raw -Encoding UTF8
Assert-Rec ($pre -match 'exit \$r\.Exit') 'M4 preflight-and-run repassa o exit do alvo ao Agendador'
Assert-Rec ((Get-Content (Join-Path $Scripts 'run_vixradar_matinal.ps1') -Raw) -match 'exit \$LASTEXITCODE' -and (Get-Content (Join-Path $Scripts 'run_vixradar_noturno_claude.ps1') -Raw) -match 'exit \$LASTEXITCODE') 'M5 wrappers da matinal e noturna repassam o exit'
$mot = Get-Content -LiteralPath (Join-Path $Scripts 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
Assert-Rec ($mot -match "if \(-not \`$DryRun -and \`$exitCode -eq 0 -and \`$__resRot\.Exit -ne 0\) \{ \`$exitCode = \[int\]\`$__resRot\.Exit \}") 'M6 motor so promove PARCIAL a exit 10 quando nao ha erro mais grave (6/7/9 prevalecem)'
Assert-Rec ($mot -match 'TRIAGEM_DISCORDANCIA' -and $mot -match "if \(\`$__tri\.Classe -eq 'QUIETO'\) \{\s+Start-Sleep -Seconds 3") 'M8 QUIETO exige segunda coleta fora do cache e concordante (RSS nao e deterministico)'
Assert-Rec ($mot -match "\`$script:VixTriagemAtiva = \(\(\('' \+ \`$__flagTriagem\)\.Trim\(\) -eq '1'\)") 'M7 triagem deterministica e OPT-IN (so liga com VIXRADAR_TRIAGEM_DETERMINISTICA=1)'

Write-Host '=== G: gate anti-Claude (duas pontas) ==='
$gate = Join-Path $Scripts 'check-claude-free.ps1'
$gd = Join-Path $Tmp 'gate\scripts'; New-Item -ItemType Directory -Force $gd | Out-Null
# Fixtures montadas em tempo de execucao: o gate varre o TEXTO dos .ps1 do repo (nao so codigo
# executado), entao o literal da invocacao nao pode aparecer contiguo neste arquivo.
$cl = 'cla' + 'ude'
$fxVersao = '$v = (& ' + $cl + ' --version 2>&1 | Out-String).Trim()'
$fxInvoca = '$r = "oi" | ' + $cl + ' -p --model x'
$fxMisto = '$v = (& ' + $cl + ' --version 2>&1); $r = "oi" | ' + $cl + ' -p --model x'
Set-Content -LiteralPath (Join-Path $gd 'diag-versao.ps1') -Value $fxVersao -Encoding UTF8
Set-Content -LiteralPath (Join-Path $gd 'diag-invoca.ps1') -Value $fxInvoca -Encoding UTF8
Set-Content -LiteralPath (Join-Path $gd 'diag-misto.ps1') -Value $fxMisto -Encoding UTF8
$gp = Join-Path $Tmp 'gate'
$null = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate -Path (Join-Path $gd 'diag-versao.ps1') -RootPrefix $gp 2>&1; $e1 = $LASTEXITCODE
$null = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate -Path (Join-Path $gd 'diag-invoca.ps1') -RootPrefix $gp 2>&1; $e2 = $LASTEXITCODE
$null = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gate -Path (Join-Path $gd 'diag-misto.ps1') -RootPrefix $gp 2>&1; $e3 = $LASTEXITCODE
Assert-Rec ($e1 -eq 0) ('G1 `claude --version` (so inventario de versao) e aceito, exit=' + $e1)
Assert-Rec ($e2 -ne 0) ('G2 ponta oposta: a invocacao real (modo -p) continua REPROVADA, exit=' + $e2)
Assert-Rec ($e3 -ne 0) ('G3 arquivo que mistura --version com invocacao real continua REPROVADO, exit=' + $e3)

Write-Host '=== R: recuperacao encadeada (3 execucoes, reinicio no meio) ==='
# SIMULACAO das regras da lib (custos ficticios). Cada "execucao" rele a fila do disco, como um
# processo novo do Agendador. A execucao 2 e morta no meio (sem gravar o fim) e a 3 recupera.
$rf = Join-Path $Tmp 'r_fila.json'
$plano = @(1..21 | ForEach-Object { [pscustomobject]@{ empresa = ('Emissor' + $_.ToString('00')); ews_score = (70 - $_) } })
$analisados = @{}; $ia = 0
function Invoke-ExecSim([int]$Exec, [int]$Cap, [int]$Custo, [bool]$MorreNoMeio = $false, [bool]$ProviderCaido = $false) {
    $pend = @($plano | Where-Object { -not $analisados.ContainsKey($_.empresa) })
    $fila = @(Select-VixOrdemComPendentes $pend (Read-VixFilaPendente $rf))
    $acum = [int64]0; $dj = New-VixDisjuntorProvider; $chamadas = 0
    $lotes = @(); for ($i = 0; $i -lt $fila.Count; $i += 4) { $lotes += ,@($fila[$i..([Math]::Min($i + 3, $fila.Count - 1))]) }
    $nL = 0
    foreach ($l in $lotes) {
        $nL++
        if ($dj.aberto) { foreach ($e in $l) { Add-VixFilaPendente -Path $rf -Empresa $e.empresa -Prioridade $e.ews_score -Motivo 'falha_provider' -Rotina ('sim' + $Exec) }; continue }
        $k = Get-VixEmissoresQueCabem -Acum $acum -Cap $Cap -CustoPorEmissor $Custo -Chunk $l.Count
        foreach ($e in @($l | Select-Object -Skip $k)) { Add-VixFilaPendente -Path $rf -Empresa $e.empresa -Prioridade $e.ews_score -Motivo 'cap_efetivo' -Rotina ('sim' + $Exec) }
        $roda = @($l | Select-Object -First $k); if ($roda.Count -eq 0) { continue }
        $chamadas++
        if ($ProviderCaido) { $dj = Update-VixDisjuntorProvider $dj $true 'modelo_indisponivel' $true; $acum += [int64]$Custo * $roda.Count; foreach ($e in $roda) { Add-VixFilaPendente -Path $rf -Empresa $e.empresa -Prioridade $e.ews_score -Motivo 'falha_provider' -Rotina ('sim' + $Exec) }; continue }
        if ($MorreNoMeio -and $nL -eq 2) { return @{ acum = $acum; chamadas = $chamadas; morreu = $true } }   # processo morto: lote 2 sem submit, sem fim
        $acum += [int64]$Custo * $roda.Count
        foreach ($e in $roda) { $analisados[$e.empresa] = 1; $script:ia++; $null = Remove-VixFilaPendente -Path $rf -Empresa $e.empresa }
    }
    return @{ acum = $acum; chamadas = $chamadas; morreu = $false }
}
$r1 = Invoke-ExecSim 1 400000 100000 $false $true     # provedor caido: 1 chamada so
$r2 = Invoke-ExecSim 2 800000 100000 $true $false     # cap comporta 2 lotes; processo morre no lote 2
Assert-Rec ($r1.chamadas -eq 1) 'R1 provedor indisponivel: UMA chamada na execucao, disjuntor impede as demais'
Assert-Rec ($r2.morreu -and $analisados.Count -eq 4) 'R2 processo morto no meio: o que ja foi submetido fica, o lote morto nao conta como analisado'
$r3 = Invoke-ExecSim 3 400000 100000 $false $false    # recupera
$r4 = Invoke-ExecSim 4 400000 100000 $false $false
Assert-Rec ($analisados.Count -le 21 -and (@($analisados.Values | Where-Object { $_ -gt 1 }).Count -eq 0)) 'R4 nenhuma analise duplicada'
Assert-Rec ($script:ia -eq $analisados.Count) 'R5 contagem de IA == emissores distintos analisados (sem dupla contagem)'
$pfFinal = Read-VixFilaPendente $rf
$sobreposicao = @($analisados.Keys | Where-Object { $pfFinal.ContainsKey((ConvertTo-VixChaveEmissor $_)) })
Assert-Rec ($sobreposicao.Count -eq 0) 'R6 emissor analisado nao fica na fila'
Assert-Rec (($r3.acum -le 400000) -and ($r4.acum -le 400000) -and ($r1.acum -le 400000)) 'R7 nenhuma execucao passou do cap'
Assert-Rec ($analisados.Count -gt 8) 'R8 a recuperacao avanca: execucoes 3 e 4 drenam a fila deixada pelas anteriores'
Write-Host ('  info  apos 4 execucoes simuladas: analisados=' + $analisados.Count + '/21 pendentes_na_fila=' + $pfFinal.Count + ' (simulacao, custo ficticio 100000/emissor, cap 400000)')

# Cenario B: fila VAZIA e processo morto no meio, ANTES de qualquer registro. Aqui sobram orfaos de
# verdade: emissores do lote morto e dos lotes que nem chegaram a rodar nao estao analisados nem na
# fila. A recuperacao depende do plano do Worker (que so exclui quem foi analisado) e do ciclo
# seguinte. Prova de que nenhum se perde.
$analisados.Clear(); $script:ia = 0
if (Test-Path -LiteralPath $rf) { [IO.File]::Delete($rf) }
$b1 = Invoke-ExecSim 5 800000 100000 $true $false
$pfB = Read-VixFilaPendente $rf
$orfaos = @($plano | Where-Object { -not $analisados.ContainsKey($_.empresa) -and -not $pfB.ContainsKey((ConvertTo-VixChaveEmissor $_.empresa)) } | ForEach-Object { $_.empresa })
Write-Host ('  info  cenario B apos a morte: analisados=' + $analisados.Count + ' na_fila=' + $pfB.Count + ' orfaos_sem_registro=' + $orfaos.Count)
Assert-Rec ($b1.morreu -and $orfaos.Count -ge 4) 'R9 cenario B realmente deixa orfaos (sem isso R10 nao provaria nada)'
$null = Invoke-ExecSim 6 400000 100000 $false $false
$null = Invoke-ExecSim 7 400000 100000 $false $false
$null = Invoke-ExecSim 8 400000 100000 $false $false
$pfB2 = Read-VixFilaPendente $rf
$perdidos = @($plano | Where-Object { -not $analisados.ContainsKey($_.empresa) -and -not $pfB2.ContainsKey((ConvertTo-VixChaveEmissor $_.empresa)) })
Assert-Rec ($perdidos.Count -eq 0) ('R10 apos 3 execucoes seguintes nenhum emissor esta perdido (analisados=' + $analisados.Count + ' na_fila=' + $pfB2.Count + ')')
Assert-Rec (@($analisados.Values | Where-Object { $_ -gt 1 }).Count -eq 0 -and $script:ia -eq $analisados.Count) 'R11 sem duplicacao no cenario B'

Write-Host '=== Q: fontes do coletor somadas ao resultado da IA (duas pontas) ==='
$resIA = [pscustomobject]@{ classificacao_geral = 'NENHUM'; sem_eventos = $true; cobertura_nota = 'x'; eventos = @(); fontes_consultadas = @() }
Assert-Rec (-not (Test-VixAusenciaCertificavel $resIA).permitir_sem_eventos) 'Q0 resultado da IA sem fontes estruturais NAO certifica (era o INCONCLUSIVO de 13/10)'
$mgQ = Add-VixFontesColetorAoResultado -Res $resIA -Coleta $colQuieta -DeltaInicio $delta -Novas @()
Assert-Rec ($mgQ.Adicionadas -eq 3 -and (Test-VixAusenciaCertificavel $resIA).permitir_sem_eventos) 'Q1 coleta completa e sem fato novo: 3 fontes somadas e o gate de ausencia passa'
$mgQ2 = Add-VixFontesColetorAoResultado -Res $resIA -Coleta $colQuieta -DeltaInicio $delta -Novas @()
Assert-Rec ($mgQ2.Adicionadas -eq 0 -and @($resIA.fontes_consultadas).Count -eq 3) 'Q2 nao duplica consulta ja declarada'
$resIA3 = [pscustomobject]@{ classificacao_geral = 'NENHUM'; sem_eventos = $true; cobertura_nota = 'x'; eventos = @(); fontes_consultadas = @() }
$mgQ3 = Add-VixFontesColetorAoResultado -Res $resIA3 -Coleta (New-ColetaFake 'Aegea Saneamento' $ev0 $false) -DeltaInicio $delta -Novas @()
Assert-Rec ($mgQ3.Adicionadas -eq 0 -and $mgQ3.Motivo -eq 'coleta_incompleta' -and -not (Test-VixAusenciaCertificavel $resIA3).permitir_sem_eventos) 'Q3 coleta incompleta (HTTP 503) nao soma nada e continua sem certificar'
$resIA4 = [pscustomobject]@{ classificacao_geral = 'NENHUM'; sem_eventos = $true; cobertura_nota = 'x'; eventos = @(); fontes_consultadas = @() }
$novasQ = @([pscustomobject]@{ familia = 'F1'; data = $hoje; veiculo = 'x'; dominio = 'x.com'; titulo = 'CSN poe siderurgica alema a venda' })
$mgQ4 = Add-VixFontesColetorAoResultado -Res $resIA4 -Coleta $colNova -DeltaInicio $delta -Novas $novasQ
Assert-Rec ($mgQ4.Divergencia -and $mgQ4.Adicionadas -eq 0 -and -not (Test-VixAusenciaCertificavel $resIA4).permitir_sem_eventos) 'Q4 IA diz sem evento mas o coletor viu manchete nova do emissor: diverge, nao soma, nao certifica'
$resIA5 = [pscustomobject]@{ classificacao_geral = 'RELEVANTE'; sem_eventos = $false; cobertura_nota = 'x'; eventos = @([pscustomobject]@{ titulo = 'e' }); fontes_consultadas = @() }
$mgQ5 = Add-VixFontesColetorAoResultado -Res $resIA5 -Coleta $colNova -DeltaInicio $delta -Novas $novasQ
Assert-Rec (-not $mgQ5.Divergencia -and $mgQ5.Adicionadas -eq 3) 'Q5 IA que reportou evento nao diverge e recebe as fontes do coletor'
Assert-Rec ($mot -match 'Add-VixFontesColetorAoResultado' -and $mot -match 'DIVERGENCIA_IA_COLETOR') 'Q6 motor soma as fontes na via da IA e loga a divergencia'
} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ('RESULTADO: ' + $script:Ok + ' OK, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
