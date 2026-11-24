# Changelog

All notable changes to Vela are listed here. Vela follows [Semantic Versioning](https://semver.org/): breaking changes to settings or theme files come only in major versions, and they're always called out here.

## Unreleased

### Presets

- **Presets are now three choices that combine freely.** **Settings → Presets** has a row of picture cards for the **window layout** (**Sidebar**, **Tabs on Top**, **Tabs in Title Bar** or **Focus**), a row for the **message style** (**Modern**, **Classic IRC** or **Columns**) and a **density** control (**Compact**, **Standard** or **Comfortable**), with a live preview of your messages under them. Pick any layout with any style and any density. Each row changes only its own settings, in one change, so choosing a layout never touches your message style, font, media or anything else, and presets still never change your theme. The cards are drawn in your theme with your own settings, so each shows what you'd get. See [Presets](https://velairc.app/guide/presets).
  - **Window layout** sets `navigation.style` and `tabs.placement`; **message style** sets `chat.layout` and `chat.monospace` (Classic IRC is monospaced); **density** sets `chat.lineSpacing` and `chat.messageSpacing`: 1 and 2 points, 4 and 12 (Vela's defaults) or 6 and 18. Density never changes the font size, so a size you chose yourself stays.
  - **Customized.** A row whose settings you've changed by hand (tabs at the bottom, say, or spacing of your own) has no card selected and says **Customized**, with what's different and a link to where to fine-tune it. Picking a card resets just that row.
  - A choice that matches Vela's default is removed from settings.json rather than written, so it keeps following the default.
  - The cards work from the keyboard: Tab goes from row to row, ← and → move between the cards in a row, and Space or Return picks one. VoiceOver reads each card as a button, says which is selected and what you picked, and says when a row is customized. Increase Contrast draws stronger borders, and Reduce Motion turns off the cards' animations.
- **Focus: no sidebar and no tabs.** The new **Focus** layout (`navigation.style: "focus"`) gives the conversation the whole window, with the channel's name and topic above it. Switch channels with **Go to Conversation…** (⌘P), ⌘1–⌘9 or the **Go** menu. **Settings → Layout** offers it too. Vela 1.4 and earlier read it as the sidebar.
- **The View menu and the command palette follow.** **View → Layout**, **View → Message Style** and **View → Density** replace **View → Navigation**, **View → Message Layout** and **View → Presets**, and the palette has **Layout: Tabs on Top**, **Message Style: Columns**, **Density: Compact** and the rest, checked while your settings match. **Tabs: Move to Bottom** and **Always Show Server Row** stay, under **View → Layout**. The top of **Settings → Appearance** has the three choices as menus.
- **Nothing changes when you update.** Your settings stay exactly as they were, and each row shows the choice they match: the old **Classic IRC** preset is Sidebar and Classic IRC; **Modern Chat** is Sidebar, Modern and Standard; **Tabbed** is Tabs on Top and Modern; and the old **Focus** is Tabs in Title Bar and Columns. Their own spacing (Classic's tighter 1 and 2 points, Tabbed's and Focus's) shows as a customized density; **Compact** is 2 and 4 points, so Modern's message groups stay apart. What else the old presets set (font size, media sizes, unread settings) stays as it was.
- The message preview in **Settings → Messages** now spaces messages as the conversation does: the message spacing between messages in every layout, and none between the lines of one person's run.

### AI models

- **Use your own AI models for Catch me up and Recap.** Add **OpenAI**, **Anthropic (Claude)** or **Google Gemini** with your own API key, or a server that speaks OpenAI's API, such as **Ollama** or **LM Studio** on your Mac or your network, in **Settings → Intelligence → Models**. Apple Intelligence stays the default (**Automatic (Apple)**) until you choose another model. See [Your own AI models](https://velairc.app/guide/ai-models).
  - **Choose the default model,** or a model for Catch me up or Recap only. Menus list Apple's model first, then each provider's, with Vela's recommended pick first: Claude Opus 5.5, GPT-6.2 Sol and Gemini 3.8 Flash. **Test** fetches a provider's models with your key, and lists are kept between launches.
  - **See which model wrote it, and try another.** A Catch me up card and a Recap say which model wrote them, and **Change** writes them again with another one.
  - **Works on any Mac.** With a model of your own, Catch me up and Recap's summaries work without Apple Intelligence, on an Intel Mac too.
  - **Fewer passes.** Hosted models read far more at once than the model on your Mac, so a long catch-up or Recap usually takes one pass.
- **You decide what's sent.** The first time a provider would be used, Vela asks, and says exactly what goes: the text and nicks of the messages you ask about and your nick, never channel, network or server names or your account, under the provider's data policy, billed to your key. Take it back any time in **Settings → Intelligence**. Keys are kept in your Keychain, never in settings.json.
- **Clear errors, and never a silent switch.** Offline, a key that's turned down, an account out of credit or a refusal each says so, with **Try with Apple Intelligence** where it can run. Vela never falls back to another provider on its own.
- **In the command palette:** **AI: Set Default Model…**, **AI: Manage Providers…**, **Buffer: Catch Me Up With…** and **Buffer: Recap With…**.
- **Settings → Apple Intelligence is now Settings → Intelligence.** Translation stays on your Mac with Apple's Translation framework, and Writing Tools is still macOS's own.
- **New settings:** [`intelligence.model`](https://velairc.app/reference/settings#intelligence.model), [`intelligence.catchUpModel`](https://velairc.app/reference/settings#intelligence.catchUpModel), [`intelligence.recapModel`](https://velairc.app/reference/settings#intelligence.recapModel) and [`intelligence.providers`](https://velairc.app/reference/settings#intelligence.providers).

### Automation and Spotlight

- **`vela://` links.** Open a channel or a private conversation, Catch me up, a Recap (filled in), message search, or a message box with text in it, from a web page, your notes, Alfred, Raycast or the terminal: `vela://open?network=Libera.Chat&channel=%23vela`, `vela://draft?channel=%23vela&text=…`, `vela://recap?span=today` and more. Links only ever show things: they never send a message, never join a channel without asking (`vela://join` opens **Join Channel**, filled in), never run a command (text that starts with `/` goes in as `//…`), never replace what you were typing and never hand anything back. A link Vela can't follow just brings it forward with a short note saying why. Vela Dev answers `vela-dev://` instead. See [Links & AppleScript](https://velairc.app/guide/automation#links).
- **An AppleScript dictionary**, for Alfred, Raycast, Shortcuts' **Run AppleScript** and your own scripts: your networks and conversations with their unread and mention counts, `unread conversations`, `current conversation` and `scripting version` (which goes up only when a change could break scripts), and the commands `show`, `send message`, `draft message`, `join`, `catch up`, `open recap`, `mark read`, `mark all read`, `search`, `set away` and `set back`. macOS asks you once for each app before it can script Vela. `send message` sends plain text only (a `/` is never a command), only to channels you're in and conversations you have open, splits long text as the message box does, and needs `allowing multiple lines true` for more than 3 lines. See [AppleScript](https://velairc.app/guide/automation#applescript).
- **Message search.** **Search Messages…** in the command palette finds messages in your saved history and in what your channels have open, newest first; choose one to see it in its conversation. Links, AppleScript and Spotlight open it too.
- **Search your messages in Spotlight**, if you want to. **Search messages in Spotlight** in **Settings → Integrations** (`intelligence.spotlightMessages`) is off by default and needs **Save message history**. On, Spotlight gets the newest 5,000 saved messages of each network, then each new one as it's saved, in the background; choosing a result opens the conversation at that message. Turning it off, turning off saved history or deleting it takes them out of Spotlight, and so does removing a channel, a conversation or a network. See [Messages in Spotlight](https://velairc.app/guide/siri-shortcuts#messages-in-spotlight).
- **People in Spotlight.** The people you talk to in private show up in Spotlight as people (with **Show channels in Spotlight**), including conversations you closed since Vela started; choosing one opens or reopens it. There's a new **Open Private Conversation** action too.
- **Search in Vela, and Vela's actions in Spotlight.** Type in Spotlight and choose **Search in Vela** to open message search, or run **Search Messages** and Vela's other actions there with what they ask for. Actions find better with everyday words ("DM", "afk", "find"), and Siri knows "Search messages in Vela" and "Join a channel in Vela".

### Integrations, Alfred and Raycast

- **Settings → Integrations.** A new pane lists what works with Vela: Alfred, Raycast, Shortcuts and Siri, Spotlight, and AppleScript and `vela://` links. Each shows what it does, whether it's installed on your Mac, buttons to set it up and a link to its guide. Siri & Shortcuts and the Spotlight settings moved here from **Settings → Intelligence**, which links to it. It also lists every action Vela adds to Shortcuts, and has **Open Dictionary** for Script Editor and a few links to try. **Settings: Integrations** in the command palette opens it. See [Integrations](https://velairc.app/guide/integrations).
- **An Alfred workflow.** Type `vela` in Alfred for your channels and private conversations: mentions first, then what's unread, then the rest, each with its network and how many mentions and unread messages it has. Type to filter by name or network, or `vela unread` for what's waiting. ↩ shows one in Vela, ⌘↩ opens Catch me up, ⌥↩ a Recap, ⇧↩ marks it read and ⌘C copies its `vela://` link. ⌃↩ writes a message: type it, then ↩ sends it, or ⌘↩ puts it in the message box instead. `vela catch`, `vela recap` and `vela mark` run **Catch Me Up**, **Open Recap** and **Mark All Read**, and `vsearch` or the **Search in Vela** Universal Action searches your messages. It comes with Vela: **Install Workflow…** in **Settings → Integrations** (or **Integrations: Install Alfred Workflow…** in the command palette) opens it in Alfred, which asks before importing it (Alfred 5 or later, with the Powerpack). Its own releases are on [GitHub](https://github.com/r3volution11/vela-alfred-workflow). See [Alfred & Raycast](https://velairc.app/guide/alfred-and-raycast#alfred).
- **A Raycast extension**, coming to the Raycast Store, and on [GitHub](https://github.com/r3volution11/vela-raycast-extension) until then: **Search Conversations**, in Mentions, Unread and All sections, with actions to open, catch up, recap, write a message, draft it in Vela, mark read and copy a link; **Send Message**; **Catch Me Up**; and, if you turn it on, **Unread Conversations** in the menu bar with your mentions. See [Alfred & Raycast](https://velairc.app/guide/alfred-and-raycast#raycast).
- **Neither opens Vela just to list things,** and both say what's wrong in words: Vela isn't running (with a way to open it), isn't allowed to be controlled (with a way to the setting), isn't connected, you're not in that channel, or Catch me up is turned off. Either can talk to Vela Dev instead, for working on Vela. Neither has any tracking.

## 1.1.0 - 2026-11-21

Vela 1.1 brings an updater, the whole window from the keyboard, and a choice about saving your chat history. The highlights:

- **Vela updates itself.** It checks once a day and offers a new version when you open Vela, never in the middle of a conversation. Vela 1.0 has no updater, so download this version once from [velairc.app](https://velairc.app/guide/install#from-1-0); after that, updates come to you.
- **The whole window works from the keyboard:** the sidebar or the tabs, the messages and the member list, with ⌥⌘1 to ⌥⌘4 and F6 to move between them. ⌘W now closes the tab, as in a browser, and ⇧⌘W the window.
- **Leave a channel, or remove it.** **Leave Channel** keeps it in the list, ready to join again, and **Remove Channel…** takes it out. Through ZNC or soju, leaving detaches the channel, so the bouncer stays in it and keeps its history. ⇧⌘T and ⌘Z bring back what you closed.
- **Catch me up does more, and Recap goes further.** Catch me up covers what your bouncer replays from while Vela was closed, Siri hands long catch-ups over to Vela, and a summary keeps going while you read another channel. **Recap** (⇧⌘R) is a fuller report in a window of its own: a channel, a network or everything, for anyone or one person, over any span, with what was decided, who'll do what and the links shared.
- **Saving your chat history is your choice.** It's off for new installs. If you already use Vela, nothing changes.
- **A fresh look in places:** a redesigned welcome screen, an emoji picker and a send button in the message box, and tabs that shrink to fit before they scroll, so every tab stays in view.

### Updates

- **Vela updates itself.** It checks for a new version once a day and offers it when you open Vela or come back to your Mac, never in the middle of a conversation. **Vela → Check for Updates…** checks right away, and the new **About Vela** window shows your version and whether it's up to date. **Settings → Updates** has **Check for updates automatically** (on by default, `updates.checkAutomatically`) and **Install updates automatically** (off by default, `updates.installAutomatically`). A check sends only Vela's version, and every update is signed and checked before it installs. See [Updates](https://velairc.app/guide/updates).
  - **Coming from Vela 1.0?** It has no updater, so get this version from [velairc.app](https://velairc.app/guide/install#from-1-0) by hand, once. From 1.1 on, Vela updates itself.
- **What's New after an update.** The first time a new version of Vela opens, it shows what changed, with anything you need to know first. **Help → What's New in Vela** shows it again.

### Keyboard

- **⌘W closes the tab, as in a browser.** In the main window, **File → Close Tab** (⌘W) does what the selected tab's **×** does: removes the channel, leaves it on a bouncer, hides a detached one or closes the conversation, asking first where that asks. The menu item says which. **File → Close Window** moves to ⇧⌘W. In Settings and other windows, ⌘W still closes the window.
- **Use the whole window from the keyboard.** The **Go** menu moves the keyboard to each part of the window: **Focus Sidebar** or **Focus Tabs** (⌥⌘1), **Focus Messages** (⌥⌘2), **Focus Message Box** (⌥⌘3 or ⌘L) and **Focus Member List** (⌥⌘4, which shows the list first if it's hidden). F6 and ⇧F6 go round them. The row or tab the keyboard is on has a ring in your theme's focus color, and VoiceOver says where you've moved. See [Keyboard shortcuts](https://velairc.app/reference/keyboard-shortcuts).
  - **In the sidebar or the rail,** ↑ and ↓ select as they go, like Mail's mailbox list. ← goes from a channel to its network, and on a network folds its channels away; → shows them again. Type the first letters of a name to go to it.
  - **In the tabs,** ← and → select the tab beside (Home and End, the first and last), and ↑ and ↓ go between the network row and the channel row.
  - Switching channels this way leaves the keyboard in the sidebar or the tabs, instead of the new message box taking it. Return or Esc goes back to the message box. Clicking a channel or a tab still goes straight to its message box.
  - **In the member list,** ↑, ↓, Page Up, Page Down, Home and End move a highlight. Return opens a private conversation with that person, and Space or ⇧F10 opens their user menu. Typing filters the list (↓ comes back from the filter), and Esc clears the filter, then goes back to the message box. In a channel of thousands, moving the highlight costs the same as in a small one.
- **Messages from the keyboard.** **Go → Focus Messages** (⌥⌘2), or F6, selects the newest message, or the lowest one in view if you've scrolled up. ↑ and ↓ move through the messages, skipping joins and parts, Page Up, Page Down, Home and End go further, and the selected message stays in view, highlighted in your theme's selection color. Then R replies, E reacts, C (or ⌘C) copies the text, Return opens its link (with a menu when there are several) or shows a collapsed run of joins and parts, U opens the sender's menu, T translates and Space shows every action, as right-clicking does. Esc, or just typing, goes back to the message box. VoiceOver reads each message as you select it, and offers the same actions. See [Keyboard shortcuts](https://velairc.app/reference/keyboard-shortcuts#the-messages).
  - In the message box, Page Up and Page Down scroll the messages a page, Home and End go to the oldest message loaded and the newest, and Esc with no reply or paste to cancel jumps to the newest message, like **Jump to present**.
- **Switch tabs from the keyboard, as in Safari.** **Go → Show Previous Tab** (⇧⌘[ or ⌃⇧Tab) and **Show Next Tab** (⇧⌘] or ⌃Tab) step through the network you're on: its console, channels and conversations, wrapping around at the ends. With the sidebar they walk the same list. **Go → Previous Network** (⌃⌘[) and **Next Network** (⌃⌘]) switch networks and come back to the channel you were last on there. ⌥⌘↑ and ⌥⌘↓ still go through everything.
- **Move tabs from the keyboard.** **Network → Move Channel Left** and **Move Channel Right** (⌥⇧⌘[ and ⌥⇧⌘]) move the selected channel or conversation one place, and **Move Network Left** and **Move Network Right** (⌃⌥⌘[ and ⌃⌥⌘]) move its network. With the sidebar they say Up and Down.
- **⌘1–⌘9 now always match the tabs' order** after joining, closing or reordering, and work with the sidebar too.
- **⌘[ and ⌘] switch sections in Settings.**

### Channels and tabs

- **Leave or remove a channel.** The menus have **Leave Channel** (or **Join Channel**) and **Remove Channel…**, and the command palette has **Leave**, **Join** and **Remove** for the selected channel. See [Leave or remove](https://velairc.app/guide/joining-channels#leave-or-remove).
  - **Leave Channel** parts the channel and keeps it in the list, dimmed, so **Join Channel** brings it back. It also comes off the network's auto-join list, so it stays left when you reconnect; joining it again puts it back where it was, with its key.
  - **Remove Channel…** parts the channel and takes it out of the list and off the auto-join list, so it doesn't come back when you reconnect. If you save message history, its messages stay in it.
  - A tab's **×** (or a middle-click) leaves and removes a channel in one step, like **Remove Channel…**. Its tooltip and VoiceOver action say what it does.
  - Vela asks before leaving or removing a channel. **Don't ask again** in the question, or **Ask before leaving a channel** and **Ask before removing a channel** in **Settings → Networks → Channels** (`channels.confirmLeave` and `channels.confirmRemove`), turn that off. `/part` leaves and `/close` removes without asking.
- **Leave a channel and keep it on your bouncer.** Through ZNC or soju, **Leave Channel**, a tab's **×** and a middle-click detach the channel: the bouncer stays in it and keeps its history, and Vela shows it dimmed, even after you quit and reopen Vela. **Join Channel** reattaches it and catches up on what you missed. If the bouncer doesn't confirm, the network's console says so, and Vela never parts the channel instead. See [Connecting through a bouncer](https://velairc.app/guide/bouncers#leaving-a-channel-detaches-it).
  - **Hide Channel** (or **×** on a detached channel) takes a detached channel out of the list and leaves it on the bouncer. Get it back from the network's settings (**Show** or **Join** under **Hidden channels**), with **Show #channel (Network)** in the command palette, or with ⌘Z and ⇧⌘T.
  - **Remove Channel…**, `/close` and `/part` really part, so the bouncer forgets the channel. **Closing a channel removes it from the bouncer** in **Settings → Networks → Channels** (`channels.bouncerCloseRemoves`) makes a tab's **×** and middle-click do that too.
  - A message the bouncer passes on from a detached channel counts as unread, or as a mention, without bringing the channel back. One from a hidden channel doesn't bring it back either; if you save message history, it's kept for when you show the channel.
  - Detached or removed a channel while disconnected from the bouncer? Vela tells the bouncer after your next connection, even if you quit Vela in between.
- **Reopen what you closed.** **File → Reopen Closed Channel** (⇧⌘T) brings back the channel you removed or hid, or the conversation you closed, last, and pressing it again goes further back. **File → Recently Closed** lists the last 20, and the command palette can reopen each one. A reopened channel returns to its old place, muted or not, with the **New** line where you left off, and goes back on the auto-join list with its key. The list lasts until you quit.
- **Undo it.** **Edit → Undo** (⌘Z) right after leaving, removing, hiding or closing puts things back, and **Redo** (⇧⌘Z) does it again. Undoing a leave joins the channel again (reattaching it on a bouncer) and puts it back on the auto-join list. It shares the message box's undo, so ⌘Z after typing undoes the typing first.
- **Tabs shrink to fit before they scroll.** When a row of tabs is too wide for the window, the tabs you're not on get narrower, longest names first, so every tab stays in view: short names stay whole and long ones are cut to the same width. The selected tab always shows its whole name, and its neighbors make room as you switch. Cut names fade out on the right instead of ending in "…", keeping the **#**, avatar and unread badge, and the tooltip and VoiceOver give the whole name. Only when the tabs wouldn't fit at their narrowest does the row scroll, with every name whole and the **»** menu. Tabs can also be narrower than before: about 58 points at the default size (was 78), so short names like **#dn** take less room. The network row in the strip works the same way. See [Tab stacks](https://velairc.app/guide/tab-stacks#when-tabs-don-t-fit).
- **Dragging a tab moves it past its neighbors sooner**: once its edge passes a neighbor's middle, as in a browser. A tab wider than the one at the end of its row (often the selected tab, which keeps its whole name) can now be dragged all the way to either end; before, it stopped one place short and couldn't be dragged back. The same goes for networks and channels dragged in the sidebar.
- **Hide the channel title bar.** With tabs at the top or the bottom, right-click the channel title bar and choose **Hide Channel Title Bar**. The tabs move up into the title bar, and the topic moves behind the **ⓘ** button. To bring it back, right-click an empty part of the title bar and choose **Show Channel Title Bar**: the tabs go back where they were. **View → Show Channel Title Bar** does both. It's the same as **Settings → Layout → Placement → Title bar**. See [Tab stacks](https://velairc.app/guide/tab-stacks#hide-the-channel-title-bar).
- **`/close` in the sidebar** now moves to the next channel, like closing a tab does, instead of leaving an empty view.
- **A channel you close stays closed** even when messages are still arriving as you leave it.

### Chat and messages

- **Emoji in the message box.** The smiley at the end of the message box, or **Edit → Emoji…** (⇧⌘E), opens an emoji picker: search, move with the arrow keys and press Return to pick, and the emoji goes in where your cursor was. The message box also has a send button, which **Show the send button** in **Settings → Messages → Typing** hides. The smiley and the send arrow are your accent color while you're typing, and muted otherwise. GIF search comes in a later version. See [Emoji & GIFs](https://velairc.app/guide/emoji-and-gifs).
- **More room between lines and messages.** Line spacing now starts at 4 pt (was 2) and message spacing at 12 pt (was 6), and so does the **Modern Chat** preset. If you applied Modern Chat in Vela 1.0 and kept its spacing (exactly 2 and 6), yours moves to 4 and 12 once, so **Settings → Presets** still shows Modern Chat, and What's New says so. Any other spacing you set stays as you set it. Change them in **Settings → Messages**.
- **Reply works on every channel.** On servers without IRCv3 replies, such as Libera.Chat or through most bouncers, **Reply** (R, the hover button or the right-click menu) puts the sender's `nick: ` in the message box, the usual IRC way, on any message, instead of not being offered.
- **Nicks are colored in messages.** When a message mentions someone in the channel, or the person you're talking with, their nick has the same color it has everywhere else, and right-clicking it opens their menu (now in a conversation too). Only whole nicks are colored, never inside links or channel names or over colors the sender chose, and a mention of you keeps its own highlight. It's on by default with **Colored nicknames**; turn it off with **Color nicks in messages** in **Settings → Messages** (`chat.colorNicksInText`) or **Toggle Nick Colors in Messages** in the command palette.
- **Nobody else has your nick's color.** Many themes have your nick's color in their nick palette too, so someone else could be shown in it, or in a color right beside it, and look like you. Those colors are now kept for you. Your nick also has its own color in the member list and on your avatar, as on your messages, and in a crowded channel someone new shares the color of a person who isn't talking rather than look like someone who is.
- **Messages a bouncer replays now count as unread.** What ZNC, soju or a server with chat history replays when Vela connects counts in unread and mention badges, the New line and the Dock badge once it's newer than where you stopped reading. Replayed messages never pop up notifications or play sounds, and a channel Vela has never had open starts counting from when it first joins.
- **Mention** in a sender's menu or the member list now always puts their nick in the message box. When the message box didn't have the focus, it could flash in and vanish.
- The newest message no longer ends up out of view (under the message box) when something arrives just as you send.

### Inline media

- **GIFs from KLIPY play inline,** like those from Tenor, GIPHY and Imgur: links to a GIF's `.gif`, `.webp` or `.mp4` file on KLIPY's servers (`static.klipy.com`), with a **via KLIPY · klipy.com** line under them that opens klipy.com, and KLIPY's watermark, small and see-through, in the bottom-left corner, as KLIPY asks. Your media settings apply to them as to other GIFs, and a site rule for `klipy.com` covers them. See [Supported media sites](https://velairc.app/reference/media-sites#gifs).

### Appearance

- **Even spacing around messages.** A mention's highlight, the hover color and a selection now sit evenly around a message, one line or several, with its nick and time on their own line or beside it; before, they ran high above the name and stopped right under the text. **Message spacing** (`chat.messageSpacing`) is now the same distance in every layout, outside those colors, so Modern and Classic no longer space messages differently for the same setting.
- **Your nick looks the same everywhere.** Where a message mentions you, your nick is in your own nick color, as on your messages, rather than a separate mention color. Built-in themes follow it (Solarized Dark's and Vela Mist's nick colors are a touch stronger, to stay readable on the mention highlight); a theme can still set `chat.mention` on its own. A recap that names you uses your nick color too.
- **Other people's nicks are easier to tell apart.** Colors in a theme's nick palette that look alike, like Palenight's blue and lavender, are nudged a little apart when the theme loads, staying close to the theme's own colors and just as readable. And when two people who were given look-alike colors at different times end up talking side by side, one of them (usually the one who'd been away) moves to a clearly different color, at most once per conversation, and the change shows at once in their messages, the member list and wherever they're mentioned. The member list now also picks up a color someone is given as they first speak, rather than showing their usual one until it next updates.
- **A new welcome screen.** The sailboat is gone. Before you add a network, or when no conversation is open, Vela shows a picture of a river winding through a mountain valley. Dark themes get night: a full moon, Vela's stars and a stargazer at a telescope. Light themes get day: the sun, clouds, birds and a kayaker paddling upstream. It's drawn in your theme's colors and accent, so a custom theme, a new accent color or your color customizations change it too. It grows and shrinks with the window, and it's drawn only when the window shows, resizes or changes theme. The drawing code is published on its own as [Savage](https://github.com/r3volution11/Savage), an open-source (MIT) Swift package that draws a picture on screen and writes the same picture as an SVG.

### Catch me up and Recap

- **Recap: a report of what you missed, or of any stretch you pick.** **Go → Recap…** (⇧⌘R), **Recap…** in a channel's right-click menu, **Recap Network…** in a network's, **Recap Conversations with alice…** in a person's, the command palette, **Open Full Recap** on a Catch me up card and Siri open one in a window of its own. See [Recap](https://velairc.app/guide/recap).
  - **It covers what you choose:** a channel, a network or every network; anyone, or one person (their messages, messages that name them or reply to them, and your private conversation with them); since your first unread message, or the last 30 minutes up to a week, or any number of minutes, hours or days. With nothing unread, it asks how far back to go. It reads saved history when **Save message history** is on, and says when Vela doesn't have messages that far back.
  - **Summary:** Apple Intelligence's report, short and to the point: an overview, the topics with who took part, **For you** (messages that named you, and private messages, marked **No reply yet** when you haven't answered), **Decisions and follow-ups** (what was decided, open questions, who said they'd do what) and **Links shared**. Each item links to its message in the main window, and **More detail** reads just the messages behind a topic or note again for a closer look. Sections fill in as they're written, with progress ("Reading 340 of 1,200 messages"), and a long Recap says about how long it will take first.
  - **Log:** the same messages as a readable transcript, by channel and day, in nick colors. No Apple Intelligence needed, so it works on any Mac.
  - **Copy as Markdown** and **Save as Markdown…**. Nothing else is kept: closing the window forgets the Recap.
  - **Up to the latest 2,000 messages are summarized,** in parts that fit your Mac's model, at low priority, one summary at a time with Catch me up. Like Catch me up, a Recap tells Apple Intelligence the messages and your nick, never a channel's, network's or person's name.
  - **Offer Recap** in **Settings → Apple Intelligence** (`intelligence.recap`) turns it off everywhere.
- **Siri hands a catch-up longer than a card covers (over 600 messages) to a Recap,** and the new **Open Recap** action opens one from Siri and Shortcuts: "Recap #vela in Vela", "Recap today in Vela".
- **Catch me up works with bouncers.** Messages your bouncer replays count as new, so the button, the card and Siri cover what you missed while Vela was closed.
- **Private Cloud Compute for long catch-ups comes in a later version.** It's built, but apps need Apple's permission to use Private Cloud Compute, and Vela is waiting for it, so for now it's only in development builds. In this version, every catch-up is summarized on your Mac. See [Private Cloud Compute for long catch-ups](https://velairc.app/guide/apple-intelligence#private-cloud-compute).
- **Going to another channel no longer cancels a summary.** It keeps going, and the card is there when you come back. After you've read the channel, **Catch Me Up** in the right-click menu, the command palette or Siri shows that summary again until you quit.
- **Long catch-ups show their progress:** "Reading… 3 of 8", then "Writing the summary…". Every response is capped, so a runaway one can't keep Apple Intelligence busy for minutes.
- **Summaries are written one at a time,** in the order you ask for them, so catching up in several channels doesn't weigh down a Mac with 8 GB of memory. A card waiting its turn says "Waiting… 1 summary ahead", and dismissing it takes it out of line. A summary Siri is waiting for goes next.
- **Words never disappear from the card.** When a pass has to be redone, what was written stays, dimmed, with "Finishing…", until the new words arrive.
- **Catch me up no longer skips most of a heated or political channel:** summaries are asked for in plain text, which Apple Intelligence's safety checks accept far more often, and describe the discussion neutrally, without taking sides or repeating insults.
- **A part Apple Intelligence won't summarize is skipped,** and the card says how many messages it left out, instead of the whole summary failing.
- **Apple Intelligence is no longer told the channel's or the network's name.** Catch me up gives it the messages and your nick, nothing else.
- **A topic links to its first message only when Apple Intelligence placed it there.** A topic it couldn't place has no link, instead of a guess at where it started.
- **Catch Me Up in the right-click menu and the command palette is always there** while Catch me up is on. With nothing new it says so on a card, and the palette notes "nothing new" or "earlier summary".
- **Offer Catch me up in busy channels turns it off everywhere:** the button, the right-click menu, the command palette and open cards, and Siri says it's turned off.
- **A clear message when the conversation's language isn't supported,** without the System Settings button meant for your Mac's language.
- **Apple Intelligence turns on as soon as it's ready.** When macOS finishes downloading the model while Vela is in front, Catch me up and **Settings → Apple Intelligence** update at once, instead of waiting until you switch away from Vela and back.

### Siri, Shortcuts and Spotlight

- **Siri's Catch Me Up never cuts a catch-up short.** A stretch your Mac summarizes in one quick pass (about 100 messages) Siri reads out itself. A longer one opens Vela to the channel, with the Catch me up card summarizing all of it, after Siri says so ("That's 412 messages in #vela. Opening Vela to catch you up."). Siri waits about 15 seconds at most; a summary that isn't ready by then carries on in the card. A summary already made in the card is used whole.
- **Name the network to Siri.** "Open #vela on Libera.Chat in Vela", or just "on Libera", picks the channel on that network when you're in channels with the same name on more than one. It works in every phrase that names a channel.
- **Catch Me Up and Check Mentions are right after Siri opens Vela.** They count what's unread from where you last read each channel, so they no longer say "You're all caught up" or "You have no new mentions" before Vela has loaded its history.
- **Siri can run an action the moment it opens Vela.** Vela sets up what its actions need as it starts, rather than when it sets up its windows.
- **Show channels in Spotlight** only takes your channels out of Spotlight's results now. On macOS 27, Siri still finds channels and nicks by name when it's off.
- **Spotlight keeps up after a hiccup.** A Spotlight update that fails is tried again, a little later each time, and updates no longer run over each other.
- **Settings → Apple Intelligence** shows a fixed example phrase, using Vela's own channel, instead of the name of one of your channels.
- **Settings no longer promise "summarize this" on macOS 27.** macOS gives apps no public way to let Siri summarize what's on screen; ask it to "Catch me up on #vela in Vela" instead.

### Privacy

- **Saving your chat history is now your choice.** **Save message history** in **Settings → Messages → History** (`history.save`) is off for new installs: messages, reactions and link previews stay in memory while Vela is open, and a bouncer or server that keeps history fills them in again after a restart. Your channels and where you stopped reading are still saved, so unread counts and Catch me up work as before. See [Scrollback and history](https://velairc.app/guide/messages-and-layouts#scrollback-and-history).
  - **If you already use Vela, nothing changes:** your history is still being saved, and **Keep messages** still applies. Turn it off any time.
  - Turning it off asks whether to delete what's already saved or keep it. **Delete Saved History…** removes saved messages, reactions and link previews whenever you like. [Chat logs](https://velairc.app/guide/chat-logs) are separate, and stay off unless you turn them on.

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
