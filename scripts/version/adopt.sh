#!/usr/bin/env bash
# Install the `version` skill into a partial-state repo without clobbering
# existing tags, releases, manifests, or CHANGELOG history.
#
# Steps (apply mode):
#   1. Run adopt-preflight.sh; capture inventory JSON.
#   2. Build a reconciliation plan from the inventory.
#   3. In --plan mode, print the plan and exit. Otherwise:
#   4. apply-preset.sh --adopt <preset> (no tag seed, preserves CHANGELOG,
#      warns on manifest drift before sync rewrites).
#   5. release.sh backfill (creates missing GitHub releases for existing tags).
#   6. Print final report.
#
# Usage:
#   adopt.sh [preset-name] [--plan] [--no-commit] [--force]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

preset_name=""
plan_only="false"
no_commit="false"
force="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --plan) plan_only="true"; shift ;;
    --no-commit) no_commit="true"; shift ;;
    --force) force="true"; shift ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*)
      die "unknown arg: $1" ;;
    *)
      [ -z "$preset_name" ] || die "multiple preset names given: $preset_name, $1"
      preset_name="$1"; shift ;;
  esac
done

require_cmd jq
require_cmd git
is_repo_root || die "not inside a git repository" 30
git remote get-url origin >/dev/null 2>&1 || die "no 'origin' remote configured (adopt refuses to run without an origin)" 30

# 1. Preflight.
preflight="$SCRIPT_DIR/lib/adopt-preflight.sh"
[ -x "$preflight" ] || die "adopt-preflight.sh missing at $preflight" 10

inventory="$("$preflight" --pretty)"

# 2. Select preset if not supplied.
if [ -z "$preset_name" ]; then
  if [ -x "$SCRIPT_DIR/detect-preset.sh" ]; then
    detected_name="$("$SCRIPT_DIR/detect-preset.sh" --first 2>/dev/null || true)"
    if [ -n "$detected_name" ]; then
      preset_name="$detected_name"
      log "auto-selected preset: $preset_name"
    fi
  fi
  [ -n "$preset_name" ] || die "no preset supplied and auto-detect found no match; pass [preset-name]" 10
fi
preset_exists "$preset_name" || die "preset not found: $preset_name" 10

# 3. Build plan.
resolved_version="$(jq -r '.resolved_version.value' <<<"$inventory")"
resolved_source="$(jq -r '.resolved_version.source' <<<"$inventory")"
tag_count="$(jq -r '.git.tags.count' <<<"$inventory")"
latest_tag="$(jq -r '.git.tags.latest // ""' <<<"$inventory")"
cl_exists="$(jq -r '.changelog.exists' <<<"$inventory")"
cl_format="$(jq -r '.changelog.format' <<<"$inventory")"
preset_state_val="$(jq -r '.preset.state' <<<"$inventory")"
detected_tool="$(jq -r '.detected_tool' <<<"$inventory")"
drift_count="$(jq -r '.drift | length' <<<"$inventory")"
missing_releases_count="$(jq -r '.git.releases.missing_for_tags | length' <<<"$inventory")"
releases_status="$(jq -r '.git.releases.status' <<<"$inventory")"

steps_json="[]"

add_step() {
  local kind="$1" target="$2" from="$3" to="$4" reason="$5"
  steps_json="$(jq \
    --arg kind "$kind" \
    --arg target "$target" \
    --arg from "$from" \
    --arg to "$to" \
    --arg reason "$reason" \
    '. + [{kind: $kind, target: $target, from: $from, to: $to, reason: $reason}]' <<<"$steps_json")"
}

# Preset install step.
if [ "$preset_state_val" = "absent" ]; then
  add_step "install-preset" ".version-preset" "<none>" "$preset_name" "no preset configured"
else
  existing_preset="$(jq -r '.preset.name // ""' <<<"$inventory")"
  if [ "$existing_preset" = "$preset_name" ]; then
    add_step "noop" ".version-preset" "$existing_preset" "$preset_name" "preset already matches"
  else
    add_step "reinstall-preset" ".version-preset" "${existing_preset:-<unknown>}" "$preset_name" "preset mismatch; reinstalling"
  fi
fi

# Drift warnings.
if [ "$drift_count" -gt 0 ]; then
  while IFS=$'\t' read -r dp mv rv; do
    add_step "sync-manifest" "$dp" "$mv" "$rv" "manifest disagrees with resolved version (source: $resolved_source wins)"
  done < <(jq -r '.drift[] | [.path, .manifest_version, .resolved_version] | @tsv' <<<"$inventory")
