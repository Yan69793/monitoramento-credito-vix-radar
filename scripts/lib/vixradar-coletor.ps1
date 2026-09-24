# vixradar-coletor.ps1 - coleta deterministica de evidencia para as rotinas (COLETOR-PS1).
#
# Por que existe. O custo das rotinas esta no LOOP DE BUSCA DENTRO DO MODELO, nao na inferencia.
# Medido em 22/09: a sentinela queimou 490.961 tokens e entregou 0 analise, e o comentario
# SENTINELA-TOOLSVOL1 do adapter ja registrava que o custo esta no bucle de server tools, nao na
# inferencia base. Tirando a coleta do modelo e trazendo para ca, dois efeitos acontecem ao mesmo
# tempo: (1) corta token, porque o modelo deixa de reler pagina atras de pagina; e (2)
# fontes_consultadas deixa de ser auto-declaracao do modelo (a classe PROVAFALSA1) e passa a ser
# medicao de quem buscou de verdade.
#
# Sem LLM, sem chave de API, sem custo por token. Fonte: Google News RSS. Medido em 23/09:
# HTTP 200 em ~0,9s, 100 itens por consulta.
#
# Fonte ASCII puro por exigencia do lint-encoding. Os acentos dos TERMOS de busca entram por code
# point, e isso nao e capricho: medido em 23/09 a mesma consulta deu 11 itens recentes com acento
# contra 1 sem acento, entao acentuar e a diferenca entre achar e nao achar. O NOME do emissor nao
# precisa de tabela porque ja chega acentuado do plano do Worker.
#
# O dominio do veiculo sai de <source url="...">, nunca do <link>, que e redirect opaco do Google.
# Isso importa porque o Worker classifica a fonte por dominio no submit (_classificaFonte), e um
# news.google.com no lugar do publisher destruiria a classificacao oficial/imprensa/research.
#
# PowerShell 5.1, ASCII puro, $ErrorActionPreference Continue.

$VixColetorUa          = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
$VixColetorRssBase     = 'https://news.google.com/rss/search'
$VixColetorTimeoutSec  = 25
$VixColetorMaxPorFamilia = 5
$VixColetorJanelaDias  = 7
$VixColetorSleepMs     = 250

# Acentos por code point. Leia a coluna da direita como o termo que se quer escrever.
$VixColetorAc = @{
    i = [char]0xED   # i agudo,   como em d-i-vida
    e = [char]0xEA   # e circunflexo, como em deb-e-nture
    a = [char]0xE3   # a til,     como em emiss-a-o
    c = [char]0xE7   # c cedilha, como em capta-c-a-o
}
$VixColetorTermosDivida = @(
    ('d' + $VixColetorAc.i + 'vida'),
    ('deb' + $VixColetorAc.e + 'nture'),
    ('emiss' + $VixColetorAc.a + 'o'),
    ('capta' + $VixColetorAc.c + $VixColetorAc.a + 'o'),
    'credores',
    'refinanciamento'
)

function Get-VixColetorFamilias {
    # As tres familias sao o contrato de cobertura que o Worker ja cobra da rotina (F1 emissor,
    # F2 divida/emissao/captacao, F3 CVM/RI/fato). Aqui elas viram consulta concreta.
    param([string]$Empresa)
    $e = ('' + $Empresa).Trim()
    return @(
        [pscustomobject]@{ Id = 'F1'; Nome = 'emissor';          Query = $e },
        [pscustomobject]@{ Id = 'F2'; Nome = 'divida_emissao';   Query = ($e + ' (' + ($VixColetorTermosDivida -join ' OR ') + ')') },
        [pscustomobject]@{ Id = 'F3'; Nome = 'cvm_ri_fato';      Query = ($e + ' ("fato relevante" OR "comunicado ao mercado" OR assembleia OR debenturistas)') }
    )
}

function Get-VixColetorDominio {
    param([string]$Url)
    $u = ('' + $Url).Trim()
    if (-not $u) { return '' }
    try { return (([uri]$u).Host -replace '^www\.', '') } catch { return '' }
}

