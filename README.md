<p align="center">
  <img src=".github/assets/lil-agent-3d.png" alt="Lil Agent" width="149" />
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/readme-hero-dark.svg" />
    <img src=".github/assets/readme-hero-light.svg" alt="Lil Agent — A little desktop companion for your AI coding sessions." width="1200" />
  </picture>
</p>

<p align="center">
  Choose <strong>Clawd</strong> or <strong>Codex</strong> and watch your companion act out<br />
  what your local Claude Code or Codex agent is doing.
</p>

<br />

<p align="center">
  <a href="https://github.com/misanode/lil-agent/releases/latest/download/Lil-Agent-Electron-macOS-arm64.zip"><img src=".github/assets/get-for-mac.svg" alt="Get for Mac — Electron app for Apple silicon" width="240" /></a>
  &nbsp;
  <a href="https://github.com/misanode/lil-agent/releases/latest/download/Lil-Agent-Windows-Setup.exe"><img src=".github/assets/get-for-windows.svg" alt="Get for Windows — Electron app" width="288" /></a>
</p>

<p align="center">
  <sub>Electron for macOS and Windows. The Mac download supports Apple silicon.</sub>
</p>

<br />

<p align="center">
  <a href="https://github.com/misanode/lil-agent/releases/latest/download/Lil-Agent-Native-Swift-macOS.zip"><img src=".github/assets/get-native-swift-for-mac.svg" alt="Native Swift for Mac" width="330" /></a>
</p>

<p align="center">
  Written entirely in Swift with AppKit and SceneKit.<br />
  A smaller download for people who prefer native macOS frameworks.<br />
  <sub>macOS 14+ · Apple silicon &amp; Intel · <a href="LilAgentMac/README.md">Native setup &amp; build guide</a></sub>
</p>

<br />

### A little company, while you code

Lil Agent reacts to your local Claude Code and Codex sessions—from thinking and reading to running commands, needing attention, and finishing work. Child-agent activity gets its own reactions, too.

Pet, carry, throw, and resize your companion. Customize its moods, size, and sleep behavior. Add typing reactions, cursor attention, or music reactions, and use a keyboard shortcut to show or hide it.

<br />

### Get started

Check [Releases](https://github.com/misanode/lil-agent/releases) for published installers. For local builds, follow your platform’s guide.

The release downloads are ready to run—no Node.js, npm, Xcode, or terminal commands required. On Mac, unzip and move **Lil Agent.app** to **Applications**. On Windows, run the installer.

**macOS · Electron** · `.zip` app · Apple silicon · macOS 13+ · [Setup & build guide](LilAgentWindows/README.md)

**Windows · Electron** · `.exe` installer · x64 & ARM64 · [Setup & build guide](LilAgentWindows/README.md)

**macOS · Native Swift** · `.zip` app · Apple silicon & Intel · macOS 14+ · [Setup & build guide](LilAgentMac/README.md)

<br />

### Good to know

<details>
  <summary>Can I use it without a coding agent?</summary>
  <p>Yes. Lil Agent works as a desktop companion on its own. Connect local Claude Code or Codex sessions when you want reactions to agent activity.</p>
</details>

<details>
  <summary>Which platforms does it run on?</summary>
  <p>The main macOS and Windows downloads use Electron and Three.js. The Electron Mac download supports Apple silicon and requires macOS 13 or later. The optional native Swift app supports Apple silicon and Intel Macs running macOS 14 or later.</p>
</details>

<details>
  <summary>What permissions does it need?</summary>
  <p>On Mac, Electron typing reactions require Accessibility access; the native Swift app uses Input Monitoring. Music reactions may ask for permission to check Spotify or Music. Agent integrations are optional and use local hooks.</p>
  <p>Electron typing reactions use a US keyboard layout and have no app-level password-field filter. On Windows, this can display characters entered into password fields. Disable typing reactions when entering sensitive information.</p>
</details>

<br />

<p align="center">
  <sub><a href="LICENSE">MIT license</a> · Unofficial fan project. Not affiliated with Anthropic or OpenAI.</sub>
</p>
