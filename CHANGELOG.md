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
- **12-hour or 24-hour timestamps.** Settings → Messages → Timestamps has a **Clock** choice (System, 12-hour, 24-hour) and a **Show seconds** switch; a custom Unicode date pattern is still available under **Custom format**. New settings: `chat.clock` and `chat.timestampSeconds`.
  - System is the default and follows your Mac's 24-hour time setting, even when you change it while Vela is running. Timestamps were always 24-hour before, so on a Mac set to 12-hour time they now read like 2:47 PM.
  - `chat.timestampFormat` is now empty by default and only holds a custom pattern. A format chosen in 0.1.0 is kept as your custom format.
- **Videos you can expand.** Settings → Media → **Videos** chooses how YouTube, Vimeo, Twitch and Streamable links and video files show: **Player** (the default: a large thumbnail whose player loads in place when you press ▶), **Compact** (one line; ▶ opens the player underneath) or **Off** (a link preview). New setting: `media.videos`.
  - **Expand** a playing video to fill the window. It keeps playing; Esc, a click outside it or **Return** puts it back. The player's own full-screen button still works.
  - One video plays at a time. Videos pause when you scroll them out of view or switch conversations, and stay where they were; press play to resume.
  - Players are bigger: up to 560 points wide (was 480).
  - Command palette: **Media: Play Videos Inline**, **Compact Videos** and **Videos as Links**.
- **Link previews in three sizes:** **Minimal** (one line), **Standard** (the new default: the title and two lines of description beside a thumbnail) and **Large** (the full card). Images get their own **Full size** or **Thumbnail** choice. New settings: `media.linkPreviewSize` and `media.imageSize`; palette commands **Media: Minimal / Standard / Large Link Previews**, **Full-Size Images** and **Image Thumbnails**.
- **Hide previews of adult sites**, on by default. Links stay clickable, but Vela fetches nothing from the site. New setting: `media.filterAdultSites`; palette command **Media: Hide Adult Site Previews**.
  - Sites are checked on your Mac, never online, against a list of about 42,000 domains bundled with Vela (from [Sinfonietta/hostfiles](https://github.com/Sinfonietta/hostfiles), MIT license) and refreshed with each release, plus the `.xxx`, `.porn`, `.adult` and `.sex` domains.
  - Pages that label themselves adult (the RTA label or a `rating` meta tag) are caught too, as are links that redirect to a listed site.
- **Blocked previews explain themselves.** A quiet chip says why ("Adult site · preview blocked", "Blocked site", "Not on your allowed sites") and offers **Show once** and **Always allow**, or **Unblock** for a site you blocked.
- **Site rules.** Settings → Media → **Site rules** sets a site to **Everything**, **Text only** (titles and descriptions, no images or players) or **Nothing** (Vela never contacts it). New setting: `media.siteRules`.
  - The most specific rule wins, so a rule for `i.example.com` beats one for `example.com`. A video site's rule covers its short links and thumbnails: a `youtube.com` rule covers `youtu.be`.
  - Right-click any preview for **Block Previews from ‹site›** or **Previews from ‹site›** (Default, Everything, Text Only, Nothing).
- **Blur images until clicked**, everywhere (Settings → Media → Restrictions) or per channel or network (right-click it and choose **Blur Images**). Images, link preview images, video thumbnails and video stills show "Click to show"; right-click revealed media to **Blur Again**. New settings: `media.blurImages` and `media.blurredBuffers`; palette commands **Media: Blur Images Until Clicked** and **Buffer: Blur Images**.

### Changed

- **Media settings changed, and yours are upgraded automatically** the first time the new version starts:
  - `media.presentation` and `media.loadVideoEmbeds` are replaced by `media.linkPreviewSize`, `media.videos` and `media.imageSize`. `"compact"` becomes Minimal links, Compact videos and Thumbnail images, and `media.loadVideoEmbeds: false` becomes `media.videos: "off"`.
  - `media.blockedDomains` and `media.allowedDomains` become `media.siteRules` entries: blocked domains are set to Nothing and allowed domains to Everything. **Allowed sites now also get past the adult-site filter.**
  - `media.restrictToAllowed` (**Only load previews from sites listed here**) now lets through sites set to Everything or Text only.
  - If you used the Classic IRC or Focus preset, you keep it, with its new media settings.
- **Link previews are Standard size by default**, smaller than the old full card. Choose **Large** in Settings → Media for the old look.
- **Presets set the new media settings.** Classic IRC: Minimal links, Compact videos and Thumbnail images, so videos get a one-line row with ▶ instead of a title line. Modern Chat and Tabbed: Standard, Player and Full size. Focus: Minimal, Player and Thumbnail, so videos now get a full player.
- In the command palette, **Toggle Inline Images** is now **Load Previews Automatically**, which is what it always did. **Use Full Previews** and **Use Compact Previews** are replaced by the size commands above.
- **Nick colors stay apart.** People talking in the same channel get different colors while the theme's palette has room; before, two nicks whose names hashed alike shared a color. Colors that merely look alike (orange beside red) are kept apart too, using the nearest clearly different color from the theme's palette, but only when a clearly different one is free. A nick keeps its color once given and usually has the same one everywhere. Palette colors too close to the message text (or under 3:1 against the background) are no longer used, so a colored nick never reads as plain text.

### Fixed

- The **New** unread marker now appears while the window is in the background, and messages you've already seen no longer appear below it.
- Messages no longer appear twice after reconnecting to a ZNC bouncer. ZNC replays its buffer without message IDs, and those copies were shown and stored next to the originals; copies already stored are removed on first launch.
- Dragging a tab in the title bar no longer starts moving the window partway through.
- With **Load previews automatically** off, previews no longer appear without a click.
- Unblocking a site takes effect immediately, instead of after up to 15 minutes.
- Cached link previews older than 30 days are deleted when Vela starts, so the cache no longer grows forever.
- A playing video no longer reloads when its message is redrawn (it keeps playing) or when you scroll it away and back (it waits, paused, where you left it).

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
