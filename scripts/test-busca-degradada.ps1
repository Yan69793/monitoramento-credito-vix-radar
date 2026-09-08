# test-busca-degradada.ps1 - BUSCADEGRADADA1 (2026-09-08), offline POR CONTRATO.
# Reproduz o modo de falha do lote noturno de 08/09: POST unico de 15 emissores com server
# tools, limite max_total_results esgotado apos 2 buscas; as 23 seguintes voltam com texto
# "sem resultados - limite de busca" / "sem resultados por restricao de max_total_results".
# Antes do fix o regex do motor contava essas buscas como EFETIVAS (nao casavam os padroes
# antigos) e o emissor saia ANALISADO/sem_eventos certificado, alimentando "sem fato novo"
# falso no feed. Depois do fix, emissor com ZERO buscas efetivas e >=1 degradada vira
# pendente (INCONCLUSIVO no fluxo, rechecagem normal), nunca sem_eventos certificado.
# Extrai as funcoes REAIS do motor por AST e as exercita com fixtures. ASCII puro (PS 5.1,
# sem BOM) para rodar identico em pwsh 7.
$ErrorActionPreference = 'Continue'
$fail = 0
$pass = 0

function Assert-True([bool]$cond, [string]$nome) {
    if ($cond) { $script:pass++; Write-Host ('PASS: ' + $nome) }
    else { $script:fail++; Write-Host ('FAIL: ' + $nome) }
}

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

$MotorPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_varredura.ps1'
foreach ($_def in (Get-MotorFuncDefs $MotorPath @('Test-VixBuscaDegradada', 'Resolve-VixCoberturaWeb'))) { Invoke-Expression $_def }

Write-Host '== Test-VixBuscaDegradada: o que E degradada (evidencia explicita) =='
Assert-True (Test-VixBuscaDegradada 'sem resultados - limite de busca') 'D1: "sem resultados - limite de busca" (texto real 08/09) = degradada'
Assert-True (Test-VixBuscaDegradada 'sem resultados por restricao de max_total_results') 'D2: "max_total_results" = degradada'
Assert-True (Test-VixBuscaDegradada 'limite de busca atingido apos 2 buscas') 'D3: "limite de busca" = degradada'
Assert-True (Test-VixBuscaDegradada 'busca esgotada') 'D4: "esgotad" = degradada'
Assert-True (Test-VixBuscaDegradada 'servico indisponivel no momento') 'D5: "indisponivel" = degradada'
Assert-True (Test-VixBuscaDegradada 'servico indisponivel no momento') 'D5b: "indisponivel" sem acento = degradada'
Assert-True (Test-VixBuscaDegradada 'falha na ferramenta de busca') 'D6: "falha" = degradada'
Assert-True (Test-VixBuscaDegradada 'erro ao executar a busca') 'D7: "erro" = degradada'
Assert-True (Test-VixBuscaDegradada 'busca nao executada por limite') 'D8: "nao execut" = degradada'
Assert-True (Test-VixBuscaDegradada 'timeout na busca web') 'D9: "timeout" = degradada'
Assert-True (Test-VixBuscaDegradada 'restricao de busca por volume') 'D10: "restric.*busca" = degradada'

Write-Host '== Test-VixBuscaDegradada: o que NAO e degradada (busca valida) =='
Assert-True (-not (Test-VixBuscaDegradada 'artigos de julho/2026 ja em eventos_conhecidos; sem fato novo na janela')) 'N1: resultado descritivo real (Raizen 08/09) NAO e degradada'
Assert-True (-not (Test-VixBuscaDegradada 'Fitch afirmou e retirou A+(bra) em jan/2026; sem novidades na janela')) 'N2: resultado descritivo real (BRK 08/09) NAO e degradada'
Assert-True (-not (Test-VixBuscaDegradada 'resultados apontam apenas eventos de agosto/2026, nenhum fato novo')) 'N3: "sem fato na janela" NAO e degradada'
Assert-True (-not (Test-VixBuscaDegradada 'sem eventos')) 'N4: "sem eventos" (busca rodou e nada achou) NAO e degradada'
Assert-True (-not (Test-VixBuscaDegradada 'sem resultados visiveis na janela delta')) 'N5: "sem resultados" GENERICO (sem marcador de limite/falha) NAO e degradada'
Assert-True (-not (Test-VixBuscaDegradada 'emissao confirmada')) 'N6: achado positivo NAO e degradada'
Assert-True (-not (Test-VixBuscaDegradada '')) 'N7: vazio NAO e degradada (nao conta como evidencia, mas nao e falha explicita)'

