# check-drivers-preditivos.ps1
# Mede a cobertura real de cada driver do score preditivo no export diario e
# reprova driver declarado no codigo que nunca produz valor em producao.
#
# Motivo (DRIVERMORTO1, auditoria 2026-08-20): scorePreditivoRuleV1 declara 6
# drivers (evento, momentum, mercado, recorrencia, desagio, merton). Em producao
# so 3 aparecem. merton_dd esta null nos 103 emissores em TODOS os exports desde
# 2026-07-11, porque o gate exige market_cap e nenhuma das duas fontes lidas
# publica esse campo: fundamentals:altman:latest vem da DFP da CVM (balanco, sem
# valor de mercado) e cotacoes:volatilidade:v1 se recusa a publicar preco por
# acao como market cap, de proposito. O caminho nunca executou uma unica vez.
# momentum e mercado tambem ficam em zero (velocity_delta 0 com tem_serie false,
# spread_score 0). Nada disso aparecia em log, health ou alerta: o pipeline
# gravava normalmente, o export subia, tudo verde. Codigo morto que se apresenta
# como driver ativo faz o modelo parecer mais rico do que e.
#
# Uso:   powershell.exe -NoProfile -File scripts\check-drivers-preditivos.ps1
#        -Export <caminho\predictive.json>   (padrao: export mais recente)
#        -Estrito                            (exit 1 se algum driver zerar)
#
# Regras PS 5.1: conteudo ASCII apenas (sem BOM), ErrorActionPreference Continue,
# exit real no final (contrato com o Task Scheduler).

param(
    [string]$Export = $null,
    [string]$Root = 'E:\Diretorio\Claude\Monitoramento de Credito',
    [switch]$Estrito
)
$ErrorActionPreference = 'Continue'

# Drivers que scorePreditivoRuleV1 (api\src\worker.js) pode emitir. Se o Worker
# ganhar um driver novo, ele entra aqui, senao o cheque passa a mentir por baixo.
$DRIVERS_DECLARADOS = @('evento', 'momentum', 'mercado', 'recorrencia', 'desagio', 'merton')

# Drivers ja diagnosticados como mortos em 20/08. Ficam de fora do exit 1 para o
# cheque nao virar ruido diario, mas continuam reportados no log. Tirar daqui
# assim que a fonte de dado que falta entrar no ar.
$MORTOS_CONHECIDOS = @{
    'merton'   = 'sem market_cap em fundamentals:altman:latest nem em cotacoes:volatilidade:v1 (DRIVERMORTO1)'
    'momentum' = 'velocity_delta zerado, serie ews:hist ainda curta (tem_serie false)'
    'mercado'  = 'spread_score zerado, anbima:zscores nao alimenta o gate >= 10'
}

if (-not $Export) {
    $dirHist = Join-Path $Root 'data\historico'
    if (-not (Test-Path -LiteralPath $dirHist)) {
        Write-Output ('ERRO: diretorio de historico ausente: ' + $dirHist)
        exit 1
    }
    $ultimo = Get-ChildItem -LiteralPath $dirHist -Directory |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $ultimo) {
        Write-Output 'ERRO: nenhum export datado em data\historico.'
        exit 1
    }
    $Export = Join-Path $ultimo.FullName 'predictive.json'
}

if (-not (Test-Path -LiteralPath $Export)) {
    Write-Output ('ERRO: export nao encontrado: ' + $Export)
    exit 1
}

try {
    $pred = Get-Content -LiteralPath $Export -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Output ('ERRO: export ilegivel (' + $Export + '): ' + $_.Exception.Message)
    exit 1
}

if (-not $pred.emissores) {
    Write-Output 'ERRO: export sem a lista de emissores.'
    exit 1
}

$total = @($pred.emissores).Count
if ($total -eq 0) {
    Write-Output 'ERRO: export com 0 emissores.'
    exit 1
}

$contagem = @{}
foreach ($d in $DRIVERS_DECLARADOS) { $contagem[$d] = 0 }
$mertonComValor = 0

foreach ($e in @($pred.emissores)) {
    $pv = $e.predictive_v1
    if (-not $pv) { continue }
    if ($pv.merton_dd -ne $null) { $mertonComValor++ }
    if (-not $pv.drivers) { continue }
    foreach ($d in @($pv.drivers)) {
        $nome = [string]$d
        if ($contagem.ContainsKey($nome)) { $contagem[$nome]++ }
        else { $contagem[$nome] = 1 }
    }
}

Write-Output ('EXPORT: ' + $Export)
Write-Output ('RUN_DATE: ' + $pred.run_date + ' emissores=' + $total + ' user_facing=' + $pred.user_facing)

$zerados = @()
foreach ($d in $DRIVERS_DECLARADOS) {
    $n = $contagem[$d]
    $pct = [Math]::Round(100.0 * $n / $total, 1)
    $linha = ('DRIVER {0,-12} cobertura={1,3}/{2} ({3}%)' -f $d, $n, $total, $pct)
    if ($n -eq 0) {
        $zerados += $d
        if ($MORTOS_CONHECIDOS.ContainsKey($d)) {
            $linha += ' MORTO_CONHECIDO: ' + $MORTOS_CONHECIDOS[$d]
        } else {
            $linha += ' MORTO_NOVO: driver declarado no codigo sem nenhuma ocorrencia'
        }
    }
    Write-Output $linha
}
Write-Output ('MERTON_DD com valor: ' + $mertonComValor + '/' + $total)

# Driver novo zerado e o caso que importa: alguem ligou um driver que nao produz
# nada e o pipeline nao reclamou. Esse reprova sempre, independente de -Estrito.
$novosMortos = @($zerados | Where-Object { -not $MORTOS_CONHECIDOS.ContainsKey($_) })
if ($novosMortos.Count -gt 0) {
    Write-Output ('FALHA: driver declarado sem cobertura nenhuma: ' + ($novosMortos -join ', '))
    exit 1
}

if ($Estrito -and $zerados.Count -gt 0) {
    Write-Output ('FALHA (modo estrito): drivers zerados: ' + ($zerados -join ', '))
    exit 1
}

if ($zerados.Count -gt 0) {
    Write-Output ('AVISO: ' + $zerados.Count + ' driver(s) zerado(s), todos ja diagnosticados. Ver PENDENCIAS.md DRIVERMORTO1.')
}
Write-Output 'CHECK_DRIVERS_OK'
exit 0
