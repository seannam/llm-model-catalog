#!/usr/bin/env bash
# Given a commit range, output the required bump kind: major, minor, patch, or none.
# Usage: commit-bump.sh <range> [--strict-semver]
#   range: any git log-compatible range (e.g. v1.2.3..HEAD, or HEAD for "all history").
#   --strict-semver: fix:/perf: count as patch. Default: fix:/perf: count as none
#     (appropriate for iOS/macOS TestFlight iteration, where patch-level fixes
#     don't warrant a new marketing version).
#
# Rules (precedence, first match wins):
#   1. `^<type>(<scope>)?!:` or `BREAKING CHANGE:` in body  -> major
#   2. `^feat(<scope>)?:`                                   -> minor
#   3. `^fix(<scope>)?:` or `^perf(<scope>)?:` (strict only)-> patch
#   4. otherwise                                            -> none
#
# Exit: always 0 (result is in stdout). Downstream uses should-release.sh for gating.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
. "$SCRIPT_DIR/common.sh"

range="${1:-}"
if [ -z "$range" ] || [ "$range" = "-h" ] || [ "$range" = "--help" ]; then
  echo "usage: commit-bump.sh <range> [--strict-semver]" >&2
  [ -n "$range" ] || exit 1
  exit 0
fi
shift

strict="false"
while [ $# -gt 0 ]; do
  case "$1" in
    --strict-semver) strict="true"; shift ;;
    *) die "unknown arg: $1" ;;
  esac
done

commits="$(git log "$range" --no-merges --pretty=format:'%s%n%b%n---END---' 2>/dev/null || true)"

if [ -z "$commits" ]; then
  printf 'none\n'
  exit 0
fi

# 1. Breaking: any `<type>(<scope>)?!:` subject OR `BREAKING CHANGE:` in body.
if printf '%s\n' "$commits" | grep -qE '^[a-zA-Z]+(\([^)]*\))?!:' \
  || printf '%s\n' "$commits" | grep -qE '^BREAKING CHANGE:'; then
  printf 'major\n'
  exit 0
fi

# 2. feat:
if printf '%s\n' "$commits" | grep -qE '^feat(\([^)]*\))?:'; then
  printf 'minor\n'
  exit 0
fi

# 3. fix: or perf:, only when --strict-semver.
if [ "$strict" = "true" ] && printf '%s\n' "$commits" | grep -qE '^(fix|perf)(\([^)]*\))?:'; then
  printf 'patch\n'
  exit 0
fi

printf 'none\n'
