# 00 — Auditoria Técnica Completa VIX Radar

Data: 2026-07-28. SHA-base: `fdae5cb14b854415f27d9f17333d57812d347f25` (branch `main`, 1 commit à frente de `origin/main`). Bundle auditado: `api/v4.9.182.js`, que é o `main` do `api/wrangler.toml` (linha 469) e a versão viva em produção conforme health desta sessão. Worktree no momento da auditoria: 83 arquivos modificados sem commit, caracterizados na seção 8, nenhum deles alterado por esta entrega.

Este é o registro canônico. Os relatórios 01 a 04 referenciam os IDs daqui e não recontam diagnóstico.

## 1. Sumário executivo

O sistema está operacionalmente saudável e verificado ao vivo nesta sessão (seção 6). Os defeitos encontrados não são de disponibilidade, são de veracidade: em vários pontos o sistema afirma coisas que nenhum código apurou. Uma data estimada por padrão histórico aparece na tela com o selo AGENDADO (CAL-001). Um contador de buscas que o próprio modelo declara vira métrica de cobertura da rotina (OPS-001). Um campo chamado `market_cap` carrega preço de ação (VOL-001). Um HTTP 201 do Twilio é tratado como prova de entrega (SEC-003). Um secret ausente encerra o workflow de vigilância com sucesso (CI-001).

A causa sistêmica é uma só e está registrada como DATA-001: o contrato de dados não carrega proveniência nem nível de confiança, então rótulo e fonte se descolam sem que nada acuse. As correções pontuais do relatório 04 só estancam a família se cada uma fechar com a guarda correspondente.

Contagem: 21 entradas no registro. 1 P0 ativo, 2 P1, 11 P2, 3 P3, 1 decisão de produto pendente, 1 causa transversal, 2 resolvidos com guarda (registrados para rastreabilidade). O P0 é CAL-002, divergência oficial confirmada em 28/07: o RI do Bradesco marca a divulgação para 05/08 (o dashboard exibe AGENDADO para hoje, 28/07, dentro do período de silêncio oficial do banco), e a Vale divulga em 30/07 (o dashboard exibe "Última divulgação 24/07", afirmando um resultado que oficialmente ainda não saiu). A recomendação de contenção imediata está no achado e no relatório 04. Nada foi executado, correção de dado é Gate C.

## 2. Taxonomia de certeza

| Nível | Critério |
|---|---|
| COMPROVADO | Evidência direta e reproduzível obtida no repositório, no bundle implantado, em fonte oficial primária ou em runtime observado, sempre com data, comando ou URL e saída registrada |
| CORROBORADO | Duas ou mais evidências independentes, ao menos uma primária |
| INFERÊNCIA | Dedução a partir do código, sem observação de runtime |
| LACUNA DE RUNTIME | Depende de KV, secret ou estado de produção não inspecionado. Vira pendência de verificação, nunca afirmação |

A análise de código vale para o bundle implantado (`v4.9.182.js`, confirmado pelo health). Valores de KV, secrets e estado runtime não foram integralmente inspecionados, as exceções estão marcadas.

## 3. Rubrica de severidade

Dimensões avaliadas por achado: impacto financeiro/operacional, exposição ao usuário, abrangência, recorrência, detectabilidade, existência de workaround, confiança da evidência.

| Nível | Definição |
|---|---|
| P0 | Dado decisório incorreto, indisponibilidade crítica ou exposição grave ativa, com necessidade de contenção imediata. Ausência de workaround agrava a severidade, mas não é condição obrigatória |
| P1 | Falha de integridade ou operação com workaround ou detecção tardia |
| P2 | Risco latente com gatilho plausível |
| P3 | Higiene, melhoria, dívida sem gatilho ativo |

P0 ativo em produção exige recomendação de contenção imediata dentro do relatório, sem executar nada sem autorização.

## 4. Registro canônico de achados

### Família CAL — Calendário de resultados

---

**CAL-001 — Data estimada exibida como AGENDADO, e como evento sem ressalva**
Severidade: P1. Certeza: COMPROVADO. Status: aberto.

Evidência:
1. A camada de dados rotula honestamente. Todas as entradas 2T26 de `CALENDARIO_RESULTADOS_V1` (`api/v4.9.182.js:3828` em diante) carregam `status: "estimado"`, `fonte: "estimado_historico"` e `nota: "Data estimada com base em padrao historico. Confirmar no RI."` (ex.: Petrobras `:3838`, Bradesco `:3854`).
2. A UI descarta o rótulo. `app/index.html:4869`: `var statusLbl = prox.status === "divulgado" ? "DIVULGADO" : "AGENDADO";`. Tudo que não é "divulgado" vira AGENDADO, inclusive "estimado". A nota nunca é exibida.
3. A agenda descarta os dois campos. `agendaBuildPersistir` (`api/v4.9.182.js:10989-11001`) monta o evento com `titulo: "<periodo> - divulgacao de resultado"` e não copia `status` nem `nota`. O feed `agenda:eventos` apresenta estimativa como fato.
4. O endpoint `op=calendario` (`:15608-15621`) entrega o status correto ao cliente, o defeito é de apresentação, nos dois consumidores.

