<#
.SYNOPSIS
  Configura (ou rotaciona) a credencial Cloudflare para deploy do Pages.

.DESCRIPTION
  Persiste CLOUDFLARE_API_TOKEN e CLOUDFLARE_ACCOUNT_ID como variaveis de
  ambiente do Windows (User scope). O token NUNCA e gravado em arquivo.
  Rode novamente sempre que rotacionar o token.

  Apos rodar, ABRA UM NOVO terminal para as variaveis ficarem visiveis,
  entao use: pwsh ./scripts/deploy-pages.ps1

.EXAMPLE
  # Interativo (token nao aparece no historico):
  pwsh ./scripts/setup-deploy-credential.ps1

  # Nao-interativo:
  pwsh ./scripts/setup-deploy-credential.ps1 -Token "cfut_xxx" -AccountId "7ac7..."
#>
[CmdletBinding()]
param(
  [string]$Token,
  [string]$AccountId = "7ac79fb1030e4e81115ef33c21a9b070"
)

if (-not $Token) {
  $sec = Read-Host -AsSecureString "Cole o CLOUDFLARE_API_TOKEN (entrada oculta)"
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
if (-not $Token) { Write-Host "Token vazio — abortado." -ForegroundColor Red; exit 1 }

[Environment]::SetEnvironmentVariable("CLOUDFLARE_API_TOKEN", $Token, "User")
[Environment]::SetEnvironmentVariable("CLOUDFLARE_ACCOUNT_ID", $AccountId, "User")

Write-Host "OK — CLOUDFLARE_API_TOKEN e CLOUDFLARE_ACCOUNT_ID persistidos (User scope)." -ForegroundColor Green
Write-Host "Token len: $($Token.Length) | AccountId: $AccountId" -ForegroundColor DarkGray
Write-Host "Abra um NOVO terminal e rode: pwsh ./scripts/deploy-pages.ps1" -ForegroundColor Cyan
