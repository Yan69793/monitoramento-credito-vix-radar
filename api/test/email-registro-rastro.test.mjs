import { SELF, env } from "cloudflare:test";
import { bootstrapIndiceQuarentena } from "./_quarentena-idx.mjs";
import { beforeEach, describe, expect, it } from "vitest";

// REPROVADO-FAILCLOSED1 (2026-09-06): gates sao fail-closed; indice ausente = erro.
beforeEach(async () => { await bootstrapIndiceQuarentena(env); });

// EMAILSILENT1 RESIDUAL — os DOIS envios de `handleRegistrar` (worker.js:6265 e :6307).
//
// EMAILSILENT1 fechou os 5 envios ao usuario final (aprovar, rejeitar, os dois ramos de
// confirmacao por e-mail e o reset) com `enviarEmailRastreado`. Ficaram de fora os dois
// avisos ao ADMIN dentro de `handleRegistrar`: o de solicitacao nova e o de reenvio de
// pendente com +24h. Os dois chamavam `enviarResend` cru.
//
// O que este arquivo prova (regra 5 do CLAUDE.md, duas pontas + lote misto + resiliencia):
//   - sucesso: rastro `ok:true` com `resend_id` no KV, para o destinatario admin;
//   - falha de provedor: recusa por dominio do destinatario (422 do mock) vira rastro `ok:false`
//     com o motivo, e a resposta HTTP continua 200 identica a do caminho feliz;
//   - chave ausente: RESEND_API_KEY ausente gera rastro `ok:false` explicitando "RESEND_API_KEY ausente"
//     sem lancar excecao e mantendo retorno 200;
//   - lote misto: dois envios na mesma rodada, um falhando e o outro nao, com o rastro
//     de cada um contabilizado separadamente (sem "tudo verde" e sem "tudo vermelho");
//   - reenvio com sucesso: grava dedupKey no KV para evitar spam ao admin nas proximas 24h;
//   - reenvio com falha: NAO grava dedupKey quando o envio falha, permitindo nova tentativa imediata;
//   - anti-enumeracao: quem se cadastra recebe a mesma mensagem exista ou nao o e-mail, e falhe ou nao o aviso.

const DOMINIO_QUE_FALHA = "falha-envio.example";

let seqAdmin = 0;
function adminUnico(dominio) {
  seqAdmin++;
  return "admin-t" + seqAdmin + "@" + dominio;
}

let seqCand = 0;
function candidatoUnico() {
  seqCand++;
  return "candidato-t" + seqCand + "@example.com";
}

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

async function rastroDoKv(email) {
  const lista = await env.RADAR_KV.list({ prefix: "email_envio:" + email.toLowerCase() + ":" });
  const registros = [];
  for (const k of lista.keys) {
    const raw = await env.RADAR_KV.get(k.name);
    if (raw) registros.push(JSON.parse(raw));
  }
  return registros;
}

