---
title: settings.json
description: Configure Vela with a VS Code-style settings.json that applies as soon as you save, including appearance.colorCustomizations to override theme colors globally or per theme.
---

# settings.json

Everything you can set in Vela's Settings window, and a little more, lives in one plain-text file, `settings.json`, just like VS Code's user settings. Edit it in any text editor and Vela applies your changes the moment you save.

## Opening it

- **Theme → Open settings.json**
- **Settings → Advanced → Open settings.json**
- In the [command palette](/guide/command-palette): **Settings: Open settings.json**

It opens in your default editor for JSON files. The file is at:

```text
~/Library/Containers/io.github.r3volution11.Vela/Data/Library/Application Support/Vela/settings.json
```

## How it works

- It's a flat JSON object of dotted keys, such as `"chat.fontSize": 14`. Comments and trailing commas are allowed.
- **Only the settings you change are stored.** A missing key uses its default, and a value of the wrong type falls back to the default too.
- **Changes in either direction are live.** Saving the file updates Vela immediately, and changes you make in Settings are written back to the file.
- **Mistakes are safe.** If the file doesn't parse (say, a missing comma), Vela keeps your last good settings, shows the problem in **Settings → Advanced**, and won't overwrite the file until you fix it.
- **Unknown keys are kept**, so a setting from a newer version of Vela survives a trip through an older one.

::: warning Comments are not preserved
When Vela writes the file (after you change something in Settings), it rewrites it neatly formatted with sorted keys, and **comments are dropped**. Keep notes elsewhere if they matter to you.
:::

**Settings → Advanced → All settings** lists every key with its current value and default; right-click one to copy the key or a ready-to-paste JSON line. The [settings reference](/reference/settings) has the same list with descriptions.

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

  // No media from this site
  "media.blockedDomains": ["example.com"]
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

- Keys are [token names](/reference/theme-tokens), plus `nickColors`, `ircColors` and `vibrancy`.
- A `"[Theme Name]"` block applies only to themes whose name or id matches, ignoring case. List several in one key, and use `*` as a wildcard.
- Theme-specific values win over global ones.
- Unknown tokens and malformed colors are ignored and listed in **Settings → Appearance**.
- Customizations apply to the theme in use and to the previews in the theme gallery and picker, but not inside the theme editor.

From lowest to highest priority, a color comes from: the token's default, the included theme(s), the theme's own `colors`, global `colorCustomizations`, then `"[Theme Name]"` customizations.

## networks.json

Your networks are kept in `networks.json` in the same folder. You can edit it by hand while Vela is quit, but the [network editor](/guide/adding-a-network) is easier. It never contains passwords: those are in your Keychain.
