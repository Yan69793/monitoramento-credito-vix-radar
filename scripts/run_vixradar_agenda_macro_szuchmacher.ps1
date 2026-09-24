param(
    [switch]$ForceClaude
)

# run_vixradar_agenda_macro_szuchmacher.ps1 - Rotina Szuchmacher agenda/macro (sexta 07:07 BRT).
#
# AGENDAMACRO-MIGRACAO1 (2026-09-18): migrada do caminho so-Claude (entrada no catalogo de
# run_claude_routine.ps1 + SKILL.md em ~/.claude/scheduled-tasks) para o motor
# provedor-agnostico, no mesmo desenho de run_vixradar_agenda_semanal.ps1: este driver faz
# TODA a I/O (backup, gravacao do agenda-data.json, validacao local) e o LLM apenas pesquisa,
# pelo adapter OpenRouter (scripts/lib/vixradar-openrouter.ps1, server tools web_search e
# web_fetch). O caminho Claude antigo parava com exit 86 sob VIXRADAR_LLM_PROVIDER=openrouter
# (Set-VixClaudeAuthEnv -> Stop-VixLlmBloqueado), sem entregar janela nova desde 04/09/2026.
#
# ASCII puro de proposito: .ps1 com nao-ASCII exige BOM UTF-8 no powershell.exe 5.1, e o gate
# de runtime do repo (scripts/preflight-and-run.ps1) recusa TODAS as rotinas agendadas se o
# parse deste arquivo falhar. O texto acentuado que vai para o site (bloco meta) e lido do
# proprio agenda-data.json vivo, nao escrito aqui.
#
# NUNCA publica: o Passo 6 do SKILL.md exige aprovacao explicita do operador para deploy.

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ProjectRoot = 'E:\Diretorio\Claude\Monitoramento de Credito'
$SiteRoot    = 'E:\Diretorio\Claude\FREQUENTE\Site\site-producao'
$LogDir      = Join-Path $ProjectRoot 'logs\routines'
$DateTag     = Get-Date -Format 'yyyyMMdd'
$LogFile     = Join-Path $LogDir ('agenda-macro-szuchmacher_' + $DateTag + '.log')
$DataFile    = Join-Path $SiteRoot 'agenda-data.json'
$BackupDir   = Join-Path $SiteRoot 'backups\agenda'

# Passo 1 do SKILL.md: janela = hoje ate hoje + 7 dias, fuso local (America/Sao_Paulo).
$Inicio = Get-Date -Format 'yyyy-MM-dd'
$Fim    = (Get-Date).AddDays(7).ToString('yyyy-MM-dd')
$Stamp  = Get-Date -Format 'yyyyMMdd'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log([string]$msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Write-Host $line
    for ($i = 1; $i -le 8; $i++) {
        try {
            Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
            return
        } catch {
            if ($i -eq 8) { Write-Host "FALHA Write-Log (Add-Content, $i tentativas): $($_.Exception.Message)" }
            else { Start-Sleep -Milliseconds ([Math]::Min(200 * [Math]::Pow(2, $i - 1), 2000)) }
        }
    }
}

# Mesmo varredor balanceado de run_vixradar_agenda_semanal.ps1: robusto contra o modelo
# envolver a resposta em cerca e anexar texto/links depois do array.
function Get-BalancedJson([string]$scan) {
    $start = $scan.IndexOf('[')
    $startObj = $scan.IndexOf('{')
    if ($start -lt 0 -or ($startObj -ge 0 -and $startObj -lt $start)) { $start = $startObj }
    if ($start -lt 0) { return $null }
    $depth = 0; $inStr = $false; $esc = $false
    for ($k = $start; $k -lt $scan.Length; $k++) {
        $ch = [string]$scan[$k]
        if ($esc) { $esc = $false; continue }
        if ($ch -eq '\') { $esc = $true; continue }
        if ($ch -eq '"') { $inStr = -not $inStr; continue }
        if ($inStr) { continue }
        if ($ch -eq '[' -or $ch -eq '{') { $depth++ }
        elseif ($ch -eq ']' -or $ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $scan.Substring($start, $k - $start + 1) }
        }
    }
    return $null
}

