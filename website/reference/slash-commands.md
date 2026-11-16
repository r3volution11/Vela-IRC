---
title: Slash commands
description: Every slash command Vela understands, from /join, /msg and /me to /mode, /ban, /ctcp and /raw, with their aliases and arguments.
---

# Slash commands

Type a command in the message field and press Return. <kbd>Tab</kbd> completes command names at the start of a line. Arguments in `<angle brackets>` are required and ones in `[square brackets]` are optional.

::: tip
Any command Vela doesn't know is **sent to the server as typed**, so `/list`, `/motd`, `/names`, `/who` and your network's own commands all work. To send a message that starts with a slash, type two: `//shrug` sends `/shrug`.
:::

## Talking

| Command | Does |
| --- | --- |
| `/me <action>` | Sends an action: `/me waves` shows as "* doug waves". |
| `/msg <target> <message>` | Sends a message to a nick or channel. To a nick, it opens a private conversation. Alias: `/privmsg`. |
| `/query <nick> [message]` | Opens a private conversation with someone, and optionally sends a message. Alias: `/q`. |
| `/notice <target> <message>` | Sends a notice, the IRC way of messaging without expecting a reply. |
| `/ctcp <target> <command> [args]` | Sends a CTCP request, such as `/ctcp wren VERSION` or `/ctcp wren PING`. |

## Channels

| Command | Does |
| --- | --- |
| `/join <#channel>[,#other] [keys]` | Joins one or more channels, with keys if they need them: `/join #a,#b keyA,keyB`. Alias: `/j`. |
| `/part [#channel] [reason]` | Leaves the current (or named) channel. Vela stops rejoining it automatically. Alias: `/leave`. |
| `/topic [#channel] [new topic]` | Shows the topic, or sets it if you add text. |
| `/invite <nick> [#channel]` | Invites someone to the current (or named) channel. |
| `/close` | Closes the current channel (leaving it) or conversation. Alias: `/wc`. |
| `/clear` | Clears the messages shown in this channel. Your stored history isn't deleted. |

## You

| Command | Does |
| --- | --- |
| `/nick <newnick>` | Changes your nickname. |
| `/away [message]` | Marks you as away, with an optional message ("Away" if you don't give one). |
| `/back` | Marks you as back. |
| `/whois <nick>` | Shows who someone is: their host, real name, channels and account. Alias: `/wi`. |

## Moderation

These work in the current channel, and need operator rights there.

| Command | Does |
| --- | --- |
| `/op <nick> [nick…]`, `/deop` | Gives or takes operator status (`+o`). |
| `/voice <nick> [nick…]`, `/devoice` | Gives or takes voice (`+v`). |
| `/halfop <nick> [nick…]`, `/dehalfop` | Gives or takes half-op status (`+h`), on servers that have it. |
| `/kick <nick> [reason]` | Removes someone from the channel. Alias: `/k`. |
| `/ban <nick or mask>` | Bans a mask. Given a nick, Vela bans `*!*@their.host` if it knows their host, otherwise `nick!*@*`. |
| `/unban <mask>` | Removes a ban. |
| `/mode [target] <modes> [args]` | Sets modes. Without a target, it applies to the current channel (or, in the server console, to you). For example `/mode +m` or `/mode #vela +b *!*@spam.example`. |

## Ignoring

| Command | Does |
| --- | --- |
| `/ignore <nick or mask>` | Hides messages from matching people on this network. A bare nick matches any user and host; masks like `*!*@host.example` work too. |
| `/unignore <nick or mask>` | Stops ignoring them. |

The ignore list is saved with the network; you can also edit it in the [network settings](/guide/adding-a-network#highlight-words-and-ignore-list).

## Connection

| Command | Does |
| --- | --- |
| `/connect` | Connects this network, using its saved settings. Alias: `/server`. To add a new server, use **Add Network…** (<kbd>⇧⌘N</kbd>). |
| `/disconnect [reason]` | Disconnects from this network. |
| `/quit [reason]` | Disconnects from this network with a quit message. It doesn't quit Vela; <kbd>⌘Q</kbd> does that. |
| `/reconnect` | Disconnects and connects again. |
| `/raw <line>` | Sends a line to the server exactly as typed, such as `/raw PRIVMSG NickServ :help`. Alias: `/quote`. |

`/connect`, `/disconnect`, `/quit`, `/reconnect`, `/close`, `/clear`, `/ignore` and `/unignore` work while you're offline; everything else needs a connection.
