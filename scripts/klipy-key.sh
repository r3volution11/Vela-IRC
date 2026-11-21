#!/bin/zsh
# The GIF picker's KLIPY API key, kept in 1Password and built into Vela.
#
#   scripts/klipy-key.sh --local    # write Config/Secrets.xcconfig, so local
#                                   # builds (Vela Dev) can search GIFs
#   scripts/klipy-key.sh --remove   # delete Config/Secrets.xcconfig
#   scripts/klipy-key.sh --check    # can the key be read from 1Password?
#
# Release builds don't need --local: scripts/release.sh reads the key itself.
# Config/Secrets.xcconfig is git-ignored and readable only by you.
#
# Options:
#   --account <account>  The 1Password account (default: VELA_OP_ACCOUNT,
#                        or my.1password.com).
#   --vault <vault>      The vault (default: VELA_KLIPY_VAULT, or Personal).
#   --item <title>       The item (default: VELA_KLIPY_ITEM, or
#                        "Vela - KLIPY - Mac API Credentials").
#
# Needs the 1Password CLI (op), signed in; 1Password asks you to approve.
set -euo pipefail

script="${0:A}"
cd "${0:A:h}/.."
source scripts/lib/klipy.zsh

usage() { sed -n '2,/^set -euo/p' "$script" | sed -e '$d' -e 's/^# \{0,1\}//'; }
fail() { print -u2 -P "%F{red}error:%f $1"; exit 1; }

mode=""
while (( $# )); do
  case "$1" in
    --local|--remove|--check)
      [[ -z $mode ]] || { print -u2 "Give one of --local, --remove and --check."; exit 2; }
      mode=${1#--}; shift ;;
    --account|--vault|--item)
      [[ $# -ge 2 && -n "$2" ]] || { print -u2 -r -- "$1 needs a value."; exit 2; }
      case "$1" in
        --account) klipy_op_account=$2 ;;
        --vault) klipy_vault=$2 ;;
        --item) klipy_item=$2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 -r -- "Unknown option: $1 (see --help)"; exit 2 ;;
  esac
done
[[ -n $mode ]] || { usage >&2; exit 2; }

where="\"$klipy_item\" in the $klipy_vault vault of $klipy_op_account"

case $mode in
  local)
    command -v op >/dev/null || fail "This needs the 1Password CLI: brew install 1password-cli."
    klipy_write_xcconfig "$klipy_secrets_xcconfig" \
      || fail "Couldn't read the key from $where. Is 1Password unlocked?"
    print -P "%F{green}✓%f Wrote $klipy_secrets_xcconfig (git-ignored). Build Vela Dev again to search GIFs."
    ;;
  remove)
    rm -f "$klipy_secrets_xcconfig"
    print -P "%F{green}✓%f Removed $klipy_secrets_xcconfig."
    ;;
  check)
    command -v op >/dev/null || fail "This needs the 1Password CLI: brew install 1password-cli."
    key=$(klipy_read_key) || fail "Couldn't read the key from $where. Is 1Password unlocked?"
    klipy_key_is_valid "$key" || fail "$where has no usable key in its $klipy_key_field field."
    print -P "%F{green}✓%f The KLIPY key in $where can be read (${#key} characters)."
    ;;
esac
