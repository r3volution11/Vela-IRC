---
title: Importing VS Code themes
description: Import any VS Code color theme into Vela from a .json theme file or a whole .vsix extension, and how VS Code colors map onto Vela's tokens.
---

# Importing VS Code themes

Vela's themes are modeled on [VS Code](https://code.visualstudio.com)'s, so almost any VS Code color theme makes a good Vela theme. Import one with **Theme → Import Theme…** or **Settings → Appearance → Import Theme…**, and Vela switches to it right away.

## What you can import

- **A VS Code color theme file**: `something-color-theme.json`. Comments are fine.
- **A whole extension**: a `.vsix` file. Every color theme in it is imported, named the way the extension names them, and themes that build on a base file are followed.
- **A Vela theme** (`.json` or `.jsonc`), which is added to your Themes folder. Import saves it in Vela's own format, so its comments and formatting aren't kept; to keep them, put the file in the Themes folder yourself.

Imported themes are written into your Themes folder as ordinary Vela themes, so you can [edit them](/customize/theme-editor) afterwards. If a name clashes with a theme you already have, the import gets " (Imported)" added.

## Where to find theme files

- **The Visual Studio Marketplace.** On a theme's page, **Download Extension** saves its `.vsix`.
- **[Open VSX](https://open-vsx.org).** Each extension has a download link for its `.vsix`.
- **Your own VS Code.** Installed extensions are in `~/.vscode/extensions/`; a theme's `.json` files are usually in its `themes` folder.
- **GitHub.** Most themes publish their source, often with ready-made `.json` theme files.

## How colors are mapped

Vela reads the theme's workbench colors and maps them onto its own tokens. Anything it can't map is derived, like any Vela theme.

| VS Code | Vela |
| --- | --- |
| `editor.background` / `editor.foreground` | `chat.*` and `window.*` |
| `sideBar.background` / `foreground` / `border` | `sidebar.*` |
| `sideBarSectionHeader.foreground` | `sidebar.headerForeground` |
| `list.activeSelectionBackground` / `Foreground` | `sidebar.activeBackground` / `Foreground` |
| `list.hoverBackground` | `sidebar.hoverBackground` |
| `activityBar.*`, `activityBarBadge.*` | `rail.*` |
| `titleBar.activeBackground` / `activeForeground` / `border` | `titleBar.*` |
| `input.*`, `button.*`, `focusBorder`, `scrollbarSlider.*` | `input.*`, `button.*`, `focusBorder`, `scrollbar.*` |
| `badge.*` | sidebar unread badges |
| `editorWidget.*`, `quickInput.*` | `popover.*` |
| `textLink.foreground` | `chat.link` |
| `editorLineNumber.foreground` | `chat.timestamp` |
| `editor.findMatchHighlightBackground` (or `wordHighlightBackground`) | `chat.highlightBackground` |
| `editor.selectionBackground` | `chat.selectionBackground` |
| `textCodeBlock.background` | `chat.codeBackground` |
| `terminal.ansi*` | `ircColors` 0–15 and the nick palette |

A few details:

- **The accent** is the first saturated, visible color among the activity bar badge, the active activity bar border, the primary button and the focus border.
- **Light or dark** comes from the file, the extension's `uiTheme`, or the brightness of the editor background.
- **Terminal colors become [mIRC](https://www.mirc.com) colors** the way terminal IRC clients map them, and the **nick palette** uses the theme's colored terminal entries, topped up from its syntax colors when there aren't enough.
- **Readability comes first.** Imported text colors that would be hard to read in Vela (VS Code line numbers are often deliberately faint) are dropped so Vela derives a readable one, and accent-colored text is lightened or darkened to reach a 4.5:1 contrast ratio.

After importing, open the [theme editor](/customize/theme-editor) and check the **Contrast issues** filter for anything worth a tweak.
