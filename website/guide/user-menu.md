---
title: User menu & moderation
description: Vela's user menu for a nick, in the member list and in messages, with Message, Mention, Whois, Ping, CTCP, Ignore, and the op, voice, kick, ban and quiet your rank allows.
---

# User menu & moderation

Right-click someone's nick to see what you can do with them. The same menu opens from:

- the [member list](/guide/member-list);
- a nick in a message, in every layout: the name above a message in Modern (or its avatar), `<nick>` in Classic, and the nick column in Compact columns;
- a nick mentioned in a message's text, when that person is in the channel;
- a message's own menu (right-click elsewhere on the message, or click **…**), under a submenu named after the person who wrote it.

The menu only shows what you can actually do. If your rank in the channel doesn't allow something, it isn't there. Things that need a connection, such as **Whois**, are grayed out while you're offline.

## For everyone

| Item | Does |
| --- | --- |
| **Message** | Opens a private conversation. |
| **Mention** | Puts their nick in the message box: `wren: ` at the start of a message, `wren ` after other text. |
| **Whois** | Shows who they are: host, real name, channels and account. |
| **Ping** | Sends a CTCP PING. When they answer, Vela shows how long it took, such as "Ping reply from wren: 84 ms". |
| **CTCP** | **Version** (which client they use), **Time** (their clock) and **Client Info** (which CTCP requests their client answers). |
| **Invite to** | Your other channels on this network that they aren't in. |
| **Copy Nick** | Copies their nick. |
| **Copy Host Mask** | Copies `nick!user@host`, when Vela knows it. |
| **Ignore** / **Unignore** | Hides their messages on this network, or stops hiding them. See [Ignoring someone](/guide/member-list#ignoring-someone). |

CTCP replies show in the channel or conversation where you asked, as a line you can read: "wren is using HexChat 2.16.2", "wren's time is …". Some clients don't answer CTCP requests at all.

Your own nick has no **Message**, **Mention**, **Ping**, **CTCP**, **Invite**, **Ignore** or moderation items. You can still see your **Whois**, copy your nick and host mask, and give up your own ranks.

## Moderation

If you're a half-op or higher in the channel, the menu also has rank changes and moderation:

| Item | Does |
| --- | --- |
| **Op** / **Deop** | Gives or takes operator status (`+o`). |
| **Halfop** / **Dehalfop** | Gives or takes half-op status (`+h`), on networks that have it. |
| **Voice** / **Devoice** | Gives or takes voice (`+v`). |
| **Make Admin**, **Make Owner** | Higher ranks, on networks that have them (`+a`, `+q`). |
| **Kick** | Removes them from the channel, with your default kick reason. |
| **Kick with Reason…** | Asks for a reason first. Return kicks; Esc cancels. |
| **Ban** | Bans their mask (see [Ban masks](#ban-masks)). |
| **Kick + Ban** | Bans them, then kicks them, with your default reason. |
| **Kick + Ban with Reason…** | The same, asking for a reason first. |
| **Quiet** / **Unquiet** | Lets them stay but not talk. Only on networks where Vela can tell how (see [Quiets](#quiets)). |

### What your rank allows

Ranks come from the network, highest first. Most networks have owner (`~`), admin (`&`), operator (`@`), half-op (`%`) and voice (`+`); Libera.Chat and OFTC have only operator and voice.

- **Changing someone's rank:** an operator or higher can give or take any rank below their own, and operator itself. So an owner can make admins, but an admin can't. A half-op can only voice and devoice.
- **Who:** operators and higher act on people at or below their own rank. Half-ops act only on people below half-op. An operator can't deop or kick an owner or admin.
- **Kick, ban and quiet** need half-op or higher. Never on yourself.
- **Your own ranks** you can always give up.

Vela goes by the channel ranks it sees. IRC operator and services powers aren't taken into account, so if you have them, use [slash commands](/reference/slash-commands#moderation).

### Ban masks

**Ban**, **Kick + Ban**, **Quiet** and `/ban` ban a mask built from the person's `nick!user@host`. Choose its shape in **Settings → Networks → Moderation → Ban mask** ([`moderation.banMask`](/reference/settings#moderation.banMask)):

| Ban mask | Bans | Example |
| --- | --- | --- |
| **Their host** (the default) | anyone from their host | `*!*@user/wren` |
| **Their user and host** | their user name at their host | `*!~wren@host.example` |
| **Their nick** | their nick, from anywhere | `wren!*@*` |

If Vela doesn't know someone's host yet, it asks the server first. If the server doesn't answer, or they aren't online, Vela bans `nick!*@*`.

### Kick reasons

**Kick** and **Kick + Ban** use the reason in **Settings → Networks → Moderation → Kick reason** ([`moderation.kickReason`](/reference/settings#moderation.kickReason)). It's empty by default, which gives no reason; most servers then show your nick. `/kick` and `/kickban` use it too when you don't type a reason.

**Kick with Reason…** and **Kick + Ban with Reason…** open a small sheet with that reason filled in, so you can change it for this kick. Clearing it kicks with no reason.

### Quiets

A quiet keeps someone in the channel without letting them talk. Networks do it in different ways, and Vela uses the one the server announces:

- Libera.Chat, OFTC and other Solanum-style servers have a quiet list: `+q mask`.
- InspIRCd has a mute ban: `+b m:mask`.
- UnrealIRCd has a quiet ban: `+b ~q:mask`.

On other networks **Quiet** isn't shown. **Unquiet** removes a quiet with the same mask Vela would set, so a quiet someone set with another mask needs `/mode`.

## Several people at once

In the member list, **⌘-click** to add or remove people, and **⇧-click** to select everyone between. Right-click anyone in the selection to act on all of them:

- **Copy Nicks**
- rank changes, such as **Op** or **Devoice**
- **Kick**, **Ban**, **Kick + Ban** (with or without a reason), **Quiet** and **Unquiet**

An item shows only if you can do it to everyone selected. Rank changes go out together, as many per line as the network allows (`+ooo wren ada theo`).

## Slash commands

Everything in the menu has a slash command, and the menu sends the same thing:

`/query`, `/whois`, `/ping`, `/version`, `/time`, `/clientinfo`, `/invite`, `/ignore`, `/unignore`, `/op`, `/deop`, `/halfop`, `/dehalfop`, `/voice`, `/devoice`, `/kick`, `/ban`, `/kickban` (or `/kb`), `/quiet` and `/unquiet`.

See [Slash commands](/reference/slash-commands) for their arguments.
