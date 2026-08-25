import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// EMAILSILENT1 (auditoria 2026-08-24).
//
// Cinco caminhos de envio transacional ao usuario final engoliam a falha da
// Resend. Quatro tinham `catch {}` literalmente vazio (handleAdminAprovar,
// handleAdminRejeitar e os dois ramos de handleEmailActionConfirm) e o quinto,
// handleSolicitarReset, tinha um console.error solto e mais nada. O efeito era
// sempre o mesmo: a API respondia ok:true tivesse a mensagem saido ou nao, e a
// unica fonte que sabia a verdade era o painel da Resend, fora do sistema.
//
// O caso real: joao.tavano@mirabaud.com.br foi aprovado, o painel exibiu "Joao
// Tavano aprovado", e nao havia como saber se o e-mail chegou. Dominio
// corporativo recusando remetente e o desfecho mais provavel e o mais invisivel,
// porque a recusa acontece do lado de la e nunca virou excecao aqui dentro.
//
// A prova aqui e de DUAS PONTAS, como manda a regra 5 do CLAUDE.md:
//   - a falha de envio passa a ser registrada, e a acao primaria continua valendo
//   - o caminho feliz continua passando, com id da Resend gravado
// Um teste so do lado ruim esconderia o caso de a instrumentacao ter quebrado o
// envio bom; um teste so do lado bom e o estado anterior a esta correcao.
//
// Determinismo do envio: o outboundService em vitest.config.mts intercepta
// api.resend.com e decide pelo endereco do destinatario. Dominio
// "falha-envio.example" volta 422 (recusa por dominio, exatamente o caso real),
// qualquer outro volta 200 com id "mock-resend-id-0001".

const ADMIN_SENHA = "test-admin-password-nao-usar-em-producao"; // igual ao vars do wrangler.test.jsonc
const DOMINIO_QUE_FALHA = "falha-envio.example";

function ipAleatorio() {
  return "198.51.100." + Math.floor(Math.random() * 200 + 10);
}

function postar(payload) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ipAleatorio() },
    body: JSON.stringify(payload),
  });
}

async function registrar(email) {
  const r = await postar({
    action: "registrar",
    nome: "Fulano Teste",
    email,
    empresa: "Empresa Teste",
    senha: "senha-de-teste-123",
    consentimento_lgpd: true,
  });
  expect(r.status).toBe(200);
  return r;
}

function aprovar(email) {
  return postar({ action: "admin_aprovar", admin_senha: ADMIN_SENHA, email });
}

function rejeitar(email) {
  return postar({ action: "admin_rejeitar", admin_senha: ADMIN_SENHA, email });
}

// Le o rastro direto do KV, sem passar pelo endpoint de consulta. Se o assert
// dependesse do proprio endpoint novo, um bug que fizesse os dois lerem a mesma
// chave errada passaria despercebido.
async function rastroDoKv(email) {
  const lista = await env.RADAR_KV.list({ prefix: "email_envio:" + email.toLowerCase() + ":" });
  const registros = [];
  for (const k of lista.keys) {
    const raw = await env.RADAR_KV.get(k.name);
    if (raw) registros.push(JSON.parse(raw));
  }
  return registros;
}

