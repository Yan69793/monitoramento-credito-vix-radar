# cobertura-por-emissor.ps1 - regua unica de cobertura e duplicidade das rotinas de analise.
#
# COBERTURA-DESENHO1 (2026-09-02). Ate aqui a cobertura do dia era lida da linha
# FIM: ("Total do dia 103/103", "submit_ok=103"), que conta SUBMISSAO aceita, nao
# analise feita. Medido em 01/09: 33 analisados, 69 deferidos, e o log dizia 103/103.
# Este script le o ledger OK| de noturna, matinal e sentinela (quatro formatos que
# conviveram na mesma semana: 5 campos da matinal, 6 campos da noturna ate 31/08,
# 7 campos com <status> desde 01/09, e "OK| nome eventos=N" da sentinela) e conta,
# por dia: analisados por rotina, emissores analisados mais de uma vez no dia,
# deferidos, e ha quantos dias cada emissor nao recebe analise.
#
# Duplicidade "sem fato novo" so e classificavel quando o log traz a linha
# ALVO <nome> ... cvm_novos=N (sentinela desde 25/08, runners desde 02/09). Sem
# ela, o duplicado sai como n/d, nunca como "sem fato novo" por suposicao.
#
# Uso: cobertura-por-emissor.ps1 [-Inicio yyyyMMdd] [-Fim yyyyMMdd] [-LogDir ...] [-JsonOut ...] [-Quiet]
# PowerShell 5.1, ASCII puro, exit 0 sempre (e regua, nao guarda).

