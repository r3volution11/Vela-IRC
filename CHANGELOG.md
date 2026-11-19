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
- **Move timestamps** to the **Left**, **Right**, **Top** or **Bottom** of messages, in Settings → Messages → Timestamps → **Position**. Each layout keeps its own position, and the defaults look as before: on the left in Classic and Compact columns, beside the name in Modern. New settings: `chat.timestampPosition.classic`, `chat.timestampPosition.grouped` and `chat.timestampPosition.columns`; palette commands **Chat: Timestamps on the Left**, **on the Right**, **at the Top** and **at the Bottom**, for the layout you're using.
  - In Modern, a group's first message shows its time in the chosen place: in the margin (Left), at the right edge (Right), beside the name (Top) or below the message (Bottom). Hover the others to see theirs, as before.
  - Times on the right line up in one column, and the hover toolbar moves aside so it doesn't cover them. A time at the bottom comes after a message's translation, above its previews and reactions.
  - Joins, parts and other events stay one line. Their time shares the messages' column with Right, and with Left in Classic and Compact columns; otherwise it follows their text.
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
- **Catch me up.** Back in a busy channel, a **Catch me up** button on the New marker summarizes what you missed with Apple Intelligence, on your Mac: an overview, the topics with who took part (click one to jump to where it starts), and where you were mentioned. Copy, regenerate or dismiss the summary from its card. New settings: `intelligence.catchUp` and `intelligence.catchUpThreshold`.
  - The button appears after 25 new messages; choose 10, 25, 50 or 100 in Settings → Apple Intelligence.
  - For any number of new messages, right-click a channel or conversation and choose **Catch Me Up**, or run **Buffer: Catch Me Up** from the command palette.
  - Covers the latest 600 messages, leaving out deleted ones, and takes from about 10 seconds to a minute. Summaries can contain mistakes.
  - The card stays open, and keeps writing, when you switch to another app or open Settings, until you dismiss it or go to another channel.
  - Needs a Mac with Apple silicon, with Apple Intelligence turned on.
- **Translate messages**, on your Mac. Right-click a message in another language (or click **…**) and choose **Translate**; the translation appears under it, with **Translate Again** and **Hide Translation** in its caption. New settings: `translation.language` and `translation.autoTranslate`.
  - **Translate Messages Automatically**, in a channel's, conversation's or network's right-click menu (and the palette, as **Buffer: Translate Messages Automatically**), translates lines in other languages as they scroll into view.
  - **Translate into** follows your Mac's language unless you choose another. Changing it redoes the translations on screen straight away, and the rest as you scroll to them.
  - A language whose download you declined is skipped, and comes back once you download it. Deleted messages are never translated.
  - Doesn't need Apple Intelligence. macOS downloads each language from Apple, once, after asking.
- **Siri, Shortcuts and Spotlight.** Ask Siri "Catch me up in Vela", "Check my Vela mentions", "Message #vela in Vela", "Open #vela in Vela" or "Set me away in Vela", with no setup. New setting: `intelligence.spotlightChannels`.
  - Shortcuts actions: Open Channel, Send Message, Join Channel, Check Mentions, Catch Me Up, Set Away, Set Back, Mark All as Read, Connect Network and Disconnect Network.
  - Your channels and conversations appear in Spotlight: names only, never messages.
  - Sending, joining, Set Away and Set Back wait about 10 seconds for a network that's still connecting.
  - On macOS 27, Siri can also send and draft messages, mark a message and everything before it as read, and knows which channel is open, so "reply to this" and "summarize this" work. Deleted messages are never read out.
