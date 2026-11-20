# Changelog

All notable changes to Vela are listed here. Vela follows [Semantic Versioning](https://semver.org/): breaking changes to settings or theme files come only in major versions, and they're always called out here.

## Unreleased

### Layouts and navigation

- **Leave or remove a channel.** The menus have **Leave Channel** (or **Join Channel**) and **Remove Channel…**, and the command palette has **Leave**, **Join** and **Remove** for the selected channel.
  - **Leave Channel** parts the channel and keeps it in the list, dimmed, so **Join Channel** brings it back. It also comes off the network's auto-join list, so it stays left when you reconnect; joining it again puts it back where it was, with its key.
  - **Remove Channel…** parts the channel and takes it out of the list and off the auto-join list, so it doesn't come back when you reconnect. Its messages stay in your history.
  - A tab's **×** (or a middle-click) leaves and removes a channel in one step, like **Remove Channel…**. Its tooltip and VoiceOver action say what it does.
  - Vela asks before leaving or removing a channel. **Don't ask again** in the question, or the switches in **Settings → Networks → Channels** (`channels.confirmLeave` and `channels.confirmRemove`), turn that off. `/part` leaves and `/close` removes without asking.
- **Leave a channel and keep it on your bouncer.** Through ZNC or soju, **Leave Channel**, a tab's **×** and a middle-click detach the channel: the bouncer stays in it and keeps its history, and Vela shows it dimmed, even after you quit and reopen Vela. **Join Channel** reattaches it and catches up on what you missed. If the bouncer doesn't confirm, the network's console says so, and Vela never parts the channel instead.
  - **Hide Channel** (or **×** on a detached channel) takes a detached channel out of the list and leaves it on the bouncer. Get it back from the network's settings (**Show** or **Join** under **Hidden channels**), with **Show #channel (Network)** in the command palette, or with ⌘Z and ⇧⌘T.
  - **Remove Channel…**, `/close` and `/part` really part, so the bouncer forgets the channel. **Closing a channel removes it from the bouncer** in **Settings → Networks → Channels** (`channels.bouncerCloseRemoves`) makes a tab's **×** and middle-click do that too.
  - A message the bouncer passes on from a detached channel counts as unread, or as a mention, without bringing the channel back; one from a hidden channel is saved for when you show it.
  - Detached or removed a channel while disconnected from the bouncer? Vela tells the bouncer after your next connection, even if you quit Vela in between.
- **Reopen what you closed.** **File → Reopen Closed Channel** (⇧⌘T) brings back the channel you removed or hid, or the conversation you closed, last, and pressing it again goes further back. **File → Recently Closed** lists the last 20, and the command palette can reopen each one. A reopened channel returns to its old place, muted or not, with the **New** line where you left off, and goes back on the auto-join list with its key. The list lasts until you quit.
- **Undo it.** Edit → Undo (⌘Z) right after leaving, removing, hiding or closing puts things back, and Redo (⇧⌘Z) does it again. Undoing a leave joins the channel again (reattaching it on a bouncer) and puts it back on the auto-join list. It shares the message box's undo, so ⌘Z after typing undoes the typing first.
- **`/close` in the sidebar** now moves to the next channel, like closing a tab does, instead of leaving an empty view.
- **A channel you close stays closed** even when messages are still arriving as you leave it.
- **⌘1–⌘9 now always match the tabs' order** after joining, closing or reordering.

### Chat and messages

- **Nicks are colored in messages.** When a message mentions someone in the channel, or the person you're talking with, their nick has the same color it has everywhere else, and right-clicking it opens their menu (now in a conversation too). Only whole nicks are colored, never inside links or channel names or over colors the sender chose, and a mention of you keeps its own highlight. It's on by default with **Colored nicknames**; turn it off with **Color nicks in messages** in **Settings → Messages** (`chat.colorNicksInText`) or **Toggle Nick Colors in Messages** in the command palette.
- **Nobody else has your nick's color.** Many themes have your nick's color in their nick palette too, so someone else could be shown in it, or in a color right beside it, and look like you. Those colors are now kept for you. Your nick also has its own color in the member list and on your avatar, as on your messages, and in a crowded channel someone new shares the color of a person who isn't talking rather than look like someone who is.
- **Messages a bouncer replays now count as unread.** What ZNC, soju or a server with chat history replays when Vela connects counts in unread and mention badges, the New line and the Dock badge once it's newer than where you stopped reading. Replayed messages never pop up notifications or play sounds, and a channel Vela has never had open starts counting from when it first joins.

### Siri, Shortcuts and Apple Intelligence

- **Name the network to Siri.** "Open #vela on Libera.Chat in Vela", or just "on Libera", picks the channel on that network when you're in channels with the same name on more than one. It works in every phrase that names a channel.
- **Settings → Apple Intelligence** shows a fixed example phrase, using Vela's own channel, instead of the name of one of your channels.
- **Apple Intelligence turns on as soon as it's ready.** When macOS finishes downloading the model while Vela is in front, Catch me up and Settings → Apple Intelligence update at once, instead of waiting until you switch away from Vela and back.
- **Catch Me Up and Check Mentions are right after Siri opens Vela.** They count what's unread from where you last read each channel, so they no longer say "You're all caught up" or "You have no new mentions" before Vela has loaded its history.
- **Siri's Catch Me Up never cuts a catch-up short.** A stretch your Mac summarizes in one quick pass (about 100 messages) Siri reads out itself. A longer one opens Vela to the channel, with the Catch me up card summarizing all of it, after Siri says so ("That's 412 messages in #vela. Opening Vela to catch you up."). Siri waits about 15 seconds at most; a summary that isn't ready by then carries on in the card. A summary already made in the card is used whole.
- **Private Cloud Compute for long catch-ups, off by default.** On macOS 27 or later, **Use Private Cloud Compute for long catch-ups** in Settings → Apple Intelligence (`intelligence.privateCloudCompute`) sends a catch-up too long for one pass on your Mac to Apple's Private Cloud Compute: encrypted, not stored and not readable by Apple. Its larger model reads a few hundred messages in one go, and Siri can answer those itself. Short catch-ups, translation and everything else stay on your Mac. When Private Cloud Compute isn't available, or its daily limit is reached, the summary is made on your Mac instead, and the card's footer says where each summary was made.
- **Summaries are written one at a time,** in the order you ask for them, so catching up in several channels doesn't weigh down a Mac with 8 GB of memory. A card waiting its turn says "Waiting… 1 summary ahead", and dismissing it takes it out of line. A summary Siri is waiting for goes next.
- **Show channels in Spotlight** only takes your channels out of Spotlight's results now. On macOS 27, Siri still finds channels and nicks by name when it's off.
- **Spotlight keeps up after a hiccup.** A Spotlight update that fails is tried again, a little later each time, and updates no longer run over each other.
- **Settings no longer promise "summarize this" on macOS 27.** macOS gives apps no public way to let Siri summarize what's on screen; ask it to "Catch me up on #vela in Vela" instead.
- **Siri can run an action the moment it opens Vela.** Vela sets up what its actions need as it starts, rather than when it sets up its windows.
- **Catch me up works with bouncers.** Messages your bouncer replays count as new, so the button, the card and Siri cover what you missed while Vela was closed.
- **Long catch-ups show their progress:** "Reading… 3 of 8", then "Writing the summary…". Every response is capped, so a runaway one can't keep Apple Intelligence busy for minutes.
- **Words never disappear from the card.** When a pass has to be redone, what was written stays, dimmed, with "Finishing…", until the new words arrive.
- **Going to another channel no longer cancels a summary.** It keeps going, and the card is there when you come back. After you've read the channel, **Catch Me Up** in the right-click menu, the command palette or Siri shows that summary again until you quit.
- **A part Apple Intelligence won't summarize is skipped,** and the card says how many messages it left out, instead of the whole summary failing.
- **Catch Me Up in the right-click menu and the command palette is always there** while Catch me up is on. With nothing new it says so on a card, and the palette notes "nothing new" or "earlier summary".
- **A clear message when the conversation's language isn't supported,** without the System Settings button meant for your Mac's language.
- **Offer Catch me up in busy channels turns it off everywhere:** the button, the right-click menu, the command palette and open cards, and Siri says it's turned off.

## 1.0.0 - 2026-11-18

The first public release of Vela, a native, deeply themable IRC client for macOS with inline media, IRCv3 and bouncer support, and on-device Apple Intelligence. It needs macOS 26 or later and runs on Apple silicon and Intel Macs.

### Themes and appearance

- **Every surface is themable.** The title bar, sidebar, tabs, chat, message box, member list, link previews, settings and even the scroll bars draw from named color tokens, the way VS Code themes work.
- **21 built-in themes,** with Palenight and Lighter as the default dark and light pair. **Select Theme** (⌃⌘T) previews each one live as you move through the list.
- **Make your own.** The theme editor has a live preview and contrast checks, VS Code themes import from a `.json` or `.vsix` file, theme files reload as you edit them, and `appearance.colorCustomizations` in settings.json overrides any color. The [theme guide](https://velairc.app/customize/creating-themes) walks through it all.
  - Typos in a theme file are pointed out ("Did you mean “sidebar.background”?") in Settings → Appearance and the theme editor, and the rest of the theme still loads.
- **Accent colors.** Settings → Appearance → **Accent color** switches a theme's accent to one of its own colors. Text stays readable, colors with a meaning (errors, joins and parts) never change, and each theme keeps its own choice.
- **Translucent themes.** A theme's `"vibrancy"` puts the sidebar, or the whole window, on macOS's translucent material, tinted with the theme's colors. Try it on any theme with **Translucency** in the theme editor.
- **Message box border:** **None**, **Subtle** (the default) or **Accent when typing**, in one of the theme's colors or any color you choose.

### Layouts and navigation

- **Sidebar or tab stacks.** A compact sidebar that collapses to a thin rail, or Vivaldi-style two-level tab stacks at the top, in the title bar or above the message box, with corners from square to pill. Hover a tab's **#** to close it, or middle-click the tab.
- **Three message layouts:** Classic, Modern grouped and Compact columns. Joins and parts can be shown, collapsed into one line or hidden.
- **One-click presets.** Classic IRC, Modern Chat, Tabbed and Focus set up navigation, layout, density and media in one step, and never change your theme.
- **Drag to reorder** networks and channels in the sidebar, the rail, the tab bars or Settings → Networks. The order is the same everywhere, and reordering channels updates the network's auto-join list. New channels go at the end; **Sort Channels A–Z** puts them in order.
- **Command palette.** ⇧⌘P runs any command, and ⌘P or ⌘K jumps to any channel or conversation.

### Chat and messages

- **History on your Mac,** stored in SQLite with full-text indexing. Day dividers mark each day, and a **New** line marks where you left off.
- **Open channels where you like:** at the first unread message (the default) or at the newest messages. The New line can be turned off; unread counts in the sidebar and on tabs still work.
- **Timestamps your way:** your Mac's 12- or 24-hour setting or your own choice, with seconds or a custom pattern, on the left, right, top or bottom of messages in each layout.
- **Nick colors that stay apart.** People talking in the same channel get clearly different colors while the theme's palette has room, and colors too close to the message text are never used.
- **Right-click any message** for **Reply**, **Translate**, **Copy Text** and **Copy Link** (for the link you clicked), plus **Copy**, **Look Up** and **Share…** on selected text. Text in links and link previews selects and copies like any other text, and a click on a link still opens it.
- **Typing options** in Settings → Messages → Typing: spelling, grammar, autocorrect, text replacements, and smart quotes and dashes. Commands, nicks, channel names, links and code are never corrected.
- **Chat logs,** off by default: a plain-text file for each channel and conversation (`Logs/Libera.Chat/#vela.log`), with lines like `[2026-11-17 21:04:05] <alice> hi`.
  - Logs hold messages, actions and notices, plus channel events unless you turn them off. Never previews, translations or summaries. Choose any folder, leave out a channel or network, or add server messages in `server.log`.
  - A log starts a new file at 10 MB, and each channel keeps its 5 newest; both are adjustable. History a bouncer replays fills in what you missed, without duplicates.

### Users and moderation

- **A user menu for every nick.** Right-click someone in the member list, or their nick on a message or mentioned in one, for **Message**, **Mention**, **Whois**, **Ping**, **CTCP**, **Invite to**, **Copy Nick**, **Copy Host Mask** and **Ignore**. See [User menu & moderation](https://velairc.app/guide/user-menu).
  - Rank changes, kicks, bans and quiets appear only when your rank in the channel allows them, using the network's own ranks. Quiets use `+q` on Libera.Chat, OFTC and other Solanum-style servers, and mute bans on InspIRCd and UnrealIRCd.
  - Select several people in the member list (⌘-click or ⇧-click) to change their ranks, kick, ban or quiet them all at once.
- **Moderation settings** in Settings → Networks → Moderation: the ban mask (`*!*@host` by default) and a default kick reason. `/ban` uses the mask, and asks the server for a host Vela doesn't know.
- **Slash commands** for moderation and CTCP, including `/kickban` (or `/kb`), `/quiet`, `/unquiet`, `/ping`, `/version`, `/time` and `/clientinfo`. `/ban`, `/unban` and rank changes such as `/op wren ada theo` take several nicks, sent in as few lines as the network allows.

### Inline media

- **Images, animated GIFs and link previews** in the conversation. Previews come in **Minimal**, **Standard** (the default) and **Large**, and images at full size or as thumbnails.
- **Video players** for YouTube, Vimeo, Twitch, Streamable and Reddit (`v.redd.it`) links and video files. A player loads only when you press ▶ and can expand to fill the window; one video plays at a time, and it pauses when you scroll away. Or choose **Compact** (one line) or **Off**.
- **GIFs from Tenor, GIPHY and Imgur** play inline, even from a link to the GIF's page, a short link or a `.gifv`, using the site's much smaller video copy where there is one. [Supported media sites](https://velairc.app/reference/media-sites) lists every site and link Vela recognizes.
- **Previews from sites behind bot checks,** such as IMDb. Vela lets the site's check run in a private WebKit session that blocks images, other sites and your local network, then throws the session away. **Load previews from sites that need a browser** turns this off.
- **You decide what loads:**
  - **Site rules** set a site to **Everything**, **Text only** or **Nothing**, in Settings → Media or by right-clicking a preview. A rule for `reddit.com` covers all of Reddit's links and media servers.
  - **Adult sites' previews are hidden** by default. Links are checked on your Mac against a bundled list of about 42,000 domains, and pages that label themselves adult are caught too.
  - **Blur images until clicked,** everywhere or for a channel or network. You can also turn media off for a network or channel, load previews only when clicked, and set size limits.
  - A blocked preview says why, with **Show once** and **Always allow**.

### Networks, bouncers and connections

- **Secure connections:** TLS with certificate validation (and an opt-in to allow invalid certificates, for self-signed bouncers), SASL PLAIN and EXTERNAL, and client certificates.
- **IRCv3:** `server-time`, `echo-message`, `batch`, `chathistory`, `message-tags`, `away-notify`, `account-notify`, `extended-join`, reactions, replies, typing indicators and message deletion.
- **Stays connected,** with STS upgrades and automatic reconnects with backoff, after sleep and wake and network changes too.
- **Bouncers:** ZNC (server password login, `self-message`, `playback`, `server-time`) and soju (your bouncer's networks appear automatically, with history from `chathistory`).

### The Dock

- **Choose what the badge counts:** mentions and highlight words, private messages, all channel messages or any mix, shown as a number up to 99+, an exact count or a dot. Muted channels never count.
- **An offline mark** on the Dock icon when a network drops and isn't back within about 10 seconds.
- **Bounce the Dock icon** for mentions or private messages while Vela is in the background, once or until you switch to Vela. Off by default.
- **Six Dock icons** in Settings → Appearance: the standard glass V and star, made for macOS 26's Default, Dark, Clear and Tinted icon styles, plus Midnight, Graphite, Sunrise, Paper and Vivid.

### Settings

- **settings.json, VS Code style.** Every setting is a documented key. Edits from any editor apply right away, and changes made in Vela touch only the setting that changed, keeping your comments and formatting.
- **A settings editor** in Settings → Advanced, with a UI view and a JSON view. The search field at the top of Settings finds any setting.
  - **UI view:** every setting with the right control, search with filters such as `@modified`, and color overrides for each theme.
  - **JSON view:** suggestions for settings and values, problems underlined as you type, docs on hover, the defaults alongside, and ⌘S to save.
- **Mistakes are caught:** unknown settings ("Did you mean “chat.fontSize”?"), wrong types and out-of-range values are flagged, and a file Vela can't read says where the problem is.

### Siri, Shortcuts and Apple Intelligence

- **Catch me up.** Back in a busy channel, a button on the New line summarizes what you missed with Apple Intelligence, on your Mac: an overview, the topics and who took part, and where you were mentioned.
- **Translate messages** on your Mac, one at a time or automatically for a channel, conversation or network. The translation appears under the original. No Apple Intelligence needed.
- **Writing Tools** proofreads and rewrites your message where Apple Intelligence is available.
- **Siri and Shortcuts,** with no setup: ask Siri to "Catch me up in Vela", "Check my Vela mentions", "Message #vela in Vela" or "Set me away in Vela". Shortcuts actions open, join and message channels, set you away or back, and connect networks. Your channels appear in Spotlight, names only.
  - On macOS 27, Siri can also send and draft messages, and knows which channel is open, so "reply to this" works.
- **Settings → Apple Intelligence** brings these together, and says whether Apple Intelligence is ready.

### Privacy

- **No telemetry.** Vela is sandboxed and keeps passwords in the macOS Keychain.
- **Previews are never fetched from your local network,** and you choose which sites Vela contacts at all.
- **Made on your Mac:** Catch me up summaries, translations and the adult-site check. Spotlight gets channel names, never messages.

### Accessibility

- **VoiceOver** offers actions to move networks and channels, open each link in a message and translate a message, and scrolling stays smooth while VoiceOver or other accessibility apps run.
- **Reduce Motion and Reduce Transparency** are respected. With Reduce Motion, GIFs show their first frame and a play button and loading placeholders keep still; with Reduce Transparency, every theme is drawn opaque.
- **Readable colors:** accent colors keep text readable, nick colors under 3:1 against the background are never used, and the theme editor checks contrast.

### Performance

- **Smooth scrolling,** even in long, busy channels and on older Macs. Hover highlights and the message toolbar wait until you stop scrolling.
- **Light on GIFs:** animated images are decoded in the background at the size they're shown, and Tenor, GIPHY and Imgur GIFs start a beat after they scroll into view, so a fast scroll doesn't stutter.
- **Easy on 8 GB Macs:** Vela keeps half as many images and messages in memory there, and lets go of off-screen ones when macOS runs low on memory.

### Known limitations

- Uploading images, searching messages, iCloud sync and automatic updates are planned. See the [roadmap](ROADMAP.md).
- Reactions, replies and typing indicators need a server or bouncer that passes IRCv3 message tags. Older ZNC versions don't, so Vela hides those features there.
- Catch me up and Writing Tools need a Mac with Apple silicon, with Apple Intelligence turned on.
- Links to Reddit posts show a link preview, not the video; `v.redd.it` links play. Reddit videos show no thumbnail until you press ▶, since Vela can't tell whether a post is NSFW.
- Your Dock icon choice shows only in the Dock and the app switcher. Finder, Spotlight and notifications show the standard icon.
- The menu bar, context menus and system alerts follow macOS's light or dark appearance rather than theme colors.
