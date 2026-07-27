# apply-security-rotation.ps1, Etapa 1: Rotacao de credenciais VIX Radar
# Gerado em 2026-07-24
# Executar como Administrador em PowerShell 7+ com CLOUDFLARE_API_TOKEN definido
#
# Pré-requisitos:
#   1. Node.js + npx disponiveis no PATH
#   2. $env:CLOUDFLARE_API_TOKEN definido (token Cloudflare com permissao Workers)
#   3. Executar do diretorio raiz do projeto (Monitoramento de Credito)
#
# O que faz:
#   A. Le a nova senha admin do DPAPI local
#   B. Atualiza ADMIN_PASSWORD no Cloudflare Worker secret
#   C. Configura ADMIN_EMAIL como Cloudflare Worker secret
#   D. Remove ADMIN_EMAIL do [vars] do wrangler.toml (ja feito)
#   E. Valida health apos rotacao
#   F. Exibe comandos para rotacionar token ANBIMA

param(
    [switch]$DryRun,
    [switch]$SkipHealthCheck
)

$ErrorActionPreference = 'Stop'
$ROOT = $PSScriptRoot | Split-Path -Parent

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " VIX RADAR, Rotacao de Credenciais (Etapa 1)" -ForegroundColor Cyan
Write-Host " Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss BRT')" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Verificar pré-requisitos ------------------------------------------
Write-Host "[1/6] Verificando pre-requisitos..." -ForegroundColor Yellow

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Host "ERRO: npx nao encontrado. Instale Node.js." -ForegroundColor Red
    exit 1
}

if (-not $env:CLOUDFLARE_API_TOKEN) {
    Write-Host "ERRO: CLOUDFLARE_API_TOKEN nao definido." -ForegroundColor Red
    Write-Host "  Defina com: `$env:CLOUDFLARE_API_TOKEN = '<seu-token>'" -ForegroundColor Yellow
    exit 1
}

Write-Host "  npx: OK" -ForegroundColor Green
Write-Host "  CLOUDFLARE_API_TOKEN: presente ($($env:CLOUDFLARE_API_TOKEN.Length) chars)" -ForegroundColor Green

# --- Ler nova senha do DPAPI -------------------------------------------
Write-Host "[2/6] Lendo nova senha admin do DPAPI..." -ForegroundColor Yellow

$helper = Join-Path $ROOT 'api\Get-VixAdminCredential.ps1'
if (-not (Test-Path $helper)) {
    Write-Host "ERRO: Get-VixAdminCredential.ps1 nao encontrado em api/" -ForegroundColor Red
    exit 1
}

$NOVA_SENHA = & $helper -AsPlainText 2>$null
if (-not $NOVA_SENHA) {
    Write-Host "ERRO: Nao foi possivel ler a credencial do DPAPI." -ForegroundColor Red
    Write-Host "  O arquivo .admin_credencial.dat foi gerado nesta maquina?" -ForegroundColor Yellow
    exit 1
}

Write-Host "  Senha recuperada: $($NOVA_SENHA.Length) chars (prefixo: $($NOVA_SENHA.Substring(0,4))...)" -ForegroundColor Green

# --- Atualizar ADMIN_PASSWORD ------------------------------------------
Write-Host "[3/6] Atualizando ADMIN_PASSWORD no Cloudflare..." -ForegroundColor Yellow

$apiDir = Join-Path $ROOT 'api'
Push-Location $apiDir

if ($DryRun) {
    Write-Host "  DRY-RUN: pulando wrangler secret put ADMIN_PASSWORD" -ForegroundColor Yellow
} else {
    Write-Host "  Executando: npx wrangler secret put ADMIN_PASSWORD" -ForegroundColor White

    # Usar echo via pipe para passar a senha (evita expor no comando)
    $NOVA_SENHA | npx wrangler secret put ADMIN_PASSWORD --no-autoconfig 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRO: Falha ao atualizar ADMIN_PASSWORD (exit code: $LASTEXITCODE)" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "  ADMIN_PASSWORD: ATUALIZADO" -ForegroundColor Green
}

