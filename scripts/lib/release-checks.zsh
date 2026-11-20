# Shared by scripts/release.sh, scripts/release-preflight.sh and
# scripts/verify-release.sh (sourced, not run): PASS/FAIL/SKIP results, the
# summary at the end, reading the Vela target's build settings, and checking
# a built app's App Intents metadata.
#
# Each result is printed as it happens and kept for the summary. When
# RELEASE_CHECKS_RESULTS names a file, results are appended to it too, one per
# line: status, group, check, detail and fix, separated by tabs. That's how
# scripts/release.sh collects the results of both scripts into one summary.

typeset -g RELEASE_CHECKS_RESULTS=${RELEASE_CHECKS_RESULTS:-}
typeset -gi release_checks_failed=0
typeset -g release_checks_group=""

step() { print -P "%F{magenta}==>%f %B$1%b"; }

# check_section <group>: starts a group of checks ("Git", "Version", …).
check_section() {
  release_checks_group=$1
  step "$1"
}

_check_record() { # <status> <check> <detail> <fix>
  [[ -n $RELEASE_CHECKS_RESULTS ]] || return 0
  print -r -- "$1"$'\t'"$release_checks_group"$'\t'"$2"$'\t'"${3//$'\t'/ }"$'\t'"${4//$'\t'/ }" >> "$RELEASE_CHECKS_RESULTS"
}

# check_pass <check> [detail]
check_pass() {
  _check_record PASS "$1" "${2:-}" ""
  print -nP "    %F{green}PASS%f  "
  print -r -- "$1${2:+: $2}"
}

# check_fail <check> <what's wrong> <how to fix it>
check_fail() {
  _check_record FAIL "$1" "${2:-}" "${3:-}"
  release_checks_failed+=1
  print -nP "    %F{red}FAIL%f  "
  print -r -- "$1${2:+: $2}"
  if [[ -n ${3:-} ]]; then
    print -r -- "          Fix: $3"
  fi
}

# check_skip <check> <why>
check_skip() {
  _check_record SKIP "$1" "${2:-}" ""
  print -nP "    %F{yellow}SKIP%f  "
  print -r -- "$1${2:+: $2}"
}

# print_check_summary <results file>: every result, failures with their fix.
print_check_summary() {
  local file=$1 line group
  local -a fields
  local -i passed=0 failed=0 skipped=0
  [[ -s $file ]] || return 0
  print
  step "Summary"
  while IFS= read -r line; do
    fields=("${(@ps:\t:)line}")
    case $fields[1] in
      PASS) passed+=1; print -nP "    %F{green}PASS%f  " ;;
      FAIL) failed+=1; print -nP "    %F{red}FAIL%f  " ;;
      *) skipped+=1; print -nP "    %F{yellow}SKIP%f  " ;;
    esac
    group=${fields[2]:-}
    # "Git: On main", but "CI workflow" rather than "CI: CI workflow".
    [[ "${fields[3]:l}" == "${group:l}"* ]] && group=""
    print -r -- "${group:+$group: }${fields[3]:-}${fields[4]:+: ${fields[4]}}"
    if [[ $fields[1] == FAIL && -n ${fields[5]:-} ]]; then
      print -r -- "          Fix: ${fields[5]}"
    fi
  done < "$file"
  local totals="$passed passed, $failed failed, $skipped skipped"
  if (( failed )); then
    print -P "    %F{red}$totals%f"
  else
    print -P "    %F{green}$totals%f"
  fi
}

