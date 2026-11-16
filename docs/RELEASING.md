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
2. **Commit and push** to `main`, then make sure CI is green: `gh run list --limit 2`.
3. **Build, sign, notarize and staple:**
   ```sh
   scripts/release.sh
   ```
   This writes `build/release/Vela.dmg`, `build/release/Vela-<version>.dmg` and `SHA256SUMS`. To test the pipeline without your certificate, use `--adhoc`. To skip Apple's notary service, use `--skip-notarize`.
4. **Tag and publish:**
   ```sh
   v=0.1.0
   git tag -a "v$v" -m "Vela $v"
   git push origin "v$v"
   gh release create "v$v" build/release/Vela.dmg "build/release/Vela-$v.dmg" build/release/SHA256SUMS \
     --title "Vela $v" --notes-file <release-notes.md> --latest
   ```
   Write the release notes for users, as a light rewrite of the changelog entry.
5. **Verify:**
   - `curl -sIL https://github.com/r3volution11/Vela-IRC/releases/latest/download/Vela.dmg | grep -i location` resolves to the new version.
   - The website changelog shows the new version first after the **Deploy Website** workflow runs.

## Notes

- **Releases are universal.** They run on Apple silicon and Intel, and need macOS 26 or later.
- **The app is sandboxed and uses the hardened runtime.** Entitlements are in `Vela/Vela.entitlements`.
- **Notarization happens twice.** The app is notarized and stapled first, so it stays verifiable offline after it's copied out of the disk image. Then the DMG itself is notarized and stapled.
