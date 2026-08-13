# 00 — Escopo da auditoria

**Data:** 2026-08-13
**Alvo:** landing pública `https://vixradar.com` (página única com modais e
âncoras) + formulário de login/solicitação de acesso (`#phAcesso`).
**Fonte de citações file:line:** `app/index.html` local
(`E:\Diretorio\Claude\FREQUENTE\Monitoramento de Credito\app\index.html`,
frontend único de ~700KB com CSS e JS inline, servido por Cloudflare Pages).

**Usuário primário:** gestor / investidor institucional de crédito privado
que visita o site pela primeira vez.
**Tarefa primária:** entender o que o produto faz e solicitar acesso ou
assinar um plano.

**Restrições:**
- Clientes estão usando a produção agora: captura só leitura e leve
  (poucas requisições, nada de escrita, nada de tela autenticada).
- Brand: navy `#001020`, gold `#B7985D`, fontes DM Sans + Cormorant Garamond
  + Inter (design system documentado no CLAUDE.md do projeto).
- Sem screenshots de dados de cliente; somente superfícies públicas.

**Referências:** deck institucional em `https://vixradar.com/apresentacao`
(21 slides, dark luxury navy + gold), produto pós-login fora de escopo
nesta rodada.

**Escopo fora:** área autenticada (painel, mercado, análise, agenda), painel
admin, páginas internas do Worker.
