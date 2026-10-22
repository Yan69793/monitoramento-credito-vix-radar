# vixradar-proveniencia.ps1 - PROVENIENCIA1/2: provedor e horario reais nas fontes_consultadas.
#
# Medido em 21/10/2026 (auditoria adversarial, F6 e F7): com claude-subscription, 100% das fontes eram
# gravadas como "openrouter:web_search" (default constante do orquestrador) e a maioria dos timestamps
# (271 de 361) caia fora de qualquer janela de execucao do dia.
#
# Tres horarios que NAO se confundem (PROVENIENCIA2, 22/10/2026):
#   timestamp_fonte : quando o CONTEUDO da fonte foi publicado. Vem do modelo (timestamp_fonte ou
#                     data_fonte) e so e copiado, nunca inventado pelo orquestrador.
#   consultado_em   : quando a fonte foi CONSULTADA. E prova obrigatoria. So existe quando o horario que o
#                     modelo declarou em `timestamp` cai dentro da janela medida da invocacao do provider
#                     que respondeu. Horario de PROCESSAMENTO do orquestrador nunca vira consultado_em.
#   registrado_em   : quando o orquestrador gravou o registro. Metadado de auditoria, nunca prova de consulta.
# O `timestamp` original do modelo e preservado como veio (nunca sobrescrito). Sem prova de consulta
# (fora da janela ou sem janela medida) a fonte recebe _consulta_prova='sem_prova' e o portao estrutural a
# recusa: fail-closed. Fonte do coletor (provedor 'coletor') ja tem horario medido e nunca e tocada.
# Fonte carimbada pelo Codex (_timestamp_origem='orquestrador_lote', RECHECKDIVERG1) segue como estava: e um
# horario de processamento ja existente, fora do escopo desta rodada, registrado como pendencia.
# Compativel com Windows PowerShell 5.1, so ASCII.

$script:VixProvedoresConhecidos = @('openrouter', 'codex', 'claude')

# Rotulo de provedor da evidencia a partir do provider que EXECUTOU o lote.
function Get-VixFonteProvedorRotulo([string]$ProviderExec) {
    $p = ('' + $ProviderExec).Trim().ToLowerInvariant()
    if ($p -eq 'openrouter') { return 'openrouter' }
    if ($p -eq 'codex') { return 'codex' }
    return 'claude'
}

function ConvertTo-VixInstanteUtc([string]$Texto) {
    $t = ('' + $Texto).Trim()
    if (-not $t) { return $null }
    $dt = [datetime]::MinValue
    $estilo = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse($t, [System.Globalization.CultureInfo]::InvariantCulture, $estilo, [ref]$dt)) { return $dt }
    return $null
}

# Origem de UM emissor: o provider e a janela da invocacao que de fato o respondeu (principal, retry ou o
# lote que um fallback assumiu). O provider vem do retorno de Invoke-ClaudeBatch, que repassa o do filho
# nos desvios; o configurado so entra quando o retorno nao informa.
function Resolve-VixOrigemExecucao($Principal, $Retry, [bool]$VeioDoRetry, [string]$ProviderConfigurado = '') {
    $fonte = $Principal
    if ($VeioDoRetry -and $null -ne $Retry) { $fonte = $Retry }
    $prov = ''
    $ini = $null; $fim = $null
    if ($null -ne $fonte) {
        if ($fonte -is [System.Collections.IDictionary]) {
            if ($fonte.Contains('ProviderExecutado')) { $prov = '' + $fonte['ProviderExecutado'] }
            if ($fonte.Contains('IniUtc')) { $ini = $fonte['IniUtc'] }
            if ($fonte.Contains('FimUtc')) { $fim = $fonte['FimUtc'] }
        } else {
            if ($null -ne $fonte.PSObject.Properties['ProviderExecutado']) { $prov = '' + $fonte.ProviderExecutado }
            if ($null -ne $fonte.PSObject.Properties['IniUtc']) { $ini = $fonte.IniUtc }
            if ($null -ne $fonte.PSObject.Properties['FimUtc']) { $fim = $fonte.FimUtc }
        }
    }
    $origem = 'retorno_da_invocacao'
    if (-not $prov) { $prov = $ProviderConfigurado; $origem = 'configurado_sem_retorno' }
    return @{ Provider = $prov; IniUtc = $ini; FimUtc = $fim; Origem = $origem }
}

# Modo de prova de consulta (decisao do operador, nunca da rotina): 'estrito' (padrao, fail-closed) exige o
# horario declarado dentro da janela; 'janela' aceita a JANELA MEDIDA da invocacao como prova limitada
# (consultado_entre), sem nunca preencher consultado_em. Outro valor, vazio ou ausente = estrito.
function Get-VixProvenienciaModo {
    foreach ($escopo in 'Process', 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('VIXRADAR_PROVENIENCIA_MODO', $escopo)
        if ($v) { if ((('' + $v).Trim().ToLowerInvariant()) -eq 'janela') { return 'janela' } else { return 'estrito' } }
    }
    return 'estrito'
}

