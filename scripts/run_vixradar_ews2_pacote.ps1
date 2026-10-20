# run_vixradar_ews2_pacote.ps1 - Regenera o pacote EWS 2.0 (`ews2:latest`) e grava no KV de producao.
#
# Substitui o passo manual de 18/10/2026 (pacote de 16/10 gerado a mao, nota 126). Sem LLM: so Python local,
# o validador do proprio adaptador do Worker e wrangler. NUNCA toca em `ews2:flag` (ligar/desligar e do operador).
#
# Conferencia automatica (EWS2CONF1, controle da nota 126): depois de publicar, registra o pacote no livro de previsoes
# (data/ews2-previsoes) e compara EWS 2.0 e EWS atual contra eventos reais (scripts/predictive/ews2/conferencia.py, criterio
# pre-registrado e pinado por hash). Veredito "desligar" (evidencia forte de que o EWS 2.0 e pior): a rotina escreve
# ews2:flag = {"ativo": false, ...} depois de guardar o valor anterior. E o UNICO caso em que ela toca em ews2:flag e nunca
# para ligar. Sem -Publicar a conferencia roda sem rede e so informa.
#
# Fluxo, cada passo fail-closed:
#   1. Backtest de referencia fixo (data/validacao/g0v4/backtest_real_v4_20261018.json) com sha256 pinado. O backtest
#      decide QUAIS sinais sao expostos; trocar ele e decisao do operador, entao hash diferente aborta.
#   2. T = ultimo dia util ANTERIOR a hoje (calendario.dia_util do ews2), salvo -T explicito.
#   2b. atualizar_dados.py: baixa ITR, DFP, FCA e COTAHIST do ano e a Selic (Ipeadata); cotacao ou Selic mais de 5 dias
#      antes de T aborta (H5 sobre preco velho seria mentira). -SemDownload so mede o frescor.
#   3. python -I scripts/predictive/ews2/gerar_payload.py --backtest ... --saida <tmp> --T <T>, com teto de tempo.
#   4. node scripts/predictive/ews2/integracao/validar_pacote.mjs: usa validarPayload/liberacaoValida/
#      LIBERACAO_NOTA_SHA256 do adaptador do Worker (mesma regua), mais 104 emissores e data_observacao = T.
#   5. So com -Publicar: backup do valor atual de ews2:latest, kv key put --remote, releitura e conferencia.
#      Sem -Publicar (padrao) e dry-run: nada e escrito no KV, nem lido.
#
# Fonte de dado: os zips IPE/DFP locais lidos por scripts/predictive/ews2/dados.py (data/cvm e tmp/.../cvm-ipe).
# O ipe_cia_aberta_<ano>.zip de data/cvm e renovado pela VIXRadar-Reconciliacao-CVM (seg 12h00). A idade do zip
# vai para o log; zip com mais de -IpeMaxDias dias reprova (pacote com data nova e dado velho seria mentira).
#
# Exit codes (Task Scheduler): 0 ok | 2 entrada invalida | 3 geracao falhou | 4 validacao reprovou (nada gravado)
#   | 5 kv put falhou | 6 releitura nao confirmou | 7 instancia duplicada | 8 backup do valor atual falhou
#   | 9 conferencia mandou DESLIGAR e a flag foi desligada | 11 publicou mas o registro no livro de previsoes falhou
#   | 12 conferencia nao rodou ou falhou | 13 conferencia mandou desligar e o desligamento da flag falhou
#   | 14 veredito desligar ainda sem confirmacao (so desliga se a rodada anterior, 5+ dias antes, tambem disse desligar)
#
# Uso:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run_vixradar_ews2_pacote.ps1            (dry-run)
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\run_vixradar_ews2_pacote.ps1 -Publicar
# Parametros de teste (scripts/test-ews2-pacote.ps1): -PacotePronto pula a geracao e valida/publica um arquivo
# dado; -KvCli troca o wrangler por um executavel .cmd falso que registra as chamadas.

