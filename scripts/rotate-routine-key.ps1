# rotate-routine-key.ps1 - Rotacao atomica da ROUTINE_API_KEY nos TRES destinos.
# ASCII puro de proposito: sem caractere nao-ASCII, logo sem exigencia de BOM (regra PS 5.1).
#
# Motivo (ROUTINEKEY-PLAIN1, auditoria 2026-08-08): a chave nunca foi rotacionada desde que
# vazou. A auditoria achou TRES valores distintos em claro no disco, incluindo a chave ativa
# nua em logs/routines/rk.tmp e dois valores commitados em 15647ef.
#
# Por que um script e nao tres comandos soltos: a chave vive em tres lugares e o Worker faz
# comparacao simples (`body.routine_key !== env.ROUTINE_API_KEY`, worker.js ~16365). Nao ha
# lista de chaves nem periodo de graca. Trocar um destino e esquecer outro produz 403 silencioso
# na proxima rotina - exatamente a classe de falha que a auditoria mandou eliminar. Os tres
# destinos sao:
#
#   1. GitHub Actions  -> secrets.ROUTINE_API_KEY, consumido por .github/workflows/scan-emergencia.yml
#   2. Worker          -> wrangler secret put ROUTINE_API_KEY
#   3. Windows local   -> [Environment]::SetEnvironmentVariable(...,'User')
#
# O item 1 e o que quase passou batido: o scan-emergencia roda 23:30 UTC e e o fallback de
# quando o estado principal esta stale. Rotacionar sem ele deixaria justamente a rede de
# seguranca fora do ar, sem alarme.
#
# Ordem deliberada: GitHub primeiro (inerte ate a proxima execucao), Worker depois (a partir
# daqui a chave velha morre), local em seguida. A janela de indisponibilidade e de segundos,
# entre os passos 2 e 3. Rodar fora do horario de rotina.
#
# Uso:
#   1) gh auth login                       (uma vez; fluxo interativo, nao da para automatizar)
#   2) pwsh ./scripts/rotate-routine-key.ps1 -WhatIf     (mostra o plano, nao muda nada)
#   3) pwsh ./scripts/rotate-routine-key.ps1
#
# Rollback: automatico se a validacao final falhar. Manual: rodar de novo com -RestaurarAntiga
# nao existe de proposito - a chave velha vazou, restaurar seria voltar ao problema.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $WorkerName = 'radar-credito-api',
    [string] $Repo       = 'Yan69793/monitoramento-credito-vix-radar',
    [string] $ApiUrl     = 'https://api.vixradar.com',
    [int]    $TamanhoChave = 43
)

$ErrorActionPreference = 'Continue'   # nunca 'Stop': regra global do CLAUDE.md
$ApiDir = Join-Path $PSScriptRoot '..\api'

function Escrever($msg, $cor) {
    if (-not $cor) { $cor = 'Gray' }
    Write-Host ((Get-Date -Format 'HH:mm:ss') + ' ' + $msg) -ForegroundColor $cor
}

function Abortar($msg) {
    Escrever ('ABORTADO: ' + $msg) 'Red'
    exit 1
}

# ---------------------------------------------------------------- portoes
# Todos antes de tocar em qualquer coisa. Um portao que roda no meio da rotacao
# e pior que portao nenhum: aborta com o sistema em estado misto.

Escrever 'Portao 1/4: gh CLI autenticado' 'Cyan'
$null = & gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Abortar 'gh nao autenticado. Rode: gh auth login. Sem isso o secret do GitHub Actions fica com a chave velha e o scan-emergencia (23:30 UTC) quebra silencioso.'
}

Escrever 'Portao 2/4: secret ROUTINE_API_KEY existe no GitHub' 'Cyan'
$secretsGh = & gh secret list --repo $Repo 2>&1 | Out-String
if ($secretsGh -notmatch 'ROUTINE_API_KEY') {
    Abortar ('ROUTINE_API_KEY nao encontrada nos secrets de ' + $Repo + '. Confirme o nome antes de prosseguir.')
}

