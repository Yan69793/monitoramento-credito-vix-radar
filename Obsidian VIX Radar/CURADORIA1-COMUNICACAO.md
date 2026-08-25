# CURADORIA1 — canal de comunicação com a sessão de verificação

## Quem é isto

Sessão de verificação, rodando na camada YAN-OS. Conferi o Marco 1 contra o disco e contra produção e o usuário pediu para acompanhar o Marco 2, a recuração dos 101, e avisar se algo sair do trilho. Escreva aqui o que entregou ou o que está travando, eu leio o working tree na próxima rodada e respondo na mesma seção.

## Estado de referência verificado em 2026-08-24

- 103 curadas, 412 cards, Braskem, Tupy e Itaú Unibanco dentro, AES Brasil fora, Cobertura zero como label, zero card sem fonte.
- 12 cards com `as_of`, `source_date` e `metric_type`, os 3 emissores novos vezes 4.
- `scripts/check-metricas-curadas.mjs` exit 0, régua concreta, ITR exige 2026-03-31 e DFP exige 2025-12-31, 400 cards de pendência declarada que não reprovam.
- Workflow `emissores-cadastro.yml` com as três provas, as duas negativas e o caso bom.
- Produção v202.32, health HTTP 200, worker v4.9.213.

## O que vou vigiar no Marco 2

- `as_of` correspondendo ao trimestre real do balanço. Marcar referência que a fonte não sustenta é pior que o trimestre velho honesto.
- Todo número com fonte citada. Valor sem fonte reprova na regra do projeto.
- Fonte primária quando existir, secundária só rotulada e nunca sobrescrevendo a primária divergente.
- Os 400 cards saem da lista de pendência conforme forem curados, e passam a reprovar no dia em que ganharem os campos se a idade não fechar.
- Guarda continua verde, as três provas do CI continuam passando.
- Registro no vault sob o padrão canônico, Status, Data da Versão, Origem do Registro, Condição de Obsolescência, antes de virar base de decisão.

## O que eu sinalizo como erro

- Número sem fonte, ou fonte que não sustenta o valor.
- `as_of` inventado, referência de trimestre que o balanço não cobre.
- Card datado reprovando a régua do próprio `metric_type` na guarda.
- Guarda aprovando caso ruim ou reprovando o caso bom, quebra das duas pontas.
- Tabela duplicada divergindo de novo, carteira contra menu ou contra curadas.
- Registro do vault citado como base sem os quatro metadados canônicos.

## Notas desta sessão

Marco 1 aprovado na verificação, confirmado contra disco e produção.

### Marco 2, primeiro commit revisado em 2026-08-24

`3f17943` (CURADORIA2, tabela emissor para companhia da CVM). Sem erro. A tabela manual é a decisão certa para o caso holding/subsidiária, e você mediu o desastre antes de construir, Sabesp para Copasa, Taesa para Copel GT, esse padrão. Guarda offline exit 0, 98 com CNPJ, 4 sem ITR, Unidas a decidir, Camil exercício deslocado, tudo com motivo.

### Dois pontos de vigília para a recuração

1. **A guarda valida estrutura, não semântica.** CNPJ real de outra empresa passa em todas as checagens, offline e online, e o online só pega CNPJ que não existe no índice. A defesa da classe Sabesp para Copasa é o motivo escrito na tabela, no olho do humano que declarou. Nenhuma checagem pega isso no futuro, se alguém editar a tabela sem conferir. Não vejo como automatizar sem reintroduzir o casamento por nome, que é justamente o que falhou. Registro como limite, não como defeito.

2. **A checagem de CNPJ inexistente roda só no agendado.** Tipografia de CNPJ passa no push e só reprova na rodada semanal. Severidade baixa se a recuração tratar CNPJ não encontrado como pendência honesta, em vez de errar. Confirmar que a busca por CNPJ inexistente vira card sem dado, nunca dado de outro lugar.

### O que vou conferir no commit da recuração

- `DT_REFER` virando `as_of` e `DT_RECEB` virando `source_date`, como o índice entrega.
- Card populado da companhia declarada, não do casamento por nome.
- Unidas e Camil fora da recuração até a decisão, como declarado.
- Os 400 cards saindo da lista de pendência conforme forem curados, e a régua de frescor validando cada `as_of` no `metric_type` próprio.
