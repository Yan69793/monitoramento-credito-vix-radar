# test-cobertura-analitica.ps1 - COBERTURA-13OUT1 (2026-10-13)
# Prova deterministica, offline e sem token das correcoes de cobertura analitica:
#   A contexto enxuto do Codex (codex debug prompt-input: renderiza, NAO chama modelo)
#   B consumo do Codex lido do JSONL (cache separado, soma de eventos, ausencia != zero)
#   C estimativa por emissor e lote que cabe no cap (caso real de 13/10)
#   D provedor indisponivel: classe e disjuntor
#   E resultado OK / PARCIAL / FALHA
#   F fila pendente persistente (sem duplicar, sem perder, sobrevive a reinicio)
#   G circuito do dia nao soma zero para uso desconhecido da sentinela
#   H simulacao de 3 execucoes com orcamento limitado e falhas injetadas
#   I guardas estruturais no fonte das rotinas
# Toda guarda e provada nas duas pontas (reprova o caso ruim E aceita o bom).
# SIMULACAO != EXECUCAO REAL: a parte H exercita as funcoes da lib com custos ficticios;
# ela nao prova o custo real do Codex com o contexto enxuto, que so a proxima execucao mede.
# ASCII puro, PowerShell 5.1. Saida: exit 0 = tudo verde, 1 = alguma falha.

$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Cob([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
. (Join-Path $Scripts 'lib\vixradar-cobertura.ps1')
. (Join-Path $Scripts 'lib\vixradar-custo.ps1')
$Tmp = Join-Path $env:TEMP ('vix-cobertura-test-' + $PID)
New-Item -ItemType Directory -Force $Tmp | Out-Null

try {
# ------------------------------------------------------------------------------------
Write-Host '=== A: contexto do Codex (codex debug prompt-input, sem chamada de modelo) ==='
$codex = Get-Command codex -ErrorAction SilentlyContinue
if (-not $codex) {
    Write-Host '  info  codex ausente nesta maquina - parte A pulada (nao conta como OK nem FALHA)'
} else {
    Push-Location $env:TEMP
    $antes = (& codex -c features.skip_host_skill_discovery=true debug prompt-input 'X' 2>&1 | Out-String)
    $baseArgs = @(Get-VixCodexArgsBase)
    $depois = (& codex @baseArgs debug prompt-input 'X' 2>&1 | Out-String)
    Pop-Location
    Write-Host ('  info  chars antes=' + $antes.Length + ' depois=' + $depois.Length)
    Assert-Cob ($antes -match '<skills_instructions>') 'A1 ponta ruim: com so skip_host_skill_discovery o catalogo de skills CONTINUA no contexto'
    Assert-Cob ($depois -notmatch '<skills_instructions>') 'A2 ponta boa: Get-VixCodexArgsBase remove o catalogo de skills'
    Assert-Cob ($depois -notmatch '<permissions instructions>' -and $depois -notmatch '<plugins_instructions>' -and $depois -notmatch '<recommended_plugins>' -and $depois -notmatch '<apps_instructions>') 'A3 permissoes, apps e plugins fora do contexto'
    Assert-Cob ($depois.Length -lt ($antes.Length * 0.5)) 'A4 contexto por passo do agente cai mais da metade'
    Assert-Cob ($depois -match '"X"' -or $depois -match 'X') 'A5 o prompt da rotina continua presente'
}
$pre = Get-VixCodexPreambulo
Assert-Cob ($pre -match 'nao execute comandos de shell' -and $pre -match 'task-observer') 'A6 preambulo headless neutraliza o fluxo de skills do AGENTS.md'
Assert-Cob ((@(Get-VixCodexArgsBase) -join ' ') -notmatch 'sandbox|danger|workspace-write|bypass') 'A7 args base nao mexem no sandbox'

# ------------------------------------------------------------------------------------
Write-Host '=== B: consumo do Codex lido do JSONL ==='
$jsonl = @(
    '{"type":"thread.started","thread_id":"t1"}',
    '{"type":"item.completed","item":{"type":"web_search"}}',
    '{"type":"turn.completed","usage":{"input_tokens":442787,"cached_input_tokens":398000,"output_tokens":3168,"reasoning_output_tokens":900}}'
)
$u = Get-VixCodexUsageJsonl $jsonl
Assert-Cob ($u.mensuravel -and $u.input_total -eq 442787 -and $u.cached -eq 398000 -and $u.output -eq 3168) 'B1 cached_input_tokens lido (o campo que o Codex publica)'
$p = ConvertTo-VixParcelasCodex $u
Assert-Cob ($p.trabalho -eq 445955) 'B2 regua do cap preservada: trabalho = input total + output (445955, igual ao contado em 13/10)'
Assert-Cob ($p.codex_cached -eq 398000 -and $p.cache_read -eq 0) 'B3 cache vai em campo de medicao, sem afrouxar o cap'
$u2 = Get-VixCodexUsageJsonl @('{"type":"turn.completed","usage":{"input_tokens":100,"output_tokens":10}}', '{"type":"turn.completed","usage":{"input_tokens":50,"cached_input_tokens":20,"output_tokens":5}}')
Assert-Cob ($u2.eventos -eq 2 -and $u2.input_total -eq 150 -and $u2.output -eq 15 -and $u2.cached -eq 20) 'B4 varios turnos sao somados (antes so o primeiro contava)'
$u3 = Get-VixCodexUsageJsonl @('{"type":"turn.completed"}', 'texto solto', '')
Assert-Cob ((-not $u3.mensuravel) -and $null -eq (ConvertTo-VixParcelasCodex $u3)) 'B5 sem usage = NAO mensuravel, nunca zero'
$u4 = Get-VixCodexUsageJsonl @('{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":99,"output_tokens":1}}')
Assert-Cob (-not $u4.mensuravel) 'B6 usage incoerente (cache > input) e rejeitado'
# Ponta ruim: a versao anterior do motor lia so cache_read_input_tokens e devolvia o 1o evento.
function Get-VixCodexUsageProbeAntigo($Linhas) {
    foreach ($linha in @($Linhas)) { try { $o = ('' + $linha).Trim() | ConvertFrom-Json; if ($o.usage -and $null -ne $o.usage.input_tokens) { return @{ cache_read = [int64]$o.usage.cache_read_input_tokens; input = [int64]$o.usage.input_tokens } } } catch { } }
    return $null
}
$antigo = Get-VixCodexUsageProbeAntigo $jsonl
Assert-Cob ($antigo.cache_read -eq 0) 'B7 ponta ruim reproduzida: o parser antigo perdia o cache (cache_read=0 em 13/10)'

# Motor: a funcao real extraida do run_vixradar_varredura.ps1
$tk = $null; $er = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Scripts 'run_vixradar_varredura.ps1'), [ref]$tk, [ref]$er)
$def = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-VixCodexUsageProbe' }, $true) | Select-Object -First 1
Invoke-Expression $def.Extent.Text
$pm = Get-VixCodexUsageProbe $jsonl
Assert-Cob ($pm.mensuravel -and $pm.parcelas.input -eq 442787 -and $pm.parcelas.codex_cached -eq 398000) 'B8 motor usa a leitura nova'

# ------------------------------------------------------------------------------------
Write-Host '=== C: estimativa por emissor e quantos cabem no cap (caso de 13/10) ==='
$estAntigo = 15000 + 4 * 11500
Assert-Cob ($estAntigo -eq 61000 -and (0 + $estAntigo) -lt 400000) 'C1 ponta ruim: a estimativa antiga (61.000, a do log de 13/10) deixava passar o lote de 445.955 contra cap 400.000'
$cpe = Get-VixCustoPorEmissor -ObservadosExecucao @() -Historico @() -Default $script:VixCustoEmissorDefaultCodex -Piso 26500
$k = Get-VixEmissoresQueCabem -Acum 0 -Cap 400000 -CustoPorEmissor $cpe.Custo -Chunk 4
Assert-Cob ($cpe.Custo -eq 250000 -and $k -eq 1) 'C2 sem historico: default Codex 250k/emissor, cabe 1 de 4 no cap 400k'
$cpe2 = Get-VixCustoPorEmissor -ObservadosExecucao @(111489) -Historico @() -Default 250000 -Piso 26500
$k2 = Get-VixEmissoresQueCabem -Acum 0 -Cap 400000 -CustoPorEmissor $cpe2.Custo -Chunk 4
Assert-Cob ($cpe2.Fonte -eq 'observado_execucao' -and $k2 -eq 3 -and ($k2 * 111489) -le 400000) 'C3 com o custo medido de 13/10 (111.489/emissor) cabem 3, sem passar o cap'
$cpe3 = Get-VixCustoPorEmissor -ObservadosExecucao @(50000, 90000) -Historico @(10) -Default 250000
Assert-Cob ($cpe3.Custo -eq 90000) 'C4 observado na execucao usa o MAXIMO, nunca a media'
$cpe4 = Get-VixCustoPorEmissor -ObservadosExecucao @() -Historico @(60000, 80000, 300000) -Default 250000
Assert-Cob ($cpe4.Custo -eq 80000 -and $cpe4.Fonte -like 'historico_mediana*') 'C5 sem medicao propria: mediana do historico do provedor'
$cpe5 = Get-VixCustoPorEmissor -ObservadosExecucao @() -Historico @(1000) -Default 250000 -Piso 26500
Assert-Cob ($cpe5.Custo -eq 250000) 'C6 historico com 1 amostra nao basta, fica o default'
$cpe6 = Get-VixCustoPorEmissor -ObservadosExecucao @(100) -Historico @() -Default 1 -Piso 26500
Assert-Cob ($cpe6.Custo -eq 26500) 'C7 piso do perfil: provedor barato nao afrouxa a estimativa antiga'
Assert-Cob ((Get-VixEmissoresQueCabem -Acum 399999 -Cap 400000 -CustoPorEmissor 1000 -Chunk 4) -eq 0) 'C8 sobra menor que 1 emissor = 0 (lote inteiro deferido)'
Assert-Cob ((Get-VixEmissoresQueCabem -Acum 500000 -Cap 400000 -CustoPorEmissor 1 -Chunk 4) -eq 0) 'C9 acum acima do cap = 0'
# Historico: so metrics do MESMO provedor, com campo provider
$mdir = Join-Path $Tmp 'metrics'; New-Item -ItemType Directory -Force $mdir | Out-Null
$hoje = (Get-Date).ToString('yyyyMMdd')
@{ provider = 'codex'; lotes_detalhe = @(@{ emissores = 2; trabalho = 120000 }, @{ emissores = 0; trabalho = 9999 }, @{ emissores = 4; trabalho = 'NAO_MENSURAVEL' }) } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $mdir ('matinal_metrics_' + $hoje + '.json')) -Encoding UTF8
@{ lotes_detalhe = @(@{ emissores = 4; trabalho = 1000000 }) } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $mdir ('noturno_metrics_' + $hoje + '.json')) -Encoding UTF8
@{ provider = 'openrouter'; lotes_detalhe = @(@{ emissores = 1; trabalho = 5 }) } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $mdir ('noturno_metrics_' + $hoje + '_dryrun_1.json')) -Encoding UTF8
$h = @(Get-VixHistoricoCustoPorEmissor -LogDir $mdir -Provider 'codex' -Dias 7)
Assert-Cob ($h.Count -eq 1 -and $h[0] -eq 60000) 'C10 historico ignora legado sem provider, outro provedor, lote de falha e trabalho nao numerico'

