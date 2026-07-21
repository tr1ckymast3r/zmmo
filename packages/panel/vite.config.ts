import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { TanStackRouterVite } from "@tanstack/router-plugin/vite";
import path from "path";

export default defineConfig({
  plugins: [
    TanStackRouterVite({ target: "react", autoCodeSplitting: true }),
    react(),
  ],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    port: 3013,
    host: "0.0.0.0",
    proxy: {
      "/agent-binaries": {
        target: "http://localhost:3013",
        rewrite: () => "/agent-binaries/",
      },
    },
  },
});
