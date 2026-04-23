#!/usr/bin/env bash
# Shared helpers for scripts/version/*.sh
# Source, do not execute.

set -euo pipefail

VERSION_SKILL_ROOT="${VERSION_SKILL_ROOT:-$HOME/.claude/skills/version}"
VERSION_SCRIPTS_ROOT="${VERSION_SCRIPTS_ROOT:-$HOME/.claude/scripts/version}"
PRESET_DIR="$VERSION_SKILL_ROOT/presets"

log()  { printf '[version] %s\n' "$*" >&2; }
warn() { printf '[version] WARN: %s\n' "$*" >&2; }
die()  { printf '[version] ERROR: %s\n' "$*" >&2; exit "${2:-1}"; }
dbg()  { [ "${VERSION_SKILL_DEBUG:-0}" = "1" ] && printf '[version] DEBUG: %s\n' "$*" >&2 || true; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1" 11
}

is_repo_root() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

repo_root() {
  git rev-parse --show-toplevel
}

# Parse semver X.Y.Z (ignores leading v). Sets globals VER_MAJOR, VER_MINOR, VER_PATCH.
parse_semver() {
  local v="${1#v}"
  if ! printf '%s' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+].*)?$'; then
    die "invalid semver: $1"
  fi
  local core="${v%%[-+]*}"
  VER_MAJOR="${core%%.*}"
  local rest="${core#*.}"
  VER_MINOR="${rest%%.*}"
  VER_PATCH="${rest#*.}"
}

# Print current version plus provenance on a single tab-separated line:
#   <version><TAB><source>        where source ∈ {tag, version_file, manifest, fallback}
# Resolution order: git tag, VERSION file, primary manifest, 0.1.0 fallback.
resolve_version_with_provenance() {
  local tag
  tag=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname 2>/dev/null | head -1 || true)
  if [ -n "$tag" ]; then
    printf '%s\ttag\n' "${tag#v}"
    return 0
  fi
  if [ -f VERSION ]; then
    local v
    v=$(tr -d '[:space:]' < VERSION || true)
    if [ -n "$v" ]; then
      printf '%s\tversion_file\n' "${v#v}"
      return 0
    fi
  fi
  # Try common primary manifests, respecting APP_ROOT when set.
  local root="${APP_ROOT:-.}"
  [ "$root" = "." ] && root=""
  local pj="${root:+$root/}package.json"
  local ct="${root:+$root/}Cargo.toml"
  local pp="${root:+$root/}pyproject.toml"

  if [ -f "$pj" ] && command -v jq >/dev/null 2>&1; then
    local v
    v=$(jq -r '.version // empty' "$pj" 2>/dev/null || true)
    [ -n "$v" ] && { printf '%s\tmanifest\n' "$v"; return 0; }
  fi
  if [ -f "$ct" ]; then
    local v
    v=$(grep -E '^version[[:space:]]*=' "$ct" | head -1 | sed -E 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')
    [ -n "$v" ] && { printf '%s\tmanifest\n' "$v"; return 0; }
  fi
  if [ -f "$pp" ]; then
    local v
    v=$(grep -E '^version[[:space:]]*=' "$pp" | head -1 | sed -E 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')
    [ -n "$v" ] && { printf '%s\tmanifest\n' "$v"; return 0; }
  fi
  printf '0.1.0\tfallback\n'
}

# Backwards-compatible wrapper: print only the version column.
resolve_current_version() {
  resolve_version_with_provenance | awk -F'\t' '{print $1}'
}

bump_version() {
  local current="$1" kind="$2"
  case "$kind" in
    patch|minor|major)
      parse_semver "$current"
      case "$kind" in
        patch) VER_PATCH=$((VER_PATCH + 1)) ;;
        minor) VER_MINOR=$((VER_MINOR + 1)); VER_PATCH=0 ;;
        major) VER_MAJOR=$((VER_MAJOR + 1)); VER_MINOR=0; VER_PATCH=0 ;;
      esac
      printf '%s.%s.%s\n' "$VER_MAJOR" "$VER_MINOR" "$VER_PATCH"
      ;;
    *)
      parse_semver "$kind"
      printf '%s\n' "${kind#v}"
      ;;
  esac
}

preset_path() {
  local name="$1"
  local local_path="scripts/version/presets/${name}.json"
  if [ -f "$local_path" ]; then
    printf '%s\n' "$local_path"
    return 0
  fi
  printf '%s/%s.json\n' "$PRESET_DIR" "$name"
}

preset_exists() {
  [ -f "$(preset_path "$1")" ]
}

