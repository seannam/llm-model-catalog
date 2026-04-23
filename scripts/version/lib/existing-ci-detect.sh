#!/usr/bin/env bash
# Detect an already-installed version/release tool in the current repo.
# Emits the tool name on stdout, or nothing if none detected.
#
# Usage: existing-ci-detect.sh
#
# Recognized tools (first match wins):
#   release-please   - release-please-config.json OR .release-please-manifest.json
#                      OR any workflow using googleapis/release-please-action
#   semantic-release - .releaserc, .releaserc.json, .releaserc.yml, .releaserc.yaml,
#                      OR release.config.js OR devDependency on semantic-release
#   changesets       - .changeset/ directory
#   git-cliff        - cliff.toml
#   custom-release   - any .github/workflows/release*.yml not matching the above
#                      (catches hand-rolled scripts like ios_portfolio_manager's)

set -euo pipefail

is_file() { [ -f "$1" ]; }
is_dir()  { [ -d "$1" ]; }

# 1. release-please (strongest signals first)
if is_file release-please-config.json \
   || is_file .release-please-manifest.json; then
  printf 'release-please\n'; exit 0
fi
if ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null \
     | xargs grep -l 'googleapis/release-please-action' 2>/dev/null \
     | head -1 | grep -q .; then
  printf 'release-please\n'; exit 0
fi

# 2. semantic-release
for f in .releaserc .releaserc.json .releaserc.yml .releaserc.yaml release.config.js release.config.cjs release.config.mjs; do
  if is_file "$f"; then printf 'semantic-release\n'; exit 0; fi
done
if is_file package.json && grep -q '"semantic-release"' package.json 2>/dev/null; then
  printf 'semantic-release\n'; exit 0
fi

# 3. changesets
if is_dir .changeset; then
  printf 'changesets\n'; exit 0
fi

# 4. git-cliff
if is_file cliff.toml; then
  printf 'git-cliff\n'; exit 0
fi

# 5. hand-rolled release workflow (anything that looks release-ish we didn't own)
for w in .github/workflows/release.yml \
         .github/workflows/release.yaml \
         .github/workflows/auto-release.yml \
         .github/workflows/auto-release-on-push.yml; do
  [ -f "$w" ] || continue
  # Skip if it's OUR template (we'll overwrite our own safely during re-install).
  if grep -q 'scripts/version/lib/commit-bump.sh' "$w" 2>/dev/null; then
    continue
  fi
  printf 'custom-release\n'; exit 0
done

# 6. Nothing detected.
exit 0
