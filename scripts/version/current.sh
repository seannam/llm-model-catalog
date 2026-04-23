#!/usr/bin/env bash
# Print the current version. Resolution order: git tag (vX.Y.Z), primary
# manifest, VERSION file, then 0.1.0 fallback. Apple presets also surface
# marketing + next build in --verbose mode.
#
# Usage: current.sh [--raw|--tag|--verbose|--inventory]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

mode_out="raw"
while [ $# -gt 0 ]; do
  case "$1" in
    --raw) mode_out="raw"; shift ;;
    --tag) mode_out="tag"; shift ;;
    --verbose) mode_out="verbose"; shift ;;
    --inventory) mode_out="inventory"; shift ;;
    -h|--help) echo "usage: current.sh [--raw|--tag|--verbose|--inventory]"; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

is_repo_root || die "not inside a git repository" 30

if [ "$mode_out" = "inventory" ]; then
  preflight="$SCRIPT_DIR/lib/adopt-preflight.sh"
  [ -x "$preflight" ] || die "adopt-preflight.sh missing at $preflight" 10
  "$preflight" | jq .
  exit 0
fi

v="$(resolve_current_version)"

case "$mode_out" in
  raw) printf '%s\n' "$v" ;;
  tag) printf 'v%s\n' "$v" ;;
  verbose)
    preset_mode_val="$(preset_mode 2>/dev/null || true)"
    printf 'Resolved: %s\n' "$v"
    printf 'Preset:   %s\n' "$(printf '%s\n' "$(preset_state 2>/dev/null)" | awk -F= '/^NAME=/ {print $2}')"
    printf 'Mode:     %s\n' "${preset_mode_val:-manual}"

    latest_tag="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname 2>/dev/null | head -1 || true)"
    printf 'Git tag:  %s\n' "${latest_tag:-<none>}"

    if is_apple_mode 2>/dev/null && [ -f project.yml ]; then
      mkt="$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | awk '{print $2}' | tr -d '"' || true)"
      bld="$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | head -1 | awk '{print $2}' | tr -d '"' || true)"
      printf 'Marketing: %s\n' "${mkt:-unknown}"
      printf 'Build:     %s\n' "${bld:-unknown}"

      last_marketing_sha="$(git log --grep='^chore(release): v' --pretty=%H -1 2>/dev/null || true)"
      if [ -n "$last_marketing_sha" ]; then
        range="${last_marketing_sha}..HEAD"
      else
        range="HEAD"
      fi
      strict_flag=()
      [ "$preset_mode_val" = "apple-strict-semver" ] && strict_flag=( --strict-semver )
      pending="$("$SCRIPT_DIR/lib/commit-bump.sh" "$range" "${strict_flag[@]}" 2>/dev/null || echo unknown)"
      if [ "$pending" = "none" ]; then
        printf 'Pending marketing bump: no\n'
      else
        printf 'Pending marketing bump: yes (%s)\n' "$pending"
      fi
    else
      if [ -f VERSION ]; then
        printf 'VERSION:  %s\n' "$(tr -d '[:space:]' < VERSION)"
      fi
    fi
    ;;
esac
