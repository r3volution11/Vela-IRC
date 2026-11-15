# Theme credits

Vela's built-in themes live in
`Packages/VelaKit/Sources/VelaTheme/BuiltInThemes/`. Every file was written for
Vela (they are Vela theme files, not copies of other projects' files) and is
distributed under Vela's license (MPL-2.0), with the attributions below. Ports
reuse their projects' published color palettes; where a color was changed for
legibility, it's noted.

## Ports of MIT-licensed themes

All of the following projects are released under the MIT License. Their
copyright notices are reproduced here as that license requires.

### Dracula — `dracula.json`

- Source: <https://github.com/dracula/visual-studio-code> (palette from `src/dracula.yml`), consulted at `b50e62e320906d5f57a8bf05fd6ddf23b890d6dd`
- License: MIT — Copyright (c) 2016 Dracula Theme
- Accent purple `#BD93F9`, pink `#FF79C6` for mentions.
- Changes for legibility: the mention badge uses dark text `#21222C` (white on pink is under 3:1); secondary text and timestamps use slightly brighter comment tones (`#8A93B8`, `#6D7AAD`).

### Nord — `nord.json`

- Source: <https://github.com/nordtheme/visual-studio-code>, consulted at `8ead09822c02d0d49d0f764104505e5a34d3689f`
- License: MIT — Copyright (c) 2016-present Sven Greb &lt;development@svengreb.de&gt; (<https://www.svengreb.de>)
- Accent Frost `#88C0D0`; the selected sidebar row is a Frost fill with dark text, as in the original.
- Changes for legibility: `chat.error` is `#DC8A92` (Nord red `#BF616A` is 3.1:1 for body-size text); timestamps `#6F7B93` instead of the line-number color `#4C566A`; a visible title bar border; two nick tints (`#D99AA0`, `#E3A98C`).

### Catppuccin Latte and Catppuccin Mocha — `catppuccin-latte.json`, `catppuccin-mocha.json`

- Source: <https://github.com/catppuccin/vscode> (layout from its `uiColors.ts`), consulted at `befc9e6fc41980f4241408f7049755d47c06ff45`; palette from <https://github.com/catppuccin/palette> at `07d02aa110ef9eb7e7427afca5c73ba9cf7f8ebd`
- License: MIT — Copyright (c) 2021 Catppuccin
- Accent Mauve, links Blue.
- Mocha uses the palette unchanged.
- Latte darkens colors that are too light to read as text on its base: `accentText` `#7A30E0`, link `#1A5CE0` (Blue `#1E66F5` is 4.3:1), notice `#B3460A`, action `#A93E8E`, join `#3A8F27`, part `#C0394A`, code `#2A7019`, and the peach/yellow/sky/lavender/pink nick colors (`#D9530A`, `#B07012`, `#0389C0`, `#5A6FEA`, `#C8559F`). Text on the accent uses base `#EFF1F5`, and IRC color 0 is `#FFFFFF`.

### Tokyo Night — `tokyo-night.json`

- Source: <https://github.com/enkia/tokyo-night-vscode-theme>, consulted at `7c0f11eaef322f293621ca7befe462214b7ea468`
- License: MIT — Copyright (c) 2018-present Enkia
- Accent fill `#3D59A1` with white text; `accentText` `#7AA2F7`.
- Changes for legibility: links `#7AA2F7` (the original `#6183BB` is 4.4:1); `chat.error` uses palette red `#F7768E`; sidebar text brightened to `#8A91B5`; timestamps use the comment color `#565F89`; a slightly more visible scrollbar.

### One Dark — `one-dark.json`

- Source: One Dark Pro, <https://github.com/Binaryify/OneDark-Pro>, consulted at `75c80ab18d90655e05ad837bb8d89f5e68d5ce53` (itself based on Atom's One Dark)
- License: MIT — Copyright (c) 2013-2022 Binaryify
- Accent fill `#4170C8`, `accentText` `#61AFEF`.
- Changes for legibility: the accent fill is darkened from `#4D78CC` so white text passes 4.5:1 (`#4D78CC` is kept for focus, hover and badges); `chat.error` `#E5737C` (`#E06C75` is 4.37:1); timestamps `#636D83`; IRC color 8 uses palette yellow `#E5C07B` because One Dark's terminal bright yellow is orange.

### Gruvbox Dark — `gruvbox-dark.json`

- Source: <https://github.com/jdinhify/vscode-theme-gruvbox> (medium contrast variant), consulted at `5538f16b660b5ebf12450e5dfcf15e6f9f64960a`
- License: MIT — Copyright © 2017 JD
- Palette: Gruvbox by Pavel Pertsev, <https://github.com/morhetz/gruvbox> (at `ef8864bb42bf244f0295d1c5a403b27e3d139695`), whose README states MIT/X11; the repository has no separate license file.
- Accent aqua `#8EC07C` (the original's selected-file color), yellow `#FABD2F` for mentions.
- Changes for legibility: `chat.error` `#FB5C46` (`#FB4934` is 4.2:1); timestamps `#7C6F64`.

### Solarized Dark and Solarized Light — `solarized-dark.json`, `solarized-light.json`

- Source: VS Code's built-in Solarized themes, <https://github.com/microsoft/vscode> (`extensions/theme-solarized-dark`, `extensions/theme-solarized-light`), consulted at `9893f280efbceb0dd54b0327120977223e49af93`
  - License: MIT — Copyright (c) 2015 - present Microsoft Corporation
- Palette: Solarized by Ethan Schoonover, <https://github.com/altercation/solarized> (at `62f656a02f93c5190a8753159e34b385588d5ff3`)
  - License: MIT — Copyright (c) 2011 Ethan Schoonover
- Solarized's bright terminal colors are greys, so IRC colors are mapped by palette meaning; slots 9 and 11 are derived tints.
- **Dark** (accent cyan `#2AA198`): body text `#93A1A1` (base1) instead of `#839496` (base0) so highlighted rows stay above 4.5:1; mentions `#EEE8D5`; links `#45A3E6`; `chat.error` `#F06560`; four lightened nick tints.
- **Light** (accent gold `#B58900`, from the original's badges and buttons; `accentText` `#7A5C00`): body text `#586E75` (base01) because base00 `#657B83` is 4.1:1; sidebar, input and popover text darkened to about `#4E636A`–`#52676E`; links `#1A6FAF`, embed titles `#16609A`; notice `#B5410F`, action `#B92D6F`, error `#C42B28`; nick variants `#A67D00`, `#22877F`, `#6F8000`.

### Rosé Pine — `rose-pine.json`

- Source: <https://github.com/rose-pine/vscode>, consulted at `d8f5ebe8e096fa833e997c07eb7685ee1677a4ba`
- License: MIT — Copyright (c) 2021 Rosé Pine
- Accent rose `#EBBCBA`, links iris.
- Rosé Pine has six hues, so the nick palette and some IRC colors also borrow from its official Moon and Dawn variants (`#3E8FB0`, `#D7827E`, `#907AA9`, `#56949F`, `#EA9D34`, `#B4637A`). Timestamps `#6E6A86`; a visible pane divider `#26233A`.

### MIT License text

```text
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Inspired by Material Theme

**Palenight, Lighter, Oceanic, Darker, Ocean, Deepforest, Volcano and Sandy
Beach** are original Vela themes inspired by the variants of the classic
*Material Theme* by Mattia Astorino and contributors, originally published at
`github.com/material-theme/vsc-material-theme` (that address now redirects to
its successor). Material Theme has since been relaunched as the commercial
Vira Theme; Vela's themes are not
affiliated with or endorsed by it, contain none of its files, and don't use its
name. They take inspiration from the classic variants' well-known color
palettes (for example Palenight's `#292D3E` background and `#C792EA` purple,
Oceanic's `#263238` and `#80CBC4`), redesigned for Vela's surfaces with
WCAG AA text contrast. Deepforest, Volcano and Sandy Beach are free
reinterpretations of their namesakes' moods rather than reproductions.

## Vela originals

**Vela Graphite, Vela Paper and Vela Mist** are original designs. Their
paper-like surfaces, single confident accent, softly tinted sidebar and quiet
dividers were inspired by the aesthetic of [Bear](https://bear.app) by Shiny
Frog; no colors were taken from Bear's themes.

## Test fixtures

The VS Code importer's tests use unmodified theme files from Nord (MIT,
Copyright (c) 2016-present Sven Greb) and Tokyo Night (MIT, Copyright (c)
2018-present Enkia). They live in
`Packages/VelaKit/Tests/VelaThemeTests/Fixtures/vscode/` alongside their
license files; they aren't shipped in the app.
