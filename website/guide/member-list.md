---
title: Member list
description: Vela's channel member list, grouped by rank, with filtering, away status, private messages, whois and channel moderation (op, voice, kick, ban, ignore).
---

# Member list

The member list on the right shows everyone in the current channel. Show or hide it with <kbd>⇧⌘M</kbd>, **View → Show Member List**, or the **people** icon in the channel header. Drag its edge to make it wider or narrower.

## Reading the list

- People are grouped by rank, using the prefixes your server defines: **Owners** (`~`), **Admins** (`&`), **Operators** (`@`), **Half-ops** (`%`), **Voiced** (`+`) and **Members**. Each group's header shows how many people are in it and stays pinned while you scroll.
- Each nick has its color from your theme (if **Colored nicknames** is on in **Settings → Messages**), so you can match people to their messages at a glance.
- People who are **away** are dimmed, with a small moon.
- Hover a name to see the full `nick!user@host`.
- Type in **Filter** at the top to find someone in a big channel; <kbd>Esc</kbd> clears it.

## Doing things with people

- **Double-click** someone to open a private conversation.
- **Right-click** someone for **Message**, **Whois**, **Copy Nickname** and **Ignore**.

If you're a channel operator, the right-click menu also has moderation tools:

| Item | Sends |
| --- | --- |
| **Op** / **Deop** | `/op nick` / `/deop nick` |
| **Voice** / **Devoice** | `/voice nick` / `/devoice nick` |
| **Kick** | `/kick nick` |
| **Ban** | `/ban nick`: bans `*!*@their.host` when Vela knows their host, or `nick!*@*` otherwise |
| **Kick and Ban** | both, ban first |

The same [slash commands](/reference/slash-commands) work in the message field, with more options, such as a kick reason.

## Ignoring someone

**Ignore** hides that person's messages on this network, matching their nickname with any user and host. Manage the list (and add masks like `*!*@spammy.example`) in the network's settings under **Ignore list**, or with `/ignore` and `/unignore`.