Impacto: usuário de um radar de crédito lê selo de certeza que o sistema não tem, para as datas de resultado dos 20 emissores cobertos, hoje 100% estimadas no 2T26. Mesma família do card "Cobertura 62%" e do `buscas=N` (DATA-001).
Workaround: inexistente para o usuário, a informação de que é estimativa não chega à tela.
Correção proposta: exibir ESTIMADO quando `status === "estimado"` (com a nota em tooltip ou texto) e propagar `status`/`nota` nos eventos da agenda. Guarda: check de veracidade de UI cobrindo mapeamento status→rótulo (extensão do `audit-ui-metrics.mjs`).
Critério de aceite: nenhum caminho de exibição descarta `status`; trimestre estimado nunca renderiza AGENDADO.
Escalação: a condição se materializou em 28/07 com as divergências confirmadas de Bradesco e Vale, ver CAL-002 (P0). A contenção de lá inclui o rótulo daqui.

---

**CAL-002 — Datas 2T26 de Bradesco e Vale divergem da fonte oficial, e o dashboard exibe as erradas com selo de certeza**
Severidade: **P0 ativo**. Certeza: COMPROVADO por fonte oficial primária, consultada em 2026-07-28T08:00Z (05:00 BRT). Status: aberto, contenção recomendada.

**Bradesco.** O sistema registra 2T26 em 2026-07-28 (`api/v4.9.182.js:3852-3855`, `status: "estimado"`, `fonte: "estimado_historico"`), e a UI exibe isso como AGENDADO para hoje (CAL-001). O RI oficial informa outra data. Agenda 2T26 em `https://www.bradescori.com.br/informacoes-ao-mercado/agenda-2t26/` (HTTP 200, 66789 bytes, capturada com `curl.exe -sL`), tabela da página:

| Evento | Data | Horário |
|---|---|---|
| Período de Silêncio | 22/07/2026 a 05/08/2026 | — |
| Divulgação de Resultados | **05/08/2026** | Após o fechamento dos mercados, B3 e NYSE |
| Videoconferência | 06/08/2026 | 10h30 (horário de Brasília) |

Divergência de 8 dias. Agravante: a data que o sistema exibe como AGENDADO cai dentro do período de silêncio declarado pelo próprio banco, ou seja o dashboard afirma divulgação para um dia em que a companhia está formalmente impedida de divulgar.

**Vale.** O sistema registra 2T26 em 2026-07-24 (`:3840-3843`, estimado), data já vencida, e a UI exibe "Última divulgação 2T26: 24/07/2026" (CAL-001), afirmando como fato consumado um resultado que ainda não saiu. Comunicado oficial em `https://vale.com/pt/w/vale-divulga-as-datas-para-o-relatorio-de-desempenho-no-2t26` (capturado no mesmo horário): "Divulgação dos resultados do 2T26: Data: 30 de julho de 2026 (quinta-feira), Horário: Após o fechamento do mercado". O mesmo comunicado traz "Relatório de produção e vendas do 2T26: Data: 21 de julho de 2026 (terça-feira), Após o fechamento", evento distinto que não é o resultado financeiro e provavelmente é a origem da confusão de datas.

**Petrobras** segue explicitamente não confirmada: o sistema exibe 28/07 como AGENDADO, nenhuma fonte primária reproduzível foi obtida nesta sessão, e o item permanece como pendência de validação dentro deste ID, sem afirmação em nenhuma direção.

Impacto: usuário de radar de crédito recebe data errada de resultado de dois emissores sistêmicos com selo de agendamento, no início da temporada. Uma das datas é impossível pelo próprio calendário do emissor. Nenhum workaround: a informação de que é estimativa não chega à tela.

Contenção imediata recomendada (nenhuma executada, tudo Gate C):
1. Corrigir as duas datas via override de KV com `fonte` primária e `status: "agendado"`, Bradesco 05/08 e Vale 30/07. Depende de CAL-003, hoje o override não alcança o selo da UI.
2. Enquanto CAL-003 não sai, alternativa de menor superfície: corrigir as duas entradas na base do bundle e redeployar.
3. Rotular Petrobras e as demais estimativas como ESTIMADO (CAL-001), que remove o selo falso de todas de uma vez.