param(
    [switch]$Publicar,
    [string]$T,
    [string]$Backtest,
    [string]$BacktestSha256 = 'BBAAE5544BCE91DC00B667249BFC4E32BE77F0B05F5E1C4015936E51C7F6DA45',
    [int]$IpeMaxDias = 10,
    [string]$PacotePronto,
    [string]$KvCli,
    [string]$LogDir,
    [string]$BackupRaiz = 'E:\Diretorio\Claude\BACKUPS\operacional\vix-radar\ews2-latest',
    [int]$GerarTimeoutSeg = 1200,
    [int]$DadosTimeoutSeg = 1800,
    [int]$ConferenciaTimeoutSeg = 1800,
    [switch]$SemDownload,
    [switch]$SemConferencia,
    [string]$LivroDir,
    [string]$HistoricoDir,
    [string]$EventosJson,
    [string]$HojeConferencia,
    [double]$ConfirmacaoMinDias = 5,
    [int]$KvTimeoutSeg = 120
)

$ErrorActionPreference = 'Continue'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$ApiDir      = Join-Path $ProjectRoot 'api'
$Ews2Dir     = Join-Path $ProjectRoot 'scripts\predictive\ews2'
$Gerador     = Join-Path $Ews2Dir 'gerar_payload.py'
$Atualizador = Join-Path $Ews2Dir 'atualizar_dados.py'
$Validador   = Join-Path $Ews2Dir 'integracao\validar_pacote.mjs'
$NamespaceId = 'c6805b8d8a7b468e9f854ab4f91fb93a'
$Chave       = 'ews2:latest'
$NEmissores  = 104
if (-not $Backtest) { $Backtest = Join-Path $ProjectRoot 'data\validacao\g0v4\backtest_real_v4_20261018.json' }
if (-not $LogDir)   { $LogDir = Join-Path $ProjectRoot 'logs\ews2-pacote' }

$Carimbo  = Get-Date -Format 'yyyyMMdd-HHmmss'
$TmpDir   = Join-Path 'E:\Diretorio\Claude\tmp\operacional\vix-radar\ews2-pacote' $Carimbo
$BackupDir = Join-Path $BackupRaiz $Carimbo
New-Item -ItemType Directory -Force -Path $LogDir, $TmpDir | Out-Null
$LogFile = Join-Path $LogDir ('ews2-pacote-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))

$script:Res = [ordered]@{ ok = $false; exit = 1; modo = $(if ($Publicar) { 'publicar' } else { 'dry-run' }); T = $null;
    pacote = $null; validacao = $null; gravado = $false; backup = $null; releitura = $null; motivo = $null }

function Write-Log([string]$m) {
    $linha = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    [Console]::WriteLine($linha)
    try { [System.IO.File]::AppendAllText($LogFile, $linha + "`r`n", $Utf8NoBom) } catch { }
}

function Stop-Rotina([int]$Code, [string]$Motivo) {
    $script:Res.exit = $Code
    $script:Res.ok = ($Code -eq 0)
    if ($Motivo) { $script:Res.motivo = $Motivo }
    if ($Code -eq 0) { Write-Log ('FIM: ok exit=0 modo=' + $script:Res.modo) } else { Write-Log ('FIM: FALHA exit=' + $Code + ' motivo=' + $Motivo) }
    $json = ($script:Res | ConvertTo-Json -Depth 6 -Compress)
    Write-Log ('RESULTADO ' + $json)
    if ($script:Mutex) { try { $script:Mutex.ReleaseMutex() } catch { } }
    exit $Code
}

# Executa processo com teto de tempo (KVTIMEOUT1: wrangler sem teto ja travou 26 min). Devolve Code/Out/Err.
function Invoke-ProcessoComTeto([string]$Exe, [string]$Argumentos, [string]$Cwd, [int]$TetoSeg) {
    $base = Join-Path $TmpDir ('proc_' + [System.IO.Path]::GetRandomFileName())
    $outF = $base + '.out'; $errF = $base + '.err'
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $Argumentos -WorkingDirectory $Cwd -NoNewWindow -PassThru -RedirectStandardOutput $outF -RedirectStandardError $errF
    } catch {
        return [pscustomobject]@{ Code = 127; Out = ''; Err = ('falha ao iniciar ' + $Exe + ': ' + $_.Exception.Message) }
    }
    $null = $p.Handle   # PS 5.1: sem o handle em cache o ExitCode volta nulo apos WaitForExit(ms)
    if (-not $p.WaitForExit($TetoSeg * 1000)) {
        & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null
        return [pscustomobject]@{ Code = 124; Out = ''; Err = ('timed out apos ' + $TetoSeg + 's') }
    }
    $out = ''; $err = ''
    if (Test-Path -LiteralPath $outF) { $out = [System.IO.File]::ReadAllText($outF, [System.Text.Encoding]::UTF8) }
    if (Test-Path -LiteralPath $errF) { $err = [System.IO.File]::ReadAllText($errF, [System.Text.Encoding]::UTF8) }
    $err = $err -replace ([string][char]27 + '\[[0-9;]*m'), ''
    Remove-Item -LiteralPath $outF, $errF -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $err }
}