load_preset() {
  local name="$1"
  local path
  path="$(preset_path "$name")"
  [ -f "$path" ] || die "preset not found: $name ($path)" 10
  require_cmd jq
  jq '.' "$path"
}

# Read .version-preset and return its fields.
# Format: "name" (legacy) or "name:mode[:detected][:app_root]".
# app_root is "." when the manifest lives at repo root (default if absent).
# Emits `NAME=... MODE=... DETECTED=... APP_ROOT=...` on stdout.
preset_state() {
  [ -f .version-preset ] || { printf 'NAME=\nMODE=\nDETECTED=\nAPP_ROOT=.\n'; return; }
  local raw name mode detected app_root
  raw="$(tr -d '[:space:]' < .version-preset)"

  # Split on colons into up to 4 fields.
  IFS=: read -r name mode detected app_root <<<"$raw"
  : "${mode:=}"
  : "${detected:=}"
  : "${app_root:=.}"

  # Fill missing mode from preset JSON if available (legacy single-name files).
  if [ -z "$mode" ] && preset_exists "$name"; then
    mode="$(jq -r '.mode // "manual"' "$(preset_path "$name")")"
  fi
  printf 'NAME=%s\nMODE=%s\nDETECTED=%s\nAPP_ROOT=%s\n' "$name" "$mode" "$detected" "$app_root"
}

# Locate the directory that contains the given relative path `suffix`.
# Tries: repo root, then the common `app/` variants, then any top-level
# subdirectory (handles iOS-style named project folders). Returns "." when
# the file is at the repo root; returns empty string if not found.
#
# Examples:
#   resolve_app_root "package.json"             -> "." | "app" | "app/server"
#   resolve_app_root "client/package.json"      -> "." | "app"
#   resolve_app_root "project.yml"              -> "." | "IdleSodaPopEmpire" | ...
resolve_app_root() {
  local suffix="$1" prefix test_path
  local prefixes=("" "app" "app/server" "app/client" "app/backend" "app/frontend" "backend" "frontend" "src")
  for prefix in "${prefixes[@]}"; do
    test_path="${prefix:+$prefix/}$suffix"
    if [ -e "$test_path" ]; then
      [ -z "$prefix" ] && printf '.\n' || printf '%s\n' "$prefix"
      return 0
    fi
  done
  # Fallback for iOS-style named folders: scan top-level dirs when suffix is
  # a simple filename (no slash).
  if [ "$(basename "$suffix")" = "$suffix" ]; then
    local d
    for d in */; do
      d="${d%/}"
      case "$d" in
        .git|node_modules|Pods|DerivedData|build|dist|_*) continue ;;
      esac
      [ -e "$d/$suffix" ] && { printf '%s\n' "$d"; return 0; }
    done
  fi
  return 1
}

# Expand {app_root} in a path. With APP_ROOT="." or empty, strips the
# "{app_root}/" prefix entirely so paths normalize to "package.json"
# rather than "./package.json".
expand_app_root() {
  local path="$1" root="${APP_ROOT:-.}"
  case "$path" in
    *\{app_root\}*) ;;
    *) printf '%s\n' "$path"; return 0 ;;
  esac
  if [ "$root" = "." ] || [ -z "$root" ]; then
    printf '%s\n' "${path//\{app_root\}\//}"
  else
    printf '%s\n' "${path//\{app_root\}/$root}"
  fi
}

# Export APP_ROOT from .version-preset for downstream scripts (sync.sh,
# bump.sh, manifest.sh). No-op when APP_ROOT is already set.
load_app_root() {
  [ -n "${APP_ROOT:-}" ] && return 0
  local state
  state="$(preset_state 2>/dev/null || true)"
  APP_ROOT="$(printf '%s\n' "$state" | awk -F= '/^APP_ROOT=/ {print $2}')"
  [ -z "$APP_ROOT" ] && APP_ROOT="."
  export APP_ROOT
}

preset_mode() {
  local state mode
  state="$(preset_state)"
  mode="$(printf '%s\n' "$state" | awk -F= '/^MODE=/ {print $2}')"
  printf '%s\n' "${mode:-manual}"
}

is_apple_mode() {
  case "$(preset_mode)" in
    apple-commit-driven|apple-strict-semver) return 0 ;;
    *) return 1 ;;
  esac
}

require_apple_platform() {
  case "$1" in
    IOS|MAC_OS|TV_OS|VISION_OS|WATCH_OS) return 0 ;;
    *) die "invalid Apple platform: $1 (use IOS, MAC_OS, TV_OS, VISION_OS, WATCH_OS)" ;;
  esac
}
