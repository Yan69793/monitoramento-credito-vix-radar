---
name: igor-apresentacao
description: Apresentacao VIX Radar para Igor Giesteira (Bradesco BBI), envio agendado 27/07 10h, conta demo, Worker v4.9.181
metadata:
  type: project
---

# Apresentacao Igor Giesteira (Bradesco BBI) — 2026-07-25

## Contexto

Igor e amigo do Yan, trabalha no Bradesco BBI, vai apresentar o VIX Radar para contatos dele.
Objetivo: parceria e demonstracao de capacidade tecnica. Sem precos, sem mencao a Bradesco.

## Entregaveis

- Apresentacao: `https://vixradar.com/apresentacao` — 21 slides, dark luxury (navy + gold)
- Conta demo: `demo@vixradar.com` / `VixRadarDemo2026!` — ativa (criada e aprovada 25/07)
- Landing page: `https://vixradar.com`
- Worker: v4.9.181 (endpoint `email_enviar` para envio de email personalizado, admin)

## Envio agendado

- Cron: 7132d3dd — 27/07/2026 09:57 BRT
- Destinatario: igor.giesteira@gmail.com
- Remetente: Szuchmacher Consultoria (szuchmacheryan@gmail.com)
- Via: endpoint `email_enviar` do Worker (Resend internamente)
- Assunto: "VIX Radar - Apresentacao Institucional | Szuchmacher Consultoria"
- Email aprovado pelo Yan em 25/07

## O que esta no email

- Links: vixradar.com/apresentacao, vixradar.com
- Credenciais demo: demo@vixradar.com / VixRadarDemo2026!
- Diferencial: IA + verificacao adversarial (sem precos)
- Tom: institucional, direto, sem mencionar que Igor vai apresentar

## Historico de alteracoes

- 25/07 00:00: Apresentacao HTML criada baseada no deck Bradesco (sem precos)
- 25/07 01:00: Deploy da apresentacao em vixradar.com/apresentacao
- 25/07 02:20: Worker v4.9.181 deployado com endpoint email_enviar
- 25/07 02:45: Email de teste enviado para Yan (newsletter + reset + personalizado)
- 25/07 03:00: Conta demo trocada de demo.bradesco para demo@vixradar.com
- 25/07 03:15: Apresentacao atualizada com nova conta demo, deploy Pages
- 25/07 03:20: Email final aprovado pelo Yan, cron reagendado
