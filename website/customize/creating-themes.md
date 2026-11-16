---
title: Creating themes
description: Write your own Vela theme as a JSON file of color tokens, with live reload, editor autocomplete from the JSON Schema, derived defaults, include, nick colors and mIRC colors.
---

# Creating themes

A Vela theme is a JSON file of named color **tokens**, modeled on VS Code color themes. If you've ever tweaked `workbench.colorCustomizations`, you already know how it works. You can build one in the [theme editor](/customize/theme-editor), or write it by hand as described here.

::: info The full guide
This page is a summary. The complete theme authoring guide, [THEMES.md](https://github.com/r3volution11/Vela-IRC/blob/main/docs/THEMES.md), lives with Vela's source. Every token is listed in the [theme token reference](/reference/theme-tokens).
:::

## Quick start

1. Choose **Theme → Reveal Themes Folder** and create a file called `my-theme.json`.
2. Paste this and save:

   ```jsonc
   {
     "$schema": "https://raw.githubusercontent.com/r3volution11/Vela-IRC/main/schemas/vela-theme.schema.json",
     "name": "My Theme",
     "type": "dark",
     "include": "Palenight",
     "colors": {
       "accent": "#FF8A65",
       "chat.background": "#1E2030"
     }
   }
   ```

3. Pick **My Theme** with <kbd>⌃⌘T</kbd>. Keep the file open in your editor: every time you save, Vela reloads it instantly.

Thanks to `"$schema"`, editors such as VS Code, Zed and Nova autocomplete every token name, show its description and default, and flag typos and malformed colors as you type.

## Where themes live

Vela is sandboxed, so the Themes folder is inside its container:

```text
~/Library/Containers/io.github.r3volution11.Vela/Data/Library/Application Support/Vela/Themes
```

Every `.json` or `.jsonc` file in it is a theme. Its **id** is the file name without the extension (`my-theme`) and its **name** is the `name` field; settings accept either, in any case. If you save a file with a mistake in it, Vela keeps the last version that worked and reports the problem in **Settings → Appearance**.

## The theme file

Comments (`//` and `/* */`) and trailing commas are allowed.

| Field | Required | Meaning |
| --- | --- | --- |
| `$schema` | no | Schema URL, for autocomplete and validation in your editor. |
| `name` | yes | Display name. Must be unique among your themes. |
| `type` | yes | `"dark"` or `"light"`. Picks the token defaults and how macOS draws menus and alerts. |
| `include` | no | Name or id of another theme to start from. |
| `author`, `description` | no | Shown in the theme picker. |
| `colors` | no | Token → color. Anything you leave out is derived. |
| `nickColors` | no | Array of colors used for nicknames. |
| `ircColors` | no | mIRC color index (`"0"`–`"98"`) → color. |
| `vibrancy` | no | `"none"` (default), `"sidebar"` or `"window"`, to let macOS draw translucent Liquid Glass materials. |

Colors are hex strings: `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA`. Transparency works everywhere, which keeps hover and selection highlights subtle on any background (`"chat.hoverBackground": "#FFFFFF0A"`).

## How defaults work {#how-defaults-work}

Most token defaults are **formulas over other tokens**, so a convincing theme can start with three colors:

```jsonc
{ "name": "Three Colors", "type": "dark",
  "colors": { "window.background": "#20242C", "window.foreground": "#D8DEE9", "accent": "#E5A050" } }
```

Everything else follows: the sidebar is a slightly darker tint of the window, the member list matches the sidebar, links and your own nick use the accent, and badges use the accent with readable text. Set a more specific token to break the chain:

```text
memberList.background → sidebar.background → mix(window.background, #000000, 16%)
```

Setting `sidebar.background` moves the member list with it; setting `memberList.background` changes only the member list.

Two tokens deserve a note: `accent` is the theme's signature color for **fills** (selection, badges, buttons), while `accentText` is the accent used **as text** (links, your nick, mentions). Set `accentText` when your accent is too light or too dark to read as text. `accentForeground` is text drawn **on** the accent.

## Building on another theme

`include` starts from another theme, and your `colors` win:

```jsonc
{
  "name": "Palenight Midnight",
  "type": "dark",
  "include": "Palenight",
  "colors": { "chat.background": "#1B1E2B", "window.background": "#1B1E2B" }
}
```

Includes can chain up to 8 levels. To customize a built-in in place, name your file after it (for example `nord.json`) and `"include": "Nord"`.

## Nick colors and mIRC colors

- **`nickColors`** is the palette nicknames are drawn from. Each nick starts from a stable entry, and people talking in the same conversation get different entries while the palette has room. Aim for 8–12 clearly different hues with at least 3:1 contrast (ideally 4.5:1) against `chat.background`; entries that would read as plain text (a grey close to `chat.foreground`) or fall under 3:1 aren't used.
- **`ircColors`** are the colors behind mIRC formatting codes. Colors 0–15 (white, black, blue, green, red, brown, magenta, orange, yellow, light green, cyan, light cyan, light blue, pink, grey, light grey) are worth tuning for your background; list only the ones you change:

  ```jsonc
  "ircColors": { "1": "#1B1E2B", "2": "#6C8EEF", "4": "#FF5370" }
  ```

## Checking contrast

Vela's theme editor flags tokens with **contrast issues**. Every built-in theme meets these targets:

- **4.5:1** for message text and other body text,
- **3:1** for secondary text, events, badges and nick colors,
- **2.5:1** for timestamps, placeholders and away members.

If you build Vela from source, `swift run vela-theme-tool check my-theme.json` reports the same checks from the command line.

## Sharing your theme

Use **Export…** in the theme editor, or just share the file. To propose a theme for Vela's built-in collection, open a [theme submission](https://github.com/r3volution11/Vela-IRC/issues/new?template=theme_submission.yml) with screenshots of all three message layouts, or send a pull request. Ports of other themes need a compatible license and attribution; see [CONTRIBUTING.md](https://github.com/r3volution11/Vela-IRC/blob/main/CONTRIBUTING.md).
