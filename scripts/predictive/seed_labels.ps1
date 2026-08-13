# seed_labels.ps1
# One-shot: constroi o dataset seed de labels de eventos de credito para o preditivo v2
# (plano 2026-07-11, nota 51). Fontes: semanas vivas de radar:estado:{YYYY-Www} no KV de
# producao + snapshots versionados em scans/*.json (jun/2026) + dataset oficial CVM IPE
# (nota Obsidian 60, recomendacao 6, 2026-07-17).
# Saida: data/labels/eventos_credito.jsonl (1 evento por linha, dedup empresa+data+titulo).
# Target de treino do v2 = evento real (RJ/default/downgrade/covenant...), nunca proxy.
#
# Fonte IPE (Passo 3): mesma deteccao de severidade de reconciliar_ipe_cvm.ps1 (categoria
# dedicada "Informacoes de Companhias em RJ/RE" OU Fato Relevante/Comunicado ao Mercado com
# keyword de RJ/RE/default/reestruturacao/inadimplencia), cruzada por CNPJ contra
# cnpj_emissores.json. Ao contrario da fonte KV (que reflete o que o Radar classificou), a
# fonte IPE e GROUND TRUTH regulatorio independente - todo documento severo vira label
# classificacao="CRITICO", goste ou nao goste do que o Radar concluiu na mesma janela. Cobre
# multiplos anos (nota 60: "historico ate 2003 para backtest") via -AnosIpe.
# CUIDADO (nota 60): Data_Entrega e a data do PROTOCOLO, posterior ao vazamento na imprensa
# em parte dos casos - serve como label de OCORRENCIA para precision@k, nao como marco de
# lead time.
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\predictive\seed_labels.ps1" [-DeSemana 1] [-AteSemana 28] [-AnosIpe 2023,2024,2025,2026]