# ------------------------------------------------------------------------------------
Write-Host '=== D: provedor/modelo indisponivel ==='
$c1 = Get-VixClasseFalhaProvider 'Modelo claude-sonnet-4-6 indisponivel nesta sessao.'
Assert-Cob ($c1.Classe -eq 'modelo_indisponivel' -and $c1.SemPerspectiva) 'D1 modelo indisponivel = sem perspectiva'
$c2 = Get-VixClasseFalhaProvider 'error: The model `gpt-9` does not exist or you do not have access'
Assert-Cob ($c2.Classe -eq 'modelo_indisponivel') 'D2 model does not exist = modelo_indisponivel'
$c3 = Get-VixClasseFalhaProvider "You've hit your usage limit. Try again later."
Assert-Cob ($c3.Classe -eq 'cota' -and $c3.SemPerspectiva) 'D3 limite de uso = cota, sem perspectiva'
$c4 = Get-VixClasseFalhaProvider 'stream disconnected before completion: connection reset'
Assert-Cob ($c4.Classe -eq 'transitoria' -and -not $c4.SemPerspectiva) 'D4 queda de conexao = transitoria (pode tentar o proximo lote)'
$dj = New-VixDisjuntorProvider
$dj = Update-VixDisjuntorProvider $dj $true 'transitoria' $false
Assert-Cob (-not $dj.aberto) 'D5 uma falha transitoria nao abre o disjuntor'
$dj = Update-VixDisjuntorProvider $dj $false
$dj = Update-VixDisjuntorProvider $dj $true 'transitoria' $false
Assert-Cob (-not $dj.aberto) 'D6 sucesso entre falhas zera a contagem'
$dj = Update-VixDisjuntorProvider $dj $true 'transitoria' $false
Assert-Cob ($dj.aberto -and $dj.motivo -like 'falhas_consecutivas*') 'D7 duas transitorias seguidas abrem o disjuntor'
$dj2 = Update-VixDisjuntorProvider (New-VixDisjuntorProvider) $true 'modelo_indisponivel' $true
Assert-Cob ($dj2.aberto -and $dj2.motivo -eq 'sem_perspectiva:modelo_indisponivel') 'D8 falha sem perspectiva abre na primeira'