function Get-Cabeca([string]$s, [int]$n) {
    if (-not $s) { return '' }
    $l = @($s -split "`r?`n" | Where-Object { $_.Trim() })
    return (($l | Select-Object -Last $n) -join ' | ')
}

# Chamada ao wrangler (ou ao -KvCli falso dos testes). A chave e conferida AQUI: nada alem de ews2:latest passa.
function Invoke-KvCli([string]$Sub, [string]$Key, [string]$Extra) {
    $permitida = ($Key -eq 'ews2:latest') -or ($Key -eq 'ews2:flag' -and $script:PermiteFlag -eq $true)
    if (-not $permitida) { return [pscustomobject]@{ Code = 99; Out = ''; Err = ('chave recusada pela guarda: ' + $Key) } }
    if ($KvCli) { $exe = $KvCli; $pre = '' }
    else {
        $exe = (Get-Command npx.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
        if (-not $exe) { return [pscustomobject]@{ Code = 127; Out = ''; Err = 'npx.cmd ausente no PATH' } }
        $pre = 'wrangler '
    }
    $a = $pre + 'kv key ' + $Sub + ' "' + $Key + '" ' + $Extra + ' --namespace-id ' + $NamespaceId + ' --remote'
    return Invoke-ProcessoComTeto $exe $a $ApiDir $KvTimeoutSeg
}

function Get-JsonDoTexto([string]$raw) {
    if (-not $raw) { return $null }
    $i = $raw.IndexOf('{')
    if ($i -lt 0) { return $null }
    try { return ($raw.Substring($i) | ConvertFrom-Json) } catch { return $null }
}

$script:PermiteFlag = $false

# Desligamento da flag pela conferencia. Escreve SO ativo=false (conteudo conferido antes do put e na releitura).
function Invoke-FlagDesligar([string]$Motivo, [string]$Relatorio) {
    $script:PermiteFlag = $true
    try {
        $r = Invoke-KvCli 'get' 'ews2:flag' ''
        if ($r.Code -ne 0) { Stop-Rotina 13 ('desligar: leitura da flag falhou: exit=' + $r.Code) }
        New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
        $bk = Join-Path $BackupDir 'ews2_flag_anterior.json'
        [System.IO.File]::WriteAllText($bk, $r.Out, $Utf8NoBom)
        $script:Res.backup_flag = $bk
        $novo = [ordered]@{ ativo = $false; desligado_em = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); origem = 'conferencia_automatica'; motivo = $Motivo; relatorio = $Relatorio }
        $f = Join-Path $TmpDir 'ews2_flag_desligada.json'
        [System.IO.File]::WriteAllText($f, ($novo | ConvertTo-Json -Compress), $Utf8NoBom)
        $conf = Get-JsonDoTexto ([System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8))
        if (-not $conf -or $conf.ativo -ne $false) { Stop-Rotina 13 'desligar: conteudo a gravar nao e ativo=false, recusado' }
        $r = Invoke-KvCli 'put' 'ews2:flag' ('--path "' + $f + '"')
        Write-Log ('FLAG_DESLIGADA: put exit=' + $r.Code + ' ' + (Get-Cabeca $r.Err 2))
        if ($r.Code -ne 0) { Stop-Rotina 13 ('desligar: put da flag falhou: ' + (Get-Cabeca $r.Err 2)) }
        $r = Invoke-KvCli 'get' 'ews2:flag' ''
        $lido = Get-JsonDoTexto $r.Out
        if ($r.Code -ne 0 -or -not $lido -or $lido.ativo -ne $false) { Stop-Rotina 13 'desligar: releitura nao confirmou ativo=false' }
        $script:Res.flag_desligada = $true
    } finally { $script:PermiteFlag = $false }
}

