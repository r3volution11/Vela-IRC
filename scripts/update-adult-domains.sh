#!/bin/zsh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Refreshes the adult-domain list bundled with Vela. The adult-site filter
# blocks link, image and video previews from these domains and their
# subdomains; the links themselves stay clickable. Vela never downloads the
# list at runtime, so run this before each release and commit the result.
#
#   scripts/update-adult-domains.sh                # latest upstream commit
#   scripts/update-adult-domains.sh --ref <sha>    # a specific upstream commit
#   scripts/update-adult-domains.sh --force        # accept a big drop in size
#
# Source: the `pornography-hosts` file from Sinfonietta/hostfiles (MIT). The
# script normalizes it (lowercase hosts, no IP addresses, one leading www./
# www2./m./mobile. removed, no duplicates, no subdomains of listed domains)
# and drops every host in scripts/adult-domains-exclude.txt. It stops if the
# result has fewer than 10,000 domains, or under 70% of the current file's
# count unless --force is given.
#
# Needs git, curl, awk and comm (all part of macOS with the Xcode tools).
#
# Output: Packages/VelaKit/Sources/VelaMedia/Resources/adult-domains.txt
set -euo pipefail
cd "${0:A:h}/.."
export LC_ALL=C

repo="Sinfonietta/hostfiles"
upstream_file="pornography-hosts"
exclude="scripts/adult-domains-exclude.txt"
out="Packages/VelaKit/Sources/VelaMedia/Resources/adult-domains.txt"
min_count=10000
min_ratio=70 # percent of the previous count

