# EVOLUCAO2B: prova de duas pontas do envio de propostas da rotina EWS2-Pacote, sem rede e sem rodar a rotina.
# Extrai as funcoes do run_vixradar_ews2_pacote.ps1 pelo AST, troca Invoke-WebRequest por um duble que so registra,
# e confere: simulacao nunca envia; envio so com VIXRADAR_EVOLUCAO_ENVIAR=1 E -Publicar; a chave nunca vai para o log.
$ErrorActionPreference = 'Continue'
$raiz = Split-Path -Parent $PSScriptRoot
$alvo = Join-Path $raiz 'scripts\run_vixradar_ews2_pacote.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($alvo, [ref]$null, [ref]$null)
$nomes = 'Write-Log', 'Invoke-ProcessoComTeto', 'Get-JsonDoTexto', 'Get-Cabeca', 'Invoke-PropostasEvolucao'
foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($nomes -contains $f.Name) { . ([scriptblock]::Create($f.Extent.Text)) }
}
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('evol2b_' + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$TmpDir = $tmp; $LogFile = Join-Path $tmp 'log.txt'; $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ProjectRoot = $raiz; $Ews2Dir = Join-Path $raiz 'scripts\predictive\ews2'
$python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
$script:Res = [ordered]@{}
$script:Envios = New-Object System.Collections.ArrayList
function Invoke-WebRequest { param($Uri, $Method, [switch]$UseBasicParsing, $TimeoutSec, $ContentType, $Body, $ErrorAction)
    [void]$script:Envios.Add([System.Text.Encoding]::UTF8.GetString($Body))
    $ms = New-Object System.IO.MemoryStream(, [System.Text.Encoding]::UTF8.GetBytes('{"ok":true,"criada":true,"estado":"proposta"}'))
    return [pscustomobject]@{ RawContentStream = $ms } }

$rel = Join-Path $tmp 'rel.json'
$evento = '{"cnpj":"11.111.111/0001-11","inicio":"2026-11-10","pacote":"2026-11-02","sev_ews2":"baixa","pct_ews2":0.3,"pct_atual":0.9,"links":["https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?numProtocolo=1"]}'
[System.IO.File]::WriteAllText($rel, '{"decisao":"amostra_insuficiente","eventos":[' + $evento + ']}', $Utf8NoBom)
$falhas = 0
function Assert-Caso([string]$Nome, [bool]$Ok) { if ($Ok) { Write-Host ('OK   ' + $Nome) } else { Write-Host ('FALHA ' + $Nome); $script:falhas++ } }

$antes = $env:VIXRADAR_EVOLUCAO_ENVIAR; $chaveAntes = $env:ROUTINE_API_KEY
$userEnviar = [Environment]::GetEnvironmentVariable('VIXRADAR_EVOLUCAO_ENVIAR', 'User')
Assert-Caso 'pre-condicao: VIXRADAR_EVOLUCAO_ENVIAR User vazio' (-not $userEnviar)
$env:ROUTINE_API_KEY = 'chave-de-teste-nao-real'

$env:VIXRADAR_EVOLUCAO_ENVIAR = $null
Invoke-PropostasEvolucao $rel $true
Assert-Caso 'sem a variavel: deriva 1 e nao envia' (($script:Res.evolucao.derivadas -eq 1) -and ($script:Envios.Count -eq 0))

$env:VIXRADAR_EVOLUCAO_ENVIAR = '1'
Invoke-PropostasEvolucao $rel $false
Assert-Caso 'variavel ligada sem -Publicar: nao envia' ($script:Envios.Count -eq 0)

Invoke-PropostasEvolucao $rel $true
Assert-Caso 'variavel ligada e -Publicar: envia 1' (($script:Envios.Count -eq 1) -and ($script:Res.evolucao.enviadas -eq 1))
$corpo = $script:Envios[0] | ConvertFrom-Json
Assert-Caso 'corpo: action, origem rotina e fonte oficial' (($corpo.action -eq 'evolucao_propor') -and ($corpo.origem -eq 'rotina') -and (@($corpo.proposta.fontes)[0] -like 'https://www.rad.cvm.gov.br/*'))
$log = [System.IO.File]::ReadAllText($LogFile)
Assert-Caso 'chave nunca aparece no log' (-not $log.Contains('chave-de-teste-nao-real'))

[System.IO.File]::WriteAllText($rel, '{"decisao":"amostra_insuficiente","eventos":[]}', $Utf8NoBom)
$script:Envios.Clear()
Invoke-PropostasEvolucao $rel $true
Assert-Caso 'relatorio sem evento: 0 derivadas, nada enviado' (($script:Res.evolucao.derivadas -eq 0) -and ($script:Envios.Count -eq 0))

Invoke-PropostasEvolucao (Join-Path $tmp 'nao-existe.json') $true
Assert-Caso 'relatorio ausente: nao lanca' $true

$env:VIXRADAR_EVOLUCAO_ENVIAR = $antes; $env:ROUTINE_API_KEY = $chaveAntes
Remove-Item -LiteralPath $tmp -Recurse -Force
Write-Host ('RESULTADO: ' + $(if ($falhas -eq 0) { 'OK' } else { "$falhas falha(s)" }))
exit $falhas
