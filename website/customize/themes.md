---
title: Choosing a theme
description: Pick one of Vela's 21 built-in themes or your own, preview themes live with Select Theme (⌃⌘T), use different themes for Light and Dark Mode, and change a theme's accent color and message box border.
---

# Choosing a theme

Everything in Vela's window is drawn from a theme: the title bar, sidebar, tabs, conversation, message field, member list, link previews, badges and even the colors of nicknames. Vela comes with [21 built-in themes](/reference/built-in-themes), and you can [import](/customize/vs-code-themes), [edit](/customize/theme-editor) or [write](/customize/creating-themes) your own.

**A theme is only colors.** It never changes your layout, fonts, sizes or spacing, so any theme works with any layout and preset, and switching themes keeps your setup. See [Colors only, by design](/customize/creating-themes#colors-only).

<Screenshot src="/screenshots/theme-tokyo-night.webp" alt="Vela in the Tokyo Night theme" caption="Tokyo Night, one of the 21 built-in themes." />

## Light and dark

Out of the box, Vela follows your Mac: **Palenight** in Dark Mode and **Lighter** in Light Mode, switching automatically when macOS does. You can pick a different theme for each mode, or turn matching off and use one theme all the time.

The **Match System Appearance** switch is in the **Theme** menu and in **Settings → Appearance → System appearance**, along with the **Dark Mode theme** and **Light Mode theme** pickers.

## Select Theme: the quickest way

Press <kbd>⌃⌘T</kbd> (or choose **Theme → Select Theme…**) and move through the list with the arrow keys. The whole app takes on each theme as you go, so you can judge it on your own conversations. Press **Return** to keep it, or **Esc** to go back.

Each theme in the list has a tiny picture of a window in its colors: the sidebar with its selected channel and a mention badge, and the conversation with nick colors, a link and a message that mentions you. Hover a theme's name for its author and description.

With **Match System Appearance** on, the theme you pick becomes the theme for the mode your Mac is in right now, and the other mode keeps its own. With it off, the theme you pick is used all the time.

## The theme gallery

**Settings → Appearance** shows every theme as a small preview of Vela's window in your own layout, with its selected channel, badges, tabs, links, mentions and the New line in the theme's colors, and translucency if the theme has it. Use **All**, **Dark** and **Light** to filter. Hover a card for the theme's author and description. See [Previews are drawn for you](/customize/creating-themes#previews).

- **Click** a theme to use it. It follows the same rule as Select Theme: with **Match System Appearance** on, it becomes the theme for the current mode.
- **Right-click** a theme for more: **Use in Dark Mode** or **Use in Light Mode** (which keeps matching on), **Customize in Theme Editor…**, and, for your own themes, **Show in Finder** and **Delete Theme…**.

## Accent color {#accent-color}

<Screenshot src="/screenshots/settings-accent.webp" alt="Settings → Appearance: the Message box section with its Border and Border color rows, then the Accent color row above the theme gallery, with round swatches from Palenight's colors and a ring around Cyan" caption="Accent color, at the top of the theme gallery." />

Every theme has an **accent color**, used for buttons, the selected channel, links, mention highlights, focus rings and more. To use a different one, pick it from **Accent color** at the top of **Settings → Appearance → Theme**.

- **The choices come from the theme itself:** its nick colors and its [mIRC](https://www.mirc.com) colors 0–15, keeping up to ten that work as an accent. A color makes the list if it isn't grey or too close to the text color, stands out against the window and sidebar, and looks different from the others. **Default**, the theme's own accent, always comes first.
- **Hover a swatch** for its name, such as "Cyan" or "Default (Purple)". A ring marks the one in use.
- **Everything the theme draws in its accent switches over:** buttons, selection, links, mention highlights, the sidebar selection, focus rings and so on. Text in the new accent is lightened or darkened as needed to stay readable (4.5:1).
- **Colors with a meaning never change.** Errors, warnings, success, and joins, parts and quits keep their colors, even if they matched the old accent.
- **Each theme keeps its own choice.** With **Match System Appearance** on and different themes for Dark and Light Mode, there are two rows, **Dark Mode accent** and **Light Mode accent**.

<Screenshot src="/screenshots/accent-cyan.webp" alt="Vela in Palenight with a cyan accent: the selected channel, the private message badge and the message field's focus ring are cyan instead of purple" caption="Palenight with its Cyan accent." />

From the [command palette](/guide/command-palette): **Theme: Next Accent Color** steps through the swatches (after the last, it's back to Default), and **Theme: Reset Accent Color** goes back to the theme's own accent.

If a theme has no other colors that work as an accent, the row says so. If you've set the theme's accent yourself in settings.json, the row says that instead, and picking a swatch replaces it. The picker saves its choice in [settings.json](/customize/settings-json#accent-colors), so it survives updates and travels with your settings.

## Message box border {#message-box-border}

The message box has a quiet border that doesn't change while you type; the blinking cursor shows where you're typing. To change it, go to **Settings → Appearance → Message box**:

- **Border** sets the style:
  - **None:** no border, just the field's own background color.
  - **Subtle** (the default): a quiet 1-point line in the theme's border color, the same whether or not you're typing.
  - **Accent when typing:** the quiet line turns into a thicker line in the accent color while the field has focus.
- **Border color** sets its color, from the theme's own colors:
  - **Default** first: the theme's own border (and, with **Accent when typing**, its accent while you type).
  - Then the theme's quiet grays, from quietest to strongest: its **Divider**, **Window Border**, **Link Preview Border**, **Placeholder** and **Secondary Text** colors, leaving out any that look like another swatch.
  - Then its **Accent** and a few of its other colors. Hover a swatch for its name.
  - **Custom…** opens the macOS color panel for any color, transparency included.

A color you choose shows whether or not you're typing, with either style, and it's grayed out with **None**. Each theme keeps its own color; with **Match System Appearance** on and different themes for Dark and Light Mode, there are two rows, **Dark Mode border color** and **Light Mode border color**.

- **The border color beats the accent color.** Picking or resetting an [accent](#accent-color) never changes a border color you chose. Choose **Default** for the border, and it follows the accent again.
- **The same color is used nearby:** the line under the reply bar, the outline of the paste confirmation, the command palette's outline and the emoji picker's search field use the same two theme colors, `input.border` and `input.focusBorder`.
- **None on light themes:** with no border, the field stands apart from the bar around it only by its background. In Lighter, Vela Paper, Vela Mist and Sandy Beach (and the dark Ocean theme), the field is only slightly lighter than the bar, so it's hard to see. **Subtle** with a quiet color, such as **Divider**, is a gentler choice there.

From the [command palette](/guide/command-palette): **Typing: Message Box Border: None**, **Subtle** and **Accent When Typing**. The style is [`appearance.messageBoxBorder`](/reference/settings#appearance.messageBoxBorder) in settings.json, and the color is saved in [`appearance.colorCustomizations`](/customize/settings-json#message-box-border-color).

## Your own themes

Themes you import, save from the theme editor or write yourself live in the **Themes folder**. Open it with **Theme → Reveal Themes Folder**. Drop a theme file in, and it appears in the list right away; edit one in your text editor, and Vela reloads it the moment you save.

If a theme file has a mistake, Vela keeps showing the last version that worked and explains the problem in **Settings → Appearance**. If it only has a typo, such as a misspelled token name or a key themes don't have, the theme loads and **Settings → Appearance** lists what was ignored, with the name you probably meant. See [Typos and skipped values](/customize/creating-themes#problems).

A theme of your own with the same file name as a built-in one (for example `nord.json`) replaces the built-in in the list.

## Adjusting a theme without editing it

To change just a color or two, add `appearance.colorCustomizations` to [settings.json](/customize/settings-json#color-customizations). (The [accent color](#accent-color) and [message box border color](#message-box-border) pickers save their choices there too.) Overrides can apply to every theme or only to one:

```jsonc
"appearance.colorCustomizations": {
  "chat.timestamp": "#7A7A7A",
  "[Palenight]": { "accent": "#FFCB6B" }
}
```

## Translucency

Every built-in theme is opaque, so every color is exactly as designed. A theme can set `"vibrancy"` to put parts of the window on macOS's translucent materials, so your desktop shows through, blurred:

- **`"sidebar"`:** the sidebar and the collapsed rail (or, with tab stacks, the tab bars) use the macOS sidebar material.
- **`"window"`:** the whole main window is translucent.

The theme's colors tint the material, so it still looks like the theme. **Settings → Appearance → Details → Translucency** shows what the current theme uses. To try it on any theme, choose **Translucency** in the [theme editor](/customize/theme-editor), or add `"vibrancy"` for the theme in [`appearance.colorCustomizations`](/customize/settings-json#color-customizations). With **Reduce Transparency** on in **System Settings → Accessibility → Display**, every theme is drawn opaque. See [Translucency](/customize/creating-themes#translucency).

## What themes don't change

- **Layout, fonts, sizes and spacing** aren't part of themes. Set them in **Settings → Layout** and **Settings → Messages**, or all at once with a [preset](/guide/presets).
- **Menus, context menus, alerts and file pickers** are drawn by macOS. They follow the theme's light or dark type, not its colors.