# ------------------------------------------------------------------------------------
Write-Host '=== E: resultado OK / PARCIAL / FALHA ==='
$r1 = Get-VixResultadoRotina -DryRun $false -TrabalhoZero $false -PlanoTotal 22 -Analisados 4 -Skips 1 -PendentesObrigatorios 17 -Erros 0
Assert-Cob ($r1.Resultado -eq 'PARCIAL' -and $r1.Exit -eq 10) 'E1 matinal de 13/10 (4 analisados, 17 deferidos, 0 erro) = PARCIAL exit 10 (antes OK)'
$r2 = Get-VixResultadoRotina -DryRun $false -TrabalhoZero $false -PlanoTotal 22 -Analisados 21 -Skips 1 -PendentesObrigatorios 0 -Erros 0
Assert-Cob ($r2.Resultado -eq 'OK' -and $r2.Exit -eq 0) 'E2 cobertura completa = OK exit 0'
$r3 = Get-VixResultadoRotina -DryRun $false -TrabalhoZero $false -PlanoTotal 22 -Analisados 0 -Skips 0 -PendentesObrigatorios 22 -Erros 0
Assert-Cob ($r3.Resultado -eq 'FALHA') 'E3 plano com trabalho e zero analise efetiva = FALHA'
$r4 = Get-VixResultadoRotina -DryRun $false -TrabalhoZero $true -PlanoTotal 22 -Analisados 22 -Skips 0 -PendentesObrigatorios 0 -Erros 0
Assert-Cob ($r4.Resultado -eq 'FALHA' -and $r4.Exit -eq 9) 'E4 trabalho zero (FIMFALSO1) = FALHA exit 9'
$r5 = Get-VixResultadoRotina -DryRun $false -TrabalhoZero $false -PlanoTotal 0 -Analisados 0 -Skips 0 -PendentesObrigatorios 0 -Erros 0
Assert-Cob ($r5.Resultado -eq 'OK') 'E5 plano vazio (nada a fazer) = OK'
$r6 = Get-VixResultadoRotina -DryRun $true -TrabalhoZero $false -PlanoTotal 22 -Analisados 0 -Skips 0 -PendentesObrigatorios 22 -Erros 0
Assert-Cob ($r6.Resultado -eq 'DRYRUN' -and $r6.Exit -eq 0) 'E6 dry-run nao vira OK nem FALHA'

# ------------------------------------------------------------------------------------
Write-Host '=== F: fila pendente persistente ==='
$fp = Join-Path $Tmp 'fila_pendente_cobertura.json'
$def13 = @('Light','CSN','Aegea Saneamento','Simpar','Dasa','Hapvida','Cosan','MRV Engenharia','Energisa',"Rede D'Or",'Cury Construtora','Klabin','Marfrig','Nexa Resources','Itausa','Vamos','Minerva Foods')
$ews13 = @(50,42,40,38,38,36,36,36,10,3,2,1,1,1,0,0,0)
for ($i = 0; $i -lt $def13.Count; $i++) { Add-VixFilaPendente -Path $fp -Empresa $def13[$i] -Prioridade $ews13[$i] -Motivo 'cap_efetivo' -Rotina 'matinal' -Tier 'FULL' -SubmitRegistrado $true }
$f1 = Read-VixFilaPendente $fp
Assert-Cob ($f1.Count -eq 17) 'F1 os 17 deferidos de 13/10 persistidos'
Add-VixFilaPendente -Path $fp -Empresa 'CSN' -Prioridade 10 -Motivo 'falha_provider' -Rotina 'sentinela' -SubmitRegistrado $false
Add-VixFilaPendente -Path $fp -Empresa 'csn ' -Prioridade 10 -Motivo 'falha_provider' -Rotina 'sentinela' -SubmitRegistrado $false
$f2 = Read-VixFilaPendente $fp
$csn = $f2[(ConvertTo-VixChaveEmissor 'CSN')]
Assert-Cob ($f2.Count -eq 17 -and $csn.tentativas -eq 3 -and $csn.prioridade -eq 42 -and $csn.motivo -eq 'falha_provider') 'F2 reinsercao nao duplica: soma tentativa, prioridade nunca cai, motivo atualiza'
$ord = @(Get-VixFilaPendenteOrdenada $f2)
Assert-Cob ($ord[0].empresa -eq 'Light' -and $ord[1].empresa -eq 'CSN') 'F3 ordem por prioridade (EWS) e depois antiguidade'
Assert-Cob (Remove-VixFilaPendente -Path $fp -Empresa 'Light') 'F4 analise efetiva remove a pendencia'
Assert-Cob (-not (Remove-VixFilaPendente -Path $fp -Empresa 'Light')) 'F5 remover de novo devolve false (idempotente)'
$f3 = Read-VixFilaPendente $fp
Assert-Cob ($f3.Count -eq 16 -and -not $f3.ContainsKey('light')) 'F6 estado relido do disco (sobrevive a reinicio)'
$plano = @(@{ empresa = 'Kora Saude' }, @{ empresa = 'Oi' }, @{ empresa = 'Dasa' }, @{ empresa = 'CSN' }, @{ empresa = 'Oi' }, @{ empresa = 'Vale' })
$reord = @(Select-VixOrdemComPendentes $plano $f3)
$nomes = @($reord | ForEach-Object { $_.empresa })
Assert-Cob (($nomes -join ',') -eq 'CSN,Dasa,Kora Saude,Oi,Vale') 'F7 pendentes primeiro (por prioridade), resto na ordem original, sem duplicar e sem perder'
Set-Content -Path $fp -Value '{ isto nao e json' -Encoding UTF8
$lancou = $false
try { $null = Read-VixFilaPendente $fp } catch { $lancou = $true }
Assert-Cob $lancou 'F8 fila corrompida LANCA (nunca vira fila vazia silenciosa)'
Remove-Item $fp -Force
Assert-Cob ((Read-VixFilaPendente $fp).Count -eq 0) 'F9 fila ausente = vazia (primeira execucao)'

# ------------------------------------------------------------------------------------
Write-Host '=== G: circuito do dia e uso desconhecido da sentinela ==='
$gdir = Join-Path $Tmp 'g'; New-Item -ItemType Directory -Force $gdir | Out-Null
$tag = '20991231'
$cfg = @{ TETO_DIA = 2600000; RESERVA_VERIFICACAO = 150000; RESERVA_NOTURNO = 700000; MARGEM_MINIMA = 100000 }
$sl = Join-Path $gdir ('vixradar-sentinela_' + $tag + '.log')
Set-Content -Path $sl -Encoding UTF8 -Value '2099-12-31 13:58:38 FIM: sentinela resultado=OK. tokens=0 analisados=4 submit_fail=0 deferidos=4 sem_resultado=0 excedente_worker=0 buscas=13 backlog=True lotes_ok=1 lotes_falha_provider=0 tokens_falha_provider=0'
$g1 = Get-VixCustoDia $gdir $tag $cfg
Assert-Cob ($g1.mensuravel -and $g1.total_consumido -eq 0) 'G1 ponta ruim reproduzida: o FIM antigo (13/10) somava ZERO e o dia seguia mensuravel'
Add-Content -Path $sl -Encoding UTF8 -Value '2099-12-31 14:28:43 FIM: sentinela resultado=PARCIAL. tokens=0 analisados=4 submit_fail=0 deferidos=1 sem_resultado=0 excedente_worker=0 buscas=18 backlog=True lotes_ok=1 lotes_falha_provider=0 tokens_falha_provider=0 uso_desconhecido=1 tokens_estimados_falha=0 provider=codex disjuntor_provider=fechado'
$g2 = Get-VixCustoDia $gdir $tag $cfg
Assert-Cob ((-not $g2.mensuravel) -and ($g2.nao_mensuraveis -contains 'sentinela:uso_desconhecido')) 'G2 FIM novo com uso_desconhecido=1 deixa o dia NAO_MENSURAVEL'
Assert-Cob ((Get-VixCapEfetivo 400000 $g2 $cfg 850000) -eq 0 -and (Get-VixDisponivelSentinela $g2 $cfg) -eq 0) 'G3 cap e orcamento da sentinela vao a zero (fail-closed), nunca para o cap proprio'
Set-Content -Path $sl -Encoding UTF8 -Value '2099-12-31 14:28:43 FIM: sentinela resultado=OK. tokens=210000 analisados=2 submit_fail=0 deferidos=0 sem_resultado=0 excedente_worker=0 buscas=8 backlog=False lotes_ok=1 lotes_falha_provider=1 tokens_falha_provider=250000 uso_desconhecido=0 tokens_estimados_falha=250000 provider=codex disjuntor_provider=fechado'
$g4 = Get-VixCustoDia $gdir $tag $cfg
Assert-Cob ($g4.mensuravel -and $g4.total_trabalho -eq 210000 -and $g4.total_consumido -eq 460000) 'G4 ponta boa: uso medido conta, falha estimada entra no CONSUMO (nunca zero), dia segue mensuravel'

