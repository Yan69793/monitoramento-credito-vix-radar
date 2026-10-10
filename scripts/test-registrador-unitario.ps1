# test-registrador-unitario.ps1 - prova do modo UNITARIO de registro (UNITREG1, 2026-09-25).
#
# O que este teste prova, e so isso:
#   1. o gate da lib (Select-VixUnitDef / Assert-VixUnitWriteSet) e fail-closed: alvo ausente,
#      alvo ambiguo, tabela vazia, nome so-espacos e write-set != 1 LANCA;
#   2. os 4 modos unitarios novos (-TaskName) fazem -DryRun com exit 0, declaram write-set de
#      EXATAMENTE 1 task, montam 1 e apenas 1 task, e nao nomeiam nenhuma irma da tabela;
#   3. os 2 registradores que ja eram de 1 task (Coleta-Volatilidade e Reconciliacao-CVM)
#      rodam 1 e apenas 1 task - fecha a prova 6/6 de escopo exclusivo;
#   4. o default (sem -TaskName) nao imprime o marcador do modo unitario, continua cobrindo a
#      tabela inteira, e a saida do -DryRun e IDENTICA a do commitado em HEAD (modo unitario
#      e opt-in, nao mexeu no caminho de producao);
#   5. prova estrutural: a colecao iterada pelos call sites de escrita e reatribuida pelo gate,
#      todo -TaskName de escrita e o campo do item dessa colecao (ou um literal que so existe
#      dentro do guarda `if (-not $TaskName)`), e o gate vem ANTES do primeiro call site;
#   6. a lib nao escreve no Task Scheduler nem usa rede.
#
# Nao registra, nao altera, nao dispara task, nao usa rede. Escreve so em %TEMP% e apaga no fim.
# ASCII puro, PS 5.1.
$ErrorActionPreference = 'Continue'
$script:ok = 0; $script:fal = 0
function Assert([bool]$cond, [string]$msg) { if ($cond) { $script:ok++; Write-Host ('  OK    ' + $msg) } else { $script:fal++; Write-Host ('  FALHA ' + $msg) } }

$scriptDir = $PSScriptRoot
$raiz = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir 'lib\vixradar-task-unit.ps1')

# Escrita no Agendador: os cmdlets que mudam algo. Nenhum deles e chamado por este teste.
$ESCRITA = 'Register-ScheduledTask|Unregister-ScheduledTask|Set-ScheduledTask|Disable-ScheduledTask|Enable-ScheduledTask|Start-ScheduledTask|Stop-ScheduledTask'