- **Settings → Apple Intelligence**, a new pane for Catch me up, translation, Writing Tools, and Siri & Shortcuts, with a status box that says whether Apple Intelligence is ready.
- **Typing options** in Settings → Messages → **Typing**: check spelling, check grammar, correct spelling automatically, use text replacements, smart quotes and dashes, and Writing Tools. New settings: `input.grammarCheck`, `input.autocorrect`, `input.textReplacements`, `input.smartPunctuation` and `input.writingTools`.
  - Autocorrect, text replacements, and smart quotes and dashes follow System Settings → Keyboard until you change them in Vela; **Use macOS Setting** follows macOS again.
  - Commands, `/msg` targets, nicks, channel names, links, `:emoji:` codes and code are never corrected or underlined, and text Vela fills in (history, Tab completion, drafts) is never autocorrected.
  - **Edit → Spelling and Grammar** and **Edit → Substitutions**, and the message field's right-click menu, change the same settings, so your choice sticks in every channel. Palette commands are under **Typing:**.
  - **Writing Tools** proofreads and rewrites your message where Apple Intelligence is available. Its changes are one undo step, and Return doesn't send while it works.
- **Accent colors.** Settings → Appearance → **Accent color** switches the theme's accent to one of its own colors (from its nick and mIRC colors). Buttons, selection, links, mentions and everything else in the accent follow, text stays readable, and colors with a meaning (errors, joins and parts) never change. Each theme keeps its own choice.
  - Saved in the theme's scope in `appearance.colorCustomizations`, with `"$accentPicker"` listing what the picker wrote; your own overrides there always win.
  - Palette: **Theme: Next Accent Color** and **Theme: Reset Accent Color**.
