// CURADORIA2 (2026-08-24) — de qual companhia da CVM sai o numero de cada emissor.
//
// Por que esta tabela existe, e por que ela e escrita a mao.
//
// O Marco 2 (recuracao dos 101 emissores herdados) precisa dos demonstrativos
// trimestrais da CVM. O ramo DOC/ITR do portal esta vivo e fresco, ao contrario do
// DOC/IPE que esta em 404 desde 23/08 (CVMURL404): o itr_cia_aberta_2026.zip tinha
// Last-Modified de 23/08/2026 e traz 655 companhias com ITR do 2T26.
//
// O problema nao e achar o dado, e saber DE QUEM ele e. Casar o nome do emissor
// contra o DENOM_CIA da CVM por prefixo ou por token erra, e erra feio, porque
// holding e subsidiaria compartilham o nome. Medido antes de escrever esta tabela:
//
//   Sabesp   -> pegava CIA SANEAMENTO DE MINAS GERAIS-COPASA MG   (outra empresa)
//   Taesa    -> pegava COPEL GERACAO E TRANSMISSAO S.A.           (outra empresa)
//   CBA      -> pegava COMPANHIA ENERGETICA DE BRASILIA - CEB     (outra empresa)
//   CSN      -> pegava CSN MINERACAO S.A.                         (subsidiaria)
//   Equatorial Energia -> pegava EQUATORIAL GOIAS DISTRIBUIDORA   (subsidiaria)
//   CEMIG    -> pegava CEMIG GERACAO E TRANSMISSAO S.A.           (subsidiaria)
//   Copel    -> pegava COPEL DISTRIBUICAO S.A.                    (subsidiaria)
//
// Publicar alavancagem da Copasa dentro do card da Sabesp, com "CVM" escrito na
// fonte, seria pior que o dado velho que esta la hoje: o dado velho ao menos e
// dela. Por isso nada aqui e inferido em runtime. Cada linha e uma decisao.
//
// Regra aplicada: a companhia e a entidade consolidada listada que o mercado quer
// dizer quando fala aquele nome, e que carrega a divida, nao a operadora nem a
// distribuidora. Quando holding e operacional divergem, vale a que emite a
// debenture acompanhada pelo radar.
//
// Contagem que valeu ao escrever (nao confie nela sem rodar a guarda):
// 8 candidatas para Energisa, 6 para Rumo, 5 para Eletrobras, 4 para Equatorial.
// Emissor com UMA candidata tambem foi conferido um a um, porque foi exatamente
// no caso de candidata unica que a CSN apontou para a CSN Mineracao.