function Get-EventosArray($outputLines) {
    $texto = ($outputLines -join "`n").Trim()
    $candidatos = New-Object System.Collections.ArrayList
    $fence = [regex]::Match($texto, '```(?:json)?\s*([\s\S]*?)```')
    if ($fence.Success) { [void]$candidatos.Add($fence.Groups[1].Value) }
    [void]$candidatos.Add($texto)
    foreach ($cand in $candidatos) {
        # O modelo costuma narrar o raciocinio antes de responder: procura do ULTIMO '[' para o
        # primeiro e aceita o primeiro array que parseia como lista de objetos com campo 'data'.
        $pos = @()
        $idx = $cand.IndexOf('[')
        while ($idx -ge 0 -and $pos.Count -lt 40) { $pos += $idx; $idx = $cand.IndexOf('[', $idx + 1) }
        if ($pos.Count -gt 0) { [array]::Reverse($pos) }
        foreach ($p in $pos) {
            $bruto = Get-BalancedJson $cand.Substring($p)
            if (-not $bruto) { continue }
            try { $parsed = $bruto | ConvertFrom-Json } catch { continue }
            $arr = @($parsed)
            # Envelope: as vezes devolve {"eventos":[...]} em vez do array puro pedido.
            if ($arr.Count -eq 1 -and -not $arr[0].data) {
                foreach ($nome in @('eventos', 'events', 'itens', 'items', 'agenda', 'calendario')) {
                    $prop = $arr[0].PSObject.Properties[$nome]
                    if ($prop) {
                        $interno = @($prop.Value)
                        if ($interno.Count -gt 0 -and $interno[0].data) { $arr = $interno }
                    }
                }
            }
            if ($arr.Count -gt 0 -and $arr[0].data) { return ,$arr }
        }
    }
    return $null
}

