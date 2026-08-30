# Reposicao de varredura perdida - passada de caça dirigida na janela perdida.
#
# CONTEXTO: dias uteis ficaram sem rotina (app fechado, task travada) e o feed ficou preso
# em data antiga. Voce esta caçando fatos de credito REALMENTE datados dentro da janela
# perdida (informada no cabecalho). Nao e uma varredura completa dos 103, e uma caçada
# dirigida nos emissores com contexto na janela.
#
# REGRA DE OURO - data real da fonte, nunca resumo de busca (REPOSIC1):
# a busca web recicla artigo velho e cola data nova na manchete. REPOSIC1 quase entrou com
# "Moody's reafirma Petrobras 27/08" que era artigo de 2015, e "Fitch eleva Petrobras 26/08"
# que era de 2025. Para TODO fato, conferir a data na fonte: baixar a pagina e procurar
# article:published_time, datePublished ou <time datetime>. Data de resumo de busca NAO vale.
#
# ANTI-ANCORAGEM - o bug que matou o feed (REPOSIC1):
# a passada de 29/08 re-ancorou desenvolvimento novo em fato antigo. Evento vira do FATO,
# nao do enredo. Nova decisao judicial, novo rating action, novo documento CVM protocolado
# na janela = evento com data_evento = data do fato na janela, MESMO que seja continuacao de
# saga ja conhecida (ex: nova decisao na recuperacao da Braskem em 28/08 vira evento datado
# 28/08, nunca dobra no protocolo de 24/08). Evento ancorado em fato fora da janela (sem
# delta datado nela) NAO cria evento novo.
#
# ALVOS: por emissor, na ordem - (1) rating action e reafirmacao com outlook na janela
# (Moody's/S&P/Fitch), (2) default/RJ/recuperacao/negociacao, (3) documento CVM protocolado
# na janela (Fato Relevante, Comunicado ao Mercado), (4) captacao/vencimento/refinanciamento,
# (5) M&A, troca de controle, venda de ativo, (6) resultado material (lucro/prejuizo) na janela.
# Sinal positivo (upgrade, reafirmacao com outlook positivo) DEVE gerar evento ECO com
# sem_eventos=false. Nao descartar sinal positivo como "sem eventos".
#
# FONTE - preferir nesta ordem:
# 1. URL com data no path (/2026/08/27/...), imune ao fetch do validarDatasFontes.
# 2. Dominio confiavel do Worker: exame.com, infomoney.com.br, valor.globo.com, estadao.com.br,
#    moneytimes.com.br, braziljournal.com, neofeed.com.br, poder360.com.br.
# 3. Dominio de agencia de rating (moodys.com, fitchratings.com, spglobal.com) - aceito com
#    verificacao forcada da data mesmo se o fetch for bloqueado.
# Sem fonte com data real na janela: registrar em cobertura_nota e NAO criar evento.
#
# EMITENTE: conferir nome canonico em EMISSORES_LISTA antes de montar o resultado.
# Emitente fora da carteira de 103: receber_analise devolve 400. Nao submeter.
#
# EVENTOS:
# (a) data_evento YYYY-MM-DD = data do fato na janela. Nunca "nao_identificada"; se a data e
#     aproximada, data_aproximada:true e a melhor data conhecida.
# (b) CRITICO/RELEVANTE exigem fonte_primaria = URL profunda especifica (pagina da rating
#     action, materia com slug, documento CVM). Proibido dominio raiz e homepage.
# (c) CRITICO/RELEVANTE exigem memo_acontecimento + memo_importancia_credito + memo_monitorar.
# (d) Evento de RJ/REX/default/rebaixamento: conferir rad.cvm.gov.br por Fato Relevante do
#     proprio protocolo na janela antes de fechar com imprensa; se achar, usar como
#     fonte_primaria (fonte_tipo=CVM_FATO_RELEVANTE).
#
# SAIDA: somente linhas RESULTADO| / LOTE_RESUMO| / ANOTA| no formato do cabecalho do prompt.
# Sem markdown, sem tabelas, sem backticks, sem narrativa. NAO executar curl nem submit HTTP -
# o orquestrador grava e submete via scripts/repor-varredura.ps1.