param(
    [string]$Inicio,
    [string]$Fim,
    [string]$LogDir = 'E:\Diretorio\Claude\Monitoramento de Credito\logs\routines',
    [string]$JsonOut,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

if (-not $Fim) { $Fim = Get-Date -Format 'yyyyMMdd' }
if (-not $Inicio) { $Inicio = ([datetime]::ParseExact($Fim, 'yyyyMMdd', $null)).AddDays(-6).ToString('yyyyMMdd') }
if (-not $JsonOut) {
    $monDir = Join-Path (Split-Path $LogDir -Parent) 'monitor-tasks'
    if (-not (Test-Path $monDir)) { New-Item -ItemType Directory -Force -Path $monDir | Out-Null }
    $JsonOut = Join-Path $monDir ('cobertura_' + $Fim + '.json')
}

function Out-Linha([string]$msg) { if (-not $Quiet) { Write-Host $msg } }

function Parse-LinhaLedger([string]$l, [string]$rot) {
    if ($rot -eq 'sentinela') {
        if ($l -match '^\S+ \S+\s+OK\|\s*(.+?)\s+eventos=(\d+)') {
            return @{ nome = $Matches[1].Trim(); status = 'ANALISADO' }
        }
        return $null
    }
    if ($l -match '^\S+ \S+ (OK|DRYRUN)\|') {
        $tipo = $Matches[1]
        $p = $l -split '\|'
        if ($p.Count -lt 4) { return $null }
        $nome = $p[1].Trim()
        if (-not $nome) { return $null }
        $campo = ''
        if ($p.Count -ge 7) { $campo = $p[6].Trim() } else { $campo = $p[3].Trim() }
        $st = 'ANALISADO'
        if ($campo -eq 'DEFERIDO') { $st = 'DEFERIDO' }
        elseif ($campo -eq 'SKIP' -or $campo -eq '-' -or $campo -eq '') { $st = 'SKIP' }
        if ($tipo -eq 'DRYRUN') { $st = 'DRYRUN' }
        return @{ nome = $nome; status = $st }
    }
    return $null
}

$dtIni = [datetime]::ParseExact($Inicio, 'yyyyMMdd', $null)
$dtFim = [datetime]::ParseExact($Fim, 'yyyyMMdd', $null)
$rotinas = @('matinal', 'noturno', 'sentinela')
$ultima = @{}
$universoRef = @()
$dias = @()

$d = $dtIni
while ($d -le $dtFim) {
    $tag = $d.ToString('yyyyMMdd')
    $porRot = @{}
    $vezes = @{}
    $fatoNovo = @{}
    $deferidos = @{}
    $skips = @{}
    $dryruns = @{}
    foreach ($rot in $rotinas) {
        $f = Join-Path $LogDir ('vixradar-' + $rot + '_' + $tag + '.log')
        $set = @{}
        if (Test-Path $f) {
            foreach ($l in (Get-Content $f -Encoding UTF8)) {
                if ($l -match '^\S+ \S+\s+ALVO\s+(.+?)\s+tier=\S+\s+cvm_novos=(\d+)') {
                    $n = $Matches[1].Trim(); $cn = [int]$Matches[2]
                    if (-not $fatoNovo.ContainsKey($n)) { $fatoNovo[$n] = 0 }
                    if ($cn -gt $fatoNovo[$n]) { $fatoNovo[$n] = $cn }
                    continue
                }
                $r = Parse-LinhaLedger $l $rot
                if ($null -eq $r) { continue }
                switch ($r.status) {
                    'ANALISADO' {
                        $set[$r.nome] = 1
                        if (-not $vezes.ContainsKey($r.nome)) { $vezes[$r.nome] = @() }
                        $vezes[$r.nome] += $rot
                        if ((-not $ultima.ContainsKey($r.nome)) -or ($ultima[$r.nome] -lt $tag)) { $ultima[$r.nome] = $tag }
                    }
                    'DEFERIDO' { $deferidos[$r.nome] = 1 }
                    'SKIP' { $skips[$r.nome] = 1 }
                    'DRYRUN' { $dryruns[$r.nome] = 1 }
                }
            }
            if ($rot -eq 'noturno') {
                $nomesLog = @()
                foreach ($l in (Get-Content $f -Encoding UTF8)) { $r2 = Parse-LinhaLedger $l $rot; if ($r2) { $nomesLog += $r2.nome } }
                $nomesLog = $nomesLog | Sort-Object -Unique
                if ($nomesLog.Count -ge 90) { $universoRef = $nomesLog }
            }
        }
        $porRot[$rot] = @($set.Keys)
    }
    $dups = @()
    foreach ($n in $vezes.Keys) {
        if ($vezes[$n].Count -ge 2) {
            $fn = 'n/d'
            if ($fatoNovo.ContainsKey($n)) { if ($fatoNovo[$n] -gt 0) { $fn = 'com_fato_novo' } else { $fn = 'sem_fato_novo' } }
            $dups += @{ nome = $n; rotinas = @($vezes[$n]); fato_novo = $fn }
        }
    }
    $unicos = @($vezes.Keys).Count
    $nSem = @($dups | Where-Object { $_.fato_novo -eq 'sem_fato_novo' }).Count
    $nCom = @($dups | Where-Object { $_.fato_novo -eq 'com_fato_novo' }).Count
    $nNd = @($dups | Where-Object { $_.fato_novo -eq 'n/d' }).Count
    $linha = 'DIA ' + $tag + ': matinal=' + @($porRot['matinal']).Count + ' noturno=' + @($porRot['noturno']).Count + ' sentinela=' + @($porRot['sentinela']).Count +
        ' | analisados_unicos=' + $unicos + ' | duplicados=' + $dups.Count + ' (sem_fato_novo=' + $nSem + ' com_fato_novo=' + $nCom + ' n/d=' + $nNd + ')' +
        ' | deferidos=' + @($deferidos.Keys).Count + ' skip=' + @($skips.Keys).Count + ' dryrun=' + @($dryruns.Keys).Count
    Out-Linha $linha
    if ($dups.Count -gt 0) {
        $txt = ($dups | Sort-Object { $_.nome } | ForEach-Object { $_.nome + '[' + ($_.rotinas -join '+') + ',' + $_.fato_novo + ']' }) -join '; '
        Out-Linha ('  DUPLICADOS ' + $tag + ': ' + $txt)
    }
    $dias += @{
        dia = $tag
        por_rotina = @{ matinal = @($porRot['matinal']).Count; noturno = @($porRot['noturno']).Count; sentinela = @($porRot['sentinela']).Count }
        analisados_unicos = $unicos
        duplicados = $dups
        deferidos = @($deferidos.Keys).Count
        deferidos_nomes = @($deferidos.Keys | Sort-Object)
        skip = @($skips.Keys).Count
        dryrun = @($dryruns.Keys).Count
    }
    $d = $d.AddDays(1)
}

if ($universoRef.Count -eq 0) { $universoRef = @($ultima.Keys | Sort-Object) }
$semAnalise = @()
foreach ($n in $universoRef) {
    $u = ''
    if ($ultima.ContainsKey($n)) { $u = $ultima[$n] }
    $idade = -1
    if ($u) { $idade = [int]($dtFim - [datetime]::ParseExact($u, 'yyyyMMdd', $null)).TotalDays }
    $semAnalise += @{ nome = $n; ultima = $u; dias = $idade }
}
$grupos = $semAnalise | Group-Object { $_.dias } | Sort-Object { [int]$_.Name }
Out-Linha ('UNIVERSO=' + $universoRef.Count + ' (referencia: log da noturna com >=90 emissores, ou uniao dos nomes vistos)')
foreach ($g in $grupos) {
    $rot = 'dias_sem_analise=' + $g.Name
    if ([int]$g.Name -lt 0) { $rot = 'sem_analise_no_intervalo' }
    Out-Linha ('  ' + $rot + ': ' + $g.Count + ' emissores')
}
$velhos = $semAnalise | Where-Object { $_.dias -ge 3 -or $_.dias -lt 0 } | Sort-Object { $_.dias } -Descending
if (@($velhos).Count -gt 0) {
    Out-Linha ('  >=3 DIAS OU NUNCA: ' + (($velhos | ForEach-Object { $_.nome + '=' + $(if ($_.ultima) { $_.ultima } else { 'nunca' }) }) -join '; '))
}

$saida = @{
    inicio = $Inicio; fim = $Fim; gerado_em = (Get-Date).ToString('s')
    universo = $universoRef.Count
    dias = $dias
    ultima_analise = $ultima
    sem_analise = $semAnalise
}
try {
    $saida | ConvertTo-Json -Depth 6 | Set-Content -Path $JsonOut -Encoding UTF8
    Out-Linha ('JSON: ' + $JsonOut)
} catch {
    Write-Host ('AVISO: nao gravou JSON em ' + $JsonOut + ': ' + $_.Exception.Message)
}
exit 0