// emissor -> CNPJ da companhia na CVM.
export const EMISSOR_CNPJ = {
  // --- Energia Eletrica ---
  "Equatorial Energia": "03.220.438/0001-73", // EQUATORIAL S.A., nao as distribuidoras Goias/Para/Maranhao
  "CEMIG": "17.155.730/0001-64",              // CIA ENERGETICA DE MINAS GERAIS, nao Cemig GT nem Cemig D
  "Eletrobras": "00.001.180/0001-26",         // AXIA ENERGIA S.A., renomeada em 10/11/2025 (NOMEMORTO1)
  "Eneva": "04.423.567/0001-21",
  "Engie Brasil Energia": "02.474.103/0001-19",
  "Energisa": "00.864.214/0001-06",           // ENERGISA S.A., holding, nao as 7 distribuidoras
  "Copel": "76.483.817/0001-20",              // CIA PARANAENSE DE ENERGIA, nao Copel D nem Copel GT
  "ISA Energia": "02.998.611/0001-04",        // ISA ENERGIA BRASIL
  "Neoenergia": "01.083.200/0001-18",
  "Taesa": "07.859.971/0001-30",              // TRANSMISSORA ALIANCA DE ENERGIA ELETRICA
  "Auren Energia": "28.594.234/0001-23",      // AUREN ENERGIA, nao Auren Operacoes
  "CPFL Energia": "02.429.144/0001-93",       // CPFL ENERGIA, nao CPFL Renovaveis nem CPFL Transmissao
  "Omega Energia": "42.500.384/0001-51",      // SERENA ENERGIA S.A., renomeada, holding e nao Serena Geracao
  "Comerc Energia": "25.369.840/0001-57",
  "Light": "03.378.521/0001-75",              // LIGHT S.A. - EM RECUPERACAO JUDICIAL, nao Light Energia/Servicos

  // --- Transportes e Logistica ---
  "CCR": "02.846.056/0001-97",                // MOTIVA INFRAESTRUTURA DE MOBILIDADE, renomeada
  "Rumo": "02.387.241/0001-60",               // RUMO S.A., nao as 5 malhas
  "Simpar": "07.415.333/0001-20",
  "MRS Logística": "01.417.222/0001-77",
  "Santos Brasil": "02.762.121/0001-04",
  "Arteris": "02.919.555/0001-67",
  "Azul": "09.305.994/0001-29",
  "EcoRodovias": "04.149.454/0001-80",        // ECORODOVIAS INFRAESTRUTURA E LOGISTICA, nao Concessoes
  "Hidrovias do Brasil": "12.648.327/0001-53",
  "JSL": "52.548.435/0001-79",
  "Embraer": "07.689.002/0001-89",
  "VLI": "42.276.907/0001-28",                // VLI MULTIMODAL
  "Tegma": "02.351.144/0001-18",
  "Vamos": "23.373.000/0001-32",

  // --- Saneamento ---
  "Sabesp": "43.776.517/0001-80",             // CIA SANEAMENTO BASICO EST SAO PAULO
  "Aegea Saneamento": "08.827.501/0001-58",
  "Iguá Saneamento": "08.159.965/0001-33",    // IGUA SANEAMENTO, nao Igua Rio/Sergipe
  "Copasa": "17.281.106/0001-03",
  "Sanepar": "76.484.013/0001-45",
  "BRK Ambiental": "24.396.489/0001-20",      // BRK AMBIENTAL PARTICIPACOES, nao a SPE de Maceio

  // --- Petroleo, Gas e Combustiveis ---
  "Petrobras": "33.000.167/0001-01",
  "Raízen": "33.453.598/0001-23",             // RAIZEN S.A., nao Raizen Energia
  "PRIO": "10.629.105/0001-68",               // PRIO S.A., nao Prio Forte
  "Vibra Energia": "34.274.233/0001-02",
  "Cosan": "50.746.577/0001-15",
  "Brava Energia": "12.091.809/0001-55",
  "Compass Gás e Energia": "21.389.501/0001-81",
  "Braskem": "42.150.391/0001-70",

  // --- Mineracao e Siderurgia ---
  "Vale": "33.592.510/0001-54",
  "Gerdau": "33.611.500/0001-19",             // GERDAU S.A., a operacional listada; Metalurgica Gerdau e a controladora
  "CSN": "33.042.730/0001-04",                // CIA SIDERURGICA NACIONAL. O nome na CVM nao contem "CSN"
  "Usiminas": "60.894.730/0001-05",
  "CBA": "61.409.892/0001-73",                // COMPANHIA BRASILEIRA DE ALUMINIO
  "CSN Mineração": "08.902.291/0001-15",
  "Tupy": "84.683.374/0001-49",

  // --- Financeiro ---
  "Itaúsa": "61.532.644/0001-15",
  "Itaú Unibanco": "60.872.504/0001-23",      // ITAU UNIBANCO HOLDING
  "BTG Pactual": "30.306.294/0001-45",        // BCO BTG PACTUAL, nao BTG Commodities
  "Banco Daycoval": "62.232.889/0001-90",
  "Cielo": "01.027.058/0001-91",
  "B3 S.A.": "09.346.601/0001-25",
  "Bradesco": "60.746.948/0001-12",           // BCO BRADESCO, nao Bradesco Leasing

  // --- Locacao de Veiculos e Mobilidade ---
  "Localiza": "16.670.085/0001-55",           // LOCALIZA RENT A CAR, nao Localiza Fleet
  "Movida": "21.314.559/0001-66",
  // Unidas saiu do A_DECIDIR em 24/08/2026, decisao do operador. As duas candidatas
  // protocolam ITR do 2T26 e o nome nao separa, entao a decisao foi por QUEM EMITE a
  // divida que o radar acompanha, que e a regra ja aplicada nesta tabela.
  //   UNIDAS LOCACOES E SERVICOS (75.609.123) e a controladora e a registrante CVM
  //   53214. E dela as series publicas 12a a 23a de debentures, com preco ANBIMA,
  //   ISIN BROVSADBS*, codigo B3 OVSAA2, rating AA.br da Moody's Local e AA(bra) da
  //   Fitch. Confirmado no proprio ITR: debentures somam R$ 9,56 bi dos R$ 13,06 bi
  //   de divida bruta consolidada em 2026-06-30.
  //   UNIDAS LOCADORA (45.736.131) virou subsidiaria integral da controladora no
  //   3T23 e so emitiu as series 1a a 3a, privadas e atreladas a CRI. Nao e o papel
  //   que o radar precifica.
  // Fontes da decisao: Moody's Local (jun/24 e jul/25), XP Research Unidas 4T25,
  // financialreports.eu. Cuidado ao revisar: o card antigo dizia "Incorporada
  // Localiza", casamento por nome que ignorava a saida do grupo Localiza pelo
  // Cade/Brookfield em 2022-23. Nao voltar a casar Unidas com Localiza.
  "Unidas": "75.609.123/0001-23",             // UNIDAS LOCACOES E SERVICOS, a controladora, nao a Unidas Locadora

  // --- Papel e Celulose ---
  "Klabin": "89.637.490/0001-45",
  "Suzano": "16.404.287/0001-55",             // SUZANO S.A., a operacional listada, nao Suzano Holding
  "Irani": "92.791.243/0001-03",

  // --- Agronegocio ---
  "JBS": "02.916.265/0001-60",                // JBS S.A., emissora das debentures locais; JBS N.V. e a holding holandesa
  "BRF": "01.838.723/0001-27",
  "Marfrig": "03.853.896/0001-40",
  "Minerva Foods": "67.620.377/0001-14",
  "São Martinho": "51.466.860/0001-56",
  "SLC Agrícola": "89.096.457/0001-55",
  "Boa Safra Sementes": "10.807.374/0001-77",
  "Terra Santa Agro": "40.337.136/0001-06",   // TERRA SANTA PROPRIEDADES AGRICOLAS, apos a venda da operacao para a SLC
  "Camil Alimentos": "64.904.295/0001-03",    // exercicio social fecha em fevereiro, ver EXERCICIO_DESLOCADO

  // --- Saude ---
  "Rede D'Or": "06.047.087/0001-39",
  "Hapvida": "05.197.443/0001-38",
  "Fleury": "60.840.055/0001-31",
  "Oncoclínicas": "12.104.241/0004-02",
  "Dasa": "61.486.650/0001-83",               // DIAGNOSTICOS DA AMERICA
  "Kora Saúde": "13.270.520/0001-66",

  // --- Telecom e Tecnologia ---
  "TIM Brasil": "02.421.421/0001-11",         // TIM S.A., a listada; TIM Brasil Servicos e a holding de participacao
  "Totvs": "53.113.791/0001-22",
  "Vivo (Telefônica Brasil)": "02.558.157/0001-62",
  "Brisanet": "04.601.397/0001-28",
  "Algar Telecom": "71.208.516/0001-74",

  // --- Real Estate e Construcao ---
  "MRV Engenharia": "08.343.492/0001-20",
  "Cyrela": "73.178.600/0001-18",
  "Direcional Engenharia": "16.614.075/0001-00",
  "Cury Construtora": "08.797.760/0001-83",
  "Even Construtora": "43.470.988/0001-65",
  "Trisul": "08.811.643/0001-27",
  "Iguatemi": "60.543.816/0001-93",           // IGUATEMI S.A., a listada apos a reorganizacao societaria
  "Multiplan": "07.816.890/0001-53",
  "Log Commercial Properties": "09.041.168/0001-10",

  // --- Varejo e Consumo ---
  "Assaí Atacadista": "06.057.223/0001-71",   // SENDAS DISTRIBUIDORA. Nao confundir com o GPA (SENDASGPA1)
  "Pão de Açúcar (GPA)": "47.508.411/0001-56",// CIA BRASILEIRA DE DISTRIBUICAO
  "Cogna Educação": "02.800.026/0001-40",
  "Grupo Mateus": "24.990.777/0001-09",
  "LWSA": "02.351.877/0001-52",
  "Natura &Co": "71.673.990/0001-77",         // NATURA COSMETICOS
  "Ultrapar": "33.256.439/0001-39"
};