# ------------------------------------------------------------------------------------
Write-Host '=== H: simulacao de 3 execucoes (orcamento limitado, falhas injetadas) ==='
# SIMULACAO das regras da lib, nao do motor real. Custos ficticios e deterministicos.
$hfila = Join-Path $Tmp 'h_fila.json'
$plano22 = @()
for ($i = 1; $i -le 22; $i++) { $plano22 += [pscustomobject]@{ empresa = ('Emissor' + $i.ToString('00')); ews_score = (60 - $i) } }
$custoReal = 90000          # custo real por emissor nesta simulacao (abaixo do default de 250k)
$capExec = 400000
$analisadosGlobal = @{}
$consumoPorExec = @()
$chamadasAposDisjuntor = 0
$analisadosExec1 = 0
for ($exec = 1; $exec -le 3; $exec++) {
    # O plano do Worker nao devolve quem ja foi analisado (SKIP por scan recente); a fila
    # pendente local reordena o que sobrou, com prioridade.
    $planoExec = @($plano22 | Where-Object { -not $analisadosGlobal.ContainsKey($_.empresa) })
    $fila = @(Select-VixOrdemComPendentes $planoExec (Read-VixFilaPendente $hfila))
    $disjuntorAbriuNoLote = 0
    $acum = [int64]0; $obs = New-Object System.Collections.Generic.List[object]; $dj = New-VixDisjuntorProvider
    $lotes = @(); for ($i = 0; $i -lt $fila.Count; $i += 4) { $lotes += ,@($fila[$i..([Math]::Min($i + 3, $fila.Count - 1))]) }
    $nLote = 0
    foreach ($lote in $lotes) {
        $nLote++
        if ($dj.aberto) { foreach ($e in $lote) { Add-VixFilaPendente -Path $hfila -Empresa $e.empresa -Prioridade $e.ews_score -Motivo 'falha_provider' -Rotina ('sim' + $exec) }; continue }
        if ($disjuntorAbriuNoLote -gt 0) { $chamadasAposDisjuntor++ }
        $cpe = Get-VixCustoPorEmissor -ObservadosExecucao $obs.ToArray() -Historico @() -Default 250000 -Piso 26500
        $kk = Get-VixEmissoresQueCabem -Acum $acum -Cap $capExec -CustoPorEmissor $cpe.Custo -Chunk $lote.Count
        $roda = @($lote | Select-Object -First $kk); $fora = @($lote | Select-Object -Skip $kk)
        foreach ($e in $fora) { Add-VixFilaPendente -Path $hfila -Empresa $e.empresa -Prioridade $e.ews_score -Motivo 'cap_efetivo' -Rotina ('sim' + $exec) }
        if ($roda.Count -eq 0) { continue }
        # Falha injetada: execucao 1, lote 2 = modelo indisponivel (sem usage publicada).
        if ($exec -eq 1 -and $nLote -eq 2) {
            $acum += [int64]$cpe.Custo * $roda.Count     # cobrado por estimativa, nunca zero
            $dj = Update-VixDisjuntorProvider $dj $true 'modelo_indisponivel' $true
            $disjuntorAbriuNoLote = $nLote
            foreach ($e in $roda) { Add-VixFilaPendente -Path $hfila -Empresa $e.empresa -Prioridade $e.ews_score -Motivo 'falha_provider' -Rotina ('sim' + $exec) }
            continue
        }
        $gasto = [int64]$custoReal * $roda.Count
        $acum += $gasto; $obs.Add([int64]($gasto / $roda.Count))
        if ($exec -eq 1) { $analisadosExec1 += $roda.Count }
        foreach ($e in $roda) {
            if ($analisadosGlobal.ContainsKey($e.empresa)) { $analisadosGlobal[$e.empresa]++ } else { $analisadosGlobal[$e.empresa] = 1 }
            $null = Remove-VixFilaPendente -Path $hfila -Empresa $e.empresa
        }
    }
    $consumoPorExec += $acum
    $pend = Read-VixFilaPendente $hfila
    Write-Host ('  info  execucao ' + $exec + ': consumo=' + $acum + ' cap=' + $capExec + ' analisados_total=' + $analisadosGlobal.Count + ' pendentes=' + $pend.Count)
}
$pendFinal = Read-VixFilaPendente $hfila
$todos = @($plano22 | ForEach-Object { $_.empresa })
$cobertos = @($todos | Where-Object { $analisadosGlobal.ContainsKey($_) -or $pendFinal.ContainsKey((ConvertTo-VixChaveEmissor $_)) })
Assert-Cob (@($consumoPorExec | Where-Object { $_ -gt $capExec }).Count -eq 0) 'H1 nenhuma execucao passou do cap (custo real <= estimativa)'
Assert-Cob ($chamadasAposDisjuntor -eq 0 -and $analisadosExec1 -eq 1) 'H2 depois de modelo indisponivel nenhuma chamada nova na mesma execucao (exec 1 analisou so o lote 1)'
Assert-Cob ($cobertos.Count -eq 22) 'H3 nenhum emissor perdido: todo emissor do plano foi analisado ou esta na fila'
Assert-Cob (@($analisadosGlobal.Values | Where-Object { $_ -gt 1 }).Count -eq 0) 'H4 nenhum emissor analisado duas vezes (sem duplicacao)'
$sobreposicao = @($analisadosGlobal.Keys | Where-Object { $pendFinal.ContainsKey((ConvertTo-VixChaveEmissor $_)) })
Assert-Cob ($sobreposicao.Count -eq 0) 'H5 nenhum emissor analisado continua na fila (estado coerente)'
Assert-Cob ($pendFinal.Count -lt 22 -and $analisadosGlobal.Count -gt $analisadosExec1) 'H6 a fila drena entre execucoes (recuperacao automatica)'
Write-Host ('  info  apos 3 execucoes: analisados=' + $analisadosGlobal.Count + ' pendentes=' + $pendFinal.Count + ' (simulacao; nao e medicao de producao)')