# --- Configurar ADMIN_EMAIL como secret --------------------------------
Write-Host "[4/6] Configurando ADMIN_EMAIL como Cloudflare secret..." -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "  DRY-RUN: pulando wrangler secret put ADMIN_EMAIL" -ForegroundColor Yellow
} else {
    Write-Host "  Executando: npx wrangler secret put ADMIN_EMAIL" -ForegroundColor White
    "szuchmacheryan@gmail.com" | npx wrangler secret put ADMIN_EMAIL --no-autoconfig 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRO: Falha ao configurar ADMIN_EMAIL (exit code: $LASTEXITCODE)" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "  ADMIN_EMAIL: CONFIGURADO como secret" -ForegroundColor Green
}

Pop-Location

# --- Verificar que ADMIN_EMAIL saiu do [vars] --------------------------
Write-Host "[5/6] Validando wrangler.toml..." -ForegroundColor Yellow

$tomlContent = Get-Content (Join-Path $apiDir 'wrangler.toml') -Raw
if ($tomlContent -match 'ADMIN_EMAIL\s*=\s*"szuchmacheryan') {
    Write-Host "  AVISO: ADMIN_EMAIL ainda aparece no [vars] do wrangler.toml" -ForegroundColor Yellow
} else {
    Write-Host "  wrangler.toml [vars]: ADMIN_EMAIL removido" -ForegroundColor Green
}

# --- Health check ------------------------------------------------------
if (-not $SkipHealthCheck) {
    Write-Host "[6/6] Verificando health da API..." -ForegroundColor Yellow

    try {
        $health = Invoke-RestMethod -Uri "https://radar-credito-api.prospects-intel.workers.dev" -TimeoutSec 15
        Write-Host "  ok: $($health.ok)" -ForegroundColor $(if ($health.ok) { 'Green' } else { 'Red' })
        Write-Host "  versao: $($health.versao)" -ForegroundColor White
        Write-Host "  bindings: kv=$($health.bindings.kv) rate_limiter=$($health.bindings.rate_limiter) telemetria=$($health.bindings.telemetria)" -ForegroundColor White
        Write-Host "  verificador_ok: $($health.verificador_ok)" -ForegroundColor White
    } catch {
        Write-Host "  ERRO no health check: $_" -ForegroundColor Red
    }
}

# --- Próximos passos ---------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " PROXIMOS PASSOS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Testar login admin no frontend:" -ForegroundColor White
Write-Host "   - Acessar https://vixradar.com" -ForegroundColor White
Write-Host "   - Ctrl+Shift+A para abrir painel admin" -ForegroundColor White
Write-Host "   - Usar a NOVA senha (recuperar via: api/Get-VixAdminCredential.ps1 -AsPlainText)" -ForegroundColor White
Write-Host ""
Write-Host "2. Rotacionar token ANBIMA:" -ForegroundColor White
Write-Host "   - Acessar https://api.anbima.com.br" -ForegroundColor White
Write-Host "   - Solicitar novo APP token" -ForegroundColor White
Write-Host "   - Atualizar: npx wrangler secret put ANBIMA_CLIENT_SECRET" -ForegroundColor White
Write-Host ""
Write-Host "3. Commitar mudancas (APOS validar que tudo funciona):" -ForegroundColor White
Write-Host "   git add -A" -ForegroundColor White
Write-Host "   git commit -m 'security: rotacao de credenciais Etapa 1 (C1/C2/C3/M5)'" -ForegroundColor White
Write-Host "   git push" -ForegroundColor White
Write-Host ""
Write-Host "4. Deploy Worker com wrangler.toml atualizado:" -ForegroundColor White
Write-Host "   pwsh ./scripts/deploy-worker.ps1 -Version v4.9.172" -ForegroundColor White
Write-Host ""
Write-Host "5. Plano de reversao (se necessario):" -ForegroundColor White
Write-Host "   - Restaurar api/wrangler.toml do backup: _backup_security_fix_*/api_wrangler.toml.bak" -ForegroundColor White
Write-Host "   - Restaurar ADMIN_PASSWORD anterior (valor no backup DPAPI, considerar comprometida)" -ForegroundColor White
Write-Host "   - Restaurar api/.env do backup" -ForegroundColor White
Write-Host "   - Redeploy Worker" -ForegroundColor White
Write-Host ""
Write-Host "Backups em: $ROOT\_backup_security_fix_*" -ForegroundColor Yellow