# EVOLUCAO2B: deriva propostas de evolucao do relatorio da conferencia (propor_evolucao.py, sem rede) e, so com
# VIXRADAR_EVOLUCAO_ENVIAR=1 (env User) e -Publicar, envia ao livro do Worker (evolucao_propor, origem rotina). Sem isso
# e simulacao: so registra no log. Nunca muda o exit da rotina nem a flag do EWS: falha aqui so vira linha de log.
function Invoke-PropostasEvolucao([string]$Relatorio, [bool]$Aplicar) {
    try {
        if (-not (Test-Path -LiteralPath $Relatorio)) { Write-Log 'EVOLUCAO: relatorio ausente, nada a propor'; return }
        $r = Invoke-ProcessoComTeto $python ('-I "' + (Join-Path $Ews2Dir 'propor_evolucao.py') + '" --relatorio "' + $Relatorio + '"') $ProjectRoot 120
        $pj = Get-JsonDoTexto $r.Out
        if ($r.Code -ne 0 -or -not $pj -or $pj.ok -ne $true) { Write-Log ('EVOLUCAO: derivacao falhou exit=' + $r.Code + ' ' + (Get-Cabeca $r.Err 2)); return }
        $props = @($pj.propostas | Where-Object { $_ })
        $script:Res.evolucao = [ordered]@{ derivadas = $props.Count; enviadas = 0; modo = 'simulacao' }
        foreach ($p in $props) { Write-Log ('EVOLUCAO_PROPOSTA: ' + $p.titulo + ' | fontes=' + @($p.fontes).Count) }
        $ligado = ([Environment]::GetEnvironmentVariable('VIXRADAR_EVOLUCAO_ENVIAR', 'User') -eq '1') -or ($env:VIXRADAR_EVOLUCAO_ENVIAR -eq '1')
        if (-not ($ligado -and $Aplicar) -or $props.Count -eq 0) { Write-Log ('EVOLUCAO: ' + $props.Count + ' proposta(s) derivada(s), modo simulacao, nada enviado'); return }
        $chave = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
        if (-not $chave) { $chave = $env:ROUTINE_API_KEY }
        if (-not $chave) { Write-Log 'EVOLUCAO: ROUTINE_API_KEY ausente, nada enviado'; return }
        $script:Res.evolucao.modo = 'envio'
        foreach ($p in $props) {
            $corpo = @{ action = 'evolucao_propor'; routine_key = $chave; origem = 'rotina'; proposta = $p } | ConvertTo-Json -Depth 6 -Compress
            try {
                $resp = Invoke-WebRequest -Uri 'https://api.vixradar.com/' -Method Post -UseBasicParsing -TimeoutSec 60 -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($corpo)) -ErrorAction Stop
                $rj = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
                if ($rj.ok) { $script:Res.evolucao.enviadas++ }
                Write-Log ('EVOLUCAO_ENVIO: ok=' + $rj.ok + ' criada=' + $rj.criada + ' estado=' + $rj.estado + ' codigo=' + $rj.codigo)
            } catch { Write-Log ('EVOLUCAO_ENVIO: falhou ' + $_.Exception.Message) }
        }
    } catch { Write-Log ('EVOLUCAO: erro ' + $_.Exception.Message) }
}

