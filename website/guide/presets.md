---
title: Presets
description: Choose a window layout (Sidebar, Tabs on Top, Tabs in Title Bar or Focus), a message style (Modern, Classic IRC or Columns) and a density (Compact, Standard or Comfortable) in Vela, each on its own. Presets never change your theme.
---

# Presets

**Settings → Presets** sets up Vela's window in three choices that combine freely:

- a **window layout**: where your networks and channels live;
- a **message style**: how each message is laid out;
- a **density**: how much room messages get.

Pick any layout with any style and any density. Each row changes only its own settings, in one go, so choosing a layout never touches your message style, your font, your media settings or anything else you've set. **Presets never change your theme.**

<Screenshot src="/screenshots/settings-presets.webp" alt="Settings → Presets: four window layout cards, three message style cards, the density control and a preview of messages" />

The cards are drawn in your own theme and with your own settings, so each one shows what you'd get. The **Preview** under them is your chat as it looks now, with your theme, font and other message settings.

You can also choose from the **View** menu (**Layout**, **Message Style** and **Density**), from the [command palette](/guide/command-palette) (type "layout", "message style" or "density"), and from the top of **Settings → Appearance**.

## Window layout

| Layout | What you get |
| --- | --- |
| **Sidebar** | Networks and channels in a list on the left, which can fold down to an icon rail (<kbd>⌃⌘S</kbd>). Vela's default. |
| **Tabs on Top** | Browser-style [tab stacks](/guide/tab-stacks) under the channel title bar: a row of networks over a row of channels. |
| **Tabs in Title Bar** | Compact tabs in the title bar, beside the window buttons. The topic moves behind the **ⓘ** button. The most room for the conversation with tabs. |
| **Focus** | No sidebar and no tabs: just the conversation, with the channel's name and topic above it. |

### Focus

Focus takes away everything you use to move between channels, so the conversation has the whole window. To switch channels:

- press <kbd>⌘P</kbd> (or <kbd>⌘K</kbd>) for **Go to Conversation…** and type a few letters of the channel;
- press <kbd>⌘1</kbd>–<kbd>⌘9</kbd> for the network's first nine channels and conversations, in the order the tabs would show them;
- use **Go → Next Unread** (<kbd>⇧⌥⌘↓</kbd>), **Next Conversation** (<kbd>⌥⌘↓</kbd>) and the rest of the **Go** menu.

With no sidebar or tabs to show unread counts, **Go to Conversation…** shows them instead, with a badge for mentions, and the [Dock icon's badge](/guide/notifications#dock-badge) and notifications tell you about new messages. **Go → Focus Sidebar** (<kbd>⌥⌘1</kbd>) has nothing to go to in Focus, and F6 goes round the messages, the message box and the member list.

### Tabs at the bottom

Tabs can also sit at the bottom, above the message box (**View → Layout → Tabs at Bottom**, or **Settings → Layout → Placement**). It isn't one of the four cards, so the Window layout row says **Customized** while they're there.

## Message style

| Style | What you get |
| --- | --- |
| **Modern** | The name and time on one line, the message below, and one name for a run of messages from the same person, like Slack or Discord. Vela's default. |
| **Classic IRC** | `[time] <nick> message` on one line, in a monospaced font, like [Textual](https://www.textualapp.com) or [irssi](https://irssi.org). |
| **Columns** | The time, a right-aligned column of names, then the message, like [WeeChat](https://weechat.org). |

A style sets the [message layout](/guide/messages-and-layouts) and whether chat uses the monospaced font. Classic IRC turns the monospaced font on; Modern and Columns turn it off. Everything else about messages, like timestamps, avatars, nick colors and join and part messages, stays as you have it.

## Density

**Compact**, **Standard** and **Comfortable** set the space between the lines of a message and the space between messages together:

| Density | Between lines | Between messages |
| --- | --- | --- |
| **Compact** | 2 points | 4 points |
| **Standard** | 4 points | 12 points |
| **Comfortable** | 6 points | 18 points |

Standard is Vela's default. Compact fits the most messages on screen while keeping Modern's groups apart; Comfortable is for easy reading. For tighter spacing still, set it in **Settings → Messages** (the row then shows **Customized**).

**Density never changes your font size**, so it never undoes a size you chose yourself. Change that with **View → Bigger** (<kbd>⌘+</kbd>) and **Smaller** (<kbd>⌘−</kbd>), or in **Settings → Messages**.

## Customized

Each row shows which choice your settings match. If you've changed one of a row's settings yourself, say the message spacing in **Settings → Messages**, no card is selected and the row says **Customized**, with what's different and a link to where you can fine-tune it.

Picking a card again resets just that row's settings and leaves the other rows alone. Your own changes elsewhere, like your font size, media and unread settings, are never touched.

## What each choice sets

Every choice writes only the settings in its row. A dash means it leaves that setting alone. Click a setting to read what it does.

<!--@include: ../_generated/presets.md-->

A choice that matches Vela's default is removed from [settings.json](/customize/settings-json) rather than written, so it keeps following the default. Choosing **Sidebar**, **Modern** and **Standard** on a new install leaves settings.json as it was.

## Coming from an earlier version

Vela 1.5 replaced the four one-click presets (Classic IRC, Modern Chat, Tabbed and Focus) with these three rows. Updating changes nothing on screen: your settings stay exactly as they were, and each row shows the choice they match.

| If you used | Window layout | Message style | Density |
| --- | --- | --- | --- |
| **Classic IRC** | Sidebar | Classic IRC | Customized (1 and 2 points) |
| **Modern Chat** | Sidebar | Modern | Standard |
| **Tabbed** | Tabs on Top | Modern | Customized (2 and 8 points) |
| **Focus** | Tabs in Title Bar | Columns | Customized (2 and 3 points) |

The old presets also set things like the font size, media sizes and how unread messages show. Those stay as they were; change them in **Settings → Messages** and **Settings → Media**. If you used the old **Focus** preset, the new **Focus** layout goes further: no tabs at all.

## Making your own

There's no "save as preset", but every value is a key in [settings.json](/customize/settings-json), so you can keep your favorite setup in a file and paste it back whenever you like.
