---
title: Member list
description: Vela's channel member list, grouped by rank, with filtering, away status, selecting several people, and the user menu for messages, whois and moderation.
---

# Member list

The member list on the right shows everyone in the current channel. Show or hide it with <kbd>⇧⌘M</kbd>, **View → Show Member List**, or the **people** icon in the channel header. Drag its edge to make it wider or narrower.

## Reading the list

- People are grouped by rank, using the prefixes your server defines: **Owners** (`~`), **Admins** (`&`), **Operators** (`@`), **Half-ops** (`%`), **Voiced** (`+`) and **Members**. Each group's header shows how many people are in it and stays pinned while you scroll.
- Each nick has its color from your theme (if **Colored nicknames** is on in **Settings → Messages**), the same one their messages show, so you can match people to their messages at a glance. Yours is in your own nick's color, as on your messages.
- People who are **away** are dimmed, with a small moon.
- Hover a name to see the full `nick!user@host`.
- Type in **Filter** at the top to find someone in a big channel; <kbd>Esc</kbd> clears it.

## Doing things with people

- **Double-click** someone to open a private conversation.
- **Click** someone to select them. **⌘-click** adds or removes people, and **⇧-click** selects everyone between.
- **Right-click** someone for the [user menu](/guide/user-menu): **Message**, **Mention**, **Whois**, **Ping**, **CTCP**, **Invite to**, **Copy Nick**, **Copy Host Mask** and **Ignore**.

If you're a half-op or higher in the channel, the menu also has the rank changes and moderation your rank allows: **Op**, **Voice** and the others, **Kick**, **Ban**, **Kick + Ban** (each with or without a reason) and, on networks that support it, **Quiet**. Anything you can't do isn't shown. See [Moderation](/guide/user-menu#moderation) for the rules.

Right-click anyone in a selection of several people to act on all of them: **Copy Nicks**, rank changes, kick, ban and quiet. An item shows only if you can do it to everyone selected.

The same menu opens when you right-click a nick in a message, and the same [slash commands](/reference/slash-commands) work in the message field.

## Ignoring someone

**Ignore** hides that person's messages on this network, matching their nickname with any user and host. When someone is already ignored, the menu says **Unignore** instead, which removes the entries that match them. Manage the list (and add masks like `*!*@spammy.example`) in the network's settings under **Ignore list**, or with `/ignore` and `/unignore`.
