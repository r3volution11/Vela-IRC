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

Like [Slack](https://slack.com) or [Discord](https://discord.com): consecutive messages from one person share a single header with their name and the time. Hover a follow-up message to see its time in the margin.

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

Turn timestamps on or off, and choose how they read:

- **Clock**: **System** (the default) follows your Mac's **24-hour time** setting in System Settings → General → Date & Time, and updates as soon as you change it. **12-hour** (`2:47 PM`) and **24-hour** (`14:47`) override it for Vela.
- **Show seconds** adds seconds (`2:47:09 PM`, `14:47:09`).
- **Custom format** lets you write any [Unicode date pattern](https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table), such as `HH.mm` or `EEE HH:mm`. It starts from the format you had; turn it off to go back to the clock settings.

Below the settings, a sample shows what your timestamps look like.

## Joins, parts and other noise

**Joins and parts** controls join, part, quit and nick-change messages:

- **Show** each one on its own line.
- **Collapse** a run of them into one summary, such as "alice, bob and 3 others joined · carol left", which you can expand. This is the default.
- **Hide** them completely.

The same choices are in **View → Message Layout**.

## Colors and formatting

- **Colored nicknames** gives everyone a color from your theme's nick palette. People talking in the same channel get different colors while the palette has room, so two nicks never look alike just because their names hash alike. When someone's usual color would look like the color of a person they're talking with (orange beside red, say), they get the nearest color from the palette that's clearly different; otherwise everyone keeps their usual color. Each nick keeps its color once given, and usually has the same one in every channel. Palette colors that would read as plain text are skipped.
- **[mIRC](https://www.mirc.com) formatting** shows bold, italic, underline, strikethrough, monospace, colors (including hex colors) and reverse text sent by other clients. Turn it off to see plain text.
- **Large emoji** shows messages that are only emoji at a bigger size.
- Messages that **mention you** get a tinted background and an accent bar. See [Notifications & highlights](/guide/notifications).

## Reading a conversation

- **Day dividers** ("Today", "Yesterday", "Monday, November 10") separate days.
- A **New** line shows where you stopped reading. In a busy channel, it offers **Catch me up**, an Apple Intelligence summary of what you missed. See [Catch me up](/guide/apple-intelligence#catch-me-up). You can turn the line off; see [Unread messages](#unread-messages).
- When you scroll up, **Jump to present** brings you back to the newest messages, with a count of what arrived meanwhile.
- **Right-click** a message (or hover it and click **…**) to copy its text, link or the sender's nick, message or `/whois` them, [translate it](/guide/apple-intelligence#translate-messages), or [react and reply](/guide/reactions-replies-typing). Right-click a link to copy that link.
- **Select text** in a message to copy part of it, links included: drag across it, double-click a word or triple-click the line, then press <kbd>⌘C</kbd>. A single click on a link opens it.

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

Vela stores your messages on your Mac in a local database. Each channel keeps the most recent **1,000** messages in memory (**Messages kept in memory**); scroll up and older messages load from disk, then from the server if it supports [`chathistory`](/reference/ircv3).

To limit how much history is kept, set **Settings → Messages → History → Keep messages** (from a week to two years). Older messages are removed when Vela starts. By default history is kept forever. In settings.json it's [`history.retentionDays`](/reference/settings#history.retentionDays), which takes any number of days.
