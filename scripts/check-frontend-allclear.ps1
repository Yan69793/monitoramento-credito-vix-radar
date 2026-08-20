# check-frontend-allclear.ps1
# Reprova afirmacao de normalidade no frontend que nao esteja protegida por um
# teste de "o dado foi lido".
#
# Motivo (ZEROINDISPONIVEL1, auditoria 2026-08-20). O painel EWS da home publica
# imprimia "Nenhum alerta ativo. Todos os emissores monitorados estao dentro dos
# parametros normais." e o pulso do monitor operacional saia VERDE com "Mercado
# em estabilidade, sem alertas criticos ativos". Os dois com `ewsRankingCache`
# em null e `resultados` vazio, porque op=ews e op=state respondem 401 sem
# sessao. Confirmado ao vivo em producao, elemento visivel com 58px de altura.
#
# Ou seja, um produto de risco de credito afirmava all-clear sobre 103 emissores
# para qualquer visitante, enquanto o estado da semana tinha 74 eventos vivos e
# 23 emissores com evento CRITICO ou RELEVANTE, incluindo a Oi com julgamento de
# falencia marcado para 25/08. Ausencia de dado nao e evidencia de saude.
#
# Este cheque falha se qualquer frase de all-clear voltar a aparecer sem guarda.
# Roda em segundos e nao precisa de rede.
#
# Uso:  powershell.exe -NoProfile -File scripts\check-frontend-allclear.ps1
#
# Regras PS 5.1: conteudo ASCII apenas (sem BOM), ErrorActionPreference Continue,
# exit real no final.

param(
    [string]$Arquivo = $null,
    [string]$Root = 'E:\Diretorio\Claude\Monitoramento de Credito'
)
$ErrorActionPreference = 'Continue'

if (-not $Arquivo) { $Arquivo = Join-Path $Root 'app\index.html' }
if (-not (Test-Path -LiteralPath $Arquivo)) {
    Write-Output ("ERRO: arquivo nao encontrado: " + $Arquivo)
    exit 1
}
$html = [IO.File]::ReadAllText($Arquivo, [Text.Encoding]::UTF8)

# Frases que AFIRMAM normalidade sobre a carteira. Cada uma so pode existir se, na
# mesma vizinhanca, houver um teste de leitura. Padroes escritos sem acento
# opcional para nao depender da forma normalizada do arquivo.
$frasesProibidas = @(
    'Todos os emissores monitorados est',
    'Mercado em estabilidade',
    'dentro dos par.{0,3}metros normais'
)

# Marcadores que provam que alguem checou se o dado existe antes de afirmar.
$guardas = @('_ewsCarregou', '_semLeitura', 'ZEROINDISPONIVEL1')

$JANELA = 1200
$achados = @()
foreach ($frase in $frasesProibidas) {
    foreach ($m in ([regex]::Matches($html, $frase))) {
        $ini = [Math]::Max(0, $m.Index - $JANELA)
        $len = [Math]::Min($JANELA * 2, $html.Length - $ini)
        $ctx = $html.Substring($ini, $len)
        $temGuarda = $false
        foreach ($g in $guardas) { if ($ctx -match [regex]::Escape($g)) { $temGuarda = $true; break } }
        if (-not $temGuarda) {
            $linha = ($html.Substring(0, $m.Index) -split "`n").Count
            $achados += ("  linha ~{0}: '{1}' sem guarda de leitura por perto" -f $linha, $m.Value)
        }
    }
}

# O contrario tambem e achado: guarda removida e frase mantida em outro lugar.
$temAlgumaGuarda = $false
foreach ($g in $guardas) { if ($html -match [regex]::Escape($g)) { $temAlgumaGuarda = $true; break } }
if (-not $temAlgumaGuarda) {
    Write-Output 'FALHA: nenhuma guarda de leitura (_ewsCarregou / _semLeitura) existe no arquivo. O fix do ZEROINDISPONIVEL1 foi removido.'
    exit 1
}

if ($achados.Count -gt 0) {
    Write-Output 'FALHA: afirmacao de normalidade sem guarda de leitura.'
    $achados | ForEach-Object { Write-Output $_ }
    Write-Output 'Ausencia de dado nao e evidencia de saude. Ver ZEROINDISPONIVEL1 em PENDENCIAS.md.'
    exit 1
}

Write-Output ('CHECK_ALLCLEAR_OK arquivo=' + (Split-Path $Arquivo -Leaf) + ' frases_verificadas=' + $frasesProibidas.Count)
exit 0
