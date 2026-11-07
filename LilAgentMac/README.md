# Lil Agent for Mac

Lil Agent, the desktop pet that acts out what your AI coding agent is doing, as a native macOS app: Swift, AppKit
and SceneKit, no Electron and no third-party code. Two characters: Clawd and Codex. The Windows edition is
`../LilAgentWindows` (Electron + three.js), a file-for-file port of this one.

An unofficial fan project, not affiliated with Anthropic or OpenAI.

Open `LilAgent.xcodeproj` in Xcode and press Run, or build from the terminal:

```bash
xcodebuild -project LilAgent.xcodeproj -scheme LilAgent -configuration Release -derivedDataPath build/DerivedData build
open "build/DerivedData/Build/Products/Release/Lil Agent.app"
```

- Quit the Electron pet first: both listen for Claude Code on port 47613. The hooks it installed keep working as-is.
- Settings live in `~/Library/Application Support/Lil Agent/` (taken over from the older `Clawd` folder on first launch).
- macOS asks once for **Input Monitoring** (type along) and for permission to check Spotify/Music (dancing).
  Ad-hoc signed builds may ask again after a rebuild.

## Development signing and Input Monitoring

For permission grants to survive Xcode rebuilds, use a consistent Apple Development signing identity.
Copy `Config/LocalSigning.example.xcconfig` to `Config/LocalSigning.xcconfig` and replace `YOUR_TEAM_ID`
with your development team ID. The local file is ignored by Git and applies to Debug builds only.
In Xcode, sign in under Settings › Accounts and make sure that team has an Apple Development certificate
under Manage Certificates. The shared project keeps its generic bundle identifier.

After switching signing identities, grant Input Monitoring to the newly signed copy once. If Lil Agent
is missing from System Settings › Privacy & Security › Input Monitoring, choose **Show App** in
Lil Agent Settings › Agents, then use the **+** button in Input Monitoring to add that exact `.app`.
Quit and reopen the app if macOS requests it. Removing an older entry and adding the current app can
also resolve a stale entry after signing or bundle-identifier changes.

## Signed Mac releases

People installing the release download `Lil-Agent-macOS.dmg`, open it, drag **Lil Agent** to
**Applications**, and launch it there. They do not need Xcode. Input Monitoring is needed for
typing reactions, and music reactions require permission to control Spotify or Music. Claude Code
or Codex is only needed for its corresponding agent integration.

The publisher needs Apple Developer Program membership and a **Developer ID Application** certificate
with its private key in the Mac's keychain. Create the certificate in Xcode Settings › Accounts ›
Manage Certificates using an eligible developer team. An Apple Development certificate is for local
development and cannot replace Developer ID for this release workflow.

Store notarization credentials in Keychain interactively, then run the release script from this folder:

```bash
xcrun notarytool store-credentials lil-agent-notary
bash Scripts/release.sh lil-agent-notary
```

The credentials prompt supports an Apple ID, team ID, and app-specific password. Keep credentials
in Keychain rather than source files. If multiple Developer ID identities are installed, supply the
chosen certificate's SHA-1 fingerprint as the script's second argument.

The script builds for Apple silicon and Intel, signs with hardened runtime and Apple Events access,
packages the app with an Applications shortcut, submits the DMG to Apple, staples the accepted
notarization ticket, and checks Gatekeeper. Output and logs go in an ignored `release/macos.*` folder.
Distribute the DMG only after the script reports **Signed and notarized installer**. Test that DMG
on a separate Mac before publishing, including typing and music permissions. Failed notarization
leaves logs beside the installer; a DMG existing on disk alone does not mean it is ready to distribute.

## Layout

| Folder | What |
|---|---|
| `LilAgent/App` | App entry, transparent click-through window, menu-bar and right-click menus, frame loop |
| `LilAgent/Core` | Stage (camera, lights, shadow, environment), screen-space maths, settings, helpers |
| `LilAgent/Model` | Minimal glTF (.glb) loader, animation mixer, the mascot's body (port of `CustomMob.js`) |
| `LilAgent/Character` | Pose, face, locomotion, personality, state machine and every state (port of `states.js`) |
| `LilAgent/Effects` | Typed letters and emotes |
| `LilAgent/Interaction` | Pointer (pet, carry, throw, resize) and Claude Code / music / typing director |
| `LilAgent/System` | Claude Code hook listener and installer, keyboard and music watchers |

