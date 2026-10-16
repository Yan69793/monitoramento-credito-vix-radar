# test-recheckdiverg1-15out.ps1 - RECHECKDIVERG1: veredito por manchete e timestamp do lote Codex.
# PowerShell 5.1, ASCII puro. Duas pontas sobre dados reais de 14/10 e 15/10:
#   ponta ruim  - resultado sem veredito continua divergente (DIVERGENCIACOMPROVA1 preservada),
#                 inclusive os 7 casos de 14/10 que motivaram a protecao;
#   ponta boa   - resultado com veredito para cada manchete nova certifica ausencia com as
#                 fontes do coletor; a lib ANTIGA (-LibAntiga) reprova o mesmo caso, provando
#                 que a regra antiga bloqueava de forma indevida.
param([string]$LibAntiga = '')
$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Rd([bool]$c, [string]$nome, [string]$det = '') {
    if ($c) { $script:Ok++; Write-Host ('  OK    ' + $nome + ' ' + $det) } else { $script:Falhas++; Write-Host ('  FALHA ' + $nome + ' ' + $det) }
}
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root 'logs\routines'
$libCob = Join-Path $PSScriptRoot 'lib\vixradar-cobertura.ps1'
$libCol = Join-Path $PSScriptRoot 'lib\vixradar-coletor.ps1'
if ($LibAntiga) { $libCob = Join-Path $LibAntiga 'vixradar-cobertura.ps1'; $libCol = Join-Path $LibAntiga 'vixradar-coletor.ps1' }
. $libCob
. $libCol
$antiga = [bool]$LibAntiga
# A lib antiga nao tem o id de manchete; o teste usa a mesma formula para montar os vereditos.
if (-not (Get-Command 'Get-VixMancheteId' -ErrorAction SilentlyContinue)) {
    function Get-VixMancheteId($e) {
        $base = (('' + $e.data).Trim() + '|' + ('' + $e.dominio).Trim().ToLowerInvariant() + '|' + ('' + $e.titulo).Trim().ToLowerInvariant())
        $sha = [System.Security.Cryptography.SHA1]::Create()
        try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($base)) } finally { $sha.Dispose() }
        return ('m' + (($h[0..4] | ForEach-Object { $_.ToString('x2') }) -join ''))
    }
}
# Portao de ausencia do motor real (AST), sem executar o motor.
$motor = Join-Path $PSScriptRoot 'run_vixradar_varredura.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($motor, [ref]$null, [ref]$null)
$quero = @('Test-VixBuscaDegradada', 'Resolve-VixCoberturaWeb', 'Get-VixCoberturaProviderCapability', 'ConvertTo-VixFonteEstrutural', 'Resolve-VixCoberturaFamilias', 'Test-VixAusenciaCertificavel', 'Get-NomeNormalizado')
foreach ($fa in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
    if ($quero -contains $fa.Name) { . ([scriptblock]::Create($fa.Extent.Text)) }
}
foreach ($fn in $quero) { if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { Write-Host ('ERRO: funcao do motor ausente: ' + $fn); exit 2 } }

function Get-RdResultado([string]$Log, [string]$Prefixo, [string]$Emp) {
    if (-not (Test-Path -LiteralPath $Log)) { return $null }
    foreach ($l in (Get-Content -LiteralPath $Log -Encoding UTF8)) {
        if ($l.StartsWith($Prefixo) -and $l.Contains(' OUT: RESULTADO|') -and $l.Contains($Emp + '|{')) { return ($l.Substring($l.IndexOf('|{') + 1) | ConvertFrom-Json) }
    }
    return $null
}
# Corte do delta: o da linha TRIAGEM quando ela traz data; emissor marcado por revalidacao nao traz,
# e ai vale um corte fixo de 3 dias antes da execucao (premissa do teste, o plano real nao foi logado).
# O cache de coleta do dia e regravado por rotina, entao a contagem nao reproduz a do log: o teste
# prova a REGRA sobre evidencia real, nao o numero exato daquela execucao.
function Get-RdDelta([string]$Log, [string]$Prefixo, [string]$Emp, [string]$Padrao = '') {
    foreach ($l in (Get-Content -LiteralPath $Log -Encoding UTF8)) {
        if ($l.StartsWith($Prefixo) -and $l.Contains(' TRIAGEM|' + $Emp + '|') -and $l -match '_desde_(\d{4}-\d{2}-\d{2})') { return $Matches[1] }
    }
    return $Padrao
}
function Get-RdColeta([string]$Cache, [string]$Emp) { return (Get-VixColetaCacheada -Path $Cache -Empresa $Emp -TtlMin 10000000 -Agora ([datetime]'2026-10-16')) }
function Copy-RdRes($r) { return ($r | ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json) }
function Add-RdVereditos($r, $ids, [string]$ve = 'sem_efeito_credito') {
    $v = @(); foreach ($id in $ids) { $v += [pscustomobject]@{ id = $id; veredito = $ve; motivo = 'manchete lida, cita o emissor sem efeito de credito' } }
    $r | Add-Member -NotePropertyName 'vereditos_manchetes' -NotePropertyValue $v -Force
    return $r
}

