# apply-security-rotation.ps1, Etapa 1: Rotacao de credenciais VIX Radar
# Gerado em 2026-07-24
# Guarda adicionada 2026-07-27: passo C abaixo, apos a rotacao de 24/07 ter
# deixado o ADMIN_PASSWORD do GitHub Actions desatualizado por 3 dias sem
# nenhum aviso (ver PENDENCIAS.md, item "Frescor da Ingestao").
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
#   C. Pede confirmacao manual de que ADMIN_PASSWORD tambem foi atualizado no
#      GitHub Actions (secret separado, usado por frescor-check.yml,
#      daily-status-email.yml, scan-emergencia.yml)
#   D. Configura ADMIN_EMAIL como Cloudflare Worker secret
#   E. Remove ADMIN_EMAIL do [vars] do wrangler.toml (ja feito)
#   F. Confere que todo secret obrigatorio existe no Worker (aborta se faltar)
#   G. Valida health apos rotacao
#   H. Exibe comandos para rotacionar token ANBIMA

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
Write-Host "[1/8] Verificando pre-requisitos..." -ForegroundColor Yellow

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
Write-Host "[2/8] Lendo nova senha admin do DPAPI..." -ForegroundColor Yellow

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
Write-Host "[3/8] Atualizando ADMIN_PASSWORD no Cloudflare..." -ForegroundColor Yellow

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
    Write-Host "  ADMIN_PASSWORD: ATUALIZADO no Cloudflare" -ForegroundColor Green
}

# --- GitHub Actions usa o MESMO ADMIN_PASSWORD, secret separado --------
# Achado 27/07: esta etapa foi pulada na rotacao original (24/07) e os workflows
# frescor-check.yml, daily-status-email.yml e scan-emergencia.yml ficaram
# falhando silenciosamente por 3 dias (ver PENDENCIAS.md). REPETIU em ~09-10/08:
# o secret do GitHub divergiu de novo e os dois guardas de staleness ficaram
# cegos por 4 dias, achado da auditoria geral de 13/08 (GHWL1). O gh CLI existe
# nesta maquina (confirmado 11/08), mas secrets nao sao gerenciaveis via PAT
# fine-grained, entao o gate continua sendo confirmacao manual. Depois de
# atualizar, valide com: scripts/check-gh-actions-health.ps1 (esperado 3/3
# verdes na proxima run de cada workflow).
Write-Host "[4/8] ADMIN_PASSWORD tambem precisa ser atualizado no GitHub Actions..." -ForegroundColor Yellow
Write-Host "  Os workflows frescor-check.yml, daily-status-email.yml e scan-emergencia.yml" -ForegroundColor White
Write-Host "  leem secrets.ADMIN_PASSWORD, que e independente do secret do Cloudflare." -ForegroundColor White
if ($DryRun) {
    Write-Host "  DRY-RUN: pulando confirmacao do secret no GitHub" -ForegroundColor Yellow
} else {
    Write-Host "  Abra https://github.com/Yan69793/monitoramento-credito-vix-radar/settings/secrets/actions" -ForegroundColor Cyan
    Write-Host "  e atualize ADMIN_PASSWORD com o mesmo valor usado acima (recupere de novo com" -ForegroundColor Cyan
    Write-Host "  api/Get-VixAdminCredential.ps1 -AsPlainText se precisar)." -ForegroundColor Cyan
    $confirmaGithub = Read-Host "  Ja atualizou o secret ADMIN_PASSWORD no GitHub? (s/n)"
    if ($confirmaGithub -notmatch '^(s|sim|y|yes)$') {
        Write-Host "  AVISO: GitHub Actions vai continuar com a senha antiga ate voce atualizar. Os 3 workflows acima vao falhar." -ForegroundColor Red
        Write-Host "  AVISO (GHWL1): frescor-check e scan-emergencia sao os guardas de staleness da ingestao. Com secret velho eles ficam CEGOS, nao so vermelhos." -ForegroundColor Red
    } else {
        Write-Host "  ADMIN_PASSWORD: confirmado atualizado no GitHub tambem" -ForegroundColor Green
        Write-Host "  GHWL1: rode scripts/check-gh-actions-health.ps1 na proxima janela de runs para confirmar os 3 workflows verdes." -ForegroundColor Cyan
    }
}

# --- Configurar ADMIN_EMAIL como secret --------------------------------
Write-Host "[5/8] Configurando ADMIN_EMAIL como Cloudflare secret..." -ForegroundColor Yellow

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
Write-Host "[6/8] Validando wrangler.toml..." -ForegroundColor Yellow