Write-Host '== Resolve-VixCoberturaWeb: cenario do lote noturno de 08/09 =='
function New-Fonte([string]$r) { [pscustomobject]@{ rodada = 'R2'; query = 'x'; resultado = $r } }
function New-Res([object[]]$fontes, [object[]]$eventos) {
    return [pscustomobject]@{ sem_eventos = $true; classificacao_geral = 'NENHUM'; eventos = $eventos; fontes_consultadas = $fontes }
}

# Emissor A: 2 buscas OK reais (as 2 unicas que passaram antes do limite esgotar).
$resA = New-Res @((New-Fonte 'artigos de julho/2026 ja em eventos_conhecidos; sem fato novo na janela'), (New-Fonte 'Fitch afirmou e retirou A+(bra) em jan/2026; sem novidades na janela')) @()
$cobA = Resolve-VixCoberturaWeb $resA
Assert-True ($cobA.efetivas -eq 2 -and $cobA.degradadas -eq 0) 'A1: 2 buscas reais = 2 efetivas, 0 degradadas'
Assert-True (-not $cobA.pendente) 'A2: emissor com busca real NAO fica pendente (tem evidencia)'

# Emissor B: todas as buscas esgotadas por limite (a degradacao silenciosa do dia).
$resB = New-Res @((New-Fonte 'sem resultados - limite de busca'), (New-Fonte 'sem resultados por restricao de max_total_results')) @()
$cobB = Resolve-VixCoberturaWeb $resB
Assert-True ($cobB.efetivas -eq 0 -and $cobB.degradadas -eq 2) 'B1: buscas so esgotadas = 0 efetivas, 2 degradadas'
Assert-True $cobB.pendente 'B2: emissor sem evento e 0 buscas efetivas com degradada = PENDENTE (nao certifica sem_eventos)'

# Emissor C: misto 1 real + 1 esgotada (Raizen 08/09) - tem ao menos 1 evidencia real.
$resC = New-Res @((New-Fonte 'artigos de julho/2026 ja em eventos_conhecidos; sem fato novo na janela'), (New-Fonte 'sem resultados - limite de busca')) @()
$cobC = Resolve-VixCoberturaWeb $resC
Assert-True ($cobC.efetivas -eq 1 -and $cobC.degradadas -eq 1) 'C1: 1 real + 1 esgotada = 1 efetiva, 1 degradada'
Assert-True (-not $cobC.pendente) 'C2: 1 busca real basta para NAO ficar pendente (evidencia existe)'

# Emissor D: degradada mas COM evento (CRITICO com fonte) - evento entregue nao e bloqueado.
$ev = [pscustomobject]@{ classificacao = 'CRITICO'; titulo = 'Rebaixamento'; data_evento = '2026-09-08'; fonte_primaria = 'https://www.rad.cvm.gov.br/enet/frmDownloadDocumento.aspx?id=9' }
$resD = New-Res @((New-Fonte 'sem resultados - limite de busca')) @($ev)
$cobD = Resolve-VixCoberturaWeb $resD
Assert-True (-not $cobD.pendente) 'D1: com evento presente nunca fica pendente (entrega real prevalece)'

# Emissor E: sem fontes nenhuma (parse quebrado/fallback) - nao e degradacao, e ausencia de busca.
$resE = New-Res @() @()
$cobE = Resolve-VixCoberturaWeb $resE
Assert-True ($cobE.efetivas -eq 0 -and $cobE.degradadas -eq 0) 'E1: sem fontes = 0/0'
Assert-True (-not $cobE.pendente) 'E2: sem fontes nao entra no ramo degradada (segue regra antiga FULL 0 buscas)'

Write-Host ''
Write-Host ('RESULTADO: pass=' + $pass + ' fail=' + $fail)
if ($fail -gt 0) { exit 1 } else { exit 0 }