describe("EMAILSILENT1: falha de envio deixa de ser silenciosa", () => {
  it("PONTA RUIM: envio falha, a aprovacao continua valendo e a resposta admite a falha", async () => {
    const email = "recusado-pelo-dominio@" + DOMINIO_QUE_FALHA;
    await registrar(email);

    const r = await aprovar(email);
    expect(r.status).toBe(200);
    const body = await r.json();

    // A aprovacao NAO virou fail-closed. Este assert e o que impede que uma
    // futura "melhoria" transforme falha de e-mail em falha de aprovacao.
    expect(body.ok).toBe(true);

    // E a resposta parou de mentir. Antes do fix nao existia campo nenhum aqui
    // capaz de distinguir enviado de nao enviado.
    expect(body.email_enviado).toBe(false);
    expect(body.email_erro).toBeTruthy();
    expect(String(body.email_erro)).toContain("422");
    expect(body.mensagem).toContain("NAO saiu");

    // A aprovacao valeu de verdade, nao so no texto: usuario aprovado loga.
    const login = await postar({ action: "login", email, senha: "senha-de-teste-123" });
    expect(login.status).toBe(200);
    expect((await login.json()).token).toBeTruthy();

    // E ficou rastro consultavel, que era o que nao existia em canto nenhum.
    const rastro = await rastroDoKv(email);
    expect(rastro.length).toBe(1);
    expect(rastro[0].ok).toBe(false);
    expect(rastro[0].evento).toBe("aprovacao_admin");
    expect(rastro[0].email).toBe(email);
    expect(rastro[0].resend_id).toBeNull();
    expect(String(rastro[0].erro)).toContain("422");
  });

  it("PONTA BOA: envio funciona, resposta confirma e o id da Resend fica gravado", async () => {
    const email = "aprovado-normal@example.com";
    await registrar(email);

    const r = await aprovar(email);
    expect(r.status).toBe(200);
    const body = await r.json();

    expect(body.ok).toBe(true);
    expect(body.email_enviado).toBe(true);
    expect(body.email_erro).toBeNull();
    // O id ja voltava de enviarResend antes desta correcao e era jogado fora por
    // todos os call sites de producao. Agora e persistido, e e ele que permite
    // cruzar com o painel da Resend.
    expect(body.resend_id).toBe("mock-resend-id-0001");
    expect(body.mensagem).not.toContain("NAO saiu");

    const rastro = await rastroDoKv(email);
    expect(rastro.length).toBe(1);
    expect(rastro[0].ok).toBe(true);
    expect(rastro[0].resend_id).toBe("mock-resend-id-0001");
    expect(rastro[0].erro).toBeNull();
  });

  it("rejeicao pelo painel admin tem o mesmo tratamento nas duas pontas", async () => {
    const ruim = "rejeitado-sem-aviso@" + DOMINIO_QUE_FALHA;
    await registrar(ruim);
    const rRuim = await rejeitar(ruim);
    const bRuim = await rRuim.json();
    expect(bRuim.ok).toBe(true);
    expect(bRuim.email_enviado).toBe(false);
    expect((await rastroDoKv(ruim))[0].evento).toBe("rejeicao_admin");

    const bom = "rejeitado-com-aviso@example.com";
    await registrar(bom);
    const rBom = await rejeitar(bom);
    const bBom = await rBom.json();
    expect(bBom.ok).toBe(true);
    expect(bBom.email_enviado).toBe(true);
    expect(bBom.resend_id).toBe("mock-resend-id-0001");
  });

  it("reset de senha grava o rastro sem revelar nada ao chamador", async () => {
    const email = "reset-que-falha@" + DOMINIO_QUE_FALHA;
    await registrar(email);
    await aprovar(email); // reset so envia para conta aprovada

    const r = await postar({ action: "solicitar_reset", email });
    expect(r.status).toBe(200);
    const body = await r.json();

    // Aqui a resposta NAO passa a distinguir os desfechos, e isso e deliberado:
    // dizer "o envio falhou" contaria ao anonimo que a conta existe e esta
    // aprovada, que e justamente o que a mensagem generica protege. Anti
    // enumeracao vale mais que a conveniencia do aviso.
    expect(body.ok).toBe(true);
    expect(body.mensagem).toContain("Se o e-mail estiver cadastrado");
    expect(body.email_enviado).toBeUndefined();
    expect(body.email_erro).toBeUndefined();

    // O operador, esse sim, fica sabendo: o rastro tem a aprovacao e o reset.
    const rastro = await rastroDoKv(email);
    const reset = rastro.filter((x) => x.evento === "reset_senha");
    expect(reset.length).toBe(1);
    expect(reset[0].ok).toBe(false);
  });

  it("admin_email_envios devolve o historico por destinatario, com bounce e complaint", async () => {
    const email = "consulta-historico@example.com";
    await registrar(email);
    await aprovar(email);

    // Bounce e complaint sao gravados pelo webhook da Resend, que ja existia.
    // Semeados direto no KV com as MESMAS chaves do handleResendWebhook para
    // provar que a consulta cruza os dois acervos em vez de duplicar um terceiro.
    await env.RADAR_KV.put(
      "bounce:" + email + ":20260824120000000",
      JSON.stringify({ type: "email.bounced", email, ts: "2026-08-24T12:00:00.000Z", reason: "mailbox_full" })
    );
    await env.RADAR_KV.put("complaint:" + email, JSON.stringify({ type: "email.complained", email, ts: "2026-08-24T13:00:00.000Z" }));

    const r = await postar({ action: "admin_email_envios", admin_senha: ADMIN_SENHA, email });
    expect(r.status).toBe(200);
    const body = await r.json();

    expect(body.ok).toBe(true);
    expect(body.total).toBe(1);
    expect(body.falhas).toBe(0);
    expect(body.envios[0].resend_id).toBe("mock-resend-id-0001");
    expect(body.bounces.length).toBe(1);
    expect(body.bounces[0].reason).toBe("mailbox_full");
    expect(body.complaint).not.toBeNull();
    // Lista vazia tem duas leituras (nunca enviamos, ou o TTL levou). O campo
    // impede confundir silencio com ausencia, que e o erro que abriu a auditoria.
    expect(body.retencao_dias).toBe(90);
  });

  it("aprovar quem ja esta aprovado devolve email_enviado null, nao false", async () => {
    const email = "ja-aprovado@example.com";
    await registrar(email);
    await aprovar(email);

    const r = await aprovar(email); // segunda vez, nada muda e nada e enviado
    const body = await r.json();
    expect(body.ok).toBe(true);
    expect(body.mensagem).toContain("aprovado");

    // Tri-estado deliberado: null e "nao tentou", false e "tentou e falhou".
    // Se este campo virasse false aqui, quem testa `if (!r.email_enviado)`
    // avisaria falha de envio num caminho onde nada foi enviado porque nada
    // mudou. E se virasse undefined, seria a forma antiga, a que mentia.
    expect(body.email_enviado).toBeNull();

    // E o rastro nao ganhou registro novo: continua so o do primeiro aprovar.
    expect((await rastroDoKv(email)).length).toBe(1);
  });

  it("admin_email_envios exige a senha de admin", async () => {
    const r = await postar({ action: "admin_email_envios", admin_senha: "senha-errada", email: "qualquer@example.com" });
    expect(r.status).toBe(403);
    expect((await r.json()).ok).toBe(false);
  });
});