Correção estrutural: revalidação do 2T26 inteiro pela hierarquia do relatório 02, ver CAL-004.
Critério de aceite: Bradesco 05/08 e Vale 30/07 no sistema com `fonte` primária e `status` correto; Petrobras confirmada por fonte primária ou exibida como estimativa; nenhuma data exibida com selo de certeza sem fonte oficial.

---

**CAL-003 — Dois caminhos de leitura do calendário, o selo da UI ignora overrides**
Severidade: P2. Certeza: COMPROVADO. Status: aberto.

Evidência: existe mecanismo de override em KV (`calendario:overrides:v1`, `api/v4.9.182.js:3941`) com escrita via endpoint admin (`:16470`) e rebuild da agenda em `waitUntil` (`:16665`). O `agendaBuildPersistir` lê o merge base+overrides (`:10979-10982`). Mas `obterCalendarioEmpresa` (`:3918-3940`), que alimenta o endpoint `op=calendario` (`:15611`) e portanto o selo "Próxima divulgação" da UI, lê somente o `CALENDARIO_RESULTADOS_V1` hardcoded.
Impacto: uma correção de data feita pelo admin atualiza a agenda de eventos e não atualiza o selo. Os dois caminhos divergem em silêncio, ninguém é avisado.
Correção proposta: unificar a leitura, `op=calendario` passa a usar a variante merged (async) com os overrides.
Critério de aceite: salvar um override e observar o mesmo valor em `op=calendario` e na agenda, sem redeploy.

---

**CAL-004 — Calendário congelado, cobertura 20/103, fontes secundárias, staleness sem consumidor**
Severidade: P2. Certeza: COMPROVADO. Status: aberto.

Evidência: `ultima_atualizacao: "2026-05-09"` (`api/v4.9.182.js:3830`), 80 dias até hoje. `fontes_validacao` são InfoMoney e MoneyTimes (`:3831-3834`), portais secundários, nenhuma fonte primária (RI/CVM/B3). Cobertura: 20 emissores com `trimestres` no bundle, de 103 (`grep -o 'trimestres: \[' api/v4.9.182.js | wc -l` → 20). A ferramenta de staleness existe (`listarEmissoresCalendarioStale`, `:3991`) mas só é exposta em endpoint admin sob demanda (`:16463`), nenhuma rotina ou alerta a consome.
Impacto: o 2T26 inteiro é estimativa de maio, e nada força atualização nem avisa que envelheceu. CAL-002 mostra a taxa de erro dessa extrapolação: das duas datas checadas contra fonte oficial, duas estavam erradas, uma delas caindo dentro do período de silêncio do emissor.
Correção proposta: rotina de atualização com a hierarquia de fontes do relatório 02, e o monitor diário passando a ler o staleness. Guarda: alerta quando `ultima_atualizacao` ou override mais recente passar de N dias.
Critério de aceite: staleness visível em canal monitorado, e calendário 2T26 com fontes primárias ou status honesto.

### Família VOL — Volatilidade, Merton e taxas

---

**VOL-001 — Campo `market_cap` carrega preço por ação, guarda de consumo invertida**
Severidade: P2. Certeza: COMPROVADO. Status: aberto.

Evidência:
1. Produção do dado. `scripts/upload_volatilidade_kv.ps1:56-66`: `$mktCap = $regularMarketPrice # preço; market cap real = preço x shares outstanding`. O comentário do próprio script admite a semântica errada. O campo sobe ao KV `cotacoes:volatilidade:v1` como `market_cap` (`:73`).
2. Consumo. `api/v4.9.182.js:13326`: o pipeline preditivo só aceita `volData.market_cap` se `> 100`. A guarda rejeita preços típicos, mas aceitaria exatamente os valores errados: um papel acima de R$ 100 injetaria preço como market cap.
3. Estado atual da base: nenhuma série tem `regularMarketPrice` de 3 dígitos (`grep` por `"regularMarketPrice":\s*[0-9]{3,}` em `data/cotacoes/series/` → vazio, 2026-07-28). Hoje o campo é 100% descartado.
4. Fallback real: `fundamentals:altman:latest` não tem `market_cap` (campos por empresa em `scripts/predictive/fundamentals_altman_latest.json`: z_em, x1..x4, ativo_total, patrimônio_liquido, divida_cp, divida_lp, dt_refer, cnpj). O Merton (`calcMertonDD`, chamada em `:13331`) roda com `patrimônio_liquido` contábil como E, com volatilidade de mercado como sigma_E.

