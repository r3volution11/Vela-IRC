---
title: License & credits
description: Vela is open source under the Mozilla Public License 2.0. Credits for the libraries, theme palettes and protocol references Vela builds on.
---

# License & credits

## Vela's license

Vela is free and open source under the **[Mozilla Public License 2.0](https://github.com/r3volution11/Vela-IRC/blob/main/LICENSE)**. In short:

- You can use, modify and distribute Vela, including in paid or App Store builds.
- Changes to Vela's own source files must stay open under the MPL.
- Third-party components and ported themes keep their own licenses.

The source code is at [github.com/r3volution11/Vela-IRC](https://github.com/r3volution11/Vela-IRC). Contributions are welcome, especially themes; see [CONTRIBUTING.md](https://github.com/r3volution11/Vela-IRC/blob/main/CONTRIBUTING.md).

## Libraries

| Component | License |
| --- | --- |
| [GRDB.swift](https://github.com/groue/GRDB.swift), for the local message database | MIT |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation), for importing `.vsix` theme extensions | MIT |

## Theme credits {#theme-credits}

Every built-in theme file was written for Vela and is distributed under Vela's license, with these attributions. Ports reuse their projects' published color palettes, adjusted where needed for legibility.

| Vela theme | Based on | License |
| --- | --- | --- |
| Dracula | [Dracula for Visual Studio Code](https://github.com/dracula/visual-studio-code) | MIT, © 2016 Dracula Theme |
| Nord | [Nord for Visual Studio Code](https://github.com/nordtheme/visual-studio-code) | MIT, © 2016-present Sven Greb |
| Catppuccin Latte, Catppuccin Mocha | [Catppuccin for VS Code](https://github.com/catppuccin/vscode) and the [Catppuccin palette](https://github.com/catppuccin/palette) | MIT, © 2021 Catppuccin |
| Tokyo Night | [Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme) | MIT, © 2018-present Enkia |
| One Dark | [One Dark Pro](https://github.com/Binaryify/OneDark-Pro), after Atom's One Dark | MIT, © 2013-2022 Binaryify |
| Gruvbox Dark | [vscode-theme-gruvbox](https://github.com/jdinhify/vscode-theme-gruvbox), palette [Gruvbox](https://github.com/morhetz/gruvbox) by Pavel Pertsev | MIT, © 2017 JD; palette MIT/X11 |
| Solarized Dark, Solarized Light | VS Code's built-in Solarized themes, palette [Solarized](https://github.com/altercation/solarized) by Ethan Schoonover | MIT, © Microsoft Corporation; palette MIT, © 2011 Ethan Schoonover |
| Rosé Pine | [Rosé Pine for VS Code](https://github.com/rose-pine/vscode) | MIT, © 2021 Rosé Pine |

**Palenight, Lighter, Oceanic, Darker, Ocean, Deepforest, Volcano and Sandy Beach** are original Vela themes inspired by the classic variants of the Material Theme by Mattia Astorino and contributors. Vela isn't affiliated with or endorsed by Material Theme or Vira Software, and its themes contain none of their files.

**Vela Graphite, Vela Paper and Vela Mist** are original designs. Their paper-like surfaces and single confident accent were inspired by the look of [Bear](https://bear.app); no colors were taken from Bear's themes.

The full attributions, including the exact changes made to each palette and the MIT license text, are in [THEME-CREDITS.md](https://github.com/r3volution11/Vela-IRC/blob/main/docs/THEME-CREDITS.md) and [THIRD_PARTY_NOTICES.md](https://github.com/r3volution11/Vela-IRC/blob/main/THIRD_PARTY_NOTICES.md).

## Protocol references

Vela's IRC implementation follows the [Modern IRC Client Protocol](https://modern.ircdocs.horse) and the [IRCv3 specifications](https://ircv3.net/irc/).

## This website

Built with [VitePress](https://vitepress.dev) and styled in Vela's own Palenight and Lighter themes. Screenshots come from Vela's demo mode. The site's source is in the [`website` folder](https://github.com/r3volution11/Vela-IRC/tree/main/website) of the Vela repository; if something here is wrong or unclear, **Suggest a change to this page** at the bottom of any page.
