# run-all-tests.ps1 - runner da suite de scripts/ (2026-09-12).
#
# Motivo: nao existia agregador. Nem o pre-commit nem o GitHub Actions rodavam os
# scripts/test-*.ps1, entao suites ficaram vermelhas por dias sem ninguem notar, e uma delas
# (test-busca-degradada) morria na extracao de funcao e escondia ~40 asserts verdadeiros.
# Suite que ninguem roda nao e suite, e decoracao.
#
# Contrato:
#   - enumera scripts/test-*.ps1 e executa cada um em PROCESSO separado, com timeout;
#   - compara o resultado com o baseline de falhas conhecidas (scripts/tests-baseline.json);
#   - exit 0 somente quando nenhuma suite fora do baseline esta vermelha;
#   - suite do baseline que ficou VERDE vira aviso de baseline obsoleto (nao falha): o baseline
#     so encolhe, por edicao explicita, nunca por acidente.
#
# Uso:
#   pwsh ./scripts/run-all-tests.ps1                 # roda tudo menos os pesados
#   pwsh ./scripts/run-all-tests.ps1 -Listar         # so lista, nao executa
#   pwsh ./scripts/run-all-tests.ps1 -IncluirPesados # inclui os que mexem em log/lock real
#   pwsh ./scripts/run-all-tests.ps1 -SoPadrao monitor
#
# PowerShell 5.1, ASCII puro (sem BOM necessario), $ErrorActionPreference Continue, exit real.
param(
    [switch]$Listar,
    [switch]$IncluirPesados,
    [int]$TimeoutSec = 300,
    [string]$SoPadrao
)

$ErrorActionPreference = 'Continue'
$ScriptsDir = $PSScriptRoot
$Root = Split-Path $ScriptsDir -Parent
$BaselineFile = Join-Path $ScriptsDir 'tests-baseline.json'

# Suites que NAO entram no gate por padrao. Motivo MEDIDO, nao precaucao:
#   test-locks-overlap: sobe o motor REAL quatro vezes (run_vixradar_varredura.ps1) e escreve
#   log/lock/transcript em logs\routines do dia. Leva ~7 min e deixa residuo se falhar no meio.
#
#   Os dois M3 nao sao teste unitario: sao smoke/relatorio AO VIVO, contra servico externo pago
#   ou contra producao, e dependem de credencial que o CI nao tem (nem deve ter). Sem a chave eles
#   falham por ambiente, nao por codigo - e o gate fica vermelho por motivo que nao e regressao.
#   Ficam fora do gate por isso, com o motivo escrito aqui, em vez de entrarem no baseline (que e
#   para defeito conhecido no codigo).
# Usa -IncluirPesados para rodar.
$Pesados = @{
    'test-locks-overlap.ps1' = 'sobe o motor real e escreve log/lock do dia em logs\routines'
    'test-m3-openrouter-search.ps1' = 'smoke pago ao vivo no OpenRouter; exige OPENROUTER_API_KEY e payload local nao versionado'
    'test-m3-reconciliacao.ps1' = 'relatorio ao vivo contra producao; exige ROUTINE_API_KEY'
}

function Get-Suites {
    $todas = @(Get-ChildItem -Path $ScriptsDir -Filter 'test-*.ps1' -File | Sort-Object Name)
    $out = @()
    foreach ($f in $todas) {
        if ($SoPadrao -and ($f.Name -notmatch $SoPadrao)) { continue }
        if ((-not $IncluirPesados) -and $Pesados.ContainsKey($f.Name)) { continue }
        $out += $f
    }
    return $out
}

function Read-Baseline {
    # Devolve @{ nome = motivo }. Ausente ou ilegivel vira baseline VAZIO, que e o padrao seguro:
    # sem baseline, qualquer suite vermelha reprova o gate. Nunca esconder falha por arquivo
    # faltando.
    $mapa = @{}
    if (-not (Test-Path $BaselineFile)) { return $mapa }
    try {
        $j = Get-Content $BaselineFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) {
            if ($p.Name -eq '_doc') { continue }
            $mapa[$p.Name] = [string]$p.Value.motivo
        }
    } catch {
        Write-Host ('AVISO: baseline ilegivel (' + $_.Exception.Message + ') - tratando como vazio.')
    }
    return $mapa
}