Impacto: hoje, semântica híbrida não documentada no Merton (E contábil, vol de mercado). Latente: primeiro papel acima de R$ 100 na base injeta E de dezenas de reais contra dívida de bilhões, DD despenca e o driver `merton` dispara falso. Exposição limitada: `op=predictive_v1` é lab interno atrás de auth admin (`:15641-15647`), não user-facing.
Correção proposta: ou popular market cap real (preço × shares outstanding, com `as_of` e fonte) ou remover o campo do payload. Eliminar a guarda mágica `> 100`. Documentar no contrato qual E o Merton usa.
Critério de aceite: nenhum campo com nome que não corresponde ao conteúdo; Merton com E definido em contrato e teste cobrindo papel hipotético acima de R$ 100.

---

**VOL-002 — Estimador de volatilidade é RMS não centralizado, contrato não define qual deveria ser**
Severidade: P3. Certeza: COMPROVADO. Status: aberto.

Evidência: `scripts/collect_cotacoes.ps1:160` (e cópia no caminho de cache, `:67`): `sqrt(soma(r²)/n)` sobre log-retornos, anualizado por `sqrt(252)`. É RMS dos retornos com divisor n, não desvio-padrão dos retornos centralizados com n-1.
O cálculo usa RMS dos retornos, não desvio-padrão dos retornos centralizados; é necessário confirmar qual estimador o contrato promete. RMS não é automaticamente inválido: para retornos diários a média é próxima de zero e a diferença é da ordem do quadrado da média diária, desprezível na prática, e RMS de média zero é prática aceita em risco de mercado. Nenhum lugar do bundle ou do payload promete "desvio-padrão" para `vol_anualizada` (grep por desvio/stddev no bundle só encontra o campo ANBIMA, `:11689`, contexto distinto).
Risco real: a fórmula está duplicada em dois caminhos do mesmo script e pode divergir em manutenção, e o contrato silencioso deixa o consumidor (Merton) sem saber o que recebe.
Correção proposta: declarar o estimador no schema do payload (`schema_v`) e unificar a função nos dois caminhos.
Critério de aceite: contrato documenta o estimador; uma única implementação.

---

**VOL-003 — SELIC hardcoded, sem `as_of`, defasada contra o BCB e com contradição interna no próprio bundle**
Severidade: P2. Certeza: COMPROVADO, incluindo o erro factual, demonstrado contra fonte oficial primária nesta sessão. Status: aberto.

Evidência: `scripts/upload_volatilidade_kv.ps1:78-79`: comentário "Selic atual ~13.75% (jul/2026), pode ser atualizado via BCB API" e `$selicAnual = 0.1375`. Fallback idêntico no bundle: `api/v4.9.182.js:13271`. O payload leva `selic_anual` sem `as_of` nem fonte. No mesmo bundle, a descrição do GPA (`:12836`) afirma "Dívida R$4bi com SELIC a 15%".
Taxa aplicável, consultada na API oficial do BCB em 2026-07-28T07:52Z (04:52 BRT):

```
curl.exe -s "https://api.bcb.gov.br/dados/serie/bcdata.sgs.432/dados/ultimos/1?formato=json"
[{"data":"05/08/2026","valor":"14.25"}]
curl.exe -s "https://api.bcb.gov.br/dados/serie/bcdata.sgs.1178/dados/ultimos/1?formato=json"
[{"data":"27/07/2026","valor":"14.15"}]
```

Meta SELIC vigente 14,25% a.a., efetiva anualizada 14,15% a.a. O hardcode de 13,75% está 40 a 50 bps abaixo de qualquer leitura aplicável, e a narrativa "SELIC a 15%" está 75 bps acima. As duas SELICs internas estão erradas em direções opostas, o que é a prova cabal de que constante sem `as_of` não sobrevive a um ciclo de política monetária. Efeito no Merton: taxa livre de risco subestimada reduz o drift, reduz DD e superestima PD, viés conservador de magnitude pequena. As duas séries do BCB foram usadas aqui como evidência de defasagem, não como prescrição, a escolha da série é DEC-001.
Correção proposta: depende de DEC-001. Depois da decisão, buscar da fonte oficial com `as_of` no payload, e o fallback do bundle passa a carregar `as_of` e alerta de obsolescência quando usado.
Critério de aceite: `selic_anual` com `as_of` e fonte; contradições internas eliminadas; fallback loga quando ativado.

---

**DEC-001 — Decisão de produto pendente: o que "SELIC" significa no VIX Radar**
Tipo: decisão, bloqueia a correção definitiva de VOL-003. Status: pendente.

Meta vigente do COPOM, taxa efetiva anualizada base 252, ou outra referência (CDI). Só depois dessa definição se escolhe a série do BCB (SGS 432, 1178 ou outra). Nenhuma série é prescrita neste relatório.

### Família OPS — Rotinas locais

---