# Registro do pacote no livro de previsoes e conferencia contra eventos reais.
function Invoke-Conferencia([bool]$Aplicar) {
    if ($SemConferencia) { Write-Log 'CONFERENCIA: pulada (-SemConferencia)'; return }
    if (-not $python) { Stop-Rotina 12 'python.exe ausente no PATH, conferencia nao rodou' }
    $conf = Join-Path $Ews2Dir 'conferencia.py'
    $livroArg = ''
    if ($LivroDir) { $livroArg = ' --livro "' + $LivroDir + '"' }
    if ($Aplicar) {
        $histArg = ''
        if ($HistoricoDir) { $histArg = ' --historico "' + $HistoricoDir + '"' }
        $r = Invoke-ProcessoComTeto $python ('-I "' + $conf + '" registrar --pacote "' + $caminhoPacote + '"' + $livroArg + $histArg) $ProjectRoot 120
        $rj = Get-JsonDoTexto $r.Out
        $script:Res.livro = $rj
        Write-Log ('CONFERENCIA_REGISTRO: exit=' + $r.Code + ' ' + (Get-Cabeca $r.Out 1))
        if ($r.Code -ne 0 -or -not $rj -or $rj.ok -ne $true) { Stop-Rotina 11 ('pacote publicado, mas o registro no livro de previsoes falhou: ' + (Get-Cabeca $r.Err 2)) }
    }
    $rel = Join-Path $LogDir ('conferencia-' + $Carimbo + '.json')
    $cArgs = '-I "' + $conf + '" conferir --relatorio "' + $rel + '"' + $livroArg
    if (-not $Aplicar) { $cArgs += ' --sem-rede' }
    if ($EventosJson) { $cArgs += ' --eventos-json "' + $EventosJson + '"' }
    if ($HojeConferencia) { $cArgs += ' --hoje ' + $HojeConferencia }
    $ini = Get-Date
    $r = Invoke-ProcessoComTeto $python $cArgs $ProjectRoot $ConferenciaTimeoutSeg
    $cj = Get-JsonDoTexto $r.Out
    $script:Res.conferencia = $cj
    Write-Log ('CONFERENCIA: exit=' + $r.Code + (' {0:N0}s ' -f ((Get-Date) - $ini).TotalSeconds) + (Get-Cabeca $r.Out 1))
    Invoke-PropostasEvolucao $rel $Aplicar
    if ($r.Code -eq 9 -and $cj -and $cj.decisao -eq 'desligar') {
        if (-not $Aplicar) { Write-Log 'CONFERENCIA: veredito DESLIGAR em dry-run, flag nao alterada'; return }
        # Confirmacao: o detector de eventos tem erros nos dois sentidos, entao o veredito precisa se repetir em duas
        # rodadas separadas por ConfirmacaoMinDias. A primeira so avisa (exit 14); a segunda desliga.
        $estadoF = Join-Path $LogDir 'conferencia_estado.json'
        $ant = $null
        if (Test-Path -LiteralPath $estadoF) { $ant = Get-JsonDoTexto ([System.IO.File]::ReadAllText($estadoF, [System.Text.Encoding]::UTF8)) }
        $agora = (Get-Date).ToUniversalTime()
        $desde = $agora
        if ($ant -and $ant.decisao -eq 'desligar' -and $ant.desde) { $desde = [datetime]::Parse($ant.desde, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) }
        $estado = [ordered]@{ decisao = 'desligar'; desde = $desde.ToString('o'); atualizado_em = $agora.ToString('o'); motivo = $cj.motivo }
        [System.IO.File]::WriteAllText($estadoF, ($estado | ConvertTo-Json -Compress), $Utf8NoBom)
        $confirmado = ($ant -and $ant.decisao -eq 'desligar' -and (($agora - $desde).TotalDays -ge $ConfirmacaoMinDias))
        if (-not $confirmado) {
            Write-Log ('CONFERENCIA: veredito DESLIGAR registrado, aguardando confirmacao na proxima rodada (min ' + $ConfirmacaoMinDias + ' dias)')
            Stop-Rotina 14 ('conferencia indicou desligar, aguardando confirmacao na proxima rodada: ' + $cj.motivo)
        }
        Invoke-FlagDesligar $cj.motivo $rel
        Stop-Rotina 9 ('conferencia mandou desligar o EWS 2.0 e a flag foi desligada: ' + $cj.motivo)
    }
    if ($Aplicar -and $r.Code -eq 0 -and $cj) {
        $estadoF = Join-Path $LogDir 'conferencia_estado.json'
        $estado = [ordered]@{ decisao = [string]$cj.decisao; desde = (Get-Date).ToUniversalTime().ToString('o'); atualizado_em = (Get-Date).ToUniversalTime().ToString('o'); motivo = $cj.motivo }
        [System.IO.File]::WriteAllText($estadoF, ($estado | ConvertTo-Json -Compress), $Utf8NoBom)
    }
    if ($r.Code -ne 0) {
        if (-not $Aplicar) { Write-Log 'CONFERENCIA: nao rodou em dry-run (livro vazio ou criterio alterado), nada a fazer'; return }
        Stop-Rotina 12 ('conferencia falhou: ' + (Get-Cabeca $r.Out 1) + ' ' + (Get-Cabeca $r.Err 2))
    }
}

