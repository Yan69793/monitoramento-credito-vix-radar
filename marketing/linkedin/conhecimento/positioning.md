# positioning.md — Posicionamento (VIX Radar)

v2 — atualizado em 13/07/2026 com pesquisa de contraposicionamento (ver `pesquisa-mercado.md` seção 6). Como o VIX Radar se posiciona no mercado e no funil. Base para o ângulo de toda peça.

## Frase de posicionamento

Para o buy-side de crédito privado que não tem (ou não quer pagar) um terminal Bloomberg, o VIX Radar é a camada de inteligência que transforma a varredura manual de CVM, ratings e imprensa em sinal acionável ranqueado por materialidade — por uma fração do custo de um terminal.

## Contra o quê competimos (revisado — contraposicionamento, não corrida de preço)

O erro mais comum de produto novo e mais barato é liderar a mensagem com "somos mais baratos" — é a posição que o incumbente caro está mais preparado para destruir, porque ele tem caixa para simplesmente baixar o próprio preço e esmagar o desafiante.

**O concorrente real do VIX Radar não é o terminal caro. É a planilha manual e o "não fazer nada".** A maioria monitora emissores no braço: abre CVM, ANBIMA, lê imprensa, atualiza uma planilha. É lento, não escala para mais de 100 emissores, e o evento crítico chega depois do mercado. Nosso ângulo: "o default aparece no home broker antes de aparecer na sua planilha".

**Contra o terminal caro, a postura correta é reconhecer a força dele antes de explicar por que não é para isso que ele foi feito.** Um terminal robusto resolve renda variável, trading global, mensageria, research cross-asset — e custa como resolve tudo isso. Se o problema do cliente é mais estreito (saber quando um emissor de crédito privado brasileiro se deteriora), ele paga por uma plataforma inteira para usar uma fração dela. O VIX Radar não tenta substituir terminal nenhum — resolve só essa fatia, e por isso custa uma fração. O preço vem depois dessa explicação, nunca antes.

## Quadrante competitivo

Dois eixos: "dado bruto ↔ sinal acionável" e "caro ↔ acessível". O quadrante "sinal acionável + acessível" está estruturalmente vazio no Brasil. O VIX Radar é o único ocupante. Não competimos em cobertura de base com terminal; competimos em velocidade de sinal e foco.

## Diferenciais que ninguém mais tem

- **Verificação adversarial:** o evento crítico é desafiado por um segundo modelo antes de publicar. Reduz falso positivo — caro para quem age sobre o sinal. Responde de frente à objeção óbvia de "confiar em IA para dado sensível" (padrão usado por concorrentes internacionais como 9fin — "AI you can trust" — o VIX Radar tem a mesma resposta, com mecanismo próprio).
- **Lei Zero:** só entra evento com fonte primária verificável. Sem alucinação, sem "achismo de IA".
- **EWS (Early Warning Score):** antecipação, não retrato. Território que nenhuma big player brasileira pesquisada (Quantum, Economatica) nomeia dessa forma — espaço de linguagem livre para o VIX Radar reivindicar no Brasil, mesmo já sendo usado por players internacionais como Credit Benchmark ("early warning credit risk signals").
- **Materialidade 0-100:** filtro que separa fato que move preço de ruído protocolar.

## Jobs-to-be-done (o que o cliente "contrata" o produto para fazer)

- Saber do evento de crédito antes do mercado precificar.
- Cobrir 100+ emissores sem contratar mais um analista nem pagar terminal.
- Levar ao comitê uma decisão com fonte rastreável.
- Parar de começar o dia varrendo CVM na mão.

## Funil e papel da newsletter (topo de funil)

O produto é pago e o acesso ao painel é por aprovação — não é freemium. Isso torna o topo de funil crítico: a **newsletter/boletim gratuito** (`boletim@vixradar.com`) é a porta de entrada e o principal ativo de captura de lead.

Fluxo de captura recomendado (a confirmar/instrumentar antes de escalar tráfego para ela):

1. **Landing de captura dedicada** (ex.: vixradar.com/newsletter ou um LinkedIn Lead Gen Form) — headline com a promessa do boletim (ex.: "Os eventos de crédito privado que moveram o mercado, toda semana, no seu e-mail"), campo de e-mail corporativo + empresa. Verificar se essa landing dedicada já existe; se não, é pré-requisito para a fase de captação.
2. **Confirmação (double opt-in) via Resend** — e-mail de confirmação para validar o endereço e cumprir boas práticas de deliverability/LGPD.
3. **Entrega semanal do boletim** com um recorte de valor real (os N eventos mais materiais da semana, sem paywall).
4. **One-click unsubscribe com HMAC** — já implementado no sistema; manter.
5. **Nurture → oferta de acesso ao painel** — depois de algumas edições, CTA de "Solicitar acesso" ao painel (conversão para pago).

Regra de funil: para público frio no LinkedIn, o CTA primário é a **newsletter**, não "solicite demo". A demo/solicitação de acesso fica para o público quente (retargeting de quem já engajou ou visitou o site). Todo post orgânico ou anúncio deve mencionar **www.vixradar.com** explicitamente — gera preview de link automático e é o ponto de entrada mínimo, mesmo quando o CTA principal é outro.

## Mensagem por estágio de funil

- **Topo (frio):** dor + autoridade. Gancho tipo Story/Statement (nunca pergunta — ver `copy-rules.md`). CTA newsletter + link.
- **Meio (morno):** prova + método. CTA material/Lead Gen Form (relatório de emissor, framework de risco).
- **Fundo (quente):** produto + preço, nessa ordem — nunca preço primeiro. CTA solicitar acesso / falar com o time.
