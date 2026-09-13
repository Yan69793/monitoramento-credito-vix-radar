# Plano técnico, ingestão CVM por ENETWeb

Status deste documento

Plano executável, sem implementação nesta rodada. Nesta entrega, somente este arquivo pode ser alterado. O Worker, o índice do Git, o Wrangler e a produção não foram tocados.

## 1. Estado real e decisão fixada

Baseline de escopo coletado em `2026-09-13T18:52:05-03:00`.

Commit base

```text
branch=main
HEAD=9cbecbe54cf3fb482203afde6537c6d18494403a
```

Saída literal do `git status --short`

```text
 M scripts/lib/vixradar-watchdog.ps1
 M scripts/monitor-tasks.ps1
 M scripts/run_vixradar_varredura.ps1
 M scripts/test-monitor-degradado402.ps1
 M scripts/test-varredura-defeitos.ps1
?? docs/cvm-enetweb-plano.md
?? scripts/test-monitor-drenofalha.ps1
?? scripts/test-monitor-funcoes.ps1
```

Delimitação desta entrega

```text
INCLUÍDO: docs/cvm-enetweb-plano.md
EXCLUÍDO: todos os sete caminhos restantes exibidos no status
PROIBIDO: editar, mover, adicionar ao índice, restaurar ou classificar autoria dos caminhos excluídos
```

O status prova apenas que os caminhos estão modificados ou não rastreados no timestamp acima. Não prova quem os criou nem quando. Este plano não os chama de preexistentes.

Produção medida antes do plano

```text
versao=v4.9.246
HTTP=200
ok=true
fonte_externa_ok=false
cvm_fonte_ok=false
cvm_fonte_motivo=ultimo_sync_falhou:http_404
cvm_fonte_falhas_consecutivas=1
cvm_fonte_falha_dura=true
cvm_fonte_degrada_servico=false
```

A decisão arquitetural é esta.

1. ENETWeb passa a ser a fonte primária da janela corrente.
2. O ZIP permanece no caminho permanente de reconciliação, executado pelo menos uma vez a cada sete dias. Não é apenas fallback eventual.
3. ENETWeb e ZIP produzem o mesmo array canônico antes de filtro, atribuição, teto, merge ou escrita.
4. O merge é conservador por protocolo ou link e preserva registros exclusivos de qualquer uma das fontes.
5. Não haverá tabela paralela de documentos.
6. `cvm:documentos` e o leitor atual permanecem compatíveis.
7. Sucesso isolado do ENETWeb não prova cobertura equivalente nem neutraliza sozinho um 404 do ZIP.

## 2. Contrato do endpoint

Endpoint

```text
POST https://www.rad.cvm.gov.br/ENETWeb/frmConsultaExternaCVM.aspx/ListarDocumentos
Content-Type: application/json; charset=utf-8
```

Payload canônico, com as 17 chaves obrigatórias

```javascript
{
  dataDe: '10/09/2026',
  dataAte: '10/09/2026',
  empresa: '',
  setorAtividade: '',
  categoriaEmissor: '',
  situacaoEmissor: '',
  tipoParticipante: '',
  dataReferencia: '',
  categoria: 'IPE_-1_-1_-1',
  periodo: '2',
  horaIni: '0',
  horaFim: '23',
  palavraChave: '',
  ultimaDtRef: 'false',
  tipoEmpresa: '',
  token: '',
  versaoCaptcha: ''
}
```

Regra de filtro

`Todos` é representado por string vazia. Não usar `-1`. A prova da armadilha foi medida com `empresa='-1'`.

```text
field=empresa http=200 temErro=false dadosChars=0 msg=null
```

Isso é sucesso vazio silencioso no protocolo HTTP. Logo, o caminho só aceita uma resposta quando as três condições forem verdadeiras.

```text
temErro === false
dados.length > 0
documentosValidos.length > 0
```

Uma chave ausente devolve HTTP 500 com `Invalid web service call, missing value for parameter: X`. Erros intermitentes do backend devolvem HTTP 200, `temErro=true` e `msgErro` informando indisponibilidade do serviço em `127.0.0.1:8183`.

## 3. Layout e parser

Uma linha documental tem 13 campos separados por `$&`.

| Índice | Conteúdo observado | Uso |
|---:|---|---|
| 0 | código no formato `00417-0` | Código CVM, nunca CNPJ |
| 1 | denominação do emissor | chave para conferência e fallback nominal |
| 2 | grupo de categoria | candidato a `c` |
| 3 | tipo do documento | diagnóstico, não entra no schema compacto atual |
| 4 | espécie ou assunto dentro de `spanOrder` | candidato a `a` |
| 5 | data de referência dentro de `spanOrder` | candidato a `d` |
| 6 | data e hora de entrega dentro de `spanOrder` | candidato a `de`, descartando a hora no schema atual |
| 7 | situação, como `Ativo` | validação da linha |
| 8 | flag numérica | diagnóstico |
| 9 | sigla | diagnóstico |
| 10 | HTML com ações de visualização e download | origem de protocolo, sequência, versão e `l` |
| 11 | espécie curta, como `FWP` | diagnóstico |
| 12 | vazio no layout medido | reservado |

Estabilidade medida em três dias

```text
08/09/2026 documentos=552 fieldCounts={13:552}
10/09/2026 documentos=694 fieldCounts={13:694}
12/09/2026 documentos=1   fieldCounts={13:1}
```

O parser não pode usar `dados.split('$#')[0]`. `$#` aparece dentro do HTML do campo 10, junto com metadados de locais de publicação. O mesmo vale para um `split('&*')` sem âncora.

O delimitador seguro medido para início de nova linha é

```regex
&\*(?=\d{5}-\d\$&)
```

A primeira linha começa no início do texto com o mesmo padrão de código. Depois da separação por linha, cada documento precisa ter 13 campos e um `OpenDownloadDocumentos` válido.

### Resolução da divergência 277 contra 694

A contagem correta em 10/09/2026 é 694 documentos.

Prova por segmentos que pareciam blocos

