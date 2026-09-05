# test-openrouter-contratos.ps1 - Fase B D1, testes offline POR CONTRATO das 3 rotinas wired.
# 2026-09-05. Nao toca rede, nao toca provider, nao toca scheduler. Extrai as funcoes de parse
# REAIS de cada rotina por AST e as exercita com fixtures do contrato que o adapter OpenRouter
# alimenta. Fixtures ASCII para rodar igual em PS 5.1 (sem BOM) e pwsh 7.
#
# O desempacotamento do envelope (jsonLine -> .result -> textOut) e transcrito dos blocos
# reais: run_vixradar_verificacao_async.ps1 L237-242, run_vixradar_agenda_semanal.ps1 L158-162,
# run_vixradar_sentinela.ps1 L584-593. Sao 8 linhas identicas nas 3 e o motor validou o caminho
# completo com o canario real em 2026-09-04/05 (logs/routines/vixradar-matinal_20260905.log).
#
# Fail-closed: fixture de falha do adapter (Linhas = 'OPENROUTER_FALHA_COD=...') deve produzir
# parse vazio/nulo => item preservado na fila/backlog, nunca falso sucesso.
$ErrorActionPreference = 'Continue'
$fail = 0
$pass = 0
$script:LogCalls = New-Object System.Collections.Generic.List[string]

function Assert-True([bool]$cond, [string]$nome) {
    if ($cond) { $script:pass++ ; Write-Host ('PASS: ' + $nome) }
    else { $script:fail++ ; Write-Host ('FAIL: ' + $nome) }
}

# Mock do Write-Log: captura para assert, sem tocar disco (LogDir/LogFile nao existem no teste).
function Write-Log([string]$msg) { [void]$script:LogCalls.Add($msg) }

# Extrai o texto das funcoes pedidas de um arquivo e devolve como array de definicoes.
# O Invoke-Expression roda no escopo RAIZ do teste (nao dentro de function), porque funcao
# definida por Invoke-Expression dentro de function e descartada ao sair do escopo dela.
function Get-RotinaFuncDefs([string]$Path, [string[]]$Names) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw ('parse de ' + $Path + ' falhou: ' + $errors[0].Message) }
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $out = @()
    foreach ($name in $Names) {
        $f = $defs | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $f) { throw ('funcao ' + $name + ' nao encontrada em ' + $Path) }
        $out += $f.Extent.Text
    }
    return ,$out
}

$VerifPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_verificacao_async.ps1'
$AgendaPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_agenda_semanal.ps1'
$SentPath = 'E:\Diretorio\Claude\Monitoramento de Credito\scripts\run_vixradar_sentinela.ps1'

foreach ($_def in (Get-RotinaFuncDefs $VerifPath @('Get-BalancedJson', 'Get-VeredictosArray'))) { Invoke-Expression $_def }
foreach ($_def in (Get-RotinaFuncDefs $AgendaPath @('Get-BalancedJson', 'Get-CalendarioArray'))) { Invoke-Expression $_def }
foreach ($_def in (Get-RotinaFuncDefs $SentPath @('Get-ParsedResultadosSentinela', 'Get-NomeNormalizado'))) { Invoke-Expression $_def }

# --- Bloco de desempacotamento do envelope, identico nas 3 rotinas ----------------------------
function Unpack-Envelope($raw) {
    # Espelha a rotina: linha que abre com '{', ultima, vira $jsonLine; .result substitui $raw.
    $textOut = @($raw)
    $jsonLine = @($raw) | Where-Object { ('' + $_).TrimStart().StartsWith('{') } | Select-Object -Last 1
    if ($jsonLine) {
        $json = $jsonLine | ConvertFrom-Json
        if ($null -ne $json.result) { $textOut = @(('' + $json.result) -split "`n") }
    }
    return ,$textOut
}

# Fixture do envelope exatamente no formato do adapter (ConvertTo-VixOpenRouterEnvelope):
# uma linha JSON com .result, .is_error, .model, .stop_reason e .usage.
$envelopeVerif = '{"result":"```json\n[\n  {\"veredicto\":\"CORRIGIR\",\"confianca\":0.94,\"motivo\":\"Fato confirmado em fonte primaria.\"},\n  {\"veredicto\":\"CONFIRMAR\",\"confianca\":0.88,\"motivo\":\"Valor confere com a fonte citada.\"}\n]\n```\n[Fonte 1](https://fonte1.example.com/r) [Fonte 2](https://fonte2.example.com/x)","is_error":false,"model":"deepseek/deepseek-v4-flash-0731","stop_reason":"end_turn","usage":{"input_tokens":20000,"output_tokens":512,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000}}'

