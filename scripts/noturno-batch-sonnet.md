# Lote Sonnet FULL - tier aprofundado da noturna (PROFUNDIDADE-NOTURNA1).
#
# Este arquivo e o par aprofundado do noturno-batch-haiku.md. Ele NAO substitui o contrato do
# prompt: DELTA (FEEDRETRO1), DATA (FONTEDIVERG1), COBERTURA (COBERTURA1) e o formato de saida
# vem do cabecalho que o motor monta e valem integralmente aqui. O que este arquivo acrescenta e
# a PROFUNDIDADE do tier FULL: mais verificacao por familia, gate de evento mais duro e memo
# obrigatorio. Onde este texto e o cabecalho divergirem, o CABECALHO vence.
#
# O que este arquivo NAO faz, e fazia antes de 19/09/2026: ele nao define conjunto proprio de
# rodadas nem teto proprio de consultas por lote. A versao antiga fixava um limite fixo de
# buscas por emissor enquanto o contrato exige NO MINIMO uma consulta por familia, em tres
# familias obrigatorias. As duas regras se contradiziam e o modelo recebia as duas. Rodada agora
# e detalhe de execucao; FAMILIA e o que a guarda mecanica cobra.
#
# DELTA (FEEDRETRO1) - nao recrie fato conhecido.
# Cada emissor no JSON traz ultimo_evento_data, eventos_conhecidos e janela_delta_inicio.
# Primeira consulta com ancora de recencia (mes e ano correntes, nunca termo generico) e procure
# primeiro fato com data_evento >= janela_delta_inicio. Achando somente fato ja em
# eventos_conhecidos, mesmo com URL diferente da que esta la: eventos=[] e
# cobertura_nota="sem fato novo desde <ultimo_evento_data>, confirmado <o que achou>". Continuacao
# de saga conhecida (nova decisao judicial, novo prazo, nova negociacao, nova acao de rating sobre
# o MESMO caso) e evento NOVO com a data do fato de agora, nunca dobra no protocolo antigo.
# No tier FULL a profundidade vai para a ANALISE do fato novo, nunca para re-descobrir historico:
# contexto_historico que ja indica CRITICO/REX/RJ/default nao se re-apura.
#
# DATA (FONTEDIVERG1) - sai da fonte, nunca da busca.
# data_evento e a data em que o fato ocorreu ou foi publicado pela fonte citada, lida no proprio
# conteudo (data no topo da materia, data no path da URL, protocolo CVM). Encontrar a materia numa
# busca ancorada no mes corrente NAO a torna do mes corrente: a ancora estreita a busca, nao data o
# resultado. Sem confirmar a publicacao, trate como fato conhecido (eventos=[]) em vez de carimbar
# hoje. Medido em 04/09/2026: a Kora Saude voltou com data_evento=2026-09-04 citando materia cujo
# article:published_time no HTML era 2026-05-05.
#
# COBERTURA (COBERTURA1) - OBRIGATORIO, sobrepoe qualquer esquema de busca deste arquivo.
# Para CADA emissor, no minimo UMA consulta por familia, nesta ordem:
#   F1-emissor : web_search com nome + contexto/fato conhecido.
#   F2-divida  : web_search com divida|debentures|emissao|captacao|titulos.
#   F3-fato    : CVM/RI/fato relevante/fonte primaria na janela.
# A familia conta como pesquisada so com prova MECANICA. Cada item de fontes_consultadas DEVE ser
# objeto com TODOS os campos: "familia":"emissor|divida|fato", "query":"...",
# "timestamp":"YYYY-MM-DDTHH:MM:SSZ", "provedor":"<fonte>:web_search|web_fetch", "status_http":200,
# "resultado":"<resposta textual da consulta>", "classificacao":"ok". Familia ausente, degradada
# (429, rate limit, limite backend, sem retorno, resposta vazia) ou sem os campos estruturais nao
# sustenta ausencia de fato.
# F3FETCH1 - MECANISMO DA F3: fetch-first com fallback obrigatorio. Emissor com link em
# cvm_documentos[]: web_fetch no documento mais relevante da janela (fonte primaria, sem custo de
# busca) - 1 (UM) fetch nesta familia. Sem link no JSON, OU web_fetch que falha / devolve erro /
# conteudo vazio / PDF binario ilegivel: web_search na F3 imediatamente - a familia F3 NUNCA fica
# sem consulta executada. PROIBIDO substituir o fetch falho por fetch de OUTRA URL (homepage RI,
# site institucional): o fallback da F3 e SEMPRE web_search. Item de web_fetch: query = a URL
# primaria fetchada, provedor com prefixo completo (NUNCA so "web_fetch"), status_http 200 somente
# quando a tool devolveu conteudo (status completed), resultado = o que o documento diz na janela.
# Fetch que falhou NAO vira item e NUNCA sustenta a familia.
# PROVAFALSA1: proibido registrar consulta que nao executou, inventar status_http/resultado/
# timestamp ou omitir campos. Busca que falhou vai com status_http REAL e classificacao
# "degradada", nunca "ok". "Pesquisada sem evento" = resultado ok descrevendo o que achou;
# "nao pesquisada" = familia ausente.
# NENHUM/ECO so vale com as TRES familias ok. Ausencia de fato nao se certifica com busca parcial.
#
# PROFUNDIDADE DO TIER FULL - o que este lote faz a mais que o LIGHT.
# 1. Cada familia pesquisada com mais de uma consulta quando a primeira devolver sinal ambiguo:
#    termo alternativo (razao social completa, nome fantasia, CNPJ) antes de concluir nada.
# 2. Toda acao de rating, emissao, renegociacao, covenant, vencimento ou M&A entra no gate de
#    evento, mesmo com EWS baixo - o tier FULL existe para pegar o que o LIGHT nao pega.
# 3. Evento CRITICO/RELEVANTE exige memo_acontecimento (2-3 frases, o que aconteceu - alimenta o
#    card do usuario E o contexto_historico de amanha), memo_importancia_credito (por que importa
#    para o credito) e memo_monitorar (o que observar a seguir). Sem os tres o evento fica
#    incompleto: nao omitir.
# 4. Preservar acentuacao exata do nome da empresa no RESULTADO|, como no JSON.
#
# EVENTOS - gate obrigatorio antes de criar evento CRITICO/RELEVANTE.
# (a) fonte_primaria = URL profunda especifica (documento CVM com parametros, pagina de rating
#     action, materia com slug). PROIBIDO: dominio raiz, homepage, URL de resultado de busca, link
#     de download generico. Evento de recuperacao judicial/extrajudicial, default ou rebaixamento:
#     SEMPRE checar rad.cvm.gov.br por Fato Relevante/Comunicado ao Mercado do proprio protocolo na
#     janela antes de fechar com imprensa. Achando, usar o Fato Relevante CVM como fonte_primaria
#     (fonte_tipo=CVM_FATO_RELEVANTE) e imprensa so como fontes_consultadas complementar. Sem Fato
#     Relevante localizavel, manter imprensa como fonte_primaria (nao bloquear o evento).
# (b) data_evento dentro da JANELA do cabecalho. Datas YYYY-MM-DD; nunca "nao_identificada" (usar
#     data_aproximada:true). Sem URL primaria valida OU fora da janela: registrar o achado em
#     cobertura_nota (watchlist) e NAO criar evento.
# SINAIS POSITIVOS DE CREDITO: upgrade de rating, reafirmacao com outlook positivo, vencedor de
# leilao de capacidade (LRCAP/LEN), melhora estrutural de alavancagem ou acesso a mercado em
# condicoes favoraveis DEVE gerar evento ECO com sem_eventos=false. Nao descarte sinal positivo
# como "sem eventos".
#
# SAIDA: somente linhas RESULTADO| / LOTE_RESUMO| / ANOTA| no formato do cabecalho do prompt.
# Uma linha RESULTADO| por emissor, com JSON compacto de linha UNICA, sem quebra interna (quebra
# interna faz o parser perder o emissor inteiro). Sem markdown, sem tabelas, sem backticks, sem
# narrativa. NAO executar curl nem qualquer submit HTTP - o orquestrador grava.
