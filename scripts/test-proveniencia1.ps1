# test-proveniencia1.ps1 - PROVENIENCIA1/2: provedor executado e tres horarios separados (F6 e F7).
# Cenario medido em 21/10/2026: lote da Matinal de 20:14Z a 22:22Z em claude-subscription, fontes com provedor
# "openrouter" e timestamps 10:00Z, 10:02Z, 10:05Z inventados pelo modelo.
# Regras testadas: provider vem de quem EXECUTOU (inclusive apos fallback e no retry); timestamp original
# preservado; consultado_em so com horario declarado dentro da janela da invocacao; horario de processamento
# (registrado_em) nunca vira prova de consulta; sem prova => o portao recusa (fail-closed).
# Offline, sem rotina, sem rede, sem mutex. Saida por exit code (0 = tudo passou).
$ErrorActionPreference = 'Continue'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $aqui 'lib\vixradar-proveniencia.ps1')
. (Join-Path $aqui 'lib\vixradar-cobertura.ps1')
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $aqui 'run_vixradar_varredura.ps1'), [ref]$null, [ref]$null)
foreach ($nome in 'Get-VixCoberturaProviderCapability', 'ConvertTo-VixFonteEstrutural', 'Test-VixBuscaDegradada') {
    $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $nome }, $true) | Select-Object -First 1
    if ($fn) { Invoke-Expression $fn.Extent.Text }
}
$falhas = 0
function Confere($nome, $cond) {
    if ($cond) { Write-Output ('OK    ' + $nome) } else { Write-Output ('FALHA ' + $nome); $script:falhas++ }
}
function Nova-Fonte($prov, $ts, $fam) {
    [pscustomobject]@{ familia = $fam; query = 'Klabin debentures'; timestamp = $ts; provedor = $prov; status_http = 200; resultado = 'resultados validos da consulta com conteudo'; classificacao = 'ok' }
}
function Utc($s) { [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) }
$ini = Utc '2026-10-21T20:14:17Z'
$fim = Utc '2026-10-21T22:22:00Z'
$reg = Utc '2026-10-21T22:30:00Z'

Confere 'rotulo: claude-subscription => claude' ((Get-VixFonteProvedorRotulo 'claude-subscription') -eq 'claude')
Confere 'rotulo: openrouter => openrouter' ((Get-VixFonteProvedorRotulo 'openrouter') -eq 'openrouter')

# --- Ponta ruim (falha medida): sem o reparo, origem e horario falsos passavam no portao.
$res = [pscustomobject]@{ fontes_consultadas = @(
        (Nova-Fonte 'openrouter:web_search' '2026-10-21T10:00:00Z' 'emissor'),
        (Nova-Fonte 'openrouter:web_search' '2026-10-21T10:02:00Z' 'divida'),
        (Nova-Fonte 'openrouter:web_fetch' '2026-10-21T10:05:00Z' 'fato')) }
$pre = @($res.fontes_consultadas | ForEach-Object { (ConvertTo-VixFonteEstrutural $_).ok }) -notcontains $false
Confere 'ANTES: o portao aceitava origem e horario falsos (a falha F6/F7)' $pre
$r = Repair-VixFontesProveniencia -Res $res -ProvedorAtivo 'claude-subscription' -LoteIniUtc $ini -LoteFimUtc $fim -RegistradoEm $reg
Confere ('provedor reescrito para o executado (n=' + $r.provedor_reescrito + ') e declarado guardado') ($r.provedor_reescrito -eq 3 -and $res.fontes_consultadas[0].provedor -eq 'claude:web_search' -and $res.fontes_consultadas[0].provedor_declarado -eq 'openrouter:web_search' -and $res.fontes_consultadas[2].provedor -eq 'claude:web_fetch')
Confere 'timestamp ORIGINAL preservado (nunca sobrescrito)' ($res.fontes_consultadas[0].timestamp -eq '2026-10-21T10:00:00Z' -and $res.fontes_consultadas[2].timestamp -eq '2026-10-21T10:05:00Z')
Confere 'fora da janela: consultado_em nulo e motivo registrado' ($null -eq $res.fontes_consultadas[0].consultado_em -and $res.fontes_consultadas[0].consultado_em_origem -eq 'timestamp_fora_da_janela_da_invocacao')
Confere 'registrado_em e o horario de processamento, separado de consultado_em' ($res.fontes_consultadas[0].registrado_em -eq '2026-10-21T22:30:00Z' -and $res.fontes_consultadas[0].consultado_em -ne $res.fontes_consultadas[0].registrado_em)
Confere ('horario de processamento NUNCA vira prova: sem_prova (n=' + $r.consulta_sem_prova + ')') ($r.consulta_sem_prova -eq 3 -and $res.fontes_consultadas[0]._consulta_prova -eq 'sem_prova')
$pos = @($res.fontes_consultadas | ForEach-Object { ConvertTo-VixFonteEstrutural $_ })
Confere 'fail-closed: o portao recusa fonte sem prova de consulta' (@($pos | Where-Object { $_.ok }).Count -eq 0 -and $pos[0].motivo -eq 'sem_prova_consulta_horario_nao_verificavel')

