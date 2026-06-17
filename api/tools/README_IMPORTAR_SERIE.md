# Importador de Séries Históricas de Debêntures

Self-contained script Python para normalização de dados de séries históricas de debêntures em múltiplos formatos para o schema padrão do VIX Radar.

## Instalação

Dependências opcionais (já presentes em ambientes padrão):
```bash
pip install openpyxl requests  # openpyxl para Excel, requests para upload
```

## Uso

### Modo básico (normalizar para CSV)
```bash
python importar_serie_mercado.py entrada.csv --output serie_normalizado.csv --verbose
python importar_serie_mercado.py entrada.xlsx --output serie_normalizado.csv
```

### Modo com upload ao Worker
```bash
python importar_serie_mercado.py entrada.csv \
  --output serie_normalizado.csv \
  --upload \
  --endpoint https://radar-credito-api.prospects-intel.workers.dev \
  --admin-senha "RadarAdmin@2026" \
  --verbose
```

### Modo dry-run (simula sem escrever)
```bash
python importar_serie_mercado.py entrada.csv --dry-run --verbose
```

## Formatos suportados

### 1. Excel Quantum Finance (.xlsx)
- Detecta abas contendo "deben" no nome
- Colunas: Emissor/Empresa, Data, Taxa Indicativa (%), PU, Duration, Volume, Nº Negócios, Maior Negócio
- Taxa em % é convertida automaticamente para bps (×100)

### 2. CSV ANBIMA
- Colunas: NomeEmissor, DataReferencia, SpreadMid, PUMid, Duration, Volume, Negocios, MaiorNegocio
- Suporta variantes camelCase, snake_case, espaços
- Separador auto-detectado (`;` ou `,`)

### 3. CSV B3 UP2DATA (Renda Fixa)
- Heurística baseada em nomes de colunas
- **TODO:** validar contra arquivo real da B3

## Schema de saída

Arquivo CSV com separador `;`:
```
empresa;data;spread_bps;pu_indicativo;duration;volume;negocios;maior_negocio
AUREN ENERGIA;2026-04-10;250;95.5;3.25;1500000;5;500000
```

- **empresa**: uppercase, trimmed
- **data**: YYYY-MM-DD (normaliza automáticamente de DD/MM/YYYY, DD-MM-YYYY, etc)
- **spread_bps**: numérico em basis points
- **pu_indicativo**: numérico (preço unitário)
- **duration**: numérico em anos (Macaulay/modificada)
- **volume**: numérico em reais
- **negocios**: inteiro (quantidade de negócios)
- **maior_negocio**: numérico em reais

## Validações

- Data em formato reconhecível (se não, rejeitada com log)
- Empresa não vazia
- Deduplicação por (empresa, data) mantendo última ocorrência
- Spread tolera vírgula decimal
- Detalhes de rejeições em `--verbose`

## Exemplo de entrada

```
NomeEmissor;DataReferencia;SpreadMid;PUMid;Duration;Volume;Negocios;MaiorNegocio
Auren Energia;2026-04-10;250;95.50;3.25;1500000;5;500000
Energisa;2026-04-10;180;97.20;2.80;2500000;8;750000
```

## Saída do script

```
[Ingestão] Lendo exemplo.csv
[Formato] ANBIMA
[Raw] 6 registros lidos
[Normalizado] 6 registros válidos, 0 rejeitados
[Período] 2026-04-09 a 2026-04-10
[Empresas] 5 únicas: AEGEA SANEAMENTO, AUREN ENERGIA, ...
[Saída] serie_normalizado.csv (6 linhas)
[Concluído]
```

## Upload ao Worker

O modo `--upload` quebra o CSV em batches (~50 linhas cada) e envia ao endpoint `admin_ingestao_csv` do Worker.

**Requisito:** Worker v4.8.8+ (patch em desenvolvimento).

Se o endpoint não existir ainda, erro 404 indica que o patch não foi deployado.

### Retry logic
- Até 3 tentativas por batch
- Backoff exponencial (2^retry segundos)
- Fail-fast em HTTP 404 (endpoint não existe)

## Estrutura interna

- **detect_file_format()**: auto-detecta Excel vs CSV
- **read_excel()**: parse openpyxl com heurística de colunas
- **read_csv()**: parse flexível com mapeamento de nomes de coluna
- **normalize_records()**: validação, dedup, normalização
- **export_csv()**: escrita em schema padrão
- **upload_csv()**: POST ao Worker em batches

## Dependências

- Python 3.7+
- `openpyxl` (opcional, para Excel)
- `requests` (opcional, para upload)

Se ausente, mensagem clara pedindo `pip install <lib>`.

## Licença

Parte do projeto VIX Radar.
