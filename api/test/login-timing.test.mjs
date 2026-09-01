import { SELF, env } from "cloudflare:test";
import { describe, expect, it, beforeAll } from "vitest";

// LOGINTIMING1 (2026-09-01, achado P4-1 da auditoria geral). Ate a v4.9.227 o handleLogin
// tinha tres tempos de resposta diferentes para a MESMA mensagem "Credenciais invalidas":
//
//   usuario inexistente  -> atraso deliberado de 80-200ms, sem hash
//   senha errada         -> PBKDF2 de 100k iteracoes, sem atraso
//   pendente/rejeitado   -> nem hash nem atraso, resposta imediata
//
// O texto era generico (anti-enumeracao), mas o relogio nao era: quem media a latencia
// distinguia conta existente de conta inexistente. Somar o atraso ao ramo lento so
// inverteria o oraculo, entao a correcao iguala o TRABALHO antes do atraso: todo caminho
// de falha roda um PBKDF2 (contra o hash real, ou contra HASH_DUMMY_LOGIN quando nao ha
// usuario) e sai pelo mesmo ponto, com o mesmo jitter de 80-200ms.
//
// Prova reversa medida contra o codigo pre-correcao: o caso "pendente" respondia em
// poucos milissegundos e o caso "senha errada" nao pagava atraso nenhum, entao o piso de
// 80ms deste arquivo reprova os dois. O caso "usuario inexistente" ja passava, e continua
// passando, o que confirma que o teste nao esta medindo outra coisa.
//
// Cada requisicao usa um IP proprio: o gate de rate limit anonimo e 3/60s por identidade
// (ver rate-limit.test.mjs) e sem isso a 4a tentativa voltaria 429 em vez de 401.

const SENHA_CERTA = "senha-correta-para-teste-0001";
const PISO_JITTER_MS = 80;

// Copia literal de hashSenha (api/src/worker.js, secao de auth): b64(salt 16B) + ":" +
// b64(derivado 32B), PBKDF2-SHA256 com 100k iteracoes. Escrito a mao aqui de proposito,
// para o teste depender do FORMATO gravado no KV e nao de um export novo do worker.
async function hashSenhaLocal(senha) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(senha), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt, iterations: 1e5, hash: "SHA-256" }, key, 256);
  return `${btoa(String.fromCharCode(...salt))}:${btoa(String.fromCharCode(...new Uint8Array(bits)))}`;
}

async function seedUsuario(email, status) {
  await env.RADAR_KV.put(
    "user:" + email.toLowerCase().trim(),
    JSON.stringify({
      email,
      nome: "Teste " + status,
      empresa: "Empresa Teste",
      status,
      senha_hash: await hashSenhaLocal(SENHA_CERTA),
      tenant: "default",
      ui_track: "v1",
      white_label: false,
      created_at: "2026-09-01T00:00:00.000Z",
    })
  );
}

const APROVADO = "aprovado-teste@example.com";
const PENDENTE = "pendente-teste@example.com";
const REJEITADO = "rejeitado-teste@example.com";
const INEXISTENTE = "nao-existe-teste@example.com";

let ipSeq = 0;
async function login(email, senha) {
  ipSeq += 1;
  // TEST-NET-3 (RFC 5737), nao roteavel. Um IP por tentativa.
  const ip = "203.0.113." + (ipSeq % 250);
  const t0 = Date.now();
  const res = await SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify({ action: "login", email, senha }),
  });
  const corpo = await res.json();
  return { status: res.status, corpo, ms: Date.now() - t0 };
}

async function menorDe(email, senha, amostras) {
  let menor = Infinity;
  for (let i = 0; i < amostras; i++) {
    const r = await login(email, senha);
    expect(r.status).toBe(401);
    if (r.ms < menor) menor = r.ms;
  }
  return menor;
}

describe("LOGINTIMING1: login nao vaza existencia de conta pelo tempo", () => {
  beforeAll(async () => {
    await seedUsuario(APROVADO, "aprovado");
    await seedUsuario(PENDENTE, "pendente");
    await seedUsuario(REJEITADO, "rejeitado");
  });

  it("credencial correta continua entrando (controle positivo)", async () => {
    const r = await login(APROVADO, SENHA_CERTA);
    expect(r.status).toBe(200);
    expect(r.corpo.ok).toBe(true);
    expect(typeof r.corpo.token).toBe("string");
    expect(r.corpo.token.length).toBeGreaterThan(20);
    expect(r.corpo.usuario.email).toBe(APROVADO);
  });

  it("os quatro caminhos de falha devolvem 401 com a mesma resposta", async () => {
    const casos = [
      await login(INEXISTENTE, "qualquer-coisa"),
      await login(APROVADO, "senha-errada-999"),
      await login(PENDENTE, SENHA_CERTA),
      await login(REJEITADO, SENHA_CERTA),
    ];
    for (const c of casos) {
      expect(c.status).toBe(401);
      expect(c.corpo).toEqual({ ok: false, erro: "Credenciais inválidas." });
    }
  });

  it("todo caminho de falha paga o mesmo piso de atraso", async () => {
    const amostras = 3;
    const medidas = {
      inexistente: await menorDe(INEXISTENTE, "qualquer-coisa", amostras),
      senha_errada: await menorDe(APROVADO, "senha-errada-999", amostras),
      pendente: await menorDe(PENDENTE, SENHA_CERTA, amostras),
      rejeitado: await menorDe(REJEITADO, SENHA_CERTA, amostras),
    };
    console.log("[LOGINTIMING1] menor latencia por caminho (ms):", medidas);

    // Piso: no codigo antigo, pendente/rejeitado voltavam sem hash e sem atraso, e senha
    // errada pagava so o hash. Qualquer um deles abaixo de 80ms reabre o oraculo.
    for (const [caminho, ms] of Object.entries(medidas)) {
      expect(ms, caminho).toBeGreaterThanOrEqual(PISO_JITTER_MS);
    }

    // Uniformidade: com o hash pago nos quatro caminhos, o que sobra de diferenca e o
    // jitter (120ms de amplitude) mais ruido de agendamento. A janela abaixo e folgada de
    // proposito, para nao virar teste flaky; o que ela reprova e diferenca ESTRUTURAL de
    // custo entre os ramos, que e o defeito real.
    const valores = Object.values(medidas);
    expect(Math.max(...valores) - Math.min(...valores)).toBeLessThanOrEqual(200);
  });
});