```text
chars=667961 blocks_por_split_ingenuo=8
segmento 0 documentMarkers=278
segmento 1 documentMarkers=0
segmento 2 documentMarkers=0
segmento 3 documentMarkers=6
segmento 4 documentMarkers=0
segmento 5 documentMarkers=367
segmento 6 documentMarkers=0
segmento 7 documentMarkers=43
totalDocumentMarkers=694
```

A contagem 277 veio de tratar o primeiro `$#` como fim da grade e ainda excluir a última linha desse primeiro segmento. Esse segmento tem 278 marcadores válidos, não 277. Os demais 416 documentos continuam no mesmo campo `dados`, depois de ocorrências de `$#` incorporadas ao HTML de publicação. A soma é `278 + 6 + 367 + 43 = 694`. O parser ancorado encontrou 694 linhas e todas tinham 13 campos.

## 4. Código CVM e cadastro auxiliar

O payload ENETWeb não contém CNPJ.

```text
cnpj_patterns=0
```

A primeira coluna é Código CVM. A correspondência com o cadastro oficial foi medida.

```text
portal Vale=00417-0     cadastro CD_CVM=4170
portal Embraer=02008-7 cadastro CD_CVM=20087
cadastro header CD_CVM index=9
```

O normalizador deve buscar o cadastro oficial em

```text
https://dados.cvm.gov.br/dados/CIA_ABERTA/CAD/DADOS/cad_cia_aberta.csv
```

Medição do recurso

```text
HTTP=200
Content-Length=1493217
cadastroCodes=2566
```

Normalização do Código CVM

1. Remover caracteres não numéricos.
2. Remover zeros à esquerda.
3. Usar o resultado como chave contra `CD_CVM` normalizado da mesma forma.
4. O cadastro devolve `CNPJ_CIA` e `DENOM_SOCIAL`.
5. Se o código não existir no cadastro, conservar o nome do portal, deixar `j=''` e permitir que o atribuidor único use o fallback nominal existente.
6. Nunca colocar o Código CVM em `j`. `_atribuirDocumentoCVM` trata qualquer sequência numérica não zerada como CNPJ e mandaria praticamente todo o portal para quarentena.

## 5. Mapa do portal para o array canônico

O schema persistido continua exatamente `e, j, d, de, c, a, l`.

| KV | Origem | Transformação |
|---|---|---|
| `e` | cadastro `DENOM_SOCIAL`, localizado pelo campo 0 | usar a denominação oficial do cadastro. Sem correspondência, usar campo 1 do portal normalizado |
| `j` | cadastro `CNPJ_CIA`, localizado pelo campo 0 | manter pontuação do CNPJ como hoje. Sem correspondência, string vazia |
| `d` | campo 5 | extrair `DD/MM/YYYY` do `spanOrder` e converter para `YYYY-MM-DD` |
| `de` | campo 6 | extrair `DD/MM/YYYY` e converter para `YYYY-MM-DD`. A hora não cabe no schema atual e não será inventado campo novo |
| `c` | campo 2 | remover HTML, decodificar entidades e exigir pertinência a `CVM_CATEGORIAS` |
| `a` | conteúdo do primeiro `spanOrder` no campo 4 | remover HTML e decodificar entidades. Preservar o texto, sem inferência |
| `l` | argumentos de `OpenDownloadDocumentos` no campo 10 | reconstruir a URL canônica no mesmo formato usado hoje |

Formato de `l`

```text
https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?Tela=ext&descTipo=IPE&CodigoInstituicao=1&numProtocolo={protocolo}&numSequencia={sequencia}&numVersao={versao}
```

A ordem dos argumentos medida no HTML é

```text
OpenDownloadDocumentos('{sequencia}','{versao}','{protocolo}','IPE')
```

Compatibilidade com o leitor atual

`buscarDocumentosCVM` lê `d.j`, `d.e`, filtra `d.d` lexicograficamente e expande assim.

```text
categoria=d.c
assunto=d.a
data=d.d
data_entrega=d.de || d.d
link=d.l
empresa_cvm=d.e
cnpj_cvm=d.j || null
```

`_resolverDataDocCvm` só aceita `doc.data` e `doc.data_entrega` no formato `YYYY-MM-DD`. Portanto, `d` e `de` precisam sair do normalizador nesse formato antes de entrar no array compacto.

Arquitetura proposta

```text
ENETWeb ou ZIP
        ↓
normalizarDocumentoCVM(documentoFonte, cadastroPorCodigo)
        ↓
array canônico {e,j,d,de,c,a,l}
        ↓
_atribuirDocumentoCVM(j,e)
        ↓
filtro, cobertura, teto, guarda e escrita
```

Não criar atribuidor específico para ENETWeb. Não criar lista específica de alias. O único atribuidor continua `_atribuirDocumentoCVM`.

## 6. Paridade da janela de referência

Artefato legível e medido

```text
arquivo=data/cvm-referencia/ipe_janela_2026-08-25.json.gz
gzBytes=110343
jsonBytes=860091
sha256_json=306c76f6585f585de3d22257f2b1b4bec1883c641b144570d7a3a389d6708654
janela=2026-07-21..2026-08-25
documentos=2175
empresas=510
bytes_serializado=859829
```

Comparação por `numProtocolo`, depois de resolver Código CVM contra o cadastro

```text
portal_normalizado=2229
referencia=2175
protocolos_em_ambos=2145
somente_portal=84
somente_referencia=24
```

Diferenças entre os 2145 protocolos comuns

```text
e=0
j=0
d=0
de=0
c=0
l=0
a=396
```

A divergência de `a` é textual e não muda a identidade. Exemplo medido no protocolo 1546475

```text
portal    Resgate Antecipado Facultativo Total da 29a Emissão de Debentures da Rede D Or Sao Luiz S.A. – ativo RDORD9
referencia Resgate Antecipado Facultativo Total da 29a Emissão de Debentures da Rede D Or Sao Luiz S.A. - ativo RDORD9
```

