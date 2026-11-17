---
title: First launch
description: What you see the first time you open Vela, how to add your first IRC network, and how to pick a preset and theme that suit you.
---

# First launch

The first time you open Vela, the window says **Welcome to Vela** and offers one button: **Add Network…**. Vela doesn't connect anywhere until you add a network.

## 1. Add a network

Click **Add Network…** (or press <kbd>⇧⌘N</kbd>). Choose a well-known network such as Libera.Chat or OFTC from the **Presets** menu, check the nickname (Vela suggests one from your Mac user name), and click **Add Network**. Vela connects right away.

[Adding a network](/guide/adding-a-network) explains every field, and [Connecting through a bouncer](/guide/bouncers) covers ZNC and soju.

## 2. Join some channels

Press <kbd>⌘J</kbd>, type a channel name such as `#libera` (Libera.Chat's help channel), and press Return. You can also type `/join #channel` in the message field. See [Joining channels](/guide/joining-channels).

## 3. Make it yours (optional)

Out of the box, Vela follows your Mac's light or dark appearance with the **Palenight** and **Lighter** themes, uses a sidebar for navigation and groups messages under each sender's name. If that's not you:

- **Try a preset.** Open **Settings** (<kbd>⌘,</kbd>) → **Presets** and pick Classic IRC, Modern Chat, Tabbed or Focus. Presets change layout, density and media, never your theme. See [Presets](/guide/presets).
- **Pick a theme.** Press <kbd>⌃⌘T</kbd> and move through the list with the arrow keys. Each theme previews live; Return keeps it. See [Choosing a theme](/customize/themes).
- **Fine-tune anything** in Settings. Every change applies immediately, and every option is also a key in [settings.json](/customize/settings-json).

## A quick tour of Settings

Settings (<kbd>⌘,</kbd>) has eight panes:

| Pane | What's there |
| --- | --- |
| **Presets** | The four one-click setups, and which one matches your current settings. |
| **Appearance** | The theme gallery, light/dark matching, the theme editor and theme import. |
| **Layout** | Sidebar or tabs, tab placement and roundness, sidebar and member list sizes. |
| **Messages** | Message layout, fonts, spacing, timestamps, join/part display, nick colors and avatars. |
| **Media** | Link preview size, video players, images, the adult-site filter, blurring and site rules. |
| **Networks** | Add, edit, connect and remove networks and bouncers. |
| **Notifications** | Highlights, private messages, sounds and your highlight words. |
| **Advanced** | Typing indicators, spell checking, reconnecting, history, and every setting in one searchable list. |

::: tip Want to look around first?
Vela has a demo mode with sample networks and conversations that never connects anywhere. Quit Vela, then open Terminal and run:

```sh
open -a Vela --args --demo
```

Quit Vela to leave demo mode. Settings you change in the demo aren't saved.
:::
