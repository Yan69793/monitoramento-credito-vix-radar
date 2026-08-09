---
data: 2026-08-09
tipo: changelog
tags: [vix-radar, changelog, incidentes, deploys]
status: ativo
---

# Changelog — VIX Radar

Registro cronológico de incidentes, deploys e eventos de produção. Cobertura: julho-agosto 2026. Para histórico anterior: [[_Arquivo/historico-03-2026-06]].

---

> [!success] 09/08 21h18 — **LEGALCVM1+LEGALSHARE1 v202.6. Citação CVM revogada e seção de compartilhamento de dados incompleta na Política de Privacidade.**
> **Status:** resolvido, deploy validado em produção. CNPJ segue como pendência aberta, ver final da entrada
> **Data da Versão:** 2026-08-09
> **Origem do Registro:** pedido do usuário para atualizar a documentação do projeto, incluindo leis, CVM e LGPD. Levantamento cobriu `app/index.html`, `api/src/worker.js`, `docs/`, o vault Obsidian inteiro e o site oficial da CVM (`conteudo.cvm.gov.br`)
> **Condição de Obsolescência:** perde validade se a Resolução CVM 20/2021 for revogada ou substituída, ou se Twilio/Sentry saírem da stack do Worker sem a Política de Privacidade ser atualizada junto
>
> Pedido amplo do usuário, "atualizar a documentação, como usar, e tudo mais que for necessário de documentação de leis, CVM, LGPD". O site já tinha uma base jurídica bem mais completa do que uma auditoria rápida sugeriria, Política de Privacidade e Termos de Uso inteiros, Aviso Legal, disclaimer financeiro fixo, cookie banner, tudo embutido como modal dentro do próprio `index.html`, datado de 13 de abril. O problema não era ausência, era desatualização pontual em três pontos.
>
> O Aviso Legal do guia-overlay (Configurações → Sobre → Documentação) citava a Instrução CVM nº 598/2018 para justificar que o sistema não faz análise de valores mobiliários. Fui conferir direto em `conteudo.cvm.gov.br`, a própria página da CVM para essa instrução tem o título "Instrução CVM 598 (Revogada)" e o texto "REVOGADA pela Resolução 20/21". A Resolução CVM nº 20/2021 é quem rege hoje a atividade de analista de valores mobiliários, citando a própria revogação da 598 na ementa. A citação estava errada desde que foi escrita, não venceu agora.
>
> A Seção 5 (Compartilhamento de Dados) da Política de Privacidade só citava Anthropic e Resend.com. Dois processadores reais de dado pessoal não estavam lá. A Twilio, que dispara WhatsApp para o admin a cada cadastro novo com nome, e-mail e empresa do usuário no corpo da mensagem (`enviarWhatsAppAdmin` em `worker.js`), e o Sentry, monitoramento de erro adicionado depois de abril (SENTRY1/SENTRY-PII1), que embora bem configurado tecnicamente, sem captura de usuário, cookie, corpo de requisição ou header (`dataCollection` com tudo `false` e override de `maxRequestBodySize:"none"`), simplesmente não aparecia no texto. Acrescentei os dois parágrafos e ajustei a Seção 9 (Transferência Internacional) para ficar consistente, sem isso o próprio documento contradiria a si mesmo entre duas seções vizinhas.
>
> Achado à parte, não incluído nesta correção. Termos de Uso e Política de Privacidade identificam a controladora só como "Szuchmacher Consultoria Ltda.", sem CNPJ. Achei o número, 49.463.402/0001-11, em dois documentos do próprio registro no INPI dentro do repo (`docs/archived/declaracaoVeracidade_INPI.pdf` e `GRU_730_INPI_Registro_Software.pdf`) e conferi pessoalmente o PDF da declaração, o número bate. Mesmo assim, é dado sensível indo para texto público, perguntei ao usuário se podia incluir e não tive resposta nesta sessão. Optei por não inserir, fica pendente, número já localizado para confirmação rápida quando o usuário quiser.
>
> Correção publicada em v202.6 (commits `c0b50d9`, `d47798a`, `b87d81a`), gates de deploy verdes incluindo o 3.4 que valida as rotas de acesso ao admin, verificação em produção em dois níveis, bytes do HTML publicado e texto renderizado dentro dos modais via `abrirLgpd('privacidade')` e `toggleGuia()`. Health check limpo (`ok:true`, `kv:true`, `telemetria:true`, `sentry_ok:true`).
>
> Junto, seis arquivos técnicos em `docs/` (`HANDOFF.md`, `ARQUITETURA.md`, `DEPLOY-CHECKLIST.md`, `workflow.md`, `design-system.md`, `DEVELOPMENT.md`) parados há semanas, alguns citando um `radar-standalone-worker.js` que não existe mais, ganharam um aviso de topo apontando para `README.md` e este vault como fonte atual, no mesmo padrão já usado em `docs/archived/CLAUDE.md`. Conteúdo antigo preservado abaixo do aviso em cada um, nada foi apagado (commit `9152779`).

---