# ---------------------------------------------------------------
Write-Log ('INICIO: ews2-pacote modo=' + $script:Res.modo + ' pid=' + $PID)
$script:Mutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-ews2-pacote')
if (-not $script:Mutex.WaitOne(0)) { $script:Mutex = $null; Stop-Rotina 7 'instancia duplicada' }

$python = (Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$node   = (Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $node) { Stop-Rotina 2 'node.exe ausente no PATH' }

$caminhoPacote = $null
if ($PacotePronto) {
    # Caminho de teste: valida (e, com -Publicar, grava) um pacote ja existente, sem gerar.
    if (-not (Test-Path -LiteralPath $PacotePronto)) { Stop-Rotina 2 ('pacote pronto ausente: ' + $PacotePronto) }
    $caminhoPacote = $PacotePronto
    if (-not $T) { $T = (Get-JsonDoTexto ([System.IO.File]::ReadAllText($PacotePronto, [System.Text.Encoding]::UTF8))).data_observacao }
    $script:Res.T = $T
    Write-Log ('PACOTE_PRONTO: ' + $PacotePronto + ' (geracao pulada)')
} else {
    if (-not $python) { Stop-Rotina 2 'python.exe ausente no PATH' }
    # 1. Backtest de referencia, hash pinado
    if (-not (Test-Path -LiteralPath $Backtest)) { Stop-Rotina 2 ('backtest de referencia ausente: ' + $Backtest) }
    $shaBt = (Get-FileHash -LiteralPath $Backtest -Algorithm SHA256).Hash
    if ($shaBt -ne $BacktestSha256.ToUpperInvariant()) { Stop-Rotina 2 ('sha256 do backtest diverge do pinado: ' + $shaBt) }
    Write-Log ('BACKTEST: ' + $Backtest + ' sha256=' + $shaBt)

    # Frescor do IPE do ano corrente (o zip que a Reconciliacao-CVM renova)
    $ipe = Join-Path $ProjectRoot ('data\cvm\ipe_cia_aberta_{0}.zip' -f (Get-Date).Year)
    if (-not (Test-Path -LiteralPath $ipe)) { Stop-Rotina 2 ('IPE do ano corrente ausente: ' + $ipe) }
    $ipeIdade = ((Get-Date) - (Get-Item -LiteralPath $ipe).LastWriteTime).TotalDays
    Write-Log ('IPE: ' + $ipe + ' modificado ' + (Get-Item -LiteralPath $ipe).LastWriteTime.ToString('yyyy-MM-dd HH:mm') + (' idade={0:N1}d' -f $ipeIdade))
    $script:Res.ipe_idade_dias = [Math]::Round($ipeIdade, 1)
    if ($ipeIdade -gt $IpeMaxDias) { Stop-Rotina 2 ('IPE com {0:N1} dias, acima do teto de {1}: pacote novo sobre dado velho' -f $ipeIdade, $IpeMaxDias) }

    # 2. T = ultimo dia util anterior a hoje, pelo calendario do proprio ews2
    if (-not $T) {
        $py = 'import sys,datetime as dt; sys.path.insert(0, sys.argv[1]); import calendario as C; d=dt.date.today()-dt.timedelta(days=1)' + "`n" + 'while not C.dia_util(d): d-=dt.timedelta(days=1)' + "`n" + 'print(d.isoformat())'
        $pyFile = Join-Path $TmpDir 'calc_T.py'
        [System.IO.File]::WriteAllText($pyFile, $py, $Utf8NoBom)
        $r = Invoke-ProcessoComTeto $python ('-I "' + $pyFile + '" "' + $Ews2Dir + '"') $TmpDir 60
        $T = $r.Out.Trim()
        if ($r.Code -ne 0 -or $T -notmatch '^\d{4}-\d{2}-\d{2}$') { Stop-Rotina 2 ('calculo de T falhou: ' + (Get-Cabeca $r.Err 2)) }
    }
    if ($T -notmatch '^\d{4}-\d{2}-\d{2}$') { Stop-Rotina 2 ('T invalido: ' + $T) }
    $script:Res.T = $T
    Write-Log ('T: ' + $T)

    # 2b. Dados do H5 e do H2 trimestral: ITR, DFP, FCA, COTAHIST do ano e Selic (atualizar_dados.py). Download que
    # falha mantem o arquivo anterior; o que reprova e cotacao ou Selic mais de 5 dias antes de T (exit 2).
    $dArgs = '-I "' + $Atualizador + '" --T ' + $T
    if ($SemDownload) { $dArgs += ' --sem-download' }
    $ini = Get-Date
    $r = Invoke-ProcessoComTeto $python $dArgs $ProjectRoot $DadosTimeoutSeg
    $dj = Get-JsonDoTexto $r.Out
    $script:Res.dados = $dj
    Write-Log ('DADOS: exit=' + $r.Code + (' {0:N0}s ' -f ((Get-Date) - $ini).TotalSeconds) + (Get-Cabeca $r.Out 1))
    if ($r.Code -ne 0 -or -not $dj -or $dj.ok -ne $true) {
        $m = ''; if ($dj -and $dj.motivo) { $m = $dj.motivo } else { $m = Get-Cabeca $r.Err 2 }
        Stop-Rotina 2 ('dados do H5 velhos ou indisponiveis, nada gerado: ' + $m)
    }

    # 3. Geracao
    $caminhoPacote = Join-Path $TmpDir 'ews2_latest.json'
    $env:PYTHONIOENCODING = 'utf-8'
    $ini = Get-Date
    $r = Invoke-ProcessoComTeto $python ('-I "' + $Gerador + '" --backtest "' + $Backtest + '" --saida "' + $caminhoPacote + '" --T ' + $T) $ProjectRoot $GerarTimeoutSeg
    Write-Log ('GERAR: exit=' + $r.Code + (' {0:N0}s' -f ((Get-Date) - $ini).TotalSeconds) + ' stdout=' + (Get-Cabeca $r.Out 1))
    if ($r.Code -ne 0 -or -not (Test-Path -LiteralPath $caminhoPacote)) { Stop-Rotina 3 ('gerar_payload falhou: ' + (Get-Cabeca $r.Err 3)) }
}
$script:Res.pacote = $caminhoPacote
$script:Res.pacote_sha256 = (Get-FileHash -LiteralPath $caminhoPacote -Algorithm SHA256).Hash

# 4. Validacao pela regua do adaptador do Worker
$r = Invoke-ProcessoComTeto $node ('"' + $Validador + '" "' + $caminhoPacote + '" --n ' + $NEmissores + ' --T ' + $T) $TmpDir 60
$v = Get-JsonDoTexto $r.Out
$script:Res.validacao = $v
Write-Log ('VALIDAR: exit=' + $r.Code + ' ' + ($r.Out.Trim()))
if ($r.Code -ne 0 -or -not $v -or $v.ok -ne $true) {
    $erros = ''
    if ($v -and $v.erros) { $erros = (@($v.erros) -join '; ') } else { $erros = Get-Cabeca $r.Err 2 }
    Stop-Rotina 4 ('pacote reprovado, NADA gravado: ' + $erros)
}

if (-not $Publicar) {
    Write-Log ('DRYRUN: pacote valido, SERIA gravado em ' + $Chave + ' (namespace ' + $NamespaceId + '). KV nao foi lido nem escrito.')
    Invoke-Conferencia $false
    Stop-Rotina 0 $null
}

# 5a. Backup do valor atual (rollback = kv key put deste arquivo)
$r = Invoke-KvCli 'get' $Chave ''
if ($r.Code -ne 0) { Stop-Rotina 8 ('leitura do valor atual falhou, nada gravado: exit=' + $r.Code + ' ' + (Get-Cabeca $r.Err 2)) }
$atual = Get-JsonDoTexto $r.Out
if ($atual) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $bk = Join-Path $BackupDir 'ews2_latest_anterior.json'
    [System.IO.File]::WriteAllText($bk, $r.Out.Substring($r.Out.IndexOf('{')), $Utf8NoBom)
    $script:Res.backup = $bk
    Write-Log ('BACKUP: ' + $bk + ' (data_observacao anterior ' + $atual.data_observacao + ')')
} elseif ($r.Out -match 'Value not found') {
    Write-Log 'BACKUP: chave ausente no KV, nada a guardar'
} else {
    Stop-Rotina 8 ('valor atual ilegivel, nada gravado: ' + (Get-Cabeca $r.Out 2))
}

