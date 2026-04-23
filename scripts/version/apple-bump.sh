#!/usr/bin/env bash
# Apple-platform version bumper. Writes MARKETING_VERSION and
# CURRENT_PROJECT_VERSION to project.yml, following these rules:
#
#   Marketing (CFBundleShortVersionString):
#     - `feat:` since last marketing commit     -> minor
#     - `!` / `BREAKING CHANGE`                 -> major
#     - `fix:` / `perf:`:
#         default                               -> no marketing bump (TestFlight
#                                                  iteration is normal within a
#                                                  marketing version)
#         --strict-semver                       -> patch (libraries / SPM)
#     - otherwise                               -> no marketing bump
#
#   Build (CFBundleVersion):
#     Always bump. max(ASC.next-build-number, local+1).
#
# Last marketing commit is detected by grepping commit messages for
# `^chore(release): v`. If none, treat the entire history as the range.
#
# Usage:
#   apple-bump.sh [--platform IOS|MAC_OS|TV_OS|VISION_OS|WATCH_OS]
#                 [--strict-semver]
#                 [--marketing X.Y.Z | --marketing-bump major|minor|patch | --no-marketing-bump]
#                 [--app-id <asc-app-id>]
#                 [--project <path/to/project.yml>]
#                 [--dry-run]
#
# Output (stdout, parseable KEY=value lines):
#   MARKETING=1.3.0
#   BUILD=48
#   TAG=v1.3.0-build-48
#   MARKETING_BUMPED=true
#   COMMIT_MESSAGE=chore(release): v1.3.0 build 48
#
# Consumers: push-testflight-build Phase 3, /version:bump, /version:current
# (verbose mode).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

platform="IOS"
strict="false"
force_marketing=""
force_bump=""
no_marketing="false"
app_id=""
project_yml=""
dry_run="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --platform) platform="$2"; shift 2 ;;
    --strict-semver) strict="true"; shift ;;
    --marketing) force_marketing="${2#v}"; shift 2 ;;
    --marketing-bump) force_bump="$2"; shift 2 ;;
    --no-marketing-bump) no_marketing="true"; shift ;;
    --app-id) app_id="$2"; shift 2 ;;
    --project) project_yml="$2"; shift 2 ;;
    --dry-run) dry_run="true"; shift ;;
    -h|--help)
      sed -n '/^#/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

case "$platform" in
  IOS|MAC_OS|TV_OS|VISION_OS|WATCH_OS) ;;
  *) die "invalid platform: $platform (must be IOS, MAC_OS, TV_OS, VISION_OS, WATCH_OS)" ;;
esac

is_repo_root || die "not inside a git repository" 30

# Locate project.yml
if [ -z "$project_yml" ]; then
  if [ -f project.yml ]; then
    project_yml="project.yml"
  else
    project_yml="$(find . -maxdepth 3 -name project.yml -not -path '*/node_modules/*' -not -path '*/Pods/*' | head -1)"
  fi
fi
[ -n "$project_yml" ] && [ -f "$project_yml" ] || die "project.yml not found (pass --project)" 12

# Read current marketing + build from project.yml
current_marketing="$(grep -E '^\s*MARKETING_VERSION:' "$project_yml" | head -1 | awk '{print $2}' | tr -d '"' || true)"
current_build="$(grep -E '^\s*CURRENT_PROJECT_VERSION:' "$project_yml" | head -1 | awk '{print $2}' | tr -d '"' || true)"
current_marketing="${current_marketing:-0.1.0}"
current_build="${current_build:-0}"

dbg "current: marketing=$current_marketing build=$current_build platform=$platform"

# Determine marketing bump decision
last_marketing_sha="$(git log --grep='^chore(release): v' --pretty=%H -1 2>/dev/null || true)"
if [ -n "$last_marketing_sha" ]; then
  range="${last_marketing_sha}..HEAD"
else
  range="HEAD"
fi
dbg "marketing-decision range: $range"

bump_kind=""
if [ -n "$force_marketing" ]; then
  :  # explicit marketing handled later
elif [ "$no_marketing" = "true" ]; then
  bump_kind="none"
elif [ -n "$force_bump" ]; then
  case "$force_bump" in
    major|minor|patch|none) bump_kind="$force_bump" ;;
    *) die "invalid --marketing-bump: $force_bump" ;;
  esac
