// REPROVADO-FAILCLOSED1 (2026-09-06): helpers de teste para o indice de quarentena.
//
// Em producao o rollout manda: bootstrap (indice vazio valido) ANTES do deploy do
// codigo consumidor, porque leitura fail-closed trata ausencia como ERRO. Nos
// testes o storage e isolado por test(), entao todo arquivo que exercita
// enfileirar/listar/confirmar/consumidores publicos precisa semear o indice.
export const INDICE_QUARENTENA_VAZIO = {
  schema: 1,
  ids: {},
  atualizado_em: "2026-09-06T00:00:00.000Z",
};

export async function bootstrapIndiceQuarentena(env) {
  await env.RADAR_KV.put("radar:verif:quarentena_idx", JSON.stringify(INDICE_QUARENTENA_VAZIO));
}

export async function adicionarAoIndice(env, id, meta) {
  const raw = await env.RADAR_KV.get("radar:verif:quarentena_idx", "json");
  const idx =
    raw && raw.schema === 1 && raw.ids && typeof raw.ids === "object" && !Array.isArray(raw.ids)
      ? raw
      : JSON.parse(JSON.stringify(INDICE_QUARENTENA_VAZIO));
  idx.ids[id] = meta || { empresa: null, semana: null, desde: "2026-09-06T00:00:00.000Z" };
  idx.atualizado_em = "2026-09-06T00:00:00.000Z";
  await env.RADAR_KV.put("radar:verif:quarentena_idx", JSON.stringify(idx));
}

export async function lerIndice(env) {
  return env.RADAR_KV.get("radar:verif:quarentena_idx", "json");
}

export async function resetIndiceQuarentena(env) {
  // O storage do KV e compartilhado entre os test() do MESMO arquivo (medido em
  // probe 2026-09-06), e o ConfigDO singleton mantem copia autoritativa propria
  // em state.storage. Limpar os dois evita que um teste herde ids do anterior.
  try { await env.RADAR_KV.delete("radar:verif:quarentena_idx"); } catch (_) { }
  try {
    const stub = env.CONFIG_DO.get(env.CONFIG_DO.idFromName("_global"));
    await stub.fetch("https://do.internal/", { method: "POST", body: JSON.stringify({ op: "quarentenaResetStorage", args: [] }) });
  } catch (_) { }
}

export async function removerDoIndice(env, id) {
  const raw = await env.RADAR_KV.get("radar:verif:quarentena_idx", "json");
  const idx =
    raw && raw.schema === 1 && raw.ids && typeof raw.ids === "object" && !Array.isArray(raw.ids)
      ? raw
      : JSON.parse(JSON.stringify(INDICE_QUARENTENA_VAZIO));
  delete idx.ids[id];
  idx.atualizado_em = "2026-09-06T00:00:00.000Z";
  await env.RADAR_KV.put("radar:verif:quarentena_idx", JSON.stringify(idx));
}