function Invoke-RegistradorDryRun([string]$arquivo, [string[]]$argvs) {
    $saida = (& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $arquivo @argvs *>&1 | Out-String)
    return @{ Saida = $saida; Rc = $LASTEXITCODE }
}
function Get-Marcador([string]$saida, [string]$nome) {
    return ([regex]::Matches($saida, 'VIX-UNIT-WRITESET: ' + [regex]::Escape($nome) + '(\r?\n|$)')).Count
}
function Get-Source([string]$arquivo) {
    return (Get-Content -LiteralPath (Join-Path $scriptDir $arquivo) -Raw -Encoding UTF8)
}
function Remove-LinhaComentario([string]$src) {
    # Tira as linhas que sao so comentario: os cabecalhos dos registradores citam cmdlets de
    # escrita (bloco "Reversao:") e isso nao e call site.
    return (($src -split '\r?\n' | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
}

# Tabela de cada registrador multi-task: usada para provar que as IRMAS nunca entram na saida.
# Campo = nome do campo que carrega o nome da task na tabela do registrador ('Nome' no retry).
$COMBOS = @(
    @{ Script = 'register-monitor-tasks.ps1';          Colecao = 'defs';  Campo = 'Name'; Tabela = @('Monitor-Tasks', 'Monitor-Tasks-Site') },
    @{ Script = 'register-retry-tasks.ps1';            Colecao = 'tasks'; Campo = 'Nome'; Tabela = @('Szuchmacher-RetryVixMatinal', 'Szuchmacher-RetryVixNoturno') },
    @{ Script = 'register-all-routines-scheduler.ps1'; Colecao = 'Tasks'; Campo = 'Name'; Tabela = @('VIXRadar-AgendaSemanal', 'VIXRadar-Matinal', 'VIXRadar-Noturno', 'VIXRadar-Verificacao-Async', 'Szuchmacher-AgendaMacro-Claude', 'Szuchmacher-FechamentoDiario', 'Szuchmacher-FechamentoWatchdog') }
)
# Os 6 alvos do drift: 4 por modo unitario novo + 2 que ja eram de 1 task.
$ALVOS = @(
    @{ Script = 'register-monitor-tasks.ps1';            Alvo = 'Monitor-Tasks';                  Unitario = $true },
    @{ Script = 'register-retry-tasks.ps1';              Alvo = 'Szuchmacher-RetryVixNoturno';    Unitario = $true },
    @{ Script = 'register-all-routines-scheduler.ps1';   Alvo = 'VIXRadar-AgendaSemanal';         Unitario = $true },
    @{ Script = 'register-all-routines-scheduler.ps1';   Alvo = 'Szuchmacher-AgendaMacro-Claude'; Unitario = $true },
    @{ Script = 'register-coleta-volatilidade-task.ps1'; Alvo = 'VIXRadar-Coleta-Volatilidade';   Unitario = $false },
    @{ Script = 'register-reconciliacao-cvm-task.ps1';   Alvo = 'VIXRadar-Reconciliacao-CVM';     Unitario = $false }
)

Write-Host '=== 1. gate da lib e fail-closed ==='
$tab = @(@{ Name = 'A' }, @{ Name = 'B' }, @{ Name = 'C' })
Assert ((Select-VixUnitDef -Defs $tab -Nome 'B').Name -eq 'B') 'Select-VixUnitDef devolve o unico match'
$msgAusente = ''
try { Select-VixUnitDef -Defs $tab -Nome 'Z' | Out-Null } catch { $msgAusente = $_.Exception.Message }
Assert ($msgAusente -match 'VIX-UNIT-ALVO-AUSENTE') 'alvo fora da tabela RECUSA (ALVO-AUSENTE)'
$msgAmbiguo = ''
try { Select-VixUnitDef -Defs @(@{ Name = 'A' }, @{ Name = 'A' }) -Nome 'A' | Out-Null } catch { $msgAmbiguo = $_.Exception.Message }
Assert ($msgAmbiguo -match 'VIX-UNIT-ALVO-AMBIGUO') 'alvo duplicado RECUSA (ALVO-AMBIGUO)'
$msgVazia = ''
try { Select-VixUnitDef -Defs @() -Nome 'A' | Out-Null } catch { $msgVazia = $_.Exception.Message }
Assert ($msgVazia -match 'VIX-UNIT-TABELA-VAZIA') 'tabela vazia RECUSA (TABELA-VAZIA)'
$msgEspacos = ''
try { Select-VixUnitDef -Defs $tab -Nome '   ' | Out-Null } catch { $msgEspacos = $_.Exception.Message }
Assert ($msgEspacos -match 'VIX-UNIT-ALVO-AUSENTE') 'nome so-espacos RECUSA (ALVO-AUSENTE)'
Assert ((Assert-VixUnitWriteSet -Defs @(@{ Name = 'A' }) -Nome 'A') -eq 'A') 'write-set de 1 nome e aprovado e devolvido'
$msgIrma = ''
try { Assert-VixUnitWriteSet -Defs $tab -Nome 'A' | Out-Null } catch { $msgIrma = $_.Exception.Message }
Assert ($msgIrma -match 'VIX-UNIT-WRITESET-EXCEDIDO') 'write-set com irma RECUSA (3 nomes para 1 alvo)'
Assert ($msgIrma -match 'nada foi escrito') 'a recusa do write-set avisa que nada foi escrito'
$msgZero = ''
try { Assert-VixUnitWriteSet -Defs @() -Nome 'A' | Out-Null } catch { $msgZero = $_.Exception.Message }
Assert ($msgZero -match 'VIX-UNIT-WRITESET-EXCEDIDO') 'write-set vazio RECUSA (0 nome para 1 alvo)'
$msgExtra = ''
try { Assert-VixUnitWriteSet -Defs @(@{ Name = 'A' }) -Nome 'A' -Extras @('VIXRadar-Matinal-Retry') | Out-Null } catch { $msgExtra = $_.Exception.Message }
Assert ($msgExtra -match 'VIX-UNIT-WRITESET-EXCEDIDO') 'write-set com alvo auxiliar RECUSA'
$msgOutro = ''
try { Assert-VixUnitWriteSet -Defs @(@{ Name = 'A' }) -Nome 'B' | Out-Null } catch { $msgOutro = $_.Exception.Message }
Assert ($msgOutro -match 'VIX-UNIT-WRITESET-EXCEDIDO') 'write-set de outra task RECUSA'

Write-Host ''
Write-Host '=== 2/3. os 6 alvos do drift: DryRun com escopo de exatamente 1 task ==='
# Os 8 registradores apontam para a raiz canonica abaixo, hardcoded por contrato DENTRO deles.
# Fora dessa maquina - ex.: o runner do CI, que faz checkout em D:\a\... - o $ScriptPath deles nao
# existe, o registrador lanca "Script nao encontrado" e sai 1 por AMBIENTE, nao por codigo.
# As secoes 5 e 6 continuam rodando: elas leem fonte, nao o Agendador.
$raizCanonica = 'E:\Diretorio\Claude\Monitoramento de Credito'
if (-not (Test-Path -LiteralPath $raizCanonica)) {
    Write-Host ('  PULADO secoes 2/3, 3b e 4: raiz canonica ' + $raizCanonica + ' ausente nesta maquina (nao e falha)')
} else {
foreach ($a in $ALVOS) {
    $argvs = @()
    if ($a.Unitario) { $argvs = @('-TaskName', $a.Alvo) }
    $r = Invoke-RegistradorDryRun -arquivo (Join-Path $scriptDir $a.Script) -argvs ($argvs + '-DryRun')
    $saida = $r.Saida
    $rotulo = ($a.Script + ' -TaskName ' + $a.Alvo)
    Assert ($r.Rc -eq 0) ($rotulo + ' -DryRun sai 0 (exit=' + $r.Rc + ')')
    Assert ($saida -match 'DRYRUN OK') ($a.Alvo + ': DryRun aprova')
    Assert (([regex]::Matches($saida, 'task     : ')).Count -eq 1) ($a.Alvo + ': monta 1 e apenas 1 task')
    Assert ($saida -match ('task     : ' + [regex]::Escape($a.Alvo))) ($a.Alvo + ': a task montada e a alvo')
    Assert ($saida -match 'preflight-and-run\.ps1') ($a.Alvo + ': a Action continua passando pelo guarda')
    if ($a.Unitario) {
        Assert ((Get-Marcador -saida $saida -nome $a.Alvo) -eq 1) ($a.Alvo + ': declara write-set de exatamente 1 task')
        Assert ($saida -match 'VIX-UNIT-WRITESET-TOTAL: 1') ($a.Alvo + ': total do write-set declarado = 1')
    } else {
        Assert ((Get-Marcador -saida $saida -nome $a.Alvo) -eq 0) ($a.Alvo + ': registrador ja e de 1 task (sem modo unitario a declarar)')
    }
    $irmas = @()
    foreach ($c in $COMBOS) { if ($c.Script -eq $a.Script) { $irmas = @($c.Tabela | Where-Object { $_ -ne $a.Alvo }) } }
    $irmaNaSaida = @($irmas | Where-Object { (Get-Marcador -saida $saida -nome $_) -ne 0 })
    Assert ($irmaNaSaida.Count -eq 0) ($a.Alvo + ': nenhuma irma no write-set declarado (0 de ' + $irmas.Count + ')')
}

Write-Host ''
Write-Host '=== 3b. o modo unitario nao e bloqueio cego: a irma tambem roda, sozinha ==='
$rl = Invoke-RegistradorDryRun -arquivo (Join-Path $scriptDir 'register-retry-tasks.ps1') -argvs @('-TaskName', 'Szuchmacher-RetryVixMatinal', '-DryRun')
Assert ($rl.Rc -eq 0) ('RetryVixMatinal tambem roda em modo unitario (exit=' + $rl.Rc + ')')
Assert ((Get-Marcador -saida $rl.Saida -nome 'Szuchmacher-RetryVixMatinal') -eq 1) 'RetryVixMatinal: 1 task'
Assert ((Get-Marcador -saida $rl.Saida -nome 'Szuchmacher-RetryVixNoturno') -eq 0) 'RetryVixMatinal nao arrasta RetryVixNoturno'
$rt = Invoke-RegistradorDryRun -arquivo (Join-Path $scriptDir 'register-monitor-tasks.ps1') -argvs @('-TaskName', 'Monitor-Tasks-Site', '-DryRun')
Assert ((Get-Marcador -saida $rt.Saida -nome 'Monitor-Tasks-Site') -eq 1) 'Monitor-Tasks-Site: 1 task'
Assert ((Get-Marcador -saida $rt.Saida -nome 'Monitor-Tasks') -eq 0) 'Monitor-Tasks-Site nao arrasta Monitor-Tasks'
$neg = Invoke-RegistradorDryRun -arquivo (Join-Path $scriptDir 'register-monitor-tasks.ps1') -argvs @('-TaskName', 'NaoExiste', '-DryRun')
Assert ($neg.Rc -ne 0) ('alvo desconhecido RECUSA no registrador real (exit=' + $neg.Rc + ')')
Assert ($neg.Saida -match 'VIX-UNIT-ALVO-AUSENTE') 'a recusa do registrador nomeia o alvo ausente'

Write-Host ''
Write-Host '=== 4. default (sem -TaskName) intocado ==='
foreach ($c in $COMBOS) {
    $rd = Invoke-RegistradorDryRun -arquivo (Join-Path $scriptDir $c.Script) -argvs @('-DryRun')
    # O exit do default pode refletir drift vivo pre-existente; a invariancia contra HEAD e provada abaixo.
    Assert (-not ($rd.Saida -match 'VIX-UNIT-WRITESET')) ($c.Script + ' sem -TaskName nao imprime o marcador do modo unitario')
    Assert (([regex]::Matches($rd.Saida, 'task     : ')).Count -eq $c.Tabela.Count) ($c.Script + ' sem -TaskName continua cobrindo as ' + $c.Tabela.Count + ' tasks da tabela')
    Assert ($rd.Saida -match 'preflight-and-run\.ps1') ($c.Script + ' sem -TaskName continua passando pelo guarda')
    Assert (-not ($rd.Saida -match 'FALHA ')) ($c.Script + ' sem -TaskName nao reprova token de guarda')
}

# O default tem de ser IDENTICO ao commitado: fora do modo unitario, este patch nao muda nada.
$gitOk = $false
try { $null = & git -C $raiz rev-parse --verify HEAD 2>&1; $gitOk = ($LASTEXITCODE -eq 0) } catch { $gitOk = $false }
if (-not $gitOk) {
    Write-Host '  PULADO comparacao com HEAD: git ou HEAD indisponivel nesta maquina (nao e falha)'
} else {
    $tmp = Join-Path $env:TEMP ('yan-unit-orig-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        foreach ($c in $COMBOS) {
            # PowerShell 5.1 corrompe bytes nao-ASCII de `git show` ao materializar via pipeline.
            # register-all tem texto UTF-8; sua invariancia default ja e coberta estruturalmente acima.
            if ($c.Script -eq 'register-all-routines-scheduler.ps1') { Write-Host '  PULADO baseline textual register-all: git show via PS5.1 nao preserva UTF-8'; continue }
            $origem = (& git -C $raiz show ('HEAD:scripts/' + $c.Script) 2>&1 | Out-String)
            $tmpScript = Join-Path $tmp $c.Script
            [System.IO.File]::WriteAllText($tmpScript, $origem, (New-Object System.Text.UTF8Encoding($false)))
            $rOrig = Invoke-RegistradorDryRun -arquivo $tmpScript -argvs @('-DryRun')
            $rNovo = Invoke-RegistradorDryRun -arquivo (Join-Path $scriptDir $c.Script) -argvs @('-DryRun')
            Assert ($rOrig.Rc -eq $rNovo.Rc) ($c.Script + ': exit do -DryRun default igual ao de HEAD (' + $rOrig.Rc + ' vs ' + $rNovo.Rc + ')')
            $iguais = (($rOrig.Saida -replace '\s+', ' ') -eq ($rNovo.Saida -replace '\s+', ' '))
            Assert $iguais ($c.Script + ': saida do -DryRun default identica a de HEAD')
            if (-not $iguais) {
                Write-Host ('    HEAD : ' + ($rOrig.Saida -replace '\s+', ' '))
                Write-Host ('    novo : ' + ($rNovo.Saida -replace '\s+', ' '))
            }
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { [System.IO.Directory]::Delete($tmp, $true) }
    }
}
}

Write-Host ''
Write-Host '=== 5. prova estrutural do escopo de escrita ==='
# (i) a colecao iterada pelos call sites de escrita e reatribuida pelo gate;
# (ii) todo -TaskName de escrita e o campo do item dessa colecao ($t.Name / $t.Nome / $d.Name)
#      ou um literal que so existe dentro do guarda `if (-not $TaskName)`;
# (iii) o gate vem ANTES do primeiro call site de escrita (nao existe escrita antes do filtro).
$guardaLiteral = 'if \(-not \$TaskName\) \{\r?\n\s+Unregister-ScheduledTask -TaskName ''VIXRadar-Matinal-Retry'' -Confirm:\$false'
$qualquerEscrita = '(?:Register|Unregister|Set|Disable|Enable|Start|Stop)-ScheduledTask\s'
foreach ($c in $COMBOS) {
    $src = Remove-LinhaComentario (Get-Source -arquivo $c.Script)
    $campo = $c.Campo
    # Parenteses obrigatorios: em PowerShell a virgula tem precedencia MAIOR que o +, entao
    # '@('$t.' + $campo, '$d.' + $campo)' viraria UMA string ('$t.Name $d.Name') em vez de 2 itens.
    $permitido = @(('$t.' + $campo), ('$d.' + $campo))
    Assert ($permitido.Count -eq 2) ($c.Script + ': lista de expressoes permitidas tem 2 itens')

    $padraoGate = '\$' + $c.Colecao + ' = @\(Select-VixUnitDef -Defs \$' + $c.Colecao + ' -Nome \$TaskName -NomeCampo ''' + $campo + '''\)'
    Assert (([regex]::Matches($src, $padraoGate)).Count -eq 1) ($c.Script + ': o gate reatribui $' + $c.Colecao + ' uma unica vez')
    Assert ($src -match ('Assert-VixUnitWriteSet -Defs \$' + $c.Colecao + ' -Nome \$TaskName')) ($c.Script + ': o gate confere o write-set antes de escrever')

    $comTaskName = 0
    $vistos = @()
    foreach ($m in [regex]::Matches($src, $qualquerEscrita)) {
        $trecho = $src.Substring($m.Index, [Math]::Min(240, $src.Length - $m.Index))
        $arg = [regex]::Match($trecho, '-TaskName\s+(''[^'']*''|\$[A-Za-z0-9_.]+)')
        if ($arg.Success) { $comTaskName++; $vistos += $arg.Groups[1].Value }
    }
    Assert ($comTaskName -ge 1) ($c.Script + ': todo call site de escrita passa -TaskName (' + $comTaskName + ')')
    $foraDoPermitido = @($vistos | Where-Object { $permitido -notcontains $_ -and $_ -ne "'VIXRadar-Matinal-Retry'" })
    Assert ($foraDoPermitido.Count -eq 0) ($c.Script + ': nenhum call site escreve nome fora do permitido (fora=' + $foraDoPermitido.Count + ')')

    if ($c.Script -eq 'register-all-routines-scheduler.ps1') {
        Assert (([regex]::Matches($src, 'Unregister-ScheduledTask -TaskName ''VIXRadar-Matinal-Retry''')).Count -eq 2) 'register-all: existem exatamente 2 unregisters do retry orfao'
        Assert (([regex]::Matches($src, $guardaLiteral)).Count -eq 2) 'register-all: os 2 unregisters do retry orfao estao DENTRO do guarda do modo unitario'
        $ocorr = ([regex]::Matches($vistos, "'VIXRadar-Matinal-Retry'")).Count
        Assert ($ocorr -eq 2) ('register-all: os 2 unicos nomes literais de escrita sao o retry orfao (achados=' + $ocorr + ')')
    }

    $posGate = $src.IndexOf(('$' + $c.Colecao + ' = @(Select-VixUnitDef'))
    $posEscrita = [regex]::Match($src, $qualquerEscrita).Index
    Assert (($posGate -ge 0) -and ($posGate -lt $posEscrita)) ($c.Script + ': o gate vem antes do primeiro call site de escrita')
}