> [!success] 09/08 17h23 — **ADMINMSG1 v202.5. Mensagem de erro do login admin era invisível.**
> **Status:** resolvido, deploy validado em produção
> **Data da Versão:** 2026-08-09
> **Origem do Registro:** teste ao vivo em vixradar.com com senha deliberadamente falsa, nunca a senha real do usuário. Achado durante a verificação de campo do ADMINROUTE1, ver entrada abaixo
> **Condição de Obsolescência:** perde validade se `adminAutenticar()` sair do script inline de `app/index.html` ou se o CSS `.admin-msg` mudar de mecanismo de visibilidade
>
> Depois do ADMINROUTE1 (entrada abaixo) o atalho já abria o overlay com o portão de senha. O usuário digitou a senha, apertou Enter, "nada aconteceu", sem mensagem, sem o painel abrir. Reproduzi com senha de teste propositalmente errada, o Worker respondeu certo, `ok:false`, `erro:"Acesso negado."`, o backend nunca teve problema. O bug era só na tela.
>
> Em `adminAutenticar()`, a linha `n.className="admin-msg",n.style.display="none"` setava `display:none` inline no elemento de mensagem logo após a checagem de campo vazio, e nada nos caminhos seguintes limpava esse inline style. O CSS tem `.admin-msg.err{display:block}`, mas style inline sempre vence regra de classe sem `!important`. Toda mensagem de erro era escrita no DOM e nunca aparecia, para qualquer usuário, não só hoje. Confirmado com `getComputedStyle` e `offsetHeight` no elemento ao vivo, os dois batiam com invisível antes do fix e com visível depois.
>
> Correção (commits `b95a33a` e `019504d`, v202.5): remove só a atribuição de `style.display` inline, a classe base `.admin-msg{display:none}` já cobre o estado escondido por CSS puro. Uma linha. Reverificado em produção pós-deploy com o mesmo teste, `display` computado virou `block`, elemento com `offsetHeight>0`, mensagem "Digite a senha." e a de rejeição do servidor ambas visíveis agora.
>
> Efeito colateral do próprio teste: as tentativas repetidas de senha falsa acionaram o rate limiter do Worker, resposta mudou de "Acesso negado" para "Muitas varreduras em pouco tempo". Rate limiter funcionando como esperado, não indica problema.
>
> **Desfecho, mesmo dia, 20h35.** Com a mensagem finalmente visível, a senha real do usuário apareceu como "Acesso negado." de verdade, não era mais bug de exibição. Confirmado no código do Worker (`api/src/worker.js`, `handleAdminListar` e afins) que `admin_senha` é comparado por igualdade estrita contra o secret `env.ADMIN_PASSWORD`, e que existe um segundo secret separado, `USER_PASSWORD`, os dois presentes no Worker via `wrangler secret list`, então não era caso de secret ausente. Hipótese mais provável, confusão entre os dois valores ou senha salva antiga no autofill do navegador.
>
> No meio da conversa o usuário colou a senha real em texto puro no chat. Recusado usar o valor, sinalizado que isso deixa a senha registrada no histórico da sessão, mesmo padrão do incidente ROUTINEKEY-PLAIN1 já catalogado neste projeto. Decisão do usuário, rotacionar `ADMIN_PASSWORD` pelo próprio terminal dele com `wrangler secret put`, valor nunca compartilhado nesta conversa nem gravado por mim em memória ou arquivo.
>
> Primeira tentativa de `wrangler secret put ADMIN_PASSWORD --name radar-credito-api` falhou com aviso do próprio Wrangler, "the latest version of your Worker isn't currently deployed", ligado ao sistema de Versions/Gradual Deployments do Cloudflare. Criou uma versão (`f5813bfc`) que nunca foi promovida, órfã e inofensiva, sem tráfego. Segunda tentativa, comando idêntico, teve sucesso, versão `654c9164` promovida a 100% às 20:33:44, seguida de uma entrada automática de confirmação do Cloudflare (`94e9206d`, também 100%), mesmo padrão observado em rotações de secret anteriores deste Worker em 03/08. Nada ficou em rollout parcial, confirmado em `wrangler deployments list`. Health check pós-rotação limpo. Login testado pelo usuário com a senha nova, confirmado funcionando.
>
> Com isso fecha a cadeia completa do dia: atalho de teclado (ADMINROUTE1), mensagem de erro invisível (ADMINMSG1), e a própria credencial. Painel admin acessível de ponta a ponta.

---

