# positioning.md — Posicionamento (VIX Radar)

Como o VIX Radar se posiciona no mercado e no funil. Base para o ângulo de toda peça.

## Frase de posicionamento

Para o buy-side de crédito privado que não tem (ou não quer pagar) um terminal Bloomberg, o VIX Radar é a camada de inteligência que transforma a varredura manual de CVM, ratings e imprensa em sinal acionável ranqueado por materialidade — por uma fração do custo de um terminal.

## Contra o quê competimos (as duas alternativas reais)

1. **Contra a planilha e o trabalho manual.** A maioria monitora emissores no braço: abre CVM, ANBIMA, lê imprensa, atualiza uma planilha. É lento, não escala para mais de 100 emissores, e o evento crítico chega depois do mercado. Nosso ângulo: "o default aparece no home broker antes de aparecer na sua planilha".
2. **Contra o terminal caro.** Quantum Axis, Economatica e afins vendem dado bruto por R$ 2-3 mil por licença/mês. Entregam base, não sinal — o analista ainda faz a triagem. Nosso ângulo: sinal já ranqueado, por R$ 119-490.

## Quadrante competitivo

Dois eixos: "dado bruto ↔ sinal acionável" e "caro ↔ acessível". O quadrante "sinal acionável + acessível" está estruturalmente vazio no Brasil. O VIX Radar é o único ocupante. Não competimos em cobertura de base com terminal; competimos em velocidade de sinal e custo.

## Diferenciais que ninguém mais tem

- **Verificação adversarial:** o evento crítico é desafiado por um segundo modelo antes de publicar. Reduz falso positivo — caro para quem age sobre o sinal.
- **Lei Zero:** só entra evento com fonte primária verificável. Sem alucinação, sem "achismo de IA".
- **EWS (Early Warning Score):** antecipação, não retrato.
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

Regra de funil: para público frio no LinkedIn, o CTA primário é a **newsletter**, não "solicite demo". A demo/solicitação de acesso fica para o público quente (retargeting de quem já engajou ou visitou o site).

## Mensagem por estágio de funil

- **Topo (frio):** dor + autoridade. CTA newsletter. "Você monitora crédito privado no Excel. O evento chega tarde. Recebe nosso boletim semanal?"
- **Meio (morno):** prova + método. CTA material/Lead Gen Form (relatório de emissor, framework de risco).
- **Fundo (quente):** produto + preço. CTA solicitar acesso / falar com o time.
