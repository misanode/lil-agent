// Bundles the live mascot preview (the app's real model/animation code + three.js)
// into website/vendor/mascot-preview.js.
// Run from the repo root:  node website/preview-src/build.mjs
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { createRequire } from 'node:module';

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '../../LilAgentWindows');
const require = createRequire(path.join(app, 'package.json'));
const { build } = await import(require.resolve('vite'));

await build({
  configFile: false,
  logLevel: 'warn',
  resolve: {
    alias: [
      { find: /^three\/addons\//, replacement: path.join(app, 'node_modules/three/examples/jsm') + '/' },
      { find: /^three$/, replacement: path.join(app, 'node_modules/three/build/three.module.js') },
    ],
  },
  build: {
    outDir: path.resolve(here, '../vendor'),
    emptyOutDir: false,
    minify: true,
    lib: { entry: path.join(here, 'mascot-preview.js'), formats: ['es'], fileName: () => 'mascot-preview.js' },
  },
});
console.log('Built website/vendor/mascot-preview.js');
