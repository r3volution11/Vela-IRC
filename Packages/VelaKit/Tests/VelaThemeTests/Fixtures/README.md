# VelaTheme test fixtures

## `vscode/`

| File | Source | License |
| --- | --- | --- |
| `nord-color-theme.json` | [nordtheme/visual-studio-code](https://github.com/nordtheme/visual-studio-code) `themes/nord-color-theme.json` at `8ead09822c02d0d49d0f764104505e5a34d3689f`, unmodified. Real-world JSONC: contains a `/* … */` comment. | MIT, Copyright (c) 2016-present Sven Greb, see `LICENSE-nord.txt` |
| `tokyo-night-color-theme.json` | [enkia/tokyo-night-vscode-theme](https://github.com/enkia/tokyo-night-vscode-theme) `themes/tokyo-night-color-theme.json` at `7c0f11eaef322f293621ca7befe462214b7ea468`, unmodified. | MIT, Copyright (c) 2018-present Enkia, see `LICENSE-tokyo-night.txt` |
| `harbor-color-theme.jsonc` | Written for these tests: comments, trailing commas, short hex, no `type`, no terminal colors. | MPL-2.0 |
| `lantern-themes.vsix` | Written for these tests: a zipped VS Code extension with `package.nls.json` labels, a theme that `include`s another file, a light theme typed only by `uiTheme`, and a `.tmTheme` entry that must be skipped. | MPL-2.0 |

To rebuild `lantern-themes.vsix`, zip a folder containing `extension.vsixmanifest` and
`extension/` (`package.json`, `package.nls.json`, `themes/*.json`, `themes/legacy.tmTheme`)
with `zip -X -r lantern-themes.vsix extension.vsixmanifest extension`.
