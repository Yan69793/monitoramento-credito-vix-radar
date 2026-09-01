param(
    [Parameter(Mandatory=$true)][string]$LogPath
)

# SUBMITOK-ENGANOSO1 (2026-09-01). Achado 31/08/2026: a linha FIM: do log
# noturno reportava "submit_ok=103", tecnicamente correto (103 linhas OK|
# gravadas) e enganoso de ler, 103 sugere 103 analises quando eram 50
# analisados, 22 SKIP e 31 DEFERIDOS por cap de sessao. O SKILL.md da rotina
# ganhou um sexto campo <status> na linha OK| (SKIP|ANALISADO|DEFERIDO) e a
# linha FIM: ganhou analisados=/skip=/deferidos=/submits_aceitos= explicitos.
# Este script confere que os dois lados concordam: o que a linha FIM: declara
# bate com o que o ledger OK| realmente contem. Nao muda orcamento, rotacao
# nem politica de deferimento, so audita a contagem.
#
# Uso manual ou em CI: check-ledger-noturno.ps1 -LogPath <caminho do log do dia>

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $LogPath)) {
    Write-Host "ERRO: log nao encontrado: $LogPath"
    exit 1
}

$linhas = Get-Content $LogPath -Encoding UTF8

$skip = 0
$analisado = 0
$deferido = 0
$submitsAceitos = 0
$semStatus = 0

foreach ($l in $linhas) {
    if ($l -match '^\S+ \S+ OK\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|(true|false)\|(SKIP|ANALISADO|DEFERIDO)\s*$') {
        $submitOk = $Matches[5]
        $status = $Matches[6]
        if ($submitOk -eq 'true') { $submitsAceitos++ }
        switch ($status) {
            'SKIP' { $skip++ }
            'ANALISADO' { $analisado++ }
            'DEFERIDO' { $deferido++ }
        }
    } elseif ($l -match '^\S+ \S+ OK\|') {
        $semStatus++
    }
}

$totalOk = $skip + $analisado + $deferido
Write-Host "LEDGER: analisados=$analisado skip=$skip deferidos=$deferido submits_aceitos=$submitsAceitos total_ok=$totalOk sem_status=$semStatus"

$fim = $linhas | Where-Object { $_ -match '^\S+ \S+ FIM:' } | Select-Object -Last 1
if (-not $fim) {
    Write-Host "AVISO: nenhuma linha FIM: encontrada neste log, nada para conferir."
    exit 0
}
Write-Host "FIM_LINE: $fim"

$erro = $false

if ($fim -match 'Total do dia (\d+)/') {
    $nDeclarado = [int]$Matches[1]
    if ($nDeclarado -ne $totalOk) {
        Write-Host "ERRO: Total do dia declarado=$nDeclarado, ledger real (skip+analisado+deferido)=$totalOk"
        $erro = $true
    }
} elseif ($fim -match 'submit_ok=(\d+)') {
    $nDeclarado = [int]$Matches[1]
    if ($nDeclarado -ne $totalOk) {
        Write-Host "ERRO: submit_ok declarado=$nDeclarado, ledger real (skip+analisado+deferido)=$totalOk"
        $erro = $true
    }
}

if ($fim -match 'analisados=(\d+)') {
    $v = [int]$Matches[1]
    if ($v -ne $analisado) { Write-Host "ERRO: analisados declarado=$v, ledger=$analisado"; $erro = $true }
} else {
    Write-Host "ERRO: linha FIM: sem campo analisados= (formato antigo, SUBMITOK-ENGANOSO1 nao aplicado)"
    $erro = $true
}

if ($fim -match 'skip=(\d+)') {
    $v = [int]$Matches[1]
    if ($v -ne $skip) { Write-Host "ERRO: skip declarado=$v, ledger=$skip"; $erro = $true }
} else {
    Write-Host "ERRO: linha FIM: sem campo skip="
    $erro = $true
}

if ($fim -match 'deferidos=(\d+)') {
    $v = [int]$Matches[1]
    if ($v -ne $deferido) { Write-Host "ERRO: deferidos declarado=$v, ledger=$deferido"; $erro = $true }
} else {
    Write-Host "ERRO: linha FIM: sem campo deferidos="
    $erro = $true
}

if ($fim -match 'submits_aceitos=(\d+)') {
    $v = [int]$Matches[1]
    if ($v -ne $submitsAceitos) { Write-Host "ERRO: submits_aceitos declarado=$v, ledger=$submitsAceitos"; $erro = $true }
} else {
    Write-Host "ERRO: linha FIM: sem campo submits_aceitos="
    $erro = $true
}

if ($semStatus -gt 0) {
    Write-Host "ERRO: $semStatus linha(s) OK| sem campo <status> valido (formato antigo ou incompleto)"
    $erro = $true
}

if ($erro) {
    exit 1
} else {
    Write-Host "OK: linha FIM: consistente com o ledger OK|."
    exit 0
}
