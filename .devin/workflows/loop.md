---
description: Loop de monitoramento contínuo das rotinas VIX Radar
---

Loop de monitoramento das rotinas noturna e verificação async. Atualiza a cada 10 segundos até Ctrl+C.

```powershell
while ($true) {
    Clear-Host
    Write-Host "=== ROTINA NOTURNA ===" -ForegroundColor Cyan
    Get-Content "E:\Diretorio\Claude\Monitoramento de Credito\logs\routines\vixradar-noturno_20260709.log" -Tail 5
    Write-Host ""
    Write-Host "=== VERIFICAÇÃO ASYNC ===" -ForegroundColor Yellow
    Get-Content "E:\Diretorio\Claude\Monitoramento de Credito\logs\routines\vixradar-verificacao-async_20260709.log" -Tail 5
    Write-Host ""
    Write-Host "Atualizado: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
    Write-Host "Pressione Ctrl+C para parar" -ForegroundColor DarkGray
    Start-Sleep -Seconds 10
}
```

Para usar: copie o comando acima e cole no terminal PowerShell.
