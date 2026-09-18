$ErrorActionPreference = 'Continue'
# PS 5.1: a API responde Content-Type application/json SEM charset, e Invoke-RestMethod
# decodifica como Latin-1 nesses casos, corrompendo nomes acentuados (medido 17/09:
# 'Oncoclinicas' chegava como code units 195,173 = mojibake, e 7 dos 45 deferidos
# apareciam como 'nao cadastrados' quando estavam - falso negativo por encoding).
# Caminho unico: Invoke-WebRequest + decode UTF-8 explicito do RawContentStream.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Invoke-ApiVixUtf8 {
    param([hashtable]$Body)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Compress))
    $resp = Invoke-WebRequest -Uri 'https://api.vixradar.com/' -Method Post -TimeoutSec 60 -ContentType 'application/json; charset=utf-8' -Body $bytes -UseBasicParsing
    $rawText = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    return ($rawText | ConvertFrom-Json)
}

$k = [Environment]::GetEnvironmentVariable('ROUTINE_API_KEY','User')

# 45 emissores deferidos do log da noturna 18:05
$deferidos = @(
  'Marfrig','Braskem','Oncoclínicas','Oi','Raízen','Light','CSN','Aegea Saneamento',
  'Dasa','Hapvida','Cosan','MRV Engenharia','Azul','Eneva','SLC Agrícola',
  'EcoRodovias','CCR','ISA Energia','Vibra Energia','Natura &Co','CEMIG',
  'Bradesco','Nexa Resources','Brisanet','JBS','Even Construtora','Brava Energia',
  'Cyrela','Totvs','Unidas','TIM Brasil','Sanepar','Petrobras','Rede D''Or',
  'Grupo Mateus','Multiplan','Cogna Educação','LWSA','Vivo (Telefônica Brasil)',
  'Cury Construtora','Itaú Unibanco','Compass Gás e Energia','CBA','Klabin','Minerva Foods'
)

# Mapeia setor por empresa (do log da noturna 16/09 e do plano)
# Vou primeiro listar todos os emissores para ter o setor de cada um
$todos_map = @{}
$rTodos = $null
try { $rTodos = Invoke-ApiVixUtf8 @{ action = 'listar_todos_emissores'; routine_key = $k } } catch {}
if ($null -ne $rTodos -and $rTodos.emissores) {
    foreach ($e in $rTodos.emissores) { $todos_map['' + $e.nome] = $e }
} else {
    Write-Host 'ERRO: resposta de listar_todos_emissores sem emissores - abortando' -ForegroundColor Red
    exit 10
}

# API shape measure (17/09 21:2x): objetos de 'listar_todos_emissores' trazem a
# propriedade 'nome', NAO 'empresa'. Usar $e.empresa caia em NullArrayIndex.
# Mapa do plano noturno: la os objetos trazem 'empresa' (shape diferente do listar_todos).
$plano_map = @{}
$rPlano = $null
try { $rPlano = Invoke-ApiVixUtf8 @{ action = 'listar_plano_rotina'; routine_key = $k; modo = 'noturno' } } catch {}
if ($null -ne $rPlano -and $rPlano.emissores) {
    foreach ($e in $rPlano.emissores) { $plano_map['' + $e.empresa] = $e }
} else {
    Write-Host 'ERRO: resposta de listar_plano_rotina sem emissores - abortando' -ForegroundColor Red
    exit 11
}

# Relatorio por empresa
$out = @()
foreach ($nome in $deferidos) {
    $row = [ordered]@{
        empresa = $nome
        status_no_ledger_16_09 = 'DEFERIDO'
        presente_em_listar_todos_emissores_agora = ''
        tier_atual = ''
        motivo_atual = ''
        dados_para_analise_disponivel = ''
        receber_analise_elegivel = ''
        classificacao = ''
        justificativa = ''
    }
    # listar_todos_emissores
    if ($todos_map.ContainsKey($nome)) {
        $row.presente_em_listar_todos_emissores_agora = 'sim'
        # tier: listar_todos_emissores so traz nome+setor (probe de shape 18/09);
        # o tier real vive no plano noturno. Ler de la, nao do mapa de cadastro.
        if ($plano_map.ContainsKey($nome)) {
            $row.tier_atual = $plano_map[$nome].tier
        } else {
            $row.tier_atual = '(fora do plano noturno)'
        }
        # plano noturno
        if ($plano_map.ContainsKey($nome)) {
            $row.motivo_atual = ($plano_map[$nome].motivos | Select-Object -First 1)
        } else {
            $row.motivo_atual = '(no plano: nao)'
        }
    } else {
        $row.presente_em_listar_todos_emissores_agora = 'nao'
    }

    # dados_para_analise: precisa do setor (vou pegar do plano se la estiver, senao de listar_todos)
    $setor = ''
    if ($plano_map.ContainsKey($nome)) { $setor = $plano_map[$nome].setor }
    elseif ($todos_map.ContainsKey($nome)) { $setor = $todos_map[$nome].setor }
    if ($setor) {
        try {
            $d = Invoke-ApiVixUtf8 @{ action = 'dados_para_analise'; routine_key = $k; empresa = $nome; setor = $setor }
            if ($d.ok -eq $true) {
                $row.dados_para_analise_disponivel = 'sim'
            } else {
                $row.dados_para_analise_disponivel = 'nao (' + $d.erro + ')'
            }
        } catch {
            $row.dados_para_analise_disponivel = 'nao (HTTP ' + $_.Exception.Response.StatusCode.value__ + ')'
        }
    } else {
        $row.dados_para_analise_disponivel = 'nao (sem setor - nao cadastrado)'
    }

    # receber_analise elegivel: precisa estar em listar_todos_emissores (cadastro)
    if ($todos_map.ContainsKey($nome)) {
        $row.receber_analise_elegivel = 'sim (cadastrado)'
    } else {
        $row.receber_analise_elegivel = 'nao (nao cadastrado - 400)'
    }

    $out += $row
    Start-Sleep -Milliseconds 80
}

# Imprime como tabela
$out | ForEach-Object {
    Write-Host '-----'
    foreach ($k in $_.Keys) {
        $v = $_.$k
        Write-Host ('  ' + $k + ': ' + $v)
    }
}
