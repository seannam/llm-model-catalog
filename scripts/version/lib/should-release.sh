#!/usr/bin/env bash
# Gate: exit 0 if the commit range contains anything that should cut a release,
# exit 1 otherwise. Thin wrapper over commit-bump.sh for use in CI `if:` steps.
#
# Usage: should-release.sh <range> [--strict-semver]
#   Same arguments as commit-bump.sh.
#
# Example (in GitHub Actions):
#   - run: ./scripts/version/lib/should-release.sh "$LAST_TAG..HEAD" --strict-semver
#     # next steps gated by the exit code

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

result="$("$SCRIPT_DIR/commit-bump.sh" "$@")"
[ "$result" != "none" ]
