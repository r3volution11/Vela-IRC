#!/bin/zsh
# Vela's update signing key: the EdDSA (ed25519) key Sparkle checks every
# update with. Its private half lives only in 1Password; its public half is
# SUPublicEDKey in Vela/Info.plist.
#
#   scripts/sparkle-key.sh --create   # once: make the key and store it in 1Password
#   scripts/sparkle-key.sh --public   # print the public key, read back from 1Password
#   scripts/sparkle-key.sh --check    # does Vela/Info.plist have that public key?
#
# --create makes a new key in Sparkle's format (the base64 of a 32-byte
# seed, as Sparkle's generate_keys exports it; see
# scripts/lib/sparkle-ed25519.swift) and pipes it straight into a new
# 1Password item: it's never written to a file, passed as an argument or put
# in the Keychain, so there's no Keychain copy to delete afterwards. It
# refuses if the item already exists: a new key would stop every installed
# copy of Vela from accepting updates (docs/RELEASING.md, "The update
# signing key"). Then it prints the public key to paste into Vela/Info.plist.
#
# Options:
#   --account <account>  The 1Password account (default: VELA_OP_ACCOUNT,
#                        or my.1password.com).
#   --vault <vault>      The vault (default: VELA_SPARKLE_VAULT, or Personal).
#   --item <title>       The item (default: VELA_SPARKLE_ITEM, or
#                        "Vela - Sparkle - Mac Update Signing Key").
#
# Needs the 1Password CLI (op), signed in; 1Password asks you to approve.
set -euo pipefail
script="${0:A}"
cd "${0:A:h}/.."
source scripts/lib/sparkle.zsh

usage() { sed -n '2,/^set -euo/p' "$script" | sed -e '$d' -e 's/^# \{0,1\}//'; }
fail() { print -u2 -P "%F{red}error:%f $1"; exit 1; }

mode=""
while (( $# )); do
  case "$1" in
    --create|--public|--check)
      [[ -z $mode ]] || { print -u2 "Give one of --create, --public and --check."; exit 2; }
      mode=${1#--}; shift ;;
    --account|--vault|--item)
      [[ $# -ge 2 && -n "$2" ]] || { print -u2 -r -- "$1 needs a value."; exit 2; }
      case "$1" in
        --account) sparkle_op_account=$2 ;;
        --vault) sparkle_vault=$2 ;;
        --item) sparkle_item=$2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -r -- "Unknown option: $1 (see --help)"; exit 2 ;;
  esac
done
[[ -n $mode ]] || { usage >&2; exit 2; }

command -v op >/dev/null || fail "This needs the 1Password CLI: brew install 1password-cli, then turn on 1Password → Settings → Developer → Integrate with 1Password CLI."
command -v swift >/dev/null || fail "This needs swift (Xcode's command line tools)."
where="\"$sparkle_item\" in the $sparkle_vault vault of $sparkle_op_account"

case $mode in
  create)
    if sparkle_op item get "$sparkle_item" --vault "$sparkle_vault" --format json >/dev/null 2>&1; then
      fail "1Password already has $where. It's the key installed copies of Vela trust, so this won't replace it. To see its public key: scripts/sparkle-key.sh --public."
    fi
    print -r -- "Creating the update signing key in $where…"
    # The item's JSON, private key included, goes from the generator to op
    # through a pipe.
    swift "$sparkle_ed25519" generate-op-item "$sparkle_item" \
      | sparkle_op item create --vault "$sparkle_vault" - >/dev/null \
      || fail "op couldn't create the item. Is 1Password unlocked, and is $sparkle_vault a vault of $sparkle_op_account?"
    # Read it back, as releases will.
    public_key=$(sparkle_public_key_from_1password) \
      || fail "The item was created, but reading the key back failed. Check it in 1Password, then run scripts/sparkle-key.sh --public."
    print
    print -P "%F{green}✓%f Created. The private key is only in 1Password."
    print
    print -r -- "Public key (SUPublicEDKey):"
    print -r -- "    $public_key"
    print
    print -r -- "Next: replace $sparkle_placeholder in $sparkle_info_plist with it, commit,"
    print -r -- "then check with scripts/sparkle-key.sh --check. Keep 1Password's backup of the item:"
    print -r -- "losing the key means installed copies need a key change (docs/RELEASING.md)."
    ;;

  public)
    public_key=$(sparkle_public_key_from_1password) \
      || fail "Couldn't read $where. Is 1Password unlocked? Create the key with --create if it doesn't exist."
    print -r -- "$public_key"
    ;;

  check)
    in_plist=$(sparkle_public_key)
    sparkle_key_is_valid "$in_plist" \
      || fail "$sparkle_info_plist has no public key yet (SUPublicEDKey is ${in_plist:-missing}). Paste the one scripts/sparkle-key.sh --public prints."
    public_key=$(sparkle_public_key_from_1password) \
      || fail "Couldn't read $where. Is 1Password unlocked?"
    [[ $public_key == "$in_plist" ]] \
      || fail "$sparkle_info_plist's SUPublicEDKey ($in_plist) isn't the public half of the key in 1Password ($public_key). Updates signed with it would be refused."
    print -P "%F{green}✓%f $sparkle_info_plist has the public half of the key in 1Password."
    ;;
esac