Escrever 'Portao 3/4: wrangler enxerga o Worker' 'Cyan'
$env:CLOUDFLARE_API_TOKEN = [Environment]::GetEnvironmentVariable('CLOUDFLARE_API_TOKEN', 'User')
if (-not $env:CLOUDFLARE_API_TOKEN) {
    Abortar 'CLOUDFLARE_API_TOKEN ausente do escopo User. (Auditoria 2026-08-08: ela nao esta no escopo Machine, ao contrario do que o CLAUDE.md afirma.)'
}
Push-Location $ApiDir
$secretsCf = & npx --no-install wrangler secret list --name $WorkerName 2>&1 | Out-String
Pop-Location
if ($secretsCf -notmatch 'ROUTINE_API_KEY') {
    Abortar ('ROUTINE_API_KEY nao esta nos secrets do Worker ' + $WorkerName + '.')
}

Escrever 'Portao 4/4: producao saudavel antes de mexer' 'Cyan'
try {
    $health = Invoke-RestMethod -Uri $ApiUrl -TimeoutSec 30
} catch {
    Abortar ('health check nao respondeu: ' + $_.Exception.Message)
}
if (-not $health.ok) {
    Abortar ('health ok:false (versao ' + $health.versao + '). Resolva antes de rotacionar - senao a validacao final vira ambigua.')
}
Escrever ('  producao ok, versao ' + $health.versao) 'Green'

# ---------------------------------------------------------------- chave nova
# RNGCryptoServiceProvider e nao Get-Random: Get-Random usa PRNG nao criptografico.
# Alfabeto sem +/= para a chave passar limpa por JSON, header e linha de comando.

$alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
$bytes = New-Object 'System.Byte[]' $TamanhoChave
$rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
$rng.GetBytes($bytes)
$rng.Dispose()
$sb = New-Object System.Text.StringBuilder
foreach ($b in $bytes) { $null = $sb.Append($alfabeto[$b % $alfabeto.Length]) }
$novaChave = $sb.ToString()

$chaveAntiga = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY', 'User')
if (-not $chaveAntiga) {
    Escrever 'AVISO: ROUTINE_API_KEY ausente no escopo User. Rollback automatico ficara indisponivel.' 'Yellow'
}

