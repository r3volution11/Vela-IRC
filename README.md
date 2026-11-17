<p align="center">
  <img src="docs/vela-icon.png" width="128" height="128" alt="Vela icon">
</p>

<h1 align="center">Vela</h1>

<p align="center">
  A modern, deeply themable IRC client for macOS.<br>
  Native SwiftUI · IRCv3 · inline media · VS Code-style themes
</p>

<p align="center">
  <a href="https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg"><b>Download for macOS</b></a> ·
  <a href="https://velairc.app">Website &amp; docs</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="ROADMAP.md">Roadmap</a>
</p>

<p align="center">
  <a href="https://github.com/r3volution11/Vela-IRC/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/r3volution11/Vela-IRC?label=release&color=ab47bc"></a>
  <a href="https://github.com/r3volution11/Vela-IRC/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/r3volution11/Vela-IRC/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-82aaff">
  <a href="LICENSE"><img alt="License: MPL-2.0" src="https://img.shields.io/badge/license-MPL--2.0-c3e88d"></a>
</p>

<p align="center">
  <img src="docs/screenshots/modern-palenight.png" alt="Vela with the Modern Chat preset in Palenight: grouped messages, an inline GIF, reactions and a link card" width="100%">
</p>

<table>
  <tr>
    <td><img src="docs/screenshots/focus-tabs-palenight.png" alt="Focus preset: pill tabs in the title bar and compact columns"></td>
    <td><img src="docs/screenshots/classic-graphite.png" alt="Classic IRC preset in Vela Graphite: monospace one-line messages"></td>
  </tr>
  <tr>
    <td align="center"><sub>Focus preset · pill tab stacks in the title bar</sub></td>
    <td align="center"><sub>Classic IRC preset · Vela Graphite</sub></td>
  </tr>
</table>

## Contents