# --- Ponta boa: horario declarado dentro da janela e aceito, evidencia valida nao e descartada.
$res2 = [pscustomobject]@{ fontes_consultadas = @(
        (Nova-Fonte 'claude:web_search' '2026-10-21T21:00:00Z' 'emissor'),
        (Nova-Fonte 'claude:web_search' '2026-10-21T21:30:00Z' 'divida'),
        (Nova-Fonte 'claude:web_fetch' '2026-10-21T22:00:00Z' 'fato')) }
$r2 = Repair-VixFontesProveniencia -Res $res2 -ProvedorAtivo 'claude-subscription' -LoteIniUtc $ini -LoteFimUtc $fim -RegistradoEm $reg
Confere 'dentro da janela: consultado_em preenchido com origem declarada' ($r2.consulta_na_janela -eq 3 -and $res2.fontes_consultadas[0].consultado_em -eq '2026-10-21T21:00:00Z' -and $res2.fontes_consultadas[0].consultado_em_origem -eq 'declarado_pelo_modelo_dentro_da_janela_da_invocacao')
$pos2 = @($res2.fontes_consultadas | ForEach-Object { ConvertTo-VixFonteEstrutural $_ })
Confere 'DEPOIS: evidencia valida segue ok no portao (contrato claude)' (@($pos2 | Where-Object { -not $_.ok }).Count -eq 0 -and $pos2[0].contrato_provedor -eq 'cobertura_http_provider_claude')
Confere 'timestamp_fonte so e copiado quando o modelo informa' ($null -eq $res2.fontes_consultadas[0].PSObject.Properties['timestamp_fonte'])
$comPub = Nova-Fonte 'claude:web_search' '2026-10-21T21:00:00Z' 'emissor'; $comPub | Add-Member -NotePropertyName 'data_fonte' -NotePropertyValue '2026-10-20'
$res2b = [pscustomobject]@{ fontes_consultadas = @($comPub) }
$null = Repair-VixFontesProveniencia -Res $res2b -ProvedorAtivo 'claude-subscription' -LoteIniUtc $ini -LoteFimUtc $fim -RegistradoEm $reg
Confere 'timestamp_fonte (publicacao) separado de consultado_em' ($res2b.fontes_consultadas[0].timestamp_fonte -eq '2026-10-20' -and $res2b.fontes_consultadas[0].consultado_em -eq '2026-10-21T21:00:00Z')

# --- Sem janela medida: nao ha prova possivel => sem_prova (fail-closed).
$res3 = [pscustomobject]@{ fontes_consultadas = @((Nova-Fonte 'claude:web_search' '2026-10-21T21:00:00Z' 'emissor')) }
$r3 = Repair-VixFontesProveniencia -Res $res3 -ProvedorAtivo 'claude-subscription' -LoteIniUtc $null -LoteFimUtc $null -RegistradoEm $reg
Confere 'sem janela medida: sem_prova e portao recusa' ($r3.consulta_sem_prova -eq 1 -and $res3.fontes_consultadas[0].consultado_em_origem -eq 'sem_janela_medida_da_invocacao' -and (ConvertTo-VixFonteEstrutural $res3.fontes_consultadas[0]).ok -eq $false)
$res3b = [pscustomobject]@{ fontes_consultadas = @((Nova-Fonte 'claude:web_search' 'ontem de manha' 'emissor')) }
$null = Repair-VixFontesProveniencia -Res $res3b -ProvedorAtivo 'claude-subscription' -LoteIniUtc $ini -LoteFimUtc $fim -RegistradoEm $reg
Confere 'timestamp ilegivel: sem_prova' ($res3b.fontes_consultadas[0].consultado_em_origem -eq 'timestamp_ausente_ou_ilegivel' -and (ConvertTo-VixFonteEstrutural $res3b.fontes_consultadas[0]).ok -eq $false)