> [!success] 09/08 16h27 — **ADMINROUTE1 v202.4. O Ctrl+Shift+A era o Brave, não o site.**
> **Status:** resolvido, deploy validado em produção
> **Data da Versão:** 2026-08-09
> **Origem do Registro:** perfil Brave local (`brave.accelerators` em `User Data\Default\Preferences`), fonte do Chromium (`chrome/app/chrome_command_ids.h`, `IDC_TAB_SEARCH 52500`), teste ao vivo em vixradar.com
> **Condição de Obsolescência:** perde validade quando o binding `Control+Shift+KeyA` sair da tabela de aceleradores do Brave, quando o painel admin deixar de morar em script inline de `app/index.html`, ou no primeiro deploy que altere `app/index.html` ou `app/js/admin/shared.js` sem passar pelo gate 3.4
>
> "Painel admin não abre com Ctrl+Shift+A" não tinha defeito no site. O perfil do Brave registra `Control+Shift+KeyA` para o comando 52500, `IDC_TAB_SEARCH`, e o navegador consome a tecla antes de ela chegar na página. Nenhum binding `Control+Alt` existe no mesmo perfil, por isso o Ctrl+Alt+A já funcionava. Os dois handlers do site estavam vivos, o inline do `index.html` desde o baseline de 14/06 e o do módulo `app/js/admin/shared.js` desde MODULE-MIG1, e evento sintético abria o painel nos dois chords antes de qualquer mudança.
>
> Mudanças (commits `aeffb9b` e `053c443`, v202.4). O handler inline passou a aceitar Ctrl/Cmd mais Shift ou Alt mais A, com guarda de `e.repeat` e `e.code`, alinhado ao `isAdminShortcut` do módulo. Antes disso o Ctrl+Alt+A só existia se o módulo ES carregasse. O bloco `config-admin-entry` de Configurações passou a mostrar os atalhos na `.config-field-value` ao lado do botão, que é a rota que navegador nenhum consegue tomar. O bump de `?v=` foi aplicado em todos os módulos ES, não só no `admin-bootstrap.js`, senão o browser baixa `shared.js` duas vezes como dois módulos distintos.
>
> Guarda nova: gate 3.4 do `deploy-pages.ps1`. A metade (a) confere que as rotas de acesso existem no bundle, handler com `altKey`, `registerAdminShortcut()` chamado de fato, botão em Configurações, e que todo `?v=` dos módulos bate com `CACHE_VERSION`, coisa que o gate 3.2 só fazia no `index.html`. A metade (b) confere invariantes de autorização, `abrirAdmin` ramificando para `admin-auth-gate`, `adminAutenticar` chamando `admin_listar` com `admin_senha` e checando `ok`, e o handler de atalho sem tocar em senha nem no painel. É proteção contra regressão estrutural, não teste de autorização, a autoridade final continua sendo do Worker. Prova negativa feita nas duas metades: sem o `altKey` o gate reprova com exit 1, e com `admin_senha` injetado no handler ele reprova de novo, nada deployado nos dois casos.
>
> Nota de verificação. Durante o teste em produção o navegador embutido registrou uma requisição extra de `shared.js?v=202.3`. Não vem do site. Nenhum arquivo publicado referencia 202.3 e um Chromium limpo via Playwright carrega só os 8 módulos em `?v=202.4`. É resíduo da própria sessão do painel, que tinha carregado a versão anterior antes do deploy.
>
> **Atualização 09/08 17h.** Operador liberou o `Control+Shift+A` em `brave://settings/system/shortcuts` (comando "Aba pesquisar"), IDC_TAB_SEARCH, removido pela UI, sem reatribuir outro chord. Depois disso apareceu uma terceira camada disputando a mesma combinação, sem relação com o Brave nem com o site, um atalho `.lnk` do navegador Arc na Área de Trabalho (`OneDrive\Desktop\Arc.lnk`) tinha `Ctrl+Shift+A` cadastrado como tecla de atalho do Windows nas propriedades do próprio ícone, apontando para um `Arc.exe` que não existe mais em `WindowsApps`. É o mecanismo nativo do Explorer de tecla de atalho por `.lnk`, intercepta a combinação nesse nível antes mesmo dela chegar em qualquer navegador. Enquanto o Brave ainda capturava o Ctrl+Shift+A para si, essa camada ficava muda, mascarada. Assim que o Brave parou de capturar, o Windows passou a vencer a disputa e mostrar "Atalho Não Encontrado" ao apertar a combinação. Removida a tecla de atalho do `Arc.lnk` via `WScript.Shell` COM (`Hotkey=""`, `.Save()`), edição pontual só nesse campo, ícone e alvo preservados, confirmado relendo o arquivo depois de salvar. Ctrl+Shift+A confirmado funcionando de ponta a ponta pelo operador, overlay com portão de senha abrindo. Pendência fechada. Detalhe técnico e caminho de diagnóstico registrados em memória de projeto (`project_brave_sequestra_atalhos`).

---

> [!success] 09/08 08h31 — **CACHEJS1 v202.3 estava incompleto. Painel admin sem defeito real, achado era outro.**
> Investigação de "painel admin não abre" não achou defeito reproduzível: Worker saudável, `index.html` publicado idêntico ao repo, clique abriu o painel de verdade no navegador do operador (Chrome real, sessão admin válida, `role:admin`). No meio da investigação produção trocou de v202.2 para v202.3 (deploy de outra sessão paralela, 01h43-01h45). O achado real apareceu ao reexaminar o fix CACHEJS1 v202.3 (commit `3b4b128`): `admin-bootstrap.js` versionou com `?v=202.3` os 7 imports/exports do topo, mas as 5 linhas de re-export no rodapé (`admin/modules.js`, `shared.js`, `engajamento.js`, `metricas.js`, `fase3.js`) continuaram sem query string. O navegador baixava cada um desses 5 módulos duas vezes, uma versionada e uma limpa, e a cópia limpa ficava exposta ao mesmo cache de 4h que o CACHEJS1 original existia para fechar. Corrigido nas 5 linhas restantes (commit `a69f9d7`), deploy via `deploy-pages.ps1`, validado com trace de rede no navegador real do operador: 13 requisições de módulo caíram para 8, todas com `?v=202.3`, zero sem versão.
>
> Gotcha de processo encontrado no caminho: o commit automático do `deploy-pages.ps1` (passo 6) só dá `git add` em `index.html`, `version.json` e docs, nunca em `app/js/` ou `app/admin/`, mesmo sincronizando essas pastas para `deploy_zip` no passo 2. Rodar o script sozinho publica a correção mas não a comita. Neste caso o gap foi fechado na mão (commit `a69f9d7` separado, depois push). Registrado como memória de projeto para não repetir a surpresa.

