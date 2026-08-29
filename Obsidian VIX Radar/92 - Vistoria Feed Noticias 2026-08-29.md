---
data: 2026-08-29
tipo: recado
tags: [vix-radar, feed, noticias, verificacao, recado]
status: ativo
---

# 92 - Vistoria Feed de Noticias 2026-08-29

**Recado para a sessão que for executar /melhorar-e-executar.** Sessão readonly de verificação do relato do operador: "as notícias não são atualizadas no frontend desde 25/08". Verificação concluída. O que segue é o que foi provado e o que falta fazer.

## Veredito

O feed está mostrando a verdade do sistema. Não existe evento datado depois de 25/08 em produção, então não há o que o frontend exibir.

Prova via `op=state` (JWT admin, consulta em 29/08 ~15h BRT): MAX `data_evento` = 2026-08-25, 491 eventos na janela multi-semana. Os eventos de 25/08 são todos da Oi (falência decretada, imprensa) mais a assembleia de debenturistas da Raízen (CVM). Nada datado de 26/08 em diante.

## Por que nada depois de 25/08: duas causas, uma externa esperada e uma interna

1. **Externa, esperada.** A CVM não publicou desde 25/08. Health ao vivo: `cvm_fonte_last_modified: 2026-08-25`, `cvm_fonte_idade_du:3`, cadência semanal, `cvm_fonte_proxima_prevista: 2026-08-30`. Próxima publicação prevista domingo 30/08. Não é bug, e o health está certo ao manter `cvm_fonte_ok:true` e `fonte_externa_ok:true`. Mesmo com as três rotinas rodando todo dia, o feed ficaria em 25/08 até a CVM publicar.

2. **Interna, dia 28/08 sem varredura.** Matinal (18h), noturno (10h) e verificação não rodaram em 28/08. Não existem `vixradar-noturno_20260828.log`, `vixradar-matinal_20260828.log` nem `vixradar-verificacao-async_20260828.log`. Causa: o app do Claude Desktop não estava aberto (todos os processos `claude.exe` começaram hoje 29/08 às 14:50; o CCD store `scheduled-tasks.json` confirma `lastScheduledFor` da matinal = 28/08 21:00Z com `lastRunAt` = 29/08, ou seja a sessão de 28/08 foi perdida). A sentinela (Task Scheduler, independente do app) rodou o dia inteiro e confirmou a cada meia hora `acervo do Worker inalterado (2026-08-25) e sem backlog`. Esse gap já está registrado como WATCHDOG-NAOINICIOU1 na PENDENCIAS (auditoria geral de 29/08, outra sessão), que propõe o vigia alertar quando a rotina não inicia.

## O que está acontecendo agora (catch-up)

O app subiu às 14:50 e as sessões dispararam em catch-up. A matinal já varreu o top 15 até ~15h e não achou fato novo datado de 26-29/08, os eventos que submeteu são os mesmos de 24-25/08 (Oi, Braskem, Raízen, Kora, Oncoclínicas). A noturna (103 emissores, 3 lotes disparados às 14:54) está em execução e varrendo a janela 30/07-29/08.

## Ação de follow-up para a sessão de fix

1. **Depois que a noturna de hoje terminar (estimativa 20-40 min), re-consultar `op=state`** (mesmo padrão do `scripts/monitoring/medir_staleness.ps1`). Se aparecerem eventos datados de 26-29/08, o gap de 28/08 causou atraso de ~1 dia na captura de notícia real. Se não aparecerem, nada material aconteceu no período e o feed está correto em 25/08, com a próxima atualização natural na publicação CVM de 30/08.
2. **O que vigiar não é o frontend.** É o WATCHDOG-NAOINICIOU1 (rotina que não inicia precisa alertar em vez de sair 0) e, se o operador quiser robustez, alguma guarda de "app do Claude Desktop precisa estar aberto no horário do cron", porque o agendamento das três sessões vive no CCD store e depende do app estar de pé.
3. **Prova independente opcional:** busca externa dirigida aos 5 maiores riscos (Oi, Braskem, Raízen, CSN, Light) atrás de notícia material de 26-28/08. A noturna está fazendo essa varredura agora, o resultado dela já responde.