**OPS-001 — Métrica de cobertura autodeclarada pelo modelo, falha total vira indicador verde**
Severidade: P1. Certeza: COMPROVADO. Status: aberto, já rastreado em PENDENCIAS (item P1 da matinal, com plano de 4 ações).

Evidência: o prompt da matinal pede ao modelo a última linha `LOTE_RESUMO|buscas=<total de buscas executadas>` (`scripts/run_vixradar_matinal_claude.ps1:435` no worktree atual; o arquivo tem 22 linhas não commitadas e PENDENCIAS cita a linha 421 da versão anterior). O script conta o que o medido declarou. Incidente real de 27/07 13:32: 18 emissores gravados em produção com 0 das buscas executadas, `buscas=12` autodeclarado, `submit_fail=0 auth_fail=0 silent_fail=0`, 3 CRITICOs, o verificador adversarial retratou 4 dos 5 eventos da fila. Detalhe completo em `Obsidian VIX Radar/PENDENCIAS.md` e nota 69.
Impacto: a rotina não mede o que declara medir. Qualquer degradação do WebSearch repete o padrão.
Correção proposta (a de PENDENCIAS, referenciada, não recontada): pre-flight de ambiente, probe de WebSearch, contar `fontes_consultadas[].resultado` que não casam com padrão de falha, e `-Force` para dia envenenado.
Critério de aceite: o de PENDENCIAS (aborto antes do primeiro submit com Haiku inválido, `submit_ok=0`).

---

**OPS-002 — Orquestrador da coleta de volatilidade não propaga falha do processo filho**
Severidade: P2. Certeza: COMPROVADO. Status: aberto, item novo.

Evidência: `scripts/run_coleta_volatilidade.ps1:28-44`. As duas etapas chamam filho via `& powershell.exe ... 2>&1` dentro de `try/catch`. Falha do filho (parse, crash) não lança exceção no pai, o `catch` nunca dispara. O `Select-String "Sucesso: (\d+)"` simplesmente não casa, o log grava `Coletor: sucesso=` vazio e o script segue para o upload e termina com "FIM" e exit 0. `$LASTEXITCODE` é ignorado nas duas etapas, sendo que o coletor tem código próprio de cobertura baixa (`collect_cotacoes.ps1:206-208`, exit 2) que ninguém lê. A nota 70 documenta o quase-incidente de 27/07 17h00 exatamente por este buraco.
Impacto: coleta parada ou parcial passa como sucesso, o Merton e a volatilidade do pipeline degradam sem sinal. A cobertura corrente já é 73/103 com 21 falhas de fetch (`data/cotacoes/meta_volatilidade.json` de 27/07 17:02: `total_listados: 94, sucesso: 73, falha: 21`) e nada alerta.
Correção proposta: checar `$LASTEXITCODE` após cada filho, abortar a etapa 2 se a 1 falhou, sair com exit próprio não-zero, e o monitor diário passar a tratar esse exit. Guarda: teste simulando falha de parse do filho.
Critério de aceite: filho quebrado leva a rotina a exit não-zero sem executar upload, e o monitor reporta como erro.

---

**OPS-003 — Trava de idempotência sem saída para dia envenenado**
Severidade: P2. Certeza: COMPROVADO. Status: aberto, já rastreado (ação 4 do item P1 da matinal em PENDENCIAS).

Evidência: `scripts/run_vixradar_matinal_claude.ps1:541-554` (worktree), lista de "já processados" montada das linhas `OK|` do log do próprio dia. Execução ruim marca emissores como feitos, reprocessar exige renomear log na mão, foi a remediação real de 27/07.
Correção e aceite: os de PENDENCIAS (`-Force` ou marcador de cobertura efetiva nas linhas `OK|`).

---

**OPS-004 — Monitor de tasks inventa causa de falha pelo nome da task e rebaixa erro a warning**
Severidade: P2. Certeza: COMPROVADO. Status: aberto, já rastreado em PENDENCIAS.

Evidência: `scripts/monitor-tasks.ps1:158-161` (arquivo sem modificações locais): `exit 1` + nome `VIXRadar-AgendaSemanal` recebe `reason = 'Credit balance too low (assinatura Claude Code)'` e vai para warnings, sem ler stderr, log ou qualquer fonte. Caso real 27/07: falha por roteamento DeepSeek reportada como problema de crédito.
Correção e aceite: os de PENDENCIAS (ler log/stderr real, senão "exit 1 sem causa identificada" como ERRO).

---

**OPS-005 — `exit` em vez de `return` nos scripts de rotina**
Severidade: P3. Certeza: CORROBORADO (nota 69, 7 pontos em `run_vixradar_verificacao_async.ps1`). Status: aberto.

O arquivo está hoje com 199 linhas não commitadas de trabalho em curso, reverificar a contagem quando esse trabalho fechar. Regra do CLAUDE.md global.