Write-Host '== Contrato verificacao_async: array JSON de veredictos =='
$textOutV = Unpack-Envelope $envelopeVerif
$verd = Get-VeredictosArray $textOutV 2
Assert-True ($null -ne $verd -and @($verd).Count -eq 2) 'V1: envelope -> .result -> 2 veredictos parseados (fence + markdown apos o JSON)'
Assert-True ($null -ne $verd -and ('' + $verd[0].veredicto) -eq 'CORRIGIR') 'V2: veredicto[0].veredicto = CORRIGIR'
Assert-True ($null -ne $verd -and ('' + $verd[1].veredicto) -eq 'CONFIRMAR') 'V3: veredicto[1].veredicto = CONFIRMAR'

$textoPlano = '[{"veredicto":"REPROVAR","confianca":0.7,"motivo":"Sem fonte para a tese."}]'
$verd1 = Get-VeredictosArray @($textoPlano) 1
Assert-True ($null -ne $verd1 -and @($verd1).Count -eq 1 -and ('' + $verd1[0].veredicto) -eq 'REPROVAR') 'V4: array puro sem fence parseia'

$trunc = '[{"veredicto":"A"},{"veredicto":"B"},{"veredicto":"C"}]'
$script:LogCalls.Clear()
$verdT = Get-VeredictosArray @($trunc) 2
$avisoTrunc = ($script:LogCalls | Where-Object { $_ -like 'AVISO: modelo retornou 3 veredictos*' } | Select-Object -First 1)
Assert-True ($null -ne $verdT -and @($verdT).Count -eq 2) 'V5: excesso truncado para o esperado (2)'
Assert-True ($null -ne $avisoTrunc) 'V6: truncamento registra AVISO no log'

$verdCurto = Get-VeredictosArray @('[{"veredicto":"A"}]') 2
Assert-True ($null -eq $verdCurto) 'V7: contagem menor que o esperado => null (itens ficam na fila)'

# Robustez do Get-BalancedJson: ']' dentro de string (markdown/citacao) nao fecha o array cedo.
$comColcheteEmString = '[{"cobertura_nota":"texto com [citacao] e ] no meio"},{"cobertura_nota":"fim"}]'
$verdC = Get-VeredictosArray @($comColcheteEmString) 2
Assert-True ($null -ne $verdC -and @($verdC).Count -eq 2) 'V8: varredura balanceada ignora ] dentro de string'

# Fail-closed: falha do adapter devolve Linhas NAO-JSON; parse => null, itens nao confirmados.
$textOutFalha = Unpack-Envelope @('OPENROUTER_FALHA_COD=1')
Assert-True (@($textOutFalha).Count -eq 1 -and ('' + $textOutFalha[0]).StartsWith('OPENROUTER_FALHA_COD')) 'V9: falha do adapter preserva linha de erro (sem falso envelope)'
$verdFail = Get-VeredictosArray $textOutFalha 2
Assert-True ($null -eq $verdFail) 'V10: falha do adapter => parse null (fail-closed, itens ficam na fila)'

Write-Host '== Contrato agenda_semanal: array JSON de calendario =='
$envelopeAgenda = '{"result":"```json\n[\n  {\"empresa\":\"BRASKEM\",\"periodo\":\"2026-09\",\"data_prevista\":\"2026-10-24\",\"horario\":\"apos_fechamento\",\"status\":\"agendado\",\"fonte\":\"https://ri.braskem.com.br/resultados\",\"url_fonte_primaria\":\"https://ri.braskem.com.br/resultados\",\"fonte_secundaria\":\"moneytimes.com.br\"},\n  {\"empresa\":\"PETROBRAS\",\"periodo\":\"2026-09\",\"data_prevista\":\"2026-10-30\",\"horario\":\"apos_fechamento\",\"status\":\"agendado\",\"fonte\":\"https://ri.petrobras.com.br\",\"url_fonte_primaria\":\"https://ri.petrobras.com.br\"}\n]\n```","is_error":false,"model":"deepseek/deepseek-v4-flash-0731","stop_reason":"end_turn","usage":{"input_tokens":18000,"output_tokens":400,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}'
$textOutA = Unpack-Envelope $envelopeAgenda
$cal = Get-CalendarioArray $textOutA
Assert-True ($null -ne $cal -and @($cal).Count -eq 2) 'A1: envelope -> .result -> 2 itens de calendario parseados'
Assert-True ($null -ne $cal -and ('' + $cal[0].empresa) -eq 'BRASKEM' -and ('' + $cal[0].data_prevista) -eq '2026-10-24') 'A2: item[0].empresa/.data_prevista corretos'
Assert-True ($null -ne $cal -and ('' + $cal[1].empresa) -eq 'PETROBRAS') 'A3: item[1].empresa correto'

