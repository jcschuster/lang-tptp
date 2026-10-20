import {defineConfig} from "vitest/config"

export default defineConfig({
  test: {
    environment: "jsdom",
    setupFiles: ["./test/setup.ts"],
    // monaco-editor ships ESM that imports CSS; inlining lets Vite drop those imports.
    server: {deps: {inline: [/monaco-editor/]}},
  },
})