# Fingerprint, nunca o valor. O log deste script pode acabar versionado.
function Fp($s) {
    if (-not $s) { return '(vazia)' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
    $sha.Dispose()
    return (($h | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 12)
}

Escrever ''
Escrever ('chave antiga fp=' + (Fp $chaveAntiga) + '   chave nova fp=' + (Fp $novaChave) + ' (' + $TamanhoChave + ' chars)') 'Yellow'

if (-not $PSCmdlet.ShouldProcess('ROUTINE_API_KEY nos 3 destinos', 'rotacionar')) {
    Escrever 'WhatIf: nada foi alterado. Os 4 portoes passaram, a rotacao rodaria agora.' 'Cyan'
    exit 0
}

# ---------------------------------------------------------------- rotacao
# Nenhum arquivo temporario. A primeira versao deste script gravava a chave num
# [System.IO.Path]::GetTempFileName() para alimentar `wrangler secret put` por stdin, o que
# reproduzia em %TEMP% exatamente o problema do rk.tmp que este script existe para encerrar.
# Pior: o Gate 3 aprovou aquela versao, porque o regex procura ROUTINE_API_KEY perto de
# Set-Content e ali a chave estava numa variavel de outro nome. Falso negativo anotado.
#
# `secret bulk` no lugar de `secret put`: bulk recebe JSON por stdin, e o JSON delimita o
# valor com aspas. Com `secret put` a chave vai crua por stdin e qualquer \r\n que o pipe do
# PowerShell acrescente entra no segredo. A comparacao no Worker e `!==` exata (worker.js
# ~16365), entao um \r invisivel no fim daria 403 em toda rotina com os tres destinos
# "corretos" - falha silenciosa cara de diagnosticar.

function Set-SecretWorker([string] $valor) {
    $json = (@{ ROUTINE_API_KEY = $valor } | ConvertTo-Json -Compress)
    Push-Location $ApiDir
    $json | & npx --no-install wrangler secret bulk --name $WorkerName 2>&1 | Out-Null
    $rc = $LASTEXITCODE
    Pop-Location
    return $rc
}

try {
    Escrever 'Passo 1/3: GitHub Actions' 'Cyan'
    $novaChave | & gh secret set ROUTINE_API_KEY --repo $Repo 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Abortar 'gh secret set falhou. Nada foi alterado no Worker nem no local.' }
    Escrever '  ok' 'Green'

    Escrever 'Passo 2/3: Worker (a partir daqui a chave velha esta morta)' 'Cyan'
    $rcWorker = Set-SecretWorker $novaChave
    if ($rcWorker -ne 0) { Abortar 'wrangler secret bulk falhou. GitHub ja tem a chave nova - rode de novo assim que resolver.' }
    Escrever '  ok' 'Green'

    Escrever 'Passo 3/3: variavel de ambiente local (escopo User)' 'Cyan'
    [Environment]::SetEnvironmentVariable('ROUTINE_API_KEY', $novaChave, 'User')
    $env:ROUTINE_API_KEY = $novaChave
    Escrever '  ok (shells ja abertos continuam com a chave velha ate reabrirem)' 'Green'

    # ------------------------------------------------------------ validacao
    # listar_todos_emissores e leitura pura: nao grava estado, nao gasta LLM.
    Escrever 'Validando com chamada autenticada real...' 'Cyan'
    Start-Sleep -Seconds 5   # propagacao do secret no edge
    $corpo = @{ action = 'listar_todos_emissores'; routine_key = $novaChave } | ConvertTo-Json -Compress
    $okValidacao = $false
    for ($i = 1; $i -le 3; $i++) {
        try {
            $r = Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $corpo -ContentType 'application/json' -TimeoutSec 60
            if ($r.ok -ne $false) { $okValidacao = $true; break }
            Escrever ('  tentativa ' + $i + ': resposta ok:false') 'Yellow'
        } catch {
            Escrever ('  tentativa ' + $i + ': ' + $_.Exception.Message) 'Yellow'
        }
        Start-Sleep -Seconds 10
    }

    if (-not $okValidacao) {
        Escrever 'VALIDACAO FALHOU - revertendo Worker e local para a chave antiga' 'Red'
        if ($chaveAntiga) {
            $rcRb = Set-SecretWorker $chaveAntiga
            [Environment]::SetEnvironmentVariable('ROUTINE_API_KEY', $chaveAntiga, 'User')
            $env:ROUTINE_API_KEY = $chaveAntiga
            if ($rcRb -ne 0) {
                Escrever 'ROLLBACK DO WORKER FALHOU. Local voltou para a chave antiga, Worker esta com a nova.' 'Red'
                Escrever 'Sistema em estado misto: toda rotina vai dar 403. Resolva agora, nao amanha.' 'Red'
            } else {
                Escrever 'Rollback feito no Worker e no local. ATENCAO: o GitHub ficou com a chave NOVA.' 'Red'
            }
            # Parenteses obrigatorios: 'texto' + $var como argumento posicional nao concatena
            # em PowerShell, passa multiplos argumentos. A versao anterior desta linha entregava
            # '+' como parametro de cor e estourava dentro do proprio caminho de rollback.
            Escrever ('Rode: gh secret set ROUTINE_API_KEY --repo ' + $Repo + '   com o valor antigo, ou refaca a rotacao inteira.') 'Red'
        } else {
            Escrever 'Sem chave antiga em maos: rollback impossivel. Investigue antes da proxima rotina.' 'Red'
        }
        exit 1
    }

    Escrever ''
    Escrever ('ROTACAO CONCLUIDA. fp da chave em vigor = ' + (Fp $novaChave)) 'Green'
    Escrever 'Proximos passos manuais:' 'Cyan'
    Escrever '  - reabrir qualquer PowerShell aberto (a variavel so entra em shell novo)'
    Escrever '  - conferir a proxima rotina (verificacao async, dom 10:20) na linha FIM: do log'
    Escrever '  - a chave velha continua no historico do git em 15647ef; agora ela nao vale mais nada,'
    Escrever '    o que era o objetivo. Purgar o historico virou opcional, nao urgente.'

} finally {
    # Sem arquivo temporario para limpar, de proposito: a chave nunca toca o disco neste script.
    # A unica copia persistente e o proprio secret, nos tres destinos.
    $novaChave = $null
    $chaveAntiga = $null
}
