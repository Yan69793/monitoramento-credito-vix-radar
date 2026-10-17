# COLETORVERIF1 (2026-10-17): guarda do contrato do bloco do coletor na verificacao-async.
# Offline, extrai a funcao REAL por AST. Nao chama CLI, Worker nem rede.
# Provider com busca propria (codex, claude) nao pode receber "PROIBIDO buscar" nem
# "REPROVADO obrigatorio" por coleta vazia: o prompt do Worker exige busca ativa e fonte
# primaria distinta com URL, que a coleta (manchete sem URL) nunca entrega.
# Provider sem busca (deepseek, coletor obrigatorio) mantem o contrato estrito.
param([string]$AlvoPath = (Join-Path $PSScriptRoot 'run_vixradar_verificacao_async.ps1'))
$ErrorActionPreference = 'Continue'
$script:Falhas = 0
function Assert-True([bool]$Cond, [string]$Nome) {
    if ($Cond) { Write-Host ('PASS ' + $Nome) }
    else { $script:Falhas++; Write-Host ('FAIL ' + $Nome) }
}
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($AlvoPath, [ref]$tokens, [ref]$errors)
Assert-True ($errors.Count -eq 0) 'parser PowerShell'
$def = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-VixBlocoColetorVerificacao' }, $true) | Select-Object -First 1
Assert-True ($null -ne $def) 'funcao Get-VixBlocoColetorVerificacao presente'
if (-not $def) { Write-Host ('FALHAS=' + $script:Falhas); exit 1 }
Invoke-Expression $def.Extent.Text

# Coleta simulada: um emissor com manchete, outro com coleta vazia.
function Get-VixColetorParaEmissor([string]$Empresa) { return $Empresa }
function Format-VixColetorEvidenciaTexto($Coleta) {
    if ($Coleta -eq 'Vazia SA') { return 'EVIDENCIA_COLETADA: fixture.' + "`n" + 'EVIDENCIA_VAZIA: nenhuma publicacao recente encontrada nas tres familias.' }
    return 'EVIDENCIA_COLETADA: fixture.' + "`n" + '[F1 emissor] 2026-10-16 | Veiculo (veiculo.com.br) | Manchete fixture'
}
$itens = @([pscustomobject]@{ id = 'fx-1'; empresa = 'Cheia SA' }, [pscustomobject]@{ id = 'fx-2'; empresa = 'Vazia SA' })
$proibe = 'PROIBIDO executar WebSearch'
$reprovaObrig = 'retorne obrigatoriamente REPROVADO'

# Coletor desligado: nada entra no prompt.
$script:VixColetorAtivo = $false; $script:VixColetorObrigatorio = $false
Assert-True ((Get-VixBlocoColetorVerificacao $itens) -eq '') 'coletor desligado nao gera bloco'

# Ponta 1 (o caso que reprovava tudo): provider com busca propria.
$script:VixColetorAtivo = $true; $script:VixColetorObrigatorio = $false
$b = Get-VixBlocoColetorVerificacao $itens
Assert-True (-not $b.Contains($proibe)) 'com busca propria: bloco NAO proibe busca'
Assert-True (-not $b.Contains($reprovaObrig)) 'com busca propria: coleta vazia NAO obriga REPROVADO'
Assert-True ($b -match 'busca ativa') 'com busca propria: bloco manda fazer a busca ativa do Worker'
Assert-True ($b -match 'fontes_validas so pode conter URL que voce abriu ou encontrou na busca') 'com busca propria: fontes_validas aceita URL achada na busca'
Assert-True ($b.Contains('EVENTO_COLETOR|id=fx-1|empresa=Cheia SA') -and $b.Contains('Manchete fixture')) 'com busca propria: evidencia continua no prompt'
Assert-True ($b -match 'FONTES: nao invente URL') 'com busca propria: proibicao de inventar fonte mantida'

# Ponta 2 (o caso que deve continuar estrito): provider sem busca (deepseek).
$script:VixColetorObrigatorio = $true
$s = Get-VixBlocoColetorVerificacao $itens
Assert-True ($s.Contains($proibe)) 'sem busca propria: bloco proibe busca'
Assert-True ($s.Contains($reprovaObrig)) 'sem busca propria: coleta vazia obriga REPROVADO'
Assert-True ($s.Contains('EVENTO_COLETOR|id=fx-2|empresa=Vazia SA') -and $s.Contains('EVIDENCIA_VAZIA')) 'sem busca propria: evidencia e marcador de vazio no prompt'

Write-Host ('FALHAS=' + $script:Falhas)
if ($script:Falhas -gt 0) { exit 1 }
exit 0
