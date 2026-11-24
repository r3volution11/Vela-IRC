---
title: Tab stacks
description: Use Vivaldi-style two-level tab stacks in Vela instead of the sidebar, placed at the top, in the title bar or above the message field, with corners from square to pill.
---

# Tab stacks

Instead of a sidebar, Vela can show your networks and channels as **two rows of tabs**, like [Vivaldi](https://vivaldi.com)'s tab stacks: one row for your networks, and below it the selected network's console, channels and private conversations.

<Screenshot src="/screenshots/preset-tabbed.webp" alt="Tab stacks at the top of the window: a row of networks above a row of channels, with the selected tab merging into the conversation" caption="Tabs at the top." eager />

Turn them on by choosing **Tabs on Top** or **Tabs in Title Bar** in **Settings → Presets** or **View → Layout** (see [Window layout](/guide/presets#window-layout)), or the **Tabs** card under **Navigation** in **Settings → Layout**. The settings in its **Tabs** section apply while you use tabs.

## Placement

Put the tab stacks where they suit you, in **Settings → Layout → Placement** or **View → Layout**:

- **Top** (`top`), just below the channel header. The selected tab merges into the conversation, like a browser tab.
- **Title bar** (`titleBar`), next to the window buttons. Your networks become a compact segmented group with the channel tabs beside them, and the topic moves into a popover behind the **ⓘ** button. This saves the most room.
- **Bottom** (`bottom`), just above the message field, with tabs hanging from the conversation. It isn't one of the window layouts in **Settings → Presets**, which says **Customized** while the tabs are at the bottom.

<Screenshot src="/screenshots/tabs-title-bar.webp" alt="Tab stacks in the title bar: networks in a segmented group beside the window buttons, followed by channel tabs" caption="In the title bar." />

<Screenshot src="/screenshots/tabs-bottom.webp" alt="Tab stacks at the bottom of the window, just above the message field" caption="At the bottom, above the message field." />

### Hide the channel title bar

With tabs at the top or the bottom, the channel title bar shows the channel's name, how many people are in it and the topic. To give that room to the conversation, right-click the title bar and choose **Hide Channel Title Bar**. The tabs move up into the title bar, next to the window buttons, and the topic moves behind the **ⓘ** button.

To bring it back, right-click an empty part of the title bar, before or after the tabs, and choose **Show Channel Title Bar**. The tabs go back where they were, at the top or the bottom. If they've been in the title bar since you opened Vela, they go to the top. Right-clicking a tab still opens the tab's own menu.

**View → Show Channel Title Bar** does the same. It has a checkmark while the title bar is showing. Hiding the title bar is the same as choosing **Title bar** for **Placement**, so **Settings → Layout** shows the change. With the sidebar or the [Focus layout](/guide/presets#focus), the title bar always shows.

With VoiceOver, the channel's name in the title bar has a **Hide Channel Title Bar** action, and the channel tabs in the title bar have **Show Channel Title Bar**.

## Roundness

**Roundness** goes from **Square** (0%) to **Pill** (100%), 35% by default, with a row of sample tabs under it that follows along. From 80% up, tabs become free-standing pills rather than tabs attached to the conversation. In settings.json it's a number from `0` to `1`.

<Screenshot src="/screenshots/tabs-square.webp" alt="Square tabs at the top of the window" caption="Roundness 0: square tabs." />

<Screenshot src="/screenshots/tabs-pill.webp" alt="Pill-shaped tabs at the top of the window" caption="Roundness 1: pills." />

## The network row

The row of network tabs shows each network's connection status and a badge when something there mentions you. With **Network row** set to **Auto** (the default), it's hidden while you're connected to just one network, and that network's name appears on its console tab instead. Choose **Always** to keep it, or turn on **View → Layout → Always Show Server Row**.

## More options

| Setting | What it does |
| --- | --- |
| **Tab height** | From 22 to 40 points (28 by default). Text and padding scale with it. |
| **Unread badges** | Unread and mention counts on tabs. |
| **Close buttons** | A **×** in place of a tab's **#** or avatar when you point at it. Turn it off to close tabs with a middle-click, <kbd>⌘W</kbd> or the tab's menu. |

## Using tabs

- **Click** a tab to switch to it; **right-click** it for the same actions as in the sidebar (mark as read, mute, inline media, translation, Catch Me Up, leave, hide, remove, close).
- **×** takes the place of a channel or conversation tab's **#** or avatar when you point at it. On a channel, it **leaves and removes** it: the tab goes. On a private conversation, it closes the conversation. Only that spot does this: a click anywhere else on the tab switches to it, and even the narrowest tab, or one with a short name like **#dn**, leaves more than half of itself for that. A **middle-click** anywhere on a tab does the same as its **×**.
- **Through a bouncer** (ZNC or soju), a channel's **×** leaves it only in Vela: the bouncer stays in it, **detached**, and keeps its history, and the tab stays, dimmed, so you can join again and catch up. On a detached channel, **×** **hides** the tab; the channel stays on the bouncer. To make **×** remove channels from the bouncer instead, turn on **Closing a channel removes it from the bouncer** in **Settings → Networks → Channels**. See [Through a bouncer](/guide/joining-channels#through-a-bouncer).
- The **×**'s tooltip, and the action VoiceOver offers among each tab's actions, say what it does: **Remove Channel**, **Leave Channel**, **Hide Channel** or **Close Conversation**.
- Vela asks before leaving or removing a channel; see [Leave or remove](/guide/joining-channels#leave-or-remove) to turn that off.
- **Closed a tab by mistake?** <kbd>⌘Z</kbd> puts it back right away, and **File → Reopen Closed Channel** (<kbd>⇧⌘T</kbd>) reopens removed and hidden channels and closed conversations, newest first. **File → Recently Closed** lists the last 20. A reopened tab goes back where it was.
- **File → Close Tab** (<kbd>⌘W</kbd>) does what the selected tab's **×** does, asking first where that asks. The menu item says which: **Remove Channel…**, **Leave Channel…**, **Hide Channel** or **Close Conversation**. **File → Close Window** is <kbd>⇧⌘W</kbd>.
- **Drag** a tab along its row to move it: networks among networks, channels among the network's channels, and private conversations among its conversations. It passes a neighbor once its edge crosses that tab's middle, as in a browser, and <kbd>Esc</kbd> cancels. From the keyboard, <kbd>⌥⇧⌘[</kbd> and <kbd>⌥⇧⌘]</kbd> move the selected tab one place, and <kbd>⌃⌥⌘[</kbd> and <kbd>⌃⌥⌘]</kbd> move its network (also in the **Network** menu). The sidebar uses the same order. See [Arranging networks and channels](/guide/the-window#arranging-networks-and-channels).
- <kbd>⌘1</kbd> to <kbd>⌘9</kbd> jump to the selected network's first nine channels and conversations, in the order their tabs are in. The console tab has no number.
- <kbd>⇧⌘[</kbd> and <kbd>⇧⌘]</kbd> (or <kbd>⌃⇧Tab</kbd> and <kbd>⌃Tab</kbd>) go to the previous and next tab, wrapping around at the ends. <kbd>⌃⌘[</kbd> and <kbd>⌃⌘]</kbd> go to the previous and next network, on the tab you were last on there.
- **With the keyboard alone**, <kbd>⌥⌘1</kbd> (**Go → Focus Tabs**) or <kbd>F6</kbd> puts the keyboard on the selected tab, with a ring in your theme's focus color. <kbd>←</kbd> and <kbd>→</kbd> select the tab beside it, <kbd>Home</kbd> and <kbd>End</kbd> the first and the last, and <kbd>↑</kbd> and <kbd>↓</kbd> go between the network row and the channel row. The keyboard stays on the tabs as you switch. <kbd>Return</kbd> or <kbd>Esc</kbd> goes back to the message box. See [Keyboard shortcuts](/reference/keyboard-shortcuts#tabs).
- The **+** at the end of a row joins a channel or adds a network.

## When tabs don't fit

A row shows every tab before it scrolls, like Vivaldi:

- **Tabs shrink to fit.** When a row's tabs are too wide for the window, the tabs you're not on get narrower, longest names first: short names like **#dn** stay whole, and the longer ones are all cut to the same width.
- **The selected tab is always whole.** Its neighbors make room for it, and they grow and shrink smoothly as you switch tabs.
- **Cut names fade out** on the right instead of ending in "…". The **#**, avatar or **×** and any unread or mention badge stay in full, and the tab's tooltip and VoiceOver always give the whole name.
- **No tab gets narrower than about 58 points** at the default tab height (it grows with **Tab height** and rounder corners). When the tabs wouldn't fit even at that width, the row **scrolls** instead: every tab shows its whole name, the row fades at its edges, and a **»** menu lists every tab. Selecting a tab scrolls it into view.
- Going back from scrolling to shrinking takes a little more room than going the other way, so a row doesn't flick between the two as you resize the window.

The network row in the strip works the same way. In the title bar, networks keep their whole names in their compact group, and it scrolls when there are too many.

The settings on this page are also keys in [settings.json](/reference/settings#tabs): `tabs.placement`, `tabs.roundness`, `tabs.serverRow`, `tabs.height`, `tabs.showUnreadBadges` and `tabs.showCloseButtons`.