function ConvertFrom-VixColetorRss {
    # Pura em relacao a rede: recebe o XML cru e devolve itens. Testavel sem internet.
    param([string]$Raw)
    $itens = @()
    if (-not $Raw) { return $itens }
    $xml = $null
    try { $xml = [xml]$Raw } catch { return $itens }
    if (-not $xml.rss -or -not $xml.rss.channel) { return $itens }
    foreach ($i in @($xml.rss.channel.item)) {
        if (-not $i) { continue }
        $src = ''
        $dom = ''
        try {
            if ($i.source) {
                $src = ('' + $i.source.'#text').Trim()
                $dom = Get-VixColetorDominio ('' + $i.source.url)
            }
        } catch { }
        $dt = $null
        try { if ($i.pubDate) { $dt = ([datetime]::Parse([string]$i.pubDate)).ToUniversalTime() } } catch { }
        $itens += [pscustomobject][ordered]@{
            titulo = ('' + $i.title).Trim()
            veiculo = $src
            dominio = $dom
            data_utc = $dt
        }
    }
    return $itens
}

function Invoke-VixColetorRss {
    # Unico ponto de rede deste arquivo. curl.exe com UA de navegador: medido em 23/09 que a
    # requisicao simples sem UA e tratada diferente, e o vault ja registra WAF barrando cliente
    # que nao se identifica. Devolve o XML cru e o status, sem lancar.
    param([string]$Query, [int]$TimeoutSec = 0)
    $t = if ($TimeoutSec -gt 0) { $TimeoutSec } else { $VixColetorTimeoutSec }
    $enc = [uri]::EscapeDataString($Query)
    $url = ($VixColetorRssBase + '?q=' + $enc + '&hl=pt-BR&gl=BR&ceid=BR:pt-419')
    $out = @()
    try { $out = @(& curl.exe -s -A $VixColetorUa --max-time $t -w "`n__HTTP__%{http_code}" $url 2>$null) } catch { $out = @() }
    $txt = ($out -join "`n")
    $status = 0
    $m = [regex]::Match($txt, '__HTTP__(\d{3})\s*$')
    if ($m.Success) { $status = [int]$m.Groups[1].Value; $txt = $txt.Substring(0, $m.Index) }
    return [pscustomobject]@{ Status = $status; Corpo = $txt }
}