# --- Provider realmente executado, inclusive apos fallback e no retry.
# (a) lote principal respondido pelo OpenRouter apos fallback; configurado continua claude-subscription.
$principalFb = @{ ProviderExecutado = 'openrouter'; IniUtc = $ini; FimUtc = $fim }
$o1 = Resolve-VixOrigemExecucao -Principal $principalFb -Retry $null -VeioDoRetry $false -ProviderConfigurado 'claude-subscription'
Confere 'apos fallback: a origem e o provider executado, nao o configurado' ($o1.Provider -eq 'openrouter' -and $o1.Origem -eq 'retorno_da_invocacao')
$res4 = [pscustomobject]@{ fontes_consultadas = @((Nova-Fonte 'claude:web_search' '2026-10-21T21:00:00Z' 'emissor')) }
$null = Repair-VixFontesProveniencia -Res $res4 -ProvedorAtivo $o1.Provider -LoteIniUtc $o1.IniUtc -LoteFimUtc $o1.FimUtc -RegistradoEm $reg
Confere 'apos fallback: evidencia fica vinculada a openrouter (nao a claude)' ($res4.fontes_consultadas[0].provedor -eq 'openrouter:web_search' -and $res4.fontes_consultadas[0].provedor_executado -eq 'openrouter' -and $res4.fontes_consultadas[0].provedor_declarado -eq 'claude:web_search')
# (b) retry: emissor do retry usa o provider e a janela do retry; emissor do principal usa os do principal.
$princ = @{ ProviderExecutado = 'claude-subscription'; IniUtc = $ini; FimUtc = (Utc '2026-10-21T20:30:00Z') }
$retr = @{ ProviderExecutado = 'openrouter'; IniUtc = (Utc '2026-10-21T20:40:00Z'); FimUtc = (Utc '2026-10-21T20:50:00Z') }
$oP = Resolve-VixOrigemExecucao -Principal $princ -Retry $retr -VeioDoRetry $false -ProviderConfigurado 'claude-subscription'
$oR = Resolve-VixOrigemExecucao -Principal $princ -Retry $retr -VeioDoRetry $true -ProviderConfigurado 'claude-subscription'
Confere 'retry: emissor do principal usa o principal' ($oP.Provider -eq 'claude-subscription' -and $oP.FimUtc -eq $princ.FimUtc)
Confere 'retry: emissor do retry usa o provider e a janela do retry' ($oR.Provider -eq 'openrouter' -and $oR.IniUtc -eq $retr.IniUtc)
$resR = [pscustomobject]@{ fontes_consultadas = @((Nova-Fonte 'claude:web_search' '2026-10-21T20:20:00Z' 'emissor')) }   # dentro da janela do principal, fora da do retry
$null = Repair-VixFontesProveniencia -Res $resR -ProvedorAtivo $oR.Provider -LoteIniUtc $oR.IniUtc -LoteFimUtc $oR.FimUtc -RegistradoEm $reg
Confere 'retry: horario valido so no lote principal NAO vale para o retry (sem_prova)' ($resR.fontes_consultadas[0]._consulta_prova -eq 'sem_prova')
$o3 = Resolve-VixOrigemExecucao -Principal @{ IniUtc = $ini; FimUtc = $fim } -Retry $null -VeioDoRetry $false -ProviderConfigurado 'claude-subscription'
Confere 'retorno sem provider informado: cai no configurado e DECLARA a origem' ($o3.Provider -eq 'claude-subscription' -and $o3.Origem -eq 'configurado_sem_retorno')

