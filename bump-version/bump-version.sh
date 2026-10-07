#!/usr/bin/env bash
# Bump the development version of a package (DESCRIPTION) or a SpaDES module
# (<Module>.R) in place. Rules mirror reproducible's pre-commit hook:
#   * only a development version is bumped, i.e. four or more dotted components
#     (3.2.1.9000 -> 3.2.1.9001); a release version (3.2.1) is left alone;
#   * a package's Date: line is rewritten to today (UTC), when it has one.
# A module's rendered .md/.html and NEWS.md are never touched.
#
# Usage: bump-version.sh [DIR] [MODULE]
#   DIR     the repository root (default: .)
#   MODULE  module name; defaults to the basename of DIR. Used only when DIR
#           has no DESCRIPTION.
# Prints one line saying what happened. When $GITHUB_OUTPUT is set, writes
# `bumped=true|false`, `old-version=` and `new-version=` to it.
set -euo pipefail

dir="${1:-.}"
cd "$dir"
module="${2:-$(basename "$(pwd)")}"
today="$(date -u +%Y-%m-%d)"

out() { [ -n "${GITHUB_OUTPUT:-}" ] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT" || true; }

# Four or more dotted components => development version.
is_dev() { [ "$(printf '%s' "$1" | awk -F. '{ print NF }')" -ge 4 ]; }
bump() { printf '%s' "$1" | awk -F. 'BEGIN { OFS="." } { $NF = $NF + 1; print }'; }

skip() { echo "bump-version: $1; not bumping."; out bumped false; exit 0; }

if [ -f DESCRIPTION ]; then
  file=DESCRIPTION
  old="$(awk '/^Version:[[:space:]]*/ { sub(/^Version:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }' DESCRIPTION)"
  [ -n "$old" ] || skip "no Version: line in DESCRIPTION"
  is_dev "$old" || skip "DESCRIPTION Version $old is a release version"
  new="$(bump "$old")"
  tmp="$(mktemp)"
  awk -v ver="$new" -v dt="$today" '
    BEGIN { v=0; d=0 }
    /^Version:[[:space:]]*/ && !v { print "Version: " ver; v=1; next }
    /^Date:[[:space:]]*/    && !d { print "Date: "    dt;  d=1; next }
    { print }
  ' DESCRIPTION > "$tmp"
  cat "$tmp" > DESCRIPTION; rm -f "$tmp"
elif [ -f "$module.R" ] && grep -q 'defineModule' "$module.R"; then
  file="$module.R"
  # The version is `version = list(<Module> = "x.y.z.w")` or
  # `version = list(<Module> = numeric_version("x.y.z.w"))`, sometimes with
  # other entries (a required SpaDES.core version) beside it; only the module's
  # own entry is read and rewritten. A bare `version = numeric_version("...")`
  # is accepted when there is no named entry.
  old="$(MODULE="$module" perl -0777 -ne '
    my $m = quotemeta $ENV{MODULE};
    if (/\bversion\s*=\s*list\((.*)/s) {
      my $rest = $1;
      if ($rest =~ /\b$m\s*=\s*(?:numeric_version\(\s*)?["\x27]([0-9][0-9.]*)["\x27]/) { print $1; exit }
    }
    if (/\bversion\s*=\s*numeric_version\(\s*["\x27]([0-9][0-9.]*)["\x27]/) { print $1 }
  ' "$file")"
  [ -n "$old" ] || { echo "bump-version: no version entry for module $module in $file" >&2; out bumped false; exit 1; }
  is_dev "$old" || skip "$file version $old is a release version"
  new="$(bump "$old")"
  MODULE="$module" OLD="$old" NEW="$new" perl -0777 -i -pe '
    my $m = quotemeta $ENV{MODULE}; my $o = quotemeta $ENV{OLD};
    my $done = 0;
    if (/\bversion\s*=\s*list\(/) {
      $done = s/(\bversion\s*=\s*list\((?:(?!\bversion\s*=).)*?\b$m\s*=\s*(?:numeric_version\(\s*)?["\x27])$o(["\x27])/$1$ENV{NEW}$2/s;
    }
    $done or s/(\bversion\s*=\s*numeric_version\(\s*["\x27])$o(["\x27])/$1$ENV{NEW}$2/;
  ' "$file"
else
  skip "no DESCRIPTION and no $module.R with defineModule() in $(pwd)"
fi

if [ "$(grep -c . <<< "$new")" -ne 1 ] || ! grep -q "$new" "$file"; then
  echo "bump-version: could not write $new to $file" >&2; exit 1
fi
echo "bump-version: $file $old -> $new"
out bumped true; out old-version "$old"; out new-version "$new"