# Vincula cada fonte do modelo ao provider executado e separa os tres horarios. Devolve contadores.
function Repair-VixFontesProveniencia {
    param($Res, [string]$ProvedorAtivo, $LoteIniUtc, $LoteFimUtc, [int]$ToleranciaMin = 15, $RegistradoEm = $null, [string]$Modo = 'estrito')
    $out = [ordered]@{ provedor_reescrito = 0; consulta_na_janela = 0; consulta_sem_prova = 0; consulta_pela_janela = 0; ja_carimbada_pelo_orquestrador = 0 }
    if ($null -eq $Res -or $null -eq $Res.PSObject.Properties['fontes_consultadas']) { return [pscustomobject]$out }
    $ativo = Get-VixFonteProvedorRotulo $ProvedorAtivo
    $temJanela = ($null -ne $LoteIniUtc -and $null -ne $LoteFimUtc -and ([datetime]$LoteFimUtc) -ge ([datetime]$LoteIniUtc))
    if ($null -eq $RegistradoEm) { $RegistradoEm = (Get-Date).ToUniversalTime() }
    $registrado = ([datetime]$RegistradoEm).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    foreach ($f in @($Res.fontes_consultadas)) {
        if ($null -eq $f -or $null -eq $f.PSObject) { continue }
        $prov = ('' + $f.provedor).Trim()
        $base = $prov.ToLowerInvariant().Split(':')[0]
        if ($base -notin $script:VixProvedoresConhecidos) { continue }   # coletor e desconhecidos ficam como estao

        # PROVEDOR: o vinculo e com quem executou. O declarado fica guardado.
        $f | Add-Member -NotePropertyName 'provedor_executado' -NotePropertyValue $ativo -Force
        if ($base -ne $ativo) {
            $ferr = if ($prov.Contains(':')) { $prov.Substring($prov.IndexOf(':') + 1) } else { 'web_search' }
            $f | Add-Member -NotePropertyName 'provedor_declarado' -NotePropertyValue $prov -Force
            $f.provedor = ($ativo + ':' + $ferr)
            $f | Add-Member -NotePropertyName '_provedor_origem' -NotePropertyValue 'orquestrador' -Force
            $out.provedor_reescrito++
        }

        # HORARIOS. registrado_em e sempre metadado do orquestrador.
        $f | Add-Member -NotePropertyName 'registrado_em' -NotePropertyValue $registrado -Force
        if ($f.PSObject.Properties['_timestamp_origem'] -and ('' + $f._timestamp_origem) -eq 'orquestrador_lote') { $out.ja_carimbada_pelo_orquestrador++; continue }

        # timestamp_fonte: so copia o que o modelo informou sobre a PUBLICACAO da fonte.
        foreach ($campo in 'timestamp_fonte', 'data_fonte') {
            if ($f.PSObject.Properties[$campo] -and ('' + $f.$campo).Trim()) {
                $f | Add-Member -NotePropertyName 'timestamp_fonte' -NotePropertyValue ('' + $f.$campo).Trim() -Force
                break
            }
        }

        # consultado_em: so o horario DECLARADO pelo modelo e coerente com a janela da invocacao que respondeu.
        $tsDecl = ('' + $f.timestamp).Trim()
        $dt = ConvertTo-VixInstanteUtc $tsDecl
        $naJanela = $false
        if ($temJanela -and $null -ne $dt) {
            $ini = ([datetime]$LoteIniUtc).AddMinutes(-$ToleranciaMin)
            $fim = ([datetime]$LoteFimUtc).AddMinutes($ToleranciaMin)
            $naJanela = ($dt -ge $ini -and $dt -le $fim)
        }
        if ($naJanela) {
            $f | Add-Member -NotePropertyName 'consultado_em' -NotePropertyValue $dt.ToString('yyyy-MM-ddTHH:mm:ssZ') -Force
            $f | Add-Member -NotePropertyName 'consultado_em_origem' -NotePropertyValue 'declarado_pelo_modelo_dentro_da_janela_da_invocacao' -Force
            $f | Add-Member -NotePropertyName '_consulta_prova' -NotePropertyValue 'declarado_na_janela' -Force
            $out.consulta_na_janela++
        } elseif ($Modo -eq 'janela' -and $temJanela) {
            # Modo janela: a consulta ocorreu DENTRO da invocacao medida do provider que respondeu. E prova de
            # intervalo, nao de instante: consultado_em fica nulo e o horario declarado e marcado inconsistente.
            $f | Add-Member -NotePropertyName 'consultado_em' -NotePropertyValue $null -Force
            $f | Add-Member -NotePropertyName 'consultado_entre' -NotePropertyValue (([datetime]$LoteIniUtc).ToString('yyyy-MM-ddTHH:mm:ssZ') + '/' + ([datetime]$LoteFimUtc).ToString('yyyy-MM-ddTHH:mm:ssZ')) -Force
            $f | Add-Member -NotePropertyName 'consultado_em_origem' -NotePropertyValue 'janela_medida_da_invocacao_sem_instante' -Force
            $f | Add-Member -NotePropertyName 'timestamp_declarado_inconsistente' -NotePropertyValue $true -Force
            $f | Add-Member -NotePropertyName '_consulta_prova' -NotePropertyValue 'janela_da_invocacao' -Force
            $out.consulta_pela_janela++
        } else {
            $motivo = if (-not $temJanela) { 'sem_janela_medida_da_invocacao' } elseif ($null -eq $dt) { 'timestamp_ausente_ou_ilegivel' } else { 'timestamp_fora_da_janela_da_invocacao' }
            $f | Add-Member -NotePropertyName 'consultado_em' -NotePropertyValue $null -Force
            $f | Add-Member -NotePropertyName 'consultado_em_origem' -NotePropertyValue $motivo -Force
            $f | Add-Member -NotePropertyName '_consulta_prova' -NotePropertyValue 'sem_prova' -Force
            if ($temJanela) {
                $f | Add-Member -NotePropertyName '_janela_invocacao' -NotePropertyValue (([datetime]$LoteIniUtc).ToString('yyyy-MM-ddTHH:mm:ssZ') + '/' + ([datetime]$LoteFimUtc).ToString('yyyy-MM-ddTHH:mm:ssZ')) -Force
            }
            $out.consulta_sem_prova++
        }
    }
    return [pscustomobject]$out
}
