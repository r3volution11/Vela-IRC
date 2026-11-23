#!/bin/zsh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Signs Vela Dev (Debug builds) with your own certificate instead of ad hoc,
# so the Keychain stops asking for your password after every build.
#
#   scripts/dev-signing.sh            # write Config/Signing.xcconfig
#   scripts/dev-signing.sh --remove   # delete it: Vela Dev is ad hoc again
#
# Why: Vela keeps passwords and channel keys in the login keychain, which
# lets an app read an item only if its code signature matches the one the
# item trusts. An ad hoc signature is a hash of the build itself, so every
# rebuild looks like a new app and macOS asks again, once per item. Signed
# with a certificate, every build has the same identity (your team), and
# "Always Allow" sticks.
#
# Uses your first "Apple Development" certificate, or else your "Developer ID
# Application" one. Config/Signing.xcconfig is git-ignored and holds only the
# certificate's name, its SHA-1 and your team ID, nothing secret. Without
# it, Vela Dev is signed ad hoc, as on CI and in the test VMs.
set -euo pipefail
cd "${0:A:h}/.."
file=Config/Signing.xcconfig

case "${1:-}" in
  --remove)
    rm -f "$file"
    print -P "%F{green}✓%f Removed $file. Vela Dev is signed ad hoc again."
    exit 0
    ;;
  "") ;;
  *)
    print -u2 "Usage: scripts/dev-signing.sh [--remove]"
    exit 2
    ;;
esac

identities=$(security find-identity -v -p codesigning)
line=$(print -r -- "$identities" | grep '"Apple Development: ' | head -1 || true)
[[ -n $line ]] || line=$(print -r -- "$identities" | grep '"Developer ID Application: ' | head -1 || true)
if [[ -z $line ]]; then
  print -u2 "No Apple Development or Developer ID Application certificate in your keychain, so Vela Dev stays signed ad hoc."
  exit 1
fi
sha1=$(print -r -- "$line" | awk '{print $2}')
name=$(print -r -- "$line" | sed -E 's/.*"(.*)"/\1/')
team=$(security find-certificate -c "$name" -p | openssl x509 -noout -subject | sed -nE 's/.*OU=([A-Z0-9]{10}).*/\1/p')
[[ -n $team ]] || { print -u2 "Couldn't read the team ID from \"$name\"."; exit 1; }

cat > "$file" <<EOF
// Written by scripts/dev-signing.sh: signs Vela Dev (Debug builds) with
// "$name",
// so the Keychain trusts every build. Git-ignored. Delete this file, or run
// scripts/dev-signing.sh --remove, to sign Vela Dev ad hoc again.
VELA_DEV_SIGN_IDENTITY = $sha1
VELA_DEV_SIGN_STYLE = Manual
VELA_DEV_TEAM = $team
EOF
print -P "%F{green}✓%f Wrote $file: Vela Dev is signed with \"$name\"."
print "  Build and open Vela Dev again (scripts/run.sh --dev). The Keychain asks once more"
print "  for each saved password; choose Always Allow, and later builds won't ask."