---

> [!success] 06/08 02h15 — **Incidente 04-05/08 encerrado. Fila drenada, 2 guardas novas.**
> Worker v4.9.187, `ok:true`, `verificador_ok:true`. Fila de 23 eventos drenada (14 aprovados, 9 rejeitados, 785k tokens). Commits `ea49418` (preflight ROUTINE_API_KEY antes do 1o token LLM), `06cf4b7` (remove call sites orfaos de `Get-VixModeloEnvInfo` e `-ModeloFixadoNaChamada`), `250e909` (Assert-VixLibFunctions: deteccao de funcoes removidas de lib sem atualizar call sites, exit 97).

> [!warning] 05/08 — **Verificador async quebrado por 24h. Commit `2b025b0` deixou call sites orfaos.**
> Noturno rodou normal (103 submit, 9 criticos). Verificador async executou 4 vezes e morreu nas 4 apos OAuth com `CommandNotFoundException` — `Get-VixModeloEnvInfo` e `-ModeloFixadoNaChamada` tinham sido removidos das libs sem atualizar `run_vixradar_verificacao_async.ps1`. Nenhum log de erro porque PowerShell 5.1 no Task Scheduler nao reporta excecoes nao-tratadas como saida visivel. Fila acumulou 23 eventos. Health so acusou na madrugada de 06/08.

> [!warning] 04/08 — **Guarda ambiental bloqueou verificador async (falso-positivo).**
> `ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro` no ambiente do processo, injetado pelo runtime do Claude Code via `settings.json`. A variavel nao afeta `claude -p` (que recebe `--model` explicito), mas `Test-VixClaudeAmbienteLimpo` nao sabia distinguir. 3 execucoes cairam com `exit 6`. Commits `b60d21c` e `2b025b0` (05/08 02:13) corrigiram: `Set-VixClaudeAuthEnv` passou a limpar vars de modelo do processo, `Test-VixClaudeAmbienteLimpo` deixou de inspecionar `settings.json.model`. Mas `2b025b0` introduziu o bug que derrubou 05/08.

> [!success] 02/08 19h10 — **Sistema totalmente operacional. Noturno 02/08: 88/103 submit, 6 críticos.**
> Noturno: submit_ok=88, skip_ok=15, submit_fail=0, silent_fail=0. 494k tokens, 44min, 7 lotes (79 haiku + 9 sonnet). 6 CRITICO: Rumo (rebaixamento S&P brAAA→brAA+ CreditWatch negativo), Cosan (rebaixamento BB-→B+), Oncoclínicas, Pão de Açúcar (GPA), Raízen, Kora Saúde. Verificador async: fila 9, aprovados 7, rejeitados 2, 255k tokens, fila zerada. Coleta-Volatilidade 5o dia consecutivo exit 0. Export-Historico segue quebrado (token sem permissao KV Storage). Health: ok:true, verificador_ok:true, v4.9.183.

> [!warning] 31/07 — **Incidente de API key 401. Matinal e Noturno com cobertura zero real.**
> Todos os lotes Haiku e Sonnet falharam com 401 API key is invalid. Fallback classificou emissores como NENHUM com cobertura minima. Causa raiz nao investigada: key simplesmente invalida naquele dia, voltou a funcionar 01/08. Verificador async processou metrics vazias (75 bytes). Coleta-Volatilidade e Export-Historico mantiveram o padrao: coleta ok, export quebrado por KV.

> [!warning] 30/07 — **Bug de OAuth corrigido as 16h30. Recuperacao parcial.**
> Rotinas Claude paradas desde 29/07 10:00. Causa raiz: scripts apagavam `ANTHROPIC_API_KEY` antes de invocar `claude -p`, forçando OAuth que expira no Task Scheduler. Correcao: descomentada a injecao da key nos 3 scripts. Matinal reprocessada manualmente (lote 1 apenas, Oncoclinicas CRITICO, Oi CRITICO). Noturno completo com 3 CRITICO. Verificador async drenou 12+12 eventos (2 runs, 1.2M tokens combinados).

> [!warning] 29/07 — **Inicio da falha em cascata.**
> Matinal falhou exit 0x1 (morreu no lote sonnet-1). Coleta-Volatilidade falhou exit 0x1. Noturno processou so 15/93 emissores (lote haiku-1), morreu no haiku-2 com 0x40010004. Verificador async nao rodou. Mesma causa raiz do OAuth, diagnosticada no dia seguinte.

> [!success] 28/07 — **Ultimo dia totalmente operacional antes da falha em cascata.**
> Matinal: submit_ok=14, 4 criticos (Oi, Raizen, Cosan, Rumo), 165k tokens. Noturno: 93 emissores, 1 critico (Rumo). Verificador async 2x (pos-noturno: fila 8, 6 aprovados; pos-matinal: fila 17, 11 aprovados, 949k tokens). Deploy v4.9.183 + v201.93 a noite. Shadow Fable 5: 4 comparacoes no dia, 1 divergencia.

