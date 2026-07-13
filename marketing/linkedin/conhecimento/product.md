# product.md — VIX Radar

Arquivo de conhecimento de produto. Base para toda geração de copy. Não editar números sem conferir a fonte canônica (`app/index.html`, `README.md`, `CLAUDE.md`, vault Obsidian).

## Em uma frase

O VIX Radar é um sistema de inteligência de crédito privado com IA que monitora 103 emissores brasileiros de renda fixa todo dia útil e entrega os eventos que importam já classificados por materialidade — antes que virem manchete.

## Em um parágrafo

Analistas e gestores de crédito privado gastam horas varrendo CVM, ratings, ANBIMA e imprensa para não perder o fato relevante que move o spread. O VIX Radar automatiza essa varredura: cobre 103 emissores em 13 setores, lê as fontes oficiais com IA (Anthropic Claude), classifica cada evento em CRÍTICO, RELEVANTE, ECO ou RUÍDO com um score de materialidade de 0 a 100, e atualiza tudo após o fechamento da B3. Cada evento crítico passa por uma verificação adversarial antes de ser publicado, e vale a Lei Zero: nada entra sem fonte primária verificável.

## Três benefícios (ordem de peso)

1. **Antecipa o risco.** O Early Warning Score (EWS) sobe antes da manchete, dando tempo de reação sobre o emissor na sua carteira.
2. **Filtra o ruído.** Score de materialidade de 0 a 100 separa o fato que move preço do comunicado protocolar. Você lê 5 eventos que importam, não 200 que não importam.
3. **Contextualiza.** Cada evento vem com setor, rating e histórico do emissor — não um link solto, um sinal com contexto de crédito.

## Como funciona (para quando a copy precisar de prova técnica)

- Cobertura: 103 emissores, 13 setores de renda fixa corporativa brasileira.
- Fontes: CVM RAD, ANBIMA Data, B3, Moody's Local, Austin, S&P, Fitch e imprensa financeira.
- IA: Anthropic Claude (Haiku para triagem, Sonnet 4.6 para análise pesada e para a verificação adversarial). NUNCA citar OpenRouter, Gemini ou Perplexity — arquitetura obsoleta.
- Cadência: rotina diária após o fechamento da B3 (18h30 BRT). Os 103 emissores são varridos; os de maior risco recebem análise reforçada.
- Verificação adversarial: todo evento CRÍTICO e uma amostra dos RELEVANTES passam por um segundo modelo que tenta derrubar o achado antes de ele ser publicado.
- Lei Zero: só registra evento com URL e fonte primária confirmada. Sem inferência, sem "provavelmente". Inventar dado é pior do que não ter dado.

## Funcionalidades vendáveis

- Painel de eventos ranqueados por materialidade, com abas de rodadas de busca, alertas de mercado e arquivo.
- EWS por emissor e ranking Top N.
- Briefing executivo (panorama das últimas 5 semanas: materialidade, distribuição setorial, EWS, agenda CVM).
- Comparar emissores lado a lado (2 a 5).
- Watchlist com alerta por e-mail imediato quando um emissor favorito tem evento crítico.
- Agenda de divulgação (ITR/DFP, vencimentos, assembleias).
- Relatório PDF white-label com o nome da gestora e do analista responsável.
- Newsletter/boletim por e-mail (topo de funil gratuito).

## Não prometer

- Análise preditiva como recurso pronto — ainda é roadmap.
- Recomendação de investimento — é conteúdo informativo, não recomendatório (CVM 598/2018). Não é rating.

## Planos

- Essencial — R$ 119/mês: 103 emissores, alertas diários, materialidade e EWS, análise por setor.
- Profissional — R$ 490/mês: tudo do Essencial + briefing executivo + histórico + múltiplos usuários.
- Sem fidelidade. Acesso ao painel por aprovação (solicitação de acesso). Newsletter é aberta.

## Prova / credibilidade

- Operado por Szuchmacher Consultoria Ltda. Software registrado no INPI.
- Caso âncora: comitê de investimento da Mirabaud (tesouraria/family office sem terminal caro).
- Diferencial de mercado: sinal de crédito acionável por R$ 119-490/mês, num setor onde o dado bruto custa R$ 2-3 mil por licença (Quantum Axis, Economatica).
