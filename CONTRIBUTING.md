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
4. Run the app with `scripts/run.sh --dev` (or ⌘R in Xcode). Debug builds are a separate app, **Vela Dev** (bundle id `io.github.r3volution11.Vela.dev`, with its own icon: the Sunrise colorway with two more stars), with their own sandbox: settings, networks, history and Keychain items. They never touch the Vela you use every day, and the two can run at the same time. To try things without any network, add `--demo`. Vela Dev also has a **Developer** menu: an element inspector, layout outlines, a performance HUD and a state simulator (see [Developer tools](#developer-tools-vela-dev)).
5. **Stop the Keychain prompts after each build:** if you have an Apple Development or Developer ID certificate, run `scripts/dev-signing.sh` once. Vela Dev is signed ad hoc by default, and the Keychain trusts an ad hoc app only for that exact build, so after every rebuild it asks for your password once per saved password and channel key. The script writes the git-ignored `Config/Signing.xcconfig`, which signs Vela Dev with your certificate instead, so every build has the same identity. Choose **Always Allow** once more, and later builds won't ask. `scripts/dev-signing.sh --remove` goes back to ad hoc.
6. GIF search in local builds needs Vela's KLIPY key, kept out of the repository: maintainers run `scripts/klipy-key.sh --local` once, which writes it from 1Password to the git-ignored `Config/Secrets.xcconfig`. Without it, use your own free key from [KLIPY](https://partner.klipy.com) in **Settings → Media → GIFs**.

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
- **Tag new surfaces for the inspector.** A new kind of row, bar or panel gets a `.devTag("Name", tokens: […])` after its padding and background, naming the tokens it draws with (see [Developer tools](#developer-tools-vela-dev)). It costs nothing in release builds.
- **Tests use Swift Testing** (`import Testing`). Protocol code should be covered by `MockTransport`-driven tests.
- **Scrolling has a budget.** Vela must scroll smoothly on the slowest Macs it supports (2019–2020 Intel Macs, an 8 GB M1). If you change the message list, its rows or inline media, run `scripts/benchmark-scroll.sh` before and after: it scrolls a big, fixed channel in a Release build and compares the numbers with `benchmarks/scroll-baseline.json`. Its window is invisible and never takes the focus or the pointer, so you can keep working while it runs (about 12 minutes). See [docs/RELEASING.md](docs/RELEASING.md#scroll-benchmark).
- Keep pull requests focused. One feature or fix per PR is easiest to review.

## Developer tools (Vela Dev)

Vela Dev has a **Developer** menu, the last of the app's menus, with tools like a browser's devtools. The command palette lists them too, under "Developer:". They're compiled only into Debug builds (`#if DEBUG`): release builds have no menu, no tagging and none of the code.

| Tool | Shortcut | What it does |
| --- | --- | --- |
| **Inspect Element** | ⌥⌘I | Point at something to see what it's drawn with: the theme tokens and their hex values in the current theme, its font (family, size, weight), its size and its padding, and the tagged views it's inside. Click to pin it; the pinned panel has **Open in Theme Editor** for each token, which leaves inspect mode and opens the theme editor searching for that token. Click it again to unpin. Esc leaves inspect mode. While you inspect, the window's content gets no clicks or hovers. |
| **Layout Outlines** | ⌥⌘O | Outlines every tagged view with its name and size, shades its padding green and marks the gaps between neighbors (views directly inside the same tagged view) in pink, like a browser's box model. |
| **Performance HUD** | ⌥⌘P | A panel at the top right of the main window. **frame**: the frame rate and frame time, with the worst of the last second; **dropped**: frames missed, in the last second and since the HUD opened; **hitches**: how late the late frames were, in ms per second (as `scripts/benchmark-scroll.sh` reports it); **stalls**: gaps of 50 ms or more, when the main thread was blocked; **memory**: the memory footprint (what Activity Monitor shows); **rows**: message list rows built per second and in all. The numbers come from the main window's display link on the main thread and refresh twice a second. The display link runs only while the HUD is showing. |

### The state simulator

The menu's **State Simulator** section puts the window into states that are hard to reach on demand:

- **Network Offline**, **Network Connecting** and **Network Online**;
- **Incoming Mention**: someone in #simulator says your nick. Be in another buffer to see the badge and the notification;
- **Very Long Nick and Message**: a 64-character nick and a long message with an unbroken word and a long link;
- **Huge Channel**: #huge, with 5,000 members and 10,000 messages;
- **Reconnect Storm**: the connection drops and comes back 15 times in a row, with a netsplit's quits and joins each time. Choose it again to stop it;
- **Remove Simulator Network**.

All of it happens on a network of its own, **Simulator**, which the first of these adds. Your real networks are never touched, and nothing is saved: the network isn't in `networks.json` and has no message history, chat logs or Keychain items; it's never the channel Vela reopens at launch; Spotlight, Siri and Shortcuts never see it; and its connection is a stand-in that never opens a socket (**Connect** fails at once). Quitting forgets it. The states go through `NetworkSession`'s own event handling, the same code a server's lines go through. A mention posts a real notification, as one from a real network would. The code is `DevSimulator` in VelaCore.

### Checking links and the AppleScript dictionary

`Vela/Vela.sdef` is an interface the Alfred workflow, the Raycast extension and people's scripts build on: only ever add to it (never rename a term, code or cocoa key without [updating the extensions first](#working-across-vela-and-the-extensions)). `ScriptingDictionaryTests` check it against the code, but not Cocoa scripting itself, and `osascript` needs your terminal to be allowed to control Vela Dev (a permission prompt). Instead, Vela Dev in demo mode can drive its own dictionary, and a `vela-dev://` link, from inside the app, where macOS asks nothing, and write a report:

```sh
open -g -n build/DerivedData/Build/Products/Debug/Vela.app --args --demo --no-activate --automation-self-test
cat ~/Library/Containers/io.github.r3volution11.Vela.dev/Data/tmp/AutomationSelfTest.txt
```

`--no-activate` keeps it from taking the focus. The code is `AutomationSelfTest` in `Packages/VelaKit/Sources/VelaUI/DevTools/`, Debug builds only.

### Tagging views

Inspect Element and Layout Outlines see the views tagged with `devTag`:

```swift
.padding(.horizontal, 14)
.background(theme[ThemeKey.inputBackground])
.devTag(
    "Message box",
    tokens: [ThemeKey.inputBackground, ThemeKey.inputForeground],
    font: style.bodyFont,                                        // optional: what its text uses
    padding: EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)  // optional: for the green band
)
```

- **Put the tag after the view's padding and background,** so its frame is the view's box.
- **List the tokens the view draws with now,** most telling first. A row's tokens can follow its state: hovered, selected, highlighted.
- **`SurfaceFill` and `surfaceBackground` tag themselves** with their token, so every surface of the main window is covered. So are the shared components: message and event rows, sidebar and member rows, tabs, the header, the message box, badges, themed buttons and text fields, the palette and the settings pages, sections, cards and rows.
- **What it costs.** In release builds `devTag` returns the view itself, and its arguments are never evaluated: no modifier, no stored properties, no environment reads. In Debug builds, with the tools off, a tagged view carries an empty background and one check of whether they're on. Only with Inspect Element or Layout Outlines on does each tagged view report its frame.
- **What it doesn't see:** sheets, popovers and menus, which aren't in the window's own view tree.

The code is in `Packages/VelaKit/Sources/VelaUI/DevTools/`. The tools draw in fixed colors rather than theme tokens, so they read the same over every theme: the one exception to never hard-coding colors.

To check that a release build has none of it, build Release and look for the tools' symbols and strings. Every count should be 0:

```sh
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData-release build
VELA=build/DerivedData-release/Build/Products/Release/Vela.app/Contents/MacOS/Vela
nm -a "$VELA" | grep -c 'DevTag\|DevTools\|DevSimulator\|devToolsHost'
strings -a "$VELA" | grep -c 'Inspect Element\|simulator.invalid\|Message row'
```

## Working across Vela and the extensions

The Alfred workflow and the Raycast extension live in their own repositories, [vela-alfred-workflow](https://github.com/r3volution11/vela-alfred-workflow) and [vela-raycast-extension](https://github.com/r3volution11/vela-raycast-extension). Both talk to Vela through its AppleScript dictionary (`Vela/Vela.sdef`) and its `vela://` links, and **Settings → Integrations** offers them. For a change that touches Vela and either of them:

1. **Change Vela's dictionary first.** Additions are safe: a new term, property or command breaks nothing. A removal or a rename (of a term, a four-character code or a cocoa key), or a command that behaves differently, comes only after both extensions have been updated not to need the old one, and raises the application's `scripting version` (`VelaAutomation.scriptingVersion`), which the extensions read. `ScriptingDictionaryTests` check the dictionary against Vela's code.
2. **The extensions' CI checks their terms against `Vela.sdef`** on Vela's `main` and `next`, so a term they use that Vela doesn't have (yet, or any more) fails there.
3. **Use the same branch name in every repository** for one cross-cutting change, so it's easy to see what goes together, and merge Vela's side first.
4. **Refresh the workflow Vela bundles** once the workflow's change is released: `scripts/update-alfred-workflow.sh --release latest` (or `--local` to try an unreleased build from a checkout next to Vela's), then commit `Vela/Integrations/Vela.alfredworkflow` and `integrations/alfred-workflow.json` together. CI fails when they don't match. See [integrations/README.md](integrations/README.md).

## Media sites

`Packages/VelaKit/Sources/VelaMedia/MediaSites.swift` is the source of truth for the sites whose links Vela plays or shows inline: YouTube, Tenor, Reddit and the rest. For each it lists the domains (media and CDN hosts too), the domain a site rule is written for, every link form with what Vela shows and fetches, a privacy note, and sample links with what each must turn into. Three things come from it, so the list, the docs and the app can't drift apart:

- **The website's [Supported media sites](https://velairc.app/reference/media-sites) page** (`website/reference/media-sites.md`), generated by `vela-media-tool`.
- **Offline tests** (`MediaSitesTests`, part of every `swift test`). They fail when a sample isn't recognized as declared by `MediaClassifier`, `GIFLinks` and `RedditLinks`; when a domain isn't covered by the declared site rule; when a provider or domain in that code has no entry; when a lookalike host (`notyoutube.com`) passes for the site; and when the website page is stale.
- **Live checks** (`LiveMediaSiteTests`), which resolve every live sample against the real site: the title is there, the thumbnail and player load, the GIF's MP4 downloads within the size cap, and so on.

### Adding or changing a site

1. Teach Vela the links, with unit tests against stubbed responses: video sites in `MediaClassifier` and `EmbedInfo`, GIF sites in `GIFLinks`.
2. Add or update its entry in `MediaSites.all`, with a sample link for every link form. Pick samples that will last: public-domain or official uploads (NASA, the Blender Foundation's *Big Buck Bunny*) on accounts that don't delete things. Give each sample `live:` checks for what must hold on the real site. A sample that can't be checked live (an unlisted video, a share link) needs a `note` saying why.
3. Regenerate the website page:
   ```sh
   swift run --package-path Packages/VelaKit vela-media-tool docs --write website/reference/media-sites.md
   ```
4. Run the tests, then the live checks for the site:
   ```sh
   swift test --package-path Packages/VelaKit --filter VelaMediaTests
   scripts/check-media-sites.sh --site <id>       # the ids are in MediaSites.swift; --list shows them
   ```
5. Document it like any other change: the [inline media guide](website/guide/inline-media.md) if it changes what people see, and `CHANGELOG.md`.

### Where the live checks run

- **On GitHub:** the [Media sites](.github/workflows/media-sites.yml) workflow runs when a push or pull request changes media code, every Monday, and on demand from the Actions tab. GitHub emails the repository owner when a scheduled run fails.
- **Before every release:** `scripts/release.sh` stops if a site fails (see [docs/RELEASING.md](docs/RELEASING.md#when-the-media-check-fails)).
- **On your Mac:** `scripts/check-media-sites.sh` prints a report per site and exits with 1 if one failed. It's the same as `VELA_LIVE_MEDIA_TESTS=1 swift test --package-path Packages/VelaKit --filter LiveMediaSiteTests`.
- **What the browser engine costs:** for sites behind bot checks (`BrowserMetadataFetcher`), `VELA_BROWSER_FALLBACK_MEASURE=1 swift test --package-path Packages/VelaKit --filter LiveBrowserFallbackMeasurement` loads the IMDb sample (or `VELA_BROWSER_FALLBACK_URL`) with and without the content blocking, through a local counting proxy, and prints the time to metadata and the bytes and connections per host.
- **When you push,** if you install the git hook:
  ```sh
  scripts/install-git-hooks.sh                 # once per clone; --uninstall removes it
  ```
  The `pre-push` hook runs `scripts/check-media-sites.sh` only when the commits you're pushing change `Sources/VelaMedia`, `Sources/VelaUI/Embeds`, `Tests/VelaMediaTests` or the check script, and stops the push if a site fails. Other pushes only cost a `git log`. `git push --no-verify` skips it. The hook never commits or signs anything, so it works with signed commits.

## Website analytics

velairc.app uses Google Analytics. **The app has none, and must never get any:** no analytics, usage tracking or anything else that phones home. The one request Vela makes on its own is the daily update check (Sparkle), which sends only Vela's version, never a system profile, and can be turned off; keep it that way (see [Privacy](https://velairc.app/help/privacy#updates)).

- **Where it lives:** `website/.vitepress/theme/analytics.ts` (loading, consent and events) and `analyticsRules.ts` (the rules, tested by `npm test` in `website/`). It runs only on velairc.app, never on a local preview.
- **Consent:**
  - Visitors whose time zone is in Europe get a banner, and Google's tag doesn't load until they choose **Allow**.
  - Global Privacy Control counts as a no.
  - Anyone can change their choice on the [Privacy page](https://velairc.app/help/privacy#this-website).
  - `npm run docs:check` fails if a page loads Google's tag directly.
- **Events:** Google's tag counts the first page view, scrolling and outbound clicks itself. `analytics.ts` adds:
  - `page_view` for each page after the first;
  - `vela_download` for a Vela.dmg link (`file_name`, `placement`);
  - `github_repo_click` for other repository links (`link_type`, `placement`);
  - `copy_code` (`code_language`);
  - `search` (`search_term`, and `result_count`, at most 16).
- **Try it:** add `?analytics=debug` to any URL. It works locally too. Events are logged to the console instead of sent, for as long as the tab stays open.
- **When you change what's measured,** update the Privacy page's "This website" section to match.

## Contributing a theme

1. Start from an existing theme in `Packages/VelaKit/Sources/VelaTheme/BuiltInThemes/`, or export one from Vela's theme editor.
2. Check contrast: chat text should meet WCAG AA against the chat background.
3. If your theme ports someone else's palette, confirm the license allows it and add attribution to `docs/THEME-CREDITS.md`.
4. Open a PR using the *Theme submission* template, with screenshots of all three message layouts.

## Reporting bugs

Questions are best asked in **#vela** on Libera.Chat ([web chat](https://web.libera.chat/#vela)). For bugs, use the bug report template. Include your macOS version, Vela version, and (if relevant) the IRC network or bouncer you were using. **Never paste passwords, SASL credentials or private logs.**

## License

By contributing, you agree that your contributions are licensed under the [MPL-2.0](LICENSE).