O protocolo e o link são iguais. Não normalizar pontuação agressivamente para fabricar paridade. A chave documental continua sendo `l`, como em `_cvmChaveDoc`.

Paridade por categoria

| Categoria | Referência | Portal normalizado | Diferença portal menos referência |
|---|---:|---:|---:|
| Comunicação sobre Transação entre Partes Relacionadas | 17 | 17 | 0 |
| Comunicado ao Mercado | 634 | 655 | 21 |
| Fato Relevante | 221 | 228 | 7 |
| Reunião da Administração | 794 | 814 | 20 |
| Assembleia | 287 | 290 | 3 |
| Dados Econômico-Financeiros | 74 | 77 | 3 |
| Documentos de Oferta de Distribuição Pública | 62 | 66 | 4 |
| Escrituras e aditamentos de debêntures | 37 | 39 | 2 |
| Informações de Companhias em Recuperação Judicial ou Extrajudicial | 30 | 29 | -1 |
| Aviso aos Debenturistas | 19 | 20 | 1 |
| Calendário de Eventos Corporativos | 0 | 0 | 0 |

Justificativa das diferenças de conjunto

1. Dos 24 presentes apenas na referência, 19 aparecem no payload bruto do portal, mas não fecham Código CVM contra o cadastro atual. São principalmente entidades estrangeiras, como Inter & Co, JBS N.V., Aura Minerals e G2D, mais casos residuais do cadastro. Esses documentos devem seguir com `j=''` e passar pelo mesmo atribuidor nominal, sem fingir CNPJ.
2. Cinco não apareceram no payload bruto atual. São três da Tapajós Transmissora e dois do Grupo Casas Bahia. O artefato foi gerado em 25/08 e o portal foi consultado depois. Remoção, cancelamento ou revisão posterior é hipótese, não fato demonstrado pelo material disponível. Esses cinco precisam de fixture explícita no teste de migração e não podem ser apagados do acervo só porque a consulta atual não os devolveu.
3. Os 84 presentes apenas no portal são registros hoje visíveis para a janela histórica, mas ausentes do snapshot do ZIP. A causa individual não é demonstrável sem snapshot simultâneo das duas fontes. O plano os classifica como diferença temporal da fonte, não como erro do normalizador.
4. Os 396 textos de assunto divergentes não afetam protocolo, link, emissor, CNPJ, datas ou categoria. Pontuação tipográfica é a diferença comprovada em amostra. Outras diferenças devem ser registradas em teste, sem alteração silenciosa de conteúdo.

Critério para liberar o caminho primário e declarar a janela convergida

1. Todos os 2145 protocolos comuns precisam manter paridade exata em `e,j,d,de,c,l`.
2. Diferença em `a` é permitida, contabilizada e reproduzida, nunca escondida.
3. Fazer merge conservador usando a identidade canônica do leitor `_cvmChaveDoc` em `api/src/worker.js` linha 18253. A chave primária é `l` normalizado com `trim`, desde que não vazio.
4. Quando `l` estiver ausente ou vazio, usar exatamente o fallback do leitor, `categoria` mais `data` mais os primeiros 80 caracteres do assunto, com o mesmo `trim`.
5. Protocolo extraído de `onclick`, `NumeroProtocoloEntrega` e ids de `OpenDownloadDocumentos` é campo auxiliar de paridade e relatório, nunca chave de deduplicação.
6. Se o mesmo protocolo aparecer com links diferentes, manter os dois registros, não deduplicar silenciosamente, gravar `colisao_protocolo_para_revisao` com os dois `l` e exigir fixture reproduzível.
7. Preservar permanentemente dentro da janela monitorada os 24 registros exclusivos da referência, inclusive os cinco ausentes do payload bruto atual, três da Tapajós Transmissora e dois do Grupo Casas Bahia.
8. Preservar documentos da categoria `Calendário de Eventos Corporativos` vindos do ZIP, mesmo quando o ENETWeb não retornar a categoria.
9. Os 84 exclusivos do portal entram no array convergido e ficam contabilizados como `portal_only`.
10. Os 24 exclusivos da referência entram como `zip_only`. Os 24 são fixtures obrigatórias. Os cinco ausentes do payload bruto também precisam de fixtures dirigidas próprias.
11. Um protocolo `zip_only` nunca é removido apenas por não aparecer no ENETWeb. Remoção exige evidência documentada de cancelamento, expiração da janela monitorada ou outra condição explícita aprovada em teste.
12. A janela só recebe `gate_reconciliacao='aprovado'` quando o merge termina com zero diferença estrutural nos comuns e cada exceção remanescente está classificada e reproduzida por fixture.
13. Enquanto o gate estrutural não passar, conservar a última janela convergida confiável, limitada ao TTL descrito na seção 9, e não substituir o acervo por merge inválido. Uma escrita ENETWeb pura continua permitida quando os quatro lotes passarem e a guarda aceitar o candidato, mesmo com ZIP corrente vencido. O gate bloqueado impede apenas declarar reconciliação composta ou rebaixar o 404, nunca a gravação ENETWeb válida.

## 7. Retry e semântica de sucesso

Medição fornecida para o mesmo endpoint

```text
requisições=11
falhas_temErro_true=3
taxa=27.3%
repetições_imediatas_que_recuperaram=3 de 3
```

Medição adicional durante esta análise

```text
10/09 primeira tentativa http=200 temErro=true dadosChars=0
10/09 repetição http=200 temErro=false dadosChars=667961
```

A taxa de 3 em 11 implica, apenas como aproximação independente, 7,44% para duas falhas seguidas e 2,03% para três falhas seguidas. A política não depende dessa independência para aceitar dados. Ela sempre valida o corpo.

Política por lote

| Tentativa | Espera antes da tentativa | Timeout de rede |
|---:|---:|---:|
| 1 | 0 ms | 20 s |
| 2 | 250 ms mais jitter de 0 a 250 ms | 20 s |
| 3 | 1000 ms mais jitter de 0 a 500 ms | 20 s |