function Invoke-Suite {
    # Roda a suite em processo separado com timeout real. Nao deixa o runner pendurar numa suite
    # travada, nem herda exit code de outra.
    #
    # Leitura ASSINCRONA (nao negociar): a suite escreve em stdout E stderr, cada um com buffer
    # proprio de ~4 KB no Windows. Ler um fluxo ate o fim (ReadToEnd) antes de esperar o outro e
    # deadlock classico: o filho enche o buffer do segundo fluxo, bloqueia na escrita, o primeiro
    # fluxo nunca fecha e o WaitForExit com timeout NUNCA chega a ser avaliado. Foi o que matou o
    # gate: test-retry-janela.ps1 escreve ~10 KB em stderr (medido em 14/09/2026, ambiente do CI
    # simulado) e o job ficou 30 min parado ate o teto do workflow cancelar - 5/5 execucoes, sem
    # nenhuma linha de suite depois de test-preflight-429.ps1. Ler os dois em paralelo resolve o
    # deadlock e faz o timeout valer de verdade.
    param([System.IO.FileInfo]$Arquivo, [int]$Segundos)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $Arquivo.FullName + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $iniciou = $false
    try {
        $iniciou = $proc.Start()
    } catch {
        return [pscustomobject]@{ Nome = $Arquivo.Name; Exit = -1; Saida = ('falha ao iniciar: ' + $_.Exception.Message); Timeout = $false }
    }
    if (-not $iniciou) {
        return [pscustomobject]@{ Nome = $Arquivo.Name; Exit = -1; Saida = 'processo nao iniciou'; Timeout = $false }
    }
    $tarefaOut = $proc.StandardOutput.ReadToEndAsync()
    $tarefaErr = $proc.StandardError.ReadToEndAsync()
    $estourou = -not $proc.WaitForExit($Segundos * 1000)
    if ($estourou) {
        # Arvore inteira: suite travada pode ter neto segurando o pipe, e neto sobrevivente
        # mantem o job do CI vivo (e o runner lendo) mesmo depois do kill do processo direto.
        try { & taskkill.exe /F /T /PID $proc.Id 2>&1 | Out-Null } catch { }
        try { $proc.Kill() } catch { }
        try { $proc.WaitForExit(5000) | Out-Null } catch { }
    }
    # Drenagem com teto: depois do kill um neto pode continuar segurando o pipe. Nunca bloquear
    # aqui de novo - o que foi capturado ate o teto e o que vai para o resumo.
    $textoOut = '(leitura de stdout nao fechou apos o kill)'
    $textoErr = '(leitura de stderr nao fechou apos o kill)'
    if ($tarefaOut.Wait(10000)) { $textoOut = [string]$tarefaOut.Result }
    if ($tarefaErr.Wait(10000)) { $textoErr = [string]$tarefaErr.Result }
    $exit = -1
    if (-not $estourou) { $exit = $proc.ExitCode }
    $texto = ($textoOut + "`n" + $textoErr)
    return [pscustomobject]@{ Nome = $Arquivo.Name; Exit = $exit; Saida = $texto; Timeout = $estourou }
}

function Get-ResumoSuite([string]$Texto) {
    # Ultima linha de resumo conhecida. Cada familia de suite usa um rotulo proprio; listar as
    # variantes aqui e o que permite resumir sem depender de um formato unico.
    foreach ($l in @(($Texto -split "`r?`n"))) {
        $t = ('' + $l).Trim()
        if ($t.StartsWith('RESULTADO')) { return $t }
    }
    if ($Texto -match '(?m)^\s*(PASS|OK)\s*') { return '(sem linha de resumo; executou assercoes)' }
    return '(sem linha de resumo)'
}

$baseline = Read-Baseline
$suites = @(Get-Suites)
$pesadosPulados = @()
if (-not $IncluirPesados) {
    foreach ($k in $Pesados.Keys) { $pesadosPulados += $k }
}

