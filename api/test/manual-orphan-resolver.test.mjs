import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import {
  chaveOrfaoVerificacao,
  chaveConclusaoVerificacao,
  _definirFalhaInjetadaTeste,
  _limparFalhasInjetadasTeste,
  _reconciliarOrfaosConcluidos,
} from "../src/worker.js";

const ADMIN = "test-admin-password-nao-usar-em-producao";
const SEMANA = "2026-W40";
const EMPRESA = "Braskem";
const SETOR = "Petroleo";
const DATA = "2026-09-30";
const URL = "https://example.com/noticia";
const EVIDENCIA = "https://example.com/evidencia-independente";
const ID = DATA + "|" + EMPRESA.toLowerCase() + "|example.com/noticia";
const MOTIVO_CONFIRMAR = "Revisao humana confirmou o evento com evidencia externa documentada.";
const MOTIVO_DESCARTAR = "Revisao humana encontrou erro material e determinou a retirada do evento.";

const evento = () => ({
  empresa: EMPRESA,
  classificacao: "RELEVANTE",
  titulo: "Evento material para teste manual de orfao",
  evento: "Evento com fonte citavel aguardando verificacao.",
  fonte_primaria: URL,
  fonte_tipo: "IMPRENSA",
  data_evento: DATA,
  _pendente_verificacao: true,
});

async function limpar(prefix) {
  const l = await env.RADAR_KV.list({ prefix });
  for (const k of l.keys) await env.RADAR_KV.delete(k.name);
}

async function semear() {
  await env.RADAR_KV.put("radar:estado:" + SEMANA, JSON.stringify({
    week: SEMANA,
    results: { [EMPRESA]: { empresa: EMPRESA, setor: SETOR, sem_eventos: false, eventos: [evento()] } },
    updated_at: new Date().toISOString(),
  }));
  await env.RADAR_KV.put(chaveOrfaoVerificacao(ID), JSON.stringify({
    id: ID, empresa: EMPRESA, semana: SEMANA, setor: SETOR,
    criado_em: "2026-10-02T00:00:00.000Z",
    expirado_em: "2026-10-04T00:00:00.000Z",
    data_fila: "2026-10-02", motivo: "fila_expirada_48h", origem: "sweep",
  }));
}

async function estado() {
  return env.RADAR_KV.get("radar:estado:" + SEMANA, "json");
}

function post(body) {
  return SELF.fetch("https://example.com/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function payload(decisao, motivo) {
  return { action: "admin_verif_orfao_resolver", admin_senha: ADMIN, id: ID, decisao, motivo, fontes: [EVIDENCIA] };
}

beforeEach(async () => {
  await limpar("radar:verif:");
  await limpar("radar:estado:");
  _limparFalhasInjetadasTeste();
  await semear();
});

describe("MANUAL-ORFAO1 robusto - decisao terminal auditavel", () => {
  it("bloqueia sem senha admin", async () => {
    const r = await post({ action: "admin_verif_orfao_resolver", id: ID, decisao: "confirmar", motivo: MOTIVO_CONFIRMAR, fontes: [EVIDENCIA] });
    expect(r.status).toBe(403);
    expect(await env.RADAR_KV.get(chaveOrfaoVerificacao(ID), "json")).toBeTruthy();
  });

  it("exige motivo suficientemente descritivo", async () => {
    const r = await post(payload("confirmar", "curto"));
    expect(r.status).toBe(400);
    const j = await r.json();
    expect(j.codigo).toBe("ORFAO_MOTIVO_INSUFICIENTE");
  });

  it("exige ao menos uma fonte URL", async () => {
    const p = payload("confirmar", MOTIVO_CONFIRMAR);
    p.fontes = [];
    const r = await post(p);
    expect(r.status).toBe(400);
    const j = await r.json();
    expect(j.codigo).toBe("ORFAO_EVIDENCIA_AUSENTE");
  });

  it("confirmar persiste decisao, certifica evento, audita e remove orfao", async () => {
    const r = await post(payload("confirmar", MOTIVO_CONFIRMAR));
    const j = await r.json();
    expect(r.status).toBe(200);
    expect(j.ok).toBe(true);
    const st = await estado();
    const ev = st.results[EMPRESA].eventos[0];
    expect(ev._pendente_verificacao).toBe(false);
    expect(ev._verif_manual.decisao).toBe("confirmar");
    expect(st.results[EMPRESA]._verif_manual_resolucoes[ID].decisao).toBe("confirmar");
    expect(await env.RADAR_KV.get(chaveOrfaoVerificacao(ID), "json")).toBeNull();
    const audit = await env.RADAR_KV.get("radar:verif:manual:" + ID, "json");
    expect(audit.fase).toBe("finalizado");
    expect(audit.fontes).toContain(EVIDENCIA);
  });

  it("descartar remove evento, audita e remove orfao", async () => {
    const r = await post(payload("descartar", MOTIVO_DESCARTAR));
    const j = await r.json();
    expect(r.status).toBe(200);
    expect(j.ok).toBe(true);
    const st = await estado();
    expect(st.results[EMPRESA].eventos).toHaveLength(0);
    expect(st.results[EMPRESA].sem_eventos).toBe(true);
    expect(await env.RADAR_KV.get(chaveOrfaoVerificacao(ID), "json")).toBeNull();
    const audit = await env.RADAR_KV.get("radar:verif:manual:" + ID, "json");
    expect(audit.fase).toBe("finalizado");
    expect(audit.decisao).toBe("descartar");
  });

  it("retry da mesma decisao e idempotente", async () => {
    const r1 = await post(payload("confirmar", MOTIVO_CONFIRMAR));
    expect(r1.status).toBe(200);
    const r2 = await post(payload("confirmar", MOTIVO_CONFIRMAR));
    const j2 = await r2.json();
    expect(r2.status).toBe(200);
    expect(j2.ok).toBe(true);
  });

  it("decisao conflitante apos finalizacao e recusada", async () => {
    const r1 = await post(payload("confirmar", MOTIVO_CONFIRMAR));
    expect(r1.status).toBe(200);
    const r2 = await post(payload("descartar", MOTIVO_DESCARTAR));
    const j2 = await r2.json();
    expect(r2.status).toBe(409);
    expect(j2.codigo).toBe("ORFAO_DECISAO_CONFLITANTE");
  });

  it("falha no delete terminal preserva orfao e reconciliacao converge", async () => {
    _definirFalhaInjetadaTeste("orfao_delete_terminal");
    const r = await post(payload("confirmar", MOTIVO_CONFIRMAR));
    expect(r.status).toBe(409);
    expect(await env.RADAR_KV.get(chaveOrfaoVerificacao(ID), "json")).toBeTruthy();
    expect(await env.RADAR_KV.get(chaveConclusaoVerificacao(ID), "json")).toBeTruthy();
    _limparFalhasInjetadasTeste();
    const rr = await _reconciliarOrfaosConcluidos(env, 100);
    expect(rr.resolvidos).toBe(1);
    expect(await env.RADAR_KV.get(chaveOrfaoVerificacao(ID), "json")).toBeNull();
  });
});
