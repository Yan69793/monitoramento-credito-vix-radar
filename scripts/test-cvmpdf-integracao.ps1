# test-cvmpdf-integracao.ps1 - CVMPDF1: integracao do texto extraido ao payload do emissor (Get-SlimEmissor).
# Extrai a funcao real do motor por AST, sem executa-lo, e chama com dependencias simuladas.
# Prova de duas pontas: flag desligada => payload identico ao de antes; flag ligada => texto_extraido;
# falha de download => fail-open (payload sem o campo, sem excecao). Nao baixa nada, nao roda rotina.
# Saida por exit code (0 = tudo passou).
$ErrorActionPreference = 'Continue'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $aqui 'lib\vixradar-cvm-pdf.ps1')
$falhas = 0
function Confere($nome, $cond) {
    if ($cond) { Write-Output ('OK    ' + $nome) } else { Write-Output ('FALHA ' + $nome); $script:falhas++ }
}
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $aqui 'run_vixradar_varredura.ps1'), [ref]$null, [ref]$null)
$fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-SlimEmissor' }, $true) | Select-Object -First 1
Confere 'Get-SlimEmissor localizada no motor' ($null -ne $fn)
Invoke-Expression $fn.Extent.Text

# Dependencias simuladas (so o que a funcao toca).
$Perfil = [pscustomobject]@{ tier = 'FULL' }
$EwsContextoCritico = 60
$script:VixTriagemDados = $null
function Get-VixColetorParaEmissor($e) { return $null }
function Format-VixLeadsTriagem($x) { return $null }
function ConvertTo-VixChaveEmissor($e) { return ('' + $e).ToLowerInvariant() }

$linkOk = 'https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?Tela=ext&descTipo=IPE&CodigoInstituicao=1&numProtocolo=777&numSequencia=1&numVersao=1'
$emp = [pscustomobject]@{
    empresa = 'Emissor Teste'; setor = 'X'; ews_score = 10; cvm_novos = 1; contexto_historico = ''
    ultimo_evento_data = ''; eventos_conhecidos = @(); janela_delta_inicio = ''
    cvm_documentos = @([pscustomobject]@{ categoria = 'Fato Relevante'; assunto = '12a Emissao de Debentures'; data = '2026-10-16'; link = $linkOk; empresa_cvm = $null })
}
$antes = [Environment]::GetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', 'Process')

# Ponta A: flag desligada => nenhum campo novo, funcao de download nem e chamada.
[Environment]::SetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', '0', 'Process')
$script:chamadas = 0
function Get-VixCvmPdfBaixarEExtrair($l) { $script:chamadas++ }
$a = Get-SlimEmissor $emp 'FULL'
Confere 'flag desligada: documento sem texto_extraido' ($null -eq $a.cvm_documentos[0].PSObject.Properties['texto_extraido'])
Confere 'flag desligada: demais campos do documento intactos' ($a.cvm_documentos[0].assunto -eq '12a Emissao de Debentures' -and $a.cvm_documentos[0].link -eq $linkOk)

# Ponta B: flag ligada com cache em memoria preenchido (simula download ja feito) => campo presente.
[Environment]::SetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', '1', 'Process')
$script:VixCvmPdfCacheMem = @{ 'p777_s1' = 'FATO RELEVANTE A companhia comunica a 12a emissao de debentures no valor de R$ 1 bilhao.' }
$b = Get-SlimEmissor $emp 'FULL'
Confere 'flag ligada: texto_extraido presente e legivel' ($b.cvm_documentos[0].texto_extraido -like '*12a emissao de debentures*')
Confere 'flag ligada: limite de 3000 caracteres respeitado' (('' + $b.cvm_documentos[0].texto_extraido).Length -le 3000)

# Fail-open: cache aponta falha ($null) => sem campo, sem excecao.
$script:VixCvmPdfCacheMem = @{ 'p777_s1' = $null }
$c = $null; $erro = $null
try { $c = Get-SlimEmissor $emp 'FULL' } catch { $erro = $_.Exception.Message }
Confere 'falha de download: sem excecao' ($null -eq $erro)
Confere 'falha de download: payload sem texto_extraido, resto intacto' ($null -eq $c.cvm_documentos[0].PSObject.Properties['texto_extraido'] -and $c.empresa -eq 'Emissor Teste')

# Allowlist: link de outro dominio nunca vira texto, mesmo com flag ligada.
$emp2 = $emp.PSObject.Copy(); $emp2.cvm_documentos = @([pscustomobject]@{ categoria = 'Comunicado'; assunto = 'x'; data = '2026-10-16'; link = 'https://exemplo.com/a.pdf'; empresa_cvm = $null })
$script:VixCvmPdfCacheMem = @{}
$d = Get-SlimEmissor $emp2 'FULL'
Confere 'link fora da allowlist: sem texto_extraido' ($null -eq $d.cvm_documentos[0].PSObject.Properties['texto_extraido'])

# Estatico: o gancho esta no motor e a lib e opcional.
$f = Get-Content -LiteralPath (Join-Path $aqui 'run_vixradar_varredura.ps1') -Raw -Encoding UTF8
Confere 'motor carrega a lib CVMPDF1 de forma opcional' ($f.Contains("if (Test-Path -LiteralPath (Join-Path `$PSScriptRoot 'lib\vixradar-cvm-pdf.ps1'))"))

[Environment]::SetEnvironmentVariable('VIXRADAR_CVM_PDF_TEXTO', $antes, 'Process')
Write-Output ('RESULTADO: falhas=' + $falhas)
exit $falhas
