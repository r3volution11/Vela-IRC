# Releasing Vela

How to ship a signed, notarized Vela and publish it on GitHub, from a one-time setup to checking the download. The website's **Download** button points at `https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg`. Every release must therefore:

- upload an asset named exactly `Vela.dmg`;
- be marked as the latest release, not a pre-release.

If no published release is marked latest, or the latest has no asset named `Vela.dmg`, that link returns 404.

## Release builds and development builds

Vela has two identities, so a release never collides with your own testing.

| | Release | Development |
| --- | --- | --- |
| Built by | `scripts/release.sh` (signed and notarized), or `scripts/run.sh` (local, unsigned) | `scripts/run.sh --dev`, or ⌘R in Xcode |
| Configuration | Release | Debug |
| App name | Vela | Vela Dev (a **DEV** badge on the Dock icon) |
| Bundle id | `io.github.r3volution11.Vela` | `io.github.r3volution11.Vela.dev` |
| Data | `~/Library/Containers/io.github.r3volution11.Vela/` | `~/Library/Containers/io.github.r3volution11.Vela.dev/` |

macOS keys an app's sandbox, preferences, notification settings and Siri & Shortcuts registration to its bundle id. Vela Dev therefore has its own settings, networks, history and Keychain items, and runs side by side with Vela.