Write-Host '== A: casos de 14/10 (DIVERGENCIACOMPROVA1) continuam divergentes sem veredito =='
$log14 = Join-Path $LogDir 'vixradar-noturno_20261014.log'
$cache14 = Join-Path $LogDir 'coleta_cache_20261014.json'
$casos14 = @(@{ e = 'VLI'; n = 3 }, @{ e = 'Vale'; n = 6 }, @{ e = 'Rumo'; n = 4 }, @{ e = 'Usiminas'; n = 5 }, @{ e = 'Eletrobras'; n = 1 }, @{ e = 'Gerdau'; n = 5 }, @{ e = 'PRIO'; n = 1 })
if ((Test-Path -LiteralPath $log14) -and (Test-Path -LiteralPath $cache14)) {
    foreach ($c in $casos14) {
        $res = Get-RdResultado $log14 '2026-10-14 02:4' $c.e
        $col = Get-RdColeta $cache14 $c.e
        $delta = Get-RdDelta $log14 '2026-10-14 02:' $c.e '2026-10-11'
        if ($null -eq $res -or $null -eq $col -or -not $delta) { Assert-Rd $false ('A ' + $c.e + ' dados reais disponiveis') ('res=' + [bool]$res + ' col=' + [bool]$col + ' delta=' + $delta); continue }
        $nov = @((Get-VixTriagemEmissor -Coleta $col -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 0 -Ews 0).Novas)
        $mg = Add-VixFontesColetorAoResultado -Res (Copy-RdRes $res) -Coleta $col -DeltaInicio $delta -Novas $nov
        Assert-Rd ($mg.Divergencia -eq $true) ('A ' + $c.e + ' sem veredito segue divergente') ('novas=' + $nov.Count + ' (log 14/10 registrou ' + $c.n + ', cache regravado depois) motivo=' + $mg.Motivo)
    }
} else { Write-Host '  PULADO A: log ou cache de 14/10 ausente' }

Write-Host '== B: casos de 15/10 com veredito por manchete =='
$log15 = Join-Path $LogDir 'vixradar-noturno_20261015.log'
$cache15 = Join-Path $LogDir 'coleta_cache_20261015.json'
foreach ($e in @('Klabin', 'Ultrapar', 'TIM Brasil')) {
    $res = Get-RdResultado $log15 '2026-10-15 22:3' $e
    $col = Get-RdColeta $cache15 $e
    $delta = Get-RdDelta $log15 '2026-10-15 22:2' $e '2026-10-12'
    if ($null -eq $res -or $null -eq $col -or -not $delta) { Assert-Rd $false ('B ' + $e + ' dados reais disponiveis') ('res=' + [bool]$res + ' col=' + [bool]$col + ' delta=' + $delta); continue }
    $nov = @((Get-VixTriagemEmissor -Coleta $col -DeltaInicio $delta -CvmNovos 0 -HorasDesdeIA 0 -Ews 0).Novas)
    $ids = @($nov | ForEach-Object { Get-VixMancheteId $_ } | Select-Object -Unique)
    # B1 ponta ruim: o resultado real, sem veredito.
    $r0 = Copy-RdRes $res
    $mg0 = Add-VixFontesColetorAoResultado -Res $r0 -Coleta $col -DeltaInicio $delta -Novas $nov
    Assert-Rd ($mg0.Divergencia -eq $true) ('B1 ' + $e + ' resultado real sem veredito segue divergente') ('novas=' + $nov.Count)
    # B2 ponta boa: veredito para cada id.
    $r1 = Add-RdVereditos (Copy-RdRes $res) $ids
    $mg1 = Add-VixFontesColetorAoResultado -Res $r1 -Coleta $col -DeltaInicio $delta -Novas $nov
    $cert = Test-VixAusenciaCertificavel $r1
    if ($antiga) {
        Assert-Rd ($mg1.Divergencia -eq $false) ('B2 ' + $e + ' com veredito completo NAO diverge') ('motivo=' + $mg1.Motivo)
    } else {
        Assert-Rd ($mg1.Divergencia -eq $false -and $mg1.Adicionadas -ge 3) ('B2 ' + $e + ' com veredito completo nao diverge e soma fontes do coletor') ('adicionadas=' + $mg1.Adicionadas + ' vereditos=' + $mg1.Vereditos)
        Assert-Rd ($cert.permitir_sem_eventos -eq $true) ('B3 ' + $e + ' ausencia certificavel com veredito') ('motivo=' + $cert.motivo + ' faltantes=' + ($cert.faltantes -join ','))
    }
    if ($antiga) { continue }
    # B4 veredito faltando um id.
    if ($ids.Count -ge 2) {
        $r2 = Add-RdVereditos (Copy-RdRes $res) @($ids | Select-Object -Skip 1)
        $mg2 = Add-VixFontesColetorAoResultado -Res $r2 -Coleta $col -DeltaInicio $delta -Novas $nov
        Assert-Rd ($mg2.Divergencia -eq $true) ('B4 ' + $e + ' faltando 1 veredito diverge') ('motivo=' + $mg2.Motivo)
    }
    # B5 veredito 'evento' sem evento no resultado.
    $r3 = Add-RdVereditos (Copy-RdRes $res) $ids 'evento'
    $mg3 = Add-VixFontesColetorAoResultado -Res $r3 -Coleta $col -DeltaInicio $delta -Novas $nov
    Assert-Rd ($mg3.Divergencia -eq $true) ('B5 ' + $e + ' veredito evento sem evento diverge') ('motivo=' + $mg3.Motivo)
    # B6 veredito com valor fora do contrato.
    $r4 = Add-RdVereditos (Copy-RdRes $res) $ids 'irrelevante'
    $mg4 = Add-VixFontesColetorAoResultado -Res $r4 -Coleta $col -DeltaInicio $delta -Novas $nov
    Assert-Rd ($mg4.Divergencia -eq $true) ('B6 ' + $e + ' veredito fora do contrato diverge') ('motivo=' + $mg4.Motivo)
    # B7 prompt e conferencia usam o mesmo conjunto de ids, e o texto do prompt carrega cada id.
    $idsPrompt = @(Get-VixManchetesExigemVeredito -Coleta $col -DeltaInicio $delta)
    $txt = Format-VixColetorEvidenciaTexto $col
    $semIdNoTexto = @($ids | Where-Object { -not $txt.Contains('id=' + $_) })
    Assert-Rd ((@(Compare-Object $idsPrompt $ids).Count -eq 0) -and $semIdNoTexto.Count -eq 0) ('B7 ' + $e + ' ids do prompt = ids da conferencia') ('prompt=' + $idsPrompt.Count + ' conferencia=' + $ids.Count + ' ausentes_no_texto=' + $semIdNoTexto.Count)
}

