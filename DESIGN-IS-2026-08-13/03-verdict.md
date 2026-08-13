# 03 — Veredito

**REDESIGN.** A landing pública do VIX Radar fechou em 13/30 com um princípio
estrutural zerado e três no chão, não por falta de linguagem visual, que é
boa, mas porque a implementação não tem sistema: a página pública embarca o
produto inteiro inline, os estados de interação não existem, os CTAs mentem
sobre o que fazem e 19 pares de texto falham contraste AA.

Movimentos de maior alavancagem, na ordem:

1. **#10 (as little design as possible, 0/3):** extrair a landing do
   monolito. A página pública carrega o app completo (585KB JS, 24
   requisições, dois 401, shell no tab order). Landing própria com bundle
   próprio. Evidência: 01-evidence, Peso & Fricção e Estrutural.
2. **#8 (thorough, 0/3):** estados ausentes no caminho de aquisição: erro
   inline no submit, sucesso pós-envio, focus visível, disabled real.
   Evidência: 01-evidence, Visual (0 nós .error/.success, focus invisível,
   0 [disabled]).
3. **#6 (honest, 1/3):** "Assinar" (3259) e "Falar com o time" (3269)
   apontam para o mesmo cadastro; ou os rótulos mudam ou o comportamento
   muda. Remover "em tempo real" (3992), que contradiz o FAQ (3282), e
   traduzir EWS/materialidade. Evidência: 01-evidence, Copy & Honestidade.
4. **#3 (aesthetic, 1/3):** consolidar nos tokens declarados (navy #001020,
   gold #B7985D, no máximo 2 cinzas), matar as 142 cores e as escalas
   quebradas (6.5px, 49.8px, 128px soltos). Evidência: 01-evidence, Visual.
5. **Acessibilidade (alimenta #4 e #8):** 19 falhas de contraste incluindo
   © do rodapé a 1.7:1, FAQ a 4.4:1 e labels do login a 4.41:1; skip link
   inexistente. Evidência: 01-evidence, Acessibilidade.

O que preservar: a linguagem navy + gold + Cormorant + DM Sans (#7 = 3/3) e
a estrutura de conteúdo da landing (hero, diferenciais, planos, acesso), que
são a parte certa do produto.
