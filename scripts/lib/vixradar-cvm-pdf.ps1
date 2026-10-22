# vixradar-cvm-pdf.ps1 - CVMPDF1: texto legivel dos documentos IPE da CVM, extraido localmente.
#
# Problema medido em 19, 20 e 21/10/2026 (7, 11 e 11 ANOTA por dia nos logs das rotinas): o WebFetch do
# modelo recebe o PDF do ENET como binario (FlateDecode) e a familia F3 cai para busca web de fallback.
# Prova de 21/10: curl.exe --http1.1 baixa o mesmo PDF inteiro e pdftotext extrai texto legivel.
#
# Contrato: fail-open. Qualquer falha devolve $null e a rotina segue exatamente como antes.
# Desligado por padrao: so age com VIXRADAR_CVM_PDF_TEXTO=1 (env User, Process ou Machine).
# O texto extraido e DADO nao confiavel (pode conter instrucao embutida), nunca comando.
# Compativel com Windows PowerShell 5.1, so ASCII.

$script:VixCvmPdfHostPermitido = '^https://www\.rad\.cvm\.gov\.br/ENET/frmDownloadDocumento\.aspx\?'
$script:VixCvmPdfCacheMem = @{}

function Test-VixCvmPdfTextoHabilitado {
    foreach ($escopo in 'Process', 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', $escopo)
        if ($null -ne $v -and $v -ne '') { return ($v.Trim() -eq '1') }
    }
    return $false
}

function Get-VixPdftotextPath {
    $cmd = Get-Command 'pdftotext.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @('C:\Program Files\Git\mingw64\bin\pdftotext.exe', 'C:\Program Files\Git\usr\bin\pdftotext.exe')) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Test-VixCvmPdfLinkValido {
    param([string]$Link)
    if (-not $Link) { return $false }
    return ($Link -match $script:VixCvmPdfHostPermitido)
}

function Get-VixCvmPdfChave {
    param([string]$Link)
    if ($Link -match 'numProtocolo=(\d+)') { return ('p' + $Matches[1] + '_s' + $(if ($Link -match 'numSequencia=(\d+)') { $Matches[1] } else { '0' })) }
    return $null
}

# Extrai o texto de um PDF ja em disco. Devolve $null se nao for PDF ou nao houver texto.
function Get-VixPdfTextoDeArquivo {
    param([string]$Arquivo, [int]$MaxChars = 3000, [string]$Pdftotext = '')
    try {
        if (-not (Test-Path -LiteralPath $Arquivo)) { return $null }
        $fs = [System.IO.File]::OpenRead($Arquivo)
        try {
            $cab = New-Object byte[] 5
            [void]$fs.Read($cab, 0, 5)
        } finally { $fs.Dispose() }
        if ([System.Text.Encoding]::ASCII.GetString($cab) -ne '%PDF-') { return $null }
        if (-not $Pdftotext) { $Pdftotext = Get-VixPdftotextPath }
        if (-not $Pdftotext) { return $null }
        $txt = $Arquivo + '.txt'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Pdftotext
        $psi.Arguments = '-layout -enc UTF-8 -l 12 "' + $Arquivo + '" "' + $txt + '"'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc.WaitForExit(60000)) { try { $proc.Kill() } catch { }; return $null }
        if (-not (Test-Path -LiteralPath $txt)) { return $null }
        $t = [System.IO.File]::ReadAllText($txt, [System.Text.Encoding]::UTF8)
        Remove-Item -LiteralPath $txt -Force -ErrorAction SilentlyContinue
        $t = ($t -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ' ') -replace '\s+', ' '
        $t = $t.Trim()
        if ($t.Length -lt 40) { return $null }
        if ($t.Length -gt $MaxChars) { $t = $t.Substring(0, $MaxChars) }
        return $t
    } catch {
        return $null
    }
}

# Baixa (com cache) e extrai. Devolve $null quando desligado, link fora da allowlist ou qualquer falha.
function Get-VixCvmDocumentoTexto {
    param([string]$Link, [int]$MaxChars = 3000, [string]$CacheDir = '', [switch]$IgnorarFlag)
    try {
        if (-not $IgnorarFlag -and -not (Test-VixCvmPdfTextoHabilitado)) { return $null }
        if (-not (Test-VixCvmPdfLinkValido $Link)) { return $null }
        $chave = Get-VixCvmPdfChave $Link
        if (-not $chave) { return $null }
        if ($script:VixCvmPdfCacheMem.ContainsKey($chave)) { return $script:VixCvmPdfCacheMem[$chave] }
        if (-not $CacheDir) { $CacheDir = Join-Path ([System.IO.Path]::GetTempPath()) 'vixradar-cvm-pdf' }
        if (-not (Test-Path -LiteralPath $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }
        $pdf = Join-Path $CacheDir ($chave + '.pdf')
        if (-not (Test-Path -LiteralPath $pdf) -or (Get-Item -LiteralPath $pdf).Length -lt 1000) {
            $ok = $false
            foreach ($tent in 1..2) {
                & curl.exe -s -L --http1.1 --max-time 30 --max-filesize 15000000 -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130 Safari/537.36' -o $pdf $Link
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $pdf) -and (Get-Item -LiteralPath $pdf).Length -ge 1000) { $ok = $true; break }
            }
            if (-not $ok) { Remove-Item -LiteralPath $pdf -Force -ErrorAction SilentlyContinue; $script:VixCvmPdfCacheMem[$chave] = $null; return $null }
        }
        $t = Get-VixPdfTextoDeArquivo -Arquivo $pdf -MaxChars $MaxChars
        $script:VixCvmPdfCacheMem[$chave] = $t
        return $t
    } catch {
        return $null
    }
}
