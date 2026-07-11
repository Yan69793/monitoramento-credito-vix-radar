# atualizar_altman_cvm.ps1
# VIX Radar - Altman Z''-EM (variante para mercados emergentes) por emissor, a partir dos
# dados abertos da CVM (DFP consolidado). Fase 3 do plano preditivo (nota 51).
#
#   Z''-EM = 3.25 + 6.56*X1 + 3.26*X2 + 6.72*X3 + 1.05*X4
#     X1 = capital de giro / ativo total            (1.01 - 2.01) / 1
#     X2 = lucros retidos / ativo total             (2.03.04 reservas de lucros + 2.03.05 lucros acum.) / 1
#     X3 = EBIT / ativo total                       DRE 3.05 / 1
#     X4 = patrimonio liquido / passivo exigivel    2.03 / (2.01 + 2.02)
#
# Regras: plano CONSOLIDADO (arquivos *_con_*), ORDEM_EXERC = ULTIMO, exercicio mais recente;
# ESCALA_MOEDA tratada (MIL -> x1000); setor Financeiro EXCLUIDO (balanco incompativel);
# CSVs CVM sao latin-1 com separador ';'. Publica UMA chave agregada no KV de producao:
# fundamentals:altman:latest (so o v4.9.150+ le; nenhum efeito no Worker atual).
#
# 1o ciclo: publica apenas matches FORTES nome->CNPJ; candidatos fracos vao para
# scripts/predictive/cnpj_emissores.review.json (revisao manual do operador).
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\predictive\atualizar_altman_cvm.ps1" [-AnoDfp 2025] [-Publicar]

