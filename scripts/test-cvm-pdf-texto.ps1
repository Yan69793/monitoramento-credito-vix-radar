# test-cvm-pdf-texto.ps1 - prova de duas pontas do CVMPDF1 (lib\vixradar-cvm-pdf.ps1).
# Offline por padrao: gera um PDF minimo com texto, nao toca rede, mutex nem rotina viva.
# -Rede baixa 1 documento real da CVM (somente leitura) para provar o caminho completo.
# Saida por exit code (0 = tudo passou).
param([switch]$Rede, [string]$LinkRede = '')
$ErrorActionPreference = 'Continue'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $aqui 'lib\vixradar-cvm-pdf.ps1')
$falhas = 0
function Confere($nome, $cond) {
    if ($cond) { Write-Output ('OK    ' + $nome) } else { Write-Output ('FALHA ' + $nome); $script:falhas++ }
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('vixcvmpdf-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# PDF minimo valido (fluxo sem compressao) com offsets de xref corretos.
function New-PdfMinimo([string]$Texto) {
    $objs = @(
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
        $null,
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    )
    $stream = 'BT /F1 12 Tf 72 700 Td (' + $Texto + ') Tj ET'
    $objs[3] = '<< /Length ' + $stream.Length + ' >>' + "`n" + 'stream' + "`n" + $stream + "`n" + 'endstream'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("%PDF-1.4`n")
    $offs = @()
    for ($i = 0; $i -lt $objs.Count; $i++) {
        $offs += $sb.Length
        [void]$sb.Append(($i + 1).ToString() + " 0 obj`n" + $objs[$i] + "`nendobj`n")
    }
    $xref = $sb.Length
    [void]$sb.Append("xref`n0 " + ($objs.Count + 1) + "`n0000000000 65535 f `n")
    foreach ($o in $offs) { [void]$sb.Append($o.ToString('0000000000') + " 00000 n `n") }
    [void]$sb.Append("trailer`n<< /Size " + ($objs.Count + 1) + " /Root 1 0 R >>`nstartxref`n" + $xref + "`n%%EOF`n")
    return [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())
}

$frase = 'Fato Relevante Companhia Exemplo comunica a emissao de debentures no valor de R$ 1,0 bilhao em outubro de 2026'
$pdfBom = Join-Path $tmp 'bom.pdf'
[System.IO.File]::WriteAllBytes($pdfBom, (New-PdfMinimo $frase))
$naoPdf = Join-Path $tmp 'ruim.pdf'
[System.IO.File]::WriteAllText($naoPdf, '<html>pagina de erro do portal</html>', [System.Text.Encoding]::ASCII)

$pdftotext = Get-VixPdftotextPath
Confere 'pdftotext encontrado' ([bool]$pdftotext)

# Ponta boa: PDF com texto devolve o texto.
$t = Get-VixPdfTextoDeArquivo -Arquivo $pdfBom -MaxChars 3000
Confere 'ponta boa: PDF com texto devolve conteudo legivel' ($t -and $t.Contains('Fato Relevante') -and $t.Contains('debentures'))
# Ponta ruim: arquivo que nao e PDF devolve $null (nunca lixo).
Confere 'ponta ruim: arquivo nao PDF devolve $null' ($null -eq (Get-VixPdfTextoDeArquivo -Arquivo $naoPdf))
Confere 'ponta ruim: arquivo inexistente devolve $null' ($null -eq (Get-VixPdfTextoDeArquivo -Arquivo (Join-Path $tmp 'nao-existe.pdf')))
$curto = Get-VixPdfTextoDeArquivo -Arquivo $pdfBom -MaxChars 30
Confere 'limite de caracteres respeitado' ($curto -and $curto.Length -le 30)

# Flag desligada por padrao: nenhuma rede, nenhum texto.
$antes = [Environment]::GetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', 'Process')
[Environment]::SetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', $null, 'Process')
$semUser = [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', 'User'))
$linkOk = 'https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?Tela=ext&descTipo=IPE&CodigoInstituicao=1&numProtocolo=1&numSequencia=1&numVersao=1'
if ($semUser) { Confere 'flag desligada: Get-VixCvmDocumentoTexto devolve $null sem rede' ($null -eq (Get-VixCvmDocumentoTexto -Link $linkOk -CacheDir $tmp)) }
[Environment]::SetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', '1', 'Process')
Confere 'flag ligada (Process=1) e reconhecida' (Test-VixCvmPdfTextoHabilitado)
[Environment]::SetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', '0', 'Process')
Confere 'flag 0 no Process desliga' (-not (Test-VixCvmPdfTextoHabilitado))

# Allowlist de host: link de outro dominio nunca baixa.
Confere 'link fora da allowlist e recusado' (-not (Test-VixCvmPdfLinkValido 'https://exemplo.com/a.pdf'))
Confere 'link http (sem TLS) e recusado' (-not (Test-VixCvmPdfLinkValido 'http://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?numProtocolo=1'))
Confere 'link do ENET e aceito' (Test-VixCvmPdfLinkValido $linkOk)
Confere 'forcado com flag: dominio estranho devolve $null sem rede' ($null -eq (Get-VixCvmDocumentoTexto -Link 'https://exemplo.com/a.pdf' -IgnorarFlag -CacheDir $tmp))
Confere 'chave de cache usa protocolo e sequencia' ((Get-VixCvmPdfChave $linkOk) -eq 'p1_s1')

if ($Rede) {
    if (-not $LinkRede) { $LinkRede = $linkOk }
    $r = Get-VixCvmDocumentoTexto -Link $LinkRede -IgnorarFlag -CacheDir $tmp
    Confere 'rede: documento real da CVM baixado e extraido' ($r -and $r.Length -gt 200)
}

[Environment]::SetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', $antes, 'Process')
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ('RESULTADO: falhas=' + $falhas)
exit $falhas