> [!success] 27/07 — **Noturno recuperado apos correcao do settings.json (DeepSeek).**
> Noturno 18:00 rodou com exit 0 apos remocao do bloco DeepSeek do settings.json as 13h. Causa raiz: `ANTHROPIC_BASE_URL` apontando para api.deepseek.com com modelos Claude — o Task Scheduler le o settings.json sem override do app desktop. Matinal reexecutada as 14:03 (14 submit, 6 criticos, 123k tokens) apos rodada contaminada das 13:17 (120k tokens perdidos, WebSearch quebrou pelo modelo DeepSeek). agendaSemanal 03:00 falhou com mesmo padrao.

> [!success] 26/07 — **Noturno 26/07: submit_ok=90, skip_ok=13, submit_fail=0, 396k tokens, 3 criticos.**
> Críticos: Arteris, Oi, Oncoclínicas. Dreno verificacao async exit 0: fila 9, aprovados 6, rejeitados 3, 505k tokens. Shadow Fable 5 estreou em producao: 1 comparacao (Arteris), ambos APROVADO, teto 300k atingido no lote 2.

> [!success] 25/07 — **Noturno 25/07: submit_ok=91, skip_ok=12, submit_fail=0, 377k tokens, 5 criticos.**
> Críticos: Aegea Saneamento, Kora Saude, Oi, Oncoclinicas, Raizen. Dreno verificacao async exit 0: fila 13, aprovados 8, rejeitados 5, 505k tokens. Worker v4.9.181 + Frontend v201.88. Fila PENDENCIAS zerada.

> [!success] 24/07 — **Worker v4.9.180 + fila PENDENCIAS zerada.**
> HDASH1-RES (handleUso sem senha em query), OPENROUTER-DEAD (probes removidos), ALRT1-RES fechado por decisao de produto (alerta critico independente de newsletter). P-CVM executado em producao: 91 empresas corrigidas em 5 semanas ISO (W26-W30). Health `v4.9.180`.

> [!success] 24/07 — **Worker v4.9.179: COOKIE-CLEAR1 (sem Set-Cookie radar_token).**
> Login, admin auto-login e `refresh_cookie` deixam de emitir cookie HttpOnly SameSite=None. Auth so via JSON `token` + `Authorization: Bearer`. Health `versao:v4.9.179`. Completa CSRF-COOKIE1 (v4.9.177 lia so header; 179 para de gravar cookie orfao).

> [!success] 24/07 18h30 — **Worker v4.9.178 + Frontend v201.87 em produção (sprint segurança/custo/a11y).**
> Cadeia do dia: rotação de credenciais (Etapa 1) → Worker v4.9.173–178 (VERIFINJ1, OPENROUTERVIVO, RLADMIN-GET1, ENUM-LOGIN1, VERIFCACHE1, VERIFQ-ORFAO1, SKIP24H, CATCH60, F013-RESIDUAL, CSRF-COOKIE1, PRED2) e Pages v201.85–87 (FOCUSTRAP1, INDEXNOSTORE, TOGGLEA11Y1, CONTRASTMUTED1). Health: `ok:true`, `versao:v4.9.178`. Frontend `CACHE_VERSION=v201.87`. Git HEAD `99d0bed`. LOGLOCK1-REC: root cause OneDrive Pinned + fallback Write-Log por PID. Vault reconciliado nesta entrada (antes travado em v4.9.172 / v201.85).

> [!success] 24/07 18h14 — **Noturno 24/07: 103/103, 6 críticos, dreno verif 13 aprovados / 1 rejeitado.**
> Metrics: submit_ok=103, submit_fail=0, tokens_est=488116 (meta 500k), sonnet=8, haiku=95, buscas=177. Críticos: CSN, Kora Saúde, Oi, Oncoclínicas, GPA, Raízen. Verificação async: total_fila=14, aprovados=13, rejeitados=1, erros_parse=0, exit 0.

> [!warning] 23/07 09h20 — **E-MT resolvido: `email:modo_teste` estava `true` em produção, newsletter só chegava ao admin.**
> Investigação disparada por pergunta direta do operador ("o VIX Radar está enviando os relatórios do dia para a lista de emails?"). Confirmado via KV (`wrangler kv key get email:modo_teste`, sem precisar de `ADMIN_PASSWORD`) que a flag estava `true`. Efeito: `executarNewsletter` (cron `30 21 * * *`, 18h30 BRT diário) rodava normalmente — heartbeat `ok`, dedup `newsletter:enviada:2026-07-22` gravado às 18h31 BRT — mas em `isModoTesteEmail()=true` o destinatário vira só `ADMIN_EMAIL`. Base real: 30 usuários cadastrados (`user:*`), 17 com status aprovado. Ou seja, o boletim de 22/07 foi gerado e "enviado com sucesso" mas só chegou ao operador, não aos 17 assinantes aprovados (inclui contas `@mirabaud.com.br`). Pendência já constava como E-MT (P3) desde antes, mas ninguém tinha confirmado o valor da flag por falta da credencial admin local. Operador autorizou desativar; gravado `email:modo_teste=false` via `wrangler kv key put --remote`, confirmado por leitura de volta. Próximo cron (23/07 18h30 BRT) deve ir para a lista real — checar `modo:"aprovados"` no log do próximo envio. SPF de `send.vixradar.com` já estava corrigido para `-all` (SPF1, resolvido mais cedo hoje), então a entregabilidade do envio real não deve ser penalizada por isso.

