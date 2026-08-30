---
data: 2026-08-30
tipo: revisao
tags: [vix-radar, task-observer, skills]
status: ativo
---

# 96 — Revisão do backlog task-observer 2026-08-30

## Contexto

Fonte: `E:\Diretorio\Claude\skill-observations\log.md` (191 linhas). 12 observações OPEN,
datadas de 17/08 a 24/08, sem revisão desde 17/08. Escopo aprovado pelo operador: consolidar
em itens acionáveis por skill, registrar no vault e propor atualização de skill, sem alterar
skill nenhuma sem aprovação.

## Consolidação por skill

### `auditoria` — 8 observações (Obs 7 a 14) → bloco de regras "coleta e correção no Windows"

| Obs | Regra a adicionar |
|---|---|
| 7 | Enum serializado com `ConvertTo-Json` e relido com `ConvertFrom-Json` vira número, não nome: filtrar `$_.State -ne 'Disabled'` volta vazio em silêncio. Comparar por valor numérico (1 = Disabled, 3 = Interactive) e, antes de concluir "não existe", rodar contador por valor distinto. Vale para `Get-ScheduledTask`, `Get-Service`, `Get-NetTCPConnection` e qualquer objeto CIM. |
| 8 | Varredura recursiva no Windows desce em junction point (OneDrive, `FREQUENTE`, pastas do shell) e pode entrar em ciclo, travando em silêncio com CPU baixa. Todo walker recursivo checa `(.Attributes -band [System.IO.FileAttributes]::ReparsePoint)` antes de descer. Área de nuvem com placeholder hidrata ao enumerar tamanho: excluir ou usar tamanho do placeholder. |
| 9 | Passo 0 da coleta: procurar e ler relatórios/artefatos de auditorias anteriores no mesmo workspace (`DIAGNOSTICO*.md`, `AUDITORIA-*.md`) antes de abrir varredura nova. Achado de segurança de rodada anterior vale mais que número novo de disco. Template com `<<placeholder>>` = sessão interrompida, tratar como fonte parcial e completar, não como lixo. |
| 10 | Alteração de task agendada/registro com acesso negado em sessão não elevada (SD só da Administrators): ponte UAC com script curto gravado em disco, `Start-Process -Verb RunAs`, resultado em arquivo, poll com deadline. `schtasks` não cobre `LogonType`. O script ponte vai para a pasta de evidência da quarentena, faz parte do trilho de auditoria. |
| 11 | Quarentena por rename no mesmo volume não libera espaço (Move-Item é rename). Separar três números: estagiado em quarentena, efetivamente liberado (delta real de FreeGB antes/depois, saída colada) e projetado após purga. Nunca somar estagiado como liberado. |
| 12 | Move de diretório com processo vivo falha de forma não atômica: parte vai, parte fica. Após falha, medir bytes no destino E no que sobrou na origem, repetir filho-a-filho engolindo erro por item, e `PARCIAL` é status legítimo do manifest com o resto marcado para retry. |
| 13 | Secret em texto puro se audita por metadados: caminho, tamanho, datas e SHA-256, nunca abrir o conteúdo. Cópias por correspondência de nome de arquivo e por igualdade de hash. Busca em histórico/git só pelo nome do caminho, nunca por conteúdo (imprimiria o segredo em novo lugar). |
| 14 | robocopy para listar caminhos usa `/NDL` (sem lista de diretórios), nunca `/NFL` (sem lista de arquivos), o inverso do truque de tamanho. Exit 0-7 = sucesso com nuance, 8+ = parcial; validar a forma da saída com uma linha de amostra antes de aceitar um negativo de busca. |

Encaixe: Obs 7/8/9/14 no protocolo de coleta (Bloco A), Obs 10/12 nas correções (Bloco E/F),
Obs 11 na seção de relatório (espaço recuperável), Obs 13 no Bloco D (segurança).

### `ysz-superpowers` — 2 observações (Obs 5, 6)

- **Obs 5:** pip 26.x parseia `-r` com shlex POSIX e engole backslash de caminho absoluto
  Windows (`-r E:\Diretorio\...` vira `E:Diretorio...`). Usar `-r` relativo ou forward slash.
- **Obs 6:** `Set-Content -Encoding UTF8` do PowerShell 5.1 grava BOM e CLI de terceiro rejeita
  o config. Não regravar config JSON de app de terceiro com ele; usar pwsh 7 (`utf8` sem BOM)
  ou ferramenta dedicada. No VIX Radar a classe já tem guarda no nível repo
  (`scripts/lint-encoding.ps1` reprova .ps1 sem BOM com não-ASCII).

### `relatorio-diario-szuchmacher` — 1 observação (Obs 15)

- Vigia de envio ad hoc casou a substring "ENVIADO OK" dentro de linha `AVISO:` e sinalizou
  envio confirmado quando o envio tinha sido abortado pelo validador, repetindo o falso
  positivo que o watchdog corrigiu em 04/08. Regra: ocorrência em linha que contenha `AVISO`
  não conta, e o sinal primário de envio é a existência de `sent_YYYYMMDD.flag`.
- Nota: skill não encontrada em `C:\Users\User\.claude\skills\`; o workflow de recuperação
  referido deve estar no projeto do site Szuchmacher.

### `frontend-design` — 1 observação (Obs 17)

- Protótipo em sandbox visual (Replit, Figma, Higgsfield) é referência clicável, não
  substituto do repo canônico. Implementação entra no repo com os tokens já documentados
  (navy `#001020`, gold `#B7985D` no VIX Radar) e o deploy existente. Proibido colar secret,
  `wrangler.toml` ou publicar o sandbox como produto.

## Já materializado no código (não exige skill nova)

- **Obs 15 (parcial):** o padrão de exclusão de linha `AVISO` já vive no `monitor-tasks.ps1`
  (ROTINACEGA1, `(?<!SHADOW_)FIM:`) e foi estendido ao vigia novo da Sentinela
  (`scripts/lib/vixradar-watchdog.ps1:29-31`). Falta replicar no workflow do relatório diário.
- **Obs 6 (parcial):** `scripts/lint-encoding.ps1` do VIX Radar cobre a classe no nível repo.

## Disposição das observações

| Obs | Skill | Disposição proposta |
|---|---|---|
| 5 | ysz-superpowers | Propor regra de `-r` no SKILL.md |
| 6 | ysz-superpowers | Propor regra de round-trip de encoding; classe já guardada no VIX Radar |
| 7 | auditoria | Propor regra de enum desserializado |
| 8 | auditoria | Propor regra de walker com pulo de reparse point |
| 9 | auditoria | Propor passo 0 de mineração do relatório anterior |
| 10 | auditoria | Propor ponte UAC com arquivo de resultado |
| 11 | auditoria | Propor separação estagiado/liberado/projetado |
| 12 | auditoria | Propor manifest PARCIAL + medição dos dois lados |
| 13 | auditoria | Propor protocolo de secret por metadados |
| 14 | auditoria | Propor `/NDL` vs `/NFL` no robocopy |
| 15 | relatorio-diario-szuchmacher | Propor replicação da regra de AVISO + flag; padrão já no monitor |
| 17 | frontend-design | Propor regra de sandbox visual |

## Pendência de aprovação

Nenhuma skill foi alterada nesta sessão. As propostas acima aguardam o OK do operador para
editar os `SKILL.md` correspondentes.
