# Shared by scripts/sparkle-key.sh, scripts/release.sh,
# scripts/release-preflight.sh, scripts/verify-release.sh and
# scripts/test-update.sh (sourced, not run): where Vela's update signing key
# lives in 1Password, the public key in Vela/Info.plist, and Sparkle's tools.
#
# The private key is only ever read with `op read` into a pipe; nothing here
# writes it to a file, an argument or the Keychain.

# 1Password: Doug's Mac is signed in to more than one account, so every `op`
# call names one. VELA_OP_ACCOUNT, VELA_SPARKLE_VAULT and VELA_SPARKLE_ITEM
# override the defaults.
typeset -g sparkle_op_account="${VELA_OP_ACCOUNT:-my.1password.com}"
typeset -g sparkle_vault="${VELA_SPARKLE_VAULT:-Personal}"
typeset -g sparkle_item="${VELA_SPARKLE_ITEM:-Vela - Sparkle - Mac Update Signing Key}"
# The private key is the item's password field.
typeset -g sparkle_key_field=password

# Vela/Info.plist (merged into Release builds) holds SUPublicEDKey, and this
# placeholder until the key exists.
typeset -g sparkle_info_plist=Vela/Info.plist
typeset -g sparkle_placeholder=SPARKLE_PUBLIC_KEY_PLACEHOLDER
typeset -g sparkle_feed_url=https://velairc.app/appcast.xml

# The Ed25519 helper (Swift, CryptoKit) next to this file.
typeset -g sparkle_ed25519="${${(%):-%x}:A:h}/sparkle-ed25519.swift"

# sparkle_op <op arguments…>: `op` with the account.
sparkle_op() {
  op --account "$sparkle_op_account" "$@"
}

# sparkle_secret_reference: the private key's 1Password secret reference.
sparkle_secret_reference() {
  print -r -- "op://$sparkle_vault/$sparkle_item/$sparkle_key_field"
}

# sparkle_read_private_key: prints the private key (to a pipe, please).
sparkle_read_private_key() {
  sparkle_op read --no-newline "$(sparkle_secret_reference)"
}

# sparkle_public_key_from_1password: the public half of the key in 1Password.
sparkle_public_key_from_1password() {
  local key
  key=$(sparkle_read_private_key | swift "$sparkle_ed25519" public) || return 1
  [[ -n $key ]] || return 1
  print -r -- "$key"
}

# sparkle_public_key [Info.plist]: SUPublicEDKey of a plist (by default
# Vela/Info.plist), or nothing.
sparkle_public_key() {
  plutil -extract SUPublicEDKey raw -o - "${1:-$sparkle_info_plist}" 2>/dev/null || true
}

# sparkle_key_is_valid <key>: true for the base64 of 32 bytes (an Ed25519
# public key), so false for the placeholder.
sparkle_key_is_valid() {
  local key=$1 bytes
  [[ -n $key && $key != "$sparkle_placeholder" && $key =~ '^[A-Za-z0-9+/]+=*$' ]] || return 1
  bytes=$(print -rn -- "$key" | base64 -D 2>/dev/null | wc -c | tr -d ' ')
  [[ $bytes == 32 ]]
}

# sparkle_bin <derived data path>: the folder with Sparkle's tools
# (sign_update, generate_keys…) that Xcode downloaded with the package, for
# the version in Package.resolved.
sparkle_bin() {
  local bin="$1/SourcePackages/artifacts/sparkle/Sparkle/bin"
  [[ -x $bin/sign_update ]] || return 1
  print -r -- "${bin:A}"
}

# sparkle_verify_signature <file> <signature> <public key>: true when the
# EdDSA signature of <file> is valid for <public key>, as Sparkle checks an
# update before installing it.
sparkle_verify_signature() {
  swift "$sparkle_ed25519" verify "$1" "$2" "$3"
}

