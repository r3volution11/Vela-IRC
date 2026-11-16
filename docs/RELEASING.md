# Releasing Vela

How to ship a signed, notarized build and publish it on GitHub. The website's **Download** button points at `https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg`, so every release must:

- upload an asset named exactly `Vela.dmg`;
- be marked as the latest release (not a pre-release).

## One-time setup

1. **Developer ID certificate.** In Xcode → Settings → Accounts, add your Apple ID and select your team. Then choose **Manage Certificates… → + → Developer ID Application**. Only the account holder can create this certificate. Check that it's installed:
   ```sh
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
2. **Notarization credentials.** Create an app-specific password at [appleid.apple.com](https://appleid.apple.com) (Sign-In and Security → App-Specific Passwords). Then store it in your Keychain, where `notarytool` will prompt for the password:
   ```sh
   xcrun notarytool store-credentials vela-notary --apple-id "<apple-id-email>" --team-id "<TEAMID>"
   ```

## Cutting a release

1. **Bump the version.**
   - Update `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `Vela.xcodeproj/project.pbxproj`.
   - Add a section to `CHANGELOG.md`, inserted above the newest existing entry.
2. **Refresh the adult-domain list:**
   ```sh
   scripts/update-adult-domains.sh
   ```
   Check its summary, then commit the updated list with the release. See [The adult-domain list](#the-adult-domain-list).
3. **Commit and push** to `main`, then make sure CI is green: `gh run list --limit 2`.
4. **Build, sign, notarize and staple:**
   ```sh
   scripts/release.sh
   ```
   This writes `build/release/Vela.dmg`, `build/release/Vela-<version>.dmg` and `SHA256SUMS`. To test the pipeline without your certificate, use `--adhoc`. To skip Apple's notary service, use `--skip-notarize`.
5. **Tag and publish:**
   ```sh
   v=0.1.0
   git tag -a "v$v" -m "Vela $v"
   git push origin "v$v"
   gh release create "v$v" build/release/Vela.dmg "build/release/Vela-$v.dmg" build/release/SHA256SUMS \
     --title "Vela $v" --notes-file <release-notes.md> --latest
   ```
   Write the release notes for users, as a light rewrite of the changelog entry.
6. **Verify:**
   - `curl -sIL https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg | grep -i location` resolves to the new version.
   - The website changelog shows the new version first after the **Deploy Website** workflow runs.

## The adult-domain list

The adult-site filter blocks previews (never links) from domains on a list bundled in `Packages/VelaKit/Sources/VelaMedia/Resources/adult-domains.txt`. Vela doesn't download the list at runtime, so each release ships whatever was last committed. `scripts/update-adult-domains.sh` rebuilds it from [Sinfonietta/hostfiles](https://github.com/Sinfonietta/hostfiles) (MIT), at the latest upstream commit or at the one given with `--ref <sha>`.

- **Read the summary.** It shows which upstream entries were excluded and how many domains were added and removed. Small changes are listed in full.
- **Keep general-purpose sites off the list.** If upstream lists a social network, image host, CDN or other mainstream site, add it to `scripts/adult-domains-exclude.txt` and run the script again. Exclusions match exactly, so specific adult subdomains of a platform (such as one blog) stay listed.
- **Size checks.** The script refuses a list with fewer than 10,000 domains, or one under 70% of the current count. If upstream really did shrink, find out why, then rerun with `--force`.
- **License.** The script stops if the upstream license is no longer MIT. The notice is in the list's header and in `THIRD_PARTY_NOTICES.md`.

## Notes

- **Releases are universal.** They run on Apple silicon and Intel, and need macOS 26 or later.
- **The app is sandboxed and uses the hardened runtime.** Entitlements are in `Vela/Vela.entitlements`.
- **Notarization happens twice.** The app is notarized and stapled first, so it stays verifiable offline after it's copied out of the disk image. Then the DMG itself is notarized and stapled.