### Família CI — GitHub Actions

---

**CI-001 — Secret ausente encerra os workflows de vigilância com sucesso, por design declarado**
Severidade: P2. Certeza: COMPROVADO. Status: aberto.

Evidência: os caminhos de secret ausente nos workflows identificados terminam com sucesso. `.github/workflows/scan-emergencia.yml:53-59` (ADMIN_PASSWORD ausente → warning + exit 0) com a política escrita no cabeçalho, linha 20: "Faltando QUALQUER secret → aviso + exit 0 (nunca falha por secret ausente)". `.github/workflows/frescor-check.yml:39-44` (mesmo padrão). Passo 2 do scan sai limpo se `ANTHROPIC_API_KEY`/`ROUTINE_API_KEY` faltarem (`:125`). Leitura feita no worktree, que tem 14 linhas não commitadas por arquivo (acréscimo de `.erro` e http_status na saída jq), o fail-open permanece nas duas versões.
Impacto: o paraquedas e o vigia podem ficar mudos indefinidamente sem nenhum vermelho. É decisão de projeto documentada, não acidente, mas o custo dela já se materializou (24 a 27/07).
Correção proposta: revisitar a política. Em runs agendadas, secret obrigatório ausente deveria falhar o job ou abrir issue automática; exit 0 silencioso só faz sentido no `workflow_dispatch` com input manual.
Critério de aceite: run agendada sem secret termina vermelha ou gera notificação rastreável.

---

**CI-002 — Scan de emergência sai limpo quando o health responde `ok:false`, paraquedas mudo**
Severidade: P2. Certeza: COMPROVADO, com caso real. Status: aberto.

Evidência: `.github/workflows/scan-emergencia.yml:81-86`: `ok:false` → warning "Saindo limpo" + exit 0. Foi o mecanismo que silenciou a varredura de emergência entre 24 e 27/07 (senha rotacionada só no Cloudflare, PENDENCIAS documenta as runs 41 a 44 falhando e a 45 verde após o secret atualizado). O `frescor-check.yml:88-92` já trata o mesmo caso como `::error` + exit 1, a assimetria é só do scan.
Correção proposta: `ok:false` é auth quebrada, não "nada a fazer": exit 1 no scan também.
Critério de aceite: senha errada leva o scan a run vermelha.

---

**CI-003 — Rotação multi-destino com verificação parcial, resíduo do incidente de 24/07**
Severidade: P3 residual. Certeza: COMPROVADO. Status: parcialmente corrigido.

Evidência: a rotação de 24/07 (`dfa6854`, 06:10 BRT) atualizou secret no Cloudflare e quebrou dois destinos não cobertos: o secret do GitHub Actions (frescor mudo até 27/07 16h45) e o `ADMIN_EMAIL` (SEC-001). Guardas aplicadas em 27/07: `admin_email_ok` no health (SECRETMISS1, no ar em v4.9.182, verificado ao vivo nesta sessão), passo [7/8] de verificação de secrets na rotação, e a guarda de `fdae5cb` (17:00 BRT). O passo GitHub segue manual: `scripts/apply-security-rotation.ps1:100-113` pede confirmação via `Read-Host`, sem verificação pós-fato do lado GitHub.
Correção proposta: automatizar (`gh secret set` quando PAT disponível) ou ao menos verificar via API após confirmação.
Critério de aceite: rotação só conclui com os três destinos comprovados consistentes.

### Família SEC — Segurança e notificações

---

**SEC-001 — `ADMIN_EMAIL` ausente por 3 dias, cadastros sem notificação e JWT sem role admin**
Severidade: resolvido 27/07 18h01, com guardas 19h57. Certeza: COMPROVADO (health desta sessão retorna `admin_email_ok:true`). Status: fechado, validação final pendente (próximo cadastro real sem `registrar_email_admin_erro`).

Registrado para rastreabilidade, detalhe completo em PENDENCIAS. Causa raiz compartilhada com CI-003.

---

**SEC-002 — Cadastro de conta existente responde "aguarde aprovação" e não notifica ninguém**
Severidade: P2. Certeza: COMPROVADO (telemetria + código, diagnóstico de 27/07). Status: aberto, já rastreado em PENDENCIAS.

`handleRegistrar` retorna antes das notificações quando o e-mail já existe. Correção e nota de segurança (enumeração de usuários) em PENDENCIAS, referenciadas, não recontadas.

---

**SEC-003 — WhatsApp sem StatusCallback, HTTP 201 tratado como prova de entrega**
Severidade: P2. Certeza: COMPROVADO (código). Status: aberto, já rastreado em PENDENCIAS (item de 27/07 20h30, ainda não commitado no momento desta auditoria).

