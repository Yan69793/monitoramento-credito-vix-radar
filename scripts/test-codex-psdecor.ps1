# test-codex-psdecor.ps1 - prova de duas correcoes no caminho Codex CLI (2026-10-09).
#
#   1) CODEX-PSDECOR1 (P3): Get-Content -Raw devolve uma STRING COM note properties
#      (PSPath/PSParentPath/PSChildName/PSDrive/PSProvider/ReadCount). ConvertTo-Json desce
#      nelas e o envelope vira {"result":{"value":"<texto>",...}}, que o parser le como
#      "@{value=[...]; PSPath=...}" e rejeita. Foi a causa dos 5 lotes e dos 20 emissores
#      stale da Agenda Semanal em 07/10/2026 (agendasem_rawout_agendasem-*_20261007.txt).
#      Correcao: cast [string] (ToString) antes de montar o envelope.
#
#   2) CODEX-SKILLBLOCK1 (P1): o Codex anunciava as skills do host (~/.agents/skills) ao
#      modelo, que tentava le-las via `pwsh -Command Get-Content` e levava "blocked by policy"
#      do sandbox read-only; todo lote saia FALLO_PROVEEDOR com 0 analise (09/10/2026).
#      Correcao: -c features.skip_host_skill_discovery=true em toda invocacao.
#
# Offline puro: nenhum codex executado, nenhum token, nenhuma rede. ASCII puro, PS 5.1.
$ErrorActionPreference = 'Continue'

$script:ok = 0; $script:fal = 0
function Assert([bool]$c, [string]$m) { if ($c) { $script:ok++; Write-Host ('  OK    ' + $m) } else { $script:fal++; Write-Host ('  FALHA ' + $m) } }

