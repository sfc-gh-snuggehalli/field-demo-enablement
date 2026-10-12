import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dev: Vite serves the UI on 5173 and proxies /api to the Express adapter on 8080.
// Both the chat (/) and the Store Ops simulator (/apps/storeops/*) are served by index.html.
export default defineConfig({
  plugins: [react()],
  envPrefix: ["VITE_"],
  server: {
    port: 5173,
    proxy: { "/api": { target: "http://localhost:8080", changeOrigin: false } },
  },
  build: {
    outDir: "dist",
    chunkSizeWarningLimit: 1500,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (/node_modules\/(vega|vega-lite|vega-embed|vega-[a-z-]+|d3-[a-z-]+)\//.test(id)) return "vega";
        },
      },
    },
  },
});