param(
    [int]$DeSemana = 1,
    [int]$AteSemana = 28,
    [int]$Ano = 2026,
    [int[]]$AnosIpe = @(2023, 2024, 2025, 2026)
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$ProjectRoot = 'E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito'
$ApiDir      = Join-Path $ProjectRoot 'api'
$NamespaceId = 'c6805b8d8a7b468e9f854ab4f91fb93a'
$OutDir      = Join-Path $ProjectRoot 'data\labels'
$OutPath     = Join-Path $OutDir 'eventos_credito.jsonl'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-KvValue([string]$Key) {
    $ErrorActionPreference = 'Continue'
    $stderrFile = Join-Path $env:TEMP ("kvget_{0}_{1}.err" -f $PID, [System.IO.Path]::GetRandomFileName())
    try {
        Push-Location $ApiDir
        $raw = (& npx wrangler kv key get $Key --namespace-id $NamespaceId --remote 2>$stderrFile | Out-String)
        $code = $LASTEXITCODE
        Pop-Location
        if ($code -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) { return $null }
        $i = $raw.IndexOf('{')
        if ($i -lt 0) { return $null }
        return $raw.Substring($i).Trim()
    } catch {
        if ((Get-Location).Path -eq $ApiDir) { Pop-Location }
        return $null
    } finally {
        Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

$labels = New-Object System.Collections.ArrayList
$vistos = @{}

function Add-Label($empresa, $setor, $ev, [string]$origem) {
    if (-not $ev) { return }
    $dataEv = [string]$ev.data_evento
    $titulo = [string]$ev.titulo
    $chave = ($empresa + '|' + $dataEv + '|' + $titulo).ToLowerInvariant().Trim()
    if ($vistos.ContainsKey($chave)) { return }
    $vistos[$chave] = $true
    [void]$labels.Add([pscustomobject]@{
        empresa       = $empresa
        setor         = $setor
        data_evento   = $dataEv
        classificacao = [string]$ev.classificacao
        tags          = @($ev.tags)
        fonte_tipo    = [string]$ev.fonte_tipo
        titulo        = $titulo
        oficial_tier1 = [bool]$ev._oficial_tier1
        origem        = $origem
    })
}

# ---- 0. Preservar labels ja capturados (2026-07-17) ----
# O arquivo de saida e reconstruido do zero a cada execucao lendo o KV AO VIVO. Se uma semana
# que antes tinha estado legivel se corromper depois (ex: chaves duplicadas 'teste'/'Teste' em
# 2026-W16/W18/W28, mesma classe do STATELEAK1), o proximo re-run perderia silenciosamente os
# labels que so existiam naquela semana - constatado nesta sessao: 307 labels de W16/W18/W28
# desapareceriam sem este passo. Carregar o arquivo existente ANTES de rescanear KV/scans/IPE
# torna a captura de labels durável: uma vez visto, um label sobrevive a degradacao posterior
# da fonte viva. Fontes atuais (kv/scan/ipe) continuam sendo a autoridade quando concordam;
# isto so preenche o que elas nao conseguem mais alcancar.
$labelsPreservados = 0
if (Test-Path $OutPath) {
    foreach ($linhaExistente in [System.IO.File]::ReadAllLines($OutPath, [Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($linhaExistente)) { continue }
        try {
            $evExistente = $linhaExistente | ConvertFrom-Json
        } catch { continue }
        $evSintetico = [pscustomobject]@{
            data_evento    = $evExistente.data_evento
            titulo         = $evExistente.titulo
            classificacao  = $evExistente.classificacao
            tags           = $evExistente.tags
            fonte_tipo     = $evExistente.fonte_tipo
            _oficial_tier1 = $evExistente.oficial_tier1
        }
        $antesPreservar = $labels.Count
        Add-Label $evExistente.empresa $evExistente.setor $evSintetico $evExistente.origem
        if ($labels.Count -gt $antesPreservar) { $labelsPreservados++ }
    }
}
[Console]::WriteLine(('Preservados do arquivo existente: {0} labels' -f $labelsPreservados))

# ---- 1. Semanas vivas no KV ----
$semanasOk = 0
for ($w = $DeSemana; $w -le $AteSemana; $w++) {
    $semana = ('{0}-W{1:00}' -f $Ano, $w)
    $raw = Get-KvValue ('radar:estado:' + $semana)
    if (-not $raw) { [Console]::WriteLine(('  {0}: ausente' -f $semana)); continue }
    $estado = $null
    try { $estado = $raw | ConvertFrom-Json } catch {
        # W28 real: results com chaves de emissor diferindo so por caixa (bug de normalizacao
        # na escrita - registrado em PENDENCIAS). pwsh aceita via -AsHashtable; dedup colapsa.
        try { $estado = $raw | ConvertFrom-Json -AsHashtable } catch { [Console]::WriteLine(('  {0}: JSON invalido' -f $semana)); continue }
    }
    if (-not $estado -or -not $estado.results) { continue }
    $semanasOk++
    $nEv = 0
    $pares = @()
    if ($estado.results -is [System.Collections.IDictionary]) {
        foreach ($k in $estado.results.Keys) { $pares += [pscustomobject]@{ Name = $k; Value = $estado.results[$k] } }
    } else {
        $pares = @($estado.results.PSObject.Properties)
    }
    foreach ($prop in $pares) {
        $emp = $prop.Name
        $res = $prop.Value
        if (-not $res -or -not $res.eventos) { continue }
        $setorRes = ''
        if ($res -is [System.Collections.IDictionary]) { $setorRes = [string]$res['setor'] } else { $setorRes = [string]$res.setor }
        foreach ($ev in @($res.eventos)) { Add-Label $emp $setorRes $ev ('kv:' + $semana); $nEv++ }
    }
    [Console]::WriteLine(('  {0}: {1} eventos lidos' -f $semana, $nEv))
}

# ---- 2. Scans versionados (jun/2026) ----
$scanDir = Join-Path $ProjectRoot 'scans'
$scansOk = 0
if (Test-Path $scanDir) {
    foreach ($f in Get-ChildItem $scanDir -Filter '*.json' -File) {
        try {
            $scan = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        } catch { continue }
        $emp = [string]$scan.empresa
        if (-not $emp -or -not $scan.resultado -or -not $scan.resultado.eventos) { continue }
        $scansOk++
        foreach ($ev in @($scan.resultado.eventos)) { Add-Label $emp ([string]$scan.setor) $ev ('scan:' + $f.BaseName) }
    }
}

# ---- 3. Dataset oficial CVM IPE (nota Obsidian 60, recomendacao 6) ----
# Ground truth regulatorio independente do que o Radar classificou - todo documento severo
# vira label CRITICO. Mesma logica de deteccao de reconciliar_ipe_cvm.ps1 (mantida em sync
# manual - script separado porque resolve um problema diferente: divergencia semanal vs
# dataset de treino plurianual).
$CacheDirIpe = Join-Path $ProjectRoot 'data\cvm'
$MapPathIpe  = Join-Path $ProjectRoot 'scripts\predictive\cnpj_emissores.json'
New-Item -ItemType Directory -Force -Path $CacheDirIpe | Out-Null

$cnpjParaEmissorIpe = @{}
if (Test-Path $MapPathIpe) {
    $mapaJsonIpe = [System.IO.File]::ReadAllText($MapPathIpe, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in $mapaJsonIpe.PSObject.Properties) {
        $cnpjRaw = [string]$p.Value.cnpj
        if ([string]::IsNullOrWhiteSpace($cnpjRaw)) { continue }
        $cnpjParaEmissorIpe[($cnpjRaw -replace '[^0-9]', '')] = $p.Name
    }
}
[Console]::WriteLine(('Universo IPE: {0} emissores com CNPJ mapeado' -f $cnpjParaEmissorIpe.Count))

$CategoriaRJREIpe = 'Informações de Companhias em Recuperação Judicial ou Extrajudicial'
$CategoriasBaseIpe = @('Fato Relevante', 'Comunicado ao Mercado')
$RxSeveroIpe = 'RECUPERA(C|CA)AO\s+(JUDICIAL|EXTRAJUDICIAL)|PLANO DE RECUPERA|INADIMPL|MORATORIA|REESTRUTURA(C|CA)AO DE DIVIDA|DEFAULT|VENCIMENTO ANTECIPADO|NAO[- ]PAGAMENTO|NAO PAGAMENTO|CALOTE|CROSS.DEFAULT|COVENANT'

function Remover-AcentosIpe([string]$s) {
    $n = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $n.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
    }
    return $sb.ToString()
}

function Categoria-ParaTags([string]$categoria) {
    if ($categoria -eq $CategoriaRJREIpe) { return @('recuperacao-judicial-extrajudicial', 'oficial-cvm') }
    return @('fato-relevante-severo', 'oficial-cvm')
}

$ipeLabelsCount = 0
foreach ($anoIpe in $AnosIpe) {
    $zipPathIpe = Join-Path $CacheDirIpe ("ipe_cia_aberta_{0}.zip" -f $anoIpe)
    try {
        if (-not (Test-Path $zipPathIpe)) {
            [Console]::WriteLine(("  IPE {0}: baixando..." -f $anoIpe))
            Invoke-WebRequest -Uri ("https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_{0}.zip" -f $anoIpe) -OutFile $zipPathIpe -UseBasicParsing -ErrorAction Stop
        }
    } catch {
        [Console]::WriteLine(("  IPE {0}: indisponivel ({1})" -f $anoIpe, $_.Exception.Message))
        continue
    }
    $extractDirIpe = Join-Path $CacheDirIpe ("ipe_{0}" -f $anoIpe)
    if (-not (Test-Path $extractDirIpe)) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPathIpe, $extractDirIpe)
    }
    $csvPathIpe = Get-ChildItem $extractDirIpe -Filter '*.csv' | Select-Object -First 1 -ExpandProperty FullName
    if (-not $csvPathIpe) { [Console]::WriteLine(("  IPE {0}: CSV nao encontrado no zip" -f $anoIpe)); continue }

    $latin1Ipe = [Text.Encoding]::GetEncoding('ISO-8859-1')
    $readerIpe = New-Object System.IO.StreamReader($csvPathIpe, $latin1Ipe)
    $nLabelsAno = 0
    try {
        $headerIpe = $readerIpe.ReadLine().Split(';')
        $ixIpe = @{}
        for ($hi = 0; $hi -lt $headerIpe.Count; $hi++) { $ixIpe[$headerIpe[$hi].Trim()] = $hi }
        $colsNecessarias = @('Nome_Companhia', 'CNPJ_Companhia', 'Categoria', 'Assunto', 'Data_Entrega', 'Protocolo_Entrega')
        $temTodasColunas = $true
        foreach ($col in $colsNecessarias) { if (-not $ixIpe.ContainsKey($col)) { $temTodasColunas = $false } }
        if (-not $temTodasColunas) { [Console]::WriteLine(("  IPE {0}: schema inesperado, pulando" -f $anoIpe)); continue }
        while ($null -ne ($linhaIpe = $readerIpe.ReadLine())) {
            if ([string]::IsNullOrWhiteSpace($linhaIpe)) { continue }
            $ci = $linhaIpe.Split(';')
            if ($ci.Count -le $ixIpe['Protocolo_Entrega']) { continue }
            $categoriaIpe = $ci[$ixIpe['Categoria']].Trim()
            $assuntoIpe = $ci[$ixIpe['Assunto']].Trim()
            $ehSeveroIpe = ($categoriaIpe -eq $CategoriaRJREIpe)
            if (-not $ehSeveroIpe -and ($CategoriasBaseIpe -contains $categoriaIpe)) {
                $assuntoNormIpe = (Remover-AcentosIpe $assuntoIpe).ToUpperInvariant()
                if ($assuntoNormIpe -match $RxSeveroIpe) { $ehSeveroIpe = $true }
            }
            if (-not $ehSeveroIpe) { continue }
            $cnpjDigitosIpe = ($ci[$ixIpe['CNPJ_Companhia']] -replace '[^0-9]', '')
            if (-not $cnpjParaEmissorIpe.ContainsKey($cnpjDigitosIpe)) { continue }
            $empresaIpe = $cnpjParaEmissorIpe[$cnpjDigitosIpe]
            $dataEntregaIpe = $ci[$ixIpe['Data_Entrega']].Trim()
            $tituloIpe = $assuntoIpe
            if ([string]::IsNullOrWhiteSpace($tituloIpe)) { $tituloIpe = $categoriaIpe }
            $evSintetico = [pscustomobject]@{
                data_evento    = $dataEntregaIpe
                titulo         = $tituloIpe
                classificacao  = 'CRITICO'
                tags           = Categoria-ParaTags $categoriaIpe
                fonte_tipo     = 'CVM'
                _oficial_tier1 = $true
            }
            $antesCount = $labels.Count
            Add-Label $empresaIpe '' $evSintetico ('ipe:' + $anoIpe)
            if ($labels.Count -gt $antesCount) { $nLabelsAno++; $ipeLabelsCount++ }
        }
    } finally {
        $readerIpe.Dispose()
    }
    [Console]::WriteLine(('  IPE {0}: {1} labels novos' -f $anoIpe, $nLabelsAno))
}
[Console]::WriteLine(('IPE total: {0} labels (ground truth CVM, multi-ano)' -f $ipeLabelsCount))

# ---- 4. Gravar JSONL ordenado por data ----
$ordenados = $labels | Sort-Object data_evento, empresa
$linhas = $ordenados | ForEach-Object { $_ | ConvertTo-Json -Depth 4 -Compress }
[System.IO.File]::WriteAllLines($OutPath, [string[]]$linhas, $Utf8NoBom)

[Console]::WriteLine('')
[Console]::WriteLine(('FIM: {0} labels unicos ({1} semanas KV + {2} scans) -> {3}' -f $labels.Count, $semanasOk, $scansOk, $OutPath))
if ($labels.Count -lt 1) { exit 1 }
exit 0
