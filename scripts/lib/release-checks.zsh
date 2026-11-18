# Shared by scripts/release.sh, scripts/release-preflight.sh and
# scripts/verify-release.sh (sourced, not run): PASS/FAIL/SKIP results, the
# summary at the end, and reading the Vela target's build settings.
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