$tmp = Join-Path $env:TEMP ('vixpsdecor_' + $PID)
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    # ---------- 1: reproducao e correcao da decoracao ----------
    Write-Host '=== 1: CODEX-PSDECOR1 - envelope do resultado do codex ==='
    $jsonArray = '[{"empresa":"Santos Brasil","trimestres":[]}]'
    $arq = Join-Path $tmp 'codex_out.txt'
    # Sem BOM: o codex escreve o arquivo de resultado em UTF-8 puro.
    [System.IO.File]::WriteAllText($arq, $jsonArray, (New-Object System.Text.UTF8Encoding($false)))

    $sujo = Get-Content -LiteralPath $arq -Raw -Encoding UTF8
    $temNote = ($null -ne $sujo.PSObject.Properties['PSPath'])
    Write-Host ('  info  esta sessao PowerShell decora Get-Content -Raw? ' + $temNote)

    # Envelope do jeito ANTIGO (sem cast): se a versao decora, o objeto vira {value,...}.
    $envAntigo = [ordered]@{ result = $sujo; is_error = $false; model = 'codex-subscription' }
    $linhaAntiga = '' + (ConvertFrom-Json (ConvertTo-Json $envAntigo -Compress)).result
    if ($temNote) {
        Assert ($linhaAntiga -notlike '`[*') '1a: sem cast, o texto deixa de ser o array (reproduz o defeito de 07/10)'
        Assert ($linhaAntiga -match 'PSPath=') '1b: o wrapper "@{value=...; PSPath=...}" aparece (prova do defeito)'
    } else {
        Write-Host '  info  versao sem decoracao: o defeito 1a/1b nao se manifesta aqui (validado nos logs de 07/10)'
    }

    # Envelope do jeito NOVO (com cast [string]): sempre o texto puro.
    $limpo = [string](Get-Content -LiteralPath $arq -Raw -Encoding UTF8)
    $envNovo = [ordered]@{ result = $limpo; is_error = $false; model = 'codex-subscription' }
    $linhaNova = '' + (ConvertFrom-Json (ConvertTo-Json $envNovo -Compress)).result
    Assert ($linhaNova.Trim() -eq $jsonArray) '1c: com cast [string], o envelope preserva o texto exato'
    Assert ($linhaNova.TrimStart().StartsWith('[')) '1d: o resultado volta a comecar com "[" (array legivel pelo parser)'

    # ---------- 2: parser real da Agenda sobre as duas saidas ----------
    Write-Host ''
    Write-Host '=== 2: parser da Agenda sobre a saida antiga x nova (AST, sem executar a rotina) ==='
    $agendaPath = Join-Path $PSScriptRoot 'run_vixradar_agenda_semanal.ps1'
    $tk = $null; $er = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($agendaPath, [ref]$tk, [ref]$er)
    Assert ($er.Count -eq 0) ('2a: run_vixradar_agenda_semanal.ps1 faz parse sem erro (' + $er.Count + ')')
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($nome in @('Get-BalancedJson', 'Get-CalendarioArray')) {
        $d = $defs | Where-Object { $_.Name -eq $nome } | Select-Object -First 1
        if ($d) { Invoke-Expression $d.Extent.Text } else { Assert $false ('funcao presente ' + $nome) }
    }
    if (Get-Command Get-CalendarioArray -ErrorAction SilentlyContinue) {
        # Saida ANTIGA: exatamente a forma gravada em agendasem_rawout_*_20261007.txt.
        $saidaAntiga = @('@{value=' + $jsonArray + '; PSPath=' + $arq + '; PSParentPath=' + $tmp + '; PSChildName=codex_out.txt; PSDrive=; PSProvider=; ReadCount=1}')
        $rAntigo = Get-CalendarioArray $saidaAntiga
        Assert ($null -eq $rAntigo) '2b: a saida decorada de 07/10 faz o parser devolver null (reproducao)'
        # Saida NOVA: o array puro.
        $rNovo = Get-CalendarioArray @($jsonArray)
        Assert (($null -ne $rNovo) -and (@($rNovo).Count -eq 1)) '2c: o array puro e parseado (1 item)'
    }

    # ---------- 3: estatico - todo caminho codex tem cast + flag ----------
    Write-Host ''
    Write-Host '=== 3: cobertura estatica dos caminhos Codex de producao ==='
    $prod = @(
        'run_vixradar_varredura.ps1',
        'run_vixradar_sentinela.ps1',
        'run_vixradar_verificacao_async.ps1',
        'run_vixradar_agenda_semanal.ps1'
    )
    # COBERTURA-13OUT1 (2026-10-13): o conjunto de -c do Codex passou a viver numa funcao unica,
    # Get-VixCodexArgsBase (lib\vixradar-cobertura.ps1). O assert agora exige que a lib contenha o
    # skip_host_skill_discovery E que cada rotina invoque o codex pela funcao (ou pelo literal antigo).
    $libCob = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'lib\vixradar-cobertura.ps1') -Raw -Encoding UTF8
    Assert ($libCob -match "'features\.skip_host_skill_discovery=true'") '3-lib: Get-VixCodexArgsBase contem skip_host_skill_discovery'
    foreach ($f in $prod) {
        $src = Get-Content -LiteralPath (Join-Path $PSScriptRoot $f) -Raw -Encoding UTF8
        Assert (($src -match 'features\.skip_host_skill_discovery=true') -or ($src -match 'Get-VixCodexArgsBase')) ('3-' + $f + ': invoca codex com skip_host_skill_discovery')
        Assert ($src -match '\[string\]\(Get-Content .*(codex|Codex)(OutFile|ResultFile)') ('3-' + $f + ': le o resultado do codex com cast [string]')
        Assert (($src -match '--sandbox') -and ($src -match 'read-only')) ('3-' + $f + ': sandbox segue read-only (nao afrouxada)')
    }

    # ---------- 4: o sandbox nao foi afrouxado ----------
    Write-Host ''
    Write-Host '=== 4: o sandbox continua restritivo (a correcao REDUZ capacidade) ==='
    $todos = ''
    foreach ($f in $prod) { $todos += (Get-Content -LiteralPath (Join-Path $PSScriptRoot $f) -Raw -Encoding UTF8) }
    Assert (-not ($todos -match 'danger-full-access')) '4a: nenhuma invocacao usa danger-full-access'
    Assert (-not ($todos -match 'workspace-write')) '4a2: nenhuma invocacao usa workspace-write'
    Assert ($todos -match '--ignore-user-config') '4b: --ignore-user-config preservado'
    Assert ($todos -match '--ignore-rules') '4c: --ignore-rules preservado'
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