- **Message box border.** Settings → Appearance → **Message box** sets the border's style and color. New setting: `appearance.messageBoxBorder`.
  - **Border:** **None** (just the field's background), **Subtle** (the new default: a quiet line that stays the same while you type) or **Accent when typing** (the accent-colored focus border from before).
  - **Border color:** Default, the theme's own quiet grays (its divider, window and link preview borders, placeholder and secondary text), its accent and a few of its other colors, or **Custom…** for any color. It shows whether or not you're typing, and each theme keeps its own.
  - Saved in the theme's scope in `appearance.colorCustomizations` (`input.border` and `input.focusBorder`), with `"$borderPicker"` listing what the picker wrote. A border color you choose wins over the accent color picker.
  - Palette: **Typing: Message Box Border: None**, **Subtle** and **Accent When Typing**.
- **Settings editor.** Settings → Advanced is now a VS Code-style editor for every setting, with a UI view and a JSON view.
  - **UI view:** every setting with the right control: switches, pop-up menus, number fields that know their range, chip fields with suggestions (fonts, themes, timestamp formats, channels, languages), site rules, and a group of color overrides for each theme. Settings you've changed are marked; setting one back to its default removes it from settings.json. Keys Vela doesn't know are listed with a warning, and kept.
  - **Search** by name, key, description or value, with filters (`@modified`, `@unknown`, `@category:…`, `@pane:…`), a **Modified** button and category chips. **Reset All Settings…** is in its **⋯** menu.
  - **JSON view:** edit settings.json in Vela, with suggestions for setting names and values (⌃Space, ⌥Esc or F5), problems underlined as you type (with a fix for misspelled keys), docs when you hover a setting, the default settings alongside, find and replace, and ⌘S to save. It asks before you leave with unsaved changes, and offers **Reload** or **Keep My Changes** when the file changes on disk.
  - **Find any setting from anywhere in Settings:** a search field at the top of the Settings sidebar, **Show in settings editor** on each pane, **Vela → Search Settings…** and **Settings: Search…** in the command palette.
- **settings.json keeps your comments.** Changes you make in Vela now edit only the setting that changed, leaving comments, blank lines, indentation and trailing commas as they were. Before, Vela rewrote the whole file with sorted keys and dropped your comments. (Comments inside a list are still lost when that list changes.)
- **settings.json is checked.** Unknown settings ("Did you mean “chat.fontSize”?"), values of the wrong type or not among a setting's choices, numbers out of range, settings set twice and settings from older versions are flagged in the JSON view, and a file Vela can't read says where the problem is ("Line 3, column 3: Expected a comma.").

- **Choose a Dock icon.** Settings → Appearance → **Dock icon** offers six versions of Vela's icon: **Vela** (the standard icon), **Midnight**, **Graphite**, **Sunrise**, **Paper** and **Vivid**. New setting: `appearance.appIcon`; palette commands **Appearance: Next App Icon** and **Appearance: App Icon: …**.
  - The choice shows in the Dock and the app switcher while Vela is open. Finder, Spotlight, the Apps list and notifications always show the standard icon, which follows your Icon & widget style; macOS doesn't let apps change those.
- **Open channels at the newest messages, and turn off the New line.** Settings → Messages → **Unread messages**. New settings: `chat.openAt` and `chat.showUnreadMarker`; palette commands **Chat: Open Channels at Newest Messages** and **Chat: Show New Line**.
  - **When you open a channel:** **Jump to first unread** (the default, as before) or **Show newest**, which opens every channel at the bottom with the newest messages in view, so there's no **Jump to present** button to press. Coming back to Vela shows the newest messages too. If you scroll up yourself, Vela leaves you there and **Jump to present** counts what arrives.
  - **Show the New line** is on by default. Turn it off and messages appear just as they came in, with nothing marking what's new. Unread counts in the sidebar and on tabs still work.
  - Without the New line there's no **Catch me up** button, since it sits on the line. Right-click the channel and choose **Catch Me Up**, or use the command palette; the card opens where the new messages start.

- **Credits** in Vela → About Vela, and a full [License & credits](https://velairc.app/help/license) page: the Apple frameworks, libraries, IRC specifications, theme palettes and website tools Vela builds on, and the films and photos in the screenshots, with their licenses.
- **Translucent themes.** A theme's `"vibrancy"` now works: `"sidebar"` puts the sidebar and rail (or, with tab stacks, the tab bars) on macOS's sidebar material, and `"window"` makes the whole main window translucent, with the desktop showing through, blurred.
  - The theme's colors tint the material: opaque colors at 70%, colors with their own transparency exactly as written, so `#RRGGBB00` shows the bare material.
  - With Reduce Transparency on (System Settings → Accessibility → Display), every theme is drawn opaque. The Settings and Theme Editor windows stay opaque.
  - Contrast checks measure translucent surfaces over a stand-in for the least favorable desktop, so they still mean something.
  - Try it on any theme with **Translucency** in the theme editor, or `"vibrancy"` in `appearance.colorCustomizations`. No built-in theme changes.
- **Typos in theme files are pointed out.** Settings → Appearance lists what Vela ignored in a theme file ("Parts of harbor.json were ignored"), the theme editor shows the same list, and `vela-theme-tool check` prints it. The rest of the theme still loads.
  - An unknown token: "“colors.sidebar.backgroud” isn't a theme color token, so it's ignored. Did you mean “sidebar.background”?"
  - An unknown key, with "Themes only contain colors" when it's about fonts, sizes or layout (`font`, `fontSize`, `spacing` and so on).
  - A bad `vibrancy` value is skipped with a friendly error listing `"none"`, `"sidebar"` and `"window"`, instead of stopping the theme with a raw decoding error.
  - Unknown tokens in `appearance.colorCustomizations` get the same "Did you mean" suggestion.
- **Theme previews show more of the theme.** The cards in Settings → Appearance, the theme editor's live preview and the layout and preset pictures draw tabs in the theme's `tab.*` colors, a link, the New line, a message that mentions you, the sidebar's mention badge and selected row, the collapsed rail when you use it, and translucency for themes with `vibrancy`. Select Theme (⌃⌘T) shows a tiny window in each theme instead of a strip of swatches.
- **A theme's author and description** show when you hover its card in Settings → Appearance or its name in Select Theme, and the theme editor has **Author**, **Description** and **Translucency** fields.
- **Themed scroll bars and button hover.** The conversation, member list and sidebar scroll bars use the theme's `scrollbar.thumb` and `scrollbar.thumbHover`, primary buttons such as **Save** show `button.hoverBackground` under the pointer, and `window.border` outlines Vela's windows. `chat.findMatchBackground` is reserved for a future conversation search.
- **Theme guide:** Creating themes is now a step-by-step guide: the theme editor and hand-written files, every key and token group, derived colors, nick and mIRC colors, `include`, light and dark pairs, contrast checks, testing and troubleshooting. It makes clear that themes set colors only, never layout or fonts, and that Vela draws each theme's preview card from its colors.
- **GIFs from Tenor, GIPHY and Imgur play inline.** Links to a GIF's page (`tenor.com/view/…`, `giphy.com/gifs/…`), short links (`tenor.com/RaDD.gif`, `gph.is/…`), the sites' own GIF files and Imgur `.gifv` links show the GIF itself, looping, with a **GIF** badge and a "via Tenor · tenor.com" line, instead of a link preview.
  - Vela plays each site's video copy of the GIF, silent and without controls: usually a tenth of the GIF's size or less. Stickers play from the GIF, which keeps them see-through. If the video copy can't be loaded, the GIF plays instead.
  - GIFs follow the image settings (**Full size** or **Thumbnail**, **Maximum image height**, **Largest image to load automatically**), pause out of view or with the **GIF** badge, show their first frame and a play button with Reduce Motion, and open larger when clicked.
  - Blur, site rules, the adult-site filter, **Load previews automatically** (a **Load GIF** button) and turning media off for a channel apply as they do to images. A site set to Text only gets a link preview with the GIF's title and no animation.
  - To find the GIF behind a page or short link, Vela fetches the page, like any link preview. Links that name the GIF, such as GIPHY pages and files on Tenor's and GIPHY's servers, need no page.
- **Reddit videos play inline.** `v.redd.it` links show the post's title, subreddit and author and play in place when you press ▶, in the **Player**, **Compact** and **Off** styles like other videos, with Expand, one video at a time and pausing out of view. A Reddit "GIF" (a video without sound) loops silently.
  - Vela can't tell from Reddit's public information whether a post is NSFW, so Reddit videos show no thumbnail or still frame before you press ▶ and never start by themselves. A post that Reddit sends to its age check is blocked as a page marked adult.
  - Links to Reddit posts show a link preview with the post's title, subreddit and author. Their videos don't play from the post link: Reddit only shows apps what a post holds with an account.
- **[Supported media sites](https://velairc.app/reference/media-sites)**, a new page on the website, lists every site whose links Vela plays or shows inline (YouTube, Vimeo, Twitch, Streamable, Tenor, GIPHY, Imgur, Reddit and GitHub, plus image and video files anywhere), the links it recognizes on each, what it fetches, and the domain to write a site rule for. Sample links for every site are checked against the real sites each week and before every release.
- **Previews from sites behind bot checks.** Links to sites that only show their page to a browser, such as IMDb, now get a link preview with the page's title, description and image, instead of just the site's name.
  - When a site answers with a bot check ("Just a moment…", or an empty page that needs JavaScript), Vela loads the page in a private Safari engine (WebKit) session, lets the site's own check run, reads the title, description and image address, and throws the session away. No cookies or cache are kept.
  - Images, fonts, other sites (ads and analytics included) and your local network are blocked in that session, and nothing is shown or opened in your browser. The preview's image loads like any other, under your image settings and site rules.
  - It takes a second or two, only for those sites, one page at a time, and the preview is saved. Never for blocked or adult sites, or before you click **Load preview** when previews don't load automatically.
  - Right-click such a preview to see **Preview Loaded with Safari's Engine**.
- **Load previews from sites that need a browser**, a new switch in Settings → Media → Loading (on by default), turns that off. New setting: `media.browserFallback`.
- **Choose what the Dock badge counts.** Settings → Notifications → **Dock** turns the badge on or off and counts any combination of **Mentions and highlight words**, **Private messages** and **All channel messages**. New settings: `dock.showBadge`, `dock.badgeCounts` and `dock.badgeStyle`; palette command **Notifications: Show Dock Badge**.
  - Each message counts once, so a mention isn't counted twice with All channel messages checked. Only messages, actions and notices count, never joins or parts, and muted channels and conversations never count.
  - **Style:** **99+** (the default: the number, up to 99), **Exact** or **Dot**.
  - The default, mentions and private messages, is what the badge counted before.
- **An offline mark on the Dock icon.** When a network drops and isn't back within about 10 seconds, a small amber mark with an unplugged cable appears on the bottom-left corner of the Dock icon, and it goes away once every network is back. New setting: `dock.showOffline` (on by default).
  - It's for networks that connect automatically or that you connected; it shows while Vela waits to reconnect too. Networks you disconnect or remove don't count, and neither do sleep and quitting. Bouncer networks count by their own connection.
  - It works with every Dock icon, and with Vela Dev's DEV band.
- **Bounce the Dock icon** for mentions, private messages or both while Vela is in the background: **Once** for each message, or **Until you switch to Vela**. Off by default, and muted channels and conversations never bounce it. New settings: `dock.bounce` and `dock.bounceFor`.
- The settings editor shows lists of choices, such as `dock.badgeCounts`, as chips with readable names that accept only the setting's choices, and the JSON view suggests those choices inside the list.
- **Chat logs.** Settings → Messages → **Chat logs** saves plain-text logs of your channels and private conversations: a folder for each network, with a file for each channel or conversation (`Logs/Libera.Chat/#vela.log`). Off by default. New settings: `logging.enabled`, `logging.maxFileSizeMB`, `logging.keepFiles`, `logging.includeEvents`, `logging.includeServer` and `logging.excludedBuffers`; palette commands **Chat: Save Chat Logs** and **Chat: Show Chat Logs**, and **File → Show Chat Logs**.
  - Logs hold only what was written: messages, actions and notices (yours too), with links as typed and mIRC formatting removed, plus joins, parts, quits, nick, topic and mode changes, and kicks (**Include channel events**, on by default). Never link previews, images, videos, translations or Catch me up summaries.
  - Lines look like `[2026-11-17 21:04:05] <alice> hi`, in UTF-8, with `--- Log opened …` and `--- Log closed …` where Vela starts and stops writing. A deleted message stays in the log, followed by a line saying it was deleted.
  - When a log reaches **10 MB** it's renamed with the dates it covers (`#vela 2026-11-01 – 2026-11-17.log`) and a new one starts; each channel keeps its **5** newest files, about 50 MB at most. Both are adjustable, and **Keep all** never deletes.
  - Messages a bouncer or the server replays are logged only when they're newer than what the log has, so what you missed while Vela was closed fills in without duplicates. History Vela loads from its own database is never logged again.
  - Logs go in Vela's data folder, or any folder you choose with **Choose…**; **Reveal in Finder** opens it. If the chosen folder goes missing, Vela uses its own folder and says so in Settings.
  - **Include server messages** (off by default) adds each network's connection messages, MOTD and notices from services in `server.log`.
  - Right-click a channel or network for **Don't Log This Channel** or **Don't Log on This Network**.

- **A user menu for every nick.** Right-click someone in the member list, their nick on a message (the name or avatar in Modern, `<nick>` in Classic, the nick column in Compact columns) or their nick mentioned in a message, for one menu with **Message**, **Mention**, **Whois**, **Ping**, **CTCP** (Version, Time, Client Info), **Invite to** your other channels, **Copy Nick**, **Copy Host Mask** and **Ignore** or **Unignore**. A message's own menu has it too, in a submenu named after its author.
  - **It shows only what you can do.** Rank changes, kicks, bans and quiets appear only if your rank in the channel allows them, using the network's ranks (owner, admin, op, half-op, voice). A half-op can voice and kick people without a rank; an op can manage ops and below; an owner can also make admins. A voiced user sees no moderation at all. Things that need a connection are grayed out while you're offline.
  - **Kick** and **Kick + Ban** act at once, with your default kick reason. **Kick with Reason…** and **Kick + Ban with Reason…** ask for one first.
  - **Quiet** and **Unquiet** on networks that announce how: `+q` on Libera.Chat, OFTC and other Solanum-style servers, mute bans on InspIRCd and UnrealIRCd.
  - **Ping** shows the round trip when the reply comes ("Ping reply from wren: 84 ms"), and CTCP replies show in the channel or conversation where you asked, as a readable line.
  - **Select several people** in the member list with ⌘-click and ⇧-click, then right-click one of them to change their ranks, kick, ban or quiet them all, or copy their nicks. Rank changes go out together, as many per line as the network allows.
  - See [User menu & moderation](https://velairc.app/guide/user-menu).
- **Moderation settings**, in Settings → Networks → **Moderation**: the **Ban mask** (`*!*@host`, the default, `*!user@host` or `nick!*@*`) and the default **Kick reason** (empty, for none). New settings: `moderation.banMask` and `moderation.kickReason`.
- **New slash commands:** `/kickban` (or `/kb`) bans and then kicks, with an optional reason; `/quiet` and `/unquiet`; `/ping`, `/version`, `/time` and `/clientinfo` send CTCP requests to a nick. `/version` and `/time` without a nick still ask the server.

### Changed

- **`/ban` uses your ban mask setting** and, when Vela doesn't know someone's host, asks the server for it instead of banning `nick!*@*` straight away. It also finds the host from any channel you share, takes several nicks or masks at once, and so does `/unban`. `/kick` without a reason uses your default kick reason, which is empty unless you set one.
- **Several nicks in one rank change** (`/op wren ada theo`) go out in as few lines as the network allows (its `MODES` limit), instead of one line that some servers cut short.
- **The Dock badge leaves muted channels out**, mentions included (they used to count), and counts notices in private conversations along with messages and actions.
- **The website's icon is the new V and star**, deep blue in light mode and cyan in dark mode.
- **The website links the apps it mentions**, such as Vivaldi, VS Code, irssi, WeeChat, ZNC and soju, so you can find out more about them.
- **A new app icon, "Glint":** a glass V on navy with a small star in its notch, built for macOS 26's Default, Dark, Clear and Tinted icon styles. The website's favicons, logo and social card use it too.
- **The message box no longer lights up in the accent color while you type.** Its border now stays a quiet line, so it doesn't pull attention from the chat. To get the accent border back, choose **Accent when typing** in Settings → Appearance → Message box (or set `appearance.messageBoxBorder` to `"accent"`).
- **Media settings changed, and yours are upgraded automatically** the first time the new version starts:
  - `media.presentation` and `media.loadVideoEmbeds` are replaced by `media.linkPreviewSize`, `media.videos` and `media.imageSize`. `"compact"` becomes Minimal links, Compact videos and Thumbnail images, and `media.loadVideoEmbeds: false` becomes `media.videos: "off"`.
  - `media.blockedDomains` and `media.allowedDomains` become `media.siteRules` entries: blocked domains are set to Nothing and allowed domains to Everything. **Allowed sites now also get past the adult-site filter.**
  - `media.restrictToAllowed` (**Only load previews from sites listed here**) now lets through sites set to Everything or Text only.
  - If you used the Classic IRC or Focus preset, you keep it, with its new media settings.
- **Link previews are Standard size by default**, smaller than the old full card. Choose **Large** in Settings → Media for the old look.
- **Presets set the new media settings.** Classic IRC: Minimal links, Compact videos and Thumbnail images, so videos get a one-line row with ▶ instead of a title line. Modern Chat and Tabbed: Standard, Player and Full size. Focus: Minimal, Player and Thumbnail, so videos now get a full player.
- **The Classic IRC preset shows messages just as they came in:** channels open at the newest messages, with no New line. Modern Chat, Tabbed and Focus keep opening at the first unread message, with the New line. If you applied Classic IRC before, apply it again to get this; until then, Settings → Presets shows your setup as Custom.
- In the command palette, **Toggle Inline Images** is now **Load Previews Automatically**, which is what it always did. **Use Full Previews** and **Use Compact Previews** are replaced by the size commands above.
- **The tab stack's network row** is drawn in `tab.serverBackground`, which tab stacks above or below the conversation never used before (it was on `tab.barBackground`). By default it matches the collapsed rail, a little darker than the channel row in most themes.
- **Demo mode no longer reads your Themes folder.** `--demo` uses a temporary Themes folder with only the built-in themes; `--themes-dir <folder>` copies a folder's themes into it for screenshots.
- **Debug builds are a separate app, Vela Dev**, for people building Vela from source: `scripts/run.sh --dev` (or ⌘R in Xcode) builds it with its own bundle id, sandbox, settings, history and Keychain items and a DEV Dock badge, so it runs beside your everyday Vela without touching it.
- **Demo mode cleans up after itself.** Each demo run removes its temporary folders when it quits, and the next run sweeps away any left behind (`VelaDemo-…` folders more than an hour old).
- **Settings → Advanced is now the settings editor**, and its switches have moved: **Send typing indicators** and **Check spelling while typing** to Settings → Messages → Typing, **Keep messages** to Settings → Messages → History, and **Reconnect automatically** to Settings → Networks. Their settings.json keys (`input.sendTypingIndicators`, `input.spellCheck`, `history.retentionDays`, `connection.autoReconnect`) haven't changed. **Open settings.json** and **Reveal Data Folder** are in the editor's **⋯** menu, and the **All settings** list is now its UI view.
- **Nick colors stay apart.** People talking in the same channel get different colors while the theme's palette has room; before, two nicks whose names hashed alike shared a color. Colors that merely look alike (orange beside red) are kept apart too, using the nearest clearly different color from the theme's palette, but only when a clearly different one is free. A nick keeps its color once given and usually has the same one everywhere. Palette colors too close to the message text (or under 3:1 against the background) are no longer used, so a colored nick never reads as plain text.
- **Imgur `.gifv` links play like GIFs:** inline, looping and silent, without a click. They used to show a still frame and ▶ like a video file.
- **One site rule covers all of Reddit.** A rule for `reddit.com` now also covers `redd.it` links, `v.redd.it` videos, `i.redd.it` and `preview.redd.it` images and Reddit's other media servers, and right-clicking a Reddit image offers `reddit.com`. Rules for `tenor.com` and `giphy.com` cover their media servers (and `gph.is` links) the same way.
- Link previews are fetched once more after updating, so links to GIF sites, Reddit and sites behind bot checks that were saved as link previews show the new way.

### Performance

- **Smoother scrolling,** especially in long, busy channels and on older Macs. The message list no longer redoes its work on every frame as you scroll, and messages take less work to show as they scroll into view.
- **Hover highlights wait until you stop scrolling.** Messages passing under the pointer while you scroll no longer light up or show their toolbar; the one under the pointer does as soon as you stop.
- **Scrolling stays smooth with VoiceOver or other accessibility apps running** (window managers, BetterTouchTool, Bartender, Alfred and the like). They used to make Vela work out each message's language as it scrolled into view. VoiceOver's **Translate** action is now offered on other people's messages whose language Vela hasn't checked yet; choosing it translates the message, or tells you when there's nothing to translate.
- **Resizing the sidebar or the member list is smoother.** The new width is saved once, when you let go of the divider, instead of at every step of the drag.
- **Smoother scrolling past GIFs and animated images**, especially on Intel Macs and Macs with 8 GB of memory.
  - Animated GIF, APNG and WebP images are decoded in the background at the size they're shown, instead of at full size while scrolling. Animations larger than 16 megapixels (was 40) show the "too large to show inline" chip, which opens them in your browser.
  - **GIFs from Tenor, GIPHY and Imgur start a beat after they scroll into view.** Their first frame shows straight away, and ones you scroll quickly past never start, so a fast scroll doesn't stutter. Scrolling back to a GIF you just saw reuses its player.
  - The pulsing box shown while an image loads no longer costs any work per frame. With Reduce Motion it stays still, as before.
  - Messages without links skip the link-preview checks entirely.
- **Less memory on Macs with 8 GB.** Vela keeps half as many images and rendered messages in memory there as on Macs with 16 GB or more, and when macOS runs low on memory, Vela lets go of images and messages that aren't on screen. Scrolling back to them may show them loading again.

### Fixed

- **No more empty strip above the message box.** The last message now sits just above it. The "is typing…" line only takes up room while someone is typing; the conversation slides up gently to make space, and stays put if you've scrolled up. In the Modern layout, the typing line lines up with the messages, and **Jump to present** moves above it while it shows.
- Links in messages, link preview images and preview chips show the pointing-hand cursor when you hover them. The rest of a message keeps the text cursor.
- You can select and copy the text of links in messages and server lines, as anywhere else in a message: drag from a link, double-click a word in it or triple-click the line. A click still opens the link, right away. Right-clicking a link and choosing **Copy Link** copies that link (it used to copy the message's first), and VoiceOver offers an Open action for every link in a message, not just the first.
- You can select and copy the text of link previews: the title, description and site name, by dragging, double-clicking a word or triple-clicking a line. A click anywhere on a preview opens the page, and a drag never does. Right-click selected text to copy it, or anywhere else on the preview for its menu. The same goes for a video's title and the line above it, the **via GIPHY** line under a GIF, the text of a compact video's line (where a click still plays it) and a blocked-preview chip's text.
- Your own CTCP requests and automatic replies, echoed back by servers with `echo-message`, no longer show as "doug requested CTCP VERSION".
- Right-clicking (or Control-clicking) the text of a message opens the message's menu, with **Reply**, **Translate**, **Copy Text**, **Copy Link** for the link you clicked and the rest, as anywhere else on the message. It used to show a menu of editing commands (Cut, Paste, Font…) instead. On selected text, the menu also offers **Copy**, **Look Up** and **Share…** for the selection. The same goes for the translation under a message.
- The **New** unread marker now appears while the window is in the background, and messages you've already seen no longer appear below it.
- Messages no longer appear twice after reconnecting to a ZNC bouncer. ZNC replays its buffer without message IDs, and those copies were shown and stored next to the originals; copies already stored are removed on first launch.
- Dragging a tab in the title bar no longer starts moving the window partway through.
- With **Load previews automatically** off, previews no longer appear without a click.
- Unblocking a site takes effect immediately, instead of after up to 15 minutes.
- Cached link previews older than 30 days are deleted when Vela starts, so the cache no longer grows forever.
- A playing video no longer reloads when its message is redrawn (it keeps playing) or when you scroll it away and back (it waits, paused, where you left it).
- Links to Reddit posts showed "Reddit" as their title, with no description. Reddit answers apps with a page that only says "Reddit"; Vela now gets the post's title, subreddit and author from Reddit's oEmbed service, for `redd.it` short links too.
- Streamable videos show their thumbnail. Streamable gives its thumbnails' addresses without `https:`, and Vela skipped them.
- A long, busy channel with videos and link previews could look empty when you switched to it, opened it or new messages arrived, until the next message came in. Its messages now always show, at the **New** line or the newest message.
- After you change your nick, your new nick is highlighted in the messages that mention it straight away, and the old one no longer is. Messages already on screen used to keep highlighting the old nick.

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
