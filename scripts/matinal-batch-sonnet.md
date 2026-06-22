# Lote Sonnet matinal — max 3 buscas/emissor (R2, R6, R5). Sem R1. CVM do plano.
# provedor: claude-sonnet-routine. _matinal:true obrigatorio no receber_analise.
# CRITICO/RELEVANTE: URL verificavel. ECO/NENHUM: nota curta.
# Sequencial. Linha: OK|empresa|tier|classificacao|eventos_count|fontes_count|submit_ok

## Submit obrigatório por emissor

POST https://api.vixradar.com
Content-Type: application/json

{
  "action": "receber_analise",
  "routine_key": "ROUTINE_KEY_DO_PROMPT",
  "_matinal": true,
  "provedor": "claude-sonnet-routine",
  "empresa": "NOME_EMPRESA",
  "setor": "SETOR",
  "resultado": { ... }
}

PowerShell:
$body = @{ action='receber_analise'; routine_key=$ROUTINE_KEY; empresa=$emp; setor=$setor; _matinal=$true; provedor='claude-sonnet-routine'; resultado=@{...} } | ConvertTo-Json -Depth 16 -Compress
Invoke-RestMethod -Uri 'https://api.vixradar.com' -Method Post -ContentType 'application/json; charset=utf-8' -Body $body

Campo obrigatório: action (não op, não scheduler_key, não api_key).
Confirmação: ok:true no retorno.
