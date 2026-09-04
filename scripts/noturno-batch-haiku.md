# Lote Haiku - buscas condicionais. Dados CVM ja vem no JSON (nao rebuscar CVM).
#
# DELTA - nao recrie fato conhecido (FEEDRETRO1, 2026-09-04): cada emissor no JSON tem ultimo_evento_data
# (data do fato mais recente ja salvo) e eventos_conhecidos (amostra do que ja esta no estado), mais
# janela_delta_inicio (inicio real desta busca, sempre dentro da JANELA do cabecalho). Primeira busca com
# ancora de recencia (mes e ano correntes, nao termo generico), procure primeiro fato com
# data_evento >= janela_delta_inicio. Achando so fato ja em eventos_conhecidos, mesmo com URL diferente da
# que esta la: eventos=[], cobertura_nota="sem fato novo desde <ultimo_evento_data>, confirmado <o que achou>".
# Continuacao de saga conhecida (nova decisao judicial, novo prazo, nova negociacao, nova acao de rating
# sobre o MESMO caso) e evento NOVO com a data do fato de agora, nunca dobra no protocolo antigo.
#
# DATA - sai da fonte, nunca da busca (FONTEDIVERG1, 2026-09-04): data_evento e a data em que o fato ocorreu
# ou foi publicado pela fonte que voce esta citando, lida no proprio conteudo (data no topo da materia, data
# no path da URL, protocolo CVM). Encontrar a materia numa busca ancorada no mes corrente NAO a torna do mes
# corrente: a ancora estreita a busca, nao data o resultado. Sem conseguir confirmar a data de publicacao,
# trate como fato conhecido (eventos=[]) em vez de carimbar hoje. Medido em 04/09/2026: a Kora Saude voltou
# com data_evento=2026-09-04 citando materia cujo article:published_time no HTML era 2026-05-05.
#
# BUSCAS por emissor (WebSearch): R2 primeiro (noticias de credito: rating, divida, default, covenant, M&A, resultado).
# Executar R6 (cross-check rating/regulatorio) SOMENTE se: R2 trouxe sinal CRITICO/RELEVANTE, ou ews_score>=20, ou cvm_novos>0.
# Threshold 20 e provisorio (abaixo de ROTINA_EWS_LIGHT=30 do Worker, por seguranca - nao ha telemetria de 3+ noites ainda para calibrar). Revisar apos acumular dados de quantos CRITICOs teriam sido bloqueados pelo gate.
# R2 limpo em emissor de baixo EWS: classificar ECO/NENHUM com 2 buscas (R2+R6) e cobertura_nota de 1-2 frases.
# NUNCA classificar com 1 busca unica — minimo 2 fontes para qualquer classificacao.
# Emissor cujo contexto_historico indica CRITICO/REX/RJ/default: NAO re-descobrir o historico - 1 busca de confirmacao de delta na janela.
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
# CRITICO exige URL primaria sempre. ECO/NENHUM: cobertura_nota 1-2 frases, eventos=[].
# SINAIS POSITIVOS DE CREDITO: upgrade de rating, reafirmacao com outlook positivo, vencedor de leilao de capacidade (LRCAP/LEN),
# melhora estrutural de alavancagem ou acesso a mercado de capitais em condicoes favoraveis DEVE gerar evento ECO com
# sem_eventos=false. Nao descarte sinal positivo como "sem eventos". O evento ECO aparece no dashboard com severidade
# reduzida e mantem o painel informativo mesmo em periodos de baixa atividade.
# Exemplo: "Fitch afirma brAAA estavel" -> evento ECO com titulo, fonte e data. "LRCAP 2026 vencedor" -> evento ECO.
# Evento CRITICO/RELEVANTE exige memo_acontecimento + memo_importancia_credito + memo_monitorar preenchidos - alimentam o card do usuario e o contexto_historico de amanha. Preservar acentuacao exata do nome da empresa no RESULTADO|.
#
# SAIDA: somente linhas RESULTADO| / LOTE_RESUMO| / ANOTA| no formato do cabecalho do prompt.
# Sem markdown, sem tabelas, sem backticks, sem narrativa. NAO executar curl nem qualquer submit HTTP - o orquestrador grava.