// Emissor da carteira que nao protocola ITR na CVM. Nao e falha de casamento, e
// ausencia de documento, e a diferenca importa: o primeiro caso se corrige com
// alias, o segundo nunca vai casar e precisa de outra fonte para o card.
export const SEM_ITR_CVM = {
  "Nexa Resources": "Companhia de Luxemburgo listada via BDR. Nunca foi companhia aberta registrada na CVM, entao nao ha ITR. Fonte do card tem que ser o release proprio ou o 20-F. Excecao permanente.",
  "Banco Pan": "BANCO PAN SA consta CANCELADA no cadastro apos fechamento de capital. Segue emissor de divida sem protocolo. Confirmado ausente do itr_cia_aberta_2026 em 24/08/2026.",
  "Banco Votorantim": "Sem registro ativo como companhia aberta, VOTORANTIM FINANCAS cancelada e Banco BV nao consta. Confirmado ausente do itr_cia_aberta_2026 em 24/08/2026.",
  "Oi": "Nenhum ITR de 2026 protocolado, nem 1T nem 2T, confirmado por varredura do indice em 24/08/2026. Companhia em recuperacao judicial. Card depende de outra fonte."
};

// Emissor cujo trimestre nao fecha em marco/junho/setembro/dezembro. O as_of dele
// nao pode ser comparado contra a regua de trimestre civil sem ajuste, senao a
// guarda de frescor reprova quem esta em dia.
export const EXERCICIO_DESLOCADO = {
  "Camil Alimentos": { fecha_mes: 2, nota: "Exercicio social fecha no ultimo dia de fevereiro. O ITR mais recente em 24/08/2026 tem DT_REFER 2026-05-31, protocolado em 14/07/2026." }
};

