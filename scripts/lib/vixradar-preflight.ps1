# vixradar-preflight.ps1 - lib compartilhada do guarda de execucao das rotinas agendadas.
#
# Quem usa: scripts/preflight-and-run.ps1 (o guarda de verdade).
# Regra desta lib: ela NAO decide politica. Ela mede (git, scan, linter) e executa o alvo.
# A decisao de recusar ou deixar passar mora no guarda, para haver um unico lugar onde a
# politica e lida por quem audita.
#
# Nada aqui reimplementa o linter: o parse e delegado a lint-encoding.ps1 (RISCO) e a
# scripts/lib/preflight-scan.ps1 (superseto + marcador de conflito), os dois sob
# powershell.exe 5.1.

$script:PreflightExitRecusa  = 89
$script:PreflightExitTimeout = 124

function Resolve-PreflightPowerShell {
    # A autoridade de parser e o MESMO powershell.exe que o Task Scheduler usa para subir a
    # rotina. Sem fallback para caminho absoluto de proposito: se 'powershell.exe' nao resolve
    # no PATH, a rotina tambem nao subiria, e um fallback aqui seria uma segunda verdade sobre
    # o interpretador - exatamente o tipo de desvio silencioso que este guarda existe para
    # fechar. Ausente no PATH = recusa (fail-closed).
    $c = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
    if ($c) { return [string]$c.Source }
    return $null
}

function Resolve-PreflightRepoRoot {
    param([string]$StartDir)
    if (-not $StartDir) { $StartDir = (Get-Location).Path }
    $r = @(& git -C $StartDir rev-parse --show-toplevel 2>$null) | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $r) { return $null }
    return ($r.ToString().Trim() -replace '/', '\')
}

