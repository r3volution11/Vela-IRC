#!/bin/zsh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Checks GIF search against the real services: trending and a search
# (two pages), a preview and the GIF itself load, and a made-up key is
# refused. Spends five requests per service, so mind a test key's
# 100 an hour.
#
#   VELA_KLIPY_API_KEY=… scripts/check-gif-search.sh
#   scripts/check-gif-search.sh --op "op://Vela/KLIPY API key/credential"
#
# Add VELA_GIPHY_API_KEY=… to check GIPHY too.

set -euo pipefail
cd "${0:A:h}/.."

if [[ "${1:-}" == "--op" ]]; then
  [[ -n "${2:-}" ]] || { echo "usage: $0 --op <1Password reference>" >&2; exit 2; }
  VELA_KLIPY_API_KEY="$(op read "$2")"
  export VELA_KLIPY_API_KEY
fi

if [[ -z "${VELA_KLIPY_API_KEY:-}" ]]; then
  echo "Set VELA_KLIPY_API_KEY, or pass --op with the key's 1Password reference." >&2
  exit 2
fi

VELA_LIVE_GIF_TESTS=1 exec swift test --package-path Packages/VelaKit --filter LiveGIFSearchTests