fi

# CHANGELOG.
if [ "$cl_exists" = "true" ]; then
  if [ "$cl_format" = "managed" ]; then
    add_step "preserve-changelog" "CHANGELOG.md" "$cl_format" "$cl_format" "managed format; appended by future bumps"
  else
    add_step "preserve-changelog" "CHANGELOG.md" "$cl_format" "$cl_format" "non-managed format; adopt will preserve history and prepend ## Unreleased"
  fi
else
  add_step "seed-changelog" "CHANGELOG.md" "<none>" "managed" "no CHANGELOG; will seed from conventional commits"
fi

# Tag policy: NEVER seed a fresh tag in adopt mode.
if [ "$tag_count" -gt 0 ]; then
  add_step "skip-tag-seed" "git" "$latest_tag" "$latest_tag" "tags already exist; adopt does not create new tags"
else
  add_step "skip-tag-seed" "git" "<none>" "<none>" "no tags; adopt leaves tag seeding to /version:install or /version:bump"
fi

# Release backfill.
if [ "$releases_status" = "ok" ] && [ "$missing_releases_count" -gt 0 ]; then
  while IFS= read -r missing_tag; do
    [ -z "$missing_tag" ] && continue
    add_step "backfill-release" "$missing_tag" "<missing>" "<release>" "tag exists on GitHub but has no release"
  done < <(jq -r '.git.releases.missing_for_tags[]' <<<"$inventory")
elif [ "$releases_status" = "ok" ] && [ "$missing_releases_count" = "0" ]; then
  add_step "backfill-release" "all-tags" "ok" "ok" "all existing tags already have releases"
else
  add_step "skip-backfill" "git-releases" "$releases_status" "$releases_status" "cannot reach GitHub releases API; backfill skipped"
fi

# Detected external tool.
if [ -n "$detected_tool" ]; then
  add_step "respect-external-tool" "$detected_tool" "present" "present" "external release tool detected; adopt installs in existing mode (no CI overwrite)"
fi

# Pretty-print plan.
plan_json="$(jq -n \
  --argjson inventory "$inventory" \
  --arg preset "$preset_name" \
  --argjson steps "$steps_json" \
  '{preset: $preset, resolved_version: $inventory.resolved_version, partial: $inventory.partial, steps: $steps}')"

print_plan() {
  printf '\n'
  printf '=== /version:adopt plan (preset=%s) ===\n' "$preset_name"
  printf 'Resolved version: %s (source: %s)\n' "$resolved_version" "$resolved_source"
  printf 'Partial state:    %s\n' "$(jq -r '.partial' <<<"$inventory")"
  printf '\nSteps:\n'
  jq -r '.steps[] | "  [\(.kind)] \(.target): \(.from) -> \(.to)  (\(.reason))"' <<<"$plan_json"
  printf '\n'
}

if [ "$plan_only" = "true" ]; then
  print_plan
  printf '%s\n' "$plan_json"
  log "--plan mode; no writes performed"
  exit 0
fi

print_plan

# 4. apply-preset.sh --adopt
apply_args=( "$preset_name" --adopt )
[ "$no_commit" = "true" ] && apply_args+=( --no-commit )
[ "$force" = "true" ] && apply_args+=( --force )
log "invoking apply-preset.sh ${apply_args[*]}"
"$SCRIPT_DIR/apply-preset.sh" "${apply_args[@]}"

# 5. release.sh backfill (best effort; never fails the adopt run).
if [ "$releases_status" = "ok" ] && [ "$missing_releases_count" -gt 0 ]; then
  log "backfilling $missing_releases_count missing GitHub release(s)"
  "$SCRIPT_DIR/release.sh" backfill || warn "release.sh backfill returned non-zero; continuing"
elif [ "$releases_status" != "ok" ]; then
  warn "skipping release backfill: $releases_status (re-run 'release.sh backfill' once gh is authenticated)"
fi

# 6. Final report.
printf '\n'
log "adopt complete."
printf 'Preset:         %s\n' "$preset_name"
printf 'Version:        %s (source: %s)\n' "$resolved_version" "$resolved_source"
printf 'Tags preserved: %s\n' "$tag_count"
printf 'CHANGELOG:      %s\n' "$cl_format"
printf 'Detected tool:  %s\n' "${detected_tool:-<none>}"
printf 'Next:\n'
printf '  /version:current   confirm resolved version\n'
printf '  /version:sync      resync manifests if drift is re-detected\n'
printf '  /version:bump      cut the next version (mode-dependent)\n'