# 5b. Gravacao
$r = Invoke-KvCli 'put' $Chave ('--path "' + $caminhoPacote + '"')
Write-Log ('KV_PUT: exit=' + $r.Code + ' ' + (Get-Cabeca $r.Out 1) + ' ' + (Get-Cabeca $r.Err 2))
if ($r.Code -ne 0) { Stop-Rotina 5 ('kv put falhou: ' + (Get-Cabeca $r.Err 2)) }
$script:Res.gravado = $true

# 5c. Releitura: o que esta no KV e o pacote que validamos?
$esperado = Get-JsonDoTexto ([System.IO.File]::ReadAllText($caminhoPacote, [System.Text.Encoding]::UTF8))
$r = Invoke-KvCli 'get' $Chave ''
$lido = Get-JsonDoTexto $r.Out
$conf = ($r.Code -eq 0 -and $lido -and $lido.gerado_em -eq $esperado.gerado_em -and $lido.data_observacao -eq $esperado.data_observacao -and @($lido.emissores).Count -eq @($esperado.emissores).Count)
$script:Res.releitura = [ordered]@{ exit = $r.Code; confere = [bool]$conf; gerado_em = $(if ($lido) { $lido.gerado_em } else { $null }) }
if (-not $conf) { Stop-Rotina 6 ('gravado mas releitura nao confirmou: exit=' + $r.Code + ' ' + (Get-Cabeca $r.Err 2)) }
Write-Log ('PUBLICADO: ' + $Chave + ' data_observacao=' + $esperado.data_observacao + ' gerado_em=' + $esperado.gerado_em)
Invoke-Conferencia $true
Stop-Rotina 0 $null