> [!success] 23/07 08h50 — **Worker v4.9.172 + Frontend v201.85 em produção.**
> Worker v4.9.172: DEDUPFILA1 — `enfileirarVerificacaoAssincrona` troca `hashEventoKey` (SHA-256 exato de empresa|titulo|fonte_primaria|data_evento) por `_chaveDedupEvento` (data_evento|empresa|fonte_base com normalização de título). Economia estimada ~170k tokens/dia eliminando duplicatas na fila de verificação. Diff de 1 linha, health duplo (curl local + Sprite) confirma `ok:true`, `versao:v4.9.172`.
> Frontend v201.85: FOCUSTRAP1 — script focus-trap aditivo que intercepta Tab (cicla entre elementos focáveis) e Escape (fecha via função conhecida) em todos os 8 `[role="dialog"]`. Não modifica código existente. `CACHE_VERSION=v201.85` confirmado no apex e no HTML.

> [!success] 23/07 08h30 — **Worker v4.9.171 + Frontend v201.84 em produção.**
> Worker v4.9.171 deployado entre 21-23/07 (health confirma `versao:v4.9.171`, commit `6ac1f2f`). Frontend v201.84: tags `og:image` (1200x630, 52 KB, `og-vix-radar.jpg`) + `twitter:card=summary_large_image` no `index.html` para preview com cartão em WhatsApp e redes sociais. Deploy validado (imagem HTTP 200 image/jpeg, HTML com as tags, `CACHE_VERSION=v201.84`), commit `425196b`. Sem drift repo/prod.

> [!success] 23/07 06h45 — **Matinal 23/07: submit_ok=15, 5 críticos, 150.912 tokens.**
> Top 15 por EWS. Críticos: Oncoclínicas, Kora Saúde, Oi, Cosan, Rumo. Dreno de verificação ok. Disparo antecipado (04:39) via recovery.

> [!info] 23/07 08h30 — **Falso alarme: dashboard mostra eventos até 21/07. Não é falha de ingestão.**
> Investigado após relato de que o dashboard inicial só exibia dados até 21/07. Health check confirmou Worker saudável (v4.9.171, ok:true, verificador_ok:true), 103/103 emissores com `_last_scanned_at` de 22-23/07 (zero stale), briefing executivo gerado hoje com 162 eventos e 44 críticos. Análise de `data_evento` nos 162 eventos ativos do KV: o mais recente é 21/07 (Raízen vende Usina Caarapó por R$760M, Kora Saúde assembleia de debenturistas). Nenhum evento com data 22/07 ou 23/07. As noturnas de 21-22/07 e matinal de 23/07 processaram todos os emissores mas não capturaram notícias novas com data posterior a 21/07. Conclusão: sistema operando normalmente, gap percebido é ausência de notícias corporativas no período, não falha técnica. Vault atualizado com checklist pós-rotina e script `check-vault-drift.ps1` para prevenir drift documental.

> [!success] 22/07 18h38 — **Noturna 22/07: submit_ok=92+11 SKIP=103/103, 5 críticos, 468.045 tokens.**
> Críticos: GPA (REX R$4,5bi), Oncoclínicas, +3 outros. Dreno de verificação concluído. 11 SKIP (idempotente, dentro da janela). LastResult=0.

> [!warning] 22/07 13h16 — **Matinal 22/07 atrasada (StartWhenAvailable).**
> Submit_ok=13, 7 críticos, 132k tokens. Disparo normal 10h, executou 13h16. Causa provável: máquina em sleep após cold boot (INGEST-GAP1 recovery).

> [!success] 21/07 13h30 — **v4.9.168 + v201.81: stored XSS da sessão admin fechado nas duas pontas.**
> Auditoria geral do dia achou ADMINXSS1: o painel renderizava nome/email/empresa da lista de usuários via `innerHTML` sem escape, e o Worker gravava esses campos só com `.trim()`. Campo livre do auto-registro, então `empresa=<img onerror=…>` rodava JS na sessão do admin com o `radar_jwt` do localStorage ao alcance. Confirmado explorável (backend não sanitizava), não defense-in-depth. Frontend v201.81 escapa 16 pontos com `h()` (3 no painel admin + 13 no gerador de PDF, PDFXSS1 junto), protegendo inclusive dados legados no KV; Worker v4.9.168 rejeita `<>` no registro. Deploy validado ao vivo: sanitização barra o payload no cadastro, e no browser em produção `h()` escapa `<img src=x onerror=alert(1)>` para entities inertes, console limpo. v4.9.168 adota número novo por deploy, encerrando VERSAO3X. Commit `83dc22c`.

