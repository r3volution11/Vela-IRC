# Releasing Vela

How to ship a signed, notarized Vela and publish it on GitHub, from a one-time setup to checking the download. Once everything is ready, one command does the release: `scripts/release.sh --publish` builds, checks, tags and publishes it.

The website's **Download** button points at `https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg`. Every release must therefore:

- upload an asset named exactly `Vela.dmg`;
- be marked as the latest release, not a pre-release.

If no published release is marked latest, or the latest has no asset named `Vela.dmg`, that link returns 404.

A release has just the one disk image, with no version in its name: the release page already says which version it is. The mounted disk is named "Vela", and from version 2 on it carries the major version ("Vela 2"), so a major release looks like one. `--publish` takes care of both.

Beside it, `SHA256SUMS` lists the DMG's SHA-256. The Alfred workflow and the Raycast extension aren't part of a Vela release: they're released from their own repositories, and the app carries a copy of the workflow for **Settings → Integrations**. See [The Alfred workflow](#the-alfred-workflow).

From 1.1, Vela updates itself with [Sparkle](https://sparkle-project.org): installed copies read the update feed at `https://velairc.app/appcast.xml` and install the same `Vela.dmg` from the GitHub release. `--publish` signs the DMG for the updater and adds the release to the feed. See [Updates](#updates).

## Release builds and development builds

Vela has two identities, so a release never collides with your own testing.

| | Release | Development |
| --- | --- | --- |
| Built by | `scripts/release.sh` (signed and notarized), or `scripts/run.sh` (local, unsigned) | `scripts/run.sh --dev`, or ⌘R in Xcode |
| Configuration | Release | Debug |
| Signed | With your Developer ID certificate (`scripts/release.sh`), or ad hoc (`scripts/run.sh`) | Ad hoc, or with your own certificate after `scripts/dev-signing.sh` (git-ignored `Config/Signing.xcconfig`), so the Keychain trusts every build |
| App name | Vela | Vela Dev |
| App icon | Glint (`Vela/AppIcon.icon`) | Sunrise with two more stars (`Vela/AppIconDev.icon`) |
| Bundle id | `io.github.r3volution11.Vela` | `io.github.r3volution11.Vela.dev` |
| Data | `~/Library/Containers/io.github.r3volution11.Vela/` | `~/Library/Containers/io.github.r3volution11.Vela.dev/` |
| Updates | From velairc.app's feed, once the [update key](#the-update-signing-key) is in `Vela/Info.plist` | Never: no feed, and the updater isn't started |

macOS keys an app's sandbox, preferences, notification settings and Siri & Shortcuts registration to its bundle id. Vela Dev therefore has its own settings, networks, history and Keychain items, and runs side by side with Vela.

The release build you ship uses the same identity as the `build/Vela.app` that `scripts/run.sh` makes. Installing a release over it keeps your settings and history. See [Upgrading from your local build](#upgrading-from-your-local-build).

## One-time setup

1. **Join the Apple Developer Program** (paid, yearly) with the Apple ID you'll sign with. Distributing outside the Mac App Store needs a Developer ID certificate, and only members can create one. Note your **Team ID**: Membership details at [developer.apple.com/account](https://developer.apple.com/account). It's a 10-character code.
2. **Create a Developer ID Application certificate.**
   - In Xcode → Settings → Accounts, add your Apple ID and select your team (not the free Personal Team).
   - Click **Manage Certificates…**, then **+**, then **Developer ID Application**. Only the account holder can create this certificate.
   - **If Xcode says "This operation can only be performed by the account holder"** although you are: accept any pending agreement at [developer.apple.com/account](https://developer.apple.com/account), or create the certificate on the website instead.
     1. In Keychain Access, choose **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority…**, enter your email and name, choose **Saved to disk** and save the request.
     2. At developer.apple.com → **Certificates, IDs & Profiles** → **Certificates** → **+**, choose **Developer ID Application** with the **G2 Sub-CA**, upload the request, download the certificate and double-click it.
     3. Install Apple's intermediate certificate too: the website doesn't, Xcode does. Without it the certificate shows as invalid. Download [DeveloperIDG2CA.cer](https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer) and double-click it.
   - It goes into your login keychain. Check it:
     ```sh
     security find-identity -v -p codesigning | grep "Developer ID Application"
     ```
     You should see one line like `"Developer ID Application: Your Name (TEAMID)"`. If that prints nothing, but `security find-identity -p codesigning` (without `-v`) lists it, the intermediate certificate is missing; see above.
   - **Back it up.** Export the certificate with its private key as a `.p12` from Keychain Access, and store it somewhere safe, such as your password manager. Losing the key means creating a new certificate.
3. **Store notarization credentials** under the profile name the release script uses, `vela-notary`. Either way works; the script only uses the profile.
   - **An App Store Connect API key (recommended).** It belongs to your developer team, works only for App Store Connect and notarization, and keeps your Apple ID's password out of it.
     1. At [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Users and Access** → **Integrations** → **App Store Connect API**: the first time, click **Request Access** (the account holder approves it).
     2. Under **Team Keys** (not Individual Keys), click **+**, name it (say, "Vela notarization") and give it the **Developer** role.
     3. Download the `.p8` file (you can only download it once), and note its **Key ID** and the **Issuer ID** above the list.
     4. Store it:
        ```sh
        xcrun notarytool store-credentials vela-notary --key ~/Downloads/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER-ID>
        ```
        Then keep the `.p8` in your password manager and delete the download: `notarytool` keeps its own copy in your keychain.
   - **Or an app-specific password.** Quicker, but tied to your Apple ID, and app-specific passwords can also reach its iCloud mail, contacts and calendars. Create one at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords, then:
     ```sh
     xcrun notarytool store-credentials vela-notary --apple-id "<apple-id-email>" --team-id "<TEAMID>"
     ```
     `notarytool` asks for the password, and you never type it into a file.
   - Check it: `xcrun notarytool history --keychain-profile vela-notary`.
4. **Set up the GitHub CLI:** `brew install gh`, then `gh auth login`. The CI checks and publishing use it.
   - To sign release tags, set up signing in git, such as an SSH key in 1Password. Publishing signs the tag whenever git has a signing key (`user.signingkey`, or `tag.gpgSign`).
5. **Set up the 1Password CLI**, which reads the update signing key: `brew install 1password-cli`, then in the 1Password app turn on **Settings → Developer → Integrate with 1Password CLI**. Check it with `op --account my.1password.com vault list`.
6. **Create the update signing key, once:** `scripts/sparkle-key.sh --create`, then paste the public key it prints into `Vela/Info.plist` (replacing `SPARKLE_PUBLIC_KEY_PLACEHOLDER`) and commit it. See [The update signing key](#the-update-signing-key). Until then, every release build refuses to start.
7. **Save the GIF key** (KLIPY, for the picker's GIF search; development builds only for now) in 1Password as an API Credential item, "Vela - KLIPY - Mac API Credentials", in the Personal vault, with the key in its **credential** field. Check it with `scripts/klipy-key.sh --check`. See [The GIF key](#the-gif-key).
8. **Do a dry run.** `scripts/release.sh --skip-notarize --skip-preflight` signs with your Developer ID without contacting Apple. It shows that the certificate, export and disk image steps work. `--skip-preflight` leaves out the [release checks](#release-checks), which would otherwise stop the build until everything is ready to ship; the post-build checks still run.

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
2. **Finish the changelog.** In `CHANGELOG.md`, rename `## Unreleased` to `## <version> - <yyyy-mm-dd>`. Read it through as a user would, and move anything that isn't user-facing out. Start a new empty `## Unreleased` section above it for the next cycle. The section also becomes the [release notes](#release-notes).
   - *Checked:* the newest version section has that heading and entries, and `## Unreleased` has none. Whether the entries read well is up to you.
3. **Refresh the adult-domain list:** `scripts/update-adult-domains.sh`. Check its summary; see [The adult-domain list](#the-adult-domain-list).
   - *Checked:* the list was refreshed since the previous release.
4. **Bundle the newest Alfred workflow.** If [the workflow](https://github.com/r3volution11/vela-alfred-workflow/releases) has a release newer than the one `integrations/alfred-workflow.json` records (or the record says `local build`), bundle it: `scripts/update-alfred-workflow.sh --release latest`, then commit both files. See [The Alfred workflow](#the-alfred-workflow).
   - *Checked:* the bundled file matches its record. Whether it's the newest release is up to you; the preflight's summary says when it's a local build.
5. **Commit, push and wait for CI.**
   - *Checked:* you're on `main`, nothing is uncommitted, `origin/main` has your commit, and CI passed for exactly that commit. The checks also run the package tests, build and check the website, compare the generated files with the code, check the media sites against the real sites, and check that scrolling costs no more than the [scroll benchmark](#scroll-benchmark)'s baseline allows.
6. **Check the docs and screenshots.** Every user-facing change is documented on the site. If the UI changed, re-shoot with `website/scripts/screenshots.sh` and commit the images. *Not checked.*
7. **Try the Release build yourself:** `scripts/run.sh`, then use it for a bit. Release builds are optimized, and occasionally behave differently from the Debug build you develop with. *Not checked.*
8. **Check the release notes.** They're made from the changelog section and a standard footer; see [Release notes](#release-notes). To write your own, pass `--notes <file>`.
   - *Checked:* before it builds anything, `--publish` checks that the changelog section has entries, or that the `--notes` file isn't empty.

## Building and publishing the release

```sh
scripts/release.sh --publish
```

That's the whole release. It builds and checks Vela, then tags the commit it built, pushes the tag and publishes the GitHub release. Without `--publish`, it stops once the DMG is built and checked, and you [publish by hand](#publishing-by-hand).

What it does:
1. Reads the version and build number from the Vela target's Release configuration.
2. Finds your **Developer ID Application** certificate and Team ID, and checks that the `vela-notary` profile exists.
3. Checks that `Vela/Info.plist` has the [update signing key](#the-update-signing-key)'s public half, not the placeholder (`--adhoc` only notes it). With `--publish`, also checks that `gh` is installed and signed in, that the key in 1Password is the one `Vela/Info.plist` has (1Password asks you to approve), that the [update feed](#the-update-feed) takes this build, and that there are [release notes](#release-notes). If not, it stops before building anything.
4. **Runs the [preflight checks](#preflight-checks)** (`scripts/release-preflight.sh`): git, the version and changelog, CI, the adult-domain list, the generated files, the bundled Alfred workflow, the package tests, the website, the media sites and the scroll benchmark. If one fails, it prints the summary and stops before archiving.
5. **Archives** a universal (Apple silicon + Intel) Release build into `build/release/Vela.xcarchive`. The build's full output is in `build/release/archive.log`.
6. **Exports** it with Developer ID signing, the hardened runtime and a secure timestamp, signed with `Vela/Vela.entitlements`. The export signs Sparkle's framework, XPC services and helpers with your Developer ID too.
7. **Verifies** the signature (`codesign --verify --deep --strict`), both architectures, and that the App Sandbox entitlement is present.
8. **Notarizes the app and staples** the ticket to it, so it verifies offline even after it's copied out of the disk image.
9. **Builds the DMG** with `scripts/make-dmg.sh` (`Vela.app` plus an Applications shortcut, in a window drawn like the website; see [The disk image window](#the-disk-image-window)), signs it, **notarizes and staples** the DMG too, and runs a Gatekeeper assessment.
10. **Checks the DMG** as users get it, with the [post-build checks](#post-build-checks) (`scripts/verify-release.sh`). If one fails, it stops.
11. Writes `build/release/Vela.dmg` and `build/release/SHA256SUMS`.
12. With `--publish`, **publishes** the release once every check has passed: signs the DMG for the updater and adds it to the update feed, then the tag, the GitHub release, a check of the download, and the feed on velairc.app. See [Publishing](#publishing).
13. Prints a summary of every check and its result.

Notarization usually takes a few minutes. If Apple rejects a submission, the script prints Apple's log; the usual causes are an unsigned nested binary or a missing hardened-runtime flag. For testing the pipeline, `--skip-notarize` signs without notarizing, and `--adhoc` doesn't use your Developer ID at all; see [Options](#options).

## Release checks

`scripts/release.sh` checks the release twice: the **preflight checks** before it builds anything, and the **post-build checks** on the finished DMG. Each check prints a PASS, FAIL or SKIP line as it runs; a failure says what's wrong and how to fix it. Every preflight check runs even after one fails, so you see everything to fix at once. With `--publish`, the [publishing](#publishing) steps add their own lines. The run ends with a summary of all of them, and any failure stops the release.

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

#### Updates

- **Update key.** `Vela/Info.plist`'s `SUPublicEDKey` is a public key (the base64 of 32 bytes), not the placeholder. Skipped for `--adhoc`. *If it fails:* create the key and paste its public half; see [The update signing key](#the-update-signing-key).
- **Update feed.** `website/public/appcast.xml` passes `node website/scripts/appcast.mjs check`, and has no item for this build number yet. *If it fails:* fix what it lists (don't edit items by hand; see [The update feed](#the-update-feed)), or bump `CURRENT_PROJECT_VERSION` if this build is already in it.

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

#### Alfred workflow

- **Bundled workflow.** `scripts/update-alfred-workflow.sh --check` passes: `Vela/Integrations/Vela.alfredworkflow` is a zip with the workflow's `info.plist`, and its SHA-256 and version are the ones `integrations/alfred-workflow.json` records. The line says where it came from, and notes a local build. *If it fails:* bundle it again with `scripts/update-alfred-workflow.sh --release <tag>` (or `--local`) and commit both files; never edit either by hand. See [The Alfred workflow](#the-alfred-workflow).

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
| App Sandbox | The `com.apple.security.app-sandbox` entitlement is on. | Check that `scripts/release.sh` passes `VELA_ENTITLEMENTS=Vela/Vela.entitlements`. |
| Updater entitlements | The app can reach the network and has the mach-lookup exception for Sparkle's installer (`io.github.r3volution11.Vela-spks` and `-spki`), and none of the local builds' exceptions (`disable-library-validation`, `get-task-allow`). | Build with `scripts/release.sh`, which signs with `Vela/Vela.entitlements`; keep the exception there. `--adhoc` allows the local entitlements. |
| Update settings | `Info.plist` has the feed `https://velairc.app/appcast.xml`, the installer service (`SUEnableInstallerLauncherService`), automatic checks on, a daily interval, no system profile, no downloader service, and verification before extraction. | Check `Vela/Info.plist`, and that the Release configuration's `INFOPLIST_FILE` is `Vela/Info.plist`. |
| Update key | `SUPublicEDKey` is a public key, not the placeholder. | See [The update signing key](#the-update-signing-key). `--adhoc` only notes it. |
| Sparkle | `Sparkle.framework` is the version `Package.resolved` pins, and it, `Installer.xpc`, `Downloader.xpc`, `Autoupdate` and `Updater.app` each verify, with the hardened runtime, a Developer ID certificate of the app's team and a secure timestamp (`--adhoc`: they verify). | Archive and export with `scripts/release.sh`. Never add `--deep` to the signing flags: Sparkle's services need their own signatures. |
| GIF key | `Info.plist` has no `VelaKLIPYAPIKey`: GIF search is only in development builds until KLIPY approves Vela's key. | Check `Vela/Info.plist` and the build settings. See [The GIF key](#the-gif-key). |
| Private Cloud Compute | The app doesn't offer it: the switch's title ("Use Private Cloud Compute for long catch-ups") isn't in its code, Catch Me Up's description in the App Intents metadata doesn't mention it, and it doesn't have the `com.apple.developer.private-cloud-compute` entitlement. It's only in development builds until Apple grants Vela the entitlement. | See [Private Cloud Compute](#private-cloud-compute). |
| App Shortcuts | The app's App Intents metadata (`Contents/Resources/Metadata.appintents/extract.actionsdata`) has as many App Shortcuts as `Vela/VelaShortcuts.swift` declares (7 today). | Xcode's App Intents metadata processor dropped some. Its lines are kept out of the build output but saved in `build/release/archive.log`: fix what they point at and build again. |
| App Intents actions | The metadata has **Catch Me Up** (`CatchMeUpIntent`) and **Open Channel** (`OpenChannelIntent`) from the VelaIntents module. | As for App Shortcuts. |
| App Intents package | `extract.packagedata` includes `VelaIntentsPackage`, which brings in the VelaIntents package's intents. | Check that `VelaAppIntentsPackage` in `Vela/VelaShortcuts.swift` lists `VelaIntentsPackage`, then build again. |
| Alfred workflow | The app has `Contents/Resources/Vela.alfredworkflow`, with the SHA-256 `integrations/alfred-workflow.json` records. | Check that `Vela/Integrations/Vela.alfredworkflow` is committed and `scripts/update-alfred-workflow.sh --check` passes, then build again. |
| Signature | `codesign --verify --deep --strict` passes. | A file changed after signing, or a nested binary isn't signed. Build again. |
| Developer ID | Signed with a Developer ID Application certificate of your Team ID, with a secure timestamp. | Check the certificate (see [If something goes wrong](#if-something-goes-wrong)) and `VELA_TEAM_ID`. |
| Gatekeeper | `spctl -a -vvv` on the app says "Notarized Developer ID". | Notarization or stapling didn't work; build again and read Apple's log. |
| Stapled ticket (app), (DMG) | `xcrun stapler validate` passes on the app and on the DMG. | As for Gatekeeper. |
| Applications link | The DMG has its Applications shortcut. | Build again. |
| Window layout | The DMG has its window background, layout (`.DS_Store`) and volume icon. | Build again with `scripts/release.sh`. |

`--skip-notarize` skips the Gatekeeper and stapled-ticket checks, and `--adhoc` also skips the Developer ID checks (for Sparkle's code too), allows the local entitlements and only notes a missing update key; the summary lists what was skipped. When a post-build check fails, `build/release/Vela.dmg` stays for you to look at, but `SHA256SUMS` isn't written.

To check a DMG again, such as the one you downloaded after publishing:

```sh
scripts/verify-release.sh build/release/Vela.dmg
scripts/verify-release.sh ~/Downloads/Vela.dmg --version 1.1.0 --build 2 --team <TEAMID>
```

It expects the project's version and build number unless you give `--version` and `--build`, and any Developer ID team unless you give `--team` (or set `VELA_TEAM_ID`).

The App Intents checks are a function in `scripts/lib/release-checks.zsh`, so they also run on an app outside a disk image, such as the exported one:

```sh
zsh -c 'source scripts/lib/release-checks.zsh; check_app_intents build/release/export/Vela.app Vela/VelaShortcuts.swift'
```

### Options

| Option | What it does |
| --- | --- |
| `--preflight` | Runs only the preflight checks and builds no release. It doesn't look for your certificate. The first thing to run when you prepare a release. |
| `--publish` | Publishes the release on GitHub once it's built and every check has passed: the tag, the release and a check of the download. See [Publishing](#publishing). It doesn't go with `--preflight`, `--adhoc`, `--skip-notarize`, `--skip-preflight` or `--allow-dirty`. |
| `--notes <file>` | With `--publish`: use this file as the release notes, instead of making them from the changelog. A relative path is from the folder you run the script in. |
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

## Trying the build

The [post-build checks](#post-build-checks) have already checked the DMG's identity, version, architectures, sandbox, signature, notarization and stapling. What's left is to test what users will get, not your local build, with a real install.

With `--publish`, the release is public as soon as the checks pass, so do this right after, with the DMG from the release page. To try the build before anyone can download it, run `scripts/release.sh` without `--publish`, and [publish by hand](#publishing-by-hand) when you're happy with it.

1. Quit any running Vela and copy `Vela.app` from the DMG to `/Applications`.
2. Open it from there. On first launch, macOS asks for your Keychain password once per saved network password; see below.
3. Connect a network, and check inline media, the notification permission prompt, and **Catch me up** if Apple Intelligence is on.
4. Ideally, try it on a second Mac or a fresh user account with nothing of Vela's on it, opening the DMG from **Downloads** so Gatekeeper sees the quarantine flag.

### Upgrading from your local build

The release has the same bundle id as `build/Vela.app`, so it uses the same settings, networks and history. Your saved passwords stay in the Keychain, but they were created by a differently signed copy, so macOS asks once whether the release may use each one. Click **Always Allow**.

After you've switched, delete `build/Vela.app`, or at least don't keep both copies around. Two apps with the same bundle id confuse Siri, Shortcuts and Spotlight about which one to open.

## The disk image window

The DMG opens to a window drawn like the website in dark mode: Palenight, the hero's glow and gradient "Vela", and an arrow from the app to the Applications folder. `scripts/make-dmg.sh` makes it, and `scripts/release.sh` runs it.

- **`scripts/dmg/layout.json`** sets the window size and where the two icons go. Both of the files below read it.
- **`scripts/dmg/background.swift`** draws the background at 1x and 2x. `make-dmg.sh` joins them into one TIFF.
- **`scripts/dmg/settings.py`** lays out the window for [dmgbuild](https://github.com/dmgbuild/dmgbuild). dmgbuild writes Finder's layout file itself, so nothing scripts Finder, nothing appears on screen, and there are no permission prompts.
- **The plates under the icons** are there because Finder draws the names "Vela" and "Applications" itself, and won't let a disk image choose their color. Over a background picture they're usually black, even in dark mode. The plates are a mid-tone that keeps black or white text readable.
- **dmgbuild and its two dependencies** are pinned with hashes in `scripts/dmg/requirements.txt`. They install into `build/dmg-venv` the first time, which needs Python 3.10 or later (`brew install python`).
  - To update them, pick versions that have been out for at least two weeks.
  - Copy each version's wheel hash from PyPI.

To try a change, build a DMG from any `Vela.app` and open it:

```sh
scripts/make-dmg.sh build/release/Vela.app /tmp/Vela-test.dmg "Vela test"
```

Finder caches window layouts by volume name, so give each try a new name.

## Publishing

`scripts/release.sh --publish` publishes the release once the build has passed every check, and never when one failed:

1. **Signs Vela.dmg for the updater.** `op read` pipes the [update signing key](#the-update-signing-key) from 1Password into Sparkle's `sign_update` (from the packages Xcode resolved for the archive, at the version `Package.resolved` pins). The key is never in a file or an argument. The signature is then checked against the `SUPublicEDKey` of the app that was built, as installed copies will check it.
2. **Adds the release to the update feed** with `website/scripts/appcast.mjs`: version, build, minimum macOS, the DMG's URL on GitHub, its length and signature, and this version's changelog section as release notes. It commits `website/public/appcast.xml` ("Appcast: Vela <version>") on top of the commit it built. See [The update feed](#the-update-feed).
3. **Tags** the commit it built as `v<version>`, with the message `Vela <version>`.
   - The tag is signed (`git tag -s`) when git has a signing key: `user.signingkey`, or `tag.gpgSign`. With an SSH key in 1Password, 1Password asks you to approve it.
   - Otherwise it's an annotated tag (`git tag -a`), and the script prints a note saying so.
4. **Pushes** the tag to `origin`.
5. **Creates the GitHub release** with `gh release create --verify-tag --latest`. It's titled `Vela <version>`, with the [release notes](#release-notes) and two files: `Vela.dmg` and `SHA256SUMS`.
6. **Checks the download.** `releases/latest/download/Vela.dmg` must redirect to `releases/download/v<version>/Vela.dmg`. It tries for about a minute, while GitHub catches up. Then the DMG downloaded from that link must match `SHA256SUMS`.
7. **Pushes the feed's commit** to `main`, which deploys velairc.app (the **Deploy Website** workflow). The feed goes last, so installed copies are never offered an update whose download isn't there yet.
8. **Checks the feed online.** It waits up to about 8 minutes for `https://velairc.app/appcast.xml` to list this build.

Each step adds a PASS or FAIL line to the summary, under **Publish**. Only a notarized build that passed every check is published, so `--publish` doesn't go with `--preflight`, `--adhoc`, `--skip-notarize`, `--skip-preflight` or `--allow-dirty`. It also stops before building if the checkout changes while the preflight checks run, so the tag is always on the commit that was built.

### When a publishing step fails

The script stops and deletes nothing: not the tag, and not the release. After the summary, under **Finish by hand**, it says what was done and prints the commands left, from the step that failed on. For example, if the push worked but creating the release didn't:

```text
==> Finish by hand
    v1.1.0 is on origin, but the GitHub release wasn't created. Nothing was deleted. To finish, run:

      cd '/Users/you/Projects/Vela IRC'
      gh release create v1.1.0 build/release/Vela.dmg build/release/SHA256SUMS --repo r3volution11/Vela-IRC --verify-tag --title 'Vela 1.1.0' --notes-file build/release/release-notes.md --latest
      curl -sS -o /dev/null -w '%{redirect_url}\n' https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg
      curl -sSL https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg | shasum -a 256

    The first curl should print https://github.com/r3volution11/Vela-IRC/releases/download/v1.1.0/Vela.dmg,
    and the second 5f3a…  - (Vela.dmg's line in build/release/SHA256SUMS).
```

Fix what the failed check says, then run the commands. If `gh` made the release but couldn't finish it (say, an upload failed), the commands upload the files again and publish it instead. When signing or the feed failed, nothing is public yet, and the commands start with signing the DMG and adding it to the feed by hand. The feed's commit is always pushed last, once the download works.

### Release notes

Without `--notes`, the release notes are:

1. the body of this version's section in `CHANGELOG.md`, without its `## <version>` heading. Relative links, such as `ROADMAP.md`, point at the file on GitHub as of the tag;
2. then `scripts/release-notes-footer.md`: Requirements, Install, Update (with how to update from 1.0, which has no updater), Alfred and Raycast (**Settings → Integrations**) and Learn more. It's the same for every release; edit it there.

They're written to `build/release/release-notes.md` when the build starts (after the preflight checks), so you can read them while Vela builds.

The changelog section can start with a short paragraph and a few highlights before its `###` headings, as 1.0.0 and 1.1.0 do. The same section is the update window's release notes and **What's New**, so highlights written there reach everyone, while a `--notes` file changes only the GitHub release.

To write your own, such as a short, friendly rewrite with highlights first, pass the file: `scripts/release.sh --publish --notes ~/release-notes.md`. Link the full [changelog](https://velairc.app/changelog), and don't commit the file.

### Publishing by hand

If you built without `--publish`:

```sh
v=1.1.0   # the version you built
git tag -s "v$v" -m "Vela $v"     # tags HEAD, the commit you built; -a for an unsigned tag
git push origin "v$v"
gh release create "v$v" build/release/Vela.dmg build/release/SHA256SUMS \
  --verify-tag --title "Vela $v" --notes-file release-notes.md --latest
```

- **Release notes:** write `release-notes.md` from the changelog section and `scripts/release-notes-footer.md`, or as you like (see [Release notes](#release-notes)). Don't commit it.
- **Don't** mark it as a pre-release: pre-releases aren't "latest", so the Download button would skip them.
- **The update feed**, once the release and its download work. Sparkle's tools are in `build/DerivedData-release/SourcePackages/artifacts/sparkle/Sparkle/bin` after the archive:

  ```sh
  tools=build/DerivedData-release/SourcePackages/artifacts/sparkle/Sparkle/bin
  signature=$(op --account my.1password.com read --no-newline "op://Personal/Vela - Sparkle - Mac Update Signing Key/password" \
    | $tools/sign_update --ed-key-file - -p build/release/Vela.dmg)
  awk -v v="$v" '/^## /{f=($2==v)} f' CHANGELOG.md | sed 1d > build/release/appcast-notes.md
  node website/scripts/appcast.mjs add website/public/appcast.xml --version "$v" --build <build> --minimum-system 26.0 \
    --length $(stat -f %z build/release/Vela.dmg) --signature "$signature" --notes-file build/release/appcast-notes.md
  git commit -m "Appcast: Vela $v" -- website/public/appcast.xml
  git push origin main
  ```

## After publishing

1. **Check the download.** `--publish` has already checked that the website's link gives the new DMG and that it matches `SHA256SUMS`. After publishing by hand, check the link yourself:
   ```sh
   curl -sIL https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg | grep -i location
   ```
   It should end in `/download/v<version>/Vela.dmg`. Either way, download it with a browser, check it with `scripts/verify-release.sh ~/Downloads/Vela.dmg --version <version> --build <build>`, and install it once more (see [Trying the build](#trying-the-build)).
2. **Check the website:** the **Deploy Website** workflow runs on every push to `main`. Check that the changelog page shows the new version first, that velairc.app's Download button gets the new DMG, and that `https://velairc.app/appcast.xml` lists the new build (`--publish` checks this one).
3. **Check an update:** in the previous version, choose **Vela → Check for Updates…**. It should offer the new version with its release notes, and install it.
4. **Start the next cycle:** make sure `CHANGELOG.md` has an empty `## Unreleased` section.

## If something goes wrong

- **A publishing step fails:** nothing is deleted. Fix what the summary says, then run the commands the script printed under **Finish by hand** (see [When a publishing step fails](#when-a-publishing-step-fails)). Running `scripts/release.sh --publish` again would build everything again, and once the tag exists, its preflight stops it.
- **A bad release:** don't delete the release. Ship a fixed version (bump the patch number) and mark it latest. If the build is harmful, delete only its DMG assets and say so in the release notes.
- **"No Developer ID Application certificate found":** the certificate isn't in the login keychain, or its private key is missing (it shows without a disclosure triangle in Keychain Access). Re-import your `.p12` backup.
- **"Notarization profile not found":** run the `store-credentials` step again.
- **Gatekeeper rejects the DMG on another Mac:** run `scripts/verify-release.sh` on that DMG. It runs `xcrun stapler validate` on both the DMG and the app inside it, and checks that `spctl` says "Notarized Developer ID".
- **A preflight or post-build check fails:** see [Release checks](#release-checks) for what each one needs.
- **A release went out with a broken updater:** the feed can't fix a copy that can't update. Ship a fixed version, say so in the release notes, and ask people to download it once from the website.
- **The feed lists a bad release:** add a fixed version (bump the build number); Sparkle offers the newest. Don't delete items from the feed by hand.
- **"Bundled workflow" fails:** the bundled Alfred workflow isn't the one its record describes. Bundle it again with `scripts/update-alfred-workflow.sh` (see [The Alfred workflow](#the-alfred-workflow)) and commit both files.

## The Alfred workflow

The Alfred workflow and the Raycast extension live in their own repositories, [vela-alfred-workflow](https://github.com/r3volution11/vela-alfred-workflow) and [vela-raycast-extension](https://github.com/r3volution11/vela-raycast-extension), which build, test and release them: the workflow's releases carry `Vela.alfredworkflow` (the Alfred Gallery updates from them), and the extension goes to the Raycast Store. A Vela release carries neither.

The app carries a built copy of the workflow, which **Settings → Integrations → Install Workflow…** opens in Alfred:

- `Vela/Integrations/Vela.alfredworkflow` is the file; the Vela target copies it into the app's Resources.
- `integrations/alfred-workflow.json` records its `version`, `sha256`, `source` (the release's URL, or `local build` with the `commit`) and the date it was `updated`.

`scripts/update-alfred-workflow.sh` writes both:

```sh
scripts/update-alfred-workflow.sh --release latest   # the workflow's newest release (or --release v1.0.0)
scripts/update-alfred-workflow.sh --local            # build "Vela Alfred Workflow" next to your Vela checkout
scripts/update-alfred-workflow.sh --check            # the bundled file matches its record
```

`--release` checks the download against the release's `SHA256SUMS`, when it has one. `--local` builds with the workflow repository's `scripts/build.sh`, which tests it first (`--skip-tests` skips them). Every new file must be a zip with the workflow's `info.plist` and a version. Commit both files.

CI, the [preflight](#alfred-workflow) and the [post-build checks](#post-build-checks) fail when the bundled file doesn't match its record. Before a release, bundle a published release of the workflow rather than a local build, so what the app installs is what the Alfred Gallery has.

## Updates

Vela updates itself with [Sparkle 2](https://sparkle-project.org). Users' side of it is on the website: [Updates](https://velairc.app/guide/updates). This is how it fits together.

- **Sparkle is in the app target only**, added with Swift Package Manager and pinned to an exact version (2.10.1) in `Vela.xcodeproj`. `Vela/SparkleUpdater.swift` wraps it. VelaKit never imports it: VelaUI has an `AppUpdater` protocol (`Packages/VelaKit/Sources/VelaUI/Updates/`), which the About window, **Settings → Updates**, the Vela menu and the command palette use, and which tests drive with a fake.
- **Settings:** `updates.checkAutomatically` (on) and `updates.installAutomatically` (off) in settings.json are the source of truth. `UpdateSettingsSync` applies them to Sparkle before it starts, and again whenever they change; the update window's "Automatically download and install updates" box is written back to `updates.installAutomatically`.
- **Gentle reminders:** a check Sparkle runs on its own shows the update window only right after launch or when the Mac has been idle. Otherwise the update waits, shown in the About window and Settings, and is offered at the next launch. Sparkle's default would show the window when you switch back to Vela, where the next key you type could install it.
- **Info.plist:** the Release configuration merges `Vela/Info.plist` (`INFOPLIST_FILE`) into the Info.plist Xcode generates: the feed (`SUFeedURL`), the public key (`SUPublicEDKey`), automatic checks on (`SUEnableAutomaticChecks`, so Sparkle never asks), a daily interval, no system profile, the sandbox's installer service (`SUEnableInstallerLauncherService`) and verification before extraction (`SUVerifyUpdateBeforeExtraction`). `Vela/Info.plist` is excluded from the app's resources in the project.
- **Debug builds (Vela Dev) never update:** they don't get `Vela/Info.plist`, so they have no feed, and `VelaUpdater.make()` never creates a Sparkle updater in Debug. Demo runs, snapshots and the scroll benchmark get a stand-in that never goes online.
- **Local Release builds** (`scripts/run.sh`, the screenshots) have the release's identity. Once `Vela/Info.plist` has the real public key, a `build/Vela.app` checks the real feed like a release, and can update itself to one.
- **No system profile, ever.** `SUEnableSystemProfiling` is off, and a check sends only Sparkle's User-Agent (`Vela/<version> Sparkle/<version>`). The privacy page says so: [Privacy](https://velairc.app/help/privacy#updates).

### Entitlements

Vela is sandboxed, so Sparkle installs through its Installer XPC service (`SUEnableInstallerLauncherService`), and the app needs a temporary mach-lookup exception to talk to the installer: `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `-spki`. Vela already has `com.apple.security.network.client`, so it downloads updates itself and doesn't need Sparkle's Downloader service. Following [Sparkle's sandboxing guide](https://sparkle-project.org/documentation/sandboxing/):

- **`Vela/Vela.entitlements`** is what releases are signed with. `scripts/release.sh` passes it as `VELA_ENTITLEMENTS`, which the app target's `CODE_SIGN_ENTITLEMENTS` uses (`Config/Vela.xcconfig`; local builds get `Vela/Vela-Local.entitlements`). Passing `CODE_SIGN_ENTITLEMENTS` itself on the command line would apply it to every package target too, and the archive fails.
- **`Vela/Vela-Local.entitlements`** is the project's setting, for every local build: Xcode, `scripts/run.sh`, the scroll benchmark, the screenshots, `scripts/test-update.sh`. It's `Vela.entitlements` plus `com.apple.security.cs.disable-library-validation`: with the hardened runtime, macOS only loads frameworks signed by the app's own team, and an ad hoc build has none, so without it a local build couldn't load `Sparkle.framework` and would quit at launch. A release is signed with Developer ID, Sparkle included, so it keeps library validation; the post-build checks fail a release with the exception.
- **Keep the two files the same** apart from that exception.
- **Signing:** `xcodebuild -exportArchive` with the `developer-id` method signs Sparkle's framework, its XPC services and helpers (`Installer.xpc`, `Downloader.xpc`, `Autoupdate`, `Updater.app`) with your Developer ID and the hardened runtime, and notarization accepts them. Never add `--deep` to the signing flags. The **Sparkle** post-build check verifies each one.

### The update signing key

Sparkle accepts an update only if it's signed with the EdDSA (ed25519) key whose public half the installed app has in `SUPublicEDKey`. The private half lives only in 1Password, like the SSH key that signs tags:

| | Default | Override |
| --- | --- | --- |
| 1Password account | `my.1password.com` | `VELA_OP_ACCOUNT`, or `--account` |
| Vault | `Personal` | `VELA_SPARKLE_VAULT`, or `--vault` |
| Item | `Vela - Sparkle - Mac Update Signing Key` | `VELA_SPARKLE_ITEM`, or `--item` |

The private key is the item's **password** field: the base64 of the key's 32-byte seed, Sparkle's own format (what `generate_keys -x` exports and `sign_update --ed-key-file` reads). The item also has the public key and a note. The name leaves room for an iOS version later.

```sh
scripts/sparkle-key.sh --create   # once: makes the key, stores it in 1Password, prints the public key
scripts/sparkle-key.sh --public   # prints the public key, read back from 1Password
scripts/sparkle-key.sh --check    # does Vela/Info.plist have that public key?
```

- **`--create`** makes the key with CryptoKit (`scripts/lib/sparkle-ed25519.swift`), in Sparkle's format, and pipes the new item straight into `op item create`. The key never touches a file, an argument or the Keychain, so unlike Sparkle's `generate_keys`, nothing is left in the Keychain to delete. It refuses if the item already exists. Then paste the public key over `SPARKLE_PUBLIC_KEY_PLACEHOLDER` in `Vela/Info.plist`, commit, and run `--check`.
- **Until the key is in `Vela/Info.plist`,** the app doesn't start Sparkle ("Updates aren't set up in this build"), and `scripts/release.sh`, the preflight and the post-build checks refuse a release.
- **`scripts/release.sh --publish`** runs `--check` before it builds, so 1Password asks for your approval then, and once more when it signs. It reads the key with `op read` into `sign_update`'s standard input.
- **Never commit or export the private key,** and keep 1Password's backup. If it's lost, installed copies can still move to a new key: ship one release signed with the *old* Developer ID certificate and a *new* key, in a Developer ID-signed DMG (Sparkle allows changing the key or the certificate, never both at once; see [rotating keys](https://sparkle-project.org/documentation/#rotating-signing-keys)). With `SUVerifyUpdateBeforeExtraction` on, a key change is only accepted from a Developer ID-signed disk image, which is what releases are.

### The update feed

`website/public/appcast.xml` is the feed, served at `https://velairc.app/appcast.xml` by the **Deploy Website** workflow (it's in `website/public`, which VitePress copies as is). `website/scripts/appcast.mjs` writes and checks it; never edit items by hand.

- **Each release is one `<item>`,** newest first, and earlier items stay: title, date, `sparkle:version` (the build number, which Sparkle compares), `sparkle:shortVersionString`, `sparkle:minimumSystemVersion` (from the app's `LSMinimumSystemVersion`), a link to the full changelog (Sparkle's **Version History** button, which opens the browser), and the enclosure: `https://github.com/r3volution11/Vela-IRC/releases/download/v<version>/Vela.dmg` with its length and EdDSA signature.
- **Release notes** are the changelog section as HTML in the item's `<description>`, so Sparkle's window shows them without loading anything; relative links point at the files as of the tag.
- **A beta channel later:** an item with `<sparkle:channel>beta</sparkle:channel>` (`appcast.mjs add --channel beta`) is seen only by apps that ask for that channel (`allowedChannels(for:)` in `SPUUpdaterDelegate`). Items without a channel are for everyone. Build numbers must be unique across channels.
- **Checks:** the preflight, `npm run docs:check` (on the built site) and `npm test` (`website/scripts/appcast.test.ts`) check the feed; `appcast.mjs check` lists any problem.

```sh
node website/scripts/appcast.mjs check website/public/appcast.xml
node website/scripts/appcast.mjs has website/public/appcast.xml --build 2   # exits 0 if build 2 is in it
```

### Testing an update

`scripts/test-update.sh` tests the whole update on your Mac, with nothing public: a throwaway key, two Release builds as "Vela Update Test" (bundle id `io.github.r3volution11.Vela.updatetest`, its own container, so your Vela and Vela Dev are untouched), 1.0.0 (1) and 99.0.0 (99), and a feed served from `localhost`.

```sh
scripts/test-update.sh --prepare   # builds, signs, checks and serves; opens nothing (a few minutes)
scripts/test-update.sh             # the same, then opens the old app and waits for it to update itself
scripts/test-update.sh --clean     # deletes the test apps, their container and the throwaway key
```

- **`--prepare`** checks everything short of installing: both builds and their signatures, the DMG (made by `scripts/make-dmg.sh`, as releases are), `sign_update` and `sign_update --verify`, the signature against the old app's public key, that a DMG with one changed byte is refused, the feed, and that the feed and the DMG download intact.
- **Without it,** the old app opens and takes the focus. It checks at launch (it never has before) and shows Sparkle's window: choose **Install Update** (or **Vela Update Test → Check for Updates…** if nothing shows). It quits, installs 99.0.0 and opens again; the script waits until the app in `build/update-test` is 99.0.0, running and correctly signed.
- **Run it** after changing anything about updates, and after updating Sparkle. `--port` picks another port than 8723.

### Updating Sparkle

1. Pick a version that has been out for at least two weeks, from [Sparkle's releases](https://github.com/sparkle-project/Sparkle/releases), and read its release notes.
2. In Xcode → the Vela project → **Package Dependencies**, set Sparkle to that exact version. This updates `Vela.xcodeproj/project.pbxproj` and `Package.resolved`.
3. Build, run `scripts/test-update.sh`, then commit. The **Sparkle** post-build check compares the framework's version with `Package.resolved`.

## The GIF key

**For now, GIF search is only in development builds (Vela Dev).** The key is still a KLIPY test key, and releases wait for KLIPY to approve it for production: `GIFAvailability` leaves GIFs out of release builds (no **GIFs** tab, no GIF settings), `gifs.enabled` is off by default, `Vela/Info.plist` has no key, and the **GIF key** post-build check fails a release that has one. Once KLIPY approves, put `VelaKLIPYAPIKey` back in `Vela/Info.plist`, read the key from 1Password in `scripts/release.sh` (as for local builds, below), flip `GIFAvailability` and the post-build check, and update the website.

The [emoji and GIF picker](https://velairc.app/guide/emoji-and-gifs) searches KLIPY with Vela's own key, so GIFs work without setting anything up. KLIPY requires its API to be called from the app itself, so the key is in every copy of Vela (`VelaKLIPYAPIKey` in `Info.plist`) and anyone with the app can read it. It's only kept out of the repository.

- **Where it is:** the 1Password item "Vela - KLIPY - Mac API Credentials" (an API Credential, Personal vault, account `my.1password.com`), in its **credential** field. `VELA_OP_ACCOUNT`, `VELA_KLIPY_VAULT` and `VELA_KLIPY_ITEM` override those; `scripts/lib/klipy.zsh` has the defaults.
- **Release builds:** none for now (above). When GIFs ship, pass the key to `xcodebuild` in an xcconfig only you can read, deleted as soon as the archive is done, so it isn't in the logs or the process list.
- **Local builds (Vela Dev):** `scripts/klipy-key.sh --local` writes the key to `Config/Secrets.xcconfig`, which git ignores and only you can read; `Config/Vela.xcconfig` includes it. `--remove` deletes it.
- **Limits:** while KLIPY has the key in testing mode, it allows 100 requests an hour, shared by everyone using Vela. Once KLIPY approves production access (requested in KLIPY's Partner Panel), the same key has no limit, and installed copies need no update. Changing the key, such as if it's revoked, needs a new release.

## Private Cloud Compute

**For now, Private Cloud Compute for long catch-ups is only in development builds (Vela Dev).** Using it needs Apple's `com.apple.developer.private-cloud-compute` entitlement, which Vela doesn't have yet, so in a release every request would fall back to the Mac. `PrivateCloudComputeAvailability` leaves it out of release builds: no `intelligence.privateCloudCompute` in the settings catalog, no switch in **Settings → Intelligence** (compiled out with `#if DEBUG` in `IntelligenceCatchUpSection`), no cloud path for Catch me up (`IntelligenceServices`, `FoundationModelSummarizer`), and a description of **Catch Me Up** for Siri and Shortcuts that doesn't mention it (`CatchMeUpIntent`). The **Private Cloud Compute** post-build check fails a release that offers it, or that has the entitlement.

Once Apple grants the entitlement, add it to `Vela/Vela.entitlements`, flip `PrivateCloudComputeAvailability`, drop the `#if DEBUG` around the switch and the intent's description, update the post-build check, and update the website (Apple Intelligence, Siri & Shortcuts, Privacy, the settings reference), the README and the roadmap.

## When the media check fails

The check resolves each sample link in `Packages/VelaKit/Sources/VelaMedia/MediaSites.swift` the way Vela does, and fails a site when what it gets back isn't what the sample expects. The report (also in `build/media-sites/report.txt`) says what went wrong for each link, for example `✗ thumbnail: no thumbnail` or `✗ MP4 copy: HTTP 404`. Look at the failing link in a browser, then:

- **The sample is gone** (the video was deleted, the GIF taken down): pick a new sample that will last, replace it in `MediaSites.swift`, and run `scripts/check-media-sites.sh --site <id>`. Nothing about Vela is broken.
- **The site changed how it works** (a new address format, different page tags, a moved oEmbed endpoint): users are seeing it too. Fix the resolver in `VelaMedia`, with a unit test against a stubbed response, update the entry if the links or domains changed, and regenerate the docs page (see [CONTRIBUTING.md](../CONTRIBUTING.md#adding-or-changing-a-site)). Mention the fix in `CHANGELOG.md`.
- **The site is down or slow right now:** each failing link is already tried three times, a few seconds apart. Run the check again later, or release with `--skip-media-check` if it can't wait.
- **Every site fails:** check your connection. The check needs internet access.
- **Reddit in GitHub Actions:** Reddit refuses GitHub's hosted runners (HTTP 403, or an empty oEmbed answer) while answering people's Macs, so the **Media sites** workflow leaves `reddit-videos` and `reddit-posts` out (`--skip-site`) unless you name them when running it by hand. The release preflight checks them from your Mac.

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
- **The app is sandboxed and uses the hardened runtime.** Releases are signed with `Vela/Vela.entitlements`; the release script refuses a build without the App Sandbox entitlement. Local builds use `Vela/Vela-Local.entitlements`; see [Entitlements](#entitlements).
- **Notarization happens twice.** The app is notarized and stapled first, so it stays verifiable offline after it's copied out of the disk image. Then the DMG itself is notarized and stapled.
- **Vela updates itself** from 1.1, with Sparkle; see [Updates](#updates). The Mac App Store is on the roadmap.