if ($Listar) {
    Write-Host ('Suite de scripts/ - ' + $suites.Count + ' arquivo(s)')
    foreach ($s in $suites) { Write-Host ('  ' + $s.Name) }
    foreach ($k in $pesadosPulados) { Write-Host ('  ' + $k + '   [PULADO: ' + $Pesados[$k] + ']') }
    if ($baseline.Count -gt 0) {
        Write-Host 'Baseline de falhas conhecidas:'
        foreach ($k in $baseline.Keys) { Write-Host ('  ' + $k + ' - ' + $baseline[$k]) }
    }
    exit 0
}

Write-Host '=== SUITE DE SCRIPTS ==='
Write-Host ('runner: ' + $suites.Count + ' suite(s) | timeout ' + $TimeoutSec + 's | baseline ' + $baseline.Count + ' falha(s) conhecida(s)')
Write-Host ''

$verdes = 0
$vermelhas = @()
$novas = @()
$baselineObsoleto = @()
$baselineConfirmado = @()

foreach ($s in $suites) {
    $t0 = Get-Date
    $r = Invoke-Suite -Arquivo $s -Segundos $TimeoutSec
    $dur = [Math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    $resumo = Get-ResumoSuite $r.Saida
    $rotulo = 'ok'
    $cor = 'OK  '
    if ($r.Timeout) {
        $rotulo = 'timeout'
        $cor = 'FAIL'
    } elseif ($r.Exit -ne 0) {
        $rotulo = 'falha'
        $cor = 'FAIL'
    }
    Write-Host ($cor + ' ' + $s.Name.PadRight(38) + ' ' + $resumo + '  [' + $dur + 's exit=' + $r.Exit + ']')
    if ($r.Timeout) {
        # Timeout e FAIL, mas e FAIL de OUTRO tipo: a suite nao terminou, entao nao ha veredito
        # sobre o codigo. Dizer isso aqui evita ler "travou" como "quebrou".
        Write-Host ('       TRAVOU: nao terminou em ' + $TimeoutSec + 's; processo e arvore mortos pelo runner.')
    }

    $noBaseline = $baseline.ContainsKey($s.Name)
    if ($rotulo -eq 'ok') {
        $verdes++
        if ($noBaseline) { $baselineObsoleto += $s.Name }
    } else {
        $vermelhas += $s.Name
        if ($noBaseline) {
            $baselineConfirmado += $s.Name
        } else {
            $novas += $s.Name
            # Imprime as falhas reais da suite nova, para o operador nao precisar reabrir a saida.
            foreach ($l in @(($r.Saida -split "`r?`n"))) {
                $t = ('' + $l).Trim()
                if ($t -match '^(FALHA|FAIL)') { Write-Host ('       ' + $t) }
            }
        }
    }
}

Write-Host ''
Write-Host ('TOTAL: ' + $suites.Count + ' suite(s) | verde=' + $verdes + ' | vermelha=' + $vermelhas.Count)
if ($baselineConfirmado.Count -gt 0) {
    Write-Host ('  falha conhecida (baseline confirmado): ' + $baselineConfirmado.Count)
    foreach ($n in $baselineConfirmado) { Write-Host ('    - ' + $n + ' - ' + $baseline[$n]) }
}
if ($novas.Count -gt 0) {
    Write-Host ('  REGRESSAO NOVA (nao esta no baseline): ' + $novas.Count)
    foreach ($n in $novas) { Write-Host ('    - ' + $n) }
}
if ($baselineObsoleto.Count -gt 0) {
    Write-Host '  AVISO: baseline obsoleto, estas suites ja estao verdes e podem sair do arquivo:'
    foreach ($n in $baselineObsoleto) { Write-Host ('    - ' + $n) }
}
foreach ($k in $pesadosPulados) { Write-Host ('  PULADO (pesado): ' + $k + ' - ' + $Pesados[$k]) }

# Exit = regressoes novas. Suite que trava (exit 1 sem resumo) tambem conta, de proposito:
# vermelho visivel e melhor que verde falso.
if ($novas.Count -gt 0) { exit [Math]::Min($novas.Count, 255) }
exit 0