param(
    [int]$AnoDfp = 2025,
    [switch]$Publicar
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ApiDir      = Join-Path $ProjectRoot 'api'
$NamespaceId = 'c6805b8d8a7b468e9f854ab4f91fb93a'
$CacheDir    = Join-Path $ProjectRoot 'data\cvm'
$PredDir     = Join-Path $ProjectRoot 'scripts\predictive'
$MapPath     = Join-Path $PredDir 'cnpj_emissores.json'
$ReviewPath  = Join-Path $PredDir 'cnpj_emissores.review.json'
$SaidaPath   = Join-Path $PredDir 'fundamentals_altman_latest.json'
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

function Log([string]$m) { [Console]::WriteLine(('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m)) }

function Normalizar([string]$s) {
    $s = $s.ToUpperInvariant()
    $s = $s.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $s.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
    }
    $s = $sb.ToString()
    $s = $s -replace '\b(S\.?A\.?|S/A|LTDA|HOLDING|PARTICIPACOES|PARTICIPACAO|CIA|COMPANHIA|GRUPO|DO BRASIL|BRASIL|\(.*\))\b', ' '
    $s = $s -replace '[^A-Z0-9 ]', ' ' -replace '\s+', ' '
    return $s.Trim()
}

# Setor Financeiro do universo (balanco incompativel com Altman) - exclusao declarada
$Financeiros = @('Itaú Unibanco','Itaúsa','BTG Pactual','Banco Pan','Banco Daycoval','Banco Votorantim','Bradesco','Cielo','B3 S.A.')

# ---------------------------------------------------------------
# 1. Universo de emissores (do ultimo dump do exporter)
# ---------------------------------------------------------------
$dumpDirs = Get-ChildItem (Join-Path $ProjectRoot 'data\historico') -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } | Sort-Object Name
if (-not $dumpDirs) { Log 'ERRO: nenhum dump em data/historico - rode o exporter antes'; exit 1 }
$predPath = Join-Path $dumpDirs[-1].FullName 'predictive.json'
$pred = [System.IO.File]::ReadAllText($predPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$emissores = @($pred.emissores | ForEach-Object { [string]$_.name })
Log ("Universo: {0} emissores (dump {1})" -f $emissores.Count, $dumpDirs[-1].Name)

# ---------------------------------------------------------------
# 2. Cadastro CVM -> mapa nome->CNPJ (usa mapa existente se houver)
# ---------------------------------------------------------------
$mapa = @{}
if (Test-Path $MapPath) {
    $mapaJson = [System.IO.File]::ReadAllText($MapPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in $mapaJson.PSObject.Properties) { $mapa[$p.Name] = $p.Value }
    Log ("Mapa CNPJ existente: {0} emissores" -f $mapa.Count)
} else {
    $cadPath = Join-Path $CacheDir 'cad_cia_aberta.csv'
    if (-not (Test-Path $cadPath)) {
        Log 'Baixando cadastro CVM (cad_cia_aberta.csv)...'
        Invoke-WebRequest -Uri 'https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv' -OutFile $cadPath -UseBasicParsing
    }
    $latin1 = [Text.Encoding]::GetEncoding('ISO-8859-1')
    $cad = Import-Csv -Path $cadPath -Delimiter ';' -Encoding Default
    # Import-Csv -Encoding Default em PS 5.1 le ANSI (cp1252) - suficiente p/ DENOM_SOCIAL
    $ativas = @($cad | Where-Object { $_.SIT -eq 'ATIVO' })
    Log ("Cadastro CVM: {0} cias ativas" -f $ativas.Count)
    $review = @{}
    foreach ($emp in $emissores) {
        $alvo = Normalizar $emp
        if (-not $alvo) { continue }
        $forte = $null; $medio = $null
        foreach ($cia in $ativas) {
            $denom = Normalizar ([string]$cia.DENOM_SOCIAL)
            if (-not $denom) { continue }
            if ($denom -eq $alvo -or $denom.StartsWith($alvo + ' ')) { $forte = $cia; break }
            if (-not $medio -and ($denom -like ('*' + $alvo + '*'))) { $medio = $cia }
        }
        if ($forte) {
            $mapa[$emp] = [pscustomobject]@{ cnpj = $forte.CNPJ_CIA; denom = $forte.DENOM_SOCIAL; match = 'forte' }
        } elseif ($medio) {
            $review[$emp] = [pscustomobject]@{ cnpj = $medio.CNPJ_CIA; denom = $medio.DENOM_SOCIAL; match = 'medio - REVISAR' }
        } else {
            $review[$emp] = [pscustomobject]@{ cnpj = $null; denom = $null; match = 'sem candidato (fechada/nao-cia-aberta?)' }
        }
    }
    [System.IO.File]::WriteAllText($MapPath, (([pscustomobject]$mapa) | ConvertTo-Json -Depth 4), $Utf8NoBom)
    [System.IO.File]::WriteAllText($ReviewPath, (([pscustomobject]$review) | ConvertTo-Json -Depth 4), $Utf8NoBom)
    Log ("Match nome->CNPJ: {0} fortes (publicaveis), {1} para revisao ({2})" -f $mapa.Count, $review.Count, $ReviewPath)
}
$cnpjSet = @{}
foreach ($k in $mapa.Keys) {
    if ($Financeiros -contains $k) { continue }
    $cnpjSet[[string]$mapa[$k].cnpj] = $k
}
Log ("CNPJs a processar (ex-financeiros): {0}" -f $cnpjSet.Count)

# ---------------------------------------------------------------
# 3. DFP consolidado (BPA/BPP/DRE) do exercicio
# ---------------------------------------------------------------
$zipPath = Join-Path $CacheDir ("dfp_cia_aberta_{0}.zip" -f $AnoDfp)
if (-not (Test-Path $zipPath)) {
    Log ("Baixando DFP {0} (dados.cvm.gov.br)..." -f $AnoDfp)
    Invoke-WebRequest -Uri ("https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/DFP/DADOS/dfp_cia_aberta_{0}.zip" -f $AnoDfp) -OutFile $zipPath -UseBasicParsing
}
$extractDir = Join-Path $CacheDir ("dfp_{0}" -f $AnoDfp)
if (-not (Test-Path $extractDir)) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir)
}

function Carregar-Contas([string]$arquivo, [hashtable]$contasAlvo) {
    # Le CSV latin-1 gigante em streaming; retorna map cnpj -> conta -> valor (escala aplicada, ORDEM_EXERC=ULTIMO)
    $path = Join-Path $extractDir $arquivo
    if (-not (Test-Path $path)) { Log ("AVISO: {0} ausente" -f $arquivo); return @{} }
    $latin1 = [Text.Encoding]::GetEncoding('ISO-8859-1')
    $reader = New-Object System.IO.StreamReader($path, $latin1)
    try {
        $header = $reader.ReadLine().Split(';')
        $ix = @{}
        for ($i = 0; $i -lt $header.Count; $i++) { $ix[$header[$i]] = $i }
        foreach ($col in @('CNPJ_CIA','CD_CONTA','VL_CONTA','ESCALA_MOEDA','ORDEM_EXERC','DT_REFER')) {
            if (-not $ix.ContainsKey($col)) { Log ("ERRO: coluna {0} ausente em {1}" -f $col, $arquivo); return @{} }
        }
        $out = @{}
        while ($null -ne ($linha = $reader.ReadLine())) {
            $c = $linha.Split(';')
            $cnpj = $c[$ix['CNPJ_CIA']]
            if (-not $cnpjSet.ContainsKey($cnpj)) { continue }
            if ($c[$ix['ORDEM_EXERC']] -notmatch 'LTIMO') { continue }   # 'ULTIMO' com U acentuado em latin-1
            $conta = $c[$ix['CD_CONTA']]
            if (-not $contasAlvo.ContainsKey($conta)) { continue }
            $val = 0.0
            # VL_CONTA usa ponto decimal (padrao dos CSVs CVM) - InvariantCulture; pt-BR leria '.' como milhar (erro 100x silencioso)
            if (-not [double]::TryParse($c[$ix['VL_CONTA']], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$val)) { continue }
            if ($c[$ix['ESCALA_MOEDA']] -match 'MIL') { $val = $val * 1000 }
            if (-not $out.ContainsKey($cnpj)) { $out[$cnpj] = @{} }
            $out[$cnpj][$conta] = $val
            $out[$cnpj]['DT_REFER'] = $c[$ix['DT_REFER']]
        }
        return $out
    } finally { $reader.Dispose() }
}

Log 'Lendo BPA consolidado (streaming)...'
$bpa = Carregar-Contas ("dfp_cia_aberta_BPA_con_{0}.csv" -f $AnoDfp) @{ '1' = 1; '1.01' = 1 }
Log ("BPA: {0} cias" -f $bpa.Count)
Log 'Lendo BPP consolidado (streaming)...'
$bpp = Carregar-Contas ("dfp_cia_aberta_BPP_con_{0}.csv" -f $AnoDfp) @{ '2.01' = 1; '2.02' = 1; '2.03' = 1; '2.03.04' = 1; '2.03.05' = 1 }
Log ("BPP: {0} cias" -f $bpp.Count)
Log 'Lendo DRE consolidada (streaming)...'
$dre = Carregar-Contas ("dfp_cia_aberta_DRE_con_{0}.csv" -f $AnoDfp) @{ '3.05' = 1 }
Log ("DRE: {0} cias" -f $dre.Count)

# ---------------------------------------------------------------
# 4. Z''-EM por emissor
# ---------------------------------------------------------------
$empresasOut = @{}
$calculados = 0
foreach ($cnpj in $cnpjSet.Keys) {
    $emp = $cnpjSet[$cnpj]
    $a = $bpa[$cnpj]; $p = $bpp[$cnpj]; $d = $dre[$cnpj]
    if (-not $a -or -not $p -or -not $a.ContainsKey('1') -or $a['1'] -eq 0) { continue }
    $at  = $a['1']
    $ac  = if ($a.ContainsKey('1.01')) { $a['1.01'] } else { 0 }
    $pc  = if ($p -and $p.ContainsKey('2.01')) { $p['2.01'] } else { 0 }
    $pnc = if ($p -and $p.ContainsKey('2.02')) { $p['2.02'] } else { 0 }
    $pl  = if ($p -and $p.ContainsKey('2.03')) { $p['2.03'] } else { 0 }
    $reservas = 0.0
    if ($p -and $p.ContainsKey('2.03.04')) { $reservas += $p['2.03.04'] }
    if ($p -and $p.ContainsKey('2.03.05')) { $reservas += $p['2.03.05'] }
    $ebit = if ($d -and $d.ContainsKey('3.05')) { $d['3.05'] } else { $null }
    $exigivel = $pc + $pnc
    if ($exigivel -le 0) { continue }
    $x1 = ($ac - $pc) / $at
    $x2 = $reservas / $at
    $x3 = if ($null -ne $ebit) { $ebit / $at } else { 0 }
    $x4 = $pl / $exigivel
    $z  = 3.25 + 6.56 * $x1 + 3.26 * $x2 + 6.72 * $x3 + 1.05 * $x4
    $empresasOut[$emp] = [ordered]@{
        z_em = [Math]::Round($z, 2)
        x1_cg_at = [Math]::Round($x1, 4); x2_ret_at = [Math]::Round($x2, 4)
        x3_ebit_at = [Math]::Round($x3, 4); x4_pl_exig = [Math]::Round($x4, 4)
        ativo_total = $at
        dt_refer = $a['DT_REFER']
        cnpj = $cnpj
        aproximacoes = @(if ($null -eq $ebit) { 'ebit_ausente_x3_zero' })
    }
    $calculados++
}
foreach ($fin in $Financeiros) { $empresasOut[$fin] = [ordered]@{ z_em = $null; motivo = 'setor financeiro - Altman nao aplicavel' } }
Log ("Z''-EM calculado para {0} emissores (+{1} financeiros = null)" -f $calculados, $Financeiros.Count)
if ($calculados -lt 3) { Log 'ERRO: menos de 3 emissores calculados - abortando sem publicar'; exit 1 }

$payload = [ordered]@{
    schema_version = 1
    gerado_em      = (Get-Date).ToUniversalTime().AddHours(-3).ToString('yyyy-MM-dd HH:mm:ss')
    fonte          = ("CVM Dados Abertos - DFP {0} consolidado (dados.cvm.gov.br)" -f $AnoDfp)
    formula        = "Z''-EM = 3.25 + 6.56*X1 + 3.26*X2 + 6.72*X3 + 1.05*X4"
    total          = $empresasOut.Count
    empresas       = $empresasOut
}
[System.IO.File]::WriteAllText($SaidaPath, ($payload | ConvertTo-Json -Depth 5), $Utf8NoBom)
Log ("Payload gravado: {0}" -f $SaidaPath)

# Amostra p/ validacao manual (gate do 1o ciclo)
foreach ($amostra in @('Petrobras','Vale','Oncoclínicas','Raízen')) {
    if ($empresasOut.Contains($amostra)) {
        $e = $empresasOut[$amostra]
        Log ("  VALIDAR {0}: z_em={1} x1={2} x2={3} x3={4} x4={5} AT={6:E2} ({7})" -f $amostra, $e.z_em, $e.x1_cg_at, $e.x2_ret_at, $e.x3_ebit_at, $e.x4_pl_exig, $e.ativo_total, $e.dt_refer)
    }
}

# ---------------------------------------------------------------
# 5. Publicar no KV (chave nova - so v4.9.150+ le; sem efeito no Worker atual)
# ---------------------------------------------------------------
if ($Publicar) {
    $ErrorActionPreference = 'Continue'
    Push-Location $ApiDir
    $errFile = Join-Path $env:TEMP 'altman_kvput.err'
    & npx wrangler kv key put 'fundamentals:altman:latest' --path $SaidaPath --namespace-id $NamespaceId --remote 2>$errFile
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -ne 0) { Log ('ERRO: kv put falhou - ' + ((Get-Content $errFile -TotalCount 2) -join ' ')); exit 1 }
    Log 'Publicado: fundamentals:altman:latest no KV de producao'
} else {
    Log 'NAO publicado (rode com -Publicar apos validar a amostra acima)'
}
exit 0
