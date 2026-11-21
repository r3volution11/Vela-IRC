# Shared by scripts/klipy-key.sh, scripts/release.sh and
# scripts/verify-release.sh (sourced, not run): where the GIF picker's KLIPY
# API key lives in 1Password, and how a build gets it.
#
# The key ends up in every copy of Vela (KLIPY requires calls from the app
# itself, so anyone with the app can read it); it's only kept out of the
# repository. Release builds get it straight from 1Password; local builds
# from the git-ignored Config/Secrets.xcconfig.

# 1Password: VELA_OP_ACCOUNT, VELA_KLIPY_VAULT and VELA_KLIPY_ITEM override
# the defaults. Doug's Mac is signed in to more than one account.
typeset -g klipy_op_account="${VELA_OP_ACCOUNT:-my.1password.com}"
typeset -g klipy_vault="${VELA_KLIPY_VAULT:-Personal}"
typeset -g klipy_item="${VELA_KLIPY_ITEM:-Vela - KLIPY - Mac API Credentials}"
# The key is the API Credential item's "credential" field.
typeset -g klipy_key_field=credential

# Where local builds read it (Config/Vela.xcconfig includes it).
typeset -g klipy_secrets_xcconfig=Config/Secrets.xcconfig

# klipy_read_key: prints the key, with no newline (to a pipe or $(…), please).
klipy_read_key() {
  op --account "$klipy_op_account" read --no-newline "op://$klipy_vault/$klipy_item/$klipy_key_field"
}

# klipy_key_is_valid <key>: a key, not empty or an unexpanded $(…).
klipy_key_is_valid() {
  [[ -n "$1" && "$1" != '$('* && "$1" != *[[:space:]]* ]]
}

# klipy_write_xcconfig <file>: writes VELA_KLIPY_API_KEY = <key> to <file>,
# readable only by you. Fails without writing if the key can't be read.
klipy_write_xcconfig() {
  local file="$1" key
  key=$(klipy_read_key) || return 1
  klipy_key_is_valid "$key" || return 1
  ( umask 077; print -r -- "VELA_KLIPY_API_KEY = $key" > "$file" )
}
