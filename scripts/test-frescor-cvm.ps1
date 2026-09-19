# test-frescor-cvm.ps1 - poe o harness Node do frescor da fonte CVM no gate de scripts/.
#
# HARNESSMORTO1 (2026-09-19). O run-all-tests.ps1 enumera scripts/test-*.ps1 e mais nada,
# entao os harness .mjs de scripts/ nunca entraram em gate nenhum. O test-frescor-cvm.mjs
# saiu com exit 1 em TODA execucao de 20/08 a 19/09, quebrado pelo CVMCADENCIA1 (73c3a5d),
# e o unico jeito de descobrir isso era alguem rodar o arquivo a mao. Suite que gate nenhum
# roda nao e suite, e decoracao (mesma frase do run-all-tests.ps1, mesmo motivo).
#
# Este wrapper nao testa nada por conta propria: roda o .mjs, repassa a saida linha a linha
# e devolve o mesmo veredito, com a linha RESULTADO que o runner usa no resumo.
#
# Node ausente REPROVA, nao pula. Pular seria o mesmo verde falso que deixou o harness morto
# por um mes.
#
# PowerShell 5.1, ASCII puro, $ErrorActionPreference Continue, exit real.
$ErrorActionPreference = 'Continue'

$mjs = Join-Path $PSScriptRoot 'test-frescor-cvm.mjs'
if (-not (Test-Path $mjs)) {
    Write-Host ('FALHA harness ausente em ' + $mjs)
    Write-Host 'RESULTADO: FALHA (test-frescor-cvm.mjs nao encontrado)'
    exit 1
}

$node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $node) {
    Write-Host 'FALHA node ausente do PATH, o harness test-frescor-cvm.mjs nao pode rodar'
    Write-Host 'RESULTADO: FALHA (node ausente, a suite nao executou)'
    exit 1
}

# stderr do node chega como ErrorRecord no 5.1, e linha vazia dele vira o nome do tipo
# (System.Management.Automation.RemoteException). Usar a Message tira esse ruido.
$saida = & $node.Path $mjs 2>&1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { '' + $_.Exception.Message } else { '' + $_ }
}
$rc = $LASTEXITCODE
foreach ($linha in $saida) { Write-Host $linha }

# O .mjs fecha sempre com uma destas tres: TUDO VERDE, N FALHA(S) ou EXTRACAO INCOMPLETA
# (dependencia fora da lista de extracao, nenhum caso rodou). Qualquer outra coisa quer
# dizer que o node morreu no meio, e isso tambem precisa aparecer no resumo do runner.
$resumo = ''
foreach ($linha in $saida) {
    $t = ('' + $linha).Trim()
    if ($t -match '^(TUDO VERDE|\d+ FALHA\(S\)|EXTRACAO INCOMPLETA)') { $resumo = $t }
}
if ($resumo -eq '') { $resumo = 'sem linha de resumo, o node saiu antes de terminar os casos' }

if ($rc -eq 0) {
    Write-Host ('RESULTADO: ' + $resumo)
    exit 0
}
Write-Host ('RESULTADO: FALHA exit=' + $rc + ' | ' + $resumo)
exit 1
