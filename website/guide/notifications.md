---
title: Notifications & highlights
description: How Vela notifies you about mentions and private messages, how highlight words work globally and per network, muting channels, and the Dock badge.
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

## Muting a channel

Right-click a channel or conversation and choose **Mute**. A muted channel:

- doesn't count toward unread totals, and shows a **bell with a slash** instead of an unread count;
- doesn't notify you, **except when someone mentions you**. Mentions always get through.

Choose **Unmute** to undo it.

## Unread counts and the Dock

- The sidebar and tabs show how many messages you haven't read in each channel, and a separate accent-colored badge for mentions and private messages.
- The Dock icon shows the total number of mentions and private messages waiting for you.
- **Mark as Read** (right-click a channel) or **Mark All as Read** (in the **Go** menu) clears them.
- <kbd>⌥⇧⌘↓</kbd> jumps to the next channel with unread messages, and <kbd>⌥⇧⌘↑</kbd> to the previous one.

Prefer a calmer sidebar? Turn off **Settings → Layout → Unread counts** and channels show a small dot instead of a number (accent-colored for mentions).
