import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "path";

export default defineConfig({
  plugins: [react()],
  base: "/",
  build: {
    // 输出到插件根目录的 gui-dist/，一次编译两端同步
    outDir: resolve(__dirname, "../gui-dist"),
    emptyOutDir: true,
    sourcemap: false,
  },
  server: {
    port: 5173,
    proxy: {
      "/api": "http://localhost:9527",
    },
  },
});