$tomlContent = Get-Content (Join-Path $apiDir 'wrangler.toml') -Raw
if ($tomlContent -match 'ADMIN_EMAIL\s*=\s*"szuchmacheryan') {
    Write-Host "  AVISO: ADMIN_EMAIL ainda aparece no [vars] do wrangler.toml" -ForegroundColor Yellow
} else {
    Write-Host "  wrangler.toml [vars]: ADMIN_EMAIL removido" -ForegroundColor Green
}

# --- Conferencia final: todo secret obrigatorio existe no Worker -------
# Guarda adicionada 27/07. A rotacao de 24/07 removeu ADMIN_EMAIL do [vars] do
# wrangler.toml e o secret nunca chegou a ser criado no Cloudflare. O Worker
# rodou 3 dias com ADMIN_EMAIL vazio: todo e-mail ao admin morria em "Sem
# destinatarios." e nenhum login recebia role admin no JWT. Nada no processo
# conferia, depois do fato, que cada destino ficou consistente, e o unico sinal
# foi um evento de telemetria que ninguem leu. Este passo fecha a classe
# inteira, nao so o ADMIN_EMAIL. Ver PENDENCIAS.md.
Write-Host "[7/8] Conferindo secrets obrigatorios no Worker..." -ForegroundColor Yellow

# Obrigatorios: ausencia quebra funcao central do sistema, o script aborta.
$SECRETS_OBRIGATORIOS = @(
    'ADMIN_EMAIL'        # sem ele: e-mail ao admin morre e login nunca vira role admin
    'ADMIN_PASSWORD'     # painel de aprovacao e admin_health_check dos workflows
    'JWT_SECRET'         # autenticacao inteira
    'RESEND_API_KEY'     # e-mail transacional, ja entra no _okHealth
    'ANTHROPIC_API_KEY'  # verificador, entra no verificador_ok
)
# Recomendados: ausencia degrada em silencio, vira aviso e nao aborta.
$SECRETS_RECOMENDADOS = @(
    'TWILIO_ACCOUNT_SID'
    'TWILIO_AUTH_TOKEN'
    'TWILIO_WHATSAPP_FROM'
    'ADMIN_WHATSAPP_TO'
    'ANBIMA_CLIENT_SECRET'
    'ROUTINE_API_KEY'
    'RESEND_WEBHOOK_SECRET'
)

if ($DryRun) {
    Write-Host "  DRY-RUN: pulando wrangler secret list" -ForegroundColor Yellow
} else {
    Push-Location $apiDir
    try {
        $secretsRaw = npx wrangler secret list --name radar-credito-api 2>&1 | Out-String
        $secretsExit = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if ($secretsExit -ne 0) {
        Write-Host $secretsRaw -ForegroundColor DarkGray
        throw "wrangler secret list falhou (exit $secretsExit). Sem essa leitura nao da para afirmar que a rotacao ficou consistente."
    }

    # A saida costuma vir com ruido do npx antes do JSON; recorta do primeiro
    # '[' ao ultimo ']' em vez de assumir que a string inteira e JSON.
    $ini = $secretsRaw.IndexOf('[')
    $fim = $secretsRaw.LastIndexOf(']')
    if ($ini -lt 0 -or $fim -le $ini) {
        Write-Host $secretsRaw -ForegroundColor DarkGray
        throw "Nao localizei o JSON na saida de wrangler secret list. Confira a mao antes de dar a rotacao por concluida."
    }

    $presentes = @(($secretsRaw.Substring($ini, $fim - $ini + 1) | ConvertFrom-Json) | ForEach-Object { $_.name })
    Write-Host "  $($presentes.Count) secrets configurados no Worker" -ForegroundColor DarkGray

    foreach ($s in @($SECRETS_RECOMENDADOS | Where-Object { $presentes -notcontains $_ })) {
        Write-Host "  AVISO: $s ausente. Degrada em silencio, nao derruba o sistema." -ForegroundColor Yellow
    }

    $faltando = @($SECRETS_OBRIGATORIOS | Where-Object { $presentes -notcontains $_ })
    if ($faltando.Count -gt 0) {
        Write-Host ""
        foreach ($s in $faltando) { Write-Host "  FALTANDO: $s" -ForegroundColor Red }
        Write-Host "  Crie cada um com: npx wrangler secret put <NOME>" -ForegroundColor Cyan
        throw "Rotacao INCOMPLETA: $($faltando.Count) secret(s) obrigatorio(s) ausente(s). Foi exatamente assim que o ADMIN_EMAIL sumiu por 3 dias em 24/07."
    }

    Write-Host "  Todos os $($SECRETS_OBRIGATORIOS.Count) secrets obrigatorios presentes" -ForegroundColor Green
}

# --- Health check ------------------------------------------------------
if (-not $SkipHealthCheck) {
    Write-Host "[8/8] Verificando health da API..." -ForegroundColor Yellow

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
