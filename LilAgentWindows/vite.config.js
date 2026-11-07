import { resolve } from 'node:path';
import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    target: 'chrome130',
    rollupOptions: { input: { index: resolve(import.meta.dirname, 'index.html'), settings: resolve(import.meta.dirname, 'settings.html'), splash: resolve(import.meta.dirname, 'splash.html') } },
  },
  server: { port: 5183, strictPort: true },
});