// Emissor onde a companhia certa ainda nao foi decidida. Fica FORA da recuracao ate
// alguem decidir, de proposito: chute com carimbo da CVM e pior que dado velho
// honesto. Esvaziar este bloco e trabalho aberto do Marco 2.
// Vazio desde 24/08/2026, quando a Unidas foi decidida e migrou para EMISSOR_CNPJ.
// Manter o bloco existindo mesmo vazio: e aqui que emissor novo sem decisao cai, e a
// guarda so consegue reprovar "entrou na carteira e ninguem decidiu" porque os tres
// blocos sao um destino declarado. Bloco vazio nao e bloco desnecessario.
export const A_DECIDIR = {};

// Razao social que a CVM tinha para cada CNPJ declarado acima, congelada em
// 2026-08-24 a partir do itr_cia_aberta_2026 (Last-Modified 2026-08-23).
//
// Serve a dois propositos, os dois vindos de vigilancia registrada na revisao do
// commit 3f17943.
//
// 1. Erro de digitacao passa a ser pego no push, offline. Antes so a rodada
//    agendada baixava o indice da CVM, entao um CNPJ bem formado mas trocado
//    ficava ate uma semana sem ser notado. Agora a guarda confere o declarado
//    contra este bloco sem tocar na rede, e a rodada agendada confere este bloco
//    contra o indice vivo. Uma ponta pega tipografia, a outra pega renomeacao.
//
// 2. A declaracao fica revisavel a olho. A guarda valida estrutura, nao semantica:
//    CNPJ real de outra empresa passa em toda checagem automatica, e nao da para
//    automatizar esse julgamento sem voltar ao casamento por nome que falhou. O que
//    da para fazer e deixar o erro visivel. "Sabesp" ao lado de "CIA SANEAMENTO
//    BASICO EST SAO PAULO" se le sozinho, e se um dia virar "COPASA MG" salta aos
//    olhos de quem passar o olho no diff, que e a unica defesa real dessa classe.
export const SNAPSHOT_CVM = {
  "03.220.438/0001-73": "EQUATORIAL S.A.",  // Equatorial Energia
  "17.155.730/0001-64": "CIA ENERGETICA DE MINAS GERAIS - CEMIG",  // CEMIG
  "00.001.180/0001-26": "AXIA ENERGIA S.A.",  // Eletrobras
  "04.423.567/0001-21": "ENEVA S.A",  // Eneva
  "02.474.103/0001-19": "ENGIE BRASIL ENERGIA S.A.",  // Engie Brasil Energia
  "00.864.214/0001-06": "ENERGISA S.A.",  // Energisa
  "76.483.817/0001-20": "CIA PARANAENSE DE ENERGIA - COPEL",  // Copel
  "02.998.611/0001-04": "ISA ENERGIA BRASIL",  // ISA Energia
  "01.083.200/0001-18": "NEOENERGIA S.A.",  // Neoenergia
  "07.859.971/0001-30": "TRANSMISSORA ALIANÇA DE ENERGIA ELÉTRICA S.A.",  // Taesa
  "28.594.234/0001-23": "AUREN ENERGIA S.A.",  // Auren Energia
  "02.429.144/0001-93": "CPFL ENERGIA S.A.",  // CPFL Energia
  "42.500.384/0001-51": "SERENA ENERGIA S.A.",  // Omega Energia
  "25.369.840/0001-57": "COMERC ENERGIA S.A.",  // Comerc Energia
  "03.378.521/0001-75": "LIGHT S.A. - EM RECUPERAÇÃO JUDICIAL",  // Light
  "02.846.056/0001-97": "MOTIVA INFRAESTRUTURA DE MOBILIDADE S.A.",  // CCR
  "02.387.241/0001-60": "RUMO S.A.",  // Rumo
  "07.415.333/0001-20": "SIMPAR S.A.",  // Simpar
  "01.417.222/0001-77": "MRS LOGISTICA S.A.",  // MRS Logística
  "02.762.121/0001-04": "SANTOS BRASIL PARTICIPACOES S.A.",  // Santos Brasil
  "02.919.555/0001-67": "ARTERIS S.A.",  // Arteris
  "09.305.994/0001-29": "AZUL S.A.",  // Azul
  "04.149.454/0001-80": "ECORODOVIAS INFRAESTRUTURA E LOGÍSTICA S.A.",  // EcoRodovias
  "12.648.327/0001-53": "HIDROVIAS DO BRASIL S.A.",  // Hidrovias do Brasil
  "52.548.435/0001-79": "JSL S.A.",  // JSL
  "07.689.002/0001-89": "EMBRAER S.A.",  // Embraer
  "42.276.907/0001-28": "VLI MULTIMODAL S.A",  // VLI
  "02.351.144/0001-18": "TEGMA GESTAO LOGISTICA S.A.",  // Tegma
  "23.373.000/0001-32": "VAMOS LOCAÇÃO DE CAMINHÕES, MÁQUINAS E EQUIPAMENTOS S.A.",  // Vamos
  "43.776.517/0001-80": "CIA SANEAMENTO BASICO EST SAO PAULO",  // Sabesp
  "08.827.501/0001-58": "AEGEA SANEAMENTO E PARTICIPAÇÕES S.A.",  // Aegea Saneamento
  "08.159.965/0001-33": "IGUA SANEAMENTO S.A.",  // Iguá Saneamento
  "17.281.106/0001-03": "CIA SANEAMENTO DE MINAS GERAIS-COPASA MG",  // Copasa
  "76.484.013/0001-45": "CIA SANEAMENTO DO PARANA - SANEPAR",  // Sanepar
  "24.396.489/0001-20": "BRK AMBIENTAL PARTICIPAÇÕES S.A.",  // BRK Ambiental
  "33.000.167/0001-01": "PETROLEO BRASILEIRO S.A. PETROBRAS",  // Petrobras
  "33.453.598/0001-23": "RAÍZEN S.A.",  // Raízen
  "10.629.105/0001-68": "PRIO S.A.",  // PRIO
  "34.274.233/0001-02": "VIBRA ENERGIA S/A",  // Vibra Energia
  "50.746.577/0001-15": "COSAN S.A.",  // Cosan
  "12.091.809/0001-55": "BRAVA ENERGIA S.A.",  // Brava Energia
  "21.389.501/0001-81": "COMPASS GÁS E ENERGIA S.A.",  // Compass Gás e Energia
  "42.150.391/0001-70": "BRASKEM S.A.",  // Braskem
  "33.592.510/0001-54": "VALE S.A.",  // Vale
  "33.611.500/0001-19": "GERDAU S.A.",  // Gerdau
  "33.042.730/0001-04": "CIA SIDERURGICA NACIONAL",  // CSN
  "60.894.730/0001-05": "USINAS SID DE MINAS GERAIS S.A.-USIMINAS",  // Usiminas
  "61.409.892/0001-73": "COMPANHIA BRASILEIRA DE ALUMÍNIO",  // CBA
  "08.902.291/0001-15": "CSN MINERAÇÃO S.A.",  // CSN Mineração
  "84.683.374/0001-49": "TUPY S.A.",  // Tupy
  "61.532.644/0001-15": "ITAÚSA S.A.",  // Itaúsa
  "60.872.504/0001-23": "ITAU UNIBANCO HOLDING S.A.",  // Itaú Unibanco
  "30.306.294/0001-45": "BCO BTG PACTUAL S.A.",  // BTG Pactual
  "62.232.889/0001-90": "BCO DAYCOVAL S.A.",  // Banco Daycoval
  "01.027.058/0001-91": "CIELO S.A. -  INSTITUIÇÃO DE PAGAMENTO",  // Cielo
  "09.346.601/0001-25": "B3 S.A. - BRASIL, BOLSA, BALCÃO",  // B3 S.A.
  "60.746.948/0001-12": "BCO BRADESCO S.A.",  // Bradesco
  "16.670.085/0001-55": "LOCALIZA RENT A CAR S.A.",  // Localiza
  "21.314.559/0001-66": "MOVIDA PARTICIPACOES SA",  // Movida
  "75.609.123/0001-23": "UNIDAS LOCAÇÕES E SERVIÇOS S.A.",  // Unidas
  "89.637.490/0001-45": "KLABIN S.A.",  // Klabin
  "16.404.287/0001-55": "SUZANO S.A.",  // Suzano
  "92.791.243/0001-03": "IRANI PAPEL E EMBALAGEM S.A.",  // Irani
  "02.916.265/0001-60": "JBS S.A.",  // JBS
  "01.838.723/0001-27": "BRF S.A.",  // BRF
  "03.853.896/0001-40": "MARFRIG GLOBAL FOODS S.A.",  // Marfrig
  "67.620.377/0001-14": "MINERVA S.A.",  // Minerva Foods
  "51.466.860/0001-56": "SAO MARTINHO S.A.",  // São Martinho
  "89.096.457/0001-55": "SLC AGRICOLA S.A.",  // SLC Agrícola
  "10.807.374/0001-77": "BOA SAFRA SEMENTES S.A.",  // Boa Safra Sementes
  "40.337.136/0001-06": "TERRA SANTA PROPRIEDADES AGRÍCOLAS S.A.",  // Terra Santa Agro
  "64.904.295/0001-03": "CAMIL ALIMENTOS S.A.",  // Camil Alimentos
  "06.047.087/0001-39": "REDE D'OR SÃO LUIZ S.A.",  // Rede D'Or
  "05.197.443/0001-38": "HAPVIDA PARTICIPAÇÕES E INVESTIMENTOS S.A.",  // Hapvida
  "60.840.055/0001-31": "FLEURY S.A.",  // Fleury
  "12.104.241/0004-02": "ONCOCLÍNICAS DO BRASIL SERVIÇOS MÉDICOS S.A.",  // Oncoclínicas
  "61.486.650/0001-83": "DIAGNOSTICOS DA AMERICA S.A.",  // Dasa
  "13.270.520/0001-66": "KORA SAÚDE PARTICIPAÇÕES S.A.",  // Kora Saúde
  "02.421.421/0001-11": "TIM S.A.",  // TIM Brasil
  "53.113.791/0001-22": "TOTVS S.A.",  // Totvs
  "02.558.157/0001-62": "TELEFÔNICA BRASIL S.A",  // Vivo (Telefônica Brasil)
  "04.601.397/0001-28": "BRISANET SERVIÇOS DE TELECOMUNICAÇÕES S.A.",  // Brisanet
  "71.208.516/0001-74": "ALGAR TELECOM S/A",  // Algar Telecom
  "08.343.492/0001-20": "MRV ENGENHARIA E PARTICIPACOES S.A.",  // MRV Engenharia
  "73.178.600/0001-18": "CYRELA BRAZIL REALTY S.A.EMPREEND E PART",  // Cyrela
  "16.614.075/0001-00": "DIRECIONAL ENGENHARIA S.A.",  // Direcional Engenharia
  "08.797.760/0001-83": "CURY CONSTRUTORA E INCORPORADORA S.A.",  // Cury Construtora
  "43.470.988/0001-65": "EVEN CONSTRUTORA E INCORPORADORA S.A.",  // Even Construtora
  "08.811.643/0001-27": "TRISUL S.A.",  // Trisul
  "60.543.816/0001-93": "IGUATEMI S.A.",  // Iguatemi
  "07.816.890/0001-53": "MULTIPLAN - EMPREEND IMOBILIARIOS S.A.",  // Multiplan
  "09.041.168/0001-10": "LOG COMMERCIAL PROPERTIES E PARTICIPAÇÕES",  // Log Commercial Properties
  "06.057.223/0001-71": "SENDAS DISTRIBUIDORA S.A.",  // Assaí Atacadista
  "47.508.411/0001-56": "CIA BRASILEIRA DE DISTRIBUICAO",  // Pão de Açúcar (GPA)
  "02.800.026/0001-40": "COGNA EDUCAÇÃO S.A.",  // Cogna Educação
  "24.990.777/0001-09": "GRUPO MATEUS S.A.",  // Grupo Mateus
  "02.351.877/0001-52": "LWSA S/A",  // LWSA
  "71.673.990/0001-77": "NATURA COSMÉTICOS S.A.",  // Natura &Co
  "33.256.439/0001-39": "ULTRAPAR PARTICIPACOES S.A.",  // Ultrapar
};

// Quando o snapshot foi tirado. A guarda usa para dizer ha quanto tempo ele nao e
// confrontado com a CVM.
export const SNAPSHOT_CVM_EM = "2026-08-24";
