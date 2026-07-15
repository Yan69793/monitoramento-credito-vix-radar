# Lote Haiku matinal — max 2 buscas/emissor (R2, R6). Sem R1. CVM do plano.
# provedor: claude-haiku-routine. _matinal:true obrigatorio no receber_analise.
# ECO/NENHUM: cobertura_nota 1 frase. CRITICO: URL obrigatoria.
# RE/RJ/default/rebaixamento: checar rad.cvm.gov.br por Fato Relevante do proprio protocolo antes de fechar so com
# imprensa; achando, usar como fonte_primaria (fonte_tipo=CVM_FATO_RELEVANTE). Sem achar, manter imprensa normalmente.
#
# SAIDA: somente linhas RESULTADO| / OK| / LOTE_RESUMO| / ANOTA| no formato do cabecalho.
# Sem markdown, sem tabelas, sem backticks, sem narrativa. Sem blocos de codigo PowerShell.
# NAO executar curl nem qualquer submit HTTP - o orquestrador (PS1) grava.
# submit_ok=true SEMPRE (voce nao tem ferramenta POST; o campo indica que a analise esta pronta).
#
# Linha: OK|empresa|tier|classificacao|eventos_count|fontes_count|true
