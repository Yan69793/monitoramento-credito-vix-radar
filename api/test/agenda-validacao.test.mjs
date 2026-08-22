import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// CALVAL-V2 (v4.9.192): validacao de fonte da Agenda de Divulgacao de Resultados.
// Cobre as regras do pedido 2026-08-12: fonte primaria, nunca sobrescrever
// oficial com secundaria, cross-check, 5 status, nao inferir datas, trimestre
// fiscal, aliases, gate de publicacao e revalidacao (stale).
// Roda so em CI (worker-tests.yml): deploy-worker.ps1 faz `npm ci --omit=dev`,
// que apaga o vitest local (SACFALSA-RESIDUO, 2026-08-20 - a causa nao era Smart
// App Control bloqueando workerd.exe, medido e refutado). `npm ci` dentro de
// api/ restaura a suite localmente. A logica pura tambem e coberta pelo harness
// tests/system-final-regressions.mjs em Node puro, sem precisar subir Worker.

const ROUTINE_KEY = "test-routine-key-nao-usar-em-producao";
const JWT_SECRET = "test-jwt-secret-nao-usar-em-producao";
const ADMIN_PWD = "test-admin-password-nao-usar-em-producao";

// Data ISO N dias a partir de hoje (UTC). Evita datas fixas: o builder da
// agenda descarta datas passadas e o CI roda em relogio real.
function diasA(n) {
  return new Date(Date.now() + n * 864e5).toISOString().split("T")[0];
}

function b64urlBytes(bytes) {
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function mintJwt(secret, payload) {
  const enc = new TextEncoder();
  const header = b64urlBytes(enc.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = b64urlBytes(enc.encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(`${header}.${body}`));
  return `${header}.${body}.${b64urlBytes(new Uint8Array(sig))}`;
}

function postRoutine(body) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ routine_key: ROUTINE_KEY, ...body }),
  });
}

async function authHeaders() {
  const token = await mintJwt(JWT_SECRET, { email: "teste-calval@example.com", exp: Math.floor(Date.now() / 1e3) + 3600 });
  return { Authorization: `Bearer ${token}` };
}

async function getCalendario() {
  return SELF.fetch("https://example.com/?op=calendario", { method: "GET", headers: await authHeaders() });
}

async function getAgenda() {
  return SELF.fetch("https://example.com/?op=calendario&escopo=agenda&horizonte=90", { method: "GET", headers: await authHeaders() });
}

async function rebuild() {
  // O dispatch de op= roda no branch GET de __coreFetch.
  return SELF.fetch("https://example.com/?op=admin_agenda_rebuild", {
    method: "GET",
    headers: { "x-admin-password": ADMIN_PWD },
  });
}