function Invoke-PreflightProcess {
    # Processo separado, leitura ASSINCRONA dos dois fluxos. Ler um fluxo inteiro antes de
    # esperar o outro e deadlock classico no Windows (buffer de 4 KB por fluxo) - foi o que
    # matou o gate do run-all-tests.ps1 em 14/09/2026; o padrao aqui e o mesmo, corrigido.
    param(
        [string]$Exe,
        [string]$ArgumentLine,
        [int]$TimeoutSec = 14400,
        [string]$WorkingDirectory = '',
        # -SemRedirecionar: o filho HERDA o console do guarda. Usado no alvo (a rotina), para o
        # operador ver a saida em tempo real durante horas em vez de receber tudo no fim. Sem
        # pipe nao existe o risco de deadlock por buffer cheio. As sondas internas (varredura,
        # linter) usam redirecionamento porque precisam capturar a saida.
        [switch]$SemRedirecionar
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $ArgumentLine
    $psi.UseShellExecute = $false
    if (-not $SemRedirecionar) {
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
    }
    $psi.CreateNoWindow = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try { $iniciou = $proc.Start() } catch { return [pscustomobject]@{ Iniciou = $false; Exit = -1; SaidaOut = ''; SaidaErr = ('falha ao iniciar: ' + $_.Exception.Message); Timeout = $false } }
    if (-not $iniciou) { return [pscustomobject]@{ Iniciou = $false; Exit = -1; SaidaOut = ''; SaidaErr = 'processo nao iniciou'; Timeout = $false } }
    if ($SemRedirecionar) {
        $estourouDireto = -not $proc.WaitForExit($TimeoutSec * 1000)
        if ($estourouDireto) {
            try { & taskkill.exe /F /T /PID $proc.Id 2>&1 | Out-Null } catch { }
            try { $proc.Kill() } catch { }
            try { $proc.WaitForExit(5000) | Out-Null } catch { }
            return [pscustomobject]@{ Iniciou = $true; Exit = -1; SaidaOut = ''; SaidaErr = 'timeout: alvo morto com a arvore'; Timeout = $true }
        }
        return [pscustomobject]@{ Iniciou = $true; Exit = $proc.ExitCode; SaidaOut = ''; SaidaErr = ''; Timeout = $false }
    }
    $tOut = $proc.StandardOutput.ReadToEndAsync()
    $tErr = $proc.StandardError.ReadToEndAsync()
    $estourou = -not $proc.WaitForExit($TimeoutSec * 1000)
    if ($estourou) {
        try { & taskkill.exe /F /T /PID $proc.Id 2>&1 | Out-Null } catch { }
        try { $proc.Kill() } catch { }
        try { $proc.WaitForExit(5000) | Out-Null } catch { }
    }
    $saidaOut = ''
    $saidaErr = ''
    if ($tOut.Wait(10000)) { $saidaOut = [string]$tOut.Result }
    if ($tErr.Wait(10000)) { $saidaErr = [string]$tErr.Result }
    $exit = -1
    if (-not $estourou -and $proc.HasExited) { $exit = $proc.ExitCode }
    return [pscustomobject]@{
        Iniciou  = $true
        Exit     = $exit
        SaidaOut = $saidaOut
        SaidaErr = $saidaErr
        Timeout  = $estourou
    }
}

function Quote-PreflightArg {
    param([string]$Valor)
    if ($null -eq $Valor) { return '""' }
    if ($Valor -match '[\s"]') { return '"' + ($Valor -replace '"', '\"') + '"' }
    return $Valor
}

function Get-PreflightGitState {
    param([string]$Root)
    $head = @(& git -C $Root rev-parse HEAD 2>$null) | Select-Object -First 1
    $ref = @(& git -C $Root rev-parse --abbrev-ref HEAD 2>$null) | Select-Object -First 1
    $sujo = @(& git -C $Root status --porcelain 2>$null)
    $n = 0
    foreach ($l in $sujo) { if (('' + $l).Trim()) { $n++ } }
    if (-not $head) { return $null }
    if (-not $ref -or $ref -eq 'HEAD') { $ref = 'detached' }
    return [pscustomobject]@{
        Head    = [string]$head
        Branch  = [string]$ref
        Dirty   = $n
        Linha   = ('head=' + [string]$head + ' branch=' + [string]$ref + ' dirty=' + $n)
    }
}

function ConvertFrom-PreflightJson {
    # Extrai o PRIMEIRO objeto JSON de um blob de texto. Necessario porque lint-encoding.ps1
    # termina com 'return 0' no escopo do script, e isso escreve um 0 solto no stdout: a saida
    # do 'linter -Json' e o JSON seguido de uma linha '0'. Consumidor que faca ConvertFrom-Json
    # no texto inteiro recebe erro de JSON e conclui, errado, que o linter nao respondeu.
    param([string]$Texto)
    $t = ('' + $Texto).Trim()
    if (-not $t) { return $null }
    $i = $t.IndexOf('{')
    $j = $t.LastIndexOf('}')
    if ($i -lt 0 -or $j -le $i) { return $null }
    $recorte = $t.Substring($i, ($j - $i) + 1)
    try { return ($recorte | ConvertFrom-Json) } catch { return $null }
}

function Get-PreflightScan {
    # Roda a varredura do superseto no powershell.exe resolvido. Devolve $null se a varredura
    # NAO pode ser executada - e o chamador tem de recusar (fail-closed).
    param([string]$Root, [string]$PowerShellExe, [int]$TimeoutSec = 900)
    $scanner = Join-Path $Root 'scripts\lib\preflight-scan.ps1'
    if (-not (Test-Path -LiteralPath $scanner)) { return [pscustomobject]@{ Ok = $false; Erro = ('scanner ausente: ' + $scanner); Json = $null } }
    $r = Invoke-PreflightProcess -Exe $PowerShellExe -ArgumentLine ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $scanner + '" -RepoRoot "' + $Root + '" -Json') -TimeoutSec $TimeoutSec -WorkingDirectory $Root
    if (-not $r.Iniciou) { return [pscustomobject]@{ Ok = $false; Erro = $r.SaidaErr; Json = $null } }
    if ($r.Timeout) { return [pscustomobject]@{ Ok = $false; Erro = ('varredura estourou ' + $TimeoutSec + 's'); Json = $null } }
    if ($r.Exit -ne 0) { return [pscustomobject]@{ Ok = $false; Erro = ('varredura saiu com exit ' + $r.Exit + ': ' + $r.SaidaErr.Trim()); Json = $null } }
    $j = ConvertFrom-PreflightJson -Texto $r.SaidaOut
    if (-not $j) { return [pscustomobject]@{ Ok = $false; Erro = ('saida da varredura sem JSON reconhecivel: ' + ('' + $r.SaidaOut).Trim()); Json = $null } }
    if (-not $j.ok) { return [pscustomobject]@{ Ok = $false; Erro = ('varredura recusou: ' + $j.erro); Json = $null } }
    return [pscustomobject]@{ Ok = $true; Erro = ''; Json = $j }
}

function Get-PreflightLinterRisco {
    # RISCO vem do linter canonico do repo, executado - nunca recalculado aqui.
    param([string]$Root, [string]$PowerShellExe, [int]$TimeoutSec = 900)
    $linter = Join-Path $Root 'scripts\lint-encoding.ps1'
    if (-not (Test-Path -LiteralPath $linter)) { return [pscustomobject]@{ Ok = $false; Erro = ('linter ausente: ' + $linter); Risco = $null } }
    # -WorkingDirectory $Root e obrigatorio, nao estilo: sem -Path o linter descobre a raiz com
    # 'git rev-parse --show-toplevel', que usa o DIRETORIO DE TRABALHO DO PROCESSO e nao a raiz
    # que o guarda esta guardando. Medido na prova diferencial: rodando de dentro de outro repo,
    # o linter varria o repo errado (117 arquivos de outra arvore) e o veredito RISCO nao tinha
    # relacao com o alvo. Working directory fixo em $Root fecha isso.
    $r = Invoke-PreflightProcess -Exe $PowerShellExe -ArgumentLine ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $linter + '" -Json') -TimeoutSec $TimeoutSec -WorkingDirectory $Root
    if (-not $r.Iniciou) { return [pscustomobject]@{ Ok = $false; Erro = $r.SaidaErr; Risco = $null } }
    if ($r.Timeout) { return [pscustomobject]@{ Ok = $false; Erro = ('linter estourou ' + $TimeoutSec + 's'); Risco = $null } }
    $texto = ('' + $r.SaidaOut).Trim()
    if (-not $texto) { return [pscustomobject]@{ Ok = $false; Erro = ('linter saiu com exit ' + $r.Exit + ' sem JSON'); Risco = $null } }
    $j = ConvertFrom-PreflightJson -Texto $texto
    if (-not $j) { return [pscustomobject]@{ Ok = $false; Erro = ('JSON do linter ilegivel: ' + $texto); Risco = $null } }
    $risco = $null
    if ($j.PSObject.Properties.Name -contains 'risco') { $risco = [int]$j.risco }
    if ($null -eq $risco) { return [pscustomobject]@{ Ok = $false; Erro = 'JSON do linter sem o campo risco'; Risco = $null } }
    return [pscustomobject]@{ Ok = $true; Erro = ''; Risco = $risco }
}

