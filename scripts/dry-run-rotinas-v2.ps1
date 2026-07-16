# Dry-run rotina-v2: 1 emissor por tier (SKIP/LIGHT/FULL) via receber_analise
$ErrorActionPreference = 'Stop'

$WorkerUrl = 'https://api.vixradar.com'
$Key = 'mXE26ilVmBUCIUOD9wFCgwDoShWpDOq7IPCUXXu9qGlQ8LO1'
$fail = 0

function Send-Analise($empresa, $setor, $tier, $resultado) {
    $body = @{
        action      = 'receber_analise'
        routine_key = $Key
        empresa     = $empresa
        setor       = $setor
        _matinal    = $false
        provedor    = 'claude-sonnet-routine'
        resultado   = $resultado
    }
    $json = $body | ConvertTo-Json -Depth 12 -Compress
    $resp = Invoke-RestMethod -Uri $WorkerUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $json
    if ($resp.ok -ne $true) {
        Write-Output "FAIL $tier $empresa : $($resp | ConvertTo-Json -Compress)"
        $script:fail++
        return $resp
    }
    Write-Output "PASS $tier $empresa | n_eventos=$($resp.n_eventos) sem_eventos=$($resp.sem_eventos)"
    return $resp
}

Write-Output '=== dry-run rotina-v2 ==='

# SKIP — Eneva
$skip = @{
    empresa             = 'Eneva'
    setor               = 'Energia Elétrica'
    sem_eventos         = $true
    cobertura_nota      = 'Dry-run tier SKIP. CVM: 2 docs na janela (Reunião Administração mai/2026). Sem delta desde última análise 2026-06-19. Motivo: sem_delta_24h.'
    instrumentos_ativos = @('debenture')
    fontes_consultadas  = @(
        @{ rodada = '0'; query = 'source-first Worker listar_plano_rotina'; resultado = '2 docs CVM, 0 novos' }
    )
    eventos             = @()
    _tier               = 'SKIP'
    _rotina_v2          = $true
    _dry_run            = $true
}
Send-Analise 'Eneva' 'Energia Elétrica' 'SKIP' $skip | Out-Null

# LIGHT — Simpar (3 rodadas documentadas; sem evento novo material)
$light = @{
    empresa             = 'Simpar'
    setor               = 'Transportes e Logística'
    sem_eventos         = $true
    cobertura_nota      = 'Dry-run tier LIGHT. 3/3 rodadas: R2 rating (Fitch BB- estável jun/2026 via CVM), R5 crédito (sem novidade), R6 RJ/default (sem novidade). CVM: assembleia jun/2026 já conhecida.'
    instrumentos_ativos = @('debenture')
    fontes_consultadas  = @(
        @{ rodada = '2'; query = '"Simpar" rating downgrade upgrade Fitch Moody after:2026-05-20'; resultado = 'Fitch BB-/AA(bra) estável — doc CVM 2026-06-01' }
        @{ rodada = '5'; query = '"Simpar" crédito mercado Valor Reuters after:2026-05-20'; resultado = 'sem evento material na janela' }
        @{ rodada = '6'; query = '"Simpar" recuperação judicial default after:2026-05-20'; resultado = 'sem novidade' }
    )
    eventos             = @()
    _tier               = 'LIGHT'
    _rotina_v2          = $true
    _dry_run            = $true
}
Send-Analise 'Simpar' 'Transportes e Logística' 'LIGHT' $light | Out-Null

# FULL — Equatorial Energia (7 rodadas; sem evento novo — prova profundidade)
$full = @{
    empresa             = 'Equatorial Energia'
    setor               = 'Energia Elétrica'
    sem_eventos         = $true
    cobertura_nota      = 'Dry-run tier FULL. 7/7 rodadas executadas (R2-R8). CVM: 0 docs na janela. Rating/ANBIMA/resultado/mercado/RJ/research/spread: sem evento material novo desde scan 2026-06-19.'
    instrumentos_ativos = @('debenture')
    fontes_consultadas  = @(
        @{ rodada = '2'; query = '"Equatorial Energia" rating after:2026-05-20'; resultado = 'sem alteração' }
        @{ rodada = '3'; query = '"Equatorial Energia" ANBIMA debenture after:2026-05-20'; resultado = 'sem emissão nova' }
        @{ rodada = '4'; query = '"Equatorial Energia" EBITDA dívida after:2026-05-20'; resultado = 'sem release novo' }
        @{ rodada = '5'; query = '"Equatorial Energia" crédito Valor after:2026-05-20'; resultado = 'sem novidade' }
        @{ rodada = '6'; query = '"Equatorial Energia" default RJ after:2026-05-20'; resultado = 'sem novidade' }
        @{ rodada = '7'; query = '"Equatorial Energia" research XP BTG after:2026-05-20'; resultado = 'sem novidade' }
        @{ rodada = '8'; query = '"Equatorial Energia" debênture spread after:2026-05-20'; resultado = 'sem novidade' }
    )
    eventos             = @()
    _tier               = 'FULL'
    _rotina_v2          = $true
    _dry_run            = $true
}
Send-Analise 'Equatorial Energia' 'Energia Elétrica' 'FULL' $full | Out-Null

# AUDIT — BTG Pactual (recall amostral; 5 rodadas compactas)
$audit = @{
    empresa             = 'BTG Pactual'
    setor               = 'Financeiro'
    sem_eventos         = $true
    cobertura_nota      = 'Dry-run tier AUDIT. 5/5 rodadas (R2,R5,R6,R4b,R7). Recall amostral SKIP promovido. Sem evento material novo.'
    instrumentos_ativos = @('debenture')
    fontes_consultadas  = @(
        @{ rodada = '2'; query = '"BTG Pactual" rating after:2026-05-20'; resultado = 'sem alteracao' }
        @{ rodada = '5'; query = '"BTG Pactual" crédito Valor after:2026-05-20'; resultado = 'sem novidade' }
        @{ rodada = '6'; query = '"BTG Pactual" default RJ after:2026-05-20'; resultado = 'sem novidade' }
        @{ rodada = '4b'; query = '"BTG Pactual" LF emissão banco after:2026-05-20'; resultado = 'sem novidade' }
        @{ rodada = '7'; query = '"BTG Pactual" research XP BTG after:2026-05-20'; resultado = 'sem novidade' }
    )
    eventos             = @()
    _tier               = 'AUDIT'
    _rotina_v2          = $true
    _dry_run            = $true
}
Send-Analise 'BTG Pactual' 'Financeiro' 'AUDIT' $audit | Out-Null

Write-Output "=== resultado: $fail falha(s) ==="
if ($fail -gt 0) { exit 1 }
exit 0