> [!warning] 21/07 12h30 — **Rastreabilidade: v4.9.167 foi publicada três vezes, com conteúdos diferentes.**
> Três commits com a mesma mensagem, `chore(worker): deploy v4.9.167 em producao`, alteraram `api/v4.9.167.js` com diffs distintos: `1842499` 15h34 (2 linhas), `ab8b478` 19h03 (117 linhas) e `5af9b39` 19h15 (1 linha). O do meio não é ajuste cosmético, é o **modelo Merton Distance to Default entrando no pipeline preditivo**: `calcMertonDD` (iterativo, padrão KMV, ref. Bharath & Shumway 2008) mais `scoreMertonToRisk`, que soma até 35 pontos ao score de risco de crédito do emissor e adiciona o driver `merton` quando `merton_dd < 1.5`. O commit das 19h15 é hotfix disso: passa a exigir `market_cap > 100` e cai para patrimônio líquido, ou seja, o primeiro deploy podia usar market cap espúrio como insumo do score.
> Consequência prática: `WORKER_VERSAO = "v4.9.167"` deixou de identificar o build, o `canonical-test` compara só o número e não detecta divergência de conteúdo, e "voltar para v4.9.167" virou instrução ambígua. Nem esta nota nem o `PENDENCIAS.md` mencionavam Merton até agora, os dois descreviam a v4.9.167 como sendo apenas F002 e F014.
> **Regra a partir daqui: um número de versão por deploy.** Mudança de comportamento do score nunca reaproveita número já publicado.

> [!danger] 21/07 12h45 — **MERTONLIVE1: o Merton está movendo score real, e o driver não aparece.**
> Build em produção identificado com autorização do MCP: é o terceiro, `5af9b39`. Três evidências convergentes. O histórico do wrangler mostra os dois últimos deploys às 19h06 e 19h18 BRT de 20/07, três minutos depois dos commits `ab8b478` (19h03) e `5af9b39` (19h15), e nada depois; o `api/v4.9.167.js` local é byte-idêntico a `5af9b39` e diferente dos outros dois; e esse arquivo contém as 4 ocorrências de `scoreMertonToRisk` mais o guard `market_cap > 100`.
> Efeito medido no artefato `predictive_v1:latest` gerado hoje 12h30 BRT: dos 103 emissores, **65 têm `merton_dd` calculado e 22 tiveram o score alterado** (2 recebendo +20, 7 recebendo +10, 13 recebendo +4 no `rule.score`, que entra no final com peso 0,55).
> Dois achados que não estavam no radar de ninguém. Primeiro, **o driver é invisível na maioria dos casos**: `drivers.push("merton")` exige `dd < 1.5`, mas o `score +=` roda para todo `dd != null`, então 20 dos 22 afetados não mostram `merton` na lista de drivers. Light (dd 1,86), Pão de Açúcar (1,83), Simpar, EcoRodovias, Vamos, JSL, Minerva, Cosan, Raízen e CSN têm score inflado por um fator que o painel não exibe. Segundo, **dois emissores mudaram de classificação por causa dele**: EcoRodovias (16, baixo; seria 10, neutro) e Movida (16, baixo; seria 5, neutro).
> Ver `PENDENCIAS.md`, MERTONLIVE1.

> [!success] 21/07 12h30 — **Reconciliação CVM destravada.**
> `scripts/predictive/reconciliar_ipe_cvm.ps1` morria na primeira leitura de KV que voltasse 404. Com `$ErrorActionPreference = 'Stop'` herdado do topo, o não-zero do wrangler virava erro terminante e o guard gracioso logo abaixo nunca executava. Como a chave `radar:estado:{semana ISO corrente}` ainda não existe na segunda de manhã, e a task roda justamente na segunda, a rotina falhava de forma determinística toda semana: em 20/07 casou 4 documentos severos da CVM com 3 emissores e morreu em seguida, quatro dias sem ground truth. Fix aplica o mesmo idioma `Continue`/`Stop` já usado na linha 336 do próprio arquivo e nos scripts irmãos. Validado em DryRun nos dois caminhos: 3/3 semanas lidas no caso normal, e com `-SemanasEstado 12` os três 404 viram `AVISO` e a rotina termina em 9/12 semanas com exit 0. O guard de `semanasLidas -eq 0` segue abortando quando nenhuma semana lê, então dado incompleto continua não sendo publicado.

> [!success] 20/07 16h00 — **INGEST-GAP1 resolvido. Recovery manual + deploy v4.9.167 + fix estrutural.**
> Noturno 103/103 (9 críticos, 535k tokens) + Matinal 13/13 (7 críticos, 132k tokens). Causa raiz: máquina desligada 00:25, cold boot 12:24, `StartWhenAvailable=false`. Fix: register reexecutado Admin. Ver [[63 - Recovery e Deploy 2026-07-20]].

> [!danger] 20/07 16h50 — **INGEST-GAP1 detectado: 103/103 stale 24-48h.**
> Matinal 20/07 e Noturna 19/07 não executaram (`0x800710E0`). Diagnóstico completo em [[62 - Auditoria Completa e Correcoes 2026-07-20]].

> [!danger] 19/07 12h25 — **ESCAPEH1 (P0): `renderEventoCard` quebrada 2 dias. Corrigido v201.80.**
> `ReferenceError: h is not defined` — fix de XSS do v201.76 introduziu chamadas a `h()` sem defini-la no escopo. Nenhum card de evento renderizava. Ver [[03 - Estado de Produção]].

> [!warning] 19/07 12h18 — **JANELA30x90 corrigido. Frontend v201.79.**
> `normalizarResultadoPayload` filtrava eventos com janela de 30 dias em vez de 90. Eventos entre 30-90 dias sumiam de todos os emissores.

> [!success] 19/07 12h07 — **JANELACONF1: Worker v4.9.166.**
> Rename cosmético de campo de bookkeeping. Deploy + git reconciliado.

> [!success] 19/07 11h52 — **V0EMPTY1: Frontend v201.78.**
> Dashboard renderizava "0 críticos" como estado definitivo antes do fetch assíncrono resolver. Fix: guarda `Object.keys(resultados).length>0`.

