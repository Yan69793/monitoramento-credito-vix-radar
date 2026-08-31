import { env } from "cloudflare:test";

// RELOGIOTESTE1 (2026-08-31) - guarda contra teste que depende do relogio de parede.
//
// O incidente: `worker-tests` aprovou d88c293 as 02:36:55Z de 31/08 e as mesmas
// tres suites, no MESMO commit, sem alteracao de codigo, falharam horas depois.
// Snapshot datado comparado contra `Date.now()` real so passa numa janela curta
// depois de capturado. Corrigir os tres arquivos nao impede o quarto de nascer
// com o mesmo defeito, entao a guarda mede o comportamento em vez de vigiar
// forma: a suite inteira roda de novo com o relogio adiantado e tem que dar o
// mesmo resultado.
//
// Ligado so quando VIX_TEST_CLOCK_SHIFT_DAYS existe (job proprio no
// worker-tests.yml). Sem a variavel, este arquivo nao toca em nada e a rodada
// normal fica identica ao que era.
//
// O deslocamento e sempre MULTIPLO DE 7 de proposito: dias uteis, cadencia
// semanal da CVM e semana ISO sao sensiveis a dia da semana, e um deslocamento
// quebrado acusaria diferenca de calendario em vez de fragilidade de relogio.
//
// Este shift mexe no relogio REAL do isolate. Teste que congela o proprio
// relogio (test/_relogio-fixo.mjs) passa por cima dele com vi.setSystemTime,
// que e absoluto, e por isso fica imune. Teste que monta fixture em data
// relativa ("hoje menos 3 dias") acompanha o shift e tambem fica imune. Quem
// quebra aqui e so quem compara valor datado fixo contra o relogio real.

const DIAS = Number(env.VIX_TEST_CLOCK_SHIFT_DAYS || 0);

if (Number.isFinite(DIAS) && DIAS !== 0) {
  if (DIAS % 7 !== 0) {
    throw new Error(`VIX_TEST_CLOCK_SHIFT_DAYS deve ser multiplo de 7, veio ${DIAS}`);
  }
  const RelogioReal = Date;
  const deslocamento = DIAS * 864e5;
  class DataAdiantada extends RelogioReal {
    constructor(...args) {
      if (args.length === 0) super(RelogioReal.now() + deslocamento);
      else super(...args);
    }
    static now() {
      return RelogioReal.now() + deslocamento;
    }
  }
  globalThis.Date = DataAdiantada;
}
