// =============================================================================
// LOG1: logger estruturado (v4.9.186) — substitui console.log/warn/error soltos.
// Output JSON com {ts, level, msg, ...extra}. Cloudflare Logpush → R2/Grafana.
// Compatível com console.log existente: toda chamada antiga continua funcionando,
// mas _log() oferece estrutura parseavel via wrangler tail --format json | jq.
// =============================================================================
var _LOG_LEVELS = { DEBUG: 0, INFO: 1, WARN: 2, ERROR: 3 };
var _LOG_LEVEL = "INFO"; // INFO em produção, DEBUG em desenvolvimento

function _log(env, level, msg, extra) {
  if (_LOG_LEVELS[level] < _LOG_LEVELS[_LOG_LEVEL]) return;
  var entry = { ts: (new Date()).toISOString(), level: level, msg: msg };
  if (extra) { for (var k in extra) { if (extra.hasOwnProperty(k)) entry[k] = extra[k]; } }
  // Sempre usa console.log para que Logpush capture. O campo level diferencia severidade.
  try { console.log(JSON.stringify(entry)); } catch (_) { /* nunca quebra o handler */ }
}
__name(_log, "_log");

function _logInfo(env, msg, extra) { _log(env, "INFO", msg, extra); }
function _logWarn(env, msg, extra) { _log(env, "WARN", msg, extra); }
function _logError(env, msg, extra) { _log(env, "ERROR", msg, extra); }
__name(_logInfo, "_logInfo");
__name(_logWarn, "_logWarn");
__name(_logError, "_logError");