# Markdown de fontes DEPOIS do array (lista de links) nao corrompe a extracao.
$calMd = Get-CalendarioArray @('[{"empresa":"BRASKEM","data_prevista":"2026-10-24"}]' , '[ri](https://ri.braskem.com.br) [moneytimes](https://moneytimes.com.br/x)')
Assert-True ($null -ne $calMd -and @($calMd).Count -eq 1 -and ('' + $calMd[0].empresa) -eq 'BRASKEM') 'A4: links markdown apos o JSON nao corrompem o parse'

$calFail = Get-CalendarioArray @('OPENROUTER_FALHA_COD=1')
Assert-True ($null -eq $calFail -or @($calFail).Count -eq 0) 'A5: falha do adapter => parse vazio (lote preservado)'

Write-Host '== Contrato sentinela: protocolo textual RESULTADO| =='
$envelopeSent = '{"result":"RESULTADO|Petrobras|{\"classificacao_geral\":\"OK\",\"sem_eventos\":true,\"cobertura_nota\":\"sem fato novo desde 2026-08-30\",\"eventos\":[],\"fontes_consultadas\":[]}\nRESULTADO|Vale|{\"classificacao_geral\":\"CRITICO\",\"sem_eventos\":false,\"cobertura_nota\":\"fato novo em 2026-09-03\",\"eventos\":[{\"tipo\":\"imprensa\"}],\"fontes_consultadas\":[{\"query\":\"Vale setembro 2026\"}]}\nLOTE_RESUMO|buscas=7\nANOTA|registro de apoio para a trilha","is_error":false,"model":"deepseek/deepseek-v4-flash-0731","stop_reason":"end_turn","usage":{"input_tokens":15000,"output_tokens":900,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}'
$textOutS = Unpack-Envelope $envelopeSent
$script:LogCalls.Clear()
$parsedS = Get-ParsedResultadosSentinela $textOutS
Assert-True ($parsedS.Map.Count -eq 2) 'S1: 2 RESULTADO| viram 2 entradas no map'
Assert-True ($parsedS.Map.ContainsKey('Petrobras') -and $parsedS.Map.ContainsKey('Vale')) 'S2: chaves normalizadas sem acento/case (Get-NomeNormalizado real)'
Assert-True ((('' + $parsedS.Map['Vale'].classificacao_geral) -eq 'CRITICO') -and ($parsedS.Map['Vale'].sem_eventos -eq $false)) 'S3: objeto JSON do RESULTADO| preserva campos'
Assert-True ($parsedS.Buscas -eq 7) 'S4: LOTE_RESUMO|buscas=N lido'
$anota = ($script:LogCalls | Where-Object { $_ -like 'ANOTA:*' } | Select-Object -First 1)
Assert-True ($null -ne $anota) 'S5: ANOTA| registrado no log'

# Linha fora do protocolo nao entra nem quebra.
$parsedLixo = Get-ParsedResultadosSentinela @('texto solto sem protocolo', '---', '')
Assert-True ($parsedLixo.Map.Count -eq 0 -and $parsedLixo.Buscas -eq -1) 'S6: linhas fora do protocolo ignoradas'

# Fail-closed sentinela: falha do adapter => map vazio (caller preserva no backlog).
$parsedFail = Get-ParsedResultadosSentinela @('OPENROUTER_FALHA_COD=1')
Assert-True ($parsedFail.Map.Count -eq 0) 'S7: falha do adapter => map vazio (backlog preservado)'

# RESULTADO com JSON invalido (regex casa por ter { e }, mas ConvertFrom-Json falha) => fora do
# map, com AVISO, sem lancar. Linha que nem fecha chaves nao casa o regex e cai como fora do
# protocolo (contrato S6), nao gera AVISO.
$script:LogCalls.Clear()
$parsedInv = Get-ParsedResultadosSentinela @('RESULTADO|Empresa|{"a":}', 'LOTE_RESUMO|buscas=1')
Assert-True ($parsedInv.Map.Count -eq 0 -and $parsedInv.Buscas -eq 1) 'S8: RESULTADO com JSON invalido sai do map sem quebrar'
Assert-True (@($script:LogCalls | Where-Object { $_ -like 'AVISO: RESULTADO com JSON invalido*' }).Count -eq 1) 'S9: JSON invalido registra AVISO'

Write-Host ''
Write-Host ('RESULTADO: ' + $pass + ' passaram, ' + $fail + ' falharam')
if ($fail -gt 0) { Write-Host 'EXIT: 1 (contrato quebrado)'; exit 1 }
Write-Host 'EXIT: 0'
exit 0