- [Install](#install)
- [Why Vela?](#why-vela)
- [Features](#features)
- [Getting started](#getting-started)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Customizing Vela](#customizing-vela)
- [Privacy](#privacy)
- [Building from source](#building-from-source)
- [Project layout](#project-layout)
- [Contributing](#contributing)
- [License and credits](#license-and-credits)

## Install

1. Download **[Vela.dmg](https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg)**, the latest release.
2. Open it and drag **Vela** into **Applications**.
3. Launch Vela from Applications or Spotlight.

Requirements:

- macOS 26 Tahoe or later, on Apple silicon or Intel.
- Releases are signed with a Developer ID and notarized by Apple, so they open without security warnings.

The full user guide is at **[velairc.app](https://velairc.app)**.

## Why Vela?

IRC is simple, open and everywhere, but IRC clients on the Mac have stood still. Vela pairs IRC's simplicity with what people now expect from chat: inline media, reactions, replies and a polished native interface. It is built around one idea: **make Vela work the way you want.**

- **Every pixel is themable.** You can import VS Code themes, edit themes live and override any color from `settings.json`.
- **Navigation is your choice.** Use a sidebar (or a thin rail) if you're on many networks, or Vivaldi-style tab stacks if you're on a few.
- **Three message layouts.** Pick Classic one-line, Modern grouped, or Compact columns.
- **Presets get you started.** Each preset sets up a whole style in one click, so you don't have to get into the weeds.

## Features

### Themes everywhere

- **Every surface** draws from named color tokens, the way VS Code themes work: the title bar, sidebar and rail, tabs, chat, input, member list, embeds and settings.
- **21 built-in themes:**
  - Material-inspired: Palenight (default dark), Lighter (default light), Oceanic, Darker, Ocean, Deepforest, Volcano and Sandy Beach.
  - Vela originals: Vela Graphite, Vela Paper and Vela Mist.
  - Ports of popular editor themes: Dracula, Nord, Catppuccin Latte and Mocha, Tokyo Night, One Dark, Gruvbox Dark, Solarized Dark and Light, and Rosé Pine.
- **Select Theme** in the command palette previews each theme live as you move through the list.
- **Follows macOS** light and dark appearance, using a preferred theme for each.
- **Theme editor** with color wells for every token, contrast warnings and live preview of the whole app.
- **Import VS Code themes** (`.json` or `.vsix`). Editor, sidebar, list, input, badge and terminal ANSI colors map onto Vela's tokens automatically.
- **Theme files are JSON (comments allowed),** with `include` for inheritance and a published JSON Schema for autocomplete. They reload live as you edit them.
- **`appearance.colorCustomizations`** in `settings.json` overrides any token, globally or for one theme (`"[Palenight]": { … }`).

### Navigation and layout

- **Sidebar:** a compact network/channel tree with unread and mention badges. It collapses to a thin icon rail, and the window buttons stack vertically to fit. Hover the rail to peek at the full tree.
- **Tab stacks:** Vivaldi-style two-level tabs, with networks on top and that network's channels below.
  - Place them **at the top**, **in the title bar** or **above the input**.
  - Corners range from square to pill.
  - The network row hides automatically when you're on a single network.
- **Message layouts:**
  - **Classic** — `[12:01] <nick> text`
  - **Modern grouped** — one name header per run of messages
  - **Compact columns** — time, right-aligned nick, then text
- **Density controls:** fonts (including a monospace mode), line and message spacing, timestamps, nick colors and optional avatars. Join/part/quit noise can be shown, collapsed into one line, or hidden.

### Presets

One click sets navigation, layout, density and media together. Presets never touch your theme, and you can keep tweaking afterwards.

| Preset | What you get |
|---|---|
| **Classic IRC** | Sidebar, one-line monospace messages, dense spacing, minimal link previews |
| **Modern Chat** | Sidebar, grouped messages, full inline media |
| **Tabbed** | Tab stacks at the top, grouped messages, rounded tabs |
| **Focus** | Pill tabs in the title bar, compact columns, no join/part noise, member list hidden |

### Messages and media

- **Inline images and animated GIFs.** Click one to view it full size.
- **Link previews** with the page title, description, site name and thumbnail, accented with the page's own theme color.
- **Video players** for YouTube, Vimeo, Twitch and Streamable. The player loads only when you press play, and you can expand it to fill the window.
- **Your choice of size:** Minimal, Standard or Large link previews, full or compact videos, and full-size or thumbnail images.
- **Site rules and an adult-site filter:** show everything, text only or nothing per site. Adult sites' previews are hidden by default, checked on your Mac against a list bundled with Vela. Images can stay blurred until clicked.
- **mIRC formatting:** bold, italic, underline, strikethrough, monospace, colors (including hex) and reverse.
- **Reactions, replies, typing indicators and message deletion,** where the server supports IRCv3 message tags.
- **Day dividers, a "New" marker** at your last read position, and a "Jump to present" button.

### IRC done properly

- **Secure connections:** TLS with certificate validation, plus an opt-in "Allow invalid certificates" for self-signed bouncers.
- **Authentication:** SASL PLAIN and EXTERNAL, client certificates, and server passwords. All secrets live in the macOS Keychain.
- **IRCv3:**
  - `server-time`, `echo-message`, `batch`, `labeled-response`, `chathistory`
  - `message-tags`, `away-notify`, `account-notify`, `extended-join`, `multi-prefix`, `userhost-in-names`
  - `setname`, `chghost`, `invite-notify`, `cap-notify`, STS, `message-redaction`
- **Reconnection:** automatic, with backoff, including after sleep/wake and network changes.
- **Bouncers:**
  - **ZNC:** server-password login, `self-message`, `playback`, server-time.
  - **soju:** your bouncer's networks appear automatically, and history comes from `chathistory`.
- **Scrollback:** stored locally in SQLite with full-text indexing. Older history is paged in from disk, then from the server.

### Fast to drive

- **Command palette** (⇧⌘P) runs any command: layouts, presets, themes, network actions, settings and more.
- **Quick switcher** (⌘P or ⌘K) jumps to any channel or conversation with fuzzy search.
- **Composer:** Tab completion for nicks, channels, `/commands` and `:emoji:` shortcodes, plus per-channel history and drafts. Pasting multiple lines asks for confirmation before sending.
- **Slash commands:**
  - `/join`, `/part`, `/msg`, `/query`, `/me`, `/nick`, `/topic`, `/away`, `/whois`
  - `/mode`, `/kick`, `/ban`, `/op`, `/voice`, `/invite`
  - `/ctcp`, `/raw`, `/ignore`, `/close`, `/clear`, `/quit`
  - Any other command is sent to the server as typed.

## Getting started

1. Open Vela and click **Add Network…** (⇧⌘N).
2. Pick a preset such as Libera.Chat or OFTC, or enter a server, port and nickname yourself.
3. Choose how to sign in: SASL for most networks, a server password for ZNC, or a client certificate.
4. Click **Save**. Vela connects and joins your auto-join channels. Press ⌘J to join more.

**Connecting through ZNC:** turn on **Bouncer → ZNC** and use your ZNC password in the form `username/network:password`. If your ZNC listener doesn't use TLS, turn TLS off for that network. If it uses a self-signed certificate, turn on **Allow invalid certificates** instead. Vela and your other clients can stay connected to ZNC at the same time.

**Connecting through soju:** turn on **Bouncer → soju**. Vela lists the networks on your bouncer and connects to each one.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Command palette | ⇧⌘P |
| Go to channel or conversation | ⌘P or ⌘K |
| Select theme | ⌃⌘T |
| Show/hide member list | ⇧⌘M |
| Collapse/expand sidebar | ⌃⌘S |
| Previous / next conversation | ⌥⌘↑ / ⌥⌘↓ |
| Next unread | ⌥⇧⌘↓ |
| Focus the message field | ⌘L |
| Add network | ⇧⌘N |
| Join channel | ⌘J |
| Bigger / smaller / actual-size text | ⌘+ / ⌘− / ⌘0 |
| Settings | ⌘, |

## Customizing Vela

- **Settings** (⌘,) has panes for Presets, Appearance, Layout, Messages, Media, Networks, Notifications and Advanced. Every change applies immediately.
- **`settings.json`** holds everything, VS Code style. Open it from **Theme → Open settings.json** or **Settings → Advanced**. Edits made in any editor apply live. Example:

  ```jsonc
  {
    "appearance.theme": "Tokyo Night",
    "appearance.followSystem": false,
    "appearance.colorCustomizations": {
      "chat.background": "#16161e",
      "[Tokyo Night]": { "accent": "#ff9e64" }
    },
    "navigation.style": "tabs",
    "tabs.placement": "titleBar",
    "tabs.roundness": 1,
    "chat.layout": "columns",
    "chat.showJoinPart": "hide",
    "media.siteRules": { "example.com": "block", "news.example": "textOnly" }
  }
  ```

- **Themes folder.** Choose **Theme → Reveal Themes Folder**, drop theme files in, and they appear immediately. See the [theme authoring guide](docs/THEMES.md) and the [JSON Schema](schemas/vela-theme.schema.json).

## Privacy

- **No telemetry, analytics or accounts.** Vela talks only to the IRC servers you add.
- **Link previews** fetch the linked page or image, which reveals your IP address to that site. You can control this:
  - Turn previews off entirely, or switch to click-to-load.
  - Disable media for a network or channel.
  - Set per-site rules: everything, text only or nothing.
- **No previews from your local network.** Vela never fetches previews from private, local or LAN addresses.
- **Passwords and certificates** are stored in the macOS Keychain. Vela is sandboxed.

## Building from source

You need Xcode 27 or later.

```sh
git clone git@github.com:r3volution11/Vela-IRC.git
cd Vela-IRC
scripts/run.sh               # build and launch build/Vela.app
scripts/run.sh --demo        # launch with offline sample content
```

Or open `Vela.xcodeproj` in Xcode (the project file, not the folder), choose the **Vela** scheme and **My Mac**, and press ⌘R.

```sh
swift test --package-path Packages/VelaKit                    # unit tests (400+)
VELA_LIVE_TESTS=1 swift test --package-path Packages/VelaKit \
  --filter "LiveNetwork|LiveSession"                          # live TLS + IRCv3 checks against public servers
scripts/demo-screenshot.sh build/Vela.app shot.png --theme Lighter --preset tabbed   # offscreen screenshot
```

To build a signed and notarized release, see [docs/RELEASING.md](docs/RELEASING.md).

## Project layout

```
Vela/                    Thin macOS app target (entry point, app icon, entitlements)
Packages/VelaKit/
  Sources/VelaIRC        IRC protocol, IRCv3 negotiation, SASL, TLS connection
  Sources/VelaStore      SQLite scrollback, settings.json, networks, Keychain, presets
  Sources/VelaTheme      Token registry, theme loading, VS Code import, live reload
  Sources/VelaMedia      Link detection, previews, images, video embeds
  Sources/VelaCore       App and session models tying it together
  Sources/VelaUI         SwiftUI views, scenes, command palette
schemas/                 JSON Schema for theme files
website/                 velairc.app (VitePress)
docs/                    Theme authoring guide, credits, release process
design/app-icon/         App icon generators and geometry (see its README)
scripts/                 run, release, screenshot and icon export tools
```

## Contributing

Contributions are welcome, especially themes. See [CONTRIBUTING.md](CONTRIBUTING.md). The [roadmap](ROADMAP.md) lists what's planned next, including image uploads, search, iCloud sync and auto-updates.

## License and credits

Vela is licensed under the [Mozilla Public License 2.0](LICENSE):

- You can use, modify and distribute it, including in paid or App Store builds.
- Changes to Vela's own source files must stay open.

Third-party components and ported themes keep their own licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [docs/THEME-CREDITS.md](docs/THEME-CREDITS.md). The Material-inspired themes are original designs inspired by the classic Material Theme palettes; Vela is not affiliated with Material Theme or Vira Software.
