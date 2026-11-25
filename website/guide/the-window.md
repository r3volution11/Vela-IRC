---
title: The window
description: A tour of Vela's main window, the sidebar and its collapsible rail, tab stacks, arranging networks and channels, the conversation header, the member list and unread badges.
---

# The window

<Screenshot src="/screenshots/preset-modern.webp" alt="Vela's main window: the sidebar on the left, the conversation in the middle and the member list on the right" caption="The sidebar, the conversation and the member list, in Palenight." eager />

Vela's window has up to three panes: **navigation** on the left (or tabs along the top, or none in the Focus layout), the **conversation** in the middle and the **member list** on the right. Every part of it, down to the title bar, is drawn with your [theme](/customize/themes).

## Sidebar, tabs or Focus {#sidebar-or-tabs}

Choose how you move between networks and channels with a [window layout](/guide/presets#window-layout) in **Settings → Presets** or **View → Layout**, or with the **Sidebar**, **Tabs** and **Focus** cards under **Navigation** in **Settings → Layout**:

- **Sidebar** (the default) suits many networks and channels.
- **Tabs on Top** and **Tabs in Title Bar** give you [Vivaldi](https://vivaldi.com)-style [tab stacks](/guide/tab-stacks), great for one network and a few channels.
- **Focus** shows neither, just the conversation. Switch channels with **Go to Conversation…** (<kbd>⌘P</kbd>) or <kbd>⌘1</kbd>–<kbd>⌘9</kbd>. See [Focus](/guide/presets#focus).

## The sidebar

Each network has a header with a status dot (connected, connecting or offline) and its name. Click the header to open that network's server console, or click its chevron to fold its channels away; a folded network still shows a badge when something inside it needs you.

Under each network are its channels (`#`) and private conversations. A channel's name tells you what's waiting:

- **Brighter text** means unread messages; a **number** counts them.
- An **accent-colored badge** counts mentions of you and private messages.
- A **bell with a slash** means the channel is muted.
- **Dimmed** names are channels you've left (or left on a [bouncer](/guide/bouncers), detached) and networks that are offline.

Drag the sidebar's edge to resize it, and drag networks and channels to [rearrange them](#arranging-networks-and-channels). The **+** at the bottom adds a network or joins a channel. Right-click anything for more: mark as read, mute, inline media, [automatic translation](/guide/apple-intelligence#automatic), [Catch Me Up](/guide/apple-intelligence#catch-me-up), leave, hide or remove a channel (see [Leave or remove](/guide/joining-channels#leave-or-remove)), close a conversation, and network actions. <kbd>⌘W</kbd> closes the selected channel or conversation as a tab's **×** would, and the **File** menu item says what it will do (**Remove Channel…**, for example). <kbd>⇧⌘W</kbd> closes the window.

## The rail

<Screenshot src="/screenshots/sidebar-rail.webp" alt="The collapsed sidebar: a thin rail with network initials, channel tiles and the window buttons stacked vertically" caption="Collapsed to a rail. The window buttons stack vertically to fit." />

Collapse the sidebar with <kbd>⌃⌘S</kbd>, **View → Collapse Sidebar** or the sidebar button at its top-right corner, and it becomes a thin rail:

- Each network is a **circle with its initial** and a status dot.
- Each channel is a **tile with its initials** (`#swift-lang` becomes **SL**), and conversations show the person's initial.
- A short **pip** on the left edge marks unread activity, a tall **bar** marks the selected channel, and a badge counts mentions.

**Hover the rail** for a moment and the full sidebar floats over the conversation without changing the layout. Move away and it tucks back in. Click the sidebar button at the bottom of the rail to expand it for good.

The red, yellow and green window buttons stack vertically when the rail is showing and sit side by side otherwise. Double-clicking an empty part of the title strip zooms or minimizes the window, following your setting in **System Settings → Desktop & Dock**.

## Arranging networks and channels

Drag a network, channel or conversation to put it where you want it. This works in the sidebar, the rail, the [tab bars](/guide/tab-stacks) and **Settings → Networks**, and the order is the same everywhere. The others slide aside to show where it will land; let go to drop it, or press <kbd>Esc</kbd> to put it back. From the keyboard, **Network → Move Channel Up** and **Move Channel Down** (<kbd>⌥⇧⌘[</kbd> and <kbd>⌥⇧⌘]</kbd>) move the selected channel or conversation, and **Move Network Up** and **Move Network Down** (<kbd>⌃⌥⌘[</kbd> and <kbd>⌃⌥⌘]</kbd>) move its network. With tabs they say Left and Right. In [Focus](/guide/presets#focus), with no sidebar or tabs to move them in, they're dimmed.

- **Networks** move among each other. Networks provided by a [soju bouncer](/guide/bouncers#soju) stay under their bouncer and move among themselves there; moving the bouncer takes them along.
- **Channels** always come before **private conversations**. A channel moves among its network's channels, and a conversation among its conversations.
- **New channels and conversations** go at the end of their group, like a new browser tab.
- **Auto-join follows.** Reordering a network's channels reorders its **Channels** list (the ones Vela joins when it connects) to match.

To put a network's channels and conversations back in alphabetical order, right-click the network and choose **Sort Channels A–Z** (it's also in the **Network** menu), or run **Network: Sort Channels A–Z** from the [command palette](/guide/command-palette) (<kbd>⇧⌘P</kbd>) for the network you're in.

With VoiceOver or Full Keyboard Access, use the **Move Up** and **Move Down** actions (**Move Left** and **Move Right** on tabs) instead of dragging.

## The conversation

The header shows the channel name, how many people are in it and the topic. On the right:

- **Media** (picture icon) turns inline images and previews on or off for this channel. See [Inline media & privacy](/guide/inline-media).
- **Members** (people icon) shows or hides the member list (<kbd>⇧⌘M</kbd>).

With [tabs](/guide/tab-stacks) at the top or the bottom, you can hide the header. Right-click it and choose **Hide Channel Title Bar**, or use **View → Show Channel Title Bar**. The tabs move up into the title bar, and the topic moves behind the **ⓘ** button. See [Hide the channel title bar](/guide/tab-stacks#hide-the-channel-title-bar).

When you're offline or connecting, the header says so, and the message field offers a **Reconnect** button. If you've left a channel, it offers **Join** instead. Otherwise it ends with a smiley, which opens the [emoji picker](/guide/emoji-and-gifs), and a send button, unless you've hidden it. See [Sending messages](/guide/sending-messages).

Messages are separated by **day dividers**. A **New** marker shows where you stopped reading (in a busy channel, with a **Catch me up** button that [summarizes what you missed](/guide/apple-intelligence#catch-me-up)), and when you've scrolled up, a **Jump to present** button takes you back to the newest messages. See [Messages & layouts](/guide/messages-and-layouts).

The messages work from the keyboard too. Press <kbd>⌥⌘2</kbd> to select one, move with <kbd>↑</kbd> and <kbd>↓</kbd>, and press <kbd>R</kbd> to reply, <kbd>E</kbd> to react or <kbd>Space</kbd> for all its actions; <kbd>Esc</kbd> goes back to the message field. See [The messages](/reference/keyboard-shortcuts#the-messages).

## The member list

The list of people in the channel, grouped by rank. See [Member list](/guide/member-list). Drag its edge to resize it.

## Moving around

| To | Press |
| --- | --- |
| Go to any channel or conversation | <kbd>⌘P</kbd> or <kbd>⌘K</kbd> |
| Previous / next tab of this network (wraps around) | <kbd>⇧⌘[</kbd> / <kbd>⇧⌘]</kbd> or <kbd>⌃⇧Tab</kbd> / <kbd>⌃Tab</kbd> |
| Previous / next network, back where you were on it | <kbd>⌃⌘[</kbd> / <kbd>⌃⌘]</kbd> |
| Previous / next conversation, across networks | <kbd>⌥⌘↑</kbd> / <kbd>⌥⌘↓</kbd> |
| Previous / next with unread messages | <kbd>⌥⇧⌘↑</kbd> / <kbd>⌥⇧⌘↓</kbd> |
| This network's channels and conversations 1–9 | <kbd>⌘1</kbd> … <kbd>⌘9</kbd> |
| Focus the sidebar or tabs, the messages, the message box or the member list | <kbd>⌥⌘1</kbd>, <kbd>⌥⌘2</kbd>, <kbd>⌥⌘3</kbd> (or <kbd>⌘L</kbd>), <kbd>⌥⌘4</kbd> |
| Go round those four, forward / back | <kbd>F6</kbd> / <kbd>⇧F6</kbd> |
| Pick a message, to reply, react, copy… | <kbd>⌥⌘2</kbd>, then <kbd>↑</kbd> <kbd>↓</kbd> |
| Scroll the messages from the message box | <kbd>Page Up</kbd> <kbd>Page Down</kbd> <kbd>Home</kbd> <kbd>End</kbd> |

All of them are listed in [Keyboard shortcuts](/reference/keyboard-shortcuts).

### With the keyboard alone

Each part of the window can have the keyboard. **Go → Focus Sidebar** (or **Focus Tabs**), **Focus Messages**, **Focus Message Box** and **Focus Member List** go straight to one, and <kbd>F6</kbd> goes round them. The row or tab the keyboard is on has a ring in your theme's focus color.

- **In the sidebar or the rail**, <kbd>↑</kbd> and <kbd>↓</kbd> select as they go, like Mail's mailbox list, and <kbd>Home</kbd> and <kbd>End</kbd> go to the first and the last. <kbd>←</kbd> goes from a channel to its network, and on a network folds its channels away. <kbd>→</kbd> shows them again. Type the first letters of a name to go to it.
- **In the tabs**, <kbd>←</kbd> and <kbd>→</kbd> select the tab beside, and <kbd>↑</kbd> and <kbd>↓</kbd> go between the network row and the channel row.
- **In the member list**, the keys move a highlight. See [Member list](/guide/member-list#with-the-keyboard).

<kbd>Return</kbd> or <kbd>Esc</kbd> goes back to the message box. Switching channels from the sidebar or the tabs leaves the keyboard there until you do.

## The Dock icon

Vela's Dock icon shows a badge with the number of mentions and private messages you haven't read yet, and a small amber mark when a network has gone offline. You can count every channel message instead, show a dot rather than a number, or have the icon bounce for mentions and private messages: see [The Dock icon](/guide/notifications#dock) in Notifications.