Teto do ciclo ENETWeb

```text
3 tentativas por lote
4 lotes
75 segundos de teto global para ENETWeb
```

O ciclo tolera duas falhas por lote. Grava motivo somente quando a terceira tentativa do mesmo lote falhar ou quando o teto global expirar. Uma tentativa que retorna `temErro=true`, dados vazios, JSON inválido ou zero documento válido não conta como sucesso.

Não fazer escrita parcial. Os quatro lotes precisam passar. Se um lote esgotar retry, conservar `cvm:documentos` anterior somente enquanto a chave ainda estiver dentro do TTL de 30 dias descrito na seção 9.1, e gravar apenas a meta de falha, preservando o último sucesso por `gravarFonteCVMMeta`.

## 8. Motivos de fonte e classificação

Motivos novos

| Motivo | Quando ocorre | Dura | Efeito |
|---|---|---:|---|
| `enet_indisponivel` | três tentativas terminaram em `temErro=true`, timeout ou indisponibilidade transitória | não | conserva acervo, `cvm_fonte_ok=false`, `fonte_externa_ok=false`, sem `degrada_servico` |
| `enet_sucesso_vazio` | `temErro=false` com `dados` vazio | sim | rejeita resposta, conserva acervo e evidencia provável payload incorreto ou contrato quebrado |
| `enet_payload_invalido` | resposta não é JSON esperado ou faltam campos estruturais | sim | rejeita resposta e conserva acervo |
| `enet_layout_invalido` | nenhuma linha válida ou contagem de campos diferente de 13 | sim | rejeita resposta e conserva acervo |
| `enet_encolhimento_bloqueado` | array candidato cai abaixo do piso da guarda | sim | não escreve `cvm:documentos`, expõe contagem anterior, candidata e piso |
| `cadastro_cvm_indisponivel` | cadastro Código CVM para CNPJ falhou após retry e não há cópia confiável | sim | não publica array com semântica degradada de `j` |
| `zip_reconciliacao_ausente` | nunca houve reconciliação ZIP bem-sucedida para a janela | sim | bloqueia gate e conserva último convergido confiável |
| `zip_reconciliacao_vencida` | última reconciliação ZIP corrente bem-sucedida ocorreu há mais de sete dias ou nunca ocorreu | sim | bloqueia gate de reconciliação e rebaixamento de 404, mas não bloqueia escrita ENETWeb válida |
| `zip_reconciliacao_gate_bloqueado` | existem diferenças estruturais não classificadas ou fixtures obrigatórias falharam | sim | não escreve array candidato e expõe motivo do gate |
| `zip_only_nao_preservado` | merge candidato removeu protocolo exclusivo do ZIP sem condição explícita | sim | rejeita merge e conserva último convergido confiável |
| `base_expirada_ttl` | `cvm:documentos` expirou após 30 dias sem escrita válida | sim | base ausente, gate bloqueado e fonte indisponível até reconciliação integral aprovada |

Diff exato proposto para a linha atual

```diff
-var CVM_FONTE_MOTIVOS_DUROS = /^(http_\d{3}|excecao:|fonte_ausente_no_catalogo|nao_e_zip|nao_e_deflate)/;
+var CVM_FONTE_MOTIVOS_DUROS = /^(http_\d{3}|excecao:|fonte_ausente_no_catalogo|nao_e_zip|nao_e_deflate|enet_sucesso_vazio|enet_payload_invalido|enet_layout_invalido|enet_encolhimento_bloqueado|cadastro_cvm_indisponivel|zip_reconciliacao_ausente|zip_reconciliacao_vencida|zip_reconciliacao_gate_bloqueado|zip_only_nao_preservado|base_expirada_ttl)/;
```

`enet_indisponivel` fica deliberadamente fora da expressão. Um hiccup do backend não pode gerar e-mail nem `degrada_servico` por si só. Essa tolerância vale somente para a indisponibilidade transitória do ENETWeb. Ela não neutraliza reconciliação ZIP ausente, vencida ou reprovada.

O 404 do ZIP só deixa de ser falha dura quando todas estas condições estiverem simultaneamente verdadeiras.

1. A última reconciliação ZIP bem-sucedida ocorreu há no máximo sete dias.
2. O gate estrutural da reconciliação está aprovado.
3. Os registros `zip_only` da janela permanecem comprovadamente presentes no array convergido.
4. A meta preserva o timestamp e a impressão da última reconciliação ZIP válida.

Sucesso isolado do ENETWeb não satisfaz essas condições. Isso bloqueia somente o rebaixamento do 404 e a declaração de origem composta, não a escrita de um lote ENETWeb válido protegido pelas guardas cumulativas.

Reconciliação em dois níveis

1. O ZIP do ano corrente é a única fonte que pode limpar `zip_reconciliacao_vencida`, atualizar `reconciliacao_zip_ultimo_ok_em` corrente e autorizar a discussão do rebaixamento do 404 corrente.
2. Um ZIP de ano fechado, 2025 ou anterior, pode comprovar que o pipeline de leitura e o normalizador funcionam, além de preservar Calendário e cauda longa. Ele usa `reconciliacao_zip_historica_ultimo_ok_em` separado e não limpa a vencida corrente.
3. Não foi medido nesta rodada se o ZIP de 2025 entrega documentos dentro da janela corrente de 35 dias. Essa cobertura permanece uma incerteza explícita.
4. A meta deve expor `reconciliacao_zip_ano_corrente_ok`, `reconciliacao_zip_historica_ultimo_ok_em` e o motivo de ausência ou vencimento corrente.

Proteção cumulativa da escrita ENETWeb

A escrita ENETWeb sem ZIP corrente exige quatro lotes válidos, layout de 13 campos, identidade `_cvmChaveDoc`, allowlist comum, carry forward dos `zip_only` da última base convergida sem remoção silenciosa, zero colisão de protocolo, piso anti-encolhimento e teto de 16000. O resultado recebe `origem='enetweb_sem_zip_corrente'`, `gate_reconciliacao='bloqueado'`, `reconciliacao_zip_ano_corrente_ok=false` e `reconciliacao_zip_gate_motivo='zip_reconciliacao_vencida'`. O sucesso ENETWeb não zera a vencida do ZIP, mas a escrita válida ocorre.

