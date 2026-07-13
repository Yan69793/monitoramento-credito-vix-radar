# posts_organicos.md — 10 posts (voz Yan Szuchmacher)

Formato nativo LinkedIn: hook nas 2 primeiras linhas, parágrafos de 1-2 linhas, termina em pergunta. Sem emojis. Conteúdo informativo, não-recomendatório. Mix 80/20. Publicar no perfil pessoal do Yan; a página reforça.

Legenda de CTA: [NL] = newsletter (topo) · [MAT] = material/lead gen (meio) · [ACESSO] = solicitar acesso (fundo).

---

## Post 1 — Dor central [NL]

Você acompanha mais de 100 emissores de crédito privado numa planilha.

O rebaixamento aparece no home broker antes de aparecer na sua aba do Excel.

Essa é a rotina real de muita mesa de crédito no Brasil: abrir CVM, ANBIMA, os sites das agências, a imprensa, um por um, toda manhã. Funciona para 10 emissores. Não escala para 100.

E o custo de perder um evento não é operacional. É o spread que já mexeu quando você leu a notícia.

O trabalho de monitorar não é o trabalho de analisar. Só que ele consome as duas primeiras horas do dia de quem deveria estar decidindo.

Como está a sua rotina de varredura hoje: no braço, terminal caro, ou nenhuma?

---

## Post 2 — EWS / antecipação [NL]

O default não manda aviso prévio.

O spread, sim.

Antes de um emissor virar manchete, o risco costuma aparecer em sinais dispersos: um aditamento de debênture, um comunicado de assembleia, um rebaixamento de perspectiva, uma queda de caixa no ITR.

Isoladamente, cada um parece pequeno. Juntos, formam um padrão.

A ideia de um Early Warning Score é essa: transformar sinais dispersos num número que sobe antes da manchete, para dar tempo de olhar o emissor com atenção antes do mercado.

Não é bola de cristal. É leitura estruturada do que já é público, só que rápido e no lugar certo.

Quando um emissor da sua carteira se deteriora, você costuma perceber pelo preço ou pelo fato relevante?

---

## Post 3 — Materialidade / filtro [NL]

Todo dia a CVM recebe dezenas de fatos relevantes e comunicados.

A maioria não move preço nenhum.

O problema de quem monitora crédito não é falta de informação. É excesso. Aprovação de ata, mudança de diretor sem impacto, recompra protocolar. Ruído com cara de sinal.

O que importa é a materialidade: aquele evento muda a capacidade do emissor de pagar a dívida?

Um score de 0 a 100 por evento serve para isso. Ele não substitui o analista. Ele coloca na frente dele os 5 eventos que merecem os olhos, e empurra os 195 que não merecem para o fim da fila.

Ler menos, melhor.

Qual proporção do que você lê sobre os seus emissores realmente muda alguma decisão?

---

## Post 4 — Verificação adversarial [MAT]

IA de linguagem tem um problema conhecido em crédito: ela é confiante até quando está errada.

Se você deixa um modelo classificar sozinho um evento de crédito, uma hora ele vai afirmar um rebaixamento que não aconteceu, com toda a segurança do mundo.

Num relatório de faculdade, tudo bem. Numa mesa de crédito, é caro.

A forma de reduzir isso não é confiar mais no modelo. É desconfiar de propósito.

No VIX Radar, todo evento crítico passa por um segundo modelo cujo trabalho é tentar derrubar o primeiro. Só o que sobrevive à contestação é publicado.

Verificação adversarial não elimina o erro. Reduz o tipo de erro mais perigoso: o falso positivo confiante.

Você confiaria numa classificação de crédito feita por IA sem uma camada de checagem?

---

## Post 5 — Lei Zero [NL]

A regra número um do nosso sistema é chata de propósito:

Inventar dado é pior do que não ter dado.

Na prática: um evento só entra no radar se tiver uma fonte primária verificável. URL real, documento real. Sem "provavelmente", sem inferência, sem completar a lacuna com o que soa plausível.

Isso significa que às vezes o sistema diz "não encontrei nada de novo neste emissor" em vez de encher a tela.

Para marketing, silêncio é ruim. Para uma mesa de crédito, silêncio honesto vale mais do que um alerta inventado que faz você mexer numa posição à toa.

