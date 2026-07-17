# reconciliar_ipe_cvm.ps1
# VIX Radar - reconciliador semanal CVM IPE vs classificacao do Radar (nota Obsidian 60,
# recomendacao 3, 2026-07-16).
#
# Problema que resolve: o Radar decide severidade (CRITICO/RELEVANTE) por heuristica de LLM
# sobre imprensa e busca web. Quando essa heuristica falha em silencio (RESEARCHDOWN1,
# 2026-07-15: verificador aprovou um CRITICO real e um gate deterministico rebaixou mesmo
# assim), a unica forma de saber que algo escapou era varredura manual ou admin_sweep_
# revalidacao (caro, chamada paga). Este script responde de forma deterministica e gratuita:
# baixa o dataset oficial da CVM (Fato Relevante e categorias correlatas), filtra documentos
# que sinalizam RJ/RE/default/reestruturacao/inadimplencia, cruza por CNPJ contra o universo
# de emissores do Radar, e verifica se cada emissor com documento severo tem um evento
# CRITICO correspondente no estado semanal do Radar (radar:estado:{semana}, KV producao).
# Emissor com documento severo SEM CRITICO correspondente = divergencia = miss potencial.
#
# Fonte de dados: dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_{ano}.zip
#   (mesmo dataset que o Worker consome em syncCVMAutomatico, api/v4.9.161.js:6268+).
#   Publicacao semanal aos domingos (~07h BRT, medido uma vez em 12/07/2026 - nota 60).
# Universo de emissores: scripts/predictive/cnpj_emissores.json (nome -> CNPJ, ja com o guard
#   de entidade de atualizar_altman_cvm.ps1). Emissores sem CNPJ mapeado (PRED3, hoje 22) nao
#   podem ser reconciliados - reportados como gap informativo, nao como divergencia.
# Estado do Radar: KV radar:estado:{semanaISO} lido via wrangler CLI (--remote), replicando
#   em PowerShell a mesma funcao semanaISO() do Worker (api/v4.9.161.js:9455) para bater
#   exatamente com as chaves que o Worker grava.
#
# Janela e limitacoes conhecidas (nota 60): o lag de publicacao do IPE foi medido uma vez
# (~5 dias); a data_evento do Fato Relevante e a do protocolo, posterior ao vazamento na
# imprensa em parte dos casos - serve para reconciliacao de cobertura, nao para lead time.
#
# Canais de alerta: nota Obsidian (sempre) + e-mail Resend (se RESEND_API_KEY) + toast Windows
#   (padrao de run_vixradar_ranking_mensal.ps1). KV publicado: radar:reconciliacao_cvm:latest
#   (chave nova, sem consumidor no Worker ainda - zero risco ao caminho de score/ingestao).
# Exit codes: 0 ok (com ou sem divergencias - divergencia e dado, nao falha de execucao)
#             1 falha ao baixar/parsear o IPE · 2 falha ao ler todas as semanas de estado do KV
#
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\predictive\reconciliar_ipe_cvm.ps1" [-DiasJanela 10] [-SemanasEstado 3] [-DryRun] [-Quiet]

