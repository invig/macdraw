import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { cpSync, existsSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";

// Excalidraw loads its drawing fonts at runtime from EXCALIDRAW_ASSET_PATH.
// Copy them into the build so the app works fully offline (no CDN).
const copyExcalidrawFonts = () => ({
  name: "copy-excalidraw-fonts",
  writeBundle(options: { dir?: string }) {
    const src = resolve(import.meta.dirname, "node_modules/@excalidraw/excalidraw/dist/prod/fonts");
    const out = resolve(options.dir ?? "dist", "fonts");
    if (!existsSync(out)) mkdirSync(out, { recursive: true });
    cpSync(src, out, { recursive: true });
  },
});

export default defineConfig({
  base: "/",
  plugins: [react(), copyExcalidrawFonts()],
  define: { "process.env.IS_PREACT": JSON.stringify("false") },
  build: {
    outDir: "dist",
    emptyOutDir: true,
    chunkSizeWarningLimit: 10000,
    sourcemap: false,
    rollupOptions: {
      // index.html = the editor; render.html = headless renderer for Quick Look.
      input: {
        main: resolve(import.meta.dirname, "index.html"),
        render: resolve(import.meta.dirname, "render.html"),
      },
    },
  },
});
