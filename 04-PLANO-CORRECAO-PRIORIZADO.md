# 04 — Plano de Correção Priorizado VIX Radar

Data: 2026-07-28. Base: SHA `fdae5cb`. IDs, severidades, evidências e critérios de aceite completos no registro canônico (`00-AUDITORIA-SISTEMA-COMPLETA.md`). Este plano ordena e sequencia, não reconta.

Nenhum item deste plano executa sem Gate C (autorização própria para mudança de código, KV, calendário ou produção). Os itens já rastreados em `Obsidian VIX Radar/PENDENCIAS.md` mantêm lá seu plano detalhado, aqui entram só na ordenação com o ID canônico.

## 1. Contenção imediata recomendada (P0 ativo)

CAL-002 é P0: o dashboard exibe hoje, com selo AGENDADO, datas de resultado comprovadamente erradas de dois emissores sistêmicos. Bradesco marcado para 28/07 quando o RI oficial informa 05/08 (e 28/07 cai dentro do período de silêncio do banco), Vale exibida como "Última divulgação 24/07" quando a divulgação oficial é 30/07 e ainda não ocorreu. Evidência completa no relatório 03, seção 3.

Três ações de contenção, em ordem de menor superfície, nenhuma executada:

1. **Corrigir as duas datas.** Bradesco 05/08 e Vale 30/07, com `fonte` primária e `status: "agendado"`. Via override de KV é o caminho limpo, mas depende de CAL-003 (hoje o override não alcança o selo da UI). Sem CAL-003, o caminho efetivo é corrigir as duas entradas na base do bundle e redeployar.
2. **CAL-001, rótulo.** Trocar o colapso "não divulgado → AGENDADO" por "estimado → ESTIMADO" é mudança de uma linha no frontend mais propagação de dois campos na agenda. Remove o selo falso das 20 estimativas de uma vez, inclusive Petrobras, que segue não confirmada.
3. **Validar o resto do lote.** As 18 datas 2T26 não checadas, começando pelas mais próximas (Itaúsa e Gerdau em 29/07, Suzano e Embraer em 30/07). É leitura, não mutação. A taxa observada até agora é 2 erros em 2 verificações, então tratar as demais como suspeitas é o default correto.

## 2. Fila priorizada

| Ordem | ID | Sev | Item | Esforço | Gate | Dependência |
|---|---|---|---|---|---|---|
| 1 | CAL-002 | **P0** | Corrigir Bradesco 05/08 e Vale 30/07 com fonte primária; validar as 18 datas 2T26 restantes | S por data, M com validação do lote | C | F0 |
| 2 | CAL-001 | P1 | Exibir ESTIMADO e propagar `status`/`nota` na agenda (remove o selo falso das demais estimativas) | S | C | — |
| 3 | OPS-001 | P1 | Matinal: pre-flight de ambiente, probe WebSearch, contagem apurada de buscas, `-Force` (plano em PENDENCIAS) | M | C | — |
| 4 | CI-002 | P2 | Scan de emergência: `ok:false` vira exit 1 | S | C | — |
| 5 | OPS-002 | P2 | Coleta de volatilidade: propagar `$LASTEXITCODE` dos filhos, abortar upload, exit próprio | S | C | — |
| 6 | CAL-003 | P2 | `op=calendario` passa a ler base + overrides | S | C | — |
| 7 | CI-001 | P2 | Política de secret ausente: run agendada falha ou abre issue | S | C | Decisão de política |
| 8 | SEC-002 | P2 | Cadastro existente: resposta honesta + notificação com dedup (plano em PENDENCIAS, nota de enumeração) | M | C | — |
| 9 | SEC-003 | P2 | WhatsApp StatusCallback + fallback e-mail (plano em PENDENCIAS, validação Twilio antes) | M | C | Validação console Twilio |
| 10 | CAL-004 | P2 | Rotina de atualização do calendário + staleness no monitor | M | C | CAL-003, hierarquia do rel. 02 |
| 11 | VOL-003 | P2 | SELIC com fonte e `as_of`, eliminar contradição interna | S | C | DEC-001 |
| 12 | VOL-001 | P2 | `market_cap`: popular de verdade ou remover campo, tirar guarda `> 100`, documentar E do Merton | M | C | Decisão de fonte |
| 13 | OPS-003 | P2 | Idempotência com `-Force`/marcador de cobertura (plano em PENDENCIAS) | S | C | Sai junto com OPS-001 |
| 14 | OPS-004 | P2 | monitor-tasks: causa lida de log/stderr real (plano em PENDENCIAS) | S | C | — |
| 15 | VOL-002 | P3 | Contrato do estimador de volatilidade + unificar função duplicada | S | C | — |
| 16 | CI-003 | P3 | Rotação: automatizar/verificar secret GitHub | S | C | PAT com escopo |
| 17 | OPS-005 | P3 | `exit` → `return` na verificação async (após commit do trabalho em curso) | S | C | Trabalho não commitado fechar |
| 18 | ENC-001 resíduos | P3 | Guarda no repo Site, identificar editor que remove BOM | S | C | — |

