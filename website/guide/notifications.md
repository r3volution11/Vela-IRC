---
title: Notifications & highlights
description: How Vela notifies you about mentions and private messages, how highlight words work globally and per network, muting channels, and the Dock icon's badge, offline mark and bouncing.
---

# Notifications & highlights

## What counts as a highlight

A message **highlights** you when it contains your current nickname, or one of your **highlight words**, as a whole word. Matching ignores case and treats the characters IRC allows in nicks as part of a word, so `doug` matches "doug: hi" and "thanks Doug!" but not "dougie" or "doug_away".

Add highlight words in two places:

- **Settings → Notifications → Highlight words** apply on every network.
- A network's own **Highlight words** (right-click it → **Edit Network…**) apply only there.

Highlighted messages get a tinted background and an accent bar in the conversation, and the channel's name turns the accent color in the sidebar, with a badge counting mentions.

## Notifications

Vela posts a macOS notification for:

- **Highlights**, when someone mentions you.
- **Private messages**, every message in a one-to-one conversation.

You don't get notified about the conversation you're looking at while Vela is in front. Click a notification to jump straight to its conversation. The first time Vela has something to tell you, macOS asks whether to allow notifications.

Turn either kind off, or turn off the sound, in **Settings → Notifications**. Banner style, lock screen previews and Focus filters are up to macOS: click **Open Notification Settings…** to change them.

On macOS 27, you can ask Siri to "reply to this" while a notification from Vela is showing. See [Siri, Shortcuts & Spotlight](/guide/siri-shortcuts#macos-27).

## Muting a channel

Right-click a channel or conversation and choose **Mute**. A muted channel:

- doesn't count toward unread totals, and shows a **bell with a slash** instead of an unread count;
- doesn't notify you, **except when someone mentions you**. Mentions always get through;
- never counts toward the [Dock badge](#dock-badge) and never bounces the Dock icon, mentions included.

Choose **Unmute** to undo it.

## Unread counts

- The sidebar and tabs show how many messages you haven't read in each channel, and a separate accent-colored badge for mentions and private messages.
- The Dock icon shows a badge too: see [The Dock icon](#dock).
- **Mark as Read** (right-click a channel) or **Mark All as Read** (in the **Go** menu) clears them.
- Ask Siri "Check my Vela mentions" to hear where you're mentioned, or run **Check Mentions** in [Shortcuts](/guide/siri-shortcuts#shortcuts).
- <kbd>⌥⇧⌘↓</kbd> jumps to the next channel with unread messages, and <kbd>⌥⇧⌘↑</kbd> to the previous one.

Prefer a calmer sidebar? Turn off **Settings → Layout → Unread counts** and channels show a small dot instead of a number (accent-colored for mentions).

## The Dock icon {#dock}

Vela's Dock icon can show a badge counting what you haven't read, a mark when a network goes offline, and bounce when someone wants you. Choose all of it in **Settings → Notifications → Dock**.

<Screenshot src="/screenshots/settings-dock.webp" alt="Settings → Notifications: the Dock section, with the badge switch on, Count set to Mentions and highlight words and Private messages, Style set to 99+, the offline mark switch on beside a small Vela icon wearing the amber mark, and Bounce the Dock icon set to Off" caption="The Dock section of Settings → Notifications." />

### The badge {#dock-badge}

**Show a badge on the Dock icon** is on by default. Under **Count**, check any combination of:

- **Mentions and highlight words:** unread channel messages that say your nick or one of your [highlight words](#what-counts-as-a-highlight).
- **Private messages:** unread messages in your one-to-one conversations.
- **All channel messages:** every unread message in your channels.

The badge shows the total of what you check, counting each message once: a mention is one of its channel's messages, so with both **Mentions** and **All channel messages** checked it still counts once. Only messages count: actions (`/me`) and notices do, while joins, parts, nick changes and other events never do. [Muted](#muting-a-channel) channels and conversations never count, mentions included.

The default, **Mentions and highlight words** plus **Private messages**, is what Vela has always counted.

**Style** sets how the count reads:

- **99+** (the default): the number, up to 99, then "99+".
- **Exact:** the exact number, however large.
- **Dot:** a dot (•) instead of a number, so you know something's waiting without counting it.

Turn the badge off or on from the [command palette](/guide/command-palette) too, with **Notifications: Show Dock Badge**.

::: tip Badge not showing?
macOS can hide app badges. If Vela's never appears, check that **Badge application icon** is on for Vela in **System Settings → Notifications**.
:::

### When a network is offline {#offline}

When a network drops and isn't back within about 10 seconds, Vela draws a small **amber mark** with an unplugged cable on the bottom-left corner of its Dock icon, opposite the badge. It goes away as soon as every network is connected again.

It's for networks Vela should be connected to: ones that connect automatically, or that you connected since Vela started. It shows while Vela waits to reconnect, too. Networks you disconnect yourself, and networks you remove, never count, and neither does quitting or putting your Mac to sleep. The 10-second wait means a quick reconnect never shows it. Networks on a [bouncer](/guide/bouncers) count by their own connection to the bouncer.

The mark works with any [Dock icon](/customize/app-icon) you choose. Turn it off with **Show when a network is offline**.

### Bouncing {#bounce}

Vela can bounce its Dock icon when a message comes in while it's in the background. It's off by default. Choose **Bounce the Dock icon**:

- **Off** (the default).
- **Once:** one bounce for each message.
- **Until you switch to Vela:** keeps bouncing until you come back.

**Bounce for** chooses which messages: **Mentions and highlight words**, **Private messages**, or both. Switching to Vela stops the bouncing, and muted channels and conversations never bounce the icon.

### In settings.json {#dock-settings-json}

The Dock settings are in [settings.json](/customize/settings-json) under `dock.`:

```jsonc
{
    // Show the badge, and what it counts: any of "mentions", "privateMessages", "channels"
    "dock.showBadge": true,
    "dock.badgeCounts": ["mentions", "privateMessages"],
    // "capped" (99+), "exact" or "dot"
    "dock.badgeStyle": "capped",
    // The amber mark while a network is offline
    "dock.showOffline": true,
    // "off", "once" or "untilActive", for any of "mentions", "privateMessages"
    "dock.bounce": "off",
    "dock.bounceFor": ["mentions", "privateMessages"]
}
```

See [`dock.showBadge`](/reference/settings#dock.showBadge) and the rest in the settings reference.
