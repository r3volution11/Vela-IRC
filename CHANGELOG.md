# Changelog

All notable changes to Vela are listed here. Vela follows [Semantic Versioning](https://semver.org/). While it's below 1.0, minor versions may include breaking changes to settings or theme files, and those are always called out here.

## Unreleased

### Added

- **Drag to reorder networks and channels** in the sidebar, the rail, the tab bars and Settings → Networks. The order is the same everywhere and is remembered.
  - Channels stay above private conversations, and each moves within its own group.
  - Networks provided by a soju bouncer stay under their bouncer; moving the bouncer takes them along.
  - Reordering channels also reorders the network's auto-join list.
  - New channels and conversations now go at the end of their group instead of in alphabetical order. **Sort Channels A–Z** (right-click a network, the Network menu, or the command palette) puts them back in order.
  - Esc cancels a drag, and VoiceOver offers Move Up/Down (Move Left/Right on tabs) actions.

### Fixed

- The **New** unread marker now appears while the window is in the background, and messages you've already seen no longer appear below it.

## 0.1.0 - 2026-11-16

The first public release of Vela, a native, deeply themable IRC client for macOS.

### Highlights

- **Fully themable interface.** Every surface (title bar, sidebar, tabs, chat, input, member list, embeds, settings) draws from named color tokens, the way VS Code themes work.
  - Built-in themes: 21. Palenight and Lighter are the default dark/light pair.
  - Theme editor with live preview.
  - Import any VS Code theme from a `.json` or `.vsix` file.
  - Theme files in the Themes folder reload live as you edit them.
  - Override any token from `settings.json` with `appearance.colorCustomizations`.
- **Your layout, your way.**
  - A compact sidebar that collapses to a thin rail; the window buttons stack vertically when it's narrow.
  - Or Vivaldi-style two-level tab stacks, at the top, in the title bar or above the input, with corners from square to pill.
  - Three message layouts: Classic, Modern grouped and Compact columns.
- **One-click presets.** Classic IRC, Modern Chat, Tabbed and Focus set up navigation, layout, density and media in one step. Your theme is never changed.
- **Command palette.** ⇧⌘P runs any command. ⌘P or ⌘K jumps to any channel or conversation. Select Theme previews themes live as you move through the list.
- **Inline media.**
  - Images and animated GIFs.
  - Link cards with page titles and descriptions.
  - YouTube, Vimeo, Twitch and Streamable players, loaded only when you press play.
  - Controls per network and per channel (right-click a network or channel), domain block/allow lists, size limits and a compact presentation.
  - Previews are never fetched from your local network.
- **Modern IRC.**
  - TLS, with certificate validation and an opt-in "allow invalid certificates" for self-signed bouncers.
  - SASL PLAIN and EXTERNAL, plus client certificates.
  - IRCv3: `server-time`, `echo-message`, `batch`, `chathistory`, `message-tags`, away/account/extended-join, reactions, replies, typing indicators and message redaction.
  - STS upgrades and automatic reconnect with backoff, including after sleep/wake and network changes.
- **Bouncers.** First-class ZNC support (server password login, `self-message`, `playback`, server-time) and soju support (bouncer network discovery and chathistory).
- **Scrollback and search-ready storage.**
  - Local SQLite history with full-text indexing.
  - Unread markers and day dividers.
  - Join/part runs that can be shown, collapsed or hidden.
- **VS Code-style `settings.json`.** Every setting is a documented key, and edits you make in an editor apply immediately.
- **Native and private.**
  - Built with Swift 6 and SwiftUI.
  - Sandboxed, with passwords in the macOS Keychain.
  - No telemetry.

### Known limitations

- Uploading images (FILEHOST / custom uploaders), message search UI, iCloud sync and automatic updates are planned. See the [roadmap](ROADMAP.md).
- Reactions, replies and typing indicators need a server or bouncer that passes IRCv3 message tags. Older ZNC versions don't, so Vela hides those features on such connections.
- The menu bar, context menus and system alerts follow macOS light/dark appearance rather than theme colors.
