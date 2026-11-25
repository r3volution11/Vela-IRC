---
title: settings.json
description: Configure Vela with a VS Code-style settings.json that keeps your comments and applies as soon as you save, and override theme colors and accents with appearance.colorCustomizations.
---

# settings.json

Everything you can set in Vela's Settings window, and a little more, lives in one plain-text file, `settings.json`, just like [VS Code](https://code.visualstudio.com)'s user settings. Edit it in any text editor and Vela applies your changes the moment you save.

You can also edit it without leaving Vela: the [settings editor](/customize/settings-editor) in **Settings → Advanced** lists every setting with a control for each, and its **JSON** view edits the file itself, with suggestions and checks as you type.

## Opening it

To open settings.json in your default editor for JSON files:

- **Theme → Open settings.json**
- In the [command palette](/guide/command-palette): **Settings: Open settings.json**
- In **Settings → Advanced**: **⋯ → Open settings.json in External Editor**, or **Open in External Editor** in the JSON view's toolbar

The file is at:

```text
~/Library/Containers/io.github.r3volution11.Vela/Data/Library/Application Support/Vela/settings.json
```

## How it works

- It's a flat JSON object of dotted keys, such as `"chat.fontSize": 14`. It's JSON with Comments: `//` and `/* */` comments and trailing commas are allowed.
- **Only the settings you change are stored.** A missing key uses its default, and a value of the wrong type, or one that isn't among a setting's choices, falls back to the default too.
- **Changes in either direction are live.** Saving the file updates Vela immediately, and changes you make in Settings are written back to the file, [keeping your comments](#comments).
- **Mistakes are safe.** If the file doesn't parse (say, a missing comma), Vela keeps your last good settings and shows where the problem is in **Settings → Advanced**, for example "settings.json is invalid; keeping previous values. Line 3, column 3: Expected a comma." Changes you make in Settings meanwhile work as usual, and are written to the file once it's fixed, so a half-typed edit is never overwritten.
- **Unknown keys are kept**, so a setting from a newer version of Vela survives a trip through an older one.
- **A key set twice uses the last one**, as in VS Code.
- **Replaced settings are upgraded.** When a newer Vela replaces a setting (`media.blockedDomains` became `media.siteRules`, for example), it converts your value when it starts and removes the old key.

Every key is listed, with its description, type and default, in the [settings reference](/reference/settings), and in the [settings editor](/customize/settings-editor), where you can search them and see which ones you've changed.

## Comments and formatting {#comments}

When you change a setting in Vela, in Settings, the settings editor, Settings → Presets or the accent color picker, Vela edits settings.json the way you would: it changes only that setting's text and leaves the rest of the file alone, comments, blank lines and all.

- **A changed value** is replaced where it is.
- **A setting reset to its default** is removed along with its line, including a comment at the end of that line. Comments on the lines above it stay.
- **A new setting** goes after the last one, before any comments at the end of the file. It follows the file's own style: tabs or spaces and how many, line endings, `"key": value` or `"key" : value`, and whether the last entry has a trailing comma.
- **Objects** such as `appearance.colorCustomizations` and `media.siteRules` are changed entry by entry, so comments inside them survive too.
- **Lists** (arrays) are rewritten whole when they change, so comments inside a list are lost. Comments around it are kept.
- **A missing or empty file** is created fresh, indented with four spaces. A file with nothing but comments keeps them.
- **While the file has a syntax error,** Vela doesn't write to it at all.

## An example

```jsonc
{
  // Always Tokyo Night, whatever macOS is doing
  "appearance.theme": "Tokyo Night",
  "appearance.followSystem": false,

  // Tabs in the title bar, as pills
  "navigation.style": "tabs",
  "tabs.placement": "titleBar",
  "tabs.roundness": 1,

  // Compact, quiet conversations
  "chat.layout": "columns",
  "chat.showJoinPart": "hide",
  "chat.clock": "24h",
  "chat.timestampSeconds": true,

  // Previews per site: "block" (nothing), "textOnly" or "allow" (everything)
  "media.siteRules": {
    "example.com": "block",
    "news.example": "textOnly"
  }
}
```

## Color customizations {#color-customizations}

Like VS Code's `workbench.colorCustomizations`, `appearance.colorCustomizations` overrides theme colors without editing the theme:

```jsonc
"appearance.colorCustomizations": {
  // Every theme
  "chat.timestamp": "#7A7A7A",

  // Only Palenight
  "[Palenight]": {
    "accent": "#FFCB6B",
    "nickColors": ["#F07178", "#C3E88D", "#82AAFF", "#C792EA"]
  },

  // Several themes at once, and wildcards
  "[Nord][Dracula]": { "chat.selfNick": "#FFB86C" },
  "[Catppuccin *]": { "ircColors": { "4": "#FF5555" } },
  "[Solarized*]": { "vibrancy": "sidebar" }
}
```

- Keys are [token names](/reference/theme-tokens), plus `nickColors`, `ircColors` and `vibrancy` (`"none"`, `"sidebar"` or `"window"`; see [Translucency](/customize/creating-themes#translucency)).
- A `"[Theme Name]"` block applies only to themes whose name or id matches, ignoring case. List several in one key, and use `*` as a wildcard.
- Theme-specific values win over global ones.
- Unknown tokens and malformed colors are ignored and listed in **Settings → Appearance**, with the token you probably meant: "“sidebar.backgroud” is not a theme color token, so it's ignored. Did you mean “sidebar.background”?"
- Customizations apply to the theme in use and to the previews in the theme gallery and picker, but not inside the theme editor.

From lowest to highest priority, a color comes from: the token's default, the included theme(s), the theme's own `colors`, global `colorCustomizations`, then `"[Theme Name]"` customizations.

### Accent colors {#accent-colors}

The [accent color](/customize/themes#accent-color) picker in **Settings → Appearance** saves its choice here too, in the theme's own scope. It sets `accent`, a readable `accentText` and `accentForeground`, and every other token the theme draws in its accent, then lists what it wrote under `"$accentPicker"`. Picking Cyan for Palenight writes:

```jsonc
"appearance.colorCustomizations": {
  "[Palenight]": {
    "accent": "#89DDFF",
    "accentForeground": "#08222B",
    "accentText": "#89DDFF",
    "button.background": "#89DDFF",
    "chat.highlightBorder": "#89DDFF",
    "sidebar.activeBackground": "#304153",
    // …and the other tokens Palenight draws in its accent
    "$accentPicker": ["accent", "accentForeground", "accentText", "button.background", "chat.highlightBorder", "sidebar.activeBackground", …]
  }
}
```

- **Your own overrides win.** The picker never replaces a token you set yourself, in the theme's scope, at the top level or in another scope that matches the theme. The exception is `accent` itself: picking a swatch always sets it.
- **Default (or Theme: Reset Accent Color) removes only what the picker wrote**, as listed in `"$accentPicker"`, and drops the theme's scope if nothing else is left in it. Your own entries stay.
- **Leave `"$accentPicker"` alone.** It isn't a color, and it's how Vela knows which entries are its own. If you edit one of those entries by hand, also take its name out of the list, or Default will remove it.
- **The picker writes to an existing scope** that names only this theme (such as `"[palenight]"`), or else adds `"[Theme Name]"`.
- **Settings → Appearance → Color overrides** counts only the entries you wrote yourself, not the accent or border pickers'.

### Message box border color {#message-box-border-color}

The [message box border](/customize/themes#message-box-border) color in **Settings → Appearance → Message box** is saved the same way, in the theme's own scope. It sets both `input.border` and `input.focusBorder` to the color, so it shows whether or not you're typing, and lists them under `"$borderPicker"`:

```jsonc
"appearance.colorCustomizations": {
  "[Palenight]": {
    "input.border": "#4E5579",
    "input.focusBorder": "#4E5579",
    "$borderPicker": ["input.border", "input.focusBorder"]
  }
}
```

- **It wins over the accent color picker.** Choosing a border color takes `input.focusBorder` over from the accent picker (out of `"$accentPicker"`, when the accent picker had set it), and picking or resetting an accent leaves the border's entries alone. Both pickers share the theme's scope.
- **Default removes only the picker's two entries and `"$borderPicker"`.** If you're using a picked accent, `input.focusBorder` goes back to it. The theme's scope is dropped if nothing else is left in it.
- **Leave `"$borderPicker"` alone**, as with `"$accentPicker"`. Changing one of its entries in the [settings editor](/customize/settings-editor#color-customizations) (**Settings → Advanced**) takes it out of the list for you; in the file, take its name out too.
- **`input.border` you set yourself** (at the top level or in a scope) shows as a custom color in Settings → Appearance, and Default doesn't remove it.

Whether there's a border at all is a separate setting, [`appearance.messageBoxBorder`](/reference/settings#appearance.messageBoxBorder): `"none"`, `"subtle"` (the default) or `"accent"` (the accent color while you type).

## networks.json

Your networks are kept in `networks.json` in the same folder. You can edit it by hand while Vela is quit, but the [network editor](/guide/adding-a-network) is easier. It never contains passwords: those are in your Keychain.

A bouncer network can have `pendingParts` and `pendingDetaches`: channels you removed or [left](/guide/joining-channels#through-a-bouncer) while Vela wasn't connected to the bouncer. Vela parts or detaches each on the bouncer after it next connects, then takes it off the list.