Confiança se constrói mais rápido pelo que você se recusa a afirmar do que pelo que você afirma.

Você prefere um monitoramento que erra para mais ou para menos?

---

## Post 6 — Caso setorial (público, não-recomendatório) [MAT]

2026 foi um ano de aula sobre crédito privado no Brasil.

Recuperações judiciais e extrajudiciais de nomes grandes, rebaixamentos em cadeia, reestruturações de dívida bilionária. Tudo público, tudo divulgado.

O que separou quem reagiu a tempo de quem reagiu pelo jornal não foi acesso à informação. Era tudo público.

Foi velocidade e triagem. Enxergar o padrão de deterioração enquanto ele se formava, no meio de centenas de comunicados que não importavam.

Não é sobre prever o futuro. É sobre ler o presente rápido o suficiente para agir dentro dele.

Isto aqui é observação de eventos públicos, não recomendação sobre nenhum ativo.

Olhando para trás, qual desses casos você acha que dava sinais antes da manchete?

---

## Post 7 — Custo / posicionamento [NL]

Cobrir crédito privado profissionalmente no Brasil costuma custar de R$ 2 a 3 mil por mês, por licença.

Faz sentido para um banco com mesa dedicada. Não faz sentido para uma tesouraria de empresa, um family office ou uma gestora média que carrega crédito privado mas não vive só disso.

Esse pessoal fica no pior dos mundos: risco de crédito real na carteira, sem ferramenta à altura, resolvendo no Excel.

A pergunta que me levou a construir o VIX Radar foi simples: por que monitorar mais de 100 emissores tem que custar o preço de um analista júnior?

Sinal de crédito acionável não deveria ser artigo de luxo.

Se você não tem terminal, como resolve o monitoramento de crédito hoje?

---

## Post 8 — Bastidor / como funciona [NL]

O que acontece entre um comunicado da CVM às 19h e um alerta classificado no seu painel:

Primeiro, a varredura. Depois do fechamento da B3, o sistema passa pelos 103 emissores, lendo CVM, ANBIMA, agências e imprensa.

Segundo, a leitura. A IA extrai o que é evento de crédito e descarta o protocolar.

Terceiro, a classificação. Cada evento recebe um grau (crítico a ruído) e um score de materialidade.

Quarto, a contestação. O que é crítico passa por um segundo modelo que tenta derrubar.

Quinto, a publicação. Só o que sobreviveu, com fonte, entra no radar.

Nada disso é mágico. É engenharia sóbria em cima de fontes públicas.

Que parte desse fluxo você acha mais difícil de acertar: a leitura, a classificação ou a checagem?

---

## Post 9 — Comitê / decisão com fonte [ACESSO]

A pior pergunta para se ouvir num comitê de investimento é: "de onde você tirou isso?"

Não porque a resposta seja difícil. Porque procurar a fonte na frente de todo mundo mina a decisão.

Monitoramento de crédito não serve só para você saber do evento. Serve para você sustentar a decisão depois, com rastreabilidade.

Todo alerta com a fonte primária anexada. O relatório com o nome do emissor, o setor, a data e o link. Exportável com a marca da sua casa.

Decisão de crédito não é palpite. É tese com evidência.

No seu processo, quanto tempo se gasta reconstruindo a fonte de uma decisão já tomada?

---

## Post 10 — Pitch direto da newsletter [NL]

Uma vez por semana eu mando um recorte do que moveu o crédito privado brasileiro.

Não é newsletter de "mercado hoje". É especificamente sobre eventos de crédito: rebaixamentos, recuperações, reestruturações, eventos CVM materiais entre os principais emissores de renda fixa.

Os que importam, com fonte, sem ruído.

É de graça e é o mesmo filtro de materialidade que roda no produto pago, só que num resumo semanal.

Se você opera ou acompanha crédito privado, é o tipo de coisa que economiza a sua varredura de segunda-feira.

Quer receber? Comenta ou me chama que eu te coloco na lista.

---

## Notas de uso

- Não publicar os 10 de uma vez. Cadência 3-5/semana. Alternar ângulo (dor, método, prova, bastidor).
- Os posts 4, 6 e 8 são os mais fortes candidatos a virar Thought Leader Ad se performarem.
- Post 6: manter o disclaimer não-recomendatório sempre que citar casos reais.
- Trocar a pergunta final por variações para testar engajamento.