function Test-VixFonteData {
    # Confere se a data do evento aparece na pagina oficial que o proprio evento declara.
    # Nao prova atribuicao nem substitui curadoria, mas mata data inventada: medido em
    # 18/09/2026 o modelo escreveu "Beige Book 24/09 confirmado pelo Fed", e o Fed publica
    # 02/09 e 14/10. Aceita as formas em que calendario oficial costuma escrever a data.
    param(
        [string]$Data,
        [string]$Url,
        [int]$TimeoutSec = 20
    )
    $res = [ordered]@{ Ok = $false; Inconclusivo = $false; Onde = ''; Motivo = '' }
    if ([string]::IsNullOrWhiteSpace($Url) -or $Url -notmatch '^https?://') {
        $res.Motivo = 'fonte_url ausente ou invalida'
        return [PSCustomObject]$res
    }
    if ($Data -notmatch '^\d{4}-\d{2}-\d{2}$') {
        $res.Motivo = 'data fora do formato YYYY-MM-DD'
        return [PSCustomObject]$res
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        # Cabecalhos de navegador: medido em 18/09/2026, o IBGE devolve 403 para requisicao sem
        # eles, e 403 nao e prova de que o evento seja falso.
        $hdrs = @{
            'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
            'Accept-Language' = 'pt-BR,pt;q=0.9,en;q=0.8'
        }
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -Headers $hdrs -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
        $txt = '' + $resp.Content
    } catch {
        # Pagina bloqueada, fora do ar ou lenta nao prova invencao. Fica inconclusiva e marcada
        # no arquivo, para a curadoria conferir a mao, em vez de derrubar evento verdadeiro.
        $res.Inconclusivo = $true
        $res.Motivo = 'a pagina nao respondeu (' + $_.Exception.Message + ')'
        return [PSCustomObject]$res
    }
    $txt = [System.Text.RegularExpressions.Regex]::Replace($txt, '<[^>]+>', ' ')
    $txt = [System.Net.WebUtility]::HtmlDecode($txt)
    $txt = [System.Text.RegularExpressions.Regex]::Replace($txt, '\s+', ' ')
    $txt = $txt.ToLowerInvariant()
    $d = [datetime]::ParseExact($Data, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    # Mes de marco aceita c-cedilha sem escrever o caractere neste arquivo ASCII.
    $mesPt = @('janeiro', 'fevereiro', 'mar\p{L}o', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro')[$d.Month - 1]
    $mesEn = @('january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december')[$d.Month - 1]
    $curtoEn = @('jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec')[$d.Month - 1]
    $ano = $d.Year
    $m2 = ('{0:00}' -f $d.Month)
    $d2 = ('{0:00}' -f $d.Day)
    # O (?![0-9]) impede casar o dia 2 quando a pagina traz o dia 24: sem ele, "september 2"
    # casa dentro de "september 24" e o gate daria falso positivo.
    $padroes = [ordered]@{
        'iso'        = ('{0}-{1}-{2}(?![0-9])' -f $ano, $m2, $d2)
        'isoBarra'   = ('{0}/{1}/{2}(?![0-9])' -f $ano, $m2, $d2)
        'brBarra'    = ('{0}/{1}/{2}(?![0-9])' -f $d2, $m2, $ano)
        'brPonto'    = ('{0}\.{1}\.{2}(?![0-9])' -f $d2, $m2, $ano)
        'ptExtenso'  = ('(^|[^0-9])' + $d2 + '\s+de\s+' + $mesPt)
        'ptExtenso1' = ('(^|[^0-9])' + $d.Day + '\s+de\s+' + $mesPt)
        'enMesDia'   = ($mesEn + '\s+' + $d2 + '(?![0-9])')
        'enMesDia1'  = ($mesEn + '\s+' + $d.Day + '(?![0-9])')
        'enDiaMes'   = ('(^|[^0-9])' + $d2 + '\s+' + $mesEn)
        'enCurto'    = ($curtoEn + '\.?\s+' + $d2 + '(?![0-9])')
    }
    foreach ($k in $padroes.Keys) {
        if ($txt -match $padroes[$k]) {
            $res.Ok = $true
            $res.Onde = $k
            return [PSCustomObject]$res
        }
    }
    # A data nao apareceu. Antes de acusar invencao, medir se a pagina expoe datas. Calendario
    # oficial lista uma data por mes, entao exigir varios dias do mesmo mes reprovaria pagina
    # que e calendario de verdade. Contar data de qualquer mes resolve os dois formatos, e
    # pagina que nao expoe data nenhuma e hub ou JavaScript, onde a checagem fica inconclusiva.
    # Nao conseguir provar nao e prova de que o evento seja falso.
    $rxData = '\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}(?![0-9])|\b\d{1,2}\s+de\s+(janeiro|fevereiro|mar\p{L}o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)|(?<![0-9])\d{2}/\d{2}/\d{4}(?![0-9])|(?<![0-9])\d{4}-\d{2}-\d{2}(?![0-9])'
    $datasNaPagina = ([regex]::Matches($txt, $rxData)).Count
    if ($datasNaPagina -ge 4) {
        $res.Motivo = 'a pagina expoe ' + $datasNaPagina + ' datas e a data do evento nao esta entre elas'
    } else {
        $res.Inconclusivo = $true
        $res.Motivo = 'a pagina respondeu mas expoe apenas ' + $datasNaPagina + ' data(s) (hub ou JavaScript), checagem inconclusiva'
    }
    return [PSCustomObject]$res
}

# CORTE DA DEPENDENCIA DO CLAUDE (18/09/2026). A lib de auth do Claude nao e carregada aqui.
# Medido: este driver nao chama nenhuma funcao dela, e Get-VixLlmProvider /
# Test-VixLlmProviderPermiteRotina vem da lib neutra, que o ambient-check carrega abaixo.
# Manter o dot-source obrigava uma rotina migrada a exigir a lib do Claude viva para subir.
. (Join-Path $PSScriptRoot 'lib\vixradar-ambient-check.ps1')
# Adapter OpenRouter e opcional na lib; ausencia nao derruba o carregamento, mas o gate abaixo
# recusa a rotina quando o provider e 'openrouter' sem adapter.
if (Test-Path (Join-Path $PSScriptRoot 'lib\vixradar-openrouter.ps1')) {
    . (Join-Path $PSScriptRoot 'lib\vixradar-openrouter.ps1')
    $script:VixLibOpenRouterOk = $true
} else {
    $script:VixLibOpenRouterOk = $false
}
Assert-VixLibFunctions @('Assert-VixLibFunctions', 'Get-VixLlmProvider', 'Test-VixLlmProviderPermiteRotina')

# GATE provedor-agnostico. Nenhum claude e invocado neste caminho: a pesquisa vai pelo
# adapter OpenRouter. Provider diferente de 'openrouter' para a rotina com exit 86.
$script:VixUsaOpenRouter = (Test-VixUsaLlmAdapterHttp)
$__adapterOk = $script:VixLibOpenRouterOk -and
    ($null -ne (Get-Command 'Invoke-VixOpenRouterLote' -ErrorAction SilentlyContinue)) -and
    ($null -ne (Get-Command 'Test-VixOpenRouterPronto' -ErrorAction SilentlyContinue))
if (-not (Test-VixLlmProviderPermiteRotina -ForceClaude:$ForceClaude -OpenRouterAdapterHabilitado:$__adapterOk)) {
    Write-Log (Get-VixLlmBloqueadoMsg 'run_vixradar_agenda_macro_szuchmacher.ps1')
    exit $VixLlmBloqueadoExit
}
if (-not $script:VixUsaOpenRouter) {
    Write-Log ('ERRO FATAL: este driver so opera sob provider openrouter (motor provedor-agnostico); provider efetivo = ' + (Get-VixLlmProvider))
    exit $VixLlmBloqueadoExit
}
if (-not $__adapterOk) {
    Write-Log 'ERRO FATAL: adapter OpenRouter ausente ou incompleto (scripts/lib/vixradar-openrouter.ps1) - provider openrouter sem adapter = bloqueio'
    exit $VixLlmBloqueadoExit
}

$__mutex = New-Object System.Threading.Mutex($false, 'Global\vixradar-agenda-macro-szuchmacher')
if (-not $__mutex.WaitOne(0)) {
    Write-Log 'ABORT: outra instancia da agenda macro ja esta em execucao (mutex ocupado) - saindo limpo em 0 tokens'
    exit 0
}

$inicioIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
Write-Log ('INICIO: atualizar-agenda-macro-szuchmacher | janela=' + $Inicio + '..' + $Fim + ' | provider=openrouter | motor=adapter-http')
Write-Log ('AUTH_MODO: ' + (Get-VixLlmEndpointDescricao) + ' (adapter HTTP, sem claude, sem auth Anthropic). busca_web=' + (Test-VixLlmEndpointTemBusca))
Write-Log 'PROVE_NAO_CLAUDE: nenhuma CLI de agente foi invocada nesta execucao - a pesquisa vai pelo adapter HTTP OpenRouter (gate Test-VixLlmProviderPermiteRotina)'

$exitCode = 0
try {

# Passo 3 do SKILL.md: backup do arquivo vivo ANTES de qualquer escrita.
$temArquivoVivo = Test-Path -LiteralPath $DataFile
$backupFile = Join-Path $BackupDir ('agenda-data-backup-' + $Stamp + '.json')
if ($temArquivoVivo) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    if (Test-Path -LiteralPath $backupFile) {
        Write-Log ('Backup: ' + $backupFile + ' ja existe - preservado (backup do dia nao e sobrescrito)')
    } else {
        Copy-Item -LiteralPath $DataFile -Destination $backupFile -Force
        if (-not (Test-Path -LiteralPath $backupFile) -or ((Get-Item -LiteralPath $backupFile).Length -eq 0)) {
            Write-Log 'ERRO FATAL: backup vazio ou ausente. Sem backup = pare (Passo 3 do SKILL.md).'
            exit 1
        }
        Write-Log ('Backup: ' + $backupFile + ' (' + (Get-Item -LiteralPath $backupFile).Length + ' B)')
    }
    try {
        $metaFonte = (Get-Content -LiteralPath $DataFile -Raw -Encoding UTF8 | ConvertFrom-Json).meta
    } catch {
        $metaFonte = $null
        Write-Log ('AVISO: nao consegui ler o bloco meta do arquivo vivo (' + $_.Exception.Message + ') - usando meta minimo.')
    }
} else {
    $metaFonte = $null
    Write-Log 'AVISO: agenda-data.json nao existe (primeira execucao), sem backup'
}

# Passo 2 do SKILL.md: pesquisa em fontes oficiais pelo adapter OpenRouter.
# Mapa de dias da janela, sem acento (este arquivo e ASCII por design). Tira do modelo a
# tarefa de calcular o dia da semana, que foi onde ele errou em 18/09/2026 ao emitir
# "Boletim Focus" em duas sextas.
$__nomesDia = @('domingo','segunda','terca','quarta','quinta','sexta','sabado')
$__mapaDias = @()
for ($__i = 0; $__i -le 7; $__i++) {
    $__d = (Get-Date).Date.AddDays($__i)
    $__mapaDias += ($__d.ToString('yyyy-MM-dd') + '=' + $__nomesDia[[int]$__d.DayOfWeek])
}
$__mapaDiasTexto = ($__mapaDias -join ', ')
$promptTexto = @"
Voce mantem o calendario macroeconomico semanal publicado em szuchmacher.com.br.

Busque eventos macroeconomicos PROGRAMADOS para a janela de $Inicio a $Fim (7 dias, fuso America/Sao_Paulo).

Fontes oficiais, por prioridade:
- Brasil: BCB (Boletim Focus, COPOM), IBGE (calendario de divulgacoes)
- EUA: BLS (CPI, PPI, Nonfarm Payrolls), ISM, S&P Global PMI, Census Bureau, DoL, NY Fed, Federal Reserve (FOMC)
- Europa: ECB, BoE. Asia: BoJ, NBS China.

Regras:
- Apenas eventos com DATA e FONTE PRIMARIA confirmadas dentro da janela. Nunca antecipar resultado.
- Boletim Focus = toda segunda-feira 08:25 BRT. Somente segunda: nao emita Focus em outro dia.
- Dia da semana de cada data da janela, ja calculado. Use este mapa e nao recalcule: $__mapaDiasTexto
- Nao emita evento cuja data caia em dia incoerente com a regra do proprio evento.
- fonte_url e obrigatoria em todo evento: a URL da pagina oficial que sustenta a data. A rotina
  baixa essa pagina e marca o evento como conferido ou nao conferido para a curadoria. O minimo
  de 5 eventos continua valendo, entao nao deixe de incluir evento confirmado por duvida na URL.
- Converter horarios de EUA, Europa e Asia para BRT (America/Sao_Paulo).
- Minimo 5 eventos. O campo evento_en e obrigatorio em todos.
- Textos em portugues com acentuacao correta; descricao de 1 a 2 linhas.
- Nao narre o processo de busca nem escreva raciocinio: entregue apenas o array JSON final.

Responda SOMENTE com um array JSON, um objeto por evento, em ordem cronologica. Nenhum texto antes ou depois do JSON. O array JSON e o objeto raiz da resposta: nao envolva em {"eventos": [...]} nem em cerca de codigo. Schema exato de cada objeto:

[
  {
    "data": "YYYY-MM-DD",
    "hora_brt": "HH:MM",
    "regiao": "BR",
    "evento": "Nome em portugues",
    "evento_en": "Name in English",
    "descricao": "Descricao em portugues",
    "descricao_en": "Description in English",
    "fonte": "BCB",
    "fonte_url": "https://pagina-oficial-exata-onde-a-data-aparece",
    "relevancia": "alta"
  }
]
"@

$promptPath = Join-Path $LogDir ('agendamacro_prompt_' + $DateTag + '.txt')
Set-Content -Path $promptPath -Value $promptTexto -Encoding UTF8
Write-Log ('Prompt: ' + $promptPath + ' (' + $promptTexto.Length + ' chars)')

$__orResp = Invoke-VixOpenRouterLote -PromptPath $promptPath -Tier 'FULL'
if ([int]$__orResp.ExitCode -ne 0) {
    Write-Log ('ERRO: lote OpenRouter falhou (' + $__orResp.Msg + ')')
    $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Log ('FIM: atualizar-agenda-macro-szuchmacher | status=ERRO_ADAPTER | janela=' + $Inicio + '..' + $Fim)
    Write-Log ('ROTINA_RESUMO|agenda-macro-szuchmacher|local|' + $inicioIso + '|' + $fimIso + '|FALHA|0|1|0|')
    exit 1
}
Write-Log ('OR_OK: modelo=' + $__orResp.Modelo + ' intentos=' + $__orResp.Intentos + ' fallback=' + ('' + $__orResp.FallbackUsado).ToLower() + ' trabalho_tokens=' + $__orResp.Tokens)

# O adapter devolve o envelope do CLI numa linha JSON unica ({result, model, stop_reason,
# usage}). Mesmo tratamento de run_vixradar_agenda_semanal.ps1: o texto util esta em .result.
$textOut = @($__orResp.Linhas)
try {
    $jsonLine = @($__orResp.Linhas) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
    if ($jsonLine) {
        $envCli = $jsonLine | ConvertFrom-Json
        if ($null -ne $envCli.result) {
            $textOut = @(('' + $envCli.result) -split "`n")
            Write-Log ('Envelope: stop_reason=' + $envCli.stop_reason + ' in=' + $envCli.usage.input_tokens + ' out=' + $envCli.usage.output_tokens + ' cache_read=' + $envCli.usage.cache_read_input_tokens)
        }
    }
} catch {
    Write-Log ('AVISO: parse do envelope JSON do adapter falhou (' + $_.Exception.Message + ') - usando a linha crua')
}

# Texto util do modelo em disco (auditoria): e dele que sai o agenda-data.json.
$rawPath = Join-Path $LogDir ('agendamacro_raw_' + $DateTag + '.txt')
($textOut -join "`n") | Set-Content -Path $rawPath -Encoding UTF8
Write-Log ('Resposta do modelo: ' + $rawPath + ' (' + (($textOut -join "`n").Length) + ' chars)')

$itens = Get-EventosArray $textOut
if (-not $itens -or @($itens).Count -eq 0) {
    $bruto = (($textOut -join ' | '))
    if ($bruto.Length -gt 500) { $bruto = $bruto.Substring(0, 500) }
    Write-Log ('ERRO: adapter nao devolveu array JSON de eventos. Bruto: ' + $bruto)
    $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Log ('FIM: atualizar-agenda-macro-szuchmacher | status=ERRO_PARSE | janela=' + $Inicio + '..' + $Fim)
    Write-Log ('ROTINA_RESUMO|agenda-macro-szuchmacher|local|' + $inicioIso + '|' + $fimIso + '|FALHA|0|1|0|')
    exit 1
}
Write-Log ('Adapter devolveu ' + @($itens).Count + ' item(ns).')

$eventos = New-Object System.Collections.ArrayList
$descartados = 0
$foraDaJanela = 0
$descartadosDia = 0

# REGRA DE DIA, validacao determinista. Regra semanal conhecida exige dia da semana
# especifico, e o gate nao pode depender de o modelo ter obedecido o prompt: medido em
# 18/09/2026, "Boletim Focus" saiu em 18/09 e 25/09 (ambas sextas) com a regra escrita no
# prompt e no SKILL.md:29, e nenhuma validacao pegou. Evento que viola a regra e descartado
# com rastro no log, e a contagem minima do Passo 5 continua valendo.
$__regraDia = @(
    @{ Padrao = 'focus'; Dia = [System.DayOfWeek]::Monday; Rotulo = 'segunda-feira' }
)
foreach ($item in $itens) {
    $data      = ('' + $item.data).Trim()
    $evento    = ('' + $item.evento).Trim()
    $eventoEn  = ('' + $item.evento_en).Trim()
    if (-not $data -or -not $evento -or -not $eventoEn) {
        $itemJson = ($item | ConvertTo-Json -Compress -Depth 4)
        if (('' + $itemJson).Length -gt 200) { $itemJson = ('' + $itemJson).Substring(0, 200) }
        Write-Log ('DESCARTE: item sem data/evento/evento_en preenchidos (data="' + $data + '" evento_en_presente=' + ([bool]$eventoEn) + ') item=' + $itemJson)
        $descartados++
        continue
    }
    if ($data -lt $Inicio -or $data -gt $Fim) {
        Write-Log ('AVISO: evento fora da janela ' + $Inicio + '..' + $Fim + ' - ' + $data + ' ' + $evento)
        $foraDaJanela++
    }
    $__diaOk = $true
    foreach ($__r in $__regraDia) {
        if ($evento -match $__r.Padrao -or $eventoEn -match $__r.Padrao) {
            $__dow = $null
            try {
                $__dow = ([datetime]::ParseExact($data, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)).DayOfWeek
            } catch { }
            if ($null -ne $__dow -and $__dow -ne $__r.Dia) {
                Write-Log ('DESCARTE_DIA: "' + $evento + '" em ' + $data + ' cai em ' + ('' + $__dow) + '; a regra exige ' + $__r.Rotulo + ' - descartado antes de gravar')
                $descartadosDia++
                $__diaOk = $false
            }
            break
        }
    }
    if (-not $__diaOk) { continue }
    $evt = [ordered]@{
        data         = $data
        hora_brt     = ('' + $item.hora_brt).Trim()
        regiao       = ('' + $item.regiao).Trim()
        evento       = $evento
        evento_en    = $eventoEn
        descricao    = ('' + $item.descricao).Trim()
        descricao_en = ('' + $item.descricao_en).Trim()
        fonte        = ('' + $item.fonte).Trim()
        fonte_url    = ('' + $item.fonte_url).Trim()
        fonte_conferida = $false
        relevancia   = ('' + $item.relevancia).Trim()
    }
    [void]$eventos.Add([PSCustomObject]$evt)
}

# VERIFICACAO DE FONTE: a data de cada evento tem de aparecer na pagina oficial que o proprio
# evento declara. E o que sobra de protecao contra data inventada depois das checagens de forma.
$descartadosFonte = 0
$naoVerificaveis = 0
$confirmados = New-Object System.Collections.ArrayList
foreach ($ev in $eventos) {
    $cf = Test-VixFonteData -Data $ev.data -Url $ev.fonte_url
    if ($cf.Ok) {
        $ev.fonte_conferida = $true
        Write-Log ('FONTE_OK: ' + $ev.data + ' ' + $ev.evento + ' (forma ' + $cf.Onde + ' em ' + $ev.fonte_url + ')')
        [void]$confirmados.Add($ev)
    } elseif ($cf.Inconclusivo) {
        $naoVerificaveis++
        Write-Log ('FONTE_NAO_VERIFICAVEL: ' + $ev.data + ' ' + $ev.evento + ' - ' + $cf.Motivo + ' (' + $ev.fonte_url + ')')
        [void]$confirmados.Add($ev)
    } else {
        Write-Log ('DESCARTE_FONTE: "' + $ev.evento + '" em ' + $ev.data + ' nao confirma em ' + $ev.fonte_url + ' - ' + $cf.Motivo)
        $descartadosFonte++
    }
}
$eventos = $confirmados

$nEventos = @($eventos).Count
Write-Log ('Eventos validos: ' + $nEventos + ' (descartados=' + $descartados + ', fora_da_janela=' + $foraDaJanela + ', descartados_dia=' + $descartadosDia + ', descartados_fonte=' + $descartadosFonte + ')')
if ($naoVerificaveis -gt 0) {
    Write-Log ('AVISO PARA A CURADORIA: ' + $naoVerificaveis + ' evento(s) com fonte nao verificavel por maquina (fonte_conferida=false no agenda-data.json). Confira contra a fonte antes de publicar.')
}

# Passo 5 do SKILL.md: validacao ANTES de gravar. Arquivo vivo nunca recebe agenda invalida.
$falhas = 0
if ($nEventos -lt 5) {
    Write-Log ('ERRO VALIDACAO: menos de 5 eventos (' + $nEventos + ')')
    $falhas++
}
foreach ($ev in $eventos) {
    if (-not $ev.evento_en) {
        Write-Log ('ERRO VALIDACAO: evento_en ausente em "' + $ev.evento + '"')
        $falhas++
    }
}
if ($falhas -gt 0) {
    Write-Log 'ERRO VALIDACAO: agenda invalida. O agenda-data.json vivo NAO foi alterado (backup do dia preservado).'
    $fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Log ('FIM: atualizar-agenda-macro-szuchmacher | status=ERRO_VALIDACAO | janela=' + $Inicio + '..' + $Fim)
    Write-Log ('ROTINA_RESUMO|agenda-macro-szuchmacher|local|' + $inicioIso + '|' + $fimIso + '|FALHA|' + $nEventos + '|1|0|')
    exit 1
}

# Passo 4 do SKILL.md: gerar o JSON. O bloco meta vem do arquivo vivo para nao duplicar
# texto acentuado neste .ps1 ASCII; version acompanha sempre a janela nova.
$meta = [ordered]@{
    version    = $Inicio
    curator    = 'Szuchmacher Consultoria'
    idiomas    = @('pt-BR', 'en')
}
if ($metaFonte) {
    if ($metaFonte.curator) { $meta.curator = '' + $metaFonte.curator }
    if ($metaFonte.fontes_primarias) { $meta.fontes_primarias = @($metaFonte.fontes_primarias) }
    if ($metaFonte.disciplina) { $meta.disciplina = '' + $metaFonte.disciplina }
    if ($metaFonte.disciplina_en) { $meta.disciplina_en = '' + $metaFonte.disciplina_en }
    if ($metaFonte.idiomas) { $meta.idiomas = @($metaFonte.idiomas) }
    Write-Log 'Meta: bloco meta do agenda-data.json vivo reaproveitado (curadoria preservada).'
} else {
    $meta.fontes_primarias = @('BCB', 'IBGE', 'BLS', 'ISM', 'Census Bureau', 'DoL', 'S&P Global PMI')
    Write-Log 'Meta: arquivo vivo sem meta legivel - usando lista minima de fontes.'
}

$agendaObj = [ordered]@{
    meta    = $meta
    gerado  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    janela  = [ordered]@{ inicio = $Inicio; fim = $Fim }
    eventos = @($eventos)
}

$jsonContent = $agendaObj | ConvertTo-Json -Depth 16
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($DataFile, $jsonContent, $utf8NoBom)
Write-Log ('Gravou: ' + $DataFile + ' (' + (Get-Item -LiteralPath $DataFile).Length + ' B)')

# Releitura do arquivo gravado: prova de que o disco tem o que a validacao aprovou.
$jsonCheck = $null
try {
    $jsonCheck = Get-Content -LiteralPath $DataFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Log ('ERRO VALIDACAO: releitura do arquivo gravado falhou - ' + $_.Exception.Message)
    $exitCode = 1
}
if ($jsonCheck) {
    $nDisco = @($jsonCheck.eventos).Count
    if ($nDisco -lt 5) {
        Write-Log ('ERRO VALIDACAO: releitura do disco tem ' + $nDisco + ' evento(s) (minimo 5)')
        $exitCode = 1
    }
    if ('' + $jsonCheck.janela.inicio -ne $Inicio -or '' + $jsonCheck.janela.fim -ne $Fim) {
        Write-Log ('ERRO VALIDACAO: janela no disco (' + $jsonCheck.janela.inicio + '..' + $jsonCheck.janela.fim + ') difere da calculada (' + $Inicio + '..' + $Fim + ')')
        $exitCode = 1
    }
    if ($exitCode -ne 0) {
        Write-Log 'ERRO VALIDACAO: o arquivo gravado nao passou na releitura. Restaure do backup do dia antes de publicar.'
    } else {
        Write-Log ('Validacao OK: ' + $nDisco + ' eventos no disco, janela ' + $jsonCheck.janela.inicio + ' -> ' + $jsonCheck.janela.fim + '.')
    }
}

} catch {
    Write-Log ('ERRO FATAL: ' + $_.Exception.Message)
    $exitCode = 1
}

# Passo 6 do SKILL.md: o deploy exige aprovacao explicita do operador. Esta rotina nao publica.
Write-Log 'Deploy NAO executado: publicar o site exige aprovacao explicita do operador (Passo 6 do SKILL.md).'
Write-Log 'PROVE_NAO_PUBLICOU: nenhum passo de publicacao foi executado neste caminho - I/O local apenas.'

$fimIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$statusTxt = if ($exitCode -eq 0) { 'OK' } else { 'FALHA' }
Write-Log ('FIM: atualizar-agenda-macro-szuchmacher | status=' + $statusTxt + ' | janela=' + $Inicio + '..' + $Fim + ' | eventos=' + $nEventos)
Write-Log ('ROTINA_RESUMO|agenda-macro-szuchmacher|local|' + $inicioIso + '|' + $fimIso + '|' + $statusTxt + '|' + $nEventos + '|' + $(if ($exitCode -eq 0) { 0 } else { 1 }) + '|0|')

exit $exitCode