function Get-VixColetorEvidencia {
    # Coleta as tres familias para um emissor. Devolve evidencia FACTUAL e um resumo de cobertura.
    # Sem noticia recente e diferente de coleta indisponivel. HTTP, timeout ou XML invalido nao
    # podem ser lidos como ausencia de fato, porque o consumidor DeepSeek nao tem busca propria.
    param(
        [string]$Empresa,
        [int]$JanelaDias = 0,
        [int]$MaxPorFamilia = 0,
        [int]$SleepMs = -1
    )
    $janela = if ($JanelaDias -gt 0) { $JanelaDias } else { $VixColetorJanelaDias }
    $max    = if ($MaxPorFamilia -gt 0) { $MaxPorFamilia } else { $VixColetorMaxPorFamilia }
    $sleep  = if ($SleepMs -ge 0) { $SleepMs } else { $VixColetorSleepMs }
    $corte  = (Get-Date).ToUniversalTime().AddDays(-1 * $janela)

    $evidencias = @()
    $resumoFam = [ordered]@{}
    $erros = @()
    $vistos = @{}
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($fam in (Get-VixColetorFamilias $Empresa)) {
        $resp = Invoke-VixColetorRss -Query $fam.Query
        $xmlValido = $false
        if ($resp.Status -ne 200) {
            $erros += ($fam.Id + ': HTTP ' + $resp.Status)
        } else {
            try {
                $xmlTeste = [xml]$resp.Corpo
                $xmlValido = ($null -ne $xmlTeste.rss -and $null -ne $xmlTeste.rss.channel)
            } catch { $xmlValido = $false }
            if (-not $xmlValido) { $erros += ($fam.Id + ': XML invalido ou vazio') }
        }
        $itens = @()
        if ($resp.Status -eq 200 -and $xmlValido) { $itens = @(ConvertFrom-VixColetorRss $resp.Corpo) }
        $n = 0
        foreach ($it in $itens) {
            if ($n -ge $max) { break }
            if (-not $it.data_utc) { continue }
            if ($it.data_utc -lt $corte) { continue }
            # Dedup entre familias pela manchete normalizada: a mesma materia sai em varios
            # veiculos e com o mesmo titulo, e repetir isso no prompt e token jogado fora.
            $chave = (('' + $it.titulo).ToLowerInvariant() -replace '[^a-z0-9]', '')
            if ($chave.Length -gt 60) { $chave = $chave.Substring(0, 60) }
            if ($vistos.ContainsKey($chave)) { continue }
            $vistos[$chave] = $true
            $evidencias += [pscustomobject][ordered]@{
                familia = $fam.Id
                familia_nome = $fam.Nome
                titulo = $it.titulo
                veiculo = $it.veiculo
                dominio = $it.dominio
                data = $it.data_utc.ToString('yyyy-MM-dd')
                status_http = $resp.Status
                query = $fam.Query
            }
            $n++
        }
        $resumoFam[$fam.Id] = $n
        if ($sleep -gt 0) { Start-Sleep -Milliseconds $sleep }
    }
    $sw.Stop()

    $cobertura = 0
    foreach ($k in $resumoFam.Keys) { if ([int]$resumoFam[$k] -gt 0) { $cobertura++ } }

    return [pscustomobject]@{
        empresa      = $Empresa
        evidencias   = $evidencias
        total        = $evidencias.Count
        por_familia  = $resumoFam
        cobertura    = $cobertura
        familias_ok  = $cobertura
        janela_dias  = $janela
        duracao_ms   = $sw.ElapsedMilliseconds
        erros        = $erros
        disponivel   = ($erros.Count -eq 0)
        motivo_indisponibilidade = if ($erros.Count -gt 0) { $erros -join '; ' } else { '' }
    }
}

function Format-VixColetorEvidenciaTexto {
    # Bloco compacto para o prompt. Deliberadamente texto curto: o ganho desta mudanca vem de o
    # modelo NAO receber pagina inteira, e sim a manchete com veiculo e data.
    param($Coleta)
    if (-not $Coleta) { return 'EVIDENCIA_INDISPONIVEL: coleta ausente.' }
    $linhas = @()
    $indisponivel = ($null -ne $Coleta.PSObject.Properties['disponivel'] -and -not $Coleta.disponivel)
    if ($indisponivel) {
        $linhas += ('EVIDENCIA_INDISPONIVEL: coleta incompleta em ' + $Coleta.duracao_ms + 'ms, janela ' + $Coleta.janela_dias + 'd.')
        if ($Coleta.erros.Count -gt 0) { $linhas += ('EVIDENCIA_ERROS: ' + ($Coleta.erros -join '; ')) }
        return ($linhas -join "`n")
    }
    $linhas += ('EVIDENCIA_COLETADA: buscada pelo orquestrador em ' + $Coleta.duracao_ms + 'ms, janela ' + $Coleta.janela_dias + 'd, familias com resultado ' + $Coleta.cobertura + '/3 (F1 emissor, F2 divida/emissao/captacao, F3 CVM/RI/fato).')
    if ($Coleta.erros.Count -gt 0) { $linhas += ('EVIDENCIA_ERROS: ' + ($Coleta.erros -join '; ')) }
    if ($Coleta.total -eq 0) {
        $linhas += 'EVIDENCIA_VAZIA: nenhuma publicacao recente encontrada nas tres familias. Nao ha fato novo a classificar; e proibido inventar evento.'
        return ($linhas -join "`n")
    }
    foreach ($e in $Coleta.evidencias) {
        $linhas += ('[' + $e.familia + ' ' + $e.familia_nome + '] ' + $e.data + ' | ' + $e.veiculo + ' (' + $e.dominio + ') | ' + $e.titulo)
    }
    return ($linhas -join "`n")
}