# ------------------------------------------------------------------------------------
Write-Host '=== I: guardas estruturais no fonte ==='
$var = Get-Content -LiteralPath (Join-Path $Scripts 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
$sen = Get-Content -LiteralPath (Join-Path $Scripts 'run_vixradar_sentinela.ps1') -Raw -Encoding UTF8
Assert-Cob ($var -match 'codex @__codexBase --search exec' -and $var -notmatch "codex -c features\.skip_host_skill_discovery=true --search") 'I1 motor invoca o Codex pelos args enxutos'
Assert-Cob ($var -notmatch 'acum inalterado''') 'I2 motor nao trata mais token desconhecido como "acum inalterado"'
Assert-Cob ($var -match 'Get-VixResultadoRotina' -and $var -match "' resultado=' \+ \`$__resPre\.Resultado") 'I3 FIM e ROTINA_RESUMO da varredura usam a regra unica de resultado'
Assert-Cob ($var -match 'Get-VixEmissoresQueCabem' -and $var -match 'CAP_LOTE_REDUZIDO') 'I4 pre-lote do motor usa custo por emissor e encolhe o lote'
Assert-Cob ($var -match 'DISJUNTOR_PROVIDER' -and $var -match 'motivo = ''falha_provider''') 'I5 motor tem disjuntor de provedor e defere com motivo proprio'
Assert-Cob ($sen -match 'Get-VixCodexUsageJsonl' -and $sen -match "uso_desconhecido=' \+ \`$lotesUsoDesconhecido") 'I6 sentinela le o usage do JSONL e declara uso_desconhecido no FIM'
Assert-Cob ($sen -match "\`$deferidos -gt 0" -and $sen -match '\$resultadoFim = ''PARCIAL''') 'I7 sentinela com deferidos fecha PARCIAL'
Assert-Cob ($sen -match "modeloPrompt = 'codex-subscription'") 'I8 sentinela nao manda mais rotulo Claude ao Codex'
Assert-Cob ($sen -match 'Get-VixDecisaoCapSentinela' -and $sen -match 'CAP_CALIBRACAO' -and $sen -match 'CAP_PREVENTIVO' -and $sen -notmatch 'Get-VixDefaultLimitadoAoCap') 'I9 sentinela decide pelo controle preventivo e nao mascara a estimativa'

Write-Host '=== J: estimativa honesta 250k contra cap 120k da Sentinela (duas pontas) ==='
$cJ = Get-VixCustoPorEmissor -ObservadosExecucao @() -Historico @() -Default 250000
Assert-Cob ($cJ.Custo -eq 250000 -and $cJ.Fonte -eq 'default') 'J0 a estimativa nao e limitada nem reescrita (250000, fonte default)'
$dJ = Get-VixDecisaoCapSentinela -Acum 0 -Cap 120000 -CustoEstimado 250000 -Fonte 'default' -Chunk 4 -DisponivelDia 900000 -CalibracaoJaFeita $false
Assert-Cob ($dJ.Cabem -eq 1 -and $dJ.Calibracao) 'J1 sem medicao, execucao zerada e dia com folga: 1 emissor de calibracao'
$dJ2 = Get-VixDecisaoCapSentinela -Acum 0 -Cap 120000 -CustoEstimado 250000 -Fonte 'default' -Chunk 4 -DisponivelDia 900000 -CalibracaoJaFeita $true
Assert-Cob ($dJ2.Cabem -eq 0 -and $dJ2.Motivo -eq 'calibracao_ja_feita_hoje') 'J2 segunda calibracao no mesmo dia e barrada'
$dJ3 = Get-VixDecisaoCapSentinela -Acum 0 -Cap 120000 -CustoEstimado 250000 -Fonte 'default' -Chunk 4 -DisponivelDia 200000 -CalibracaoJaFeita $false
Assert-Cob ($dJ3.Cabem -eq 0 -and $dJ3.Motivo -eq 'orcamento_dia_menor_que_estimativa') 'J3 orcamento do dia menor que a estimativa barra a calibracao'
$dJ4 = Get-VixDecisaoCapSentinela -Acum 0 -Cap 120000 -CustoEstimado 250000 -Fonte 'default' -Chunk 4 -DisponivelDia -1 -CalibracaoJaFeita $false
Assert-Cob ($dJ4.Cabem -eq 0 -and $dJ4.Motivo -eq 'orcamento_dia_desconhecido') 'J4 orcamento do dia desconhecido barra (fail-closed)'
$dJ5 = Get-VixDecisaoCapSentinela -Acum 111000 -Cap 120000 -CustoEstimado 111000 -Fonte 'observado_execucao' -Chunk 3 -DisponivelDia 900000 -CalibracaoJaFeita $false
Assert-Cob ($dJ5.Cabem -eq 0 -and -not $dJ5.Calibracao) 'J5 depois de medir 111k o cap de 120k fecha, sem excecao'
$dJ6 = Get-VixDecisaoCapSentinela -Acum 0 -Cap 120000 -CustoEstimado 150000 -Fonte 'historico_mediana_n3' -Chunk 3 -DisponivelDia 900000 -CalibracaoJaFeita $false
Assert-Cob ($dJ6.Cabem -eq 0 -and $dJ6.Motivo -eq 'custo_medido_nao_cabe_no_cap') 'J6 custo historico medido acima do cap nao ganha excecao'
$dJ7 = Get-VixDecisaoCapSentinela -Acum 0 -Cap 120000 -CustoEstimado 111000 -Fonte 'historico_mediana_n3' -Chunk 3 -DisponivelDia 900000 -CalibracaoJaFeita $false
Assert-Cob ($dJ7.Cabem -eq 1 -and -not $dJ7.Calibracao) 'J7 custo medido que cabe roda normal, sem rotular como calibracao'
$dJ8 = Get-VixDecisaoCapSentinela -Acum 5000 -Cap 120000 -CustoEstimado 250000 -Fonte 'default' -Chunk 3 -DisponivelDia 900000 -CalibracaoJaFeita $false
Assert-Cob ($dJ8.Cabem -eq 0) 'J8 execucao que ja gastou nao recebe calibracao'
Assert-Cob ((Get-VixDecisaoCapSentinela -Acum 0 -Cap 2000000 -CustoEstimado 250000 -Fonte 'default' -Chunk 4 -DisponivelDia 900000).Cabem -eq 4) 'J9 cap amplo roda o lote inteiro'

Write-Host '=== K: triagem, evento critico e falso negativo (duas pontas) ==='
$hojeK = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'); $deltaK = (Get-Date).ToUniversalTime().AddDays(-1).ToString('yyyy-MM-dd')
function New-ColK($Emp, $Evid) { [pscustomobject]@{ empresa = $Emp; evidencias = $Evid; total = @($Evid).Count; por_familia = @{ F1 = 5; F2 = 1; F3 = 1 }; itens_brutos = @{ F1 = 5; F2 = 3; F3 = 2 }; janela_dias = 2; disponivel = $true; erros = @() } }
$critSemNome = New-ColK 'Grupo Exemplo SA' @([pscustomobject]@{ familia = 'F1'; data = $hojeK; veiculo = 'x'; dominio = 'x.com'; titulo = 'Holding controladora pede recuperacao judicial' })
Assert-Cob ((Get-VixTriagemEmissor -Coleta $critSemNome -DeltaInicio $deltaK -HorasDesdeIA 10 -Ews 0).Classe -eq 'MATERIAL') 'K1 recuperacao judicial em F1 sem citar o nome vai para a IA (nao vira QUIETO)'
$ruidoK = New-ColK 'Grupo Exemplo SA' @([pscustomobject]@{ familia = 'F1'; data = $hojeK; veiculo = 'x'; dominio = 'x.com'; titulo = 'Time local vence campeonato' })
Assert-Cob ((Get-VixTriagemEmissor -Coleta $ruidoK -DeltaInicio $deltaK -HorasDesdeIA 10 -Ews 0).Classe -eq 'QUIETO') 'K2 ponta oposta: ruido sem termo critico segue QUIETO'
$critF2 = New-ColK 'Dasa' @([pscustomobject]@{ familia = 'F2'; data = $hojeK; veiculo = 'x'; dominio = 'x.com'; titulo = 'Pais anuncia default em divida soberana' })
Assert-Cob ((Get-VixTriagemEmissor -Coleta $critF2 -DeltaInicio $deltaK -HorasDesdeIA 10 -Ews 0).Classe -eq 'QUIETO') 'K3 termo critico em F2 sem citar o emissor nao dispara (evita ruido macro)'
$critVelho = New-ColK 'Grupo Exemplo SA' @([pscustomobject]@{ familia = 'F1'; data = (Get-Date).ToUniversalTime().AddDays(-6).ToString('yyyy-MM-dd'); veiculo = 'x'; dominio = 'x.com'; titulo = 'Pede recuperacao judicial' })
Assert-Cob ((Get-VixTriagemEmissor -Coleta $critVelho -DeltaInicio $deltaK -HorasDesdeIA 10 -Ews 0).Classe -eq 'QUIETO') 'K4 critico anterior ao delta nao reabre'
Assert-Cob ((Get-VixTriagemEmissor -Coleta $ruidoK -DeltaInicio $deltaK -CvmNovos 1 -HorasDesdeIA 10 -Ews 0).Classe -eq 'MATERIAL') 'K5 CVM novo sempre MATERIAL'
Assert-Cob ((Get-VixTriagemEmissor -Coleta $ruidoK -DeltaInicio $deltaK -HorasDesdeIA 10 -Ews 60).Classe -eq 'QUIETO' -and (Get-VixTriagemEmissor -Coleta $ruidoK -DeltaInicio $deltaK -HorasDesdeIA 49 -Ews 60).Classe -eq 'MATERIAL') 'K6 EWS critico revalida por IA em 48h (nunca QUIETO por mais que isso)'
$blocoSombra = [regex]::Match($var, '(?s)if \(\$script:VixTriagemSombra\) \{\r?\n(.*?)\r?\n            \}\r?\n')
Assert-Cob ($blocoSombra.Success -and $blocoSombra.Groups[1].Value -match 'TRIAGEM_SOMBRA' -and $blocoSombra.Groups[1].Value -match '\$__restoIA\.Add\(\$emp\); continue' -and $blocoSombra.Groups[1].Value -notmatch 'Submit-Analise|Write-Ledger') 'K7 modo sombra registra e devolve todo emissor para a IA, sem submit nem ledger do coletor'

Write-Host '=== L: gate anti-Claude, duas pontas (check-claude-free.ps1) ==='
$gD = Join-Path $Tmp 'gate'; New-Item -ItemType Directory -Force (Join-Path $gD 'scripts') | Out-Null
# O nome do executavel e montado em runtime: o proprio gate varre este arquivo na arvore e
# reprovaria o literal (R1), mesmo dentro de string.
$cl = 'cla' + 'ude'
Set-Content -LiteralPath (Join-Path $gD 'scripts\inv.ps1') -Value ('$o.v = try { (& ' + $cl + ' --version 2>&1 | Out-String).Trim() } catch { $_.Exception.Message }') -Encoding ASCII
Set-Content -LiteralPath (Join-Path $gD 'scripts\mau.ps1') -Value ('& ' + $cl + ' -p "oi"') -Encoding ASCII
Set-Content -LiteralPath (Join-Path $gD 'scripts\misto.ps1') -Value ($cl + ' --version; ' + $cl + ' -p "oi"') -Encoding ASCII
Set-Content -LiteralPath (Join-Path $gD 'scripts\pipe.ps1') -Value ('"x" | ' + $cl + ' -p') -Encoding ASCII
Assert-Cob (@('inv','mau','misto','pipe' | Where-Object { Test-Path -LiteralPath (Join-Path $gD ('scripts\' + $_ + '.ps1')) }).Count -eq 4) 'L0 as 4 amostras do gate existem (senao L1 passaria por arquivo ausente)'
foreach ($c in @(@('inv', 0, 'L1 --version (inventario) e aceito'), @('mau', 1, 'L2 invocacao -p sem gate reprova'), @('misto', 1, 'L3 --version misturado com invocacao -p na mesma linha reprova'), @('pipe', 1, 'L4 invocacao -p por pipe reprova'))) {
    & pwsh -NoProfile -File (Join-Path $Scripts 'check-claude-free.ps1') -Path (Join-Path $gD ('scripts\' + $c[0] + '.ps1')) -RootPrefix $gD *> $null
    Assert-Cob ($LASTEXITCODE -eq $c[1]) $c[2]
}

Write-Host '=== M: filtro de relevancia em sombra (gatilhos criticos preservados, duas pontas) ==='
function New-TriM($Novas, [string]$Motivo = 'evidencia_nova_1') { @{ Classe = 'MATERIAL'; Motivo = $Motivo; Novas = @($Novas) } }
function New-EvM([string]$Fam, [string]$Tit, [string]$Veic = 'Portal X', [string]$Dom = 'x.com.br') { [pscustomobject]@{ familia = $Fam; data = $hojeK; veiculo = $Veic; dominio = $Dom; titulo = $Tit } }
$rRuido = Get-VixRelevanciaCredito -Triagem (New-TriM @(New-EvM 'F1' 'Light vence classico no Maracana')) -Ews 20
Assert-Cob ($rRuido.Decisao -eq 'RUIDO') 'M1 manchete F1 esportiva sem termo de credito = RUIDO'
Assert-Cob ((Get-VixRelevanciaCredito -Triagem (New-TriM @(New-EvM 'F1' 'Light vence classico no Maracana')) -CvmNovos 1 -Ews 20).Decisao -eq 'RELEVANTE') 'M2 documento CVM novo nunca e RUIDO'
Assert-Cob ((Get-VixRelevanciaCredito -Triagem (New-TriM @(New-EvM 'F1' 'Light vence classico no Maracana')) -Ews 55).Decisao -eq 'RELEVANTE') 'M3 EWS >= 50 nunca e RUIDO'
Assert-Cob ((Get-VixRelevanciaCredito -Triagem (New-TriM @() 'revalidacao_ia_130h_limite_120h') -Ews 0).Decisao -eq 'RELEVANTE') 'M4 revalidacao obrigatoria nunca e RUIDO'
Assert-Cob ((Get-VixRelevanciaCredito -Triagem (New-TriM @(New-EvM 'F1' 'Holding pede recuperacao judicial') 'critico_f1_sem_nome_1') -Ews 0).Decisao -eq 'RELEVANTE') 'M5 termo critico F1 sem nome nunca e RUIDO'
Assert-Cob ((Get-VixRelevanciaCredito -Triagem (New-TriM @(New-EvM 'F1' 'Empresa X tem rebaixamento de nota')) -Ews 0).Decisao -eq 'RELEVANTE') 'M6 termo critico na manchete = RELEVANTE'
Assert-Cob ((Get-VixRelevanciaCredito -Triagem (New-TriM @(New-EvM 'F2' 'Empresa X no noticiario')) -Ews 0).Decisao -eq 'RELEVANTE') 'M7 familia F2 (divida/emissao) sempre RELEVANTE'
Assert-Cob ((Get-VixRelevanciaCredito -Triagem (New-TriM @(New-EvM 'F1' 'Empresa X em destaque' 'Fitch Ratings' 'fitchratings.com')) -Ews 0).Decisao -eq 'RELEVANTE') 'M8 veiculo de agencia de rating = RELEVANTE'
Assert-Cob ((Get-VixRelevanciaCredito -Triagem (New-TriM @(New-EvM 'F1' ('Empresa X conclui emiss' + [char]0xE3 + 'o de deb' + [char]0xEA + 'ntures'))) -Ews 0).Decisao -eq 'RELEVANTE') 'M9 termo de credito com acento casa sem acento'
Assert-Cob ((Get-VixRelevanciaCredito -Triagem (New-TriM @()) -Ews 0).Decisao -eq 'RELEVANTE') 'M10 MATERIAL sem evidencia para julgar = RELEVANTE (lado seguro)'
Assert-Cob ((Get-VixRelevanciaCredito -Triagem @{ Classe = 'QUIETO'; Motivo = 'x'; Novas = @() }).Decisao -eq 'NAO_APLICA') 'M11 filtro nao toca em QUIETO/INDISPONIVEL'
$regsM = @(
    [pscustomobject]@{ tipo = 'decisao'; empresa = 'A'; decisao = 'RUIDO' }, [pscustomobject]@{ tipo = 'desfecho'; empresa = 'A'; n_eventos = 0 },
    [pscustomobject]@{ tipo = 'decisao'; empresa = 'B'; decisao = 'RUIDO' }, [pscustomobject]@{ tipo = 'desfecho'; empresa = 'B'; n_eventos = 2 },
    [pscustomobject]@{ tipo = 'decisao'; empresa = 'C'; decisao = 'RUIDO' },
    [pscustomobject]@{ tipo = 'decisao'; empresa = 'D'; decisao = 'RELEVANTE' }, [pscustomobject]@{ tipo = 'desfecho'; empresa = 'D'; n_eventos = 1 })
$revM = Get-VixRevocacaoRelevancia $regsM
Assert-Cob ($revM.FalsosNegativos -eq 1 -and $revM.Emissores -contains 'B' -and -not $revM.Seguro) 'M12 RUIDO com evento achado pela IA conta como falso negativo e reprova'
Assert-Cob ($revM.RuidoSemDesfecho -eq 1 -and $revM.RuidoMedido -eq 2) 'M13 RUIDO sem desfecho nao conta como acerto'
$revOk = Get-VixRevocacaoRelevancia @($regsM[0], $regsM[1])
Assert-Cob ($revOk.Seguro -and $revOk.FalsosNegativos -eq 0) 'M14 ponta oposta: RUIDO confirmado sem evento passa'
Assert-Cob (-not (Get-VixRevocacaoRelevancia @($regsM[4])).Seguro) 'M15 sem nenhuma medicao nao declara seguro'
$jsM = Join-Path $Tmp 'rel.jsonl'
Add-VixRelevanciaRegistro $jsM ([ordered]@{ tipo = 'decisao'; empresa = ('Ra' + [char]0xED + 'zen'); decisao = 'RUIDO' })
$lidoM = @(Get-Content -LiteralPath $jsM -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
Assert-Cob ($lidoM.Count -eq 1 -and $lidoM[0].empresa -eq ('Ra' + [char]0xED + 'zen')) 'M16 registro JSONL grava e rele acento sem corromper'
Assert-Cob ($var -match 'RELEVANCIA_SOMBRA' -and $var -match "tipo = 'desfecho'" -and $var -match 'relevancia_ruido_sombra=') 'M17 motor registra decisao, desfecho da IA e resumo da sombra'
Assert-Cob ($var -notmatch 'RUIDO[^\r\n]*continue') 'M18 nenhuma decisao RUIDO tira o emissor da IA (sombra pura)'

Write-Host '=== N: estouro real de 13/10 (156.293 contra cap 120.000), medicao persistente (duas pontas) ==='
$logN = Join-Path $Tmp 'logN'; New-Item -ItemType Directory -Force $logN | Out-Null
Assert-Cob (@(Get-VixHistoricoCustoSentinela -LogDir $logN -Provider 'codex').Count -eq 0) 'N0 sem arquivo de medicao o historico proprio e vazio'
$agoraN = [datetime]'2026-10-13T17:27:00'
Add-VixCustoSentinela -LogDir $logN -Provider 'codex' -CustoEmissor 156293 -Emissores 1 -Lote 'sonnet-1' -Agora $agoraN.AddSeconds(-5)
Add-VixCustoSentinela -LogDir $logN -Provider 'outro' -CustoEmissor 5 -Emissores 1 -Lote 'x' -Agora $agoraN.AddSeconds(-5)
Add-VixCustoSentinela -LogDir $logN -Provider 'codex' -CustoEmissor 999999 -Emissores 1 -Lote 'velho' -Agora $agoraN.AddDays(-9)
Add-VixCustoSentinela -LogDir $logN -Provider 'codex' -CustoEmissor 0 -Emissores 1 -Lote 'zero' -Agora $agoraN
$hN = @(Get-VixHistoricoCustoSentinela -LogDir $logN -Provider 'codex' -Dias 7 -Agora $agoraN)
Assert-Cob ($hN.Count -eq 1 -and $hN[0] -eq 156293) 'N1 medicao persiste e rele so do provedor certo, dentro de 7 dias, ignorando zero'
$cN = Get-VixCustoPorEmissor -ObservadosExecucao @() -Historico @() -Default 250000 -HistoricoProprio $hN
Assert-Cob ($cN.Custo -eq 156293 -and $cN.Fonte -eq 'historico_proprio_max_n1') 'N2 estimativa passa a ser a medida real (156293), sem clamp'
$dN = Get-VixDecisaoCapSentinela -Acum 0 -Cap 120000 -CustoEstimado $cN.Custo -Fonte $cN.Fonte -Chunk 4 -DisponivelDia 900000 -CalibracaoJaFeita $false
Assert-Cob ($dN.Cabem -eq 0 -and $dN.Motivo -eq 'custo_medido_nao_cabe_no_cap') 'N3 repeticao do cenario de 13/10: com a medicao gravada a Sentinela nao admite o emissor'
$cSem = Get-VixCustoPorEmissor -ObservadosExecucao @() -Historico @() -Default 250000 -HistoricoProprio @()
$dSem = Get-VixDecisaoCapSentinela -Acum 0 -Cap 120000 -CustoEstimado $cSem.Custo -Fonte $cSem.Fonte -Chunk 4 -DisponivelDia 900000 -CalibracaoJaFeita $false
Assert-Cob ($dSem.Calibracao -and $dSem.Cabem -eq 1) 'N4 ponta oposta: sem medicao nenhuma, so a calibracao unica admite 1 emissor'
$cMax = Get-VixCustoPorEmissor -ObservadosExecucao @() -Historico @(100000,100000) -Default 250000 -HistoricoProprio @(90000, 156293, 110000)
Assert-Cob ($cMax.Custo -eq 156293) 'N5 historico proprio usa o MAXIMO (nao repete estouro ja medido), nao a mediana'
$cObs = Get-VixCustoPorEmissor -ObservadosExecucao @(80000) -Historico @() -Default 250000 -HistoricoProprio @(156293)
Assert-Cob ($cObs.Fonte -eq 'observado_execucao' -and $cObs.Custo -eq 80000) 'N6 medicao da propria execucao vence o historico'
Assert-Cob ($sen -match 'Add-VixCustoSentinela' -and $sen -match '-HistoricoProprio \$histProprioS') 'N7 sentinela grava a medicao por lote e le o historico proprio nas duas estimativas'

Write-Host '=== L: INCONCLUSIVO/DEFERIDO nunca vira QUIETO, e o cache do Codex fica visivel ==='
# ESTADONAORESOLVIDO1 (2026-10-13). QUIETO e certificacao de ausencia feita pelo caminho mais
# barato da casa. Emissor com pergunta viva nao pode receber esse veredito.
$ruidoL = New-ColK 'Emissor Com Pendencia' @([pscustomobject]@{ familia = 'F1'; data = $hojeK; veiculo = 'x'; dominio = 'x.com'; titulo = 'Time local vence campeonato' })
$semAberto = Get-VixTriagemEmissor -Coleta $ruidoL -DeltaInicio $deltaK -HorasDesdeIA 10 -Ews 0
Assert-Cob ($semAberto.Classe -eq 'QUIETO') 'L1 ponta boa: sem estado aberto, o mesmo ruido segue QUIETO (o fluxo normal nao quebrou)'
$comPend = Get-VixTriagemEmissor -Coleta $ruidoL -DeltaInicio $deltaK -HorasDesdeIA 10 -Ews 0 -EstadoNaoResolvido $true -MotivoNaoResolvido 'pendencia_recheck_cobertura'
Assert-Cob ($comPend.Classe -eq 'MATERIAL' -and $comPend.Motivo -eq 'estado_nao_resolvido_pendencia_recheck_cobertura') 'L2 ponta oposta: com pendencia de analise aberta o MESMO ruido vai para a IA'
$comInc = Get-VixTriagemEmissor -Coleta $ruidoL -DeltaInicio $deltaK -HorasDesdeIA 10 -Ews 0 -EstadoNaoResolvido $true -MotivoNaoResolvido 'inconclusivo_anterior'
Assert-Cob ($comInc.Classe -eq 'MATERIAL' -and $comInc.Motivo -eq 'estado_nao_resolvido_inconclusivo_anterior') 'L3 ultimo desfecho INCONCLUSIVO tambem barra o QUIETO'
$comGenerico = Get-VixTriagemEmissor -Coleta $ruidoL -DeltaInicio $deltaK -HorasDesdeIA 10 -Ews 0 -EstadoNaoResolvido $true
Assert-Cob ($comGenerico.Classe -eq 'MATERIAL' -and $comGenerico.Motivo -eq 'estado_nao_resolvido_pendencia_aberta') 'L4 sem motivo declarado o rotulo e generico - nunca vazio nem QUIETO'
Assert-Cob ((Get-VixTriagemEmissor -Coleta $null -DeltaInicio $deltaK -HorasDesdeIA 10 -Ews 0 -EstadoNaoResolvido $true).Classe -eq 'INDISPONIVEL') 'L5 coleta indisponivel continua INDISPONIVEL (nao olhei != olhei e nao posso concluir)'
Assert-Cob ((Get-VixTriagemEmissor -Coleta $ruidoL -DeltaInicio $deltaK -HorasDesdeIA 200 -Ews 0 -EstadoNaoResolvido $true).Classe -eq 'MATERIAL') 'L6 revalidacao vencida continua MATERIAL pelo motivo proprio dela'
Assert-Cob ((Get-VixTriagemEmissor -Coleta $ruidoL -DeltaInicio $deltaK -CvmNovos 1 -HorasDesdeIA 10 -Ews 0 -EstadoNaoResolvido $false).Classe -eq 'MATERIAL') 'L7 CVM novo continua MATERIAL sem depender da flag'
# A definicao de "analise concluida" e unica para as duas linhas vizinhas do motor que se
# contradiziam (uma carimbava ultima_ia para INCONCLUSIVO, a outra mantinha a pendencia).
Assert-Cob ((Test-VixAnaliseConcluida -SubOk $true -Classificacao 'RELEVANTE') -eq $true) 'L8 analise RELEVANTE aceita e concluida'
Assert-Cob ((Test-VixAnaliseConcluida -SubOk $true -Classificacao 'INCONCLUSIVO') -eq $false) 'L9 ponta oposta: INCONCLUSIVO NAO e conclusao (nao carimba ultima_ia nem solta pendencia)'
Assert-Cob ((Test-VixAnaliseConcluida -SubOk $true -Classificacao 'inconclusivo') -eq $false) 'L10 a caixa do texto nao muda o veredito'
Assert-Cob ((Test-VixAnaliseConcluida -SubOk $false -Classificacao 'NENHUM') -eq $false) 'L11 submit recusado nunca e conclusao'
Assert-Cob ($var -match 'Test-VixAnaliseConcluida -SubOk \(\[bool\]\$subOk\) -Classificacao' -and $var -notmatch "if \(\`$subOk -and -not \`$DryRun\) \{ try \{ Set-VixUltimaIA") 'L12 o motor usa a definicao unica nas duas linhas (o carimbo antigo morreu)'
# CACHECODEX-VISIVEL1: o cache do Codex ganha parcela propria sem mexer na regua do cap.
$__pc = ConvertTo-VixParcelasCodex @{ mensuravel = $true; eventos = 1; input_total = [int64]166788; cached = [int64]129408; output = [int64]980; reasoning = [int64]80 }
Assert-Cob ($__pc.cache_codex -eq 129408 -and $__pc.cache_read -eq 0) 'L13 o cache do Codex sai em parcela propria (nao se confunde com cache_read do Claude)'
Assert-Cob ($__pc.trabalho -eq 167768) 'L14 a regua do cap NAO mudou: trabalho segue 166788+980, com o cache dentro'
Assert-Cob ($__pc.cache_codex -lt $__pc.trabalho) 'L15 o cache e parte do trabalho, nunca um valor maior que ele'
$__mj = '{"tokens_trabalho":167768,"tokens_input":166788,"tokens_output":980,"tokens_cache_creation":0,"tokens_cache_read":0,"tokens_cache_codex":129408}' | ConvertFrom-Json
$__pj = Get-VixParcelas $__mj
Assert-Cob ($__pj.cache_codex -eq 129408 -and $__pj.trabalho -eq 167768) 'L16 a lib de custo le a parcela nova do metrics'
$__mjLegado = '{"tokens_trabalho":1000,"tokens_input":900,"tokens_output":100,"tokens_cache_creation":0,"tokens_cache_read":0}' | ConvertFrom-Json
Assert-Cob ((Get-VixParcelas $__mjLegado).cache_codex -eq 0) 'L17 metrics antigo, sem o campo, nao quebra e devolve zero (compatibilidade)'
} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ('RESULTADO: ' + $script:Ok + ' OK, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
