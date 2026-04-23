#!/usr/bin/env bash
# Bump the version for the current repo. Dispatches by preset mode:
#
#   auto               -> print informational hint; require --force to actually
#                          bump locally (CI owns releases).
#   apple-commit-driven
#   apple-strict-semver -> delegate to apple-bump.sh.
#   manual              -> classic flow: sync manifests, changelog, commit,
#                          tag, push, release.
#   existing            -> refuse; point at the detected tool.
#
# Usage:
#   bump.sh [patch|minor|major|X.Y.Z] [--preset NAME] [--prerelease]
#           [--no-release] [--no-commit] [--force]
#
# --force: in auto mode, run the manual flow locally anyway.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

kind=""           # empty = not explicitly specified (Apple modes will infer from commits)
preset=""
prerelease="false"
do_release="true"
do_commit="true"
force="false"

while [ $# -gt 0 ]; do
  case "$1" in
    patch|minor|major) kind="$1"; shift ;;
    --preset) preset="$2"; shift 2 ;;
    --prerelease) prerelease="true"; shift ;;
    --no-release) do_release="false"; shift ;;
    --no-commit) do_commit="false"; shift ;;
    --force) force="true"; shift ;;
    -h|--help)
      echo "usage: bump.sh [patch|minor|major|X.Y.Z] [--preset NAME] [--prerelease] [--no-release] [--no-commit] [--force]"
      exit 0
      ;;
    *)
      if printf '%s' "$1" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+([-+].*)?$'; then
        kind="${1#v}"
      else
        die "unknown arg: $1"
      fi
      shift
      ;;
  esac
done

is_repo_root || die "not inside a git repository" 30
require_cmd jq
require_cmd git

# Resolve preset + mode.
if [ -z "$preset" ]; then
  state="$(preset_state)"
  preset="$(printf '%s\n' "$state" | awk -F= '/^NAME=/ {print $2}')"
fi
if [ -z "$preset" ]; then
  if [ -f .version-preset ]; then
    preset="$(tr -d '[:space:]' < .version-preset | cut -d: -f1)"
  else
    preset="$("$SCRIPT_DIR/detect-preset.sh" --first 2>/dev/null || true)"
  fi
fi
[ -n "$preset" ] || die "could not determine preset. Pass --preset <name> or run /version:install." 10
preset_exists "$preset" || die "preset not found: $preset" 10

mode="$(preset_mode)"
if [ -z "$mode" ] || [ "$mode" = "manual" ]; then
  # Fall back to preset's declared mode if .version-preset didn't track it.
  mode="$(jq -r '.mode // "manual"' "$(preset_path "$preset")")"
fi

# === Dispatch by mode ===
case "$mode" in

  existing)
    detected="$(printf '%s\n' "$(preset_state)" | awk -F= '/^DETECTED=/ {print $2}')"
    die "this repo uses ${detected:-an existing release tool}. bump.sh will not run. Use that tool's workflow instead, or re-run /version:install --force to take over." 10
    ;;

  auto)
    if [ "$force" != "true" ]; then
      log "this repo auto-releases on push to main via CI."
      log "commit with a conventional prefix (feat:/fix:/feat!) and push."
      log "to force a local bump anyway, pass --force."
      exit 0
    fi
    log "--force: running local bump (CI workflow will be skipped via loop guard)"
    # Fall through to manual flow.
    ;;

  apple-commit-driven|apple-strict-semver)
    args=()
    [ "$mode" = "apple-strict-semver" ] && args+=( --strict-semver )
    # Only pass a marketing override if the user explicitly specified a kind.
    # Otherwise let apple-bump.sh decide from conventional commits.
    case "$kind" in
      "") : ;;  # no override - commit-driven
      major|minor|patch) args+=( --marketing-bump "$kind" ) ;;
      *)
        if printf '%s' "$kind" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
          args+=( --marketing "$kind" )
        fi
        ;;
    esac
    exec "$SCRIPT_DIR/apple-bump.sh" "${args[@]+"${args[@]}"}"
    ;;

  manual|*)
    : # fall through to manual flow below
    ;;
esac

# === Manual / --force flow ===

# Default to patch when the user didn't specify a kind for the manual flow.
[ -z "$kind" ] && kind="patch"

# Honor APP_ROOT stored in .version-preset (manifests may live in app/, etc.).
load_app_root

current="$(resolve_current_version)"
next="$(bump_version "$current" "$kind")"
log "bumping $current -> $next (preset: $preset, mode: $mode)"

"$SCRIPT_DIR/sync.sh" "$preset" "$next"
"$SCRIPT_DIR/changelog.sh" --version "$next" --append --output CHANGELOG.md

if [ "$do_commit" = "true" ]; then
  staged_paths=()
  while IFS= read -r line; do
    staged_paths+=("$(expand_app_root "$line")")
  done < <(jq -r '.sync_targets[].path' "$(preset_path "$preset")")
  staged_paths+=("CHANGELOG.md")

  for p in "${staged_paths[@]}"; do
    [ -e "$p" ] && git add -- "$p" || true
  done

  if git diff --cached --quiet; then
    warn "no staged changes; skipping commit"
  else
    git commit -m "chore(release): v$next"
    log "committed bump to $next"
  fi
fi

if [ "$do_release" = "true" ]; then
  if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    git push origin HEAD || die "failed to push HEAD" 20
  else
    warn "no upstream set; skipping pre-release push"
  fi
  release_args=( cut --version "$next" )
  [ "$prerelease" = "true" ] && release_args+=( --prerelease )
  "$SCRIPT_DIR/release.sh" "${release_args[@]}"
fi

log "bump complete: $next"
