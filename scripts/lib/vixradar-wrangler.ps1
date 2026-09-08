# vixradar-wrangler.ps1 - classificacao de falha do CLI wrangler (KV remoto).
# Offline, pura, ASCII. Usada por export-historico e reconciliacao-cvm para decidir quando
# uma falha de kv key get/put e transitoria (retry) ou determinista (auth/ausente).
# NAO faz rede, NAO le credencial, NAO loga segredo.
function Get-VixWranglerFalhaClase([string]$Stderr) {
    $t = '' + $Stderr
    # auth primeiro: o corpo completo de um 401/403 tambem traz 'Failed to fetch', e a
    # decisao de credencial tem precedencia sobre retry.
    if ($t -match '(?i)\b401\b|\b403\b|Unauthorized|Forbidden|Authentication|permission') { return 'auth' }
    if ($t -match '(?i)failed to fetch|timed?[ -]?out|econnreset|econnrefused|network|http 429|http 5\d\d|too many requests|rate limit|temporary') { return 'transitorio' }
    if ($t -match '(?i)not found|key does not exist|no such key|\b404\b') { return 'ausente' }
    return 'outro'
}
function Test-VixWranglerFalhaTransitoria([string]$Stderr) {
    return ((Get-VixWranglerFalhaClase $Stderr) -eq 'transitorio')
}
