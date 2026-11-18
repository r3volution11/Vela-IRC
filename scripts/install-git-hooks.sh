#!/bin/zsh
# Installs Vela's git hooks in this clone:
#
#   pre-push   When the commits you push change media code, checks that the
#              media sites Vela supports still work, and stops the push if one
#              broke (scripts/git-hooks/pre-push). Other pushes aren't slowed down.
#              Skip it for one push with `git push --no-verify`.
#
#   scripts/install-git-hooks.sh               # install
#   scripts/install-git-hooks.sh --uninstall   # remove
#   scripts/install-git-hooks.sh --force       # replace a pre-push hook that isn't Vela's
#                                              # (it's kept as pre-push.backup)
#
# What's installed is a small stub that runs scripts/git-hooks/pre-push from
# your checkout, so changes to the hook apply without installing it again.
# It goes wherever git looks for hooks (.git/hooks, or core.hooksPath if set).
set -euo pipefail
cd "${0:A:h}/.."

uninstall=0
force=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) uninstall=1 ;;
    --force) force=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "${0:A}" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
    *) print -u2 -r -- "Unknown option: $arg"; exit 2 ;;
  esac
done

marker="vela-git-hook"
hooks=${$(git rev-parse --git-path hooks):A}
hook="$hooks/pre-push"
ours() { [[ -f "$hook" ]] && grep -q "$marker" "$hook"; }

if (( uninstall )); then
  if ours; then
    rm "$hook"
    print "Removed the pre-push hook from $hook."
  else
    print "No Vela pre-push hook to remove."
  fi
  exit 0
fi

if [[ -e "$hook" ]] && ! ours; then
  if (( ! force )); then
    print -u2 "There's already a pre-push hook that isn't Vela's: $hook"
    print -u2 "Rerun with --force to replace it (it's kept as pre-push.backup)."
    exit 1
  fi
  mv "$hook" "$hook.backup"
  print "Kept your old hook as $hook.backup."
fi

mkdir -p "$hooks"
cat > "$hook" <<'HOOK'
#!/bin/sh
# vela-git-hook: installed by scripts/install-git-hooks.sh. Runs the checkout's
# own hook, so it's always the current one. Remove with --uninstall.
hook="$(git rev-parse --show-toplevel)/scripts/git-hooks/pre-push"
if [ -x "$hook" ]; then exec "$hook" "$@"; fi
exit 0
HOOK
chmod +x "$hook"
print "Installed the pre-push hook in $hook."
print "Pushes that change media code now check the media sites first; git push --no-verify skips that."
