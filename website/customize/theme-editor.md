---
title: Theme editor
description: Make your own Vela theme in the built-in theme editor, with color wells for every token, contrast warnings, nick and mIRC colors, and a live preview across the whole app.
---

# Theme editor

The theme editor changes any color in Vela, with a live preview of the whole app as you go. Open it with **Theme → Theme Editor…**, **Settings → Appearance → Customize…**, or by right-clicking a theme in the gallery and choosing **Customize in Theme Editor…** to start from that theme.

## Start from a theme

At the top of the editor:

- **Theme name** is the name that appears in your theme list.
- **Type** is **Dark** or **Light**. It decides the defaults for colors you don't set, and whether macOS draws menus and alerts light or dark.
- **Start from** loads another theme's colors as your starting point.
- **Author** and **Description** are who made the theme and one sentence about it. They're shown when you hover the theme's card in **Settings → Appearance** or its name in **Select Theme** (<kbd>⌃⌘T</kbd>).
- **Translucency** is **None**, **Sidebar** or **Window**: whether the sidebar, rail and tab bars, or the whole main window, use macOS's translucent materials, tinted by your colors. Every Vela window previews it as you switch. See [Translucency](/customize/creating-themes#translucency).

When you start from a built-in theme, the copy gets a new name ("Nord Custom") and the description "Based on Nord.", so saving never overwrites the original.

### Problems in the theme

If the theme you start from has typos or values Vela skipped, such as a misspelled token name, a key themes don't have (`"fontSize"`) or a `vibrancy` that isn't `"none"`, `"sidebar"` or `"window"`, the editor lists them in a bar under the details, with the token you probably meant. **Remove Unknown Tokens** deletes misspelled token names from your working copy. Saving from the editor writes only what themes support, so unknown keys and a bad `vibrancy` are left out of the file. See [Typos and skipped values](/customize/creating-themes#problems).

## Change colors

The left column groups Vela's color **tokens** by the part of the window they color: Window, Title bar, Sidebar, Rail, Tabs, Chat, Input, Member list, Embeds, Reactions, Controls, Status and Settings window. You can also show **All tokens**, only the ones **Set in this theme**, or the ones with **Contrast issues**, or search by name.

Each token shows:

- a **color well** and a **hex field** (`#RRGGBB`, or `#RRGGBBAA` with transparency);
- what it colors and its **default**, which is often a formula over other tokens, such as `mix(window.background, #000000, 16%)`;
- a **contrast warning** when text in that color would be hard to read on its background;
- a **reset** button that goes back to the default.

You only need to set a few colors. Leave a token alone and it's derived from the others: set `window.background`, `window.foreground` and `accent`, and the sidebar, member list, badges and links follow. See [How defaults and fallbacks work](/customize/creating-themes#how-defaults-work).

Below the tokens are the **nick colors** (the palette nicknames are drawn from; add, remove or reset colors) and the **[mIRC](https://www.mirc.com) colors 0–15** used by colored text from other IRC clients. Right-click a color to reset it.

## Preview, save, export

Every Vela window shows your changes as you make them, including this one, and the **Live preview** in the left column draws a miniature of your window in the theme, translucency included. Nothing is saved until you choose:

| Button | Does |
| --- | --- |
| **Save** (<kbd>⌘S</kbd>) | Saves the theme to your Themes folder and makes it your theme (for the current mode, if you match the system appearance). Under the pointer, it shows the theme's `button.hoverBackground`. |
| **Export…** | Saves a copy as a `.json` file you can share or [contribute](https://github.com/r3volution11/Vela-IRC/blob/main/CONTRIBUTING.md). |
| **Revert** | Undoes every change since the theme was loaded or last saved. |
| **Close** (<kbd>⌘W</kbd>) | Closes the editor. If there are unsaved changes, Vela asks whether to save them. |

Closing without saving puts your previous theme back.

::: tip
Overrides from `appearance.colorCustomizations` in settings.json, including an [accent color](/customize/themes#accent-color) picked in **Settings → Appearance**, don't apply inside the editor's preview, so you always see the theme exactly as it's written.
:::

Saved themes are ordinary theme files, so you can keep refining them in a text editor. See [Creating themes](/customize/creating-themes).