async function hashEmail(e) {
  const d = new TextEncoder().encode(String(e || "").toLowerCase().trim());
  const h = await crypto.subtle.digest("SHA-256", d);
  return Array.from(new Uint8Array(h)).map(b => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
}

async function comAdminEmail(valor, fn) {
  const anterior = env.ADMIN_EMAIL;
  env.ADMIN_EMAIL = valor;
  try {
    return await fn();
  } finally {
    env.ADMIN_EMAIL = anterior;
  }
}

async function comResendApiKey(valor, fn) {
  const anterior = env.RESEND_API_KEY;
  env.RESEND_API_KEY = valor;
  try {
    return await fn();
  } finally {
    env.RESEND_API_KEY = anterior;
  }
}

describe("EMAILSILENT1 residual: aviso ao admin no handleRegistrar tambem deixa rastro", () => {
  it("PONTA BOA: solicitacao nova registra rastro ok:true com o id da Resend", async () => {
    const admin = adminUnico("example.com");
    await comAdminEmail(admin, async () => {
      const email = candidatoUnico();
      const r = await registrar(email);
      const body = await r.json();
      expect(body.ok).toBe(true);

      const rastro = await rastroDoKv(admin);
      expect(rastro.length).toBe(1);
      expect(rastro[0].ok).toBe(true);
      expect(rastro[0].evento).toBe("registro_novo_admin");
      expect(rastro[0].email).toBe(admin);
      expect(rastro[0].resend_id).toBe("mock-resend-id-0001");
      expect(rastro[0].erro).toBeNull();
    });
  });

  it("PONTA RUIM (provedor): aviso recusado vira rastro ok:false e a resposta nao muda", async () => {
    const adminOk = adminUnico("example.com");
    const msgOk = await comAdminEmail(adminOk, async () => (await (await registrar(candidatoUnico())).json()).mensagem);

    const adminRuim = adminUnico(DOMINIO_QUE_FALHA);
    const msgRuim = await comAdminEmail(adminRuim, async () => {
      const r = await registrar(candidatoUnico());
      expect(r.status).toBe(200);
      return (await r.json()).mensagem;
    });

    expect(msgRuim).toBe(msgOk);
    expect(String(msgRuim).length).toBeGreaterThan(10);

    const rastro = await rastroDoKv(adminRuim);
    expect(rastro.length).toBe(1);
    expect(rastro[0].ok).toBe(false);
    expect(rastro[0].evento).toBe("registro_novo_admin");
    expect(rastro[0].resend_id).toBeNull();
    expect(String(rastro[0].erro)).toContain("422");

    const rastroOk = await rastroDoKv(adminOk);
    expect(rastroOk.length).toBe(1);
    expect(rastroOk[0].ok).toBe(true);
  });

  it("CHAVE AUSENTE: RESEND_API_KEY ausente registra rastro ok:false sem quebrar o cadastro 200", async () => {
    const admin = adminUnico("example.com");
    await comAdminEmail(admin, async () => {
      await comResendApiKey("", async () => {
        const r = await registrar(candidatoUnico());
        const body = await r.json();
        expect(body.ok).toBe(true);
        expect(body.mensagem).toBe("Solicitação enviada. Aguarde aprovação.");

        const rastro = await rastroDoKv(admin);
        expect(rastro.length).toBe(1);
        expect(rastro[0].ok).toBe(false);
        expect(rastro[0].evento).toBe("registro_novo_admin");
        expect(rastro[0].erro).toBe("RESEND_API_KEY ausente");
      });
    });
  });

  it("LOTE MISTO: um envio falha e o outro nao, cada um com o seu rastro", async () => {
    const adminRuim = adminUnico(DOMINIO_QUE_FALHA);
    const adminBom = adminUnico("example.com");
    const mensagens = [];

    mensagens.push(await comAdminEmail(adminRuim, async () => {
      const r = await registrar(candidatoUnico());
      expect(r.status).toBe(200);
      return (await r.json()).mensagem;
    }));

    mensagens.push(await comAdminEmail(adminBom, async () => {
      const r = await registrar(candidatoUnico());
      expect(r.status).toBe(200);
      return (await r.json()).mensagem;
    }));

    expect(mensagens[0]).toBe(mensagens[1]);

    const rastroRuim = await rastroDoKv(adminRuim);
    const rastroBom = await rastroDoKv(adminBom);
    expect(rastroRuim.length).toBe(1);
    expect(rastroBom.length).toBe(1);
    expect(rastroRuim[0].ok).toBe(false);
    expect(rastroBom[0].ok).toBe(true);
    expect(rastroBom[0].resend_id).toBe("mock-resend-id-0001");
    expect(rastroRuim[0].ok).not.toBe(rastroBom[0].ok);
  });

  it("REENVIO COM SUCESSO: grava dedupKey no KV e registra evento registro_reenvio_admin", async () => {
    const admin = adminUnico("example.com");
    await comAdminEmail(admin, async () => {
      const email = candidatoUnico();
      const r1 = await registrar(email);
      expect((await r1.json()).ok).toBe(true);

      const h = await hashEmail(email);
      const dedupKey = "cadastro:notif_reenvio:" + h;

      expect(await env.RADAR_KV.get(dedupKey)).toBeNull();

      const r2 = await registrar(email);
      const body2 = await r2.json();
      expect(body2.ok).toBe(true);
      expect(body2.mensagem).toBe("Sua solicitação já está na fila de aprovação.");

      expect(await env.RADAR_KV.get(dedupKey)).toBe("1");

      const rastro = await rastroDoKv(admin);
      expect(rastro.length).toBe(2);
      const evs = rastro.map(x => x.evento);
      expect(evs).toContain("registro_novo_admin");
      expect(evs).toContain("registro_reenvio_admin");
      expect(rastro.every(x => x.ok === true)).toBe(true);

      const r3 = await registrar(email);
      expect((await r3.json()).ok).toBe(true);
      const rastro3 = await rastroDoKv(admin);
      expect(rastro3.length).toBe(2);
    });
  });

  it("REENVIO COM FALHA: falha de envio NAO grava dedupKey, permitindo nova tentativa", async () => {
    const adminRuim = adminUnico(DOMINIO_QUE_FALHA);
    await comAdminEmail(adminRuim, async () => {
      const email = candidatoUnico();
      await registrar(email);

      const h = await hashEmail(email);
      const dedupKey = "cadastro:notif_reenvio:" + h;

      const r2 = await registrar(email);
      expect(r2.status).toBe(200);
      expect((await r2.json()).mensagem).toBe("Sua solicitação já está na fila de aprovação.");

      expect(await env.RADAR_KV.get(dedupKey)).toBeNull();

      const rastro = await rastroDoKv(adminRuim);
      expect(rastro.length).toBe(2);
      expect(rastro[1].evento).toBe("registro_reenvio_admin");
      expect(rastro[1].ok).toBe(false);
      expect(String(rastro[1].erro)).toContain("422");
    });
  });
});