param(
    [int]$DiasJanela = 10,
    [int]$SemanasEstado = 3,
    [switch]$DryRun,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ApiDir      = Join-Path $ProjectRoot 'api'
$NamespaceId = 'c6805b8d8a7b468e9f854ab4f91fb93a'
$CacheDir    = Join-Path $ProjectRoot 'data\cvm'
$OutDir      = Join-Path $ProjectRoot 'data\reconciliacao'
$PredDir     = Join-Path $ProjectRoot 'scripts\predictive'
$MapPath     = Join-Path $PredDir 'cnpj_emissores.json'
$ReviewPath  = Join-Path $PredDir 'cnpj_emissores.review.json'
$LogDir      = Join-Path $ProjectRoot 'logs\routines'
$VaultDir    = Join-Path $ProjectRoot 'Obsidian VIX Radar\Reconciliacao-CVM'

if ($DryRun) {
    $OutDir   = Join-Path $ProjectRoot 'data\reconciliacao\dryrun'
    $VaultDir = Join-Path $ProjectRoot 'Obsidian VIX Radar\Reconciliacao-CVM\dryrun'
}

New-Item -ItemType Directory -Force -Path $CacheDir, $OutDir, $LogDir, $VaultDir | Out-Null

# Janela temporal em UTC-3 (regra do projeto - nunca UTC puro para datas de negocio)
$NowBrt  = (Get-Date).ToUniversalTime().AddHours(-3)
$Stamp   = $NowBrt.ToString('yyyyMMdd_HHmmss')
$DataRef = $NowBrt.ToString('yyyy-MM-dd')
$LogPath = Join-Path $LogDir ("vixradar-reconciliacao-cvm_{0}.log" -f $Stamp)

function Write-Log([string]$Msg) {
    $line = ('[{0}] {1}' -f ((Get-Date).ToUniversalTime().AddHours(-3).ToString('yyyy-MM-dd HH:mm:ss')), $Msg)
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Write-Output $line
}

# Mutex contra instancia duplicada (padrao das rotinas do projeto)
$mutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-reconciliacao-cvm')
if (-not $mutex.WaitOne(0)) {
    Write-Log 'AVISO: instancia duplicada detectada - abortando esta instancia'
    exit 0
}

$exitCode = 0
try {
    Write-Log ('INICIO: reconciliacao IPE CVM vs estado Radar (janela {0}d, {1} semanas, DryRun={2})' -f $DiasJanela, $SemanasEstado, [bool]$DryRun)

    # ---------------------------------------------------------------
    # 1. semanaISO() replicada de api/v4.9.161.js:9455 - tem que bater exatamente com as
    #    chaves que o Worker grava (radar:estado:{ano}-W{semana}), senao le a semana errada
    #    e gera falso positivo de divergencia.
    # ---------------------------------------------------------------
    function Get-SemanaISO([DateTime]$d) {
        $data = [DateTime]::new($d.Year, $d.Month, $d.Day, 0, 0, 0, [DateTimeKind]::Utc)
        $dia = [int]$data.DayOfWeek
        if ($dia -eq 0) { $dia = 7 }
        $data = $data.AddDays(4 - $dia)
        $pj = [DateTime]::new($data.Year, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
        $semana = [int][Math]::Ceiling((($data - $pj).TotalDays + 1) / 7)
        return ('{0}-W{1:D2}' -f $data.Year, $semana)
    }

    # ---------------------------------------------------------------
    # 2. Universo de emissores: cnpj_emissores.json (nome -> CNPJ), guard de entidade ja
    #    aplicado por atualizar_altman_cvm.ps1. Entradas sem CNPJ nao entram nesse arquivo -
    #    ficam em cnpj_emissores.review.json (PRED3, gap informativo, nao reconciliavel ainda).
    # ---------------------------------------------------------------
    if (-not (Test-Path $MapPath)) { throw "Mapa CNPJ ausente: $MapPath - rode atualizar_altman_cvm.ps1 primeiro" }
    $mapaJson = [System.IO.File]::ReadAllText($MapPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $cnpjParaEmissor = @{}
    foreach ($p in $mapaJson.PSObject.Properties) {
        $cnpjRaw = [string]$p.Value.cnpj
        if ([string]::IsNullOrWhiteSpace($cnpjRaw)) { continue }
        $cnpjDigitos = ($cnpjRaw -replace '[^0-9]', '')
        $cnpjParaEmissor[$cnpjDigitos] = $p.Name
    }
    $semCnpj = @()
    if (Test-Path $ReviewPath) {
        $reviewJson = [System.IO.File]::ReadAllText($ReviewPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($p in $reviewJson.PSObject.Properties) { if ($p.Name.StartsWith('_')) { continue }; $semCnpj += $p.Name }
    }
    Write-Log ("Universo: {0} emissores com CNPJ mapeado, {1} sem CNPJ (gap informativo - PRED3)" -f $cnpjParaEmissor.Count, $semCnpj.Count)

    # ---------------------------------------------------------------
    # 3. Download do IPE (mesmo dataset do Worker) - zip de arquivo unico, extraido via
    #    ZipFile (a Worker runtime usa um decoder deflate manual por limitacao do isolate;
    #    PowerShell tem .NET completo, sem essa limitacao).
    # ---------------------------------------------------------------
    $ano = (Get-Date).Year
    $zipPath = Join-Path $CacheDir ("ipe_cia_aberta_{0}.zip" -f $ano)
    Write-Log ("Baixando IPE {0} (dados.cvm.gov.br)..." -f $ano)
    Invoke-WebRequest -Uri ("https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_{0}.zip" -f $ano) -OutFile $zipPath -UseBasicParsing
    $extractDir = Join-Path $CacheDir ("ipe_{0}" -f $ano)
    if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir)
    $csvPath = Get-ChildItem $extractDir -Filter '*.csv' | Select-Object -First 1 -ExpandProperty FullName
    if (-not $csvPath) { throw "Nenhum CSV encontrado dentro do zip IPE ($extractDir)" }
    Write-Log ("CSV extraido: {0}" -f (Split-Path $csvPath -Leaf))

    # ---------------------------------------------------------------
    # 4. Parse do CSV (latin-1, ';' - mesmo padrao dos demais CSVs CVM no projeto).
    #    Header lido dinamicamente por nome de coluna (robusto a reordenacao do dataset).
    # ---------------------------------------------------------------
    $dataMin = $NowBrt.AddDays(-1 * $DiasJanela).ToString('yyyy-MM-dd')
    $latin1 = [Text.Encoding]::GetEncoding('ISO-8859-1')
    $reader = New-Object System.IO.StreamReader($csvPath, $latin1)
    $CategoriaRJRE = 'Informações de Companhias em Recuperação Judicial ou Extrajudicial'
    $CategoriasBase = @('Fato Relevante', 'Comunicado ao Mercado')
    # Palavras-chave de severidade dentro de Fato Relevante/Comunicado ao Mercado - evita
    # marcar rotina (resultado trimestral, aumento de capital) como severo. Sem acento
    # (Normalizar remove diacritico antes do match) para nao depender de variacao ortografica.
    $RxSevero = 'RECUPERA(C|CA)AO\s+(JUDICIAL|EXTRAJUDICIAL)|PLANO DE RECUPERA|INADIMPL|MORATORIA|REESTRUTURA(C|CA)AO DE DIVIDA|DEFAULT|VENCIMENTO ANTECIPADO|NAO[- ]PAGAMENTO|NAO PAGAMENTO|CALOTE|CROSS.DEFAULT|COVENANT'

    function Remover-Acentos([string]$s) {
        $n = $s.Normalize([Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($c in $n.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
        }
        return $sb.ToString()
    }

    $documentosSeveros = @()
    try {
        $header = $reader.ReadLine().Split(';')
        $ix = @{}
        for ($i = 0; $i -lt $header.Count; $i++) { $ix[$header[$i].Trim()] = $i }
        foreach ($col in @('Nome_Companhia', 'CNPJ_Companhia', 'Categoria', 'Assunto', 'Data_Referencia', 'Data_Entrega', 'Link_Download', 'Protocolo_Entrega')) {
            if (-not $ix.ContainsKey($col)) { throw "Coluna ausente no IPE: $col (dataset pode ter mudado de schema)" }
        }
        $totalLinhas = 0
        while ($null -ne ($linha = $reader.ReadLine())) {
            if ([string]::IsNullOrWhiteSpace($linha)) { continue }
            $totalLinhas++
            $c = $linha.Split(';')
            if ($c.Count -le $ix['Protocolo_Entrega']) { continue }
            $entrega = $c[$ix['Data_Entrega']].Trim()
            if ($entrega -lt $dataMin) { continue }
            $categoria = $c[$ix['Categoria']].Trim()
            $assunto = $c[$ix['Assunto']].Trim()
            $ehRJRE = ($categoria -eq $CategoriaRJRE)
            $ehSevero = $ehRJRE
            if (-not $ehSevero -and ($CategoriasBase -contains $categoria)) {
                $assuntoNorm = (Remover-Acentos $assunto).ToUpperInvariant()
                if ($assuntoNorm -match $RxSevero) { $ehSevero = $true }
            }
            if (-not $ehSevero) { continue }
            $cnpjDigitos = ($c[$ix['CNPJ_Companhia']] -replace '[^0-9]', '')
            $documentosSeveros += [pscustomobject]@{
                nome_cvm        = $c[$ix['Nome_Companhia']].Trim()
                cnpj            = $cnpjDigitos
                categoria       = $categoria
                assunto         = $assunto
                data_referencia = $c[$ix['Data_Referencia']].Trim()
                data_entrega    = $entrega
                link            = $c[$ix['Link_Download']].Trim()
                protocolo       = $c[$ix['Protocolo_Entrega']].Trim()
            }
        }
        Write-Log ("IPE {0}: {1} linhas total, {2} documentos severos na janela >= {3}" -f $ano, $totalLinhas, $documentosSeveros.Count, $dataMin)
    } finally {
        $reader.Dispose()
    }

    # ---------------------------------------------------------------
    # 5. Join por CNPJ contra o universo do Radar + dedup por (emissor, protocolo)
    # ---------------------------------------------------------------
    $candidatos = @{}
    foreach ($doc in $documentosSeveros) {
        if (-not $cnpjParaEmissor.ContainsKey($doc.cnpj)) { continue }
        $emissor = $cnpjParaEmissor[$doc.cnpj]
        $chave = $emissor + '|' + $doc.protocolo
        if ($candidatos.ContainsKey($chave)) { continue }
        $candidatos[$chave] = [pscustomobject]@{
            emissor         = $emissor
            categoria       = $doc.categoria
            assunto         = $doc.assunto
            data_referencia = $doc.data_referencia
            data_entrega    = $doc.data_entrega
            link            = $doc.link
            protocolo       = $doc.protocolo
        }
    }
    # @() explicito: sem isso, Group-Object|ForEach-Object com 1 unico grupo colapsa para
    # objeto escalar em vez de array de 1 elemento (mesma classe de bug de CHUNK1,
    # PENDENCIAS.md), e $emissoresComDocSevero.Count vira $null silenciosamente.
    $emissoresComDocSevero = @($candidatos.Values | Group-Object emissor | ForEach-Object {
        [pscustomobject]@{ emissor = $_.Name; docs = @($_.Group | Sort-Object data_entrega -Descending) }
    })
    Write-Log ("Join por CNPJ: {0} documento(s) severo(s) casaram com {1} emissor(es) do universo Radar" -f $candidatos.Count, $emissoresComDocSevero.Count)

    # ---------------------------------------------------------------
    # 6. Estado do Radar - le as N semanas ISO mais recentes via wrangler kv key get --remote
    #    e marca quais emissores ja tem CRITICO em qualquer uma delas. Nao precisa bater a
    #    data exata do evento com a data do documento CVM - a pergunta e binaria: "o Radar
    #    tem CRITICO para este emissor nas semanas recentes, sim ou nao".
    # ---------------------------------------------------------------
    $semanas = @()
    for ($i = 0; $i -lt $SemanasEstado; $i++) {
        $s = Get-SemanaISO ($NowBrt.AddDays(-7 * $i))
        if ($semanas -notcontains $s) { $semanas += $s }
    }
    Write-Log ("Semanas de estado a conferir: {0}" -f ($semanas -join ', '))

    $criticosPorEmissor = @{}
    $relevantesPorEmissor = @{}
    $semanasLidas = 0
    Push-Location $ApiDir
    foreach ($sem in $semanas) {
        $tmpPath = Join-Path $env:TEMP ("radar_estado_{0}.json" -f $sem)
        $errFile = Join-Path $env:TEMP ("radar_estado_{0}.err" -f $sem)
        & npx wrangler kv key get "radar:estado:$sem" --namespace-id $NamespaceId --remote 2>$errFile | Out-File -FilePath $tmpPath -Encoding utf8
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmpPath) -or (Get-Item $tmpPath).Length -eq 0) {
            Write-Log ("AVISO: leitura de radar:estado:{0} falhou ou vazia - {1}" -f $sem, ((Get-Content $errFile -TotalCount 2 -ErrorAction SilentlyContinue) -join ' '))
            continue
        }
        try {
            # -AsHashTable resolve case sensitivity de chaves no JSON (ex.: "teste" vs "Teste" no
            # mesmo objeto quebrava ConvertFrom-Json padrao). Hashtable ignora casing.
            $estado = [System.IO.File]::ReadAllText($tmpPath, [Text.Encoding]::UTF8) | ConvertFrom-Json -AsHashTable
            $semanasLidas++
            $results = $estado['results']
            foreach ($kv in $results.GetEnumerator()) {
                $emissor = $kv.Key
                # Guard contra eventos null ou chave ausente: @($null) produz array com 1 elemento
                # null em vez de array vazio no PowerShell, quebrando o foreach interno com
                # "Cannot index into a null array" ao acessar $ev['classificacao'].
                $eventosRaw = $kv.Value['eventos']
                $eventos = if ($null -eq $eventosRaw) { @() } else { @($eventosRaw) }
                foreach ($ev in $eventos) {
                    if ($null -eq $ev) { continue }
                    if ($ev['classificacao'] -eq 'CRITICO') { $criticosPorEmissor[$emissor] = $true }
                    elseif ($ev['classificacao'] -eq 'RELEVANTE') { $relevantesPorEmissor[$emissor] = $true }
                }
            }
        } catch {
            Write-Log ("AVISO: parse de radar:estado:{0} falhou - {1}" -f $sem, $_.Exception.Message)
        } finally {
            Remove-Item $tmpPath, $errFile -ErrorAction SilentlyContinue
        }
    }
    Pop-Location
    if ($semanasLidas -eq 0) { throw "Nenhuma das $($semanas.Count) semanas de estado pode ser lida do KV - abortando sem publicar divergencias (dado incompleto e pior que nao ter dado)" }
    Write-Log ("Estado do Radar: {0}/{1} semanas lidas, {2} emissor(es) com CRITICO ativo, {3} com RELEVANTE" -f $semanasLidas, $semanas.Count, $criticosPorEmissor.Count, $relevantesPorEmissor.Count)

    # ---------------------------------------------------------------
    # 7. Divergencias: emissor com documento severo no IPE, SEM CRITICO correspondente nas
    #    semanas recentes do Radar. Marca tambem se pelo menos existe RELEVANTE (rebaixamento
    #    possivel, o padrao do RESEARCHDOWN1) vs nenhum evento (miss total).
    # ---------------------------------------------------------------
    $divergencias = @()
    foreach ($item in $emissoresComDocSevero) {
        if ($criticosPorEmissor.ContainsKey($item.emissor)) { continue }
        $tipo = if ($relevantesPorEmissor.ContainsKey($item.emissor)) { 'rebaixado_para_relevante_ou_menor' } else { 'sem_evento_correspondente' }
        $divergencias += [pscustomobject]@{
            emissor        = $item.emissor
            tipo           = $tipo
            n_documentos   = $item.docs.Count
            documento_mais_recente = $item.docs[0]
            todos_documentos = $item.docs
        }
    }
    $divergencias = @($divergencias | Sort-Object { $_.documento_mais_recente.data_entrega } -Descending)
    Write-Log ("DIVERGENCIAS: {0}" -f $divergencias.Count)
    foreach ($d in $divergencias) {
        Write-Log ("  {0} [{1}] - {2} doc(s), mais recente {3} ({4})" -f $d.emissor, $d.tipo, $d.n_documentos, $d.documento_mais_recente.data_entrega, $d.documento_mais_recente.categoria)
    }

    # ---------------------------------------------------------------
    # 8. Relatorio JSON (auditoria/historico) + publicacao KV (informativa, sem consumidor
    #    no Worker ainda - zero risco ao caminho de score/ingestao)
    # ---------------------------------------------------------------
    $payload = [ordered]@{
        schema_version       = 1
        gerado_em            = $NowBrt.ToString('yyyy-MM-dd HH:mm:ss')
        janela_dias          = $DiasJanela
        data_min_documento   = $dataMin
        semanas_estado       = $semanas
        semanas_lidas        = $semanasLidas
        total_documentos_severos_ipe = $documentosSeveros.Count
        total_emissores_com_doc_severo = $emissoresComDocSevero.Count
        total_divergencias   = $divergencias.Count
        emissores_sem_cnpj_gap = $semCnpj.Count
        divergencias         = $divergencias
        dry_run              = [bool]$DryRun
    }
    $relPath = Join-Path $OutDir ("reconciliacao_cvm_{0}.json" -f $DataRef)
    [System.IO.File]::WriteAllText($relPath, ($payload | ConvertTo-Json -Depth 8), $Utf8NoBom)
    Write-Log ("Relatorio gravado: {0}" -f $relPath)

    if (-not $DryRun) {
        $ErrorActionPreference = 'Continue'
        Push-Location $ApiDir
        $kvErrFile = Join-Path $env:TEMP 'reconciliacao_kvput.err'
        & npx wrangler kv key put 'radar:reconciliacao_cvm:latest' --path $relPath --namespace-id $NamespaceId --remote 2>$kvErrFile
        $kvCode = $LASTEXITCODE
        Pop-Location
        $ErrorActionPreference = 'Stop'
        if ($kvCode -ne 0) { Write-Log ('AVISO: kv put radar:reconciliacao_cvm:latest falhou - ' + ((Get-Content $kvErrFile -TotalCount 2 -ErrorAction SilentlyContinue) -join ' ')) }
        else { Write-Log 'Publicado: radar:reconciliacao_cvm:latest no KV de producao' }
    } else {
        Write-Log 'DryRun: KV nao publicado'
    }

    # ---------------------------------------------------------------
    # 9. Nota Obsidian (sempre) - padrao de run_vixradar_ranking_mensal.ps1
    # ---------------------------------------------------------------
    $notaPath = Join-Path $VaultDir ("Reconciliacao {0}.md" -f $DataRef)
    $nl = [Environment]::NewLine
    $nota = "# Reconciliacao CVM IPE vs Estado Radar - $DataRef$nl$nl"
    $nota += "Gerado por reconciliar_ipe_cvm.ps1 (janela ${DiasJanela}d, semanas $($semanas -join ', '), $semanasLidas/$($semanas.Count) lidas).$nl$nl"
    $nota += "Documentos severos no IPE (RJ/RE/default/reestruturacao/inadimplencia) na janela: **$($documentosSeveros.Count)**, casando com **$($emissoresComDocSevero.Count)** emissor(es) do universo Radar.$nl$nl"
    if ($divergencias.Count -gt 0) {
        $nota += "## DIVERGENCIAS ($($divergencias.Count))$nl$nl"
        $nota += "Emissor com documento severo na CVM sem CRITICO correspondente nas semanas recentes do Radar.$nl$nl"
        $nota += "| Emissor | Tipo | Docs | Mais recente | Categoria | Link |$nl|---|---|---|---|---|---|$nl"
        foreach ($d in $divergencias) {
            $doc = $d.documento_mais_recente
            $nota += "| $($d.emissor) | $($d.tipo) | $($d.n_documentos) | $($doc.data_entrega) | $($doc.categoria) | [protocolo]($($doc.link)) |$nl"
        }
        $nota += $nl
    } else {
        $nota += "Sem divergencias neste ciclo - todo emissor com documento severo na janela tem CRITICO correspondente.$nl$nl"
    }
    if ($semCnpj.Count -gt 0) {
        $nota += "**Gap informativo:** $($semCnpj.Count) emissor(es) sem CNPJ mapeado nao puderam ser reconciliados (PRED3): $($semCnpj -join ', ').$nl"
    }
    Set-Content -Path $notaPath -Value $nota -Encoding UTF8
    Write-Log ("Nota Obsidian gravada: {0}" -f $notaPath)

    # ---------------------------------------------------------------
    # 10. Alerta - e-mail Resend + toast (so se houver divergencias, e nao em DryRun)
    # ---------------------------------------------------------------
    if ($divergencias.Count -gt 0) {
        if (-not $DryRun) {
            if ($env:RESEND_API_KEY) {
                try {
                    $emailPara = 'szuchmacheryan@gmail.com'
                    $emailDe   = 'VIX Radar <onboarding@resend.dev>'
                    $htmlItens = ($divergencias | ForEach-Object {
                        '<li><strong>' + $_.emissor + '</strong> (' + $_.tipo + ') - ' + $_.n_documentos + ' doc(s), mais recente ' + $_.documento_mais_recente.data_entrega + ' [' + $_.documento_mais_recente.categoria + ']</li>'
                    }) -join ''
                    $body = @{
                        from    = $emailDe
                        to      = @($emailPara)
                        subject = ("VIX Radar - reconciliacao CVM: {0} divergencia(s) em {1}" -f $divergencias.Count, $DataRef)
                        html    = ('<p>Reconciliador semanal encontrou emissor(es) com documento severo na CVM (RJ/RE/default/reestruturacao/inadimplencia) sem CRITICO correspondente no Radar:</p><ul>' + $htmlItens + '</ul><p>Detalhes na nota Obsidian "Reconciliacao ' + $DataRef + '".</p>')
                    } | ConvertTo-Json -Depth 4
                    Invoke-RestMethod -Uri 'https://api.resend.com/emails' -Method Post -ContentType 'application/json' `
                        -Headers @{ Authorization = ('Bearer ' + $env:RESEND_API_KEY) } -Body $body | Out-Null
                    Write-Log ('E-mail de alerta enviado para ' + $emailPara)
                } catch {
                    Write-Log ('AVISO: falha ao enviar e-mail Resend: ' + $_.Exception.Message)
                }
            } else {
                Write-Log 'AVISO: RESEND_API_KEY ausente - alerta por e-mail NAO enviado'
            }
            if (-not $Quiet) {
                try {
                    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
                    $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
                    $textos = $template.GetElementsByTagName('text')
                    $textos.Item(0).AppendChild($template.CreateTextNode('VIX Radar - reconciliacao CVM')) | Out-Null
                    $textos.Item(1).AppendChild($template.CreateTextNode(("{0} divergencia(s) contra o dataset oficial da CVM. Ver nota Obsidian." -f $divergencias.Count))) | Out-Null
                    $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
                    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('VIX Radar').Show($toast)
                    Write-Log 'Toast exibido'
                } catch {
                    Write-Log ('AVISO: toast indisponivel neste host: ' + $_.Exception.Message)
                }
            }
        } else {
            Write-Log ('DryRun: {0} divergencia(s) encontradas mas alerta NAO enviado' -f $divergencias.Count)
        }
    } else {
        Write-Log 'Sem divergencias neste ciclo'
    }

    # Metricas (padrao das rotinas)
    $metrics = [pscustomobject]@{
        data                    = $DataRef
        janela_dias             = $DiasJanela
        documentos_severos_ipe  = $documentosSeveros.Count
        emissores_com_doc_severo = $emissoresComDocSevero.Count
        divergencias            = $divergencias.Count
        semanas_lidas           = $semanasLidas
        semanas_total           = $semanas.Count
        emissores_sem_cnpj_gap  = $semCnpj.Count
        dry_run                 = [bool]$DryRun
        exit                    = 0
    }
    $metrics | ConvertTo-Json | Set-Content -Path (Join-Path $LogDir ("vixradar-reconciliacao-cvm_metrics_{0}.json" -f $Stamp)) -Encoding UTF8

    Write-Log ("FIM: ok - {0} documentos severos, {1} emissores casados, {2} divergencias" -f $documentosSeveros.Count, $emissoresComDocSevero.Count, $divergencias.Count)
    $exitCode = 0
} catch {
    Write-Log ('ERRO FATAL: ' + $_.Exception.Message)
    $exitCode = 1
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
exit $exitCode