if (-not $antiga) {
    Write-Host '== C: timestamp do lote nas fontes Codex (GPA FULL 15/10 22:19, CBA FULL 18:17) =='
    $logM = Join-Path $LogDir 'vixradar-matinal_20261015.log'
    $gpa = Get-RdResultado $logM '2026-10-15 22:19' '(GPA)'
    if ($null -ne $gpa) {
        $famAntes = Resolve-VixCoberturaFamilias $gpa
        Assert-Rd ($famAntes.ok -eq $false) 'C1 GPA FULL real sem timestamp reprova familias (ponta ruim)' ('faltantes=' + ($famAntes.faltantes -join ','))
        $n = Set-VixTimestampLoteCodex -Res $gpa -Ts '2026-10-16T01:19:14Z'
        $famDep = Resolve-VixCoberturaFamilias $gpa
        Assert-Rd ($n -ge 3 -and $famDep.ok -eq $true) 'C2 GPA com horario do lote cobre as tres familias' ('carimbadas=' + $n)
        Assert-Rd (@(@($gpa.fontes_consultadas) | Where-Object { ('' + $_._timestamp_origem) -eq 'orquestrador_lote' }).Count -eq $n) 'C3 origem do carimbo declarada em cada fonte' ''
    } else { Assert-Rd $false 'C GPA FULL de 22:19 localizado' '' }
    $cba = Get-RdResultado $log15 '2026-10-15 18:17' 'CBA'
    if ($null -ne $cba) {
        $degr = @(@($cba.fontes_consultadas) | Where-Object { ('' + $_.classificacao) -eq 'degradada' })
        $null = Set-VixTimestampLoteCodex -Res $cba -Ts '2026-10-15T21:17:28Z'
        $degrCarimb = @($degr | Where-Object { ('' + $_.timestamp) -ne '' })
        Assert-Rd ($degr.Count -ge 1 -and $degrCarimb.Count -eq 0) 'C4 fonte degradada nunca e carimbada' ('degradadas=' + $degr.Count)
        $certCba = Test-VixAusenciaCertificavel $cba
        Assert-Rd ($certCba.permitir_sem_eventos -eq $false) 'C5 CBA com fetch degradado segue sem certificacao' ('motivo=' + $certCba.motivo)
    } else { Assert-Rd $false 'C CBA FULL de 18:17 localizado' '' }
    # C6 fonte sem provedor codex (rodada barata) nao ganha timestamp.
    $sem = [pscustomobject]@{ fontes_consultadas = @([pscustomobject]@{ familia = 'emissor'; resultado = 'Manchete' }) }
    Assert-Rd ((Set-VixTimestampLoteCodex -Res $sem -Ts '2026-10-16T00:00:00Z') -eq 0) 'C6 fonte sem provedor/query/HTTP nao e carimbada' ''
}

Write-Host ('RESULTADO: ' + $script:Ok + ' OK, ' + $script:Falhas + ' falha(s)')
if ($script:Falhas -gt 0) { exit 1 }
exit 0