# --- Coletor e Codex ja carimbado nao sao tocados; busca degradada e provedor desconhecido continuam recusados.
$col = [pscustomobject]@{ familia = 'emissor'; query = 'q'; timestamp = '2026-10-21T09:00:00Z'; provedor = 'coletor:rss'; status_http = 200; resultado = 'ok'; classificacao = 'ok' }
$res5 = [pscustomobject]@{ fontes_consultadas = @($col) }
$null = Repair-VixFontesProveniencia -Res $res5 -ProvedorAtivo 'claude-subscription' -LoteIniUtc $ini -LoteFimUtc $fim -RegistradoEm $reg
Confere 'fonte do coletor intocada' ($res5.fontes_consultadas[0].provedor -eq 'coletor:rss' -and $null -eq $res5.fontes_consultadas[0].PSObject.Properties['_consulta_prova'])
$cdx = Nova-Fonte 'codex:web_search' '2026-10-21T21:10:00Z' 'emissor'; $cdx | Add-Member -NotePropertyName '_timestamp_origem' -NotePropertyValue 'orquestrador_lote'
$res6 = [pscustomobject]@{ fontes_consultadas = @($cdx) }
$r6 = Repair-VixFontesProveniencia -Res $res6 -ProvedorAtivo 'codex' -LoteIniUtc $ini -LoteFimUtc $fim -RegistradoEm $reg
Confere 'Codex ja carimbado pelo orquestrador segue como estava (pendencia declarada)' ($r6.ja_carimbada_pelo_orquestrador -eq 1 -and $null -eq $res6.fontes_consultadas[0].PSObject.Properties['_consulta_prova'])
$ruim = Nova-Fonte 'openrouter:web_search' '2026-10-21T21:00:00Z' 'emissor'; $ruim.status_http = 429; $ruim.classificacao = 'degradada'
$res7 = [pscustomobject]@{ fontes_consultadas = @($ruim) }
$null = Repair-VixFontesProveniencia -Res $res7 -ProvedorAtivo 'claude-subscription' -LoteIniUtc $ini -LoteFimUtc $fim -RegistradoEm $reg
Confere 'busca degradada (429) continua sem prova depois do reparo' ((ConvertTo-VixFonteEstrutural $res7.fontes_consultadas[0]).ok -eq $false)
Confere 'provedor desconhecido continua recusado' ((ConvertTo-VixFonteEstrutural (Nova-Fonte 'google:search' '2026-10-21T21:00:00Z' 'emissor')).ok -eq $false)

# --- Modo de prova (decisao do operador). Padrao = estrito; 'janela' aceita so o INTERVALO medido da invocacao.
$antesModo = [Environment]::GetEnvironmentVariable('VIXRADAR_PROVENIENCIA_MODO', 'Process')
[Environment]::SetEnvironmentVariable('VIXRADAR_PROVENIENCIA_MODO', $null, 'Process')
$semUserModo = [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('VIXRADAR_PROVENIENCIA_MODO', 'User')) -and [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('VIXRADAR_PROVENIENCIA_MODO', 'Machine'))
if ($semUserModo) { Confere 'modo padrao e estrito (fail-closed)' ((Get-VixProvenienciaModo) -eq 'estrito') }
[Environment]::SetEnvironmentVariable('VIXRADAR_PROVENIENCIA_MODO', 'janela', 'Process')
Confere 'VIXRADAR_PROVENIENCIA_MODO=janela e reconhecido' ((Get-VixProvenienciaModo) -eq 'janela')
[Environment]::SetEnvironmentVariable('VIXRADAR_PROVENIENCIA_MODO', 'qualquer', 'Process')
Confere 'valor desconhecido volta para estrito' ((Get-VixProvenienciaModo) -eq 'estrito')
[Environment]::SetEnvironmentVariable('VIXRADAR_PROVENIENCIA_MODO', $antesModo, 'Process')