## 9. Guarda anti-encolhimento

Medições de base

```text
referencia=2175
portal_normalizado=2229
70% de 2175=1522
70% de 2229=1560
```

Piso proposto

```javascript
pisoBootstrap = 1522
pisoDinamico = Math.floor(documentosConfiaveisAnteriores * 0.70)
pisoEfetivo = Math.max(pisoBootstrap, pisoDinamico)
```

Aplicar a guarda depois de normalizar, deduplicar pela identidade única de `_cvmChaveDoc`, filtrar janela e categorias, e antes do `TETO_DOCS` e do `RADAR_KV.put`. O campo de protocolo não participa da deduplicação.

Razão da régua de 70%

1. A troca de fonte medida variou de 2175 para 2229, alta de 2,5%, muito distante do piso.
2. O parser incorreto que parava no primeiro `$#` produziria 278 documentos em 10/09, cerca de 12,5% do acervo da referência, e seria bloqueado.
3. A validação obrigatória dos quatro lotes já impede publicar uma janela com lote ausente. A guarda é uma segunda barreira contra regressão de parser, categoria, cadastro ou deduplicação.
4. Usar 85% antes de observar sazonalidade pode bloquear queda legítima depois de temporada de resultados. A régua de 70% é conservadora e deve ser recalibrada depois de oito ciclos reais registrados.

Quando agir

1. Não escrever `cvm:documentos`.
2. Não renovar o TTL da chave antiga.
3. Gravar meta com `ok=false`, `motivo='enet_encolhimento_bloqueado'`, `documentos_anteriores`, `documentos_candidatos`, `piso_documentos`, `conteudo_sha256_candidato`, `max_data_entrega_candidato` e a origem composta ou candidata efetivamente avaliada.
4. Preservar `ultimo_sync_ok_em`, `max_data_entrega`, impressão e contagem do último bom.

Health esperado

```text
ok=false somente após 4 falhas duras consecutivas, pela regra existente
fonte_externa_ok=false
cvm_fonte_ok=false
cvm_fonte_motivo=ultimo_sync_falhou:enet_encolhimento_bloqueado
cvm_fonte_falha_dura=true
cvm_fonte_degrada_servico=false nas falhas 1 a 3
cvm_fonte_degrada_servico=true na falha 4
cvm_fonte_documentos_anteriores=<N>
cvm_fonte_documentos_candidatos=<N>
cvm_fonte_piso_documentos=<N>
```

Os três campos finais são novos e precisam ser expostos no health público. Eles não contêm PII.

## 9.1. Retenção e expiração da base

A conservação do último array não é permanente no KV. `cvm:documentos` usa `expirationTtl` de 30 dias, conforme `CVM_DOCUMENTOS_TTL_SEG` e a aplicação na linha 8385 de `api/src/worker.js`. Uma meta de falha preservada não renova a chave. Passados 30 dias sem uma escrita bem-sucedida, a chave expira.

É proibido fazer refresh artificial do TTL sem lote válido e gate aprovado. Renovar a expiração sem dado novo mascara staleness e transforma ausência de base em falsa conservação.

Após a expiração

1. Detectar que `cvm:documentos` está ausente e gravar `base_expirada_ttl`.
2. Expor `cvm_fonte_base_presente=false`, `cvm_fonte_motivo=ultimo_sync_falhou:base_expirada_ttl`, `cvm_fonte_gate_reconciliacao=bloqueado` e `cvm_fonte_ok=false`.
3. Não fingir que existe último array confiável, não produzir fallback vazio e não renovar TTL.
4. Manter a fonte indisponível até reconciliação integral ENETWeb mais ZIP, com gate aprovado e escrita válida.
5. Depois da escrita aprovada, iniciar novo TTL de 30 dias exatamente pela operação normal de `cvm:documentos`.

O comentário associado a `CVM_DOCUMENTOS_TTL_SEG`, na linha 7789, registra risco conhecido de escrita manual com TTL menor. Este plano não altera esse comentário nem corrige o risco nesta rodada.

## 10. Frescor e impressão de conteúdo

ENETWeb não tem `Last-Modified`. O sinal canônico passa a ser a maior `Data_Entrega` do array confiável e uma impressão determinística.

Impressão

```text
SHA-256 de JSON.stringify(arrayCanonicoOrdenadoPorLink)
```

Antes do hash

1. Ordenar por `l` crescente.
2. Manter somente `e,j,d,de,c,a,l`.
3. Não incluir HTML bruto, horário de fetch ou ordem de resposta.

Meta de sucesso proposta para origem composta

```javascript
{
  ok: true,
  origem: 'enetweb+zip',
  sincronizado_em: agoraIso,
  last_modified: null,
  last_modified_iso: null,
  max_data_entrega: maxDataEntrega,
  conteudo_sha256: hashConvergido,
  documentos: docsConvergidos.length,
  lotes_ok: 4,
  janela_de: dataDe,
  janela_ate: dataAte,
  normalizador_versao: 1,
  cobertura: cobertura,
  descartados_teto: descartados,
  portal_only: portalOnly.length,
  zip_only: zipOnly.length,
  comuns: comuns.length,
  reconciliacao_zip_ultimo_ok_em: reconciliacaoZipIso,
  reconciliacao_zip_conteudo_sha256: hashZip,
  reconciliacao_zip_idade_dias: idadeZipDias,
  reconciliacao_zip_ano_corrente_ok: anoCorrenteOk,
  reconciliacao_zip_historica_ultimo_ok_em: historicaIso,
  reconciliacao_zip_gate_motivo: gateMotivo,
  gate_reconciliacao: gate,
  gate_reconciliacao_motivo: gateMotivo
}
```

