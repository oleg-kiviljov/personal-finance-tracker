import { defineConfig } from 'vite'
import vue from "@vitejs/plugin-vue";
import liveVuePlugin from "live_vue/vitePlugin";
import tailwindcss from "@tailwindcss/vite";
import ui from "@nuxt/ui/vite";

export default defineConfig({
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    cors: { origin: "http://localhost:4000" },
  },
  optimizeDeps: {
    // https://vitejs.dev/guide/dep-pre-bundling#monorepos-and-linked-dependencies
    include: ["live_vue", "phoenix", "phoenix_html", "phoenix_live_view"],
  },
  ssr: {
      noExternal: process.env.NODE_ENV === "production" ? true : undefined,
      resolve: { conditions: ["import", "module", "browser", "default"] },
    },
    build: {
    manifest: false,
    ssrManifest: false,
    rollupOptions: {
      input: ["js/app.js", "css/app.css"],
      // Rolldown can't interpret some `/* #__PURE__ */` annotations in prebuilt
      // deps (e.g. @vueuse/core via @nuxt/ui). The annotations are harmless, so
      // silence INVALID_ANNOTATION for third-party code while keeping it for ours.
      onLog(level, log, handler) {
        if (log.code === "INVALID_ANNOTATION" && /node_modules/.test(log.id ?? log.message)) {
          return;
        }
        handler(level, log);
      },
    },
    outDir: "../priv/static",
    emptyOutDir: true,
  },
  // LV Colocated JS and Hooks
  // https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.ColocatedJS.html#module-internals
  resolve: {
    alias: {
      "@": ".",
      "phoenix-colocated": `${process.env.MIX_BUILD_PATH}/phoenix-colocated`,
    },
  },
  plugins: [
    tailwindcss(),
    vue(),
    // router/colorMode off: LiveView owns navigation; colorMode uses browser APIs (SSR-unsafe)
    ui({ router: false, colorMode: false }),
    liveVuePlugin()
  ]
});
