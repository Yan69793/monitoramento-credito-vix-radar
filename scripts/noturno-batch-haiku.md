# Lote Haiku - buscas condicionais. Dados CVM ja vem no JSON (nao rebuscar CVM).
#
# BUSCAS por emissor (WebSearch): R2 primeiro (noticias de credito: rating, divida, default, covenant, M&A, resultado).
# Executar R6 (cross-check rating/regulatorio) SOMENTE se: R2 trouxe sinal CRITICO/RELEVANTE, ou ews_score>=20, ou cvm_novos>0.
# Threshold 20 e provisorio (abaixo de ROTINA_EWS_LIGHT=30 do Worker, por seguranca - nao ha telemetria de 3+ noites ainda para calibrar). Revisar apos acumular dados de quantos CRITICOs teriam sido bloqueados pelo gate.
# R2 limpo em emissor de baixo EWS: classificar ECO/NENHUM com 1 busca e cobertura_nota de 1 frase.
# Emissor cujo contexto_historico indica CRITICO/REX/RJ/default: NAO re-descobrir o historico - 1 busca de confirmacao de delta na janela.
#
# EVENTOS - gate obrigatorio antes de criar evento CRITICO/RELEVANTE:
# (a) fonte_primaria = URL profunda especifica (documento CVM com parametros, pagina de rating action, materia com slug).
#     PROIBIDO: dominio raiz, homepage, URL de resultado de busca, link de download generico.
# (b) data_evento dentro da JANELA informada no cabecalho. Datas YYYY-MM-DD; nunca "nao_identificada" (usar data_aproximada:true).
# Sem URL primaria valida OU fora da janela: registrar o achado em cobertura_nota (watchlist) e NAO criar evento.
# CRITICO exige URL primaria sempre. ECO/NENHUM: cobertura_nota 1 frase, eventos=[].
# Evento CRITICO/RELEVANTE exige memo_acontecimento + memo_importancia_credito + memo_monitorar preenchidos - alimentam o card do usuario e o contexto_historico de amanha. Preservar acentuacao exata do nome da empresa no RESULTADO|.
#
# SAIDA: somente linhas RESULTADO| / LOTE_RESUMO| / ANOTA| no formato do cabecalho do prompt.
# Sem markdown, sem tabelas, sem backticks, sem narrativa. NAO executar curl nem qualquer submit HTTP - o orquestrador grava.