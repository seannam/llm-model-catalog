#!/usr/bin/env bash
# Promote spec rows in specs/.index based on commit messages in a git range.
# Used by release.sh (mark-live after a GitHub release) and apple-bump.sh
# (mark-needs_review after a TestFlight upload).
#
# Usage:
#   promote-specs.sh --range <revspec> --status <live|needs_review> [--dry-run]
#
# Behavior:
#   - Walks commits in <revspec>, extracts spec filenames from messages.
#     Matches basenames of the form NNNN-*.md and plan-*.md.
#   - For each referenced spec row in specs/.index whose current status is a
#     valid source for the target, rewrites status and stamps the implemented
#     column with today's date if it was empty.
#   - Assumes specs/.index is at schema v5 (line 2 is `# schema: v5`). Bails
#     quietly otherwise; the caller should not block a release on this.
#   - Best-effort: exits 0 even when there is nothing to do, the range is
#     invalid, or specs/.index is missing.
#
# Transitions:
#   --status live         : implemented | needs_review  -> live
#   --status needs_review : implemented                 -> needs_review
#
# Output:
#   - One "promote-specs: <spec> <from> -> <to>" line per row changed (stderr).
#   - Final "changed=N" line on stdout so callers can decide whether to commit.

set -euo pipefail

MIGRATE_SCRIPT="$HOME/.claude/scripts/idd/migrate-index.sh"
if [ -f "$MIGRATE_SCRIPT" ]; then
  # shellcheck source=/dev/null
  source "$MIGRATE_SCRIPT"
fi

range=""
target=""
dry="false"
version=""
build=""

while [ $# -gt 0 ]; do
  case "$1" in
    --range) range="$2"; shift 2 ;;
    --status) target="$2"; shift 2 ;;
    --dry-run) dry="true"; shift ;;
    --version) version="$2"; shift 2 ;;
    --build) build="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) printf 'promote-specs: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$range" ] || { printf 'promote-specs: --range required\n' >&2; exit 2; }
case "$target" in
  live|needs_review) ;;
  *) printf 'promote-specs: --status must be live or needs_review\n' >&2; exit 2 ;;
esac

index="specs/.index"
if [ ! -f "$index" ]; then
  printf 'changed=0\n'
  exit 0
fi

schema_line="$(awk 'NR==2' "$index" 2>/dev/null || true)"
if [ "$schema_line" != "# schema: v5" ]; then
  if type migrate_index_to_v5 >/dev/null 2>&1; then
    if ! migrate_index_to_v5 "$index"; then
      printf 'promote-specs: failed to migrate %s to v5\n' "$index" >&2
      printf 'changed=0\n'
      exit 0
    fi
  else
    printf 'promote-specs: %s is not at schema v5 and migrate-index.sh not found; skipping\n' "$index" >&2
    printf 'changed=0\n'
    exit 0
  fi
fi

specs_found="$(
  git log --format=%B "$range" 2>/dev/null \
    | grep -oE '([0-9]{4}-[A-Za-z0-9_-]+\.md|plan-[A-Za-z0-9_-]+\.md)' \
    | sort -u || true
)"

if [ -z "$specs_found" ]; then
  printf 'changed=0\n'
  exit 0
fi

today="$(date '+%Y-%m-%dT%H:%M:%S')"
tmp="$(mktemp)"
log_tmp="$(mktemp)"
trap 'rm -f "$tmp" "$log_tmp"' EXIT

# Use awk for the rewrite: bash `read` with IFS=$'\t' collapses consecutive
# tabs (tab is whitespace), which would mangle rows whose `implemented` column
# is empty. awk -F'\t' preserves empty fields correctly.
awk -F'\t' -v OFS='\t' \
    -v specs="$specs_found" \
    -v target="$target" \
    -v today="$today" \
    -v dry="$dry" \
    -v ver="$version" \
    -v bld="$build" '
BEGIN {
  n = split(specs, arr, "\n")
  for (i = 1; i <= n; i++) if (arr[i] != "") want[arr[i]] = 1
  if (target == "live") {
    src["implemented"] = 1
    src["needs_review"] = 1
  } else {
    src["implemented"] = 1
  }
  changed = 0
}
NR <= 2 { print; next }
/^#/    { print; next }
NF == 0 { print; next }
NF < 6  { print; next }
{
  spec = $1; status = $6
  if ((spec in want) && (status in src) && status != target) {
    from = status
    changed++
    printf "promote-specs: %s %s -> %s%s\n", spec, from, target, (dry == "true" ? " (dry-run)" : "") > "/dev/stderr"
    if (dry != "true") {
      if ($3 == "") $3 = today
      if (ver != "" && $4 == "") $4 = ver
      if (bld != "" && $5 == "") $5 = bld
      $6 = target
    }
  }
  print
}
END { printf "%d\n", changed > "/dev/stderr" }
' "$index" > "$tmp" 2> "$log_tmp"

# Surface change events to the caller's stderr.
grep '^promote-specs:' "$log_tmp" >&2 || true

# Count is the sole numeric line (awk END).
changed="$(grep -E '^[0-9]+$' "$log_tmp" | tail -1 || true)"
changed="${changed:-0}"

if [ "$changed" -gt 0 ] && [ "$dry" != "true" ]; then
  mv "$tmp" "$index"
fi

printf 'changed=%d\n' "$changed"