ref=""
force=0
while (( $# )); do
  case "$1" in
    --ref) (( $# >= 2 )) || { echo "--ref needs a commit" >&2; exit 2; }; ref="$2"; shift 2 ;;
    --force) force=1; shift ;;
    -h|--help) sed -n '/^# Refreshes/,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

step() { print -P "%F{magenta}==>%f %B$1%b"; }
fail() { print -P "%F{red}error:%f $1" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# ---------------------------------------------------------------- resolve commit
if [[ -z "$ref" ]]; then
  sha=$(git ls-remote "https://github.com/$repo.git" HEAD | awk '{print $1}')
elif [[ "$ref" =~ '^[0-9a-f]{40}$' ]]; then
  sha="$ref"
else
  [[ "$ref" =~ '^[A-Za-z0-9._/-]+$' ]] || fail "Not a valid ref: $ref"
  sha=$(curl -fsSL -H "Accept: application/vnd.github.sha" \
    "https://api.github.com/repos/$repo/commits/$ref") || fail "Couldn't resolve $ref in $repo."
fi
[[ "$sha" =~ '^[0-9a-f]{40}$' ]] || fail "Couldn't resolve the upstream commit (got \"$sha\")."
step "Upstream $repo @ $sha"

# ---------------------------------------------------------------- download
raw="https://raw.githubusercontent.com/$repo/$sha"
curl -fsSL --retry 3 "$raw/$upstream_file" -o "$work/hosts" || fail "Couldn't download $upstream_file."
curl -fsSL --retry 3 "$raw/LICENSE" -o "$work/LICENSE" || fail "Couldn't download LICENSE."
tr -d '\r' < "$work/LICENSE" > "$work/LICENSE.lf"
grep -q "^The MIT License" "$work/LICENSE.lf" \
  && grep -q "Permission is hereby granted, free of charge" "$work/LICENSE.lf" \
  || fail "Upstream LICENSE is no longer the MIT license. Review it before shipping the list."
print "    $(wc -l < "$work/hosts" | tr -d ' ') upstream lines"

# ---------------------------------------------------------------- normalize
# Reads the exclude list, then the hosts file ("<address> <host> …"). Prints
# kept hosts to stdout and writes invalid and excluded entries to side files.
step "Normalizing"
awk -v invalid="$work/invalid" -v excluded="$work/excluded" '
  function valid(h,   n, i, label) {
    if (length(h) > 253) return 0
    n = split(h, label, ".")
    if (n < 2) return 0
    for (i = 1; i <= n; i++)
      if (length(label[i]) > 63 || label[i] !~ /^[a-z0-9_]([a-z0-9_-]*[a-z0-9_])?$/) return 0
    # A numeric or underscored last label is an IPv4 literal or junk.
    return label[n] !~ /^[0-9]+$/ && label[n] !~ /_/
  }
  FNR == NR {
    sub(/#.*/, ""); gsub(/[ \t\r]/, "")
    if ($0 != "") skip[tolower($0)] = 1
    next
  }
  {
    sub(/\r$/, "")
    if ($1 ~ /^#/ || NF < 2) next
    host = tolower($2); sub(/\.+$/, "", host)
    if (!valid(host)) { print $2 > invalid; next }
    if (host ~ /^(www|www2|m|mobile)\./) {
      rest = substr(host, index(host, ".") + 1)
      if (index(rest, ".")) host = rest
    }
    if (host in skip) { print host " (upstream: " $2 ")" > excluded; next }
    print host
  }
' "$exclude" "$work/hosts" | sort -u > "$work/normalized"
touch "$work/invalid" "$work/excluded"

# Drop subdomains of listed domains: Vela already matches them by walking up
# a host's parent domains.
awk '
  { listed[$0] = 1; order[NR] = $0 }
  END {
    for (i = 1; i <= NR; i++) {
      host = order[i]; rest = host; covered = 0
      while ((dot = index(rest, ".")) > 0) {
        rest = substr(rest, dot + 1)
        if (rest in listed) { covered = 1; break }
      }
      if (!covered) print host
    }
  }
' "$work/normalized" > "$work/domains"

count=$(wc -l < "$work/domains" | tr -d ' ')
print "    $(wc -l < "$work/invalid" | tr -d ' ') invalid entries dropped (IP addresses, malformed hosts)"
head -20 "$work/invalid" | sed 's/^/      /'
print "    $(( $(wc -l < "$work/normalized") - count )) subdomains of listed domains dropped"
if [[ -s "$work/excluded" ]]; then
  print "    Excluded by $exclude:"
  sort -u "$work/excluded" | sed 's/^/      /'
else
  print "    Nothing upstream matched $exclude"
fi

# ---------------------------------------------------------------- sanity checks
awk '!/^#/ && NF' "$out" 2>/dev/null | sort -u > "$work/previous" || true
previous=$(wc -l < "$work/previous" | tr -d ' ')
(( count >= min_count )) || fail "Only $count domains (expected at least $min_count). Upstream may have changed format."
if (( previous > 0 && count * 100 < previous * min_ratio && ! force )); then
  fail "$count domains is under $min_ratio%% of the current $previous. Check upstream, then rerun with --force to accept."
fi

# ---------------------------------------------------------------- write
step "Writing $out"
mkdir -p "${out:h}"
{
  print "# Adult domains for Vela's adult-site filter. Vela blocks link, image and"
  print "# video previews from these domains and their subdomains; links stay"
  print "# clickable."
  print "#"
  print "# Generated by scripts/update-adult-domains.sh; don't edit by hand. To keep"
  print "# a site off the list, add it to scripts/adult-domains-exclude.txt and run"
  print "# the script again."
  print "#"
  print "# Source:  https://github.com/$repo ($upstream_file)"
  print "# Commit:  $sha"
  print "# Date:    $(date -u +%Y-%m-%d)"
  print "# Domains: $count"
  print "#"
  print "# The list is derived from Sinfonietta/hostfiles, used under its license:"
  print "#"
  sed 's/^/# /; s/ *$//' "$work/LICENSE.lf"
  cat "$work/domains"
} > "$work/out"
mv "$work/out" "$out"

# ---------------------------------------------------------------- summary
comm -13 "$work/previous" "$work/domains" > "$work/added"
comm -23 "$work/previous" "$work/domains" > "$work/removed"
added=$(wc -l < "$work/added" | tr -d ' ')
removed=$(wc -l < "$work/removed" | tr -d ' ')
step "$count domains ($(( $(wc -c < "$out") / 1024 )) KB): +$added added, -$removed removed vs the previous file ($previous)"
# Small diffs are worth a glance before committing.
if (( previous > 0 && added + removed <= 40 )); then
  sed 's/^/    + /' "$work/added"
  sed 's/^/    - /' "$work/removed"
fi
