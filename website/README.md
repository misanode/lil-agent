# Lil Agent website

A static site: HTML, CSS and JavaScript. No build is needed to host it.

## Run it locally

The live 3D mascots load `.glb` models, which browsers block over `file://`. Serve the folder instead:

```sh
cd website
python3 -m http.server 8000
# open http://localhost:8000
```

Opened straight from disk, the page still works but shows the PNG fallbacks instead of the live mascots.

## Live mascots

The previews (desktop mockup and feature cards) run the app's real mascot code from `LilAgentWindows/src` — the same models, states, animation clips, props and status text.

- `assets/models/*.glb` are copies of `LilAgentWindows/public/models/`.
- `vendor/mascot-preview.js` is a bundle of `preview-src/mascot-preview.js` plus the app code and three.js.

After changing the app's mascot code or models, rebuild from the repo root (uses the app's installed Vite):

```sh
cp LilAgentWindows/public/models/{clawd,codex,bed}.glb website/assets/models/
node website/preview-src/build.mjs
```

## Other assets

- The download buttons (`assets/get-*.svg`) are copies of the ones in `.github/assets/`, so the site and the README match. Re-copy them if the README buttons change.
- **Apple assets:** the Apple icons in `assets/dock/` (except `lil-agent.png`), SF Symbols in `assets/menubar/`, and `assets/wallpaper-macos.jpg` are © Apple Inc. and are not covered by the MIT license. They were rendered from macOS 27 for the desktop mockup.

Downloads link to the latest GitHub release. Upload this folder to any static host when ready.