`avaliarFrescorCVM` deve preferir `max_data_entrega` quando a origem contém `enetweb`. Nunca preencher `last_modified_iso` com horário de consulta, pois isso faria uma resposta velha parecer fresca. A validade da fonte composta exige também reconciliação ZIP bem-sucedida nos últimos sete dias e gate estrutural aprovado.

O health deve acrescentar

```text
cvm_fonte_origem=enetweb+zip
cvm_fonte_conteudo_sha256=<hash_convergido>
cvm_fonte_documentos=<N>
cvm_fonte_lotes_ok=4
cvm_fonte_reconciliacao_zip_ultimo_ok_em=<ISO>
cvm_fonte_reconciliacao_zip_idade_dias=<N>
cvm_fonte_portal_only=<N>
cvm_fonte_zip_only=<N>
cvm_fonte_comuns=<N>
cvm_fonte_gate_reconciliacao=aprovado|bloqueado
cvm_fonte_gate_reconciliacao_motivo=<motivo|null>
```

A cadência da janela corrente é diária pelo ENETWeb. A reconciliação ZIP tem SLA próprio de sete dias. O calendário semanal continua valendo para a reconciliação e não pode ser apagado pelo sucesso diário do portal.

## 11. Tamanho do lote, volume e custo

Lote proposto

10 dias corridos por requisição. Para a janela atual de 35 dias subtraídos, inclusiva nas duas pontas, são quatro intervalos sem sobreposição.

```text
D-35 a D-26
D-25 a D-16
D-15 a D-6
D-5  a D
```

Medições que sustentam a escolha

```text
1 dia em 10/09 dadosChars=667961
7 dias em 05/09..11/09 dadosChars=3164005
10 dias em 01/09..10/09 dadosChars=5244776
36 dias em 08/08..12/09 dadosChars=18123696, rede=4.4 s em duas de três tentativas
```

A janela de 36 dias cabe, mas 18,1 MB concentra memória, parsing e retry em uma única unidade. Dez dias limita cada resposta medida a cerca de 5,24 MB e permite repetir somente o intervalo que falhou.

Requisições por ciclo

```text
4 ENETWeb
1 cadastro CVM
5 no caminho sem retry
15 no pior caso de três tentativas para todas
```

Requisições nos dois horários

```text
10 por dia sem retry
30 por dia no pior caso teórico
```

Volume superior conservador, usando quatro vezes o lote de 10 dias medido mais o cadastro

```text
por ciclo=22472321 bytes, 21.43 MiB
matinal mais noturno=42.86 MiB por dia
```

É teto conservador do caminho diário ENETWeb mais cadastro, não cobrança. O endpoint e o cadastro são públicos e não têm custo monetário por chamada. O custo operacional é subrequest, transferência, memória, CPU de parse e tempo de parede do Worker. O cadastro pode usar cache Cloudflare de 24 horas, mas o plano conta a requisição lógica nos dois ciclos para não esconder dependência.

A reconciliação ZIP permanente adiciona pelo menos uma tentativa de download a cada sete dias. Se a URL direta falhar, há ainda a consulta ao catálogo e eventual tentativa da URL resolvida. O tamanho transferido do ZIP não foi medido nesta rodada, portanto não entra artificialmente no total de 42,86 MiB por dia. Telemetria futura deve separar `bytes_enetweb`, `bytes_cadastro`, `bytes_zip` e requisições de catálogo. O custo regular permanece o ENETWeb duas vezes por dia, enquanto o custo ZIP é semanal e obrigatório.

Efeito no KV

```text
referencia serializada=859829 bytes para 2175 docs
media=395.3 bytes por doc
estimativa em TETO_DOCS=16000, 6324800 bytes
uso estimado do limite de 25 MiB=24.12%
folga no teto=3.9x
```

A medição integral do ENETWeb com a allowlist comum ainda é pendente. `13039` é somente a contagem bruta sem filtro, e `6000` a `7000` é estimativa. O ciclo real deve registrar quantidade aceita, descartados por allowlist em cada categoria, tempo de parede, CPU efetiva e bytes serializados antes de qualquer publicação.

Política de teto. Ordenar por `de` descendente, depois `d` descendente e depois `l` ascendente. Só então cortar os mais antigos até `TETO_DOCS=16000`. Se qualquer registro removido tiver entrega nos últimos 14 dias ou for `zip_only`, bloquear a escrita com motivo explícito. Todo descarte abre revisão de teto, mesmo quando o corte for permitido. Nunca depender da ordem dos lotes nem cortar silenciosamente.

## 12. Plano de implementação e ordem de deploy

### Etapa 1, testes e funções puras

1. Criar fixture mínima de resposta ENETWeb com linha completa de 13 campos, HTML com `$#` e `&*`, e dois documentos depois desses símbolos.
2. Criar parser puro que prove 694 contra a resposta medida de 10/09 ou fixture equivalente preservada sem dados pessoais.
3. Criar parser do cadastro Código CVM para CNPJ.
4. Extrair ou criar um único `normalizarDocumentoCVM` aceitando ENETWeb e ZIP como formatos de entrada.
5. Provar saída canônica idêntica para o mesmo protocolo vindo das duas fontes.
6. Provar que Código CVM nunca entra em `j`.
7. Provar formatos `YYYY-MM-DD` aceitos pelo leitor atual.
8. Provar URL por protocolo, sequência e versão.
9. Provar resposta `temErro=false` e vazia como falha.
10. Provar retry recuperando `temErro=true` seguido de payload válido.
11. Provar retry esgotado sem escrita.
12. Provar guarda nas duas pontas, 2229 aceita e 1000 bloqueia.
13. Criar fixtures para todos os 24 protocolos exclusivos da referência.
14. Criar fixtures dirigidas para os cinco protocolos ausentes do payload bruto, três da Tapajós Transmissora e dois do Grupo Casas Bahia.
15. Criar fixture de `Calendário de Eventos Corporativos` exclusiva do ZIP e provar preservação após merge com ENETWeb sem calendário.
16. Provar que um `zip_only` não é removido por ausência no ENETWeb.
17. Provar remoção somente com condição explícita, como expiração da janela ou cancelamento documentado.
18. Provar gate bloqueado por diferença estrutural em `e,j,d,de,c,l` e aprovado quando comuns são idênticos e exceções estão classificadas.
19. Provar 404 do ZIP duro com reconciliação vencida e rebaixado somente com reconciliação ZIP válida há no máximo sete dias, gate aprovado e preservação dos `zip_only`.

