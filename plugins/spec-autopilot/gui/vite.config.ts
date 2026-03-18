import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { resolve } from "path";
import { readFileSync } from "fs";

const pluginJson = JSON.parse(
  readFileSync(resolve(__dirname, "../.claude-plugin/plugin.json"), "utf-8")
);

export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: "/",
  define: {
    __PLUGIN_VERSION__: JSON.stringify(pluginJson.version),
  },
  build: {
    // 输出到插件根目录的 gui-dist/，一次编译两端同步
    outDir: resolve(__dirname, "../gui-dist"),
    emptyOutDir: true,
    sourcemap: false,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes("node_modules/react-dom") || id.includes("node_modules/react/")) {
            return "vendor-react";
          }
          if (id.includes("@tanstack/react-virtual") || id.includes("@tanstack/virtual-core")) {
            return "vendor-virtual";
          }
        },
      },
    },
  },
  server: {
    port: 5173,
    proxy: {
      "/api": "http://localhost:9527",
    },
  },
});
