# Lote Sonnet matinal — max 3 buscas/emissor (R2, R6, R5). Sem R1. CVM do plano.
# CRITICO/RELEVANTE: URL verificavel. ECO/NENHUM: nota curta.
# RE/RJ/default/rebaixamento: checar rad.cvm.gov.br por Fato Relevante do proprio protocolo antes de fechar so com
# imprensa; achando, usar como fonte_primaria (fonte_tipo=CVM_FATO_RELEVANTE). Sem achar, manter imprensa normalmente.
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
