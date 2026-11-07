# Lil Agent for macOS and Windows

The Electron edition of Lil Agent, the desktop pet that acts out what your AI coding agent is doing: Electron + Vite + three.js, for macOS and Windows. It's a
port of the optional native Swift app in `../LilAgentMac`, sharing Clawd and Codex's
state and timing, Codex's typing/coffee/bed/waking acting, the tears, typing along, the agent reactions, the
Settings panel, per-character sizes, turning moods off, look at cursor, and Ctrl+\ on Windows or ⌘\ on Mac to show or hide the mascot.

| Mac app (Swift) | Here (JavaScript) |
|---|---|
| `Character/States.swift`, `Pet.swift`, `Face.swift`, `Pose.swift`, `StateMachine.swift`, `Locomotion.swift` | `src/character/*.js` |
| `Model/Mascot.swift` (and its SceneKit shaders) | `src/model/mascot.js`, `src/model/bedding.js` (GLSL) |
| `Core/Stage.swift` | `src/core/stage.js` |
| `Effects/TypedLetters.swift` | `src/effects/typedLetters.js` |
| `Interaction/PointerDirector.swift`, `AgentDirector.swift` | `src/interaction/*.js` |
| `App/PetController.swift` | `src/main.js` (simulation) + `electron/main.js` (app) |
| `App/SettingsPanel.swift` | `settings.html`, `src/settings/panel.{js,css}` |
| `System/AgentBridge.swift`, `ClaudeHooks.swift`, `CodexHooks.swift`, `Watchers.swift` | `electron/agentBridge.js`, `hooks.js`, `keyWatcher.js`, `musicWatcher.js` |
| `Core/Settings.swift` | `electron/settings.js` |

Constants keep their Swift names, so a tweak in one app is a quick find in the other.

## Run and build

```bash
npm install
npm run dev
npm start
npm run dist:win
npm run dist:mac
```

Run these commands from `LilAgentWindows`. The folder name is retained for compatibility; it contains both Electron platforms.
The current prepared Mac release requires macOS 13 or later and supports Apple silicon. The Windows installer includes x64 and ARM64.
The native Swift app remains in `../LilAgentMac` and requires macOS 14 or later.

For a local Mac app archive without notarization, run `npm run build`, then
`npx electron-builder --mac zip --arm64 --publish never --config.mac.notarize=false`.
Signing and notarization depend on your Electron Builder configuration. The locally prepared release is ad hoc signed and unnotarized;
macOS may block its first launch. See [Apple's app-opening guidance](https://support.apple.com/en-us/102445).

Quit the other Lil Agent edition before launching: both use the local agent hook port. On Mac, Electron stores its settings
in `~/Library/Application Support/Lil Agent (Electron)/`; the native Swift app uses a separate settings folder.
Typing reactions require **Accessibility** access on Mac. Music reactions may request permission to check Spotify or Music.

`npm run assets` (run by all of the above) copies the shared art from the Mac app — `clawd.glb`, `codex.glb`,
`bed.glb`, the character renders, the menu-bar icon and the splash artwork — so both apps always use the same files.
Edit them there. The app icons (`assets/icon.icns`, `assets/icon.ico`) and the Windows tray icons (`assets/trayWindows*.png`)
are generated with the rest of the branding by `swift ../LilAgentMac/Art/Brand/export.swift` on a Mac.

`npm run test:animation`, `npm run test:status-text`, `npm run test:startup` (splash and startup coordination) and
`npm run test:updates` run the checks.

**Updates:** Settings › General checks the latest GitHub release of `UPDATE_REPO` (in `brand.js`), and the app checks quietly
at launch and daily. A newer release shows **Update Available** there and in the tray menu, opening the release page. Raise
`version` in `package.json`, build, and publish a release tagged `v<version>` with the installers attached.
Keep the download filenames used by the root README: `Lil-Agent-Electron-macOS-arm64.zip`, `Lil-Agent-Windows-Setup.exe`,
and, if included, `Lil-Agent-Native-Swift-macOS.zip`. Electron Builder's default Mac filename may need renaming before upload.

## Differences from the native Swift app

- **Settings panel:** solid black instead of glass; its own title bar with a close button.
- **Icons:** [Lucide](https://lucide.dev) (ISC licence) instead of SF Symbols — Apple's SF Symbols
  licence only allows them in apps for Apple platforms.
- **Shortcut:** Ctrl+\ (⌘\ when run on a Mac).
- **Letters:** SF Pro Rounded isn't on Windows; they fall back to Segoe UI.

## Check on a Windows PC (couldn't be tested from a Mac)

- **Claude Code / Codex hooks.** They're the same bash commands as on the Mac (`curl … || true`). Claude Code runs
  hooks through Git Bash on Windows, so they should work; confirm Codex does too.
- **Typing along** uses a global keyboard hook (`uiohook-napi`) with a US layout on both platforms, without an app-level password-field filter.
  On Windows, the letters above the pet can show what's typed into password fields. Disable typing reactions for sensitive input on either platform.
- **Dance to music** reads Windows' media sessions (Spotify, Apple Music, iTunes) through a small PowerShell helper.
- The tray icon (white or black to match the taskbar theme), the splash at different display scales, the installer and
  Start-menu icons, Ctrl+\, open at login, and the window staying on top.

## Debug switches (environment variables)

`LILAGENT_CHARACTER=codex`, `LILAGENT_STATE=sleep`, `LILAGENT_THEN=wake@3`, `LILAGENT_TYPE="hello"`, `LILAGENT_SIZE=330`,
`LILAGENT_CENTER=1`, `LILAGENT_IGNORE_HOME=1`, `LILAGENT_NO_KEYS=1`, `LILAGENT_SNAPSHOT=frame.png` (+ `LILAGENT_SNAPSHOT_AFTER=4`),
`LILAGENT_FILM=dir` (+ `LILAGENT_FILM_AT="start,step,count"`), `LILAGENT_SETTINGS_SHOT=dir` (every Settings tab),
`LILAGENT_SPLASH_FILM=dir` (+ `LILAGENT_SPLASH_FILM_AT="start,step,count"`; holds the splash and films it),
`LILAGENT_FAIL_STARTUP=1` (exercises the startup error path), `LILAGENT_UPDATE_REPO=owner/name` (checks another repo's releases). Snapshots and films skip the splash.

## Renaming

The name lives in `brand.js` (`APP_NAME`, `APP_ID`) plus `productName`, `build.appId` and `build.productName` in
`package.json`.

An unofficial fan project, not affiliated with Anthropic or OpenAI.