To change the model, export it from Blender as `.glb` into `LilAgent/Resources/clawd.glb` (node names `eyes`,
`trunk`, `prop_laptop…` and clips named after the states are used the same way as before).

Debug switches (environment variables): `LILAGENT_STATE=dance`, `LILAGENT_TYPE="hello"`, `LILAGENT_IGNORE_HOME=1`,
`LILAGENT_NO_KEYS=1`, `LILAGENT_SNAPSHOT=/path/frame.png` (+ `LILAGENT_SNAPSHOT_AFTER=4`, skips the splash),
`LILAGENT_SPLASH_FILM=/path/dir` (+ `LILAGENT_SPLASH_FILM_AT="start,step,count"`; holds the splash and films it),
`LILAGENT_FAIL_STARTUP=1` (exercises the startup error path).

## Updates

Settings › General › Updates checks the latest release of the public GitHub repository `misanode/lil-agent`
(`UpdateChecker.repository`; the Electron app reads `UPDATE_REPO` in `../LilAgentWindows/brand.js`). The apps also check
quietly at launch and once a day. When a newer release exists, the button turns into **Update Available** and the menu bar
menu gains an item; both open that release's page to download it. Until the repository has a release, they report **Up to Date**.

To ship an update, raise the version (`MARKETING_VERSION` in this project and `version` in `../LilAgentWindows/package.json`),
build the packages, and publish a GitHub release tagged `v` plus that version (for example `v1.0.1`) with them attached.
`LILAGENT_UPDATE_REPO=owner/name` points a build at another repository for testing. `bash Checks/updates.sh` runs the checks.

## Branding

The logo, splash, app icon and menu-bar artwork live in `Art/Brand`: the supplied originals in `Art/Brand/Source`,
and the named layers derived from them (`splash-card.svg`, `splash-logo.svg`, `splash-wordmark.svg`,
`menu-bar-mascot.svg` without the sparkles, and the `app-icon.svg` master). After editing them, run

```bash
swift Art/Brand/export.swift
```

It checks the layers against the originals, then writes the splash layers and menu-bar template into `LilAgent/Resources`,
the `AppIcon` set, and the Electron app's `icon.icns`, `icon.ico` and Windows tray icons. `bash Checks/startup.sh`
checks the splash and startup coordination.

## Codex reactions

The native app can listen to Claude Code and Codex together. Build and run this same Xcode project,
then choose **Connect to Codex…** from Lil Agent's menu-bar menu (or Settings › Agents). In Codex CLI, open `/hooks`
and review and trust the Lil Agent commands, then start a new session. Hook trust is managed by Codex, not by Lil Agent.
If you disabled Codex hooks in configuration, enable them first.

Lil Agent merges its handlers into `~/.codex/hooks.json` (or `$CODEX_HOME/hooks.json` when that environment
variable is set for the app). It makes a `.lil-agent-backup` before changing an existing file. Hooks installed under the old name (`# clawd-pet`) keep working and are replaced on the next install. Removing
Codex hooks preserves other handlers. The Claude hook configuration is unchanged.

Events are sent to `http://127.0.0.1:47613/codex`. Existing Claude events still use `/claude`.
Providers and child agents are tracked separately. Completion celebrates; interruption and session
end clear the activity. The menu status identifies the active provider. All reactions use the existing
native animation states. The Electron app is unchanged.

This integration requires Codex running locally with command hooks enabled. Hosted web-search tools
are not exposed through local tool hooks; cloud orchestration does not run these local command hooks.
See https://learn.chatgpt.com/docs/hooks for coverage and trust requirements.

Run focused lifecycle and hook-config checks with `bash Checks/run.sh`.
