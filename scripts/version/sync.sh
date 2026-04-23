#!/usr/bin/env bash
# Sync all manifests listed in a preset to a given version. Does not commit or tag.
# Usage: sync.sh <preset-name> <version>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

[ $# -eq 2 ] || die "usage: sync.sh <preset-name> <version>"
preset_name="$1"
version="${2#v}"

require_cmd jq
parse_semver "$version"

# Ensure manifest.sh can expand {app_root} in paths.
load_app_root

preset_json="$(load_preset "$preset_name")"
targets_count="$(jq -r '.sync_targets | length' <<<"$preset_json")"
[ "$targets_count" -ge 1 ] || die "preset '$preset_name' has no sync_targets" 10

log "syncing $targets_count target(s) to version $version"
for i in $(seq 0 $((targets_count - 1))); do
  target="$(jq -c ".sync_targets[$i]" <<<"$preset_json")"
  "$SCRIPT_DIR/lib/manifest.sh" apply "$target" "$version"
done

log "sync complete"
