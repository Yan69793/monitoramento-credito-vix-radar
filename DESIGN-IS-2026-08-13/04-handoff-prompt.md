# 04 — Handoff /make-plan

Copiar e colar o bloco abaixo numa sessão nova.

````
/make-plan Redesign da landing pública do VIX Radar. A landing atual falhou
na auditoria Rams com 13/30, princípios críticos zerados em #8 (thorough) e
#10 (as little design as possible), além de #6 (honest) em 1/3.

Veredito da auditoria (2026-08-13, DESIGN-IS-2026-08-13):
> REDESIGN. A landing pública fechou em 13/30 com princípio estrutural zerado
> e três no chão, não por falta de linguagem visual, que é boa, mas porque a
> implementação não tem sistema: a página pública embarca o produto inteiro
> inline, os estados de interação não existem, os CTAs mentem sobre o que
> fazem e 19 pares de texto falham contraste AA.

Por que redesign e não refine: total 13 < 20 e o princípio #10 zerou por
decisão estrutural (landing e app num monolito de 700KB), o que um refine
não conserta sem mexer na arquitetura.

Preservar do design atual:
- Linguagem visual navy #001020 + gold #B7985D + Cormorant Garamond (display)
  + DM Sans (corpo), que tirou 3/3 em long-lasting (#7). Evidência: deck
  institucional em https://vixradar.com/apresentacao e CLAUDE.md do projeto.
- A estrutura de conteúdo da landing: eyebrow, hero com a proposta de valor,
  os 3 diferenciais (Antecipa/Filtra/Contextualiza), card demonstrativo de
  materialidade, planos, acesso, FAQ — o inventário está em
  app/index.html:3202-3342.

Descartar (padrões que causaram as falhas):
- Landing e app inteiro na mesma página/DOM. Evidência: app/index.html
  (~700KB, app inline, 585KB JS inicial, 24 requests, 2× 401 no load).
  Causou falhas em #10 e #9.
- CTAs com rótulo divergente do comportamento: "Assinar" (app/index.html:3259)
  e "Falar com o time" (:3269) abrem o mesmo showRegister() genérico.
  Causou falha em #6.
- Estados de formulário inexistentes: 0 nós .error/.success, focus invisível
  nos inputs, 0 elementos [disabled] em runtime. Causou falha em #8.
- Escalas quebradas: 142 cores renderizadas, 28 valores de espaçamento
  (6.5px, 49.8px fora de escala), 24 tamanhos de tipo (128px solto).
  Causou falha em #3.

Top 5 movimentos da auditoria (verbatim):
1. #10 (as little design as possible): extrair a landing do monolito, com
   bundle próprio, sem o shell do app no DOM nem no tab order. Evidência:
   Peso & Fricção (585KB JS, 24 requests, dois 401) e Estrutural.
2. #8 (thorough): implementar os estados do caminho de aquisição — erro
   inline no submit, sucesso pós-envio, focus visível, disabled real.
   Evidência: Visual (0 nós .error/.success, focus invisível, 0 [disabled]).
3. #6 (honest): "Assinar" deve levar a checkout real ou ser renomeado;
   "Falar com o time" deve abrir canal de contato; remover "em tempo real"
   (contradiz FAQ em app/index.html:3282); traduzir EWS e materialidade.
   Evidência: Copy & Honestidade.
4. #3 (aesthetic): consolidar nos tokens declarados (navy, gold, no máximo
   2 cinzas), matar as 142 cores e as escalas fora de módulo.
   Evidência: Visual.
5. Acessibilidade: corrigir as 19 falhas de contraste AA (© do rodapé a
   1.7:1, FAQ a 4.4:1, labels do login a 4.41:1) e adicionar skip link.
   Evidência: Acessibilidade.

Princípios de redesign em prioridade:
1. #10 as little design as possible — cada elemento na landing precisa se
   pagar; nada de app embutido, shimmer morto ou ação duplicada.
2. #6 honest — todo rótulo mapeia 1:1 para o comportamento.
3. #8 thorough — os 6 estados (empty/loading/error/success/focus/disabled)
   presentes no form de aquisição.

Deliverables do plano:
- Nova arquitetura de página (landing separada do app; como servir as duas).
- Fluxo primário lado a lado com o atual (low-fi, rotulado).
- Decisões de token: escala de tipo modular, escala de espaçamento (4px base),
  teto de cores (máx 8 + semânticas).
- Checklist de estados (empty, loading, error, success, focus, disabled).
- Caminho de migração: como o site público troca de página sem quebrar o
  login existente (#phAcesso, localStorage radar_user/radar_jwt).
- Critérios de cutover: quando a landing nova substitui a atual.

Anti-padrões a guardar:
- Portar o markup antigo com estilo novo por cima.
- Manter as duas landings atrás de flag indefinidamente.
- Redesenhar seguindo tendência em vez dos princípios acima.
- Tratar a lista Preservar como opcional.
````