`enviarWhatsAppAdmin` (`api/v4.9.182.js:5505`, payload sem `StatusCallback` na `:5529`, verificado por leitura direta nesta sessão) e `enviarAlertaAdminWhatsApp` (`:5553`), telemetria grava aceite na `:5541`, não entrega. Plano de duas etapas em PENDENCIAS. Validação no console Twilio: LACUNA DE RUNTIME.

### Família ENC — Encoding e compatibilidade

---

**ENC-001 — Scripts PS7 executados pelo PowerShell 5.1, deploy quebrado e quase-falha da coleta**
Severidade: resolvido 27/07 com guarda. Certeza: COMPROVADO (nota 70, commits `642e599`, `184f53a`, `cc2a589`). Status: fechado com resíduos P3.

Guarda: `scripts/lint-encoding.ps1` reprova pelo parser do 5.1, ligado ao pre-commit (`scripts/hooks/` + `install-hooks.ps1`). Resíduos documentados na nota 70: repo Site sem a guarda, `_archive/` fora da varredura, editor que remove BOM não identificado, senha antiga no histórico do git.

### Família DATA — Causa sistêmica

---

**DATA-001 — O contrato de dados não carrega proveniência nem confiança, rótulo e fonte se descolam sem acusar**
Tipo: causa transversal. Certeza: COMPROVADO por acumulação de instâncias. Status: aberto, é o critério do plano de correção.

Instâncias verificadas: selo AGENDADO sobre estimativa (CAL-001) que já entregou data errada de dois emissores sistêmicos (CAL-002), `buscas=N` autodeclarado (OPS-001), HTTP 201 como entrega (SEC-003), causa de falha deduzida do nome da task (OPS-004), `market_cap` que é preço (VOL-001), SELIC sem `as_of` defasada em 40 a 50 bps (VOL-003), card "Cobertura 62%" (corrigido 27/07), exit 0 do detector lido como "UI coerente" (nota 69). Vale acrescentar o próprio health desta auditoria: HTTP 200 com autorreporte de bindings é a mesma classe de sinal, e por isso a seção 6 delimita o que ele não prova.
Princípio, formulado na nota 69 e adotado aqui como critério: toda métrica exibida ou registrada precisa ter fonte apurada. Se o número vem de autodeclaração, de nome de objeto ou de constante, é legenda, não métrica.
Aplicação: cada correção do relatório 04 fecha com proveniência (`fonte`, `as_of`) e guarda que meça a distância entre o nome e a fonte.

## 5. Auditoria sistêmica por camada

| Camada | Estado | Base | Achados |
|---|---|---|---|
| Worker (runtime) | Responde e se autorreporta saudável (limites na seção 6) | Health desta sessão | — |
| Worker (código) | Saudável com defeitos de veracidade | Bundle v4.9.182 lido por trechos dirigidos | CAL-001/003/004, VOL-001/003, SEC-002/003 |
| Frontend | Sincronizado (nota 69), exibindo data errada com selo de certeza | `app/index.html` + fontes oficiais | CAL-001, CAL-002 |
| Dados e pipeline preditivo | Lab interno protegido por auth, contratos frouxos, uma constante comprovadamente defasada | Scripts + KV payloads gerados + BCB | VOL-001/002/003, OPS-002, DATA-001 |
| Rotinas locais | Funcionais, guardas pendentes | Scripts + PENDENCIAS + notas 69/70 | OPS-001..005 |
| CI (GitHub Actions) | Fail-open por design | Workflows no worktree | CI-001/002/003 |
| Segurança | Guardas novas no ar, resíduos rastreados | Health + PENDENCIAS + rotação | SEC-001..003, CI-003 |
| Governança/vault | Consistente, contradições de entrega WhatsApp já apontadas no item preexistente | Notas 69/70, PENDENCIAS | — |

## 6. Verificado e OK nesta sessão

Health ao vivo, executado em 2026-07-28T07:27:28Z (04:27 BRT):

```
curl.exe -s https://radar-credito-api.prospects-intel.workers.dev -w "\nHTTP:%{http_code} TEMPO:%{time_total}s"
{"ok":true,"versao":"v4.9.182","ts":"2026-07-28T07:27:28.034Z","bindings":{"kv":true,"rate_limiter":true,"telemetria":true},"providers_configurados":"2/2","admin_email_ok":true,"verificador_ok":true}
HTTP:200 TEMPO:0.750865s
```