The release build you ship uses the same identity as the `build/Vela.app` that `scripts/run.sh` makes. Installing a release over it keeps your settings and history. See [Upgrading from your local build](#upgrading-from-your-local-build).

## One-time setup

1. **Join the Apple Developer Program** (paid, yearly) with the Apple ID you'll sign with. Distributing outside the Mac App Store needs a Developer ID certificate, and only members can create one. Note your **Team ID**: Membership details at [developer.apple.com/account](https://developer.apple.com/account). It's a 10-character code.
2. **Create a Developer ID Application certificate.**
   - In Xcode → Settings → Accounts, add your Apple ID and select your team.
   - Click **Manage Certificates…**, then **+**, then **Developer ID Application**. Only the account holder can create this certificate.
   - It goes into your login keychain. Check it:
     ```sh
     security find-identity -v -p codesigning | grep "Developer ID Application"
     ```
     You should see one line like `"Developer ID Application: Your Name (TEAMID)"`.
   - **Back it up.** Export the certificate with its private key as a `.p12` from Keychain Access, and store it somewhere safe, such as your password manager. Losing the key means creating a new certificate.
3. **Store notarization credentials.**
   - Create an app-specific password at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords.
   - Store it in your keychain under the profile name the release script uses:
     ```sh
     xcrun notarytool store-credentials vela-notary --apple-id "<apple-id-email>" --team-id "<TEAMID>"
     ```
     `notarytool` asks for the password, and you never type it into a file.
   - Check it: `xcrun notarytool history --keychain-profile vela-notary`.
4. **Do a dry run.** `scripts/release.sh --skip-notarize --skip-preflight` signs with your Developer ID without contacting Apple. It shows that the certificate, export and disk image steps work. `--skip-preflight` leaves out the [release checks](#release-checks), which would otherwise stop the build until everything is ready to ship; the post-build checks still run.

## Before each release

Start by running the release checks on their own:

```sh
scripts/release.sh --preflight
```

It runs every [preflight check](#preflight-checks) and builds no release (only the scroll benchmark's own copy of Vela). It ends with a summary: each check with PASS, FAIL or SKIP, and for each failure what to do. Work through the steps below and run it again until it says **Ready to release**. `scripts/release.sh` runs the same checks before it builds anything, and refuses to build while one fails.

The checks catch what can be checked. Deciding the version, writing the changelog and the release notes, and trying the build are still up to you:

1. **Pick the version.** Use [semantic versioning](https://semver.org): bump the major version for breaking changes to settings or theme files (2.0.0), the minor version for new features (1.1.0) and the patch for fixes only (1.0.1). Call out every breaking change in the changelog.
   - The version is `MARKETING_VERSION` in `Vela.xcodeproj/project.pbxproj` (the Vela target's Debug and Release configurations).
   - Also bump `CURRENT_PROJECT_VERSION`, the build number, by 1 for every build you ship.
   - The easiest way is Xcode: Vela target → General → Version and Build.
   - *Checked:* both configurations agree, the version is newer than the previous release's, the build number is higher than that release's, and the tag `v<version>` isn't taken.
2. **Finish the changelog.** In `CHANGELOG.md`, rename `## Unreleased` to `## <version> - <yyyy-mm-dd>`. Read it through as a user would, and move anything that isn't user-facing out. Start a new empty `## Unreleased` section above it for the next cycle.
   - *Checked:* the newest version section has that heading and entries, and `## Unreleased` has none. Whether the entries read well is up to you.
3. **Refresh the adult-domain list:** `scripts/update-adult-domains.sh`. Check its summary; see [The adult-domain list](#the-adult-domain-list).
   - *Checked:* the list was refreshed since the previous release.
4. **Commit, push and wait for CI.**
   - *Checked:* you're on `main`, nothing is uncommitted, `origin/main` has your commit, and CI passed for exactly that commit. The checks also run the package tests, build and check the website, compare the generated files with the code, check the media sites against the real sites, and check that scrolling costs no more than the [scroll benchmark](#scroll-benchmark)'s baseline allows.
5. **Check the docs and screenshots.** Every user-facing change is documented on the site. If the UI changed, re-shoot with `website/scripts/screenshots.sh` and commit the images. *Not checked.*
6. **Try the Release build yourself:** `scripts/run.sh`, then use it for a bit. Release builds are optimized, and occasionally behave differently from the Debug build you develop with. *Not checked.*
7. **Write the release notes** (see [Publishing](#publishing)). *Not checked.*

## Building the release

```sh
scripts/release.sh
```

What it does:
1. Reads the version and build number from the Vela target's Release configuration.
2. Finds your **Developer ID Application** certificate and Team ID, and checks that the `vela-notary` profile exists.
3. **Runs the [preflight checks](#preflight-checks)** (`scripts/release-preflight.sh`): git, the version and changelog, CI, the adult-domain list, the generated files, the package tests, the website, the media sites and the scroll benchmark. If one fails, it prints the summary and stops before archiving.
4. **Archives** a universal (Apple silicon + Intel) Release build into `build/release/Vela.xcarchive`.
5. **Exports** it with Developer ID signing, the hardened runtime and a secure timestamp.
6. **Verifies** the signature (`codesign --verify --deep --strict`), both architectures, and that the App Sandbox entitlement is present.
7. **Notarizes the app and staples** the ticket to it, so it verifies offline even after it's copied out of the disk image.
8. **Builds the DMG** (`Vela.app` plus an Applications shortcut), signs it, **notarizes and staples** the DMG too, and runs a Gatekeeper assessment.
9. **Checks the DMG** as users get it, with the [post-build checks](#post-build-checks) (`scripts/verify-release.sh`). If one fails, it stops.
10. Writes `build/release/Vela.dmg`, `build/release/Vela-<version>.dmg` and `build/release/SHA256SUMS`.
11. Prints a summary of every check and its result.

Notarization usually takes a few minutes. If Apple rejects a submission, the script prints Apple's log; the usual causes are an unsigned nested binary or a missing hardened-runtime flag. For testing the pipeline, `--skip-notarize` signs without notarizing, and `--adhoc` doesn't use your Developer ID at all; see [Options](#options).

## Release checks

`scripts/release.sh` checks the release twice: the **preflight checks** before it builds anything, and the **post-build checks** on the finished DMG. Each check prints a PASS, FAIL or SKIP line as it runs; a failure says what's wrong and how to fix it. Every preflight check runs even after one fails, so you see everything to fix at once. The run ends with a summary of all of them, and any failure stops the release.

### Preflight checks

`scripts/release.sh --preflight` runs these on their own, and so does `scripts/release-preflight.sh`. They build no app other than the scroll benchmark's own copy, and don't touch your files or branches: besides fetching `main` and the tags from `origin`, they write only to ignored folders (`build/release-preflight/` for logs and the SwiftPM build, `build/benchmark/`, `website/node_modules`, the website's build output).

"The previous release" below is the newest `v*` tag in HEAD's history, other than this version's own tag.

#### Git

Skipped for `--adhoc`.

- **On main.** Releases are built from `main`. *If it fails:* merge your work into `main` and `git switch main`.
- **Clean working tree.** No uncommitted changes and no untracked files, so the release is exactly the commit CI tested. Ignored files such as `build/` don't count. *If it fails:* it lists the files. Commit them, stash them (`git stash -u`) or delete them. For a test build, `--allow-dirty` lets them through.
- **Pushed.** After `git fetch`, `origin/main` contains HEAD. *If it fails:* `git push origin main` (pull first if `origin/main` moved on), then wait for CI.
- **Tag `v<version>` is new.** Neither your clone nor `origin` has the tag. *If it fails:* if that version was released, bump the version and the changelog. If the tag was made by mistake and nothing was published, delete it, as the check says (`git tag -d v<version>`, `git push origin :refs/tags/v<version>`).

#### Version

Skipped for `--adhoc`.

- **Version.** `MARKETING_VERSION` is the same in the Vela target's Debug and Release configurations, has the form `<major>.<minor>.<patch>`, and is newer than the previous release. *If it fails:* set it in Xcode (Vela target → General → Version), which changes both configurations.
- **Build number.** `CURRENT_PROJECT_VERSION` is a whole number above 0, the same in both configurations, and higher than the previous release's (read from the project at its tag). *If it fails:* set it to one more than the previous release's (Xcode: Build).
- **Changelog section.** The newest version section in `CHANGELOG.md` is `## <version> - <yyyy-mm-dd>`, with a real date, and has entries. Headings, blank lines and HTML comments aren't entries. *If it fails:* rename `## Unreleased` to that heading, or fix the heading's version or date.
- **Changelog Unreleased.** `## Unreleased`, if there is one, has no entries; empty `### Added`-style headings are fine. Anything listed there is in this build, so it belongs in this release's section. *If it fails:* move the entries into `## <version> - <date>`.

#### CI

Skipped for `--adhoc` and `--skip-ci-check`. These checks ask GitHub with `gh`, so it must be installed and signed in (`gh auth login`).

- **CI workflow.** The **CI** workflow (`.github/workflows/ci.yml`) has a finished, successful run for exactly HEAD's commit. *If it fails:*
  - no run yet: push, wait for CI to finish (`gh run watch`), and run the checks again;
  - still running: wait for it, then run the checks again;
  - failed: the check links the run. Fix what failed, push and wait again; for a fluke, `gh run rerun <id> --failed`.
- **Media sites workflow.** If the **Media sites** workflow ran for HEAD (it runs when media code changes), it passed. Not running is fine; the media sites check below covers it. *If it fails:* as for CI. For a site that's broken, see [When the media check fails](#when-the-media-check-fails).

#### Adult-domain list

- **Adult-domain list.** The list was refreshed since the previous release: its header has a later `# Date:` or a different upstream `# Commit:` than the list at the previous release's tag, or today's date. If there's no previous release, it must be at most 30 days old. *If it fails:* run `scripts/update-adult-domains.sh`, check its summary and commit the list; see [The adult-domain list](#the-adult-domain-list).

#### Generated files

Files generated from the code must match what's committed. The checks compare what the code generates now with the committed files, without rewriting them. Ignored output, such as `website/_generated/`, isn't compared.

- **Settings reference.** `node website/scripts/generate.mjs` runs without errors and changes no committed file. It writes the settings, presets and themes reference into `website/_generated/`. *If it fails:* fix what it reports, or commit what it changed.
- **Theme schema.** `schemas/vela-theme.schema.json` matches `vela-theme-tool schema`. *If it fails:* `swift run --package-path Packages/VelaKit vela-theme-tool schema > schemas/vela-theme.schema.json`, then commit it.
- **Theme token table.** The table between the `TOKEN TABLE` markers in `docs/THEMES.md` matches `vela-theme-tool tokens`. *If it fails:* replace it with the output of `swift run --package-path Packages/VelaKit vela-theme-tool tokens`, then commit it.
- **Media sites page.** `website/reference/media-sites.md` matches `vela-media-tool docs`. *If it fails:* `swift run --package-path Packages/VelaKit vela-media-tool docs --write website/reference/media-sites.md`, then commit it.

#### Tests, website and media sites

- **Package tests** (skipped for `--skip-tests`). `swift test --package-path Packages/VelaKit` passes, and every test target's run reaches its end: a test that quits the test process early can leave swift test reporting success with tests that never ran, and the check names the last test such a run started. It builds in `build/release-preflight/swift`, apart from Xcode's and your editor's builds, so the first run takes a few minutes. *If it fails:* the check shows the build errors or the failing tests; everything is in `build/release-preflight/swift-test.log`. Fix them, then commit, push and wait for CI.
- **Website.** In `website/`: `npm ci` if `node_modules` is missing, then `npm run docs:build` and `npm run docs:check`. *If it fails:* the check shows the errors; everything is in `build/release-preflight/website.log`. Fix them and check again with `(cd website && npm run docs:build && npm run docs:check)`.
- **Media sites** (skipped for `--skip-media-check`, and for `--adhoc` unless you add `--media-check`). `scripts/check-media-sites.sh` resolves every live sample link in `MediaSites.swift` against the real site and prints its report. *If it fails:* it names the broken sites; see [When the media check fails](#when-the-media-check-fails). If a site is only down for a while, `--skip-media-check` lets the release go ahead.

#### Scroll benchmark

Skipped for `--skip-scroll-benchmark`, and for `--adhoc` unless you add `--scroll-benchmark`.

- **Scroll benchmark.** `scripts/benchmark-scroll.sh --check` builds its own copy of Vela, scrolls a big channel in it three times in each mode, and compares the medians with `benchmarks/scroll-baseline.json` (see [Scroll benchmark](#scroll-benchmark)). It takes about 12 minutes. Its window is invisible and never takes the focus, so you can keep working; busy apps make the numbers noisier. It's skipped when there's no baseline yet, or when the baseline was recorded on another kind of Mac, display refresh rate, layout or window size, since the numbers wouldn't compare. *If it fails:*
  - **Over budget:** the check lists the numbers. Everything is in `build/release-preflight/scroll-benchmark.log`, and each run in `build/release-preflight/scroll-benchmark/`. Find the change that made scrolling cost more ([profile it](#profiling-a-run)) and fix it. If the cost is intended, record a new baseline and commit it.
  - **It didn't finish:** see the log, and run it again. To release anyway, `--skip-scroll-benchmark`.

### Post-build checks

Once the DMG is made, notarized and stapled, `scripts/verify-release.sh` mounts it read-only (out of sight, in a temporary folder), checks the `Vela.app` inside as users get it, and unmounts it:

| Check | Passes when | If it fails |
| --- | --- | --- |
| Disk image | The DMG mounts read-only. | Build it again. |
| Bundle id | It's exactly `io.github.r3volution11.Vela`, never the `.dev` one. | The app came from the Debug configuration; build with `scripts/release.sh`. |
| Version | `CFBundleShortVersionString` is the version and `CFBundleVersion` the build number. | The project changed while building, or the build isn't from it; build again. |
| Architectures | The app has both `arm64` and `x86_64`. | Check that the archive is for `generic/platform=macOS` with `ONLY_ACTIVE_ARCH=NO`, as the script does. |
| App Sandbox | The `com.apple.security.app-sandbox` entitlement is on. | Check `CODE_SIGN_ENTITLEMENTS` (`Vela/Vela.entitlements`) in the Release configuration. |
| Signature | `codesign --verify --deep --strict` passes. | A file changed after signing, or a nested binary isn't signed. Build again. |
| Developer ID | Signed with a Developer ID Application certificate of your Team ID, with a secure timestamp. | Check the certificate (see [If something goes wrong](#if-something-goes-wrong)) and `VELA_TEAM_ID`. |
| Gatekeeper | `spctl -a -vvv` on the app says "Notarized Developer ID". | Notarization or stapling didn't work; build again and read Apple's log. |
| Stapled ticket (app), (DMG) | `xcrun stapler validate` passes on the app and on the DMG. | As for Gatekeeper. |
| Applications link | The DMG has its Applications shortcut. | Build again. |

`--skip-notarize` skips the Gatekeeper and stapled-ticket checks, and `--adhoc` also skips the Developer ID check; the summary lists them as skipped. When a post-build check fails, `build/release/Vela.dmg` stays for you to look at, but `Vela-<version>.dmg` and `SHA256SUMS` aren't written.

To check a DMG again, such as the one you downloaded after publishing:

```sh
scripts/verify-release.sh build/release/Vela.dmg
scripts/verify-release.sh ~/Downloads/Vela.dmg --version 1.1.0 --build 2 --team <TEAMID>
```

It expects the project's version and build number unless you give `--version` and `--build`, and any Developer ID team unless you give `--team` (or set `VELA_TEAM_ID`).

### Options

| Option | What it does |
| --- | --- |
| `--preflight` | Runs only the preflight checks and builds no release. It doesn't look for your certificate. The first thing to run when you prepare a release. |
| `--skip-notarize` | Signs with your Developer ID but doesn't notarize, for testing the pipeline. The post-build checks skip Gatekeeper and the stapled tickets. |
| `--adhoc` | No Developer ID at all, for testing on your own Mac only; other Macs will refuse the app. Skips the git, version and CI checks, the media check (add `--media-check` to run it) and the scroll benchmark (add `--scroll-benchmark`). The post-build checks that apply still run. |
| `--allow-dirty` | Lets uncommitted changes through the clean working tree check, for test builds. The check shows as skipped. |
| `--skip-tests` | Skips the package tests. |
| `--skip-ci-check` | Skips asking GitHub about CI, for instance when you're offline or GitHub is down. |
| `--skip-media-check` | Skips the media sites check. Use it when you've looked at the failure and it shouldn't hold up the release, such as a site that's down for an hour. |
| `--media-check` | Checks the media sites even with `--adhoc`. |
| `--skip-scroll-benchmark` | Skips the scroll benchmark, which takes about 12 minutes. Use it when you've looked at a failure and it shouldn't hold up the release, or when the Mac is busy with something else. |
| `--scroll-benchmark` | Runs the scroll benchmark even with `--adhoc`. |
| `--skip-preflight` | Skips every preflight check. **Only for emergencies, and for dry runs you won't ship**: it prints a warning at the start and the end, and the post-build checks still run. After an emergency release, run `scripts/release.sh --preflight` as soon as you can. |

`scripts/release-preflight.sh` takes `--adhoc`, `--allow-dirty`, `--skip-tests`, `--skip-ci-check`, `--skip-media-check`, `--media-check`, `--skip-scroll-benchmark` and `--scroll-benchmark` too, and `--help` lists them.

## Checking the build before you publish

The [post-build checks](#post-build-checks) have already checked the DMG's identity, version, architectures, sandbox, signature, notarization and stapling. What's left is to test what users will get, not your local build, with a real install:

1. Quit any running Vela and copy `Vela.app` from the DMG to `/Applications`.
2. Open it from there. On first launch, macOS asks for your Keychain password once per saved network password; see below.
3. Connect a network, and check inline media, the notification permission prompt, and **Catch me up** if Apple Intelligence is on.
4. Ideally, try it on a second Mac or a fresh user account with nothing of Vela's on it, opening the DMG from **Downloads** so Gatekeeper sees the quarantine flag.

### Upgrading from your local build

The release has the same bundle id as `build/Vela.app`, so it uses the same settings, networks and history. Your saved passwords stay in the Keychain, but they were created by a differently signed copy, so macOS asks once whether the release may use each one. Click **Always Allow**.

After you've switched, delete `build/Vela.app`, or at least don't keep both copies around. Two apps with the same bundle id confuse Siri, Shortcuts and Spotlight about which one to open.

## Publishing

```sh
v=1.1.0   # the version you set
git tag -s "v$v" -m "Vela $v"     # signed tag (1Password), or -a for unsigned
git push origin "v$v"
gh release create "v$v" build/release/Vela.dmg "build/release/Vela-$v.dmg" build/release/SHA256SUMS \
  --title "Vela $v" --notes-file release-notes.md --latest
```

- **Release notes:** a short, friendly rewrite of the changelog section with highlights first. Link the full [changelog](https://velairc.app/changelog). Write it in `release-notes.md`, and don't commit that file.
- **Don't** mark it as a pre-release: pre-releases aren't "latest", so the Download button would skip them.

## After publishing

1. **Check the download:**
   ```sh
   curl -sIL https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg | grep -i location
   ```
   It should end in `/download/v<version>/Vela.dmg`. Then download it with a browser, check it with `scripts/verify-release.sh ~/Downloads/Vela.dmg --version <version> --build <build>`, and install it once more.
2. **Check the website:** the **Deploy Website** workflow runs on every push to `main`. Check that the changelog page shows the new version first, and that velairc.app's Download button gets the new DMG.
3. **Start the next cycle:** make sure `CHANGELOG.md` has an empty `## Unreleased` section.

## If something goes wrong

- **A bad release:** don't delete the release. Ship a fixed version (bump the patch number) and mark it latest. If the build is harmful, delete only its DMG assets and say so in the release notes.
- **"No Developer ID Application certificate found":** the certificate isn't in the login keychain, or its private key is missing (it shows without a disclosure triangle in Keychain Access). Re-import your `.p12` backup.
- **"Notarization profile not found":** run the `store-credentials` step again.
- **Gatekeeper rejects the DMG on another Mac:** run `scripts/verify-release.sh` on that DMG. It runs `xcrun stapler validate` on both the DMG and the app inside it, and checks that `spctl` says "Notarized Developer ID".
- **A preflight or post-build check fails:** see [Release checks](#release-checks) for what each one needs.

## When the media check fails

The check resolves each sample link in `Packages/VelaKit/Sources/VelaMedia/MediaSites.swift` the way Vela does, and fails a site when what it gets back isn't what the sample expects. The report (also in `build/media-sites/report.txt`) says what went wrong for each link, for example `✗ thumbnail: no thumbnail` or `✗ MP4 copy: HTTP 404`. Look at the failing link in a browser, then:

- **The sample is gone** (the video was deleted, the GIF taken down): pick a new sample that will last, replace it in `MediaSites.swift`, and run `scripts/check-media-sites.sh --site <id>`. Nothing about Vela is broken.
- **The site changed how it works** (a new address format, different page tags, a moved oEmbed endpoint): users are seeing it too. Fix the resolver in `VelaMedia`, with a unit test against a stubbed response, update the entry if the links or domains changed, and regenerate the docs page (see [CONTRIBUTING.md](../CONTRIBUTING.md#adding-or-changing-a-site)). Mention the fix in `CHANGELOG.md`.
- **The site is down or slow right now:** each failing link is already tried three times, a few seconds apart. Run the check again later, or release with `--skip-media-check` if it can't wait.
- **Every site fails:** check your connection. The check needs internet access.

A site that keeps failing for reasons Vela can't fix is better dropped from `MediaSites.swift` and the recognizers than left broken; say so in the changelog.

## Scroll benchmark

Vela must scroll smoothly on the slowest Macs it supports: 2019–2020 Intel MacBook Pros and iMacs, and an M1 with 8 GB. `scripts/benchmark-scroll.sh` measures scrolling the same way every time, so you can tell whether a change made it cheaper or dearer:

```sh
scripts/benchmark-scroll.sh                      # build, 3 runs per mode, compare with the baseline
scripts/benchmark-scroll.sh --update-baseline    # the same, then record the medians as the new baseline
scripts/benchmark-scroll.sh --modes normal --runs 5 -- --bench-scenarios sweep
scripts/benchmark-scroll.sh --no-build -- --preset classic --set chat.showAvatars=true
```

- **What runs.** An optimized Release build for this Mac's architecture, in `build/benchmark`, with a bundle id of its own (`io.github.r3volution11.Vela.bench`, named **Vela Bench**). It has its own sandbox, settings and Keychain, runs in demo mode and never touches your data or your running Vela. It's a background app (no Dock icon or menu bar), started from its executable rather than with `open`, and unregistered from LaunchServices afterwards.
- **The channel.** About 2,000 lines over five days, generated from a fixed seed (`ScrollBenchmarkContent`): one-liners, long wrapped messages, mentions, IRC formatting, emoji, replies, reactions, joins, parts and quits with a 96-line netsplit, day dividers, photos, animated GIFs (plain files and GIPHY's MP4s), YouTube players and link cards. Previews, pictures, GIFs and thumbnails come from local stand-ins (`ScrollBenchmarkMedia`), so nothing is fetched and every run sees the same thing. The theme is Palenight, in a 1280×800 window on the display with the menu bar.
- **The scrolling.** Synthetic trackpad swipes sent to the window (no accessibility permission needed), in five scenarios:
  - `slow`: short swipes up, with a pause after each, as when reading back;
  - `medium`: steady swipes that glide;
  - `fling`: hard flings up to the top, then down to the bottom;
  - `jump`: to the top and back to the bottom, as the Home and End keys do, three times;
  - `sweep`: exactly 48 points every frame, 24,000 points up and back down. However long a frame takes, the next moves the list the same distance, so the work done depends on Vela, not on how fast the Mac is. `sweep-a11y` does it again with SwiftUI's accessibility on (see below).

  A run takes about 100 seconds. **You won't see it or notice it:** the window is on screen and draws as usual, its display link ticking at the display's rate, but it's fully transparent and lets clicks through. Vela Bench is never activated and its window never becomes key, nothing is clicked, and the pointer stays where it is, so you can keep typing in another app. Runs measured this way do the same work as with the window showing (the same rows built, text drawn and instructions per frame, within 3%). To watch a run, pass `-- --bench-window visible`. (An inactive window gets no hover events, so hovering isn't measured; `-- --bench-pointer list` moves your pointer over the list anyway, and the script warns first.) Busy apps make the numbers noisier, so lighter work is better meanwhile. Plug in, and turn off Low Power Mode.
- **The modes.** `normal`, and `lowend`: under `taskpolicy -b`, background priority on the slowest cores, which runs CPU-bound code about 2.9 times slower on an M5 Pro. It stands in for the slowest supported Macs. (`taskpolicy -c background` slows it down too, but by anywhere from 1.6 to 3 times between runs.)
- **Accessibility.** As soon as any accessibility client looks at a window, SwiftUI builds accessibility for every row it lays out, from then on: VoiceOver, but also window managers, launchers and menu bar tools such as BetterTouchTool, Bartender, Alfred or Raycast. Scrolling then costs about twice as much, and many people have such a tool running. It can start in the middle of a run, so each scenario reports whether it was on (`a11y`), and the summary keeps those runs apart (`-a11y`). `sweep-a11y` turns it on deliberately, so both costs are measured every time.
- **The numbers**, per scenario:
  - frame intervals while the list moves (p50, p95, p99), frames over 1.5 and 2 times the refresh interval, and hitch time per second (Apple's measure: under 5 ms/s is good, over 10 is bad);
  - CPU time per second, per 1,000 points scrolled and per frame the list moved in, and on Apple silicon instructions per frame. These depend least on the Mac and the display;
  - the main thread's share, and memory (`phys_footprint`, peak and at the end).
- **Results** go to `build/benchmark/results/<date-time>/`: each run's JSON and summary in `runs/`, and `summary.json` with the medians and the spread between runs.

### Budgets

`--check`, which the preflight check uses, fails when a median is over its budget against `benchmarks/scroll-baseline.json`. (Until a baseline is recorded, that file is a placeholder and the check is skipped.) The budgets are in `scripts/lib/benchmark-scroll.py`:

| Number | Scenarios | Fails when it's over | Why |
| --- | --- | --- | --- |
| Instructions per frame | `sweep`, `sweep-a11y` | the baseline + 15% | Between runs it differs by about 2% on a quiet Mac, and by up to 8% while other apps are building. Real regressions are bigger: a body re-evaluated every frame cost 30% more. |
| CPU time per frame | `sweep`, `sweep-a11y`, `normal` mode only | the baseline + 40% + 0.3 ms | The same work runs up to 30% slower when other apps are busy, and under `taskpolicy -b` it swings by a third, so `lowend` only reports it. Macs without instruction counts lean on this one. |
| Peak memory | every run | the baseline + 25% + 25 MB | It varies by a few percent with what's cached when. |

Hitches and frame times are compared and printed too, but never fail the check: they swing by half or more between runs whenever something else on the Mac wakes up. A baseline compares only with runs on the same kind of Mac, display refresh rate, layout and window size; otherwise the check is skipped and says why. To record one, run `scripts/benchmark-scroll.sh --update-baseline` on a quiet Mac, look at the summary, and commit `benchmarks/scroll-baseline.json`. Record a new one whenever a change is meant to cost more, or made scrolling cheaper, and say so in the commit.

### Profiling a run

Every scenario is a Points of Interest interval, so a trace shows where each one is. Record the benchmark under Instruments with `xctrace` (Time Profiler, SwiftUI or Animation Hitches), launching the app bundle so xctrace can tell it from your Vela:

```sh
app=build/benchmark/DerivedData/Build/Products/Release/Vela.app
out=~/Library/Containers/io.github.r3volution11.Vela.bench/Data/tmp/profile.json
xcrun xctrace record --template 'Time Profiler' --output build/benchmark/time.trace --no-prompt \
  --launch -- "$app" --demo --scroll-benchmark --bench-output "$out" --bench-scenarios sweep,sweep-a11y
open build/benchmark/time.trace
```

## The adult-domain list

The adult-site filter blocks previews (never links) from domains on a list bundled in `Packages/VelaKit/Sources/VelaMedia/Resources/adult-domains.txt`. Vela doesn't download the list at runtime, so each release ships whatever was last committed. `scripts/update-adult-domains.sh` rebuilds it from [Sinfonietta/hostfiles](https://github.com/Sinfonietta/hostfiles) (MIT), at the latest upstream commit or at the one given with `--ref <sha>`.

- **Read the summary.** It shows which upstream entries were excluded and how many domains were added and removed. Small changes are listed in full.
- **Keep general-purpose sites off the list.** If upstream lists a social network, image host, CDN or other mainstream site, add it to `scripts/adult-domains-exclude.txt` and run the script again. Exclusions match exactly, so specific adult subdomains of a platform (such as one blog) stay listed.
- **Size checks.** The script refuses a list with fewer than 10,000 domains, or one under 70% of the current count. If upstream really did shrink, find out why, then rerun with `--force`.
- **License.** The script stops if the upstream license is no longer MIT. The notice is in the list's header and in `THIRD_PARTY_NOTICES.md`.

## Notes

- **Releases are universal.** They run on Apple silicon and Intel, and need macOS 26 or later.
- **The app is sandboxed and uses the hardened runtime.** Entitlements are in `Vela/Vela.entitlements`; the release script refuses a build without the App Sandbox entitlement.
- **Notarization happens twice.** The app is notarized and stapled first, so it stays verifiable offline after it's copied out of the disk image. Then the DMG itself is notarized and stapled.
- **Updates are manual for now.** Users download new versions from the website. Automatic updates (Sparkle) and the Mac App Store are on the roadmap.
