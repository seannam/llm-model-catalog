#!/usr/bin/env bash
# Generate a CHANGELOG.md fragment (or full file) from conventional commits.
# Usage: changelog.sh [--since vX.Y.Z] [--version X.Y.Z] [--output CHANGELOG.md | -] [--append]
#
#   --since vX.Y.Z   Compute range from this tag to HEAD. Defaults to the latest vX.Y.Z tag.
#   --version X.Y.Z  Heading for the new section. Defaults to HEAD.
#   --output PATH    Where to write. Default CHANGELOG.md. Use "-" for stdout.
#   --append         Prepend the new section to existing CHANGELOG.md (default: print stdout if no CHANGELOG).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

since=""
version=""
output="CHANGELOG.md"
append="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --append) append="true"; shift ;;
    -h|--help) sed -n '1,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

is_repo_root || die "not inside a git repository" 30

if [ -z "$since" ]; then
  since="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname 2>/dev/null | head -1 || true)"
fi

if [ -z "$version" ]; then
  version="$(resolve_current_version)"
fi

if [ -n "$since" ]; then
  range="$since..HEAD"
  baseline="$since"
else
  range="HEAD"
  baseline="repo start"
fi

today="$(date +%Y-%m-%d)"

# Pull subjects in the range.
subjects_tmp="$(mktemp)"
if [ -n "$since" ]; then
  git log "$range" --no-merges --pretty=format:'%s' > "$subjects_tmp" || true
else
  git log --no-merges --pretty=format:'%s' > "$subjects_tmp" || true
fi

group_by_prefix() {
  local prefix="$1"
  grep -E "^${prefix}(\([^)]+\))?!?:" "$subjects_tmp" 2>/dev/null \
    | sed -E "s/^${prefix}(\([^)]+\))?!?:[[:space:]]*//" \
    | awk '!seen[$0]++' \
    || true
}

has_entries() {
  local out
  out=$(group_by_prefix "$1")
  [ -n "$out" ]
}

render_section() {
  local heading="$1" prefix="$2"
  local entries
  entries="$(group_by_prefix "$prefix")"
  if [ -n "$entries" ]; then
    printf '\n### %s\n\n' "$heading"
    printf '%s\n' "$entries" | sed 's/^/- /'
  fi
}

new_section="$(cat <<EOF
## [$version] - $today

_Changes since ${baseline}._
$(render_section "New" "feat")
$(render_section "Fixes" "fix")
$(render_section "Improvements" "(perf|refactor)")
EOF
)"

rm -f "$subjects_tmp"

write_output() {
  if [ "$output" = "-" ]; then
    printf '%s\n' "$new_section"
    return
  fi
  if [ "$append" = "true" ] && [ -f "$output" ]; then
    local existing
    existing="$(cat "$output")"
    {
      printf '# Changelog\n\n'
      printf '%s\n\n' "$new_section"
      # Strip any existing leading "# Changelog" from existing to avoid duplication.
      printf '%s\n' "$existing" | sed -e '1{/^# Changelog$/d;}' -e '1{/^$/d;}'
    } > "$output.tmp"
    mv "$output.tmp" "$output"
  else
    {
      printf '# Changelog\n\n'
      printf '%s\n' "$new_section"
    } > "$output"
  fi
  log "wrote changelog to $output"
}

write_output
