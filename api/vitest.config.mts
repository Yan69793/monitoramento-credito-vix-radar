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
    }),
  ],
});
