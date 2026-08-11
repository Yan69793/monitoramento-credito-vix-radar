# Set-VixAdminCredential.ps1 - Grava a credencial admin no cofre DPAPI local.
#
# Contraparte de Get-VixAdminCredential.ps1, que so sabia ler. Sem este script
# nao havia caminho suportado para atualizar a senha guardada nesta maquina, e
# quando ela ficou defasada em 10/08/2026 a tarefa VIXRadar-Coleta-Volatilidade
# passou a falhar todo dia com HTTP 403 do Worker, sem que o log dissesse por que.
#
# ASCII puro de proposito: roda no powershell.exe 5.1, mesmo host do Task Scheduler.
#
# A senha e digitada aqui no terminal e nunca aparece na tela, em log, em
# parametro de linha de comando ou no historico do shell. O arquivo resultante e
# cifrado com DPAPI no escopo CurrentUser, entao so esta conta do Windows nesta
# maquina consegue abrir.
#
# Uso: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\api\Set-VixAdminCredential.ps1

[CmdletBinding()]
param([switch]$Verificar)

$ErrorActionPreference = 'Continue'

$datPath = Join-Path $PSScriptRoot ".admin_credencial.dat"

if ($Verificar) {
    if (-not (Test-Path -LiteralPath $datPath)) { Write-Host "Cofre ausente: $datPath"; return }
    $fi = Get-Item -LiteralPath $datPath
    Write-Host ("Cofre presente: {0} bytes, escrito em {1}" -f $fi.Length, $fi.LastWriteTime)
    return
}

Write-Host "Gravando a senha admin do VIX Radar no cofre DPAPI desta maquina."
Write-Host "Destino: $datPath"
Write-Host ""

$s1 = Read-Host 'Senha admin' -AsSecureString
$s2 = Read-Host 'Repita a senha' -AsSecureString

$b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1)
$b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2)
try {
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1)
    $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
}

if (-not $p1) { Write-Host "Senha vazia. Nada foi gravado." -ForegroundColor Red; return }
if ($p1 -cne $p2) { Write-Host "As duas digitacoes nao batem. Nada foi gravado." -ForegroundColor Red; return }

# Backup do cofre anterior antes de sobrescrever, para nao perder acesso se a
# senha nova estiver errada.
if (Test-Path -LiteralPath $datPath) {
    $bak = "$datPath.bak-" + (Get-Date -Format 'yyyyMMddHHmmss')
    Copy-Item -LiteralPath $datPath -Destination $bak -Force
    Write-Host "Cofre anterior salvo em: $bak"
}

Add-Type -AssemblyName System.Security
$plainBytes = [System.Text.Encoding]::UTF8.GetBytes($p1)
$tamanho = $p1.Length
$encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
    $plainBytes, $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
)
[System.IO.File]::WriteAllBytes($datPath, $encrypted)

# Zerar o material em memoria assim que possivel.
[Array]::Clear($plainBytes, 0, $plainBytes.Length)
$p1 = $null
$p2 = $null

# Conferir lendo de volta pelo mesmo helper que a producao usa. Compara so o
# comprimento, nunca o valor.
$helper = Join-Path $PSScriptRoot 'Get-VixAdminCredential.ps1'
if (Test-Path -LiteralPath $helper) {
    $lido = & $helper -AsPlainText 2>$null
    if ($lido -and $lido.Length -eq $tamanho) {
        Write-Host "OK. Cofre gravado e relido com sucesso ($tamanho caracteres)." -ForegroundColor Green
        Write-Host ""
        Write-Host "Proximo passo: confirme contra o Worker rodando a tarefa de volatilidade."
        Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_coleta_volatilidade.ps1"
    } else {
        Write-Host "ATENCAO: gravou, mas a releitura nao bateu. Verifique o arquivo." -ForegroundColor Red
    }
    $lido = $null
} else {
    Write-Host "Cofre gravado. Helper de leitura nao encontrado para conferencia."
}
