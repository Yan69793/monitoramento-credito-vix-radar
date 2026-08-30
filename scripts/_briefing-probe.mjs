import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIX = path.resolve(__dirname, "..", "api", "test", "fixtures");
const WEEKS = ["2026-W31","2026-W32","2026-W33","2026-W34","2026-W35"];

// replicas inline das funcoes do worker (worker.js 8837-8921)
const _TERMOS_FRACOS_DEDUP = /\b(fato relevante|comunicado ao mercado|informa sobre|informa acerca de|informa acerca|informa que|comunica sobre|comunica que|informa|comunica|novo|nova|novos|novas|sobre|acerca de|acerca)\b/gi;
const _PREPS_SOLTAS_DEDUP = /\bde\b/gi;
const _PLURAL_DEDUP = /\b(rating)s\b/gi;
function normalizarTituloParaDedup(t){ if(!t) return ''; return t.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(_TERMOS_FRACOS_DEDUP,' ').replace(_PREPS_SOLTAS_DEDUP,' ').replace(_PLURAL_DEDUP,'$1').replace(/^[^a-z0-9]+/,'').replace(/\s+/g,' ').trim().slice(0,70); }
function _fonteBaseParaDedup(url){ if(!url) return ''; try { var u=new URL(String(url)); return (u.hostname+u.pathname).toLowerCase().replace(/\/+$/,'').slice(0,120); } catch(e){ return String(url).split('?')[0].toLowerCase().replace(/\/+$/,'').slice(0,120); } }
function isEventoDuplicadoSemantico(ev, existentes){
  const tituloLowerA=(ev.titulo||'').trim().toLowerCase();
  const empA=(ev.empresa||'').toLowerCase();
  const dataA=ev.data_evento||'';
  if (tituloLowerA && dataA){
    for (const ex of existentes){
      if ((ex.empresa||'').toLowerCase()!==empA) continue;
      if ((ex.titulo||'').trim().toLowerCase()===tituloLowerA && (ex.data_evento||'')===dataA) return true;
      if ((ex.data_evento||'')===dataA){
        const fA=_fonteBaseParaDedup(ev.fonte_primaria); const fB=_fonteBaseParaDedup(ex.fonte_primaria);
        if (fA && fB && fA===fB) return true;
      }
    }
  }
  const normA=normalizarTituloParaDedup(ev.titulo);
  if (!normA) return false;
  for (const ex of existentes){
    const empB=(ex.empresa||'').toLowerCase();
    if (empA!==empB) continue;
    if (ev.titulo===ex.titulo && ev.data_evento===ex.data_evento) return true;
    const normB=normalizarTituloParaDedup(ex.titulo);
    if (normA!==normB) continue;
    const dA=new Date(ev.data_evento||''); const dB=new Date(ex.data_evento||'');
    if (isNaN(dA)||isNaN(dB)) return true;
    const diffDias=Math.abs(dA-dB)/864e5;
    if (diffDias<=45) return true;
    const fA=(ev.fonte_primaria||'').split('?')[0].replace(/\/+$/,''); const fB=(ex.fonte_primaria||'').split('?')[0].replace(/\/+$/,'');
    if (fA && fB && fA===fB) return true;
    continue;
  }
  return false;
}

const alvos = [];
for (const w of WEEKS) {
  const j = JSON.parse(fs.readFileSync(path.join(FIX, `materialidade-estado-${w}.json`), "utf8"));
  for (const [emp, res] of Object.entries(j.results)) {
    if (!/braskem/i.test(emp) || !Array.isArray(res.eventos)) continue;
    for (const ev of res.eventos) if (ev.data_evento === "2026-08-17") alvos.push({ semana: w, ev });
  }
}
console.log("Braskem 08-17 nas fixtures:", alvos.length, "eventos");
alvos.forEach((a, i) => {
  const ev = a.ev;
  console.log(`[${i}] semana=${a.semana} empresa=${JSON.stringify(ev.empresa)} data=${JSON.stringify(ev.data_evento)}`);
  console.log(`    titulo: ${JSON.stringify(ev.titulo)}  (len ${(ev.titulo||'').length})`);
  console.log(`    fonte: ${(ev.fonte_primaria||'').slice(0,70)}`);
});
for (let i = 0; i < alvos.length; i++) for (let j = i+1; j < alvos.length; j++) {
  const a=alvos[i].ev, b=alvos[j].ev;
  console.log(`par [${i}]->[${j}]: isDup(a,b)=${isEventoDuplicadoSemantico(a,[b])} ; isDup(b,a)=${isEventoDuplicadoSemantico(b,[a])}`);
}
