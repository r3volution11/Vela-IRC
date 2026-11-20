---
title: Messages & layouts
description: Vela's three message layouts (Classic, Modern grouped and Compact columns), fonts and spacing, timestamps, join/part display, nick colors, mIRC formatting, unread messages and scrollback.
---

# Messages & layouts

Vela can lay out a conversation three ways. Switch in **Settings → Messages**, from **View → Message Layout**, or by typing "layout" in the [command palette](/guide/command-palette) (<kbd>⇧⌘P</kbd>). The change applies instantly.

## Classic

<Screenshot src="/screenshots/layout-classic.webp" alt="The Classic layout: each message on one line, with the time and the nick in angle brackets before the text" />

One line per message, `[12:01] <nick> text`, like [Textual](https://www.textualapp.com) or [irssi](https://irssi.org). Long messages wrap and hang under the text, clear of the timestamp column. Actions read `* nick waves`.

Pair it with **Monospace** (below) for a terminal feel; the **Classic IRC** [preset](/guide/presets) does exactly that.

## Modern grouped

<Screenshot src="/screenshots/preset-modern.webp" alt="The Modern grouped layout: a name and time header over consecutive messages from the same person" />

Like [Slack](https://slack.com) or [Discord](https://discord.com): consecutive messages from one person share a single header with their name and the time. Hover a follow-up message to see its time in the margin. You can [move the time](#timestamp-position) too.

Messages are grouped when they arrive within **5 minutes** of each other (**Group messages within** in Settings, `chat.groupingInterval` in settings.json). Turn on **Avatars** to show initials next to each group; they're off by default.

## Compact columns

<Screenshot src="/screenshots/layout-columns.webp" alt="The Compact columns layout: time, a right-aligned nick column and the message text in aligned columns" />

Like [WeeChat](https://weechat.org): time, a right-aligned nick, then the text, in tidy columns divided by a thin rule. Adjust the **Name column width** to fit the nicks you see most.

## Text and spacing

In **Settings → Messages**:

- **Font** is the system font by default; choose any font installed on your Mac.
- **Monospace** renders all chat text in the monospace font, like irssi or WeeChat. **Monospace font** (SF Mono by default) is also used for code and for the columns layout's fixed-width parts.
- **Font size** goes from 9 to 28 points. **View → Bigger** (<kbd>⌘+</kbd>), **Smaller** (<kbd>⌘−</kbd>) and **Actual Size** (<kbd>⌘0</kbd>) change it from anywhere.
- **Line spacing** adds space between the lines of one message; **Message spacing** adds space between messages and groups.

## Timestamps

<Screenshot src="/screenshots/settings-timestamps.webp" alt="Settings → Messages → Timestamps: Show timestamps, Position (Left, Right, Top or Bottom) for the current layout, Other layouts, Clock, Show seconds and Custom format" />

Turn timestamps on or off, move them (see [Timestamp position](#timestamp-position)), and choose how they read:

- **Clock**: **System** (the default) follows your Mac's **24-hour time** setting in System Settings → General → Date & Time, and updates as soon as you change it. **12-hour** (`2:47 PM`) and **24-hour** (`14:47`) override it for Vela.
- **Show seconds** adds seconds (`2:47:09 PM`, `14:47:09`).
- **Custom format** lets you write any [Unicode date pattern](https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table), such as `HH.mm` or `EEE HH:mm`. It starts from the format you had; turn it off to go back to the clock settings.

Below the settings, a sample shows what your timestamps look like.

### Timestamp position

**Position** puts the time on the **Left**, **Right**, **Top** or **Bottom** of each message. Each layout keeps its own position, so you can have times on the right in Modern and in a column on the left in Classic. The control sets the layout you're using; **Other layouts** shows the others' and lets you change them too. The preview at the top of **Settings → Messages** follows along.

<Screenshot src="/screenshots/timestamps-right.webp" alt="The Modern layout with timestamps on the right: each group's time sits at the right edge, level with the name" />

| Position | Classic | Modern | Compact columns |
| --- | --- | --- | --- |
| **Left** | Before the nick, `[12:01] <nick> text` (the default) | In the margin, level with the name (under the avatar, with avatars on) | The time column before the nicks (the default) |
| **Right** | At the right edge, level with the first line | At the right edge, level with the name | A time column at the right edge |
| **Top** | On a small line above each message | Beside the name (the default) | On a small line above the text |
| **Bottom** | On a small line below each message | Below the group's first message | On a small line below the text |

In **Modern**, only a group's first message shows its time. Hover the others to see theirs: in the margin, or at the right edge with **Right**. **Bottom** goes under the first message, the one it dates, rather than under the whole group.

A few details:

- Times on the right line up in one column, and the hover toolbar moves to their left so it never covers them.
- A time at the bottom comes right after the message and its [translation](/guide/apple-intelligence#translate-messages), above link previews, images and reactions.
- Joins, parts and other events stay one compact line. With **Right**, and with **Left** in Classic and Compact columns, their time is in the same column as the messages'. Otherwise it follows the event's text, as Modern has always shown it, rather than taking a line of its own.
- Turning **Show timestamps** off hides them in every position. Copying a message never includes its time, and VoiceOver reads the time with the message wherever it's drawn.

In settings.json these are [`chat.timestampPosition.classic`](/reference/settings#chat.timestampPosition.classic), [`chat.timestampPosition.grouped`](/reference/settings#chat.timestampPosition.grouped) and [`chat.timestampPosition.columns`](/reference/settings#chat.timestampPosition.columns), each `"left"`, `"right"`, `"top"` or `"bottom"`. In the [command palette](/guide/command-palette), **Chat: Timestamps on the Left**, **on the Right**, **at the Top** and **at the Bottom** set the layout you're using, and turn timestamps on if they're off.

## Joins, parts and other noise

**Joins and parts** controls join, part, quit and nick-change messages:

- **Show** each one on its own line.
- **Collapse** a run of them into one summary, such as "alice, bob and 3 others joined · carol left", which you can expand. This is the default.
- **Hide** them completely.

The same choices are in **View → Message Layout**.

## Colors and formatting

- **Colored nicknames** gives everyone a color from your theme's nick palette. People talking in the same channel get different colors while the palette has room, so two nicks never look alike just because their names hash alike. When someone's usual color would look like the color of a person they're talking with (orange beside red, say), they get the nearest color from the palette that's clearly different; otherwise everyone keeps their usual color. In a crowded channel where every clearly different color is taken, someone new shares the color of a person who isn't talking right now rather than look like someone who is. Each nick keeps its color once given, and usually has the same one in every channel. Palette colors that would read as plain text are skipped.
- **Your own nick** always has your theme's own color for it, in your messages, avatar, the member list and reply quotes alike, and nobody else is given that color or one that looks like it.
- **Color nicks in messages** colors the nick of anyone in the channel (or the person you're talking with, in a conversation) where a message mentions them, in the same color as everywhere else. Right-clicking a colored nick opens that person's menu. It's on by default and needs **Colored nicknames**. Only whole nicks of two or more characters are colored, never inside a link or a channel name, and never over colors the sender chose. A mention of you keeps its own highlight. In settings.json it's [`chat.colorNicksInText`](/reference/settings#chat.colorNicksInText); the command palette has **Chat: Toggle Nick Colors in Messages**.
- **[mIRC](https://www.mirc.com) formatting** shows bold, italic, underline, strikethrough, monospace, colors (including hex colors) and reverse text sent by other clients. Turn it off to see plain text.
- **Large emoji** shows messages that are only emoji at a bigger size.
- Messages that **mention you** get a tinted background and an accent bar. See [Notifications & highlights](/guide/notifications).

## Reading a conversation

- **Day dividers** ("Today", "Yesterday", "Monday, November 10") separate days.
- A **New** line shows where you stopped reading. In a busy channel, it offers **Catch me up**, an Apple Intelligence summary of what you missed. See [Catch me up](/guide/apple-intelligence#catch-me-up). You can turn the line off; see [Unread messages](#unread-messages).
- When you scroll up, **Jump to present** brings you back to the newest messages, with a count of what arrived meanwhile.
- While you scroll, messages passing under the pointer don't light up or show their toolbar. The one under the pointer does as soon as you stop.
- **Right-click** a message anywhere, its text included, or Control-click it (or hover it and click **…**) to copy its text, link or the sender's nick, message or `/whois` them, [translate it](/guide/apple-intelligence#translate-messages), or [react and reply](/guide/reactions-replies-typing). Right-click a link to copy that link.
- **Select text** in a message to copy part of it, links included: drag across it, double-click a word or triple-click the line, then press <kbd>⌘C</kbd>, or right-click it for **Copy**, **Look Up** and **Share…** along with the message's own items. A click on a link opens it right away; a drag that starts on a link selects text instead. [Link previews](/guide/inline-media#link-previews) work the same way.

## Unread messages

**Settings → Messages → Unread messages** sets where channels open and whether new messages are marked.

**When you open a channel**:

- **Jump to first unread** (the default) opens a channel with unread messages at the New line, so you pick up where you stopped. **Jump to present** takes you down to the newest messages.
- **Show newest** opens every channel at the bottom, with the newest messages in view: no **Jump to present** button, nothing to scroll down to. Coming back to Vela from another app also shows the newest messages, and the conversation stays at the bottom as messages arrive. If you scroll up yourself, Vela leaves you there, and **Jump to present** counts what's arriving below, like irssi's `-- more --`.

**Show the New line** is on by default. Turn it off and messages appear just as they came in, with nothing marking which are new. With **Jump to first unread**, channels still open at the first message you haven't read; it just isn't marked.

Either way, unread counts in the sidebar, the rail and on tabs work as usual. Without the New line, the **Catch me up** button isn't offered, because it sits on the line; right-click the channel and choose **Catch Me Up**, or use the [command palette](/guide/command-palette), instead. See [Catch me up](/guide/apple-intelligence#catch-me-up).

For a classic IRC feel, where everything is simply there as it came in, choose **Show newest** and turn off the New line. The **Classic IRC** [preset](/guide/presets) does both.

In settings.json these are [`chat.openAt`](/reference/settings#chat.openAt) (`"firstUnread"` or `"newest"`) and [`chat.showUnreadMarker`](/reference/settings#chat.showUnreadMarker). In the command palette, they're **Chat: Open Channels at Newest Messages** and **Chat: Show New Line**.

## Scrollback and history

Each channel keeps the most recent **1,000** messages in memory (**Messages kept in memory**). Scroll up and older messages load from disk, if you save history, then from the server if it supports [`chathistory`](/reference/ircv3).

**Save message history**, in **Settings → Messages → History**, decides whether messages are kept on your Mac:

- **Off** (the default for new installs): messages, reactions and link previews live in memory while Vela is open. When you connect again, a [bouncer](/guide/bouncers) or a server with `chathistory` sends the latest messages, and older ones as you scroll up. Without one, a channel starts empty after a restart.
- **On:** they're saved in a local database on your Mac, as Vela always did before this setting existed. If you used Vela then, it's on for you, so nothing changed.

Either way, Vela saves your channels and conversations, where you stopped reading, and whether each is muted, so unread counts, the **New** line and [Catch me up](/guide/apple-intelligence#catch-me-up) still work with what a bouncer replays. In settings.json it's [`history.save`](/reference/settings#history.save); in the [command palette](/guide/command-palette), **Chat: Save Message History**.

**Turning it off** asks what to do with the history already saved: **Delete Saved History** removes it from your Mac, and **Keep What's Saved** leaves it, so it still shows in your channels while nothing new is added. **Delete Saved History…**, under the setting, removes saved messages, reactions and link previews whenever you like. Your channels, read positions, settings and chat logs stay, and the messages on screen stay until you quit.

To limit how much saved history is kept, set **Keep messages** (from a week to two years). Older messages are removed when Vela starts. By default saved history is kept forever. In settings.json it's [`history.retentionDays`](/reference/settings#history.retentionDays), which takes any number of days. It applies while history is saved, and to history you kept when you turned saving off.

For a copy you can keep, search or open in other apps, turn on [chat logs](/guide/chat-logs): plain-text files, one folder per network. They're separate from message history: a log is a copy for you, which Vela never loads back, and it's written whether or not history is saved.
