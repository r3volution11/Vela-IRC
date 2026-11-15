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
- [ ] **Window**
  - [x] Fully themed custom 3-pane window shell
  - [ ] Compact sidebar that collapses to a rail
  - [ ] Vivaldi-style two-level tab stacks (top / title bar / bottom, square-to-pill corners)
  - [ ] Member list
- [x] **Presets:** Classic IRC, Modern Chat, Tabbed, Focus (settings layer)
- [ ] **Message layouts:** Classic, Modern grouped, Compact columns
- [ ] **Chat rendering**
  - [ ] mIRC formatting and colors
  - [ ] Nick colors
  - [ ] Collapsed join/part
  - [ ] Unread markers and day separators
- [ ] **Inline media**
  - [ ] Images and animated GIF/WebP
  - [ ] Link cards
  - [ ] YouTube/Vimeo/Twitch/Streamable players
  - [ ] Media policy: per network/channel, domain lists, size limits
- [ ] **IRCv3 chat**
  - [ ] Reactions, replies, typing indicators, redaction
  - [ ] `chathistory` paging
- [ ] **Bouncers:** soju (`bouncer-networks`) and ZNC (`playback`, `self-message`)
- [ ] **Settings window**
  - [ ] Theme gallery
  - [ ] Network editor with SASL and certificates
  - [ ] Notifications
- [ ] **Basic in-app theme editor** with live preview

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
