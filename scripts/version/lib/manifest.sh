#!/usr/bin/env bash
# Apply a single sync_target entry from a preset to a file.
# Usage: manifest.sh apply <target-json> <version>
#   target-json: one sync_targets[] object (stringified JSON), read from the preset.
#   version:     semver string to write.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

cmd="${1:-}"; shift || true
case "$cmd" in
  apply)
    target_json="$1"
    version="$2"
    ;;
  *)
    die "usage: manifest.sh apply <target-json> <version>"
    ;;
esac

require_cmd jq

path="$(jq -r '.path' <<<"$target_json")"
type="$(jq -r '.type' <<<"$target_json")"
optional="$(jq -r '.optional // false' <<<"$target_json")"

# Expand {app_root} placeholder against APP_ROOT (set by apply-preset.sh
# or loaded from .version-preset via load_app_root). Paths without the
# placeholder pass through unchanged.
path="$(expand_app_root "$path")"

# Template expansion for paths like {version}, {major}, {minor}, {patch}
parse_semver "$version"
expand_template() {
  printf '%s' "$1" \
    | sed -e "s/{version}/$version/g" \
          -e "s/{major}/$VER_MAJOR/g" \
          -e "s/{minor}/$VER_MINOR/g" \
          -e "s/{patch}/$VER_PATCH/g"
}

if [ ! -e "$path" ] && [ "$optional" = "true" ]; then
  dbg "skipping optional missing target: $path"
  exit 0
fi

case "$type" in
  json)
    require_cmd jq
    [ -f "$path" ] || die "manifest missing: $path" 12
    selector="$(jq -r '.selector' <<<"$target_json")"
    tmp="$(mktemp)"
    jq ".$selector = \"$version\"" "$path" > "$tmp"
    mv "$tmp" "$path"
    log "synced $path ($selector = $version)"
    ;;
  toml)
    [ -f "$path" ] || die "manifest missing: $path" 12
    selector="$(jq -r '.selector' <<<"$target_json")"
    # Match only a top-level or table-scoped version line. This handles the common
    # case: "version = \"...\"" inside the relevant table. For nested keys the
    # caller should prefer the `native` type and use the stack's own tool.
    field="${selector##*.}"
    tmp="$(mktemp)"
    # Replace first occurrence of `^<field> = "..."` in the file.
    awk -v f="$field" -v v="$version" '
      BEGIN { done = 0 }
      /^[[:space:]]*[a-zA-Z0-9_-]+[[:space:]]*=/ && !done {
        split($0, parts, "=")
        key = parts[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        if (key == f) {
          print f " = \"" v "\""
          done = 1
          next
        }
      }
      { print }
    ' "$path" > "$tmp"
    mv "$tmp" "$path"
    log "synced $path ($selector = $version)"
    ;;
  yaml)
    [ -f "$path" ] || die "manifest missing: $path" 12
    selector="$(jq -r '.selector' <<<"$target_json")"
    # Use yq if present, else fall back to regex replace of a top-level key.
    if command -v yq >/dev/null 2>&1; then
      yq -i ".$selector = \"$version\"" "$path"
    else
      field="${selector##*.}"
      tmp="$(mktemp)"
      sed -E "s/^([[:space:]]*${field}:[[:space:]]*).*/\1\"${version}\"/" "$path" > "$tmp"
      mv "$tmp" "$path"
    fi
    log "synced $path ($selector = $version)"
    ;;
  plain)
    printf '%s\n' "$version" > "$path"
    log "wrote $path = $version"
    ;;
  regex)
    [ -f "$path" ] || die "manifest missing: $path" 12
    pattern="$(jq -r '.pattern' <<<"$target_json")"
    replacement="$(jq -r '.replacement' <<<"$target_json")"
    replacement="$(expand_template "$replacement")"
    tmp="$(mktemp)"
    # Use perl for reliable regex replace with special chars.
    if command -v perl >/dev/null 2>&1; then
      perl -pe "s{$pattern}{$replacement}g" "$path" > "$tmp"
    else
      sed -E "s|$pattern|$replacement|g" "$path" > "$tmp"
    fi
    mv "$tmp" "$path"
    log "regex-synced $path"
    ;;
  xcconfig)
    [ -f "$path" ] || die "manifest missing: $path" 12
    tmp="$(mktemp)"
    sed -E "s/^(MARKETING_VERSION[[:space:]]*=[[:space:]]*).*/\1${version}/" "$path" > "$tmp"
    mv "$tmp" "$path"
    log "synced $path (MARKETING_VERSION = $version)"
    ;;
  plist)
    [ -f "$path" ] || die "manifest missing: $path" 12
    if command -v plutil >/dev/null 2>&1; then
      plutil -replace CFBundleShortVersionString -string "$version" "$path"
      log "synced $path (CFBundleShortVersionString = $version)"
    else
      die "plutil required for plist sync (macOS)" 11
    fi
    ;;
  gradle)
    [ -f "$path" ] || die "manifest missing: $path" 12
    tmp="$(mktemp)"
    sed -E "s/(versionName[[:space:]]*[=[:space:]]*)\"[^\"]*\"/\1\"${version}\"/" "$path" > "$tmp"
    mv "$tmp" "$path"
    log "synced $path (versionName = $version)"
    ;;
  native)
    command_str="$(jq -r '.command' <<<"$target_json")"
    expanded="$(expand_template "$command_str")"
    dbg "running native command: $expanded"
    # Intentionally use `eval` so quoted subcommands in the preset work as expected.
    eval "$expanded"
    log "native synced via: $expanded"
    ;;
  *)
    die "unknown sync target type: $type" 12
    ;;
esac