function Test-PreflightLogDeferido {
    param([string]$Pattern)
    return ($Pattern -and $Pattern.Contains('{yyyyMMdd_HHmmss}'))
}

function Resolve-PreflightLogPath {
    param([string]$Root, [string]$Pattern, [datetime]$Agora)
    $p = $Pattern -replace '\{yyyyMMdd_HHmmss\}', $Agora.ToString('yyyyMMdd_HHmmss')
    $p = $p -replace '\{yyyyMMdd\}', $Agora.ToString('yyyyMMdd')
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $Root $p }
    return $p
}

function New-PreflightDir {
    param([string]$Dir)
    if ($Dir -and -not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Force -Path $Dir | Out-Null }
}

function Write-PreflightStampLog {
    # Grava a linha do guarda no log da rotina ANTES de invocar o alvo, quando o nome do log e
    # previsivel. Arquivo novo (caso normal: log diario do dia) = a linha e a PRIMEIRA linha.
    # Arquivo com conteudo (a rotina ja rodou hoje e esta sendo relancada) = anexa a linha ao
    # fim, porque reescrever o topo de um log ja iniciado inverteria a cronologia.
    param([string]$Path, [string]$StampLine, [datetime]$Agora)
    New-PreflightDir -Dir (Split-Path -Parent $Path)
    if (-not (Test-Path -LiteralPath $Path) -or ([System.IO.FileInfo]::new($Path)).Length -eq 0) {
        [System.IO.File]::WriteAllText($Path, $StampLine + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
        return 'linha1'
    }
    $atual = [System.IO.File]::ReadAllText($Path)
    if ($atual.StartsWith($StampLine)) { return 'ja-presente' }
    Add-Content -LiteralPath $Path -Value ($Agora.ToString('yyyy-MM-dd HH:mm:ss') + ' preflight ' + $StampLine) -Encoding UTF8
    return 'anexado'
}

function Add-PreflightStampDeferido {
    # Rotinas cujo log tem carimbo de hora no nome (vixradar-export_<yyyyMMdd_HHmmss>.log):
    # o nome exato so existe depois de a rotina rodar. O guarda captura o estado ANTES de
    # invocar (o carimbo registra a arvore de lancamento) e, depois que o alvo sai, poe a
    # linha na PRIMEIRA linha do arquivo que a rotina acabou de criar - prepend e seguro aqui
    # porque o arquivo pertence so a esta execucao e o processo filho ja terminou.
    param([string]$Root, [string]$Pattern, [string]$StampLine, [datetime]$Inicio, [datetime]$Agora)
    $glob = $Pattern -replace '\{yyyyMMdd_HHmmss\}', '*'
    $glob = $glob -replace '\{yyyyMMdd\}', $Agora.ToString('yyyyMMdd')
    if (-not [System.IO.Path]::IsPathRooted($glob)) { $glob = Join-Path $Root $glob }
    $cands = @(Get-ChildItem -Path $glob -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $Inicio.AddSeconds(-5) } | Sort-Object LastWriteTime -Descending)
    if ($cands.Count -eq 0) { return 'ausente' }
    $f = $cands[0].FullName
    $txt = [System.IO.File]::ReadAllText($f)
    if ($txt.StartsWith($StampLine)) { return 'ja-presente' }
    [System.IO.File]::WriteAllText($f, $StampLine + "`r`n" + $txt, (New-Object System.Text.UTF8Encoding($false)))
    return 'prependido'
}

function Add-PreflightAudit {
    param([string]$Root, [string]$Linha)
    $dir = Join-Path $Root 'logs\preflight'
    New-PreflightDir -Dir $dir
    $f = Join-Path $dir ('preflight_' + (Get-Date -Format 'yyyyMMdd') + '.log')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $f -Value ($ts + ' ' + $Linha) -Encoding UTF8
    return $f
}
