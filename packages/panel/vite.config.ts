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
    allowedHosts: [
      "localhost",
      "127.0.0.1",
      "100.87.34.74",
      "tmds-server-red.tail3840e.ts.net",
      ".tail3840e.ts.net",
    ],
    proxy: {
      // Proxy API calls to manager-agent
      "/api": {
        target: "http://127.0.0.1:55555",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ""),
      },
      // Serve agent binaries
      "/agent-binaries": {
        target: "http://localhost:3013",
        rewrite: () => "/agent-binaries/",
      },
    },
  },
});
