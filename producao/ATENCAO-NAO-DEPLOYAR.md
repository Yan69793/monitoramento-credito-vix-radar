# ATENÇÃO — NÃO DEPLOYAR ESTE DIRETÓRIO

Este diretório contém uma versão **estática e desconectada** (v30/v40) do VIX Radar.

**Deployar este conteúdo regrediria produção de v4.9.109 para v30** — perda completa de:
- Autenticação JWT
- KV / Durable Object / Analytics Engine
- Cascade AI
- 103 emissores / 13 setores
- Todas as features implementadas de v4.7.x a v4.9.x

## O projeto real está em

```
E:\Diretorio\Claude\Monitoramento de Credito\
  api\v4.9.109.js     ← Worker em produção
  api\wrangler.toml   ← main = "v4.9.109.js"
  app\index.html      ← Frontend v201.51
  app\deploy_zip\     ← Artefato Pages
```

Deploy Worker: `cd api && npx wrangler deploy`
Deploy Pages: `npx wrangler pages deploy ./app/deploy_zip --project-name=radar-credito`

## Por que este diretório ainda existe

Preservado como referência histórica da versão original (v30/v40 estática).
Pode ser arquivado ou deletado — não tem valor operacional.

Adicionado: 2026-06-14
