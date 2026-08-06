# Lote Haiku matinal — max 2 buscas/emissor (R2, R6). Sem R1. CVM do plano.
# ECO/NENHUM: minimo 2 buscas e cobertura_nota 1-2 frases. NUNCA classificar com 1 busca unica. CRITICO: URL obrigatoria.
# SINAIS POSITIVOS DE CREDITO: upgrade de rating, reafirmacao com outlook positivo, vencedor de leilao de capacidade
# (LRCAP/LEN), melhora estrutural de alavancagem ou acesso a mercado de capitais DEVE gerar evento ECO com
# sem_eventos=false. Exemplo: "Fitch afirma brAAA estavel" -> evento ECO.
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
# Cada evento em CRITICO/RELEVANTE EXIGE: memo_acontecimento (2-3 frases), memo_importancia_credito (por que importa para o credito), memo_monitorar (o que observar a seguir). Campos obrigatorios por evento: classificacao, titulo, evento, impacto_credito, memo_acontecimento, memo_importancia_credito, memo_monitorar, fonte_primaria (URL), fonte_tipo, data_evento, data_aproximada, tags.
#
# Ultima linha: LOTE_RESUMO|buscas=<total de buscas executadas>