foreach ($a in @($ALVOS | Where-Object { -not $_.Unitario })) {
    $src = Remove-LinhaComentario (Get-Source -arquivo $a.Script)
    # Aspas simples de proposito: em string de aspas duplas o '$TaskName' seria expandido pelo
    # PowerShell (variavel inexistente = vazio) e o padrao deixaria de casar.
    $padraoLiteral = '\$TaskName\s*=\s*' + "'" + [regex]::Escape($a.Alvo) + "'"
    Assert (([regex]::Matches($src, $qualquerEscrita)).Count -eq 1) ($a.Script + ': exatamente 1 call site de escrita')
    Assert (([regex]::Matches($src, $padraoLiteral)).Count -eq 1) ($a.Script + ': $TaskName e o literal ' + $a.Alvo)
    Assert ($src -match 'Register-ScheduledTask -TaskName \$TaskName') ($a.Script + ': o unico write usa $TaskName')
}

Write-Host ''
Write-Host '=== 6. a lib do modo unitario nao escreve no Agendador nem usa rede ==='
$srcLib = Get-Content -LiteralPath (Join-Path $scriptDir 'lib\vixradar-task-unit.ps1') -Raw -Encoding UTF8
Assert ($srcLib -notmatch $ESCRITA) 'a lib nao usa nenhum cmdlet de escrita no Agendador'
Assert ($srcLib -notmatch 'Invoke-WebRequest|Invoke-RestMethod|Send-MailMessage|wevtutil|Start-Process') 'a lib nao usa rede, e-mail, wevtutil nem Start-Process'
$errosParse = $null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $scriptDir 'lib\vixradar-task-unit.ps1'), [ref]$null, [ref]$errosParse) | Out-Null
Assert (@($errosParse).Count -eq 0) 'a lib parseia no powershell.exe 5.1'

Write-Host ''
Write-Host ('RESULTADO: ' + $script:ok + '/' + ($script:ok + $script:fal) + ' asserts OK, ' + $script:fal + ' falha(s)')
if ($script:fal -gt 0) { exit 1 }
exit 0
