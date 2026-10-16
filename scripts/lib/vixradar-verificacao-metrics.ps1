# VERIF-METRICS-ACUM1: ledger cumulativo de consumo da verificacao assincrona.
# PS 5.1, sem chamadas externas. O log FIM real recupera snapshots diarios perdidos.
function Get-VixVerificacaoLogConsumo([string]$LogFile) {
    $total = [int64]0; $unknown = $false; $runs = 0
    if (Test-Path -LiteralPath $LogFile) {
        foreach ($line in (Get-Content -LiteralPath $LogFile -Encoding UTF8)) {
            if ($line -match 'FIM: fila=\d+ .*?\btokens=(\d+)\b') {
                $total += [int64]$Matches[1]; $runs++
                if ($line -match '\btokens_desconhecidos=([1-9]\d*)\b') { $unknown = $true }
            }
        }
    }
    return @{ tokens = $total; desconhecido = $unknown; execucoes = $runs }
}

function Get-VixVerifValor($Obj, [string]$Campo) {
    if ($null -eq $Obj) { return [int64]0 }
    $valor = $null
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Campo)) { $valor = $Obj[$Campo] }
    } elseif ($Obj.PSObject.Properties[$Campo]) {
        $valor = $Obj.$Campo
    }
    if ($null -eq $valor -or ('' + $valor).Trim() -eq '') { return [int64]0 }
    $numero = [int64]0
    if (-not [int64]::TryParse(('' + $valor), [ref]$numero) -or $numero -lt 0) {
        throw ('VERIF_METRICS_INVALIDO: ' + $Campo)
    }
    return $numero
}

function Save-VixVerificacaoMetrics([string]$Path, $Novas, [string]$LogFile, [string]$ExecucaoId, [switch]$DryRun) {
    if (-not $ExecucaoId) { throw 'VERIF_METRICS_SEM_EXECUCAO_ID' }
    if ($DryRun) {
        if (Test-Path -LiteralPath $Path) { throw 'VERIF_DRYRUN_METRICS_COLISAO' }
        $Novas | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
        return
    }
    $nome = 'Local\VixVerifMetrics_' + [regex]::Replace($Path, '[^A-Za-z0-9]', '_')
    $mutex = New-Object System.Threading.Mutex($false, $nome)
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(15000) } catch [System.Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'VERIF_METRICS_MUTEX_TIMEOUT' }
        $anterior = $null
        if (Test-Path -LiteralPath $Path) {
            try { $anterior = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
            catch { throw 'VERIF_METRICS_LEGADO_ILEGIVEL' }
            if ($null -eq $anterior) { throw 'VERIF_METRICS_LEGADO_VAZIO' }
        }
        $ids = @()
        if ($anterior -and $anterior.PSObject.Properties['execucoes_aplicadas']) {
            $ids = @($anterior.execucoes_aplicadas)
        }
        if ($ids -contains $ExecucaoId) { return }
        $log = Get-VixVerificacaoLogConsumo $LogFile
        $anteriorTotal = Get-VixVerifValor $anterior 'tokens_trabalho'
        if ($null -ne $anterior -and -not $anterior.PSObject.Properties['tokens_trabalho']) {
            $anteriorTotal = Get-VixVerifValor $anterior 'tokens_total_est'
        }
        $resgate = [Math]::Max([int64]0, ([int64]$log.tokens - $anteriorTotal))
        $campos = @('total_fila','lotes','reservados','ja_reservados','aprovados','rejeitados',
            'confirmados','erros_parse','refusals','falhas_provider','truncados',
            'pareceres_incompletos','tokens_input','tokens_output','tokens_cache_creation',
            'tokens_cache_read','tokens_cache_codex','tokens_desconhecidos')
        $merged = [ordered]@{ data = $Novas.data; rotina = 'verificacao-async'; dryrun = $false }
        foreach ($campo in $campos) {
            $merged[$campo] = (Get-VixVerifValor $anterior $campo) + (Get-VixVerifValor $Novas $campo)
        }
        $merged['tokens_trabalho'] = $anteriorTotal + $resgate + (Get-VixVerifValor $Novas 'tokens_trabalho')
        $merged['tokens_total_est'] = $merged['tokens_trabalho']
        $merged['tokens_recuperados_log'] = (Get-VixVerifValor $anterior 'tokens_recuperados_log') + $resgate
        $merged['tokens_mensuraveis'] = (-not $log.desconhecido -and
            $merged['tokens_desconhecidos'] -eq 0 -and
            -not ($anterior -and $anterior.PSObject.Properties['tokens_mensuraveis'] -and $anterior.tokens_mensuraveis -eq $false))
        $merged['execucoes_aplicadas'] = @($ids) + @($ExecucaoId)
        $merged['max_tokens_verificacao'] = $Novas.max_tokens_verificacao
        $merged['auth_escalou'] = $Novas.auth_escalou
        $temp = $Path + '.tmp.' + $PID + '.' + [Guid]::NewGuid().ToString('N')
        $json = $merged | ConvertTo-Json -Depth 8
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($temp, $json, $utf8)
        try {
            if (Test-Path -LiteralPath $Path) {
                [IO.File]::Replace($temp, $Path, ($Path + '.prev'))
            } else {
                [IO.File]::Move($temp, $Path)
            }
        } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
