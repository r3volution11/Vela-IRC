# Vela Roadmap

## Milestone 1: a usable v1 (in progress)

- [x] Project scaffold: Xcode app target, `VelaKit` package, CI, MPL-2.0
- [ ] **IRC core**
  - [ ] Message parsing with IRCv3 tags
  - [ ] TLS connections
  - [ ] CAP 302 negotiation
  - [ ] SASL PLAIN/EXTERNAL and client certificates
  - [ ] ISUPPORT and casemapping
  - [ ] Reconnect with backoff
  - [ ] STS
- [ ] **Storage**
  - [ ] SQLite scrollback with FTS5
  - [ ] VS Code-style `settings.json` with live reload
  - [ ] Network configs
  - [ ] Keychain secrets
- [ ] **Theme engine**
  - [ ] Token registry with fallback chains
  - [ ] JSON(C) theme files, `include`, and `colorCustomizations` overrides
  - [ ] Live reload
  - [ ] VS Code theme import (`.json` / `.vsix`)
  - [ ] Generated JSON Schema
  - [ ] ~21 built-in themes
- [ ] **Window**
  - [ ] Fully themed custom 3-pane window
  - [ ] Compact sidebar that collapses to a rail
  - [ ] Member list
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
