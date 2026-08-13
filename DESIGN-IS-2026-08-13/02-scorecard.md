# 02 — Scorecard (Dieter Rams, 10 princípios)

Total: **13/30**

1. Good design is innovative — Score: 2/3
   Evidence: produto real de crédito privado com EWS e demo embutida é raro no mercado brasileiro; o design em si refresca o padrão institucional dark luxury (deck `/apresentacao`).
   Justification: a inovação está no produto, não na forma; a forma é um refresh competente de linguagem conhecida, que é o âncora do 2.

2. Good design makes a product useful — Score: 2/3
   Evidence: tarefa primária (entender + solicitar acesso) completa em hero → diferenciais → planos → form; porém "Assinar" e "Falar com o time" desembocam no mesmo cadastro genérico (01-evidence, Copy 3259/3269).
   Justification: o caminho principal existe e é curto, mas as ações adjacentes desviam do que prometem, impedindo o 3.

3. Good design is aesthetic — Score: 1/3
   Evidence: 142 cores renderizadas, 24 tamanhos de tipo (6.5 a 128px), 28 valores de espaçamento com 6.5 e 49.8 fora de escala, classes mortas (01-evidence, Visual e Estrutural).
   Justification: há linguagem navy/gold reconhecível, mas a superfície auditada está muito além de "2 inconsistências" e tem violações duras de contraste, o 2 não se sustenta e o 0 seria negar o sistema que existe no deck.

4. Good design makes a product understandable — Score: 1/3
   Evidence: "EWS" e "materialidade" sem tradução na landing (Copy 3228/3222), FAQ a 4.4:1 de contraste, labels do login a 4.41:1 (Acessibilidade).
   Justification: mais de um controle/termo exige explicação e jargão está presente na superfície de aquisição, âncora do 1.

5. Good design is unobtrusive — Score: 2/3
   Evidence: a landing visível é contida (hero limpo, pouca decoração); a poluição (10 badges, 4 loops de animação, shell do app, shimmer morto) está majoritariamente escondida no DOM (01-evidence, Peso e Estrutural).
   Justification: o que o visitante vê é quieto; o que a página carrega não é, o que segura no 2 em vez do 3.

6. Good design is honest — Score: 1/3
   Evidence: "Assinar" abre cadastro sem checkout (3259), "Falar com o time" abre cadastro genérico (3269), "em tempo real" (3992) contradiz o FAQ (3282), "antes do mercado"/"EWS antes da manchete" sem lastro, cookie sem "Rejeitar" (4056-4059).
   Justification: são 2+ inflações e dois rótulos que prometem o que não entregam no caminho do dinheiro; não é 0 porque não há continuidade forçada nem custo escondido.

7. Good design is long-lasting — Score: 3/3
   Evidence: navy + dourado + serifa Cormorant + DM Sans, sem gradiente de moda, glassmorphism, tipografia de tendência ou skeuomorfismo residual (01-evidence, Visual).
   Justification: a linguagem leria como atual daqui a três anos, o que é o âncora do 3.

8. Good design is thorough down to the last detail — Score: 0/3
   Evidence: error ausente (submit vazio sem erro inline, 401 só no console), success ausente, focus invisível nos inputs, disabled ausente em runtime — 4 estados faltando (01-evidence, Visual).
   Justification: o âncora do 0 é exatamente "4+ estados ausentes", e nenhum deles é cosmético num formulário de aquisição.

9. Good design is environmentally friendly — Score: 1/3
   Evidence: 585KB de JS inicial + 697KB de HTML, 24 requisições com dois 401, 4 loops de animação ociosos, reduced-motion parcial (2 loops ignoram) (01-evidence, Peso).
   Justification: acima de 500KB com movimento sempre ativo é o âncora do 1; não é 0 porque não há autoplay de vídeo.

10. Good design is as little design as possible — Score: 0/3
    Evidence: a landing pública embarca o aplicativo inteiro inline (painel, admin, agenda, 5 inputs de senha) numa página só, mais 3 classes mortas, shimmer vazio, monograma decorativo e ações duplicadas ×3 (01-evidence, Estrutural e Peso).
    Justification: duplicação e decoração em escala estrutural, o âncora do 0, e é a causa-raiz de metade das notas baixas desta tabela.
