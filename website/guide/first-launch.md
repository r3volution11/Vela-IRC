---
title: First launch
description: What you see the first time you open Vela, how to add your first IRC network, and how to pick a layout, message style and theme that suit you.
---

# First launch

The first time you open Vela, the window says **Welcome to Vela** and offers one button: **Add Network…**. Vela doesn't connect anywhere until you add a network.

<Screenshot src="/screenshots/welcome-palenight.webp" light="/screenshots/welcome-lighter.webp" alt="Vela's window on first launch: an empty sidebar, and a river winding through a mountain valley, at night with a full moon, stars and a stargazer at a telescope in a dark theme, or by day with the sun, clouds, birds and a kayaker in a light theme, above “Welcome to Vela”, “Add an IRC network or bouncer to get started.” and an Add Network… button" caption="The welcome screen in Palenight, or in Lighter while this site is light." />

Above the welcome is a picture of a river winding through a mountain valley, drawn in your theme's colors. With a dark theme it's night, with a full moon, Vela's stars and a stargazer at a telescope. With a light theme it's day, with a kayaker paddling toward the sun. Later, when no conversation is open, the same picture says **Pick a conversation**.

## 1. Add a network

Click **Add Network…** (or press <kbd>⇧⌘N</kbd>). Choose a well-known network such as Libera.Chat or OFTC from the **Presets** menu, check the nickname (Vela suggests one from your Mac user name), and click **Add Network**. Vela connects right away.

[Adding a network](/guide/adding-a-network) explains every field, and [Connecting through a bouncer](/guide/bouncers) covers [ZNC](https://znc.in) and [soju](https://soju.im).

## 2. Join some channels

Press <kbd>⌘J</kbd>, type a channel name such as `#libera` (Libera.Chat's help channel), and press Return. You can also type `/join #channel` in the message field. See [Joining channels](/guide/joining-channels).

## 3. Make it yours (optional)

Out of the box, Vela follows your Mac's light or dark appearance with the **Palenight** and **Lighter** themes, uses a sidebar for navigation and groups messages under each sender's name. If that's not you:

- **Pick a layout and a style.** Open **Settings** (<kbd>⌘,</kbd>) → **Presets** and choose a window layout (Sidebar, Tabs on Top, Tabs in Title Bar or Focus), a message style (Modern, Classic IRC or Columns) and a density (Compact, Standard or Comfortable), in any combination. Presets never change your theme. See [Presets](/guide/presets).
- **Pick a theme.** Press <kbd>⌃⌘T</kbd> and move through the list with the arrow keys. Each theme previews live; Return keeps it. Then try a different [accent color](/customize/themes#accent-color) or a quieter [message box border](/customize/themes#message-box-border) in **Settings → Appearance**. See [Choosing a theme](/customize/themes).
- **Fine-tune anything** in Settings. Every change applies immediately, and every option is also a key in [settings.json](/customize/settings-json). To find a setting fast, type in the **Search** field at the top of the Settings sidebar.

## A quick tour of Settings

Settings (<kbd>⌘,</kbd>) has thirteen panes:

| Pane | What's there |
| --- | --- |
| **Presets** | A window layout, a message style and a density, each chosen on its own, with a live preview. |
| **Appearance** | The theme gallery, the theme's accent color, the message box border, light/dark matching, the theme editor and theme import. |
| **Layout** | Sidebar, tabs or Focus, tab placement and roundness, sidebar and member list sizes. |
| **Messages** | Message layout, fonts, spacing, timestamps, join/part display, nick colors and avatars; typing: spelling, autocorrect, Writing Tools, typing indicators and the send button; whether message history is saved, and for how long; and chat logs. |
| **Media** | Link preview size, video players, images, the adult-site filter, blurring and site rules. |
| **Networks** | Add, edit, connect and remove networks and bouncers, whether to reconnect automatically, whether to ask before leaving or removing a channel, and moderation defaults. |
| **Notifications** | Highlights, private messages and sounds; the Dock icon's badge, offline mark and bouncing; and your highlight words. |
| **Intelligence** | Catch me up and Recap summaries (and the model each uses), translation and Writing Tools. See [Apple Intelligence](/guide/apple-intelligence). |
| **AI Providers** | Where Catch me up and Recap's models come from: Apple Intelligence's status, the default model, OpenAI, Anthropic or Google Gemini with your own key, and Ollama or LM Studio on your Mac. See [AI providers](/guide/ai-models). |
| **AI Privacy** | What's sent to AI models and where, and which providers may be sent messages. See [AI privacy](/guide/ai-privacy). |
| **Integrations** | Alfred, Raycast, Shortcuts and Siri, Spotlight, and AppleScript and `vela://` links: what's installed and how to set each up. See [Integrations](/guide/integrations). |
| **Updates** | Whether Vela is up to date, **Check for Updates**, and whether to check for and install new versions automatically. See [Updates](/guide/updates). |
| **Advanced** | The [settings editor](/customize/settings-editor): every setting in one searchable list, and settings.json itself. |

::: tip Want to look around first?
Vela has a demo mode with sample networks and conversations that never connects anywhere. Quit Vela, then open Terminal and run:

```sh
open -a Vela --args --demo
```

Quit Vela to leave demo mode. Settings you change in the demo aren't saved, and the demo shows only the built-in themes: it never reads or changes your Themes folder.
:::
