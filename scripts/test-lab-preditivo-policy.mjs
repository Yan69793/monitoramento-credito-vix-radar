/**
 * Teste unitario da politica unificada do lab preditivo.
 * Replica a logica de _exigeLabPreditivoAdmin sem carregar o monolithe.
 * Run: node scripts/test-lab-preditivo-policy.mjs
 */
import assert from "node:assert/strict";

function exigeLabPreditivoAdmin({ jwtOk, jwtStatus = 401, jwtErro = "Autenticacao necessaria.", adminPassword, senhaBody, senhaQuery, senhaHeader }) {
  if (jwtOk) return { ok: true, via: "jwt_admin" };
  const senha = senhaBody || senhaQuery || senhaHeader || "";
  if (adminPassword && senha && senha === adminPassword) {
    return { ok: true, via: "admin_password" };
  }
  return { ok: false, status: jwtStatus, erro: jwtErro, lab_interno: true };
}

let passed = 0;
function check(name, fn) {
  try {
    fn();
    console.log("OK ", name);
    passed++;
  } catch (e) {
    console.error("FAIL", name, e.message);
    process.exitCode = 1;
  }
}

check("jwt admin passa", () => {
  const r = exigeLabPreditivoAdmin({ jwtOk: true, adminPassword: "secret" });
  assert.equal(r.ok, true);
  assert.equal(r.via, "jwt_admin");
});

check("senha body passa", () => {
  const r = exigeLabPreditivoAdmin({ jwtOk: false, adminPassword: "secret", senhaBody: "secret" });
  assert.equal(r.ok, true);
  assert.equal(r.via, "admin_password");
});

check("senha header passa", () => {
  const r = exigeLabPreditivoAdmin({ jwtOk: false, adminPassword: "secret", senhaHeader: "secret" });
  assert.equal(r.ok, true);
  assert.equal(r.via, "admin_password");
});

check("senha query passa", () => {
  const r = exigeLabPreditivoAdmin({ jwtOk: false, adminPassword: "secret", senhaQuery: "secret" });
  assert.equal(r.ok, true);
  assert.equal(r.via, "admin_password");
});

check("senha errada falha 401", () => {
  const r = exigeLabPreditivoAdmin({ jwtOk: false, jwtStatus: 401, adminPassword: "secret", senhaBody: "x" });
  assert.equal(r.ok, false);
  assert.equal(r.status, 401);
  assert.equal(r.lab_interno, true);
});

check("sem credencial falha", () => {
  const r = exigeLabPreditivoAdmin({ jwtOk: false, adminPassword: "secret" });
  assert.equal(r.ok, false);
});

check("jwt admin tem prioridade sobre senha errada", () => {
  const r = exigeLabPreditivoAdmin({ jwtOk: true, adminPassword: "secret", senhaBody: "wrong" });
  assert.equal(r.ok, true);
  assert.equal(r.via, "jwt_admin");
});

check("user nao-admin (403) sem senha continua 403", () => {
  const r = exigeLabPreditivoAdmin({ jwtOk: false, jwtStatus: 403, jwtErro: "Acesso restrito.", adminPassword: "secret" });
  assert.equal(r.ok, false);
  assert.equal(r.status, 403);
});

check("user nao-admin com senha admin ainda passa (admin_password)", () => {
  // Politica deliberada: senha admin desbloqueia lab mesmo se JWT for user comum.
  const r = exigeLabPreditivoAdmin({ jwtOk: false, jwtStatus: 403, adminPassword: "secret", senhaHeader: "secret" });
  assert.equal(r.ok, true);
  assert.equal(r.via, "admin_password");
});

if (process.exitCode !== 1) {
  console.log(`ALL PASSED (${passed})`);
}
