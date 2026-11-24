# Vela Roadmap

## Milestone 1: a usable v1 (shipped in 1.0.0)

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
  - [x] [VS Code](https://code.visualstudio.com)-style `settings.json` with live reload
  - [x] Comment- and format-preserving writes to `settings.json`, with validation (unknown keys, types, ranges)
  - [x] Network configs
  - [x] Keychain secrets
- [x] **Theme engine**
  - [x] Token registry with fallback chains
  - [x] JSON(C) theme files, `include`, and `colorCustomizations` overrides
  - [x] Live reload
  - [x] VS Code theme import (`.json` / `.vsix`)
  - [x] Generated JSON Schema
  - [x] ~21 built-in themes
  - [x] Per-theme accent colors, picked from each theme's own palette
- [x] **Window**
  - [x] Fully themed custom 3-pane window shell
  - [x] Compact sidebar that collapses to a rail
  - [x] [Vivaldi](https://vivaldi.com)-style two-level tab stacks (top / title bar / bottom, square-to-pill corners)
  - [x] Member list
- [x] **Presets:** a window layout (Sidebar, Tabs on Top, Tabs in Title Bar, Focus), a message style (Modern, Classic IRC, Columns) and a density (Compact, Standard, Comfortable), combined freely
- [x] **Message layouts:** Classic, Modern grouped, Compact columns
- [x] **Chat rendering**
  - [x] [mIRC](https://www.mirc.com) formatting and colors
  - [x] Nick colors
  - [x] Collapsed join/part
  - [x] Unread markers and day separators
- [x] **Inline media**
  - [x] Images and animated GIF/WebP
  - [x] Link previews in three sizes (Minimal, Standard, Large)
  - [x] YouTube/Vimeo/Twitch/Streamable players: compact or full, expand to fill the window, one at a time, pause when out of view
  - [x] Media policy: per network/channel, per-site rules (everything / text only / nothing), size limits
  - [x] Adult-site filter with a bundled, on-device list and RTA label detection
  - [x] Blur images until clicked, everywhere or per channel
- [x] **IRCv3 chat**
  - [x] Reactions, replies, typing indicators, redaction
  - [x] `chathistory` paging
- [x] **Bouncers:** [soju](https://soju.im) (`bouncer-networks`) and [ZNC](https://znc.in) (`playback`, `self-message`)
- [x] **Settings window**
  - [x] Theme gallery
  - [x] Network editor with SASL and certificates
  - [x] Notifications
  - [x] VS Code-style settings editor: every setting in a searchable UI view (filters, Modified, chip fields, per-theme color overrides, unknown keys), and a JSON view with completion, inline problems, hover docs and the defaults alongside
- [x] **Basic in-app theme editor** with live preview
- [x] **Typing:** IRC-safe spelling, grammar, autocorrect, text replacements and smart quotes, following macOS until changed
- [x] **Apple Intelligence**
  - [x] Catch me up: on-device summaries of what you missed
  - [x] Writing Tools in the message field
  - [x] On-device message translation, per message or per channel
- [x] **Siri, Shortcuts and Spotlight:** App Shortcuts phrases, Shortcuts actions, channel names in Spotlight, and the macOS 27 Siri messages domain

## Milestone 2: updates and the keyboard (1.1.0)

- [x] **Updates:** Vela updates itself with [Sparkle](https://sparkle-project.org), from a signed feed on velairc.app, with an About window and **Settings → Updates**
- [x] **What's New** after an update, with notices about anything that changed for you
- [x] **Keyboard navigation everywhere:** focus areas for the sidebar or tabs, the messages, the message box and the member list (⌥⌘1–⌥⌘4, F6), messages from the keyboard, Safari-style tab switching, moving tabs, and ⌘W to close the tab
- [x] **Channels:** Leave and Remove, detach and hide on bouncers, Reopen Closed Channel (⇧⌘T) and undo
- [x] **Message history saving is optional,** off for new installs
- [x] **Emoji picker and send button** in the message box
- [x] **Tabs shrink to fit** before they scroll
- [x] **Nick colors in message text,** with your own nick's color kept for you
- [x] **Catch me up:** bouncer replays count, one summary at a time, progress, and Siri hands long catch-ups to Vela
- [x] **A redesigned welcome screen**

## Milestone 3: your models, your tools (1.5.0)

- [x] **Presets** as three choices that combine freely: window layout, message style and density, with the new **Focus** layout
- [x] **AI providers:** Catch me up and Recap with OpenAI, Anthropic or Google Gemini and your own key, or Ollama and LM Studio on your Mac, with **Settings → AI Privacy**
- [x] **Automation:** `vela://` links and an AppleScript dictionary
- [x] **Message search,** and your saved messages in Spotlight (opt-in)
- [x] **Integrations:** **Settings → Integrations**, an Alfred workflow and a Raycast extension

## Later

- **GIF search** in releases (built, in development builds for now), once KLIPY approves Vela's key
- **Private Cloud Compute for long catch-ups** in releases (opt-in, macOS 27; built, in development builds for now), once Apple grants Vela the entitlement

- **Uploads:** paste or drag images, via IRCv3 FILEHOST (soju) and a custom uploader config
- **Distribution:** a Mac App Store build, and a beta channel for testing releases early
- **iCloud sync** of networks, settings and themes
- **Per-network/per-channel themes**
- **More IRCv3:**
  - `draft/multiline`
  - `draft/read-marker` sync
  - `draft/metadata-2` avatars
  - Message edits once the spec is ratified
- **IRC scripts and plugins** inside Vela
- **DCC** file transfer and chat
- **Accessibility:** a full VoiceOver audit and a high-contrast theme set
