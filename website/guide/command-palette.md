---
title: Command palette & quick switcher
description: Run any Vela command from the keyboard with the command palette (⇧⌘P), jump to any channel or conversation with the quick switcher (⌘P or ⌘K), and preview themes live with Select Theme (⌃⌘T).
---

# Command palette & quick switcher

Vela has a VS Code-style palette that floats at the top of the window. It opens in three ways:

| Press | To |
| --- | --- |
| <kbd>⇧⌘P</kbd> | Run any command |
| <kbd>⌘P</kbd> or <kbd>⌘K</kbd> | Go to a channel, conversation or network console |
| <kbd>⌃⌘T</kbd> | Select a theme, previewing each one live |

Start typing to filter; matching is fuzzy, so `vl` finds `#vela`. Move with <kbd>↑</kbd> <kbd>↓</kbd> (or <kbd>⌃P</kbd> <kbd>⌃N</kbd>), press <kbd>Return</kbd> to choose and <kbd>Esc</kbd> to close. Pressing the same shortcut again also closes it.

## Go to a conversation

<kbd>⌘P</kbd> (or <kbd>⌘K</kbd>, if your fingers know Slack and Discord) lists every channel, private conversation and network console, with unread and mention badges. With nothing typed, the ones you visited most recently come first.

Add the network's name to narrow things down: `vela libera` finds `#vela` on Libera.Chat. Type `>` to switch to commands, and <kbd>Backspace</kbd> in the empty field to switch back.

## Run a command

<kbd>⇧⌘P</kbd> lists everything you can do, named by category, such as **View: Toggle Member List** or **Preset: Focus**. Recently used commands come first, the current choice of a setting is checked, and shortcuts are shown on the right. Commands that don't apply right now are hidden.

| Category | Commands |
| --- | --- |
| **View** | Toggle Sidebar, Toggle Member List, Toggle Full Screen |
| **Navigation** | Use Sidebar, Use Tabs |
| **Tabs** | Move to Top, Move to Title Bar, Move to Bottom, Always Show Server Row |
| **Layout** | Classic, Modern Grouped, Compact Columns |
| **Preset** | Classic IRC, Modern Chat, Tabbed, Focus |
| **Chat** | Toggle Timestamps, Toggle Monospace Font, Toggle Nick Colors, Toggle Avatars, Toggle mIRC Formatting, Show / Collapse / Hide Join/Part Messages |
| **Media** | Toggle Inline Images, Toggle Link Previews, Use Full Previews, Use Compact Previews |
| **Text** | Bigger, Smaller, Actual Size |
| **Theme** | Select Theme…, Toggle Match System Appearance, Open Theme Editor, Import Theme…, Reveal Themes Folder |
| **Settings** | Open Settings, Open settings.json |
| **Go** | Go to Conversation…, Previous / Next Conversation, Previous / Next Unread, Focus Input |
| **Buffer** | Mark as Read, Mark All as Read, Mute / Unmute, Enable / Disable Inline Media, Close |
| **Channel** | Join…, Leave _#channel_ |
| **Network** | Add Network…, and Connect, Disconnect, Reconnect, Edit… and Remove… for each network |

Commands also match words that aren't in their names: "nick list" finds Toggle Member List, and "zoom in" finds Bigger.

## Select a theme

<kbd>⌃⌘T</kbd> (or **Theme → Select Theme…**) lists every theme. As you move through the list, the whole app switches to the highlighted theme, so you can see it on your own conversations. **Return** keeps it; **Esc** goes back to the theme you had.

Your own themes are marked **custom**, and the theme in use is marked **current**. If **Match System Appearance** is on, the theme you pick becomes your theme for the current mode (dark or light) and matching stays on. See [Choosing a theme](/customize/themes).