> [!warning] 19/07 08h — **Auditoria geral (`/vix-radar-general-audit`).**
> Achou V0EMPTY1. Confirmou drifts de documentação. RACEKV1 confirmado deployado (não era pendência). [[03 - Estado de Produção]].

> [!success] 18/07 23:46 — **Ingestão recuperada pós-OAuth expirado.**
> Noturna 18/07 abortou com `submit_ok:0` (sessão OAuth expirada). Reauth + rerun manual: 103/103, 6 críticos. [[03 - Estado de Produção]].

> [!warning] 18/07 — **RACEKV1 corrigido no repo.**
> Durable Object `EstadoSemanaDO` serializa 4 funções com fila FIFO. Não deployado nesta data.

> [!success] 18/07 — **Auditoria completa (triple-pass). Sem incidente novo.**
> Drift de documentação ALRT1 e HDASH1 corrigidos. Ambos já estavam resolvidos em produção.

> [!warning] 17/07 noite — **LOGLOCK1 corrigido.**
> Lock de arquivo cegava log da noturna (dados OK). Fix: retry exponencial no `Write-Log`. Commit `49904ea`.

> [!success] 17/07 22h — **FIN1-REV confirmado em produção.**
> 79 emissores destravados. Stale >48h: 76→0. Idade máx: 92.9h→3.8h.

> [!success] 17/07 — **v4.9.164 + v201.76 deployados.**
> 3 P1 (VERIFREJ1, EMAILGET1, RLADMIN2) + fix XSS frontend. Ver [[03 - Estado de Produção]].

> [!success] 16/07 — **Auditoria de rotinas. 5 ativas, documentação reconciliada.**
> AgendaSemanal desabilitada. Commit `48ec5f9`.

> [!success] 15/07 noite — **v4.9.161 (RESEARCHDOWN1).**
> InfoMoney/imprensa financeira era rebaixada como research. Oncoclínicas CRITICO restaurado.

> [!success] 15/07 manhã — **Canonical-test verde após 8 dias.**
> Drift repo/prod reconciliado. `deploy-worker.ps1` criado. PR #10 mergeado.

> [!success] 14/07 tarde — **Aprovação via WhatsApp + CLEANAGG1 corrigido.**
> Cleanup agressivo destruía logs (desde 02/07). Corrigido commit `31035fa`.

> [!success] 14/07 manhã — **v4.9.155 + P0 secrets.**
> 3 credenciais órfãs removidas. Token CF vivo `f3e3d6b4` — revogar no painel.

> [!warning] 13/07 — **Matinal parada 3 dias (saldo -US$1,21). Migração para assinatura.**
> CHUNK1 identificado: `Split-IntoChunks` colapsava lotes de 1 emissor. 3 P1 novos (HDASH1 GET, XSS, rate limiter fail-open). [[53 - Auditoria Completa 2026-07-13]] [[54 - Auditoria Geral Backend Frontend 2026-07-13]].

> [!success] 12/07 — **Frontend v201.75 (co-branding Szuchmacher).**
> Monograma YS em landing + modais. Marca VIX Radar intocada.

> [!info] 11/07 — **v4.9.150 + preditivo v2 + análise competitiva SEO.**
> Altman Z''-EM (69 emissores). Baseline SERP 10 keywords. Task `VIXRadar-Ranking-Mensal` criada.

> [!warning] 10/07 — **Matinal: run 10h falhou (saldo), run 12h cobriu 11/11.**
> 5 CRITICOs: Raízen, Kora, Oi, Oncoclínicas, GPA. Fila de verificação drenada.

> [!error] 09/07 — **Painel sem notícias desde 06/07.**
> Cadeia de falhas 07-08/07 + fila de verificação presa. [[46 - Auditoria Completa 2026-07-09]] [[47 - Auditoria Completa 2026-07-09 (v2)]].

> [!info] 07/07 — **v4.9.147/148 deployados.**
> `admin_mercado` POST-only, `zscores_anbima` auth, `tel()` fix. [[43 - Auditoria Geral Backend Frontend 2026-07-07]] [[44 - Auditoria Geral Backend Frontend 2026-07-07]].

> [!warning] 06/07 — **Noturno rodou duplicado (colisão Task nativa + scheduled).**
> Fix: stderr por-PID + mutex global. [[41 - Auditoria Completa 2026-07-06]].

> [!error] 05/07 — **Bug encoding CP850 corrompia nomes acentuados e descartava CRITICOs.**
> Raízen e Oncoclínicas confirmados. Corrigido nos 3 scripts. [[40 - Auditoria Geral Backend Frontend 2026-07-05]].

> [!error] 04/07 — **Health-gate bloqueou noturna inteira (0/103).**
> `verificador_ok` degradado → script abortava tudo. Fix: health não-bloqueante. [[39 - Auditoria Completa 2026-07-04]].

> [!error] 02/07 — **Rotinas paradas 9 dias. Scheduler zerado (2ª vez).**
> 103/103 stale. 5 tasks recriadas. Mesmo padrão do incidente 15/06. [[35 - Auditoria Completa 2026-07-02]].

---

*Para notas detalhadas de cada evento, ver links [[wikilink]] em cada entrada. Para infraestrutura: [[03b - Infraestrutura]].*
