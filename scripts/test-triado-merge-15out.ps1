# test-triado-merge-15out.ps1 - TRIADOMERGE1 (2026-10-15). Prova offline e sem token de que o
# `triado` pegajoso do contrato de cobertura sobrevive ao Merge-VixContratoCobertura
# (RECHECK_PENDENTE / RESOLVIDO), e que isso fecha a reconciliacao da noturna de 15/10 18:05.
#   A unitario: TRIADO -> Merge -> Set mantem triado; entrada sem triado continua sem triado
#   B entrada lida do JSON (PSCustomObject) tambem preserva
#   C replay do log REAL de 15/10 18:05, duas pontas: Merge antigo (backup) reproduz o
#     `triados:92<101` medido; Merge novo fecha 101/101 sem divergencia
# ASCII puro, PowerShell 5.1. Saida: exit 0 = tudo verde, 1 = alguma falha.

param([string]$LogDir = '', [string]$MotorAntigo = '')
$ErrorActionPreference = 'Continue'
$script:Ok = 0; $script:Falhas = 0
function Assert-Tm([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:Ok++; Write-Host ('  OK    ' + $Nome) } else { $script:Falhas++; Write-Host ('  FALHA ' + $Nome) }
}
$Scripts = $PSScriptRoot
$MotorPath = Join-Path $Scripts 'run_vixradar_varredura.ps1'
if (-not $LogDir) { $LogDir = Join-Path (Split-Path $Scripts -Parent) 'logs\routines' }
. (Join-Path $Scripts 'lib\vixradar-cobertura.ps1')
function Get-MotorFuncDefs([string]$Path, [string[]]$Names) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw ('parse de ' + $Path + ' falhou: ' + $errors[0].Message) }
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $out = @()
    foreach ($name in $Names) {
        $f = $defs | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $f) { throw ('funcao ' + $name + ' nao encontrada em ' + $Path) }
        $out += $f.Extent.Text
    }
    return ,$out
}
function Import-Motor([string]$Path) {
    foreach ($_def in (Get-MotorFuncDefs $Path @('Get-NomeNormalizado', 'Merge-VixContratoCobertura', 'Set-VixContratoEstado'))) { Invoke-Expression ('function global:' + ($_def -replace '^function\s+', '')) }
}
$DryRun = $false
$Perfil = @{ modo = 'noturno' }
$script:VixContratoExec = @{}

function Get-Triado($e) {
    if ($null -eq $e) { return $null }
    if ($e -is [System.Collections.IDictionary]) { if ($e.Contains('triado')) { return [bool]$e['triado'] } else { return $null } }
    if ($null -ne $e.PSObject.Properties['triado']) { return [bool]$e.triado }
    return $null
}

Import-Motor $MotorPath

Write-Host '=== A: unitario no Merge novo ==='
$global:contratoCobertura = @{}
$contratoCobertura = $global:contratoCobertura
Set-VixContratoEstado -Empresa 'Eneva' -Estado 'TRIADO' -Motivo 'MATERIAL:x' -Triado $true
Merge-VixContratoCobertura $contratoCobertura 'Eneva' 'RECHECK_PENDENTE' @('emissor', 'divida')
$k = Get-NomeNormalizado 'Eneva'
Assert-Tm ((Get-Triado $contratoCobertura[$k]) -eq $true) 'A1 Merge RECHECK_PENDENTE preserva triado=true'
Assert-Tm (@($contratoCobertura[$k].faltantes).Count -eq 2 -and $contratoCobertura[$k].status -eq 'RECHECK_PENDENTE') 'A2 Merge continua gravando status e faltantes'
Set-VixContratoEstado -Empresa 'Eneva' -Estado 'INCONCLUSIVO' -Motivo 'nao_conclusiva:x' -Faltantes @('emissor') -Triado $false
Assert-Tm ((Get-Triado $contratoCobertura[$k]) -eq $true) 'A3 Set INCONCLUSIVO depois do Merge segue triado=true'
Set-VixContratoEstado -Empresa 'Banco Pan' -Estado 'TRIADO' -Motivo 'MATERIAL:x' -Triado $true
Merge-VixContratoCobertura $contratoCobertura 'Banco Pan' 'RESOLVIDO' @()
Set-VixContratoEstado -Empresa 'Banco Pan' -Estado 'RESOLVIDO' -Motivo 'resolvido:x' -Faltantes @() -Triado $false
Assert-Tm ((Get-Triado $contratoCobertura[(Get-NomeNormalizado 'Banco Pan')]) -eq $true) 'A4 caminho RESOLVIDO segue triado=true'
Merge-VixContratoCobertura $contratoCobertura 'Vibra Energia' 'RECHECK_PENDENTE' @('web')
Assert-Tm ($null -eq (Get-Triado $contratoCobertura[(Get-NomeNormalizado 'Vibra Energia')])) 'A5 emissor nunca triado nao ganha triado (Merge nao inventa prova)'
Set-VixContratoEstado -Empresa 'Light' -Estado 'DEFERIDO' -Motivo 'x' -Triado $false
Merge-VixContratoCobertura $contratoCobertura 'Light' 'RECHECK_PENDENTE' @('web')
Assert-Tm ((Get-Triado $contratoCobertura[(Get-NomeNormalizado 'Light')]) -eq $false) 'A6 triado=false explicito continua false'

