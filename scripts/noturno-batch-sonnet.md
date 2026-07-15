# Lote Sonnet (emissores de alto sinal: EWS>=38 ou CVM novo). Dados CVM ja vem no JSON (nao rebuscar CVM).
#
# BUSCAS por emissor (WebSearch), max 3, adaptativas: R2 primeiro (noticias de credito: rating, divida, default, covenant, M&A, resultado).
# R6 (cross-check rating/regulatorio) se R2 trouxe sinal ou ews_score>=38. R5 (aprofundamento: covenants, rolagem, liquidez) SOMENTE se R2/R6 confirmaram evento CRITICO/RELEVANTE.
# Emissor cujo contexto_historico indica CRITICO/REX/RJ/default: NAO re-descobrir o historico - buscar apenas o delta na janela (o que mudou desde a ultima analise).
#
# EVENTOS - gate obrigatorio antes de criar evento CRITICO/RELEVANTE:
# (a) fonte_primaria = URL profunda especifica (documento CVM com parametros, pagina de rating action, materia com slug).
#     PROIBIDO: dominio raiz, homepage, URL de resultado de busca, link de download generico.
#     Evento de recuperacao judicial/extrajudicial, default ou rebaixamento: SEMPRE checar rad.cvm.gov.br por Fato
#     Relevante/Comunicado ao Mercado do proprio protocolo na janela antes de fechar com fonte de imprensa. Se achar,
#     usar o Fato Relevante CVM como fonte_primaria (fonte_tipo=CVM_FATO_RELEVANTE); imprensa so como fontes_consultadas
#     complementar. Sem Fato Relevante localizavel, manter imprensa como fonte_primaria normalmente (nao bloquear o evento).
# (b) data_evento dentro da JANELA informada no cabecalho. Datas YYYY-MM-DD; nunca "nao_identificada" (usar data_aproximada:true).
# Sem URL primaria valida OU fora da janela: registrar o achado em cobertura_nota (watchlist) e NAO criar evento.
# CRITICO/RELEVANTE exigem URL verificavel sempre. ECO/NENHUM: cobertura_nota curta, eventos=[].
# Evento CRITICO/RELEVANTE exige memo_acontecimento + memo_importancia_credito + memo_monitorar preenchidos - alimentam o card do usuario e o contexto_historico de amanha. Preservar acentuacao exata do nome da empresa no RESULTADO|.
#
# SAIDA: somente linhas RESULTADO| / LOTE_RESUMO| / ANOTA| no formato do cabecalho do prompt.
# Sem markdown, sem tabelas, sem backticks, sem narrativa. NAO executar curl nem qualquer submit HTTP - o orquestrador grava.