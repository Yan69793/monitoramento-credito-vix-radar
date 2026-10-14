// _sessao-token.mjs - helper de sessao para testes (SESSOES-TEST1, 2026-10-09).
//
// A migracao para sessao unica (SESSION-ONE) fez verificarJWT exigir payload.sid E que esse
// sid esteja registrado no UsuarioDO (worker.js: `if (!payload.sid || !payload.email ||
// !env.USUARIO_DO) return null;`). As suites que montavam o JWT a mao - so com
// {sub,email,iat,exp} - passaram a receber 401 nas leituras autenticadas. O token estava
// correto para o codigo antigo; o codigo novo exige a sessao registrada. Este helper faz o
// registro pela MESMA rota do Worker (_rotearParaUsuarioDO), sem contornar a checagem.
//
// Uso:
//   import { registrarSessao, payloadComSessao } from "./_sessao-token.mjs";
//   const sid = await registrarSessao(env, "test@example.com");
//   const payload = await payloadComSessao(env, { email: "test@example.com", exp: ... });

import { env } from "cloudflare:test";

export async function registrarSessao(envTest, email) {
  const sid = crypto.randomUUID();
  const id = envTest.USUARIO_DO.idFromName((email || "").toLowerCase());
  const stub = envTest.USUARIO_DO.get(id);
  const r = await stub.fetch("https://do.internal/", {
    method: "POST",
    body: JSON.stringify({ op: "setSessaoAtiva", args: [sid] })
  });
  const j = await r.json().catch(() => ({ ok: false, erro: "resposta invalida do UsuarioDO" }));
  if (!j.ok) throw new Error("setSessaoAtiva falhou: " + (j.erro || JSON.stringify(j)));
  return sid;
}

export async function payloadComSessao(envTest, payload) {
  const e = envTest || env;
  const sid = await registrarSessao(e, payload && payload.email);
  return Object.assign({}, payload, { sid });
}