# sparkle_pinned_version: the Sparkle version Package.resolved pins.
sparkle_pinned_version() {
  local resolved=Vela.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
  local -i count i
  count=$(plutil -extract pins raw -o - "$resolved" 2>/dev/null) || return 1
  for (( i = 0; i < count; i++ )); do
    if [[ $(plutil -extract "pins.$i.identity" raw -o - "$resolved" 2>/dev/null) == sparkle ]]; then
      plutil -extract "pins.$i.state.version" raw -o - "$resolved" 2>/dev/null
      return
    fi
  done
  return 1
}

# check_update_support <Vela.app> <its entitlements, as a plist file>
# <adhoc: 0 or 1> [<team id>]: what the in-app updater needs in a release,
# for scripts/verify-release.sh (needs release-checks.zsh's check_*):
#   • the entitlements: outgoing connections and the mach-lookup exception
#     for Sparkle's installer (<bundle id>-spks, -spki); no
#     disable-library-validation or get-task-allow (local builds only);
#   • Info.plist: the velairc.app feed, the installer service, daily
#     automatic checks, no system profile, no downloader service,
#     verification before extraction;
#   • SUPublicEDKey is a real public key, not the placeholder;
#   • Sparkle.framework is the version Package.resolved pins, and it and
#     each of its XPC services and helpers is signed with the hardened
#     runtime and (unless ad hoc) Developer ID of the app's team, with a
#     secure timestamp.
check_update_support() {
  local app=$1 entitlements=$2 adhoc=$3 team=${4:-}
  local info="$app/Contents/Info.plist" bundle_id key
  local -a problems lookups
  bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$info" 2>/dev/null || true)
  _entitlement() { /usr/libexec/PlistBuddy -c "Print :$1" "$entitlements" 2>/dev/null || true; }
  _plist() { plutil -extract "$1" raw -o - "$info" 2>/dev/null || true; }

  # Entitlements.
  [[ $(_entitlement com.apple.security.network.client) == true ]] || problems+=("no com.apple.security.network.client")
  lookups=("${(@f)$(_entitlement com.apple.security.temporary-exception.mach-lookup.global-name | sed -n 's/^ \{4\}\([^ ]*\)$/\1/p')}")
  lookups=("${(@)lookups:#}")
  if [[ ${(j: :)${(o)lookups}} != "$bundle_id-spki $bundle_id-spks" ]]; then
    problems+=("the mach-lookup exception is [${(j:, :)lookups}], expected $bundle_id-spks and $bundle_id-spki")
  fi
  if (( ! adhoc )); then
    [[ -z $(_entitlement com.apple.security.cs.disable-library-validation) ]] \
      || problems+=("it has disable-library-validation (Vela-Local.entitlements, for local builds only)")
    [[ -z $(_entitlement com.apple.security.get-task-allow) ]] || problems+=("it has get-task-allow")
  fi
  if (( ${#problems} )); then
    check_fail "Updater entitlements" "${(j:; :)problems}" \
      "Release with scripts/release.sh, which signs with Vela/Vela.entitlements; keep the mach-lookup exception there (docs/RELEASING.md, \"Updates\")."
  elif (( adhoc )); then
    check_pass "Updater entitlements" "mach-lookup for $bundle_id-spks and -spki (ad hoc: the local entitlements)"
  else
    check_pass "Updater entitlements" "mach-lookup for $bundle_id-spks and -spki; library validation on"
  fi

  # Info.plist.
  problems=()
  [[ $(_plist SUFeedURL) == "$sparkle_feed_url" ]] || problems+=("SUFeedURL is ${$(_plist SUFeedURL):-missing}, expected $sparkle_feed_url")
  [[ $(_plist SUEnableInstallerLauncherService) == true ]] || problems+=("SUEnableInstallerLauncherService isn't true")
  [[ $(_plist SUEnableAutomaticChecks) == true ]] || problems+=("SUEnableAutomaticChecks isn't true")
  [[ $(_plist SUEnableSystemProfiling) == false ]] || problems+=("SUEnableSystemProfiling isn't false")
  [[ $(_plist SUScheduledCheckInterval) == 86400 ]] || problems+=("SUScheduledCheckInterval isn't 86400 (daily)")
  [[ $(_plist SUVerifyUpdateBeforeExtraction) == true ]] || problems+=("SUVerifyUpdateBeforeExtraction isn't true")
  [[ $(_plist SUEnableDownloaderService) != true ]] || problems+=("SUEnableDownloaderService is on, but Vela has the network entitlement")
  if (( ${#problems} )); then
    check_fail "Update settings" "${(j:; :)problems}" \
      "Check $sparkle_info_plist, and that the Release configuration's INFOPLIST_FILE is $sparkle_info_plist."
  else
    check_pass "Update settings" "feed $sparkle_feed_url, daily checks, installer service, no system profile"
  fi

  key=$(_plist SUPublicEDKey)
  if sparkle_key_is_valid "$key"; then
    check_pass "Update key" "SUPublicEDKey ${key[1,8]}…"
  elif (( adhoc )); then
    check_skip "Update key" "SUPublicEDKey is ${key:-missing} (ad hoc build)"
  else
    check_fail "Update key" "SUPublicEDKey is ${key:-missing}, not a public key" \
      "Create the update signing key (scripts/sparkle-key.sh --create), put its public key in $sparkle_info_plist and build again (docs/RELEASING.md, \"The update signing key\")."
  fi

  # Sparkle and its nested code.
  local framework="$app/Contents/Frameworks/Sparkle.framework" pinned found_version item signing name
  local -a items
  problems=()
  if [[ ! -d $framework ]]; then
    check_fail "Sparkle" "the app has no Contents/Frameworks/Sparkle.framework" \
      "Check that the Vela target links the Sparkle package, then build again."
    return 0
  fi
  pinned=$(sparkle_pinned_version || true)
  found_version=$(plutil -extract CFBundleShortVersionString raw -o - "$framework/Versions/B/Resources/Info.plist" 2>/dev/null || true)
  [[ -n $pinned && $found_version == "$pinned" ]] || problems+=("Sparkle ${found_version:-?} isn't the pinned ${pinned:-?}")
  items=(
    "$framework/Versions/B/XPCServices/Installer.xpc"
    "$framework/Versions/B/XPCServices/Downloader.xpc"
    "$framework/Versions/B/Autoupdate"
    "$framework/Versions/B/Updater.app"
    "$framework"
  )
  for item in $items; do
    name=${item:t}
    [[ -e $item ]] || { problems+=("$name is missing"); continue; }
    codesign --verify --strict "$item" 2>/dev/null || { problems+=("$name's signature doesn't verify"); continue; }
    signing=$(codesign -dvv "$item" 2>&1 || true)
    print -r -- "$signing" | grep -q '^CodeDirectory.*flags=.*runtime' || problems+=("$name lacks the hardened runtime")
    if (( ! adhoc )); then
      if ! print -r -- "$signing" | grep -q '^Authority=Developer ID Application: '; then
        problems+=("$name isn't signed with Developer ID")
      elif [[ -n $team ]] && ! print -r -- "$signing" | grep -q "^TeamIdentifier=$team\$"; then
        problems+=("$name is signed by another team")
      fi
      print -r -- "$signing" | grep -q '^Timestamp=' || problems+=("$name has no secure timestamp")
    fi
  done
  if (( ${#problems} )); then
    check_fail "Sparkle" "${(j:; :)problems}" \
      "Archive and export with scripts/release.sh, which signs Sparkle's services and helpers with your Developer ID; don't add --deep to the signing flags."
  elif (( adhoc )); then
    check_pass "Sparkle" "$found_version (as pinned); Sparkle.framework, Installer.xpc, Downloader.xpc, Autoupdate and Updater.app verify, with the hardened runtime (ad hoc)"
  else
    check_pass "Sparkle" "$found_version (as pinned); Sparkle.framework, Installer.xpc, Downloader.xpc, Autoupdate and Updater.app signed with Developer ID, the hardened runtime and a timestamp"
  fi
}