else
  commit_bump_args=( "$range" )
  [ "$strict" = "true" ] && commit_bump_args+=( --strict-semver )
  bump_kind="$("$SCRIPT_DIR/lib/commit-bump.sh" "${commit_bump_args[@]}")"
fi

if [ -n "$force_marketing" ]; then
  new_marketing="$force_marketing"
  parse_semver "$new_marketing"
  marketing_bumped="true"
elif [ "$bump_kind" = "none" ]; then
  new_marketing="$current_marketing"
  marketing_bumped="false"
else
  new_marketing="$(bump_version "$current_marketing" "$bump_kind")"
  marketing_bumped="true"
fi

# Determine next build
asc_next=""
if command -v asc >/dev/null 2>&1; then
  [ -z "$app_id" ] && app_id="$(asc apps list --output table 2>/dev/null | awk 'NR==2 {print $1}' || true)"
  if [ -n "$app_id" ]; then
    asc_next="$(asc builds next-build-number --app "$app_id" --version "$new_marketing" --platform "$platform" 2>/dev/null | jq -r . 2>/dev/null || true)"
  fi
fi
local_next=$(( current_build + 1 ))
if [ -n "$asc_next" ] && [ "$asc_next" -gt "$local_next" ] 2>/dev/null; then
  new_build="$asc_next"
else
  new_build="$local_next"
fi

tag="v${new_marketing}-build-${new_build}"
if [ "$marketing_bumped" = "true" ]; then
  commit_msg="chore(release): v${new_marketing} build ${new_build}"
else
  commit_msg="chore: bump to build ${new_build}"
fi

# Emit stdout contract BEFORE mutating (so --dry-run output is identical).
printf 'MARKETING=%s\n' "$new_marketing"
printf 'BUILD=%s\n' "$new_build"
printf 'TAG=%s\n' "$tag"
printf 'MARKETING_BUMPED=%s\n' "$marketing_bumped"
printf 'COMMIT_MESSAGE=%s\n' "$commit_msg"
printf 'PROJECT_YML=%s\n' "$project_yml"

if [ "$dry_run" = "true" ]; then
  log "dry-run: would update $project_yml"
  exit 0
fi

# Apply to project.yml. Only touch the two lines; do not reformat the file.
# Portable sed: BSD (macOS) and GNU differ on -i; use the `.bak` trick and remove.
sed -E \
  -e "s/^([[:space:]]*MARKETING_VERSION:[[:space:]]*).*\$/\\1${new_marketing}/" \
  -e "s/^([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*).*\$/\\1${new_build}/" \
  "$project_yml" > "${project_yml}.tmp"
mv "${project_yml}.tmp" "$project_yml"

log "updated $project_yml: marketing=$new_marketing build=$new_build"

# Promote any specs shipping in this TestFlight build: implemented -> needs_review.
# TestFlight != App Store release, so we stop at needs_review. The final
# needs_review -> live transition happens when the ASC submission lands for
# real users (handled by the asc submission-health path, not here).
# Best-effort; never blocks the bump. Commits specs/.index separately so
# push-testflight-build's release commit stays clean.
if [ -x "$SCRIPT_DIR/lib/promote-specs.sh" ] && [ -f specs/.index ]; then
  last_build_tag="$(git tag --list 'v*-build-*' --sort=-creatordate 2>/dev/null | head -1 || true)"
  if [ -n "$last_build_tag" ]; then
    spec_range="${last_build_tag}..HEAD"
  else
    spec_range="HEAD"
  fi
  promote_stdout="$("$SCRIPT_DIR/lib/promote-specs.sh" --range "$spec_range" --status needs_review --version "$new_marketing" --build "$new_build" || true)"
  changed_count="${promote_stdout#changed=}"
  if [ "${changed_count:-0}" -gt 0 ]; then
    git add specs/.index
    if git commit -m "chore(specs): mark ${changed_count} spec(s) needs_review for build ${new_build}" >/dev/null 2>&1; then
      log "marked ${changed_count} spec(s) needs_review in specs/.index"
    else
      warn "specs/.index promotion staged but commit failed"
    fi
  fi
fi
