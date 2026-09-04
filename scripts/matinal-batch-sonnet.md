# Lote Sonnet matinal — max 3 buscas/emissor (R2, R6, R5). Sem R1. CVM do plano.
# CRITICO/RELEVANTE: URL verificavel. ECO/NENHUM: nota curta.
# RE/RJ/default/rebaixamento: checar rad.cvm.gov.br por Fato Relevante do proprio protocolo antes de fechar so com
# imprensa; achando, usar como fonte_primaria (fonte_tipo=CVM_FATO_RELEVANTE). Sem achar, manter imprensa normalmente.
#
# DELTA - nao recrie fato conhecido (FEEDRETRO1, 2026-09-04): cada emissor no JSON tem ultimo_evento_data
# (data do fato mais recente ja salvo) e eventos_conhecidos (amostra do que ja esta no estado), mais
# janela_delta_inicio (inicio real desta busca, sempre dentro da JANELA do cabecalho). Primeira busca com
# ancora de recencia (mes e ano correntes), procure primeiro fato com data_evento >= janela_delta_inicio.
# Achando so fato ja em eventos_conhecidos, mesmo com URL diferente da que esta la: eventos=[],
# cobertura_nota="sem fato novo desde <ultimo_evento_data>, confirmado <o que achou>". Continuacao de saga
# conhecida (nova decisao/prazo/negociacao/rating sobre o MESMO caso) e evento NOVO com a data de agora,
# nunca dobra no protocolo antigo.
#
# SAIDA: somente linhas RESULTADO| / LOTE_RESUMO| / ANOTA| no formato do cabecalho.
# Sem markdown, sem tabelas, sem backticks, sem narrativa. Sem blocos de codigo PowerShell.
# NAO executar curl nem qualquer submit HTTP - o orquestrador (PS1) grava.
#
# Formato (1 linha por emissor, JSON compacto sem quebras):
# RESULTADO|<empresa exatamente como no JSON de entrada, com acentuacao identica>|{"classificacao_geral":"CRITICO|RELEVANTE|ECO|NENHUM","sem_eventos":true,"cobertura_nota":"...","eventos":[],"fontes_consultadas":[{"rodada":"R2","query":"...","resultado":"..."}]}
#
# Cada evento em CRITICO/RELEVANTE EXIGE: memo_acontecimento (2-3 frases, o que aconteceu), memo_importancia_credito (por que importa para o credito), memo_monitorar (o que observar a seguir). Sem esses 3 campos preenchidos o evento fica incompleto.
# Campos obrigatorios por evento: classificacao, titulo, evento (descricao), impacto_credito, memo_acontecimento, memo_importancia_credito, memo_monitorar, fonte_primaria (URL), fonte_tipo, data_evento, data_aproximada, tags.
#
# Ultima linha: LOTE_RESUMO|buscas=<total de buscas executadas>
