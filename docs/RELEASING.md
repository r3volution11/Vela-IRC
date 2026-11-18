# Releasing Vela

How to ship a signed, notarized Vela and publish it on GitHub, from a one-time setup to checking the download. The website's **Download** button points at `https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg`. Every release must therefore:

- upload an asset named exactly `Vela.dmg`;
- be marked as the latest release, not a pre-release.

Until the first release is published, that link returns 404.

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
4. **Do a dry run.** `scripts/release.sh --skip-notarize` signs with your Developer ID without contacting Apple. It shows that the certificate, export and disk image steps work.

## Before each release

1. **Pick the version.** Use [semantic versioning](https://semver.org): below 1.0, bump the minor version for features (0.2.0) and the patch for fixes only (0.2.1).
   - The version is `MARKETING_VERSION` in `Vela.xcodeproj/project.pbxproj` (the Vela target's Debug and Release configurations).
   - Also bump `CURRENT_PROJECT_VERSION`, the build number, by 1 for every build you ship.
   - The easiest way is Xcode: Vela target → General → Version and Build.
2. **Finish the changelog.** In `CHANGELOG.md`, rename `## Unreleased` to `## <version> - <yyyy-mm-dd>`. Read it through as a user would, and move anything that isn't user-facing out. Start a new empty `## Unreleased` section above it for the next cycle.
3. **Refresh the adult-domain list:** `scripts/update-adult-domains.sh`. Check its summary; see [The adult-domain list](#the-adult-domain-list).
4. **Check that everything is green:**
   ```sh
   swift test --package-path Packages/VelaKit
   (cd website && npm run docs:build && npm run docs:check)
   ```
   Then commit, push and wait for CI: `gh run list --limit 2`.
   The **Media sites** workflow checks the sites Vela shows media from every Monday; if its last run failed, sort that out first. `scripts/release.sh` checks them again anyway.
5. **Check the docs and screenshots.** Every user-facing change is documented on the site. If the UI changed, re-shoot with `website/scripts/screenshots.sh` and commit the images.
6. **Try the Release build yourself:** `scripts/run.sh`, then use it for a bit. Release builds are optimized, and occasionally behave differently from the Debug build you develop with.

## Building the release

```sh
scripts/release.sh
```

What it does:
1. Reads the version from the project and warns if the working tree has uncommitted changes.
2. Finds your **Developer ID Application** certificate and Team ID, and checks that the `vela-notary` profile exists.
3. **Checks the media sites** with `scripts/check-media-sites.sh`: every sample link in `MediaSites.swift` is resolved against the real site, and the report is printed. If a site fails, the script stops before archiving and names the broken sites. See [When the media check fails](#when-the-media-check-fails).
4. **Archives** a universal (Apple silicon + Intel) Release build into `build/release/Vela.xcarchive`.
5. **Exports** it with Developer ID signing, the hardened runtime and a secure timestamp.
6. **Verifies** the signature (`codesign --verify --deep --strict`), both architectures, and that the App Sandbox entitlement is present.
7. **Notarizes the app and staples** the ticket to it, so it verifies offline even after it's copied out of the disk image.
8. **Builds the DMG** (`Vela.app` plus an Applications shortcut), signs it, **notarizes and staples** the DMG too, and runs a Gatekeeper assessment.
9. Writes `build/release/Vela.dmg`, `build/release/Vela-<version>.dmg` and `build/release/SHA256SUMS`.

Notarization usually takes a few minutes. If Apple rejects a submission, the script prints Apple's log; the usual causes are an unsigned nested binary or a missing hardened-runtime flag. Options:
- `--skip-notarize`: signs but doesn't notarize, for testing the pipeline.
- `--adhoc`: no Developer ID at all, for testing on your own Mac only. Other Macs will refuse it. It skips the media check too, since nothing it builds ships; add `--media-check` to check anyway.
- `--skip-media-check`: builds without checking the media sites. Use it when you've looked at the failure and it shouldn't hold up the release, such as a site that's down for an hour.

## Checking the build before you publish

Test what users will get, not your local build:

```sh
spctl -a -vvv -t install build/release/Vela.dmg            # "accepted, source=Notarized Developer ID"
xcrun stapler validate build/release/Vela.dmg
hdiutil attach build/release/Vela.dmg                       # then:
spctl -a -vvv "/Volumes/Vela <version>/Vela.app"
codesign -dv --verbose=4 "/Volumes/Vela <version>/Vela.app" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp"
hdiutil detach "/Volumes/Vela <version>"
```

Then do a real install:
1. Quit any running Vela and copy `Vela.app` from the DMG to `/Applications`.
2. Open it from there. On first launch, macOS asks for your Keychain password once per saved network password; see below.
3. Connect a network, and check inline media, the notification permission prompt, and **Catch me up** if Apple Intelligence is on.
4. Ideally, try it on a second Mac or a fresh user account with nothing of Vela's on it, opening the DMG from **Downloads** so Gatekeeper sees the quarantine flag.

### Upgrading from your local build

The release has the same bundle id as `build/Vela.app`, so it uses the same settings, networks and history. Your saved passwords stay in the Keychain, but they were created by a differently signed copy, so macOS asks once whether the release may use each one. Click **Always Allow**.

After you've switched, delete `build/Vela.app`, or at least don't keep both copies around. Two apps with the same bundle id confuse Siri, Shortcuts and Spotlight about which one to open.

## Publishing

```sh
v=0.2.0   # the version you set
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
   It should end in `/download/v<version>/Vela.dmg`. Then download it with a browser and install it once more.
2. **Check the website:** the **Deploy Website** workflow runs on every push to `main`. Check that the changelog page shows the new version first, and that velairc.app's Download button gets the new DMG.
3. **Start the next cycle:** make sure `CHANGELOG.md` has an empty `## Unreleased` section.

## If something goes wrong

- **A bad release:** don't delete the release. Ship a fixed version (bump the patch number) and mark it latest. If the build is harmful, delete only its DMG assets and say so in the release notes.
- **"No Developer ID Application certificate found":** the certificate isn't in the login keychain, or its private key is missing (it shows without a disclosure triangle in Keychain Access). Re-import your `.p12` backup.
- **"Notarization profile not found":** run the `store-credentials` step again.
- **Gatekeeper rejects the DMG on another Mac:** run `xcrun stapler validate` on both the DMG and the app inside it, and check that `spctl` says "Notarized Developer ID".

## When the media check fails

The check resolves each sample link in `Packages/VelaKit/Sources/VelaMedia/MediaSites.swift` the way Vela does, and fails a site when what it gets back isn't what the sample expects. The report (also in `build/media-sites/report.txt`) says what went wrong for each link, for example `✗ thumbnail: no thumbnail` or `✗ MP4 copy: HTTP 404`. Look at the failing link in a browser, then:

- **The sample is gone** (the video was deleted, the GIF taken down): pick a new sample that will last, replace it in `MediaSites.swift`, and run `scripts/check-media-sites.sh --site <id>`. Nothing about Vela is broken.
- **The site changed how it works** (a new address format, different page tags, a moved oEmbed endpoint): users are seeing it too. Fix the resolver in `VelaMedia`, with a unit test against a stubbed response, update the entry if the links or domains changed, and regenerate the docs page (see [CONTRIBUTING.md](../CONTRIBUTING.md#adding-or-changing-a-site)). Mention the fix in `CHANGELOG.md`.
- **The site is down or slow right now:** each failing link is already tried three times, a few seconds apart. Run the check again later, or release with `--skip-media-check` if it can't wait.
- **Every site fails:** check your connection. The check needs internet access.

A site that keeps failing for reasons Vela can't fix is better dropped from `MediaSites.swift` and the recognizers than left broken; say so in the changelog.

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
