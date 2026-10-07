#!/usr/bin/env bash
# Runs bump-version.sh against the fixtures in this directory (on copies) and
# checks the result. Usage: tests/bump-version/run-tests.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../../bump-version/bump-version.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
today="$(date -u +%Y-%m-%d)"
fail=0
check() { # description, condition-exit-status
  if [ "$2" -eq 0 ]; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi
}
has()  { grep -qF -- "$2" "$1"; }
same() { cmp -s "$1" "$2"; }

cp -r "$here"/pkg-dev "$here"/pkg-release "$here"/mod_list "$here"/mod_numeric \
      "$here"/mod_release "$here"/mod_bare "$work"/

"$script" "$work/pkg-dev" >/dev/null
has "$work/pkg-dev/DESCRIPTION" "Version: 3.2.1.9001"; check "package dev version bumped" $?
has "$work/pkg-dev/DESCRIPTION" "Date: $today";        check "package Date set to today" $?
has "$work/pkg-dev/DESCRIPTION" "Depends: R (>= 4.0)"; check "package other fields untouched" $?

"$script" "$work/pkg-release" >/dev/null
same "$work/pkg-release/DESCRIPTION" "$here/pkg-release/DESCRIPTION"; check "package release version skipped, file unchanged" $?

"$script" "$work/mod_list" >/dev/null
has "$work/mod_list/mod_list.R" 'mod_list = "1.0.4.9010"'; check "module list form bumped" $?
has "$work/mod_list/mod_list.R" 'SpaDES.core = "0.1.0"';  check "module's other version entries untouched" $?

"$script" "$work/mod_numeric" >/dev/null
has "$work/mod_numeric/mod_numeric.R" 'numeric_version("2.1.0.9001")'; check "module numeric_version form bumped" $?
same "$work/mod_numeric/mod_numeric.html" "$here/mod_numeric/mod_numeric.html"; check "module rendered .html left alone" $?

"$script" "$work/mod_bare" >/dev/null
has "$work/mod_bare/mod_bare.R" 'version = numeric_version("2.1.0.9001")'; check "module bare numeric_version bumped" $?
has "$work/mod_bare/mod_bare.R" 'x (>= 1.0.0.9001)';                        check "module reqdPkgs untouched" $?

"$script" "$work/mod_release" >/dev/null
same "$work/mod_release/mod_release.R" "$here/mod_release/mod_release.R"; check "module release version skipped, file unchanged" $?

# GITHUB_OUTPUT reports the outcome
GITHUB_OUTPUT="$work/out" "$script" "$work/pkg-dev" >/dev/null
has "$work/out" "bumped=true"; check "output bumped=true" $?
has "$work/out" "new-version=3.2.1.9002"; check "output new-version" $?
: > "$work/out"; GITHUB_OUTPUT="$work/out" "$script" "$work/pkg-release" >/dev/null
has "$work/out" "bumped=false"; check "output bumped=false on release" $?

# A directory that is neither: skipped, not an error
mkdir "$work/empty"; "$script" "$work/empty" >/dev/null; check "neither package nor module: skipped" $?

[ "$fail" -eq 0 ] && echo "all bump-version tests passed" || { echo "bump-version tests FAILED"; exit 1; }
