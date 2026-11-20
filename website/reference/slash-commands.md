---
title: Slash commands
description: Every slash command Vela understands, from /join, /msg and /me to /mode, /kickban, /quiet, /ping, /ctcp and /raw, with their aliases and arguments.
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
| `/ctcp <target> <command> [args]` | Sends a CTCP request, such as `/ctcp wren VERSION` or `/ctcp wren PING`. The reply shows where you asked. |
| `/ping <nick>` | Sends a CTCP PING and shows how long the reply took: "Ping reply from wren: 84 ms". |
| `/version <nick>` | Asks which client they use (CTCP VERSION). Without a nick, or with a server name, it asks the server for its version. |
| `/time <nick>` | Asks for their local time (CTCP TIME). Without a nick, or with a server name, it asks the server. |
| `/clientinfo <nick>` | Asks which CTCP requests their client answers. |

## Channels

| Command | Does |
| --- | --- |
| `/join <#channel>[,#other] [keys]` | Joins one or more channels, with keys if they need them: `/join #a,#b keyA,keyB`. A channel you left goes back on the network's auto-join list, joined with its key if you don't type one. Through a bouncer, it reattaches a detached channel and shows a hidden one. Alias: `/j`. |
| `/part [#channel] [reason]` | Leaves the current (or named) channel, like **Leave Channel** on a network without a bouncer: it stays in the list, dimmed, and comes off the auto-join list, so Vela stops rejoining it. Through a bouncer it really parts too, so the bouncer forgets the channel; to keep it on the bouncer, use **Leave Channel**, which detaches it. It never asks first, and <kbd>⌘Z</kbd> joins it again. Alias: `/leave`. |
| `/topic [#channel] [new topic]` | Shows the topic, or sets it if you add text. |
| `/invite <nick> [#channel]` | Invites someone to the current (or named) channel. |
| `/close` | Removes the current channel, like **Remove Channel…** (leaving it, and taking it off the network's auto-join list; a bouncer forgets it too), or closes the current conversation. It never asks first. <kbd>⌘Z</kbd> or <kbd>⇧⌘T</kbd> brings it back. Alias: `/wc`. |
| `/clear` | Clears the messages shown in this channel. Your stored history isn't deleted. |

## You

| Command | Does |
| --- | --- |
| `/nick <newnick>` | Changes your nickname. |
| `/away [message]` | Marks you as away, with an optional message ("Away" if you don't give one). |
| `/back` | Marks you as back. |
| `/whois <nick>` | Shows who someone is: their host, real name, channels and account. Alias: `/wi`. |

## Moderation

These work in the current channel, and need operator (or half-op) rights there. The [user menu](/guide/user-menu) sends the same commands.

| Command | Does |
| --- | --- |
| `/op <nick> [nick…]`, `/deop` | Gives or takes operator status (`+o`). |
| `/voice <nick> [nick…]`, `/devoice` | Gives or takes voice (`+v`). |
| `/halfop <nick> [nick…]`, `/dehalfop` | Gives or takes half-op status (`+h`), on servers that have it. |
| `/kick <nick> [reason]` | Removes someone from the channel. Without a reason it uses your default kick reason ([`moderation.kickReason`](/reference/settings#moderation.kickReason)), which is empty unless you set one. Alias: `/k`. |
| `/ban <nick or mask> [more…]` | Bans each nick or mask. A nick becomes a mask of the shape you chose in [`moderation.banMask`](/reference/settings#moderation.banMask) (`*!*@their.host` by default). If Vela doesn't know their host, it asks the server first, and bans `nick!*@*` if it can't find out. |
| `/unban <nick or mask> [more…]` | Removes bans, building masks from nicks the same way. |
| `/kickban <nick> [reason]` | Bans someone, then kicks them, with the reason you type or your default one. Alias: `/kb`. |
| `/quiet <nick or mask> [more…]` | Lets someone stay but not talk, the way the network does it: `+q` on Libera.Chat, OFTC and other Solanum-style servers, a mute ban on InspIRCd (`+b m:`) and UnrealIRCd (`+b ~q:`). Elsewhere Vela says it can't. |
| `/unquiet <nick or mask> [more…]` | Removes a quiet. |
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

Several nicks at once (`/op wren ada theo`, `/ban wren ada`) go out in as few lines as the network allows, such as `MODE #vela +ooo wren ada theo`.
