import { vi } from "vitest";

// RELOGIOTESTE1 (2026-08-31). Relogio congelado para os testes que comparam
// contra snapshot de fixture datado.
//
// O defeito medido: `worker-tests` aprovou o commit d88c293 as 02:36:55Z de
// 31/08 (run 33351230334) e as MESMAS tres suites, no MESMO commit, sem
// alteracao de codigo, falharam horas depois. Nao era regressao, era o relogio
// de parede andando por baixo do fixture.
//
// Todo caminho datado do Worker passa por `obterAgoraBRT()`
// (api/src/worker.js:11485), que le `Date.now() - 3h`. Dele saem duas coisas que
// os testes dependem:
//
//   1. A janela de 5 semanas de `carregarEstadoMultiSemana`. Os fixtures estao
//      gravados em `radar:estado:2026-W31..W35`; quando a semana corrente virou
//      W36, o Worker passou a pedir W36..W32 e a W31 inteira sumiu do merge
//      (497 -> 447 eventos no ranking de materialidade).
//   2. O decaimento de recencia do EWS, `exp(-0.046 * dias)` em `calcularEWS`,
//      onde `dias` conta do evento ate hoje. Perde cerca de 4,5% ao dia, entao
//      qualquer assertiva numerica do EWS derrete sozinha com o calendario.
//
// O congelamento usa `vi.setSystemTime`, que troca o `Date` global do isolate.
// Medido em 31/08 que isso alcanca as duas pontas: o modulo importado direto
// (`carregarEstadoMultiSemana`) e o Worker atras de `SELF.fetch`, que responde
// `weeks_loaded: ["2026-W35" ... "2026-W31"]` com o relogio preso.
//
// So `Date` entra no `toFake`. `setTimeout`/`setInterval` ficam reais de
// proposito: o backoff da Resend e o agendamento interno do workerd rodam neles
// e um relogio de timer congelado trava a suite.

// 2026-08-30 12:00 BRT (15:00Z). E a data em que os snapshots e as medicoes de
// EWS destas tres suites foram capturados, e cai dentro da 2026-W35, entao a
// janela de 5 semanas fecha exatamente sobre os fixtures W35..W31.
export const INSTANTE_FIXTURE = Date.UTC(2026, 7, 30, 15, 0, 0);

export function fixarRelogioDoFixture() {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(INSTANTE_FIXTURE);
}

export function soltarRelogio() {
  vi.useRealTimers();
}
