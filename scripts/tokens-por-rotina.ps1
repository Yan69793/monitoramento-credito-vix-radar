# tokens-por-rotina.ps1 - tabela de tokens por rotina e por lote na regua unica, com o
# circuito de custo do dia (CUSTO_DIA ... MARGEM). Le os *_metrics_<data>.json dos
# runners e o log da sentinela. Ver scripts\lib\vixradar-custo.ps1 (REGUA-UNICA1).
#
# Uso: tokens-por-rotina.ps1 [-Inicio yyyyMMdd] [-Fim yyyyMMdd] [-LogDir ...] [-Detalhe]
# PowerShell 5.1, ASCII puro, exit 0 sempre (e regua, nao guarda).

param(
    [string]$Inicio,
    [string]$Fim,
    [string]$LogDir = 'E:\Diretorio\Claude\Monitoramento de Credito\logs\routines',
    [switch]$Detalhe
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\vixradar-custo.ps1')

if (-not $Fim) { $Fim = Get-Date -Format 'yyyyMMdd' }
if (-not $Inicio) { $Inicio = $Fim }
$cfg = Get-VixCustoConfig $LogDir
$dtIni = [datetime]::ParseExact($Inicio, 'yyyyMMdd', $null)
$dtFim = [datetime]::ParseExact($Fim, 'yyyyMMdd', $null)

Write-Host ('CONFIG: TETO_DIA=' + $cfg.TETO_DIA + ' RESERVA_VERIFICACAO=' + $cfg.RESERVA_VERIFICACAO + ' MARGEM_MINIMA=' + $cfg.MARGEM_MINIMA)
Write-Host ('{0,-9} {1,-12} {2,-13} {3,10} {4,10} {5,12} {6,12} {7,10} {8,6} {9,6} {10,10}' -f 'dia', 'rotina', 'regua', 'input', 'output', 'cache_creat', 'cache_read', 'trabalho', 'lotes', 'emis', 'trab/emis')

$d = $dtIni
while ($d -le $dtFim) {
    $tag = $d.ToString('yyyyMMdd')
    $c = Get-VixCustoDia $LogDir $tag $cfg
    foreach ($k in @('matinal', 'noturno', 'verificacao', 'sentinela', 'agenda')) {
        $p = $c.por_rotina[$k]
        if ($p.trabalho -eq 0 -and $p.regua -eq 'ausente') { continue }
        $porEmis = '-'
        if ($p.emissores -gt 0) { $porEmis = [math]::Round($p.trabalho / $p.emissores) }
        Write-Host ('{0,-9} {1,-12} {2,-13} {3,10} {4,10} {5,12} {6,12} {7,10} {8,6} {9,6} {10,10}' -f $tag, $k, $p.regua, $p.input, $p.output, $p.cache_creation, $p.cache_read, $p.trabalho, $p.lotes, $p.emissores, $porEmis)
        if ($Detalhe) {
            $arq = switch ($k) {
                'matinal' { 'matinal_metrics_' + $tag + '.json' }
                'noturno' { 'noturno_metrics_' + $tag + '.json' }
                'verificacao' { 'verificacao_async_metrics_' + $tag + '.json' }
                'agenda' { 'agenda-semanal_metrics_' + $tag + '.json' }
                default { '' }
            }
            if ($arq) {
                $m = Read-VixMetrics (Join-Path $LogDir $arq)
                if ($m -and $m.PSObject.Properties['lotes_detalhe']) {
                    foreach ($lt in $m.lotes_detalhe) {
                        Write-Host ('  LOTE ' + $lt.nome + ' fila=' + $lt.fila + ' emissores=' + $lt.emissores + ' input=' + $lt.input + ' output=' + $lt.output + ' cache_creation=' + $lt.cache_creation + ' cache_read=' + $lt.cache_read + ' trabalho=' + $lt.trabalho + ' duracao_sec=' + $lt.duracao_sec)
                    }
                }
            }
        }
    }
    Write-Host $c.linha
    $d = $d.AddDays(1)
}
exit 0
