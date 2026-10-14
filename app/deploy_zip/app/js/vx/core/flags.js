/**
 * Feature flag por tela da v2 (dossie §8.4, com vencimento por tela).
 * Resolucao: ?ui=v2 liga todas | ?ui=v1 desliga todas | ?ui_eventos=v2 / ?ui_empresas=v2
 * por tela | valor salvo neste navegador | PADRAO (v1).
 * Rollback global sem tocar no Worker: V2_DISPONIVEL=false e deploy do Pages.
 * Rollback por tela: tirar a tela de TELAS_PADRAO_V2 (hoje vazia: v1 e o padrao).
 */
export const V2_DISPONIVEL = true;
export const TELAS = ['eventos', 'empresas'];
const TELAS_PADRAO_V2 = []; // promover uma tela = incluir aqui, depois do ciclo estavel
const CHAVE = 'vx_ui_telas';

function lerSalvo() {
  try { const v = JSON.parse(localStorage.getItem(CHAVE) || 'null'); return v && typeof v === 'object' ? v : {}; } catch (_) { return {}; }
}
function salvar(o) { try { localStorage.setItem(CHAVE, JSON.stringify(o)); } catch (_) { /* modo privado: so a URL vale */ } }

export function aplicarFlagsDaUrl(search = location.search) {
  const q = new URLSearchParams(search);
  const salvo = lerSalvo();
  let mudou = false;
  const ui = q.get('ui');
  if (ui === 'v2' || ui === 'v1') { TELAS.forEach((t) => { salvo[t] = ui; }); mudou = true; }
  TELAS.forEach((t) => {
    const v = q.get('ui_' + t);
    if (v === 'v2' || v === 'v1') { salvo[t] = v; mudou = true; }
  });
  if (mudou) salvar(salvo);
}

export function versaoDaTela(tela) {
  if (!V2_DISPONIVEL) return 'v1';
  const salvo = lerSalvo();
  if (salvo[tela] === 'v2' || salvo[tela] === 'v1') return salvo[tela];
  return TELAS_PADRAO_V2.includes(tela) ? 'v2' : 'v1';
}

export function telasEmV2() { return TELAS.filter((t) => versaoDaTela(t) === 'v2'); }
