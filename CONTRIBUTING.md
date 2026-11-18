# Contributing to Vela

Thanks for helping build Vela! This guide covers the basics.

## Getting started

1. Install **Xcode 27** or later. Vela targets **macOS 26+**.
2. Clone the repo and open `Vela.xcodeproj`, or work on the package directly:
   ```sh
   swift build --package-path Packages/VelaKit
   swift test  --package-path Packages/VelaKit
   ```
3. Almost all code lives in `Packages/VelaKit`. The `Vela/` app target is intentionally tiny.
4. Run the app with `scripts/run.sh --dev` (or ⌘R in Xcode). Debug builds are a separate app, **Vela Dev** (bundle id `io.github.r3volution11.Vela.dev`, a **DEV** badge on its Dock icon), with their own sandbox: settings, networks, history and Keychain items. They never touch the Vela you use every day, and the two can run at the same time. To try things without any network, add `--demo`.

## Code guidelines

- **Swift 6 with strict concurrency.**
  - `VelaUI` and `VelaCore` default to `@MainActor`.
  - Protocol, storage and media code is nonisolated or actor-based.
- **Every source file starts with the MPL-2.0 header:**
  ```swift
  // This Source Code Form is subject to the terms of the Mozilla Public
  // License, v. 2.0. If a copy of the MPL was not distributed with this
  // file, You can obtain one at https://mozilla.org/MPL/2.0/.
  ```
- **Never hard-code colors in views.** Every color comes from the current theme via a token, such as `theme[ThemeKey.chatBackground]`. If you need a new surface, add a token to `ThemeRegistry` with dark and light defaults (usually a reference to an existing token) and regenerate the schema:
  ```sh
  swift run --package-path Packages/VelaKit vela-theme-tool schema > schemas/vela-theme.schema.json
  ```
- **Tests use Swift Testing** (`import Testing`). Protocol code should be covered by `MockTransport`-driven tests.
- Keep pull requests focused. One feature or fix per PR is easiest to review.

## Contributing a theme

1. Start from an existing theme in `Packages/VelaKit/Sources/VelaTheme/BuiltInThemes/`, or export one from Vela's theme editor.
2. Check contrast: chat text should meet WCAG AA against the chat background.
3. If your theme ports someone else's palette, confirm the license allows it and add attribution to `docs/THEME-CREDITS.md`.
4. Open a PR using the *Theme submission* template, with screenshots of all three message layouts.

## Reporting bugs

Use the bug report template. Include your macOS version, Vela version, and (if relevant) the IRC network or bouncer you were using. **Never paste passwords, SASL credentials or private logs.**

## License

By contributing, you agree that your contributions are licensed under the [MPL-2.0](LICENSE).