$resJ = [pscustomobject]@{ fontes_consultadas = @((Nova-Fonte 'claude:web_search' '2026-10-21T13:00:00Z' 'fato')) }
$rJ = Repair-VixFontesProveniencia -Res $resJ -ProvedorAtivo 'claude-subscription' -LoteIniUtc $ini -LoteFimUtc $fim -RegistradoEm $reg -Modo 'janela'
$fj = $resJ.fontes_consultadas[0]
Confere 'modo janela: prova de intervalo, consultado_em continua nulo' ($rJ.consulta_pela_janela -eq 1 -and $null -eq $fj.consultado_em -and $fj.consultado_entre -eq '2026-10-21T20:14:17Z/2026-10-21T22:22:00Z')
Confere 'modo janela: timestamp declarado preservado e marcado inconsistente' ($fj.timestamp -eq '2026-10-21T13:00:00Z' -and $fj.timestamp_declarado_inconsistente -eq $true)
Confere 'modo janela: horario de processamento (registrado_em) nao entra como consulta' ($fj.registrado_em -eq '2026-10-21T22:30:00Z' -and $fj.consultado_entre -notlike '*22:30*')
Confere 'modo janela: o portao aceita (evidencia valida nao descartada)' ((ConvertTo-VixFonteEstrutural $fj).ok -eq $true)
$resJ2 = [pscustomobject]@{ fontes_consultadas = @((Nova-Fonte 'claude:web_search' '2026-10-21T13:00:00Z' 'fato')) }
$null = Repair-VixFontesProveniencia -Res $resJ2 -ProvedorAtivo 'claude-subscription' -LoteIniUtc $null -LoteFimUtc $null -RegistradoEm $reg -Modo 'janela'
Confere 'modo janela SEM janela medida continua fail-closed' ((ConvertTo-VixFonteEstrutural $resJ2.fontes_consultadas[0]).ok -eq $false)
$resE = [pscustomobject]@{ fontes_consultadas = @((Nova-Fonte 'claude:web_search' '2026-10-21T13:00:00Z' 'fato')) }
$null = Repair-VixFontesProveniencia -Res $resE -ProvedorAtivo 'claude-subscription' -LoteIniUtc $ini -LoteFimUtc $fim -RegistradoEm $reg -Modo 'estrito'
Confere 'modo estrito: o mesmo caso e recusado' ((ConvertTo-VixFonteEstrutural $resE.fontes_consultadas[0]).ok -eq $false)

# --- Estatico: o motor propaga o provider executado em TODOS os retornos de fallback e o usa por emissor.
$f = Get-Content -LiteralPath (Join-Path $aqui 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
Confere 'Invoke-ClaudeBatch devolve ProviderExecutado, IniUtc e FimUtc' ($f.Contains('ProviderExecutado = $providerDaInvocacao; IniUtc = $__invIniUtc; FimUtc = (Get-Date).ToUniversalTime()'))
Confere 'os tres fallbacks devolvem a resposta do filho (carregam o provider real)' ($f.Contains('return $__fxResp') -and $f.Contains('return $anthropicResp') -and $f.Contains('return $__orFrResp'))
Confere 'motor resolve a origem por emissor (principal ou retry)' ($f.Contains('Resolve-VixOrigemExecucao -Principal $result -Retry $retryRes'))
Confere 'motor nao usa mais o provider configurado como origem da evidencia' (-not $f.Contains('Repair-VixFontesProveniencia -Res $res -ProvedorAtivo $__providerExec'))
Confere 'portao estrutural recusa _consulta_prova=sem_prova' ($f.Contains("sem_prova_consulta_horario_nao_verificavel"))

# C5 (auditoria 22/10): o provider EXECUTADO chega ao payload do Worker e ao ledger.
# Comportamento: apos fallback para o OpenRouter, a origem resolvida e openrouter, nao o claude configurado.
$oC5 = Resolve-VixOrigemExecucao -Principal @{ ProviderExecutado = 'openrouter'; IniUtc = $ini; FimUtc = $fim } -Retry $null -VeioDoRetry $false -ProviderConfigurado 'claude-subscription'
Confere 'C5 comportamento: lote desviado resolve para openrouter, nao para o configurado' ($oC5.Provider -eq 'openrouter')
Confere 'C5 motor: payload do Worker recebe _provider_executado' ($f.Contains("-NotePropertyName '_provider_executado' -NotePropertyValue `$__provExec"))
Confere 'C5 motor: __provExec nasce do provider da invocacao (Resolve-VixOrigemExecucao)' ($f.Contains('if ($__orig.Provider) { $__provExec = ''' + "'" + ' + $__orig.Provider }'))
Confere 'C5 motor: ledger grava o provider executado e guarda o configurado a parte' ($f.Contains("provider = ('' + `$__provExec); provider_configurado = ('' + (Get-VixLlmProvider))"))
Confere 'C5 motor: o ledger nao grava mais so o provider da env como provider' (-not $f.Contains("`$__cdAn = [ordered]@{ provider = ('' + (Get-VixLlmProvider));"))
Confere 'C5 motor: rotulo provedor do perfil enviado ao Worker segue inalterado' ($f.Contains('Submit-Analise $routineKey $emp.empresa $emp.setor $res $job.Provedor $job.Tier'))

Write-Output ('RESULTADO: falhas=' + $falhas)
exit $falhas
