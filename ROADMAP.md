# Vela Roadmap

## Milestone 1: a usable v1 (in progress)

- [x] Project scaffold: Xcode app target, `VelaKit` package, CI, MPL-2.0
- [x] Demo mode with offscreen screenshots (`scripts/demo-screenshot.sh`)
- [x] **IRC core**
  - [x] Message parsing with IRCv3 tags
  - [x] TLS connections
  - [x] CAP 302 negotiation
  - [x] SASL PLAIN/EXTERNAL and client certificates
  - [x] ISUPPORT and casemapping
  - [x] Reconnect with backoff
  - [x] STS
- [x] **Storage**
  - [x] SQLite scrollback with FTS5
  - [x] VS Code-style `settings.json` with live reload
  - [x] Network configs
  - [x] Keychain secrets
- [x] **Theme engine**
  - [x] Token registry with fallback chains
  - [x] JSON(C) theme files, `include`, and `colorCustomizations` overrides
  - [x] Live reload
  - [x] VS Code theme import (`.json` / `.vsix`)
  - [x] Generated JSON Schema
  - [x] ~21 built-in themes
- [x] **Window**
  - [x] Fully themed custom 3-pane window shell
  - [x] Compact sidebar that collapses to a rail
  - [x] Vivaldi-style two-level tab stacks (top / title bar / bottom, square-to-pill corners)
  - [x] Member list
- [x] **Presets:** Classic IRC, Modern Chat, Tabbed, Focus
- [x] **Message layouts:** Classic, Modern grouped, Compact columns
- [x] **Chat rendering**
  - [x] mIRC formatting and colors
  - [x] Nick colors
  - [x] Collapsed join/part
  - [x] Unread markers and day separators
- [x] **Inline media**
  - [x] Images and animated GIF/WebP
  - [x] Link cards
  - [x] YouTube/Vimeo/Twitch/Streamable players
  - [x] Media policy: per network/channel, domain lists, size limits
- [ ] **IRCv3 chat**
  - [x] Reactions, replies, typing indicators, redaction
  - [x] `chathistory` paging
- [ ] **Bouncers:** soju (`bouncer-networks`) and ZNC (`playback`, `self-message`)
- [x] **Settings window**
  - [x] Theme gallery
  - [x] Network editor with SASL and certificates
  - [x] Notifications
- [x] **Basic in-app theme editor** with live preview

## Later

- **Uploads:** paste or drag images, via IRCv3 FILEHOST (soju) and a custom uploader config
- **Distribution:** notarized DMG with Sparkle auto-updates, then a Mac App Store build
- **Search:** message search UI on top of the existing FTS5 index
- **iCloud sync** of networks, settings and themes
- **Per-network/per-channel themes**
- **More IRCv3:**
  - `draft/multiline`
  - `draft/read-marker` sync
  - `draft/metadata-2` avatars
  - Message edits once the spec is ratified
- **Scripting and plugins**
- **DCC** file transfer and chat
- **Accessibility:** a full VoiceOver audit and a high-contrast theme set
