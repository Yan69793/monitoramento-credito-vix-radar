import { defineConfig } from "vitest/config";
import { cloudflareTest } from "@cloudflare/vitest-pool-workers";

// Config e API atuais confirmadas em node_modules/@cloudflare/vitest-pool-workers
// (codemods/vitest-v3-to-v4.mjs), nao em docs externas: a partir da v0.20.x o pacote
// nao exporta mais "@cloudflare/vitest-pool-workers/config" nem defineWorkersProject.
// O pool agora entra como plugin do Vitest 4.
export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.test.jsonc" },
      miniflare: {
        // RELOGIOTESTE1 (2026-08-31): canal do deslocamento de relogio para o
        // setup em test/_setup-relogio-adiantado.mjs. Vem do ambiente do runner
        // porque o setup roda dentro do workerd e nao enxerga process.env.
        // Ausente ou "0" e o caminho normal, sem deslocamento nenhum.
        bindings: {
          VIX_TEST_CLOCK_SHIFT_DAYS: process.env.VIX_TEST_CLOCK_SHIFT_DAYS ?? "0"
        },
        // EMAILSILENT1 (2026-08-24): a Resend e a UNICA saida de rede interceptada
        // aqui. Duas razoes. Primeira, o teste de envio precisa escolher entre
        // caminho feliz e caminho de falha de forma deterministica, e este pacote
        // (v0.20.x) nao exporta `fetchMock` de "cloudflare:test" — so o tipo
        // MockAgent sobrou no .d.ts, sem implementacao em dist/. Segunda, sem isto
        // a suite bate em api.resend.com de verdade a cada rodada de CI com a chave
        // dummy do wrangler.test.jsonc, o que e lento, flaky e barulho na conta
        // de terceiro.
        //
        // O canal de escolha e o proprio destinatario, nao estado compartilhado:
        // o outboundService roda no processo do Vitest e o assert roda dentro do
        // worker, entao qualquer variavel entre os dois seria uma ponte fragil.
        // Endereco em @falha-envio.example volta 422, o resto volta 200 com id.
        // Todo host que nao for a Resend continua saindo para a rede real.
        //
        // A decisao le `to` do payload, NAO o corpo cru. O e-mail de notificacao
        // ao admin carrega o endereco do candidato dentro do HTML, entao casar
        // por substring no corpo derrubava tambem esse envio, que nem e o alvo
        // do teste. Ruido que faria o proximo leitor caçar um bug que nao existe.
        async outboundService(request: Request): Promise<Response> {
          const url = new URL(request.url);
          if (url.hostname !== "api.resend.com") return fetch(request);
          const corpo = await request.clone().text().catch(() => "");
          let destinatarios: string[] = [];
          try {
            const payload = JSON.parse(corpo);
            destinatarios = Array.isArray(payload.to) ? payload.to : [payload.to];
          } catch {
            destinatarios = [];
          }
          if (destinatarios.some((d) => String(d || "").includes("@falha-envio.example"))) {
            // Forma real de recusa por dominio do destinatario, que e o caso que
            // motivou a auditoria. 422 nao e retentavel em fetchResendComRetry
            // (so 429 e 5xx sao), entao falha na primeira tentativa.
            return new Response(
              JSON.stringify({ statusCode: 422, name: "validation_error", message: "Recipient domain rejected the message (mock)" }),
              { status: 422, headers: { "Content-Type": "application/json" } }
            );
          }
          return new Response(
            JSON.stringify({ id: "mock-resend-id-0001" }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          );
        }
      }
    }),
  ],
  test: {
    setupFiles: ["./test/_setup-relogio-adiantado.mjs"]
  }
});