### Etapa 2, deploy de observação sem escrita ENETWeb

1. Manter ZIP como escritor e reconciliador.
2. Rodar ENETWeb em shadow nos crons matinal e noturno.
3. Normalizar as duas fontes pelo mesmo normalizador.
4. Calcular contagem, categorias, cobertura, `max_data_entrega`, SHA-256, comuns, `portal_only`, `zip_only` e diferenças estruturais.
5. Gravar somente telemetria ou log, nunca `cvm:documentos` pelo caminho shadow.
6. Observar no mínimo quatro ciclos, dois matinais e dois noturnos, incluindo ao menos uma reconciliação ZIP bem-sucedida.
7. Gate para avançar, quatro lotes ENETWeb válidos por ciclo, zero layout inválido, paridade estrutural nos comuns, fixtures das exceções verdes e nenhuma queda abaixo do piso.

### Etapa 3, cutover primário com reconciliação permanente

1. Consultar e normalizar ENETWeb em cada ciclo.
2. Quatro lotes e cadastro precisam passar.
3. Verificar `reconciliacao_zip_ultimo_ok_em` em cada ciclo.
4. Executar ZIP quando nunca houve reconciliação válida ou quando a última tem sete dias ou mais.
5. Quando o ZIP estiver disponível, normalizar pelo mesmo normalizador e fazer merge conservador pela identidade de `_cvmChaveDoc`: `l.trim()` não vazio, ou o fallback `categoria + data + assunto.slice(0,80)` com o mesmo `trim`. Protocolo é somente diagnóstico. Colisão do mesmo protocolo com links diferentes mantém os dois e grava `colisao_protocolo_para_revisao`.
6. Preservar `portal_only` e `zip_only` dentro da janela monitorada.
7. Aplicar o atribuidor único somente depois do merge canônico.
8. Aplicar filtro, cobertura, guarda e teto sobre o array convergido.
9. Escrever `cvm:documentos` uma vez, de forma integral, apenas depois dos gates cumulativos da escrita. O gate de reconciliação ZIP corrente pode permanecer bloqueado sem impedir essa escrita válida.
10. Gravar meta composta com `origem='enetweb+zip'`, `max_data_entrega`, impressão, última reconciliação ZIP, contagens de diferenças e resultado do gate.
11. Nos ciclos entre reconciliações, fazer merge do ENETWeb corrente com os `zip_only` preservados da última janela convergida confiável.

### Etapa 4, política permanente do ZIP e tratamento do 404

1. O ZIP permanece em reconciliação programada pelo menos uma vez a cada sete dias.
2. `resolverUrlZipPeloCatalogo` continua ativo na reconciliação, resolvendo o recurso anual ou histórico antes de declarar ausência.
3. Quando o ZIP responder, normalizar e reconciliar pelo mesmo caminho usado pelo ENETWeb.
4. Nunca remover protocolo `zip_only` só porque não apareceu no ENETWeb.
5. Remoção exige cancelamento documentado, expiração da janela monitorada ou outra regra explícita coberta por fixture.
6. Se o ZIP retornar 404, consultar o catálogo e tentar URL alternativa válida.
7. Rebaixar o 404 somente se a última reconciliação ZIP bem-sucedida tiver no máximo sete dias, o gate estrutural estiver aprovado e os `zip_only` estiverem preservados.
8. Se qualquer condição do item anterior falhar, manter o 404 como falha dura e bloquear somente o gate de reconciliação e o rebaixamento do 404, sem bloquear a escrita ENETWeb válida.
9. `enet_indisponivel` permanece não duro somente para indisponibilidade transitória do portal. Não altera o estado da reconciliação ZIP.
10. Em qualquer falha, conservar o último array convergido confiável somente até o TTL de 30 dias de `cvm:documentos`, aplicado na linha 8385. Após a expiração, gravar `base_expirada_ttl`, bloquear o gate e não fazer escrita parcial.

Novo papel de `resolverUrlZipPeloCatalogo`

Resolver a fonte permanente de reconciliação ZIP, corrente ou histórica. Ele não decide a saúde do ENETWeb, mas continua decidindo se a reconciliação ZIP está disponível e dentro do SLA.

### Etapa 5, health

1. Expor origem composta, impressão convergida, lotes ENETWeb, `max_data_entrega`, última reconciliação ZIP, idade da reconciliação, comuns, `portal_only`, `zip_only`, gate e motivo de bloqueio.
2. Fazer a cadência diária do ENETWeb coexistir com o SLA de sete dias do ZIP.
3. `enet_indisponivel` não é duro por si só e deixa `cvm_fonte_ok=false`, sem mascarar estado ZIP.
4. ZIP 404 com reconciliação válida, recente, gate aprovado e preservação comprovada pode ser rebaixado.
5. ZIP 404 sem essas provas continua duro.
6. Falhas de integridade entram na lista dura e degradam `ok` após quatro ciclos consecutivos, como hoje.
7. Um sucesso ENETWeb não zera falha da reconciliação ZIP. Somente reconciliação ZIP integral e aprovada atualiza `reconciliacao_zip_ultimo_ok_em`.
8. Um ciclo convergido integral zera as falhas correspondentes e atualiza a impressão composta.

### Etapa 6, rollback

Rollback operacional

1. Reverter para a versão Cloudflare imediatamente anterior ao cutover.
2. O array continua compatível porque o schema não mudou.
3. A última chave confiável permanece disponível somente até o TTL de 30 dias. Falha ou encolhimento não renovam nem substituem o valor.
4. O Worker anterior volta ao ZIP sem migração reversa de KV.
5. Se necessário, executar recomposição histórica pelo ZIP fora do caminho corrente, usando o normalizador comum.