**O que esse health prova, e o que não prova.** Prova: o endpoint responde HTTP 200 em 0,75s, se identifica como `v4.9.182`, e o próprio Worker reporta seus bindings (KV, rate limiter, telemetria), 2 de 2 providers configurados, `admin_email_ok` e `verificador_ok`. Não prova: identidade byte a byte entre o bundle local e o implantado, entrega real de e-mail pelo Resend, funcionamento do Twilio, estado dos GitHub Actions, nem correção ponta a ponta de qualquer fluxo de dados. Autorreporte de configuração não é teste funcional, e nenhum achado deste registro foi encerrado com base nele.

Zero referências a Firestore no repositório auditado: `grep -ril "firestore" .` (raiz do projeto, incluindo históricos) retornou vazio em 2026-07-28.

Consistência de versão declarada: `api/wrangler.toml:469` com `main = "v4.9.182.js"`, igual ao `versao` que o health reporta. Isso alinha declaração e autorreporte, não estabelece identidade de conteúdo. Comparação direta repo × Cloudflare não é método válido (o wrangler empacota no deploy), a checagem defensável seria `--dry-run`, não executada aqui.

Corroborado pela nota 69 (auditoria de 27/07, não re-executado nesta sessão): bindings declarados e vivos, zero floating promises, `ctx.waitUntil` com catch, zero secrets hardcoded, model IDs pinados, CSS `strong` sem cor global, headers de segurança, sync `app/index.html` × `deploy_zip`.

## 7. Lacunas desta auditoria

1. Valores reais de KV (estado semanal, `calendario:overrides:v1`, conteúdo efetivo de `cotacoes:volatilidade:v1`) não inspecionados. LACUNA DE RUNTIME. Existe caminho de leitura admin, exige autorização própria.
2. Consulta externa realizada e registrada com URL, horário e saída: BCB (VOL-003), agenda 2T26 do RI do Bradesco e comunicado oficial da Vale (CAL-002). Ressalva de método: a primeira tentativa no Bradesco usou a URL genérica de calendário de eventos, que é renderizada por JavaScript e não traz o dado no HTML estático; a página correta é a agenda do trimestre (`/informacoes-ao-mercado/agenda-2t26/`), cuja tabela vem no HTML. Petrobras não teve fonte primária obtida e permanece explicitamente não confirmada dentro de CAL-002. CVM e B3 não foram consultadas, as duas confirmações vieram do primeiro nível da hierarquia (RI da companhia), o que basta pela regra do relatório 02.
3. Runs do GitHub Actions não consultadas nesta sessão (sem acesso local ao GitHub; o PAT read-only citado em PENDENCIAS não foi utilizado aqui). Estado das runs de 28/07: não verificado.
4. Console Twilio (status real de entrega das mensagens) não acessado, permanece a validação pendente de SEC-003.
5. Leitura exaustiva das 16k linhas do bundle não realizada, varredura dirigida por grep e leitura de trechos. Acessibilidade e métricas de performance de campo (LCP/INP) seguem não medidas, como na nota 69.
6. Os arquivos `scripts/run_vixradar_*.ps1`, workflows e `api/tools/*` têm modificações não commitadas de outro fluxo de trabalho. A evidência citada indica a numeração do worktree atual, com a divergência anotada onde relevante.

## 8. Estado do worktree no momento da auditoria

`git status` capturado antes de qualquer escrita desta entrega (snapshot em scratchpad da sessão): 83 arquivos modificados. Caracterização: (a) `data/cotacoes/**` (75 arquivos), artefatos da coleta de 27/07 17h02; (b) trabalho em curso não commitado em `scripts/run_vixradar_{matinal,noturno,verificacao_async}.ps1` (+22/+31/+199 linhas), `.github/workflows/*.yml` (+14 cada), `api/tools/*.ps1` (+27); (c) vault: `PENDENCIAS.md` (+46/-1, item WhatsApp de 27/07 20h30) e `03 - Estado Atual.md` (4 linhas).

Nada disso é desta entrega. Esta auditoria escreve exatamente 8 caminhos documentais, sendo 6 arquivos novos (os 5 relatórios `00..04` na raiz mais a nota `71` no vault) e 2 arquivos existentes modificados (uma linha no `00 - Índice (MOC).md` e uma seção aditiva ao final de `PENDENCIAS.md`). Commit, push e PR dependem de autorização separada (Gate B), com staging seletivo validado por allowlist e por inspeção de conteúdo de `git diff --cached -- "Obsidian VIX Radar/PENDENCIAS.md"`.

---

Relatórios complementares: `01-MAPA-FLUXO-DADOS.md`, `02-MATRIZ-FONTES-CONFIABILIDADE.md`, `03-RELATORIO-CALENDARIO-RESULTADOS.md`, `04-PLANO-CORRECAO-PRIORIZADO.md`. Nota de sessão: `Obsidian VIX Radar/71 - Auditoria Tecnica Completa 2026-07-28.md`.
