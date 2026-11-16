---
title: Sending messages
description: Use Vela's message field, with Tab completion for nicks, channels, commands and emoji, per-channel history and drafts, replies, multi-line paste confirmation and slash commands.
---

# Sending messages

Type in the message field at the bottom of the window and press **Return** to send. Press <kbd>⌘L</kbd> to jump to the field from anywhere.

| Key | Does |
| --- | --- |
| <kbd>Return</kbd> | Send |
| <kbd>⇧Return</kbd> or <kbd>⌥Return</kbd> | New line |
| <kbd>Tab</kbd> | Complete the word before the cursor; press again for the next match |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Previous / next message you sent here |
| <kbd>Esc</kbd> | Cancel a reply or a pending paste |

The field grows as you type, up to eight lines, then scrolls. IRC limits how long a single message can be, so long or multi-line text is sent as several messages; a small "2 messages" label tells you before you send.

## Tab completion

Press <kbd>Tab</kbd> after typing the start of a word:

- **Nicknames.** People who spoke most recently come first. At the start of a line Vela adds `: ` (`wren: `), the IRC way of addressing someone. A leading `@`, a habit from Slack and Discord, is dropped.
- **Channels.** Words starting with `#` complete channels on this network, joined ones first.
- **Commands.** `/jo` at the start of a line completes to `/join `.
- **Emoji.** `:thu` completes to 👍. Typing a whole shortcode such as `:tada:` turns it into 🎉 as you type. Vela knows the common Slack, GitHub and Discord names.

Press <kbd>Tab</kbd> again to cycle through the other matches.

## History and drafts

<kbd>↑</kbd> on the first line brings back the messages you've sent in this channel, newest first, and <kbd>↓</kbd> walks forward again to what you were typing. History lasts until you quit Vela.

Unsent text is kept per channel, so you can switch away mid-sentence and pick up where you left off.

## Replies

Hover a message and click the **reply** arrow (or right-click it and choose **Reply**). A bar above the field shows who you're replying to; press <kbd>Esc</kbd> or click **×** to cancel.

Replies need server support (IRCv3 message tags). On servers without it, the bar says **sent as a normal message**. See [Reactions, replies & typing](/guide/reactions-replies-typing).

## Pasting several lines

On IRC, every line is a separate message, and pasting a wall of text can flood a channel (or get you kicked). When you paste more than three lines, Vela asks first: **Send 12 lines to #channel?**

- **Send** (or <kbd>Return</kbd>) sends them all.
- **Edit** puts the text in the field so you can trim it.
- **Cancel** (or <kbd>Esc</kbd>) discards the paste.

Pasted text is always sent as-is, even if a line starts with `/`.

## Slash commands

Messages that start with `/` are commands: `/me waves`, `/join #vela`, `/msg nick hi`, `/topic …` and many more. See the full list in [Slash commands](/reference/slash-commands). To send a message that starts with a slash, type two: `//shrug` sends `/shrug`.

Commands Vela doesn't know are sent to the server as typed, so commands like `/list`, `/motd` or `/names` work too.

## When you can't send

If you're offline, or you've left the channel, the field says so (**Offline — reconnect to send** or **Not in channel — /join to rejoin**) and shows a **Reconnect** or **Join** button. Commands still work.

## Spelling and typing indicators

In **Settings → Advanced** you can turn off spell checking, and choose whether others see when you're typing (on servers that support typing indicators).