Write-Host '=== B: entrada vinda do JSON (PSCustomObject) ==='
$pso = ('{"empresa":"Cogna Educacao","estado":"TRIADO","triado":true,"faltantes":[]}' | ConvertFrom-Json)
$contratoCobertura[(Get-NomeNormalizado 'Cogna Educacao')] = $pso
Merge-VixContratoCobertura $contratoCobertura 'Cogna Educacao' 'RECHECK_PENDENTE' @('fato')
Assert-Tm ((Get-Triado $contratoCobertura[(Get-NomeNormalizado 'Cogna Educacao')]) -eq $true) 'B1 PSCustomObject com triado=true preservado'

Write-Host '=== C: replay do log real da noturna 15/10 18:05 ==='
$logP = Join-Path $LogDir 'vixradar-noturno_20261015.log'
if (-not (Test-Path -LiteralPath $logP)) {
    Write-Host ('  PULADO C: log real ausente em ' + $logP)
} else {
    $linhas = @(Get-Content -LiteralPath $logP -Encoding UTF8)
    $fb = @(Get-ChildItem -LiteralPath $LogDir -Filter 'vixradar-noturno_20261015_fallback_*.log' -File -ErrorAction SilentlyContinue)
    $antes = @(); foreach ($f in $fb) { $antes += @(Get-Content -LiteralPath $f.FullName -Encoding UTF8) }
    $iIni = -1
    for ($i = 0; $i -lt $linhas.Count; $i++) { if ($linhas[$i] -match '^2026-10-15 18:05:\d\d INICIO: noturno') { $iIni = $i; break } }
    Assert-Tm ($iIni -ge 0) 'C0 execucao das 18:05 localizada no log'
    # Recorte ate o fim da execucao das 18:05: o log do dia ganhou a noturna de recuperacao das 22:22.
    $exec = @($linhas[$iIni..($linhas.Count - 1)] | Where-Object { $_.Length -lt 19 -or $_.Substring(0, 19) -lt '2026-10-15 18:21:00' })
    $antes += @($linhas[0..([Math]::Max(0, $iIni - 1))])
    # Universo = emissores com linha de ledger no dia; entregues antes = ANALISADO/SKIP com submit true antes das 18:05.
    $rxOk = '^\S+ \S+ OK\|([^|]+)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|'
    $universo = @{}; $entreguesAntes = @{}
    foreach ($l in ($antes + $exec)) { $m = [regex]::Match($l, $rxOk); if ($m.Success) { $universo[(Get-NomeNormalizado $m.Groups[1].Value)] = $true } }
    foreach ($l in $antes) { $m = [regex]::Match($l, $rxOk); if ($m.Success -and $m.Groups[5].Value -eq 'true' -and @('ANALISADO', 'SKIP') -contains $m.Groups[6].Value) { $entreguesAntes[(Get-NomeNormalizado $m.Groups[1].Value)] = $true } }
    $eleg = @($universo.Keys | Where-Object { -not $entreguesAntes.ContainsKey($_) })
    Assert-Tm ($universo.Count -eq 104 -and $eleg.Count -eq 101) ('C1 universo=104 e elegiveis=101 (medido ' + $universo.Count + '/' + $eleg.Count + ')')

    $rodar = {
        param([string]$Motor)
        Import-Motor $Motor
        $global:contratoCobertura = @{}
        $contratoCobertura = $global:contratoCobertura
        $script:VixContratoExec = @{}
        $recheck = @{}; $final = New-Object System.Collections.Generic.List[object]
        foreach ($l in $exec) {
            if ($l -match '^\S+ \S+ TRIAGEM\|([^|]+)\|([^|]+)\|') { Set-VixContratoEstado -Empresa $Matches[1] -Estado 'TRIADO' -Motivo $Matches[2] -Triado $true; continue }
            $m = [regex]::Match($l, $rxOk)
            if ($m.Success -and $m.Groups[6].Value -eq 'SKIP') { Set-VixContratoEstado -Empresa $m.Groups[1].Value -Estado 'REUTILIZADO' -Motivo 'skip' -Triado $true; continue }
            if ($m.Success) { $final.Add(@($m.Groups[1].Value, $m.Groups[6].Value)); continue }
            if ($l -match '^\S+ \S+ RECHECK_PENDENTE\|([^|]+)\|') { Merge-VixContratoCobertura $contratoCobertura $Matches[1] 'RECHECK_PENDENTE' @('fato'); $recheck[$Matches[1]] = 'P'; continue }
            if ($l -match '^\S+ \S+ RECHECK_RESOLVIDO\|([^|]+)\|') { Merge-VixContratoCobertura $contratoCobertura $Matches[1] 'RESOLVIDO' @(); $recheck[$Matches[1]] = 'R'; continue }
        }
        foreach ($p in $final) {
            $est = 'DEFERIDO'
            if ($p[1] -eq 'ANALISADO') { $est = 'ANALISADO'; if ($recheck[$p[0]] -eq 'P') { $est = 'INCONCLUSIVO' } elseif ($recheck[$p[0]] -eq 'R') { $est = 'RESOLVIDO' } }
            Set-VixContratoEstado -Empresa $p[0] -Estado $est -Motivo 'replay' -Triado $false
        }
        $tri = @{}
        foreach ($kk in @($contratoCobertura.Keys)) { $tri[$kk] = [bool](Get-Triado $contratoCobertura[$kk]) }
        return (Test-VixReconciliacaoExecucao -LedgerExec @{} -ContratoExec @{} -TriadoPorChave $tri -Elegiveis $eleg -ExigirTriagem $true)
    }
    if (-not $MotorAntigo) {
        $bk = @(Get-ChildItem -LiteralPath 'E:\Diretorio\Claude\BACKUPS\operacional\vix-radar' -Directory -Filter 'triadomerge1-*' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1)
        if ($bk.Count -gt 0) { $MotorAntigo = Join-Path $bk[0].FullName 'run_vixradar_varredura.ps1' }
    }
    if ($MotorAntigo -and (Test-Path -LiteralPath $MotorAntigo)) {
        $rOld = & $rodar $MotorAntigo
        Write-Host ('  antigo: ' + (@($rOld.divergencias) -join ' | '))
        Assert-Tm ((-not $rOld.ok) -and ((@($rOld.divergencias) -join ' ') -match 'triados:92<101')) 'C2 Merge ANTIGO reproduz a divergencia medida triados:92<101 (ponta ruim)'
    } else { Write-Host '  PULADO C2: motor antigo (backup triadomerge1) ausente' }
    $rNew = & $rodar $MotorPath
    Write-Host ('  novo: ok=' + $rNew.ok + ' triados=' + $rNew.triados + '/' + $rNew.elegiveis + ' ' + (@($rNew.divergencias) -join ' | '))
    Assert-Tm ($rNew.ok -and $rNew.triados -eq 101 -and $rNew.elegiveis -eq 101) 'C3 Merge NOVO fecha triados=101/101 sem divergencia (ponta boa)'
    Import-Motor $MotorPath
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:Ok + ' OK, ' + $script:Falhas + ' FALHA')
if ($script:Falhas -gt 0) { exit 1 } else { exit 0 }