Racional da ordem: primeiro o dado errado exposto ao usuário agora (CAL-002, com CAL-001 logo atrás porque é o que impede a repetição), depois o que mente para o operador (OPS-001, CI-002), depois o que silencia degradação (OPS-002, CAL-003, CI-001), depois notificações, depois contratos de dado, por fim higiene. Cada correção fecha com causa raiz e guarda, nunca só o patch (regra do projeto). Corrigir as duas datas sem CAL-001 e CAL-004 resolve o sintoma e deixa as outras 18 estimativas com o mesmo selo falso.

DEC-001 (semântica da SELIC) é decisão de produto, não item de fila: meta vigente, efetiva anualizada ou outra referência. Sem ela o item 11 não especifica a série do BCB. Com os valores oficiais de 28/07 (meta 14,25%, efetiva 14,15%), a diferença entre as opções é de cerca de 10 bps, menor que o erro atual de 40 a 50 bps do hardcode, então corrigir a fonte importa mais do que a escolha da série, mas a escolha continua necessária para o contrato. Prazo sugerido: antes do item 11 entrar em execução.

## 3. F0 — Pré-requisitos de qualquer mutação de calendário ou KV

Condições para o futuro plano de execução que corrigir overrides ou reconstruir a agenda. Sem todas, não roda:

1. Snapshot das chaves KV afetadas (`calendario:overrides:v1`, `agenda:eventos`, e qualquer outra tocada) antes da mutação.
2. Lista exata das mutações (chave, campo, valor antes, valor depois).
3. Rollback testável (restauração do snapshot ensaiada, não só descrita).
4. Fontes oficiais anexadas por data alterada (URL, data-hora, timezone America/Sao_Paulo). Para Bradesco e Vale as fontes já estão no relatório 03, seção 3, prontas para anexar.
5. Comparação antes/depois dos endpoints afetados (`op=calendario`, agenda).
6. Verificação nas três superfícies: UI, endpoint e e-mail.
7. Confirmação de que as estimativas restantes continuam rotuladas como estimativas depois da mudança.

## 4. ADR proposto — Onde as rotinas devem viver

A cadeia de incidentes de julho (settings.json contaminando o Scheduler, ambiente sujo de sessão, PS 5.1 × PS7, tasks sumindo sem rastro, OneDrive travando logs) pergunta se as rotinas deveriam migrar da máquina local para GitHub Actions ou Workers cron. Isso é decisão arquitetural, não conclusão desta auditoria, e a migração não é inevitável: o desktop hoje é quem tem acesso à assinatura Claude Code (custo zero marginal por token), e o `scan-emergencia` já existe como fallback híbrido.

Proposta: um ADR curto mais piloto, comparando as opções nas dimensões que os incidentes expuseram:

| Dimensão | Local (hoje) | GitHub Actions | Workers cron |
|---|---|---|---|
| Custo por execução | Assinatura já paga | API Anthropic por token | API + limites de CPU |
| Acesso a recursos locais (CLI Claude, DPAPI, logs) | Total | Nenhum | Nenhum |
| Secrets | env var + DPAPI, um destino a mais na rotação | GitHub Secrets (CI-003) | Cloudflare Secrets |
| Observabilidade | Logs locais + monitor-tasks (OPS-004) | Runs visíveis, mas fail-open hoje (CI-001) | Telemetria AE nativa |
| Recuperação após falha | Manual, armadilhas documentadas (OPS-003) | Retry nativo | Retry + DO |
| Fragilidade ambiental | Alta (comprovada em julho) | Baixa | Baixa |

Piloto sugerido para o ADR: mover uma rotina de baixo risco e alto atrito ambiental (candidata: coleta de volatilidade, que é HTTP puro sem CLI Claude) e medir por 2 semanas antes de decidir sobre as demais. Sem autorização, nada migra.

## 5. Guardas transversais (DATA-001)

Toda correção da fila incorpora, no que tocar:

1. `fonte` e `as_of` no dado gravado.
2. Nível de confiança sobrevivendo até a exibição.
3. Métrica com origem apurada, nunca autodeclarada.
4. Falha de dependência propagada com exit/status próprio, nunca degradação silenciosa.

Aceite global do plano: a reexecução desta auditoria não encontra nenhuma instância nova da família "rótulo sem fonte apurada", e as instâncias listadas têm guarda ativa que impediria regressão.