O deploy deve usar exclusivamente

```text
pwsh ./scripts/deploy-worker.ps1 -Version v4.9.NNN
```

Nunca usar `wrangler deploy` direto.

## 13. Health esperado por etapa

| Etapa | Origem escritora | `cvm_fonte_ok` | Motivo esperado |
|---|---|---:|---|
| shadow verde | ZIP | depende do ZIP atual | ENET aparece apenas em telemetria shadow, com diferenças contabilizadas |
| origem ENETWeb sem ZIP corrente | ENETWeb | true para escrita, false para reconciliação | `ok`, `origem=enetweb_sem_zip_corrente`, `gate_reconciliacao=bloqueado`, `reconciliacao_zip_ano_corrente_ok=false`, 404 corrente visível |
| origem composta verde | ENETWeb + ZIP reconciliado | true | `ok`, gate aprovado e reconciliação ZIP até sete dias |
| ENET recuperado por retry | origem composta preservada | true | `ok`, com tentativas no log |
| ENET indisponível, ZIP válido e acervo preservado | último convergido bom | false | `ultimo_sync_falhou:enet_indisponivel`, sem apagar saúde ZIP |
| resposta vazia | último convergido bom | false | `ultimo_sync_falhou:enet_sucesso_vazio` |
| layout inválido | último convergido bom | false | `ultimo_sync_falhou:enet_layout_invalido` |
| guarda agiu | último convergido bom | false | `ultimo_sync_falhou:enet_encolhimento_bloqueado` |
| ZIP 404, reconciliação até sete dias, gate aprovado, `zip_only` preservados | último convergido bom | depende do ENET e demais gates | 404 rebaixado, timestamp ZIP e contagens continuam visíveis |
| ZIP 404 com reconciliação ausente ou vencida | último convergido bom | false | `http_404` duro e gate bloqueado |
| diferença estrutural em comum | último convergido bom | false | gate bloqueado com campo e protocolo no diagnóstico |
| `zip_only` não preservado | último convergido bom | false | gate bloqueado, sem escrita |
| base expirada após 30 dias | ausente | false | `base_expirada_ttl`, gate bloqueado até reconciliação integral aprovada |
| quarta falha dura consecutiva | último convergido bom | false | motivo preservado e `cvm_fonte_degrada_servico=true` |

## 14. Critérios de aceite da implementação futura

1. Suite atual verde.
2. Testes novos provam parser com delimitadores embutidos.
3. Teste de paridade reproduz 2145 protocolos comuns e zero diferença em `e,j,d,de,c,l`.
4. As 396 diferenças de assunto ficam contabilizadas e reproduzíveis.
5. Testes provam a identidade única de `_cvmChaveDoc`, com `l.trim()` não vazio e o fallback idêntico `categoria + data + primeiros 80 caracteres de assunto` quando `l` faltar.
6. Protocolo extraído de `onclick`, `NumeroProtocoloEntrega` e `OpenDownloadDocumentos` aparece só no diagnóstico e relatório.
7. Fixture de colisão com o mesmo protocolo e dois links prova `colisao_protocolo_para_revisao`, preserva os dois registros e não deduplica silenciosamente.
8. Os 24 `zip_only` e 84 `portal_only` ficam relatados e preservados, nunca apagados silenciosamente.
9. Fixtures cobrem os 24 exclusivos da referência e, de forma dirigida, os cinco ausentes do payload bruto, três da Tapajós Transmissora e dois do Grupo Casas Bahia.
10. Fixture de `Calendário de Eventos Corporativos` prova preservação de documento exclusivo do ZIP.
11. `Fato Relevante` aparece no portal e passa pelo filtro. Medição em 08/09 trouxe 4 e em 10/09 trouxe 2.
12. Prova negativa com `empresa='-1'` falha semanticamente apesar de HTTP 200.
13. Retry prova recuperação e esgotamento.
14. Guarda prova aceitação e bloqueio.
15. Gate só aprova com diferenças estruturais zero nos comuns ou exceção classificada e reproduzida por fixture.
16. Testes provam reconciliação ZIP em até sete dias, merge conservador e preservação dos `zip_only` entre reconciliações.
17. Testes provam 404 do ZIP rebaixado somente com reconciliação recente, gate aprovado e preservação comprovada.
18. Nenhuma segunda tabela de alias, documento ou atribuição.
19. Nenhum secret novo.
20. `git diff --check` limpo.
21. `cd api && npm ci && npm test` verde.
22. Deploy somente com autorização e script canônico.
23. Health de produção colado depois do deploy, incluindo versão, origem composta, max `Data_Entrega`, SHA-256 convergido, contagem, quatro lotes válidos, última reconciliação ZIP, comuns, `portal_only`, `zip_only`, gate e motivo.
24. Teste prova conservação somente até o TTL de 30 dias, expiração sem escrita válida, `base_expirada_ttl`, gate bloqueado e ausência marcada no health.

## 15. Incertezas que permanecem

1. `Calendário de Eventos Corporativos` não apareceu em 08/09, 10/09 ou 12/09, nem na janela comparada. ENETWeb não pode ser declarado fonte dessa categoria com a evidência atual.
2. Há cinco protocolos do snapshot que não aparecem no payload bruto atual. A causa individual não foi provada.
3. Há 19 protocolos do snapshot presentes no payload bruto, mas sem correspondência no cadastro atual por Código CVM. O fallback nominal precisa de teste dirigido para entidades estrangeiras e companhias cujo registro mudou.
4. A URL canônica respondeu HTTP 200 e entregou PDF em uma medição, mas o servidor anuncia `text/html` e teve reset em outra leitura. A validação correta é magic bytes `%PDF`, não apenas status ou `Content-Type`.
5. A régua de 70% é sustentada pelos dois acervos disponíveis, mas ainda não tem oito ciclos de sazonalidade. Recalibrar depois do shadow, sem reduzir o piso durante incidente.
