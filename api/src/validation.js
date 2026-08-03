// =============================================================================
// VALID1: middleware de validação de input (v4.9.186).
// Roda ANTES do route dispatch em __coreFetch. Bloqueia payloads > MAX_BODY_SIZE,
// força Content-Type application/json em POST, e valida campos obrigatórios.
// Falha rápido com 400 estruturado — evita que JSON quebrado chegue no handler.
// =============================================================================
var MAX_BODY_SIZE = 1024 * 1024; // 1MB — suficiente pra qualquer payload legítimo

function _validateInput(request, env) {
  // GET/HEAD/OPTIONS: sem body, sem validação
  var method = request.method.toUpperCase();
  if (method === "GET" || method === "HEAD" || method === "OPTIONS") return null;

  // POST/PUT/PATCH: exigem JSON
  var ct = (request.headers.get("Content-Type") || "").toLowerCase();
  if (ct && ct.indexOf("application/json") === -1 && method !== "DELETE") {
    return new Response(JSON.stringify({ ok: false, erro: "Content-Type deve ser application/json" }), {
      status: 415, headers: { "Content-Type": "application/json" }
    });
  }

  // Body size cap (antes de ler o body inteiro)
  var cl = request.headers.get("Content-Length");
  if (cl) {
    var size = parseInt(cl, 10);
    if (!isNaN(size) && size > MAX_BODY_SIZE) {
      _logWarn(env, "VALID1: payload excede " + MAX_BODY_SIZE + " bytes (" + size + ")", { method: method });
      return new Response(JSON.stringify({ ok: false, erro: "Payload excede 1MB" }), {
        status: 413, headers: { "Content-Type": "application/json" }
      });
    }
  }

  return null; // null = válido, segue o fluxo
}
__name(_validateInput, "_validateInput");