describe("CALVAL-V2: validacao de fonte da agenda de resultados", () => {
  it("divergencia oficial x secundaria: data oficial vence e fica DIVERGENTE (regras 2/3)", async () => {
    const d30 = diasA(30);
    const d32 = diasA(32);
    const r1 = await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Petrobras",
      trimestres: [{ periodo: "3T26", data_prevista: d30, horario: "nao_informado", status: "agendado", url_fonte_primaria: "https://ri.petrobras.com.br/x" }],
    });
    expect(r1.status).toBe(200);
    expect((await r1.json()).ok).toBe(true);

    const r2 = await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Petrobras",
      trimestres: [{ periodo: "3T26", data_prevista: d32, status: "agendado", fonte: "https://www.infomoney.com.br/x" }],
    });
    expect(r2.status).toBe(200);

    const cal = await getCalendario();
    expect(cal.status).toBe(200);
    const body = await cal.json();
    const prox = body.emissores["Petrobras"].proxima_divulgacao;
    expect(prox.periodo).toBe("3T26");
    expect(prox.data_prevista).toBe(d30);
    expect(prox.status_validacao).toBe("DIVERGENTE");
    expect(prox.observacao_divergencia).toBeTruthy();
  });

  it("divergencia so entre secundarias: PENDENTE (regra 3)", async () => {
    const d37 = diasA(37);
    const r = await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Vale",
      trimestres: [{
        periodo: "3T26", data_prevista: d37, status: "agendado", fonte: "https://www.infomoney.com.br/x",
        divergencias: [{ fonte: "moneytimes.com.br", url: "https://www.moneytimes.com.br/y", data_alternativa: diasA(40) }],
      }],
    });
    expect(r.status).toBe(200);
    const body = await (await getCalendario()).json();
    expect(body.emissores["Vale"].proxima_divulgacao.status_validacao).toBe("PENDENTE");
  });

  it("alteracao posterior pelo RI vence e gera auditoria (regra 11)", async () => {
    const d30 = diasA(30);
    const d33 = diasA(33);
    await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Petrobras",
      trimestres: [{ periodo: "3T26", data_prevista: d30, status: "agendado", url_fonte_primaria: "https://ri.petrobras.com.br/x" }],
    });
    const r2 = await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Petrobras",
      trimestres: [{ periodo: "3T26", data_prevista: d33, status: "agendado", url_fonte_primaria: "https://ri.petrobras.com.br/x" }],
    });
    expect(r2.status).toBe(200);
    const body = await (await getCalendario()).json();
    const prox = body.emissores["Petrobras"].proxima_divulgacao;
    expect(prox.data_prevista).toBe(d33);
    expect(prox.status_validacao).toBe("CONFIRMADO_OFICIAL");
    expect(prox.auditoria.length).toBeGreaterThan(0);
    expect(prox.auditoria[0].motivo).toBe("correcao_ri");
    expect(prox.auditoria[0].data_anterior).toBe(d30);
    expect(prox.auditoria[0].data_nova).toBe(d33);
    expect(prox.auditoria[0].fonte).toBe("https://ri.petrobras.com.br/x");
    expect(prox.auditoria[0].timestamp).toBeTruthy();
  });

  it("resultado ja divulgado com fonte oficial: CONFIRMADO_OFICIAL (regras 4/9)", async () => {
    const dPast = diasA(-10);
    const r = await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Vale",
      trimestres: [{ periodo: "4T25", data_prevista: dPast, horario: "apos_fechamento", status: "divulgado", url_fonte_primaria: "https://ri.vale.com/x" }],
    });
    expect(r.status).toBe(200);
    const body = await (await getCalendario()).json();
    const ult = body.emissores["Vale"].ultima_divulgacao_prevista;
    expect(ult.periodo).toBe("4T25");
    expect(ult.status).toBe("divulgado");
    expect(ult.status_validacao).toBe("CONFIRMADO_OFICIAL");
    expect(ult.antes_ou_depois_do_fechamento).toBe("depois");
  });

  it("gate: evento de agenda confirmado so com fonte oficial ou cross-check (regra 10)", async () => {
    const d30 = diasA(30);
    // Petrobras com fonte oficial -> confirmado true
    await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Petrobras",
      trimestres: [{ periodo: "3T26", data_prevista: d30, status: "agendado", url_fonte_primaria: "https://ri.petrobras.com.br/x" }],
    });
    // Vale so com fonte secundaria unica -> PENDENTE, confirmado false
    await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Vale",
      trimestres: [{ periodo: "3T26", data_prevista: d30, status: "agendado", fonte: "https://www.infomoney.com.br/x" }],
    });
    const reb = await rebuild();
    expect(reb.status).toBe(200);
    expect((await reb.json()).ok).toBe(true);

    const ag = await (await getAgenda()).json();
    expect(ag.ok).toBe(true);
    const evPetro = ag.eventos.find((e) => e.emissor === "Petrobras" && e.tipo === "resultado" && e.data === d30);
    const evVale = ag.eventos.find((e) => e.emissor === "Vale" && e.tipo === "resultado" && e.data === d30);
    expect(evPetro).toBeTruthy();
    expect(evPetro.confirmado).toBe(true);
    expect(evPetro.status_validacao).toBe("CONFIRMADO_OFICIAL");
    expect(evPetro.data_resultado).toBe(d30);
    expect(evPetro.fonte_primaria).toBe("ri.petrobras.com.br");
    expect(evVale).toBeTruthy();
    expect(evVale.confirmado).toBe(false);
    expect(evVale.status_validacao).toBe("PENDENTE");
    // contrato da newsletter preservado: campos legados intactos
    expect(evVale.titulo).toContain("3T26");
    expect(evVale.subtitulo).toBeTruthy();
    expect(evVale.fonte).toBe("infomoney.com.br");
  });

  it("sem data: trimestre persiste como NAO_INFORMADO e pode ser preenchido depois (regra 6)", async () => {
    const r = await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Itaúsa",
      trimestres: [{ periodo: "4T26" }],
    });
    expect(r.status).toBe(200);
    const res = await r.json();
    expect(res.ok).toBe(true);
    // antes do CALVAL-V2 o filtro descartava trimestre sem data (count 0)
    expect(res.trimestres_count).toBe(1);

    // preencher depois funciona: NAO_INFORMADO nao trava a rotina
    const d30 = diasA(30);
    const r2 = await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Itaúsa",
      trimestres: [{ periodo: "4T26", data_prevista: d30, status: "agendado", url_fonte_primaria: "https://ri.itausa.com.br/x" }],
    });
    expect(r2.status).toBe(200);
    const body = await (await getCalendario()).json();
    const prox = body.emissores["Itaúsa"].proxima_divulgacao;
    expect(prox.periodo).toBe("4T26");
    expect(prox.data_prevista).toBe(d30);
  });

  it("trimestre fiscal: periodo verbatim, sem conversao (regra 7)", async () => {
    const d30 = diasA(30);
    const r = await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Petrobras",
      trimestres: [{ periodo: "3T25F", data_prevista: d30, status: "agendado", trimestre_fiscal: true, url_fonte_primaria: "https://ri.petrobras.com.br/x" }],
    });
    expect(r.status).toBe(200);
    const body = await (await getCalendario()).json();
    const prox = body.emissores["Petrobras"].proxima_divulgacao;
    expect(prox.periodo).toBe("3T25F");
    expect(prox.trimestre_fiscal).toBe(true);
  });

  it("empresa renomeada resolve para o canonico e nome desconhecido e rejeitado (regra 8)", async () => {
    const d30 = diasA(30);
    const r = await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "AXIA Energia",
      trimestres: [{ periodo: "3T26", data_prevista: d30, status: "agendado", url_fonte_primaria: "https://ri.eletrobras.com/x" }],
    });
    expect(r.status).toBe(200);
    const res = await r.json();
    expect(res.empresa).toBe("Eletrobras");
    const body = await (await getCalendario()).json();
    expect(body.emissores["Eletrobras"]).toBeTruthy();

    const rBad = await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Empresa Inexistente XYZ",
      trimestres: [{ periodo: "3T26", data_prevista: d30 }],
    });
    expect(rBad.status).toBe(400);
    expect((await rBad.json()).ok).toBe(false);
  });

  it("stale: data passada nao confirmada gera motivo confirmar_divulgacao (regra 9)", async () => {
    const dPast = diasA(-5);
    await postRoutine({
      action: "atualizar_calendario_emissor",
      empresa: "Petrobras",
      trimestres: [{ periodo: "3T26", data_prevista: dPast, status: "agendado", fonte: "https://www.infomoney.com.br/x" }],
    });
    const r = await postRoutine({ action: "listar_calendario_stale", limite: 30 });
    expect(r.status).toBe(200);
    const body = await r.json();
    const petro = body.emissores.find((e) => e.empresa === "Petrobras");
    expect(petro).toBeTruthy();
    expect(petro.motivo).toBe("confirmar_divulgacao");
    expect(petro.trimestres_alvo.length).toBeGreaterThan(0);
  });
});
