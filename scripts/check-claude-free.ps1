# check-claude-free.ps1 - gate anti-regressao da CLAUDE-FREE-MIGRATION (Fase A, 2026-09-04).
# Garante que nenhum arquivo vivo de scripts/routines volte a invocar o `claude -p` sem passar
# pelo gate de provider (BLOQUEADO_SEM_PROVIDER, exit 86). Nao edita nada. Exit code real.
#
# Contexto: o operador nao tem mais Claude Pro/Max, Claude = plano FREE, PAYG nao autorizado.
# Claude Code deixou de ser infraestrutura operacional. Toda rotina LLM do VIX carrega a lib
# scripts/lib/vixradar-llm-provider.ps1 e sai bloqueada sem provider (none/claude-manual sem
# forca manual / provider de Fase B reservado com motor nao migrado). Este checker e o outro
# lado da mesma regra, no git: reintroduzir chamada a claude sem gate e erro de commit/CI.
#
# Dois modos:
#   -Path a,b,c   arquivos-alvo (pre-commit Gate 8 materializa os blobs EM STAGING e passa os
#                 caminhos das copias + -RootPrefix do diretorio temporario). Cada entrada vira
#                 relpath real via -RootPrefix; sem prefixo, o relpath e o proprio caminho.
#   (sem -Path)   varre em disco o arvore git de scripts/ + routines/ sob -RepoRoot (ou o cwd).
#                 Modo manual/diagnostico. CI roda em diff, pre-commit em staging, os dois sobre
#                 o conjunto ALTERADO, nao sobre a arvore inteira (arquivos legados inalterados
#                 fora da allowlist nao reprovam a mudanca corrente).
#
# Nao escaneia: api/** (Worker, residual documentado, correcao e Fase B), Obsidian datado,
# routines/claude-desktop/** e docs de CCD historicas, .md (docs podem mostrar comando de
# exemplo), backups (*.bak*, *.orig, *.rej). Comentarios sao removidos antes de julgar R1/R2/R3
# (regra vale sobre CODIGO, nao sobre prosa).
#
# Allowlists (por relpath, sempre com /):
#   G (gate obrigatorio): arquivo que invoca claude de verdade (codigo) E prova o gate de
#     provider. R1 exige que o marcador exista; R2 exige a ordem certa no corpo executavel.
#     Arquivo em G que ainda nao invoca claude nao paga nada; se um dia ganhar chamada direta,
#     precisa do marcador tambem.
#   L (legado/obsoleto): arquivo morto por decisao documentada que ainda invoca claude sem
#     gate. REATIVAR exige migrar o provider antes. O checker aceita e nao varre.
#   N (referencia nao-invocante): watcher/registrador/cutover que cita 'claude' apenas em
#     string de descricao, mapa de exit code ou varredura de processo (Get-CimInstance/
#     -match), nunca executa claude. Nao precisa de gate. Se um dia executar claude, sai de N.
#   K (material de chave): unico lugar onde citar a chave paga em codigo. A auth lib define e
#     gateia Get-VixAnthropicApiKey; a provider lib REMOVE a chave do processo no bloqueio
#     (corte); a sonda diagnostica cita porque prova que o corte funciona.
#
# Regras (falha => exit != 0):
#   R1  arquivo que invoca claude (codigo) precisa estar em G (com gate) ou L (legado morto).
#   R2  em G, nenhuma invocacao de claude no CORPO EXECUTAVEL antes do gate. Corpo executavel
#      = depois da ultima definicao de function do arquivo. Invocacao dentro do corpo de uma
#      function e segura por construcao: function so roda quando chamada, e o gate roda no
#      corpo executavel antes de qualquer chamada. Invocacao solta no corpo antes do gate =
#      bypass real.
#   R3  'sk-ant-' / 'VIXRADAR_ANTHROPIC_API_KEY' em codigo so em G/L/N/K. Arquivo vivo fora
#      das allowlists citando chave paga = caminho de escalacao paga reintroduzido.
#      Nota: Get-VixAnthropicApiKey NAO e token restrito. E funcao da auth lib que gateia por
#      dentro (Stop-VixLlmBloqueado quando provider nao permite). Chamada a ela fora da lib e
#      segura porque a propria lib bloqueia 86 antes de tocar na chave. R4 garante o gate.
#   R4  auth lib contem VIXRADAR_LLM_PROVIDER e a saida canonica ($VixLlmBloqueadoExit/86).
#   R5  auth lib contem 'claude-manual' (escalacao automatica para chave paga cortada).
# PowerShell 5.1, ASCII no codigo (comentarios podem ter acento, entao o arquivo tem BOM UTF-8).
# Exit: 0 ok | 1 regra reprovada | 2 erro interno.
param(
    [string]$Path,
    [string]$RootPrefix = '',
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Continue'
$falhas = New-Object System.Collections.Generic.List[string]

$G = @(
    'scripts/run_vixradar_varredura.ps1',
    'scripts/run_vixradar_matinal_claude.ps1',
    'scripts/run_vixradar_noturno_claude.ps1',
    'scripts/run_vixradar_verificacao_async.ps1',
    'scripts/run_vixradar_sentinela.ps1',
    'scripts/run_vixradar_agenda_semanal.ps1',
    'scripts/run_claude_routine.ps1',
    'scripts/probe-claude-auth.ps1',
    'scripts/retry-vixradar.ps1',
    'scripts/lib/vixradar-claude-auth.ps1',
    'scripts/lib/vixradar-ambient-check.ps1'
)
$L = @(
    # run_vixradar_ranking_mensal.ps1: SEO mensal DESCONTINUADA em 18/08/2026 (task nao existe).
    # Ainda chama claude -p sem gate; se algum dia for reativada, migrar provider antes.
    'scripts/run_vixradar_ranking_mensal.ps1',
    # montador de argumentos do claude headless; nao invoca, so monta. Consumido apos gate.
    'scripts/lib/vixradar-runner-args.ps1',
    # test-session-limit-policy.ps1: teste de regressao do incidente 03/09 (FEEDRETRO1 Fase 3),
    # roda so em dev, nunca no scheduler. Cita o valor SIMULADO 'sk-ant-teste' para exercitar o
    # parser de erro de limite de sessao; nao e chave real, nao ha caminho de escalacao. Nao
    # invoca claude. Se um dia subir a citar chave real, sai de L.
    'scripts/test-session-limit-policy.ps1'
)
$N = @(
    # watcher: cita 'claude.exe' so em string de descricao do exit code 2 e em comentario. Nunca executa.
    'scripts/monitor-tasks.ps1',
    # cutover do scheduler: varre processos vivos com -match 'claude -p' para abortar se rotina rodando. Nunca executa.
    'scripts/cutover-motor.ps1',
    # registrador do scheduler: cita Claude em Description de task Szuchmacher. Nunca executa.
    'scripts/register-all-routines-scheduler.ps1'
)
$K = @(
    'scripts/lib/vixradar-claude-auth.ps1',   # define e gateia Get-VixAnthropicApiKey
    'scripts/lib/vixradar-llm-provider.ps1',  # Remove-Item da chave do processo no bloqueio (corte)
    'scripts/probe-claude-auth.ps1',          # diagnostico: prova que o corte funciona
    'scripts/check-claude-free.ps1'           # o proprio regulador enumera os tokens (ver self-skip abaixo)
)
# Este arquivo e o regulador. Ele enumera os tokens e os padroes de invocacao que fiscaliza,
# entao auto-examinar produziria falso positivo inevitavel. Nao se auto-examina.
$Self = 'scripts/check-claude-free.ps1'

$Marcadores = @('BLOQUEADO_SEM_PROVIDER', 'Get-VixLlmProvider', 'Test-VixLlmPermiteClaude', 'Stop-VixLlmBloqueado', 'Get-VixLlmBloqueadoMsg', '$VixLlmBloqueadoExit')
$TokensRestritos = @('sk-ant-', 'VIXRADAR_ANTHROPIC_API_KEY')
$ReInvoca = '\|\s*claude\b|&\s*claude\b|claude\s+(-p|-print|--print|--output-format)|\bclaude\.exe\b'
$ReFunction = '^\s*function\s+[A-Za-z_][A-Za-z0-9_-]*'

function Normalizar-Path([string]$p) {
    return (($p -replace '\\', '/') -replace '^\./', '')
}
function Remove-Comentario([string[]]$linhas) {
    $out = New-Object System.Collections.Generic.List[string]
    $emBloco = $false
    foreach ($ln in $linhas) {
        $t = $ln
        if ($emBloco) {
            $fe = $t.IndexOf('#>')
            if ($fe -lt 0) { continue }
            $t = $t.Substring($fe + 2)
            $emBloco = $false
        }
        $abre = $t.IndexOf('<#')
        while ($abre -ge 0) {
            $fecha = $t.IndexOf('#>', $abre + 2)
            if ($fecha -ge 0) {
                $t = $t.Remove($abre, $fecha - $abre + 2)
            } else {
                $t = $t.Substring(0, $abre)
                $emBloco = $true
                break
            }
            $abre = $t.IndexOf('<#')
        }
        $h = $t.IndexOf('#')
        if ($h -ge 0) { $t = $t.Substring(0, $h) }
        $out.Add($t)
    }
    return $out.ToArray()
}
function Get-Indices([string[]]$linhasStripped, [string]$regex) {
    $indices = New-Object System.Collections.Generic.List[int]
    $n = 0
    foreach ($linha in $linhasStripped) {
        $n++
        if ($linha -match $regex) { $indices.Add($n) }
    }
    return $indices
}

function Teste-Arquivo([string]$caminhoAbs, [string]$relpath) {
    $rel = (Normalizar-Path $relpath)
    # Fora do escopo deste checker (ver cabecalho)
    if ($rel -like 'api/*' -or $rel -like 'Obsidian*' -or $rel -like 'routines/claude-desktop/*') { return }
    if ($rel -like '*.bak*' -or $rel -like '*.orig' -or $rel -like '*.rej') { return }
    if ($rel -notlike '*.ps1') { return }
    if ($rel -eq $Self) { return }  # regulador nao se auto-examina
    if (-not (Test-Path -LiteralPath $caminhoAbs)) { return }

    $raw = ''
    try { $raw = Get-Content -LiteralPath $caminhoAbs -Raw -Encoding UTF8 -ErrorAction Stop } catch { $raw = '' }
    if (-not $raw) { return }
    $stripped = Remove-Comentario ($raw -split "`r?`n")
    $txtLimpo = ($stripped -join "`n")
    $invoca = [bool]($txtLimpo -match $ReInvoca)

    # auth lib: invariantes R4 + R5 valem sempre que o arquivo existir em disco
    if ($rel -eq 'scripts/lib/vixradar-claude-auth.ps1') {
        if (-not $raw.Contains('VIXRADAR_LLM_PROVIDER')) { $falhas.Add("R4 $rel - auth lib sem VIXRADAR_LLM_PROVIDER (gate de provider nao dot-source)") }
        if (-not ($raw.Contains('$VixLlmBloqueadoExit') -or $raw.Contains('exit 86'))) { $falhas.Add("R4 $rel - auth lib sem saida canonica de bloqueio (exit 86)") }
        if (-not $raw.Contains('claude-manual')) { $falhas.Add("R5 $rel - auth lib sem 'claude-manual' (escalacao automatica paga nao cortada)") }
    }

    $naAllowlist = ($G -contains $rel) -or ($L -contains $rel) -or ($N -contains $rel) -or ($K -contains $rel)

    # R3: token de chave paga em codigo fora das allowlists
    if (-not $naAllowlist) {
        foreach ($tk in $TokensRestritos) {
            if ($txtLimpo.Contains($tk)) { $falhas.Add("R3 $rel - token de chave paga ('$tk') fora das allowlists. Caminho de escalacao paga nao pode voltar.") }
        }
    }

    if (-not $invoca) { return }
    if ($L -contains $rel) { return }  # legado morto, aceito e documentado
    if ($N -contains $rel) { return }  # referencia nao-invocante (string/processo); nunca executa claude

    if ($G -notcontains $rel) {
        $falhas.Add("R1 $rel - invoca claude (codigo) sem estar em G (gate obrigatorio) nem L (legado). Carregar a lib de provider e bloquear sem provider, ou mover para allowlist so com decisao documentada.")
        return
    }

    # R1: marcador de gate precisa existir em codigo
    $idxMarc = Get-Indices $stripped ('BLOQUEADO_SEM_PROVIDER|Get-VixLlmProvider|Test-VixLlmPermiteClaude|Stop-VixLlmBloqueado|Get-VixLlmBloqueadoMsg|\$VixLlmBloqueadoExit')
    if ($idxMarc.Count -eq 0) {
        $falhas.Add("R1 $rel - invoca claude (codigo) e nao tem marcador de gate (BLOQUEADO_SEM_PROVIDER/VixLlm). Gate tem que vir antes de qualquer claude.")
        return
    }

    # R2: nenhuma invocacao no corpo executavel ANTES do gate.
    # Corpo executavel comeca apos a ultima definicao de function. Invocacao em linha
    # anterior ao gate que esteja DENTRO do corpo executavel (linha > ultima function)
    # executa antes do gate = bypass. Invocacao em linha anterior ao gate dentro do corpo
    # de uma function e segura: a function so roda quando chamada, e o gate roda antes.
    $m = $idxMarc[0]
    $lastFn = 0
    $fnLines = Get-Indices $stripped $ReFunction
    if ($fnLines.Count -gt 0) { $lastFn = $fnLines[$fnLines.Count - 1] }
    $invos = Get-Indices $stripped $ReInvoca
    foreach ($i in $invos) {
        if ($i -lt $m -and $i -gt $lastFn) {
            $falhas.Add("R2 $rel - invocacao de claude na linha $i no corpo executavel, antes do gate na linha $m. Gate tem que ser o primeiro passo do corpo executavel.")
        }
    }
}

# ---- coleta de arquivos ----
if ($Path) {
    foreach ($p in ($Path -split ',')) {
        $p = $p.Trim()
        if (-not $p) { continue }
        $relp = $p
        if ($RootPrefix -and $p.StartsWith($RootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relp = $p.Substring($RootPrefix.Length)
        }
        Teste-Arquivo $p $relp
    }
} else {
    $root = $RepoRoot
    if (-not $root) { $root = (Get-Location).Path }
    foreach ($sub in @('scripts', 'routines')) {
        $dir = Join-Path $root $sub
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($arq in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
            $relp = $arq.FullName.Substring($root.Length).TrimStart('\', '/')
            Teste-Arquivo $arq.FullName $relp
        }
    }
}

if ($falhas.Count -gt 0) {
    Write-Host 'CLAUDE-FREE-MIGRATION - gate anti-regressao REPROVADO:'
    foreach ($f in $falhas) { Write-Host ('  ' + $f) }
    Write-Host 'Regra: claude -p so pode rodar sob provider habilitado. Sem provider, rotina sai 86.'
    Write-Host 'Corrigir: dot-source scripts/lib/vixradar-llm-provider.ps1 e bloquear antes de qualquer auth/claude (ver run_vixradar_varredura.ps1).'
    exit 1
}
exit 0