# vela_setting <project.pbxproj> <Debug|Release> <key>: prints a build setting
# of the Vela target's configuration; fails if there's no such setting.
vela_setting() {
  local file=$1 configuration=$2 key=$3 root target="" list id
  local -i count i
  root=$(plutil -extract rootObject raw -o - "$file" 2>/dev/null) || return 1
  count=$(plutil -extract "objects.$root.targets" raw -o - "$file" 2>/dev/null) || return 1
  for (( i = 0; i < count; i++ )); do
    id=$(plutil -extract "objects.$root.targets.$i" raw -o - "$file" 2>/dev/null) || return 1
    if [[ $(plutil -extract "objects.$id.name" raw -o - "$file" 2>/dev/null || true) == Vela ]]; then
      target=$id
      break
    fi
  done
  [[ -n $target ]] || return 1
  list=$(plutil -extract "objects.$target.buildConfigurationList" raw -o - "$file" 2>/dev/null) || return 1
  count=$(plutil -extract "objects.$list.buildConfigurations" raw -o - "$file" 2>/dev/null) || return 1
  for (( i = 0; i < count; i++ )); do
    id=$(plutil -extract "objects.$list.buildConfigurations.$i" raw -o - "$file" 2>/dev/null) || return 1
    if [[ $(plutil -extract "objects.$id.name" raw -o - "$file" 2>/dev/null || true) == "$configuration" ]]; then
      plutil -extract "objects.$id.buildSettings.$key" raw -o - "$file" 2>/dev/null
      return
    fi
  done
  return 1
}

# check_app_intents <Vela.app> <shortcuts source>: the App Intents metadata
# Siri, Shortcuts and Spotlight read from the app, as Xcode's
# appintentsmetadataprocessor wrote it to
# Contents/Resources/Metadata.appintents:
#   • extract.actionsdata has as many App Shortcuts as the shortcuts source
#     (Vela/VelaShortcuts.swift) declares with AppShortcut(…);
#   • its actions include CatchMeUpIntent and OpenChannelIntent from the
#     VelaIntents module;
#   • extract.packagedata includes the VelaIntents package
#     (VelaIntentsPackage), which brings in the package's intents.
# A metadata problem doesn't stop the build, so this is where it shows.
check_app_intents() {
  local app=$1 source=$2 id name included
  local metadata="$app/Contents/Resources/Metadata.appintents"
  local actions="$metadata/extract.actionsdata" packages="$metadata/extract.packagedata"
  local fix="Read the appintentsmetadataprocessor lines in build/release/archive.log, fix what they point at and build again."
  local -i expected found
  local -a missing
  # plutil reads the JSON files too (but -lint only checks property lists).
  if [[ ! -f $actions ]] || ! plutil -type actions "$actions" >/dev/null 2>&1; then
    check_fail "App Intents metadata" "Contents/Resources/Metadata.appintents/extract.actionsdata is missing or unreadable" "$fix"
    return 0
  fi

  expected=$(grep -cE '^[[:space:]]*AppShortcut\(' "$source" 2>/dev/null) || expected=0
  found=$(plutil -extract autoShortcuts raw -o - "$actions" 2>/dev/null) || found=-1
  if (( expected == 0 )); then
    check_fail "App Shortcuts" "couldn't count the AppShortcut(…) entries in $source" \
      "Check that $source is the app's AppShortcutsProvider."
  elif (( found == expected )); then
    check_pass "App Shortcuts" "$found, as in ${source:t}"
  else
    check_fail "App Shortcuts" "the app has $(( found < 0 ? 0 : found )), ${source:t} declares $expected" "$fix"
  fi

  for id in CatchMeUpIntent OpenChannelIntent; do
    name=$(plutil -extract "actions.$id.fullyQualifiedTypeName" raw -o - "$actions" 2>/dev/null) || name=""
    [[ $name == "VelaIntents.$id" ]] || missing+=($id)
  done
  if (( ${#missing} )); then
    check_fail "App Intents actions" "${(j:, :)missing} missing from the metadata" "$fix"
  else
    found=$(plutil -extract actions raw -o - "$actions" 2>/dev/null | grep -c .) || found=0
    check_pass "App Intents actions" "CatchMeUpIntent and OpenChannelIntent from VelaIntents ($found actions in all)"
  fi

  included=$(plutil -extract includes json -o - "$packages" 2>/dev/null) || included=""
  if [[ $included == *11VelaIntents*PackageV* ]]; then
    check_pass "App Intents package" "VelaIntentsPackage is included"
  else
    check_fail "App Intents package" "extract.packagedata doesn't include VelaIntentsPackage" \
      "Check that VelaAppIntentsPackage in Vela/VelaShortcuts.swift lists VelaIntentsPackage, then build again."
  fi
}
