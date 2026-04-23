#!/usr/bin/env bash
# Read-only inventory + reconcile primitive for the `/version:adopt` flow.
#
# Walks the current repo and emits a JSON inventory matching
# ~/.claude/skills/version/presets/_adopt-contract.schema.json to stdout.
# With --pretty, also renders a human-readable per-signal table to stderr.
#
# Rules:
#   - Read-only. No git fetch, no gh auth login, no file writes.
#   - Exit 0 always. Partial state is not an error.
#   - gh failures (unauthenticated, offline) degrade gracefully: git.releases.status
#     becomes "gh_unauth" and count/missing_for_tags are null/[].
#
# Usage:
#   adopt-preflight.sh [--pretty]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./common.sh
. "$SCRIPT_DIR/common.sh"

pretty="false"
while [ $# -gt 0 ]; do
  case "$1" in
    --pretty) pretty="true"; shift ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

require_cmd jq
is_repo_root || die "not inside a git repository" 30

repo_root_path="$(repo_root)"
head_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"

origin_url=""
has_origin="false"
if origin_url="$(git remote get-url origin 2>/dev/null)"; then
  has_origin="true"
fi

# --- git tags ---
tag_list="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname 2>/dev/null || true)"
tag_count=0
latest_tag=""
latest_tag_sha=""
head_at_latest="false"
if [ -n "$tag_list" ]; then
  tag_count="$(printf '%s\n' "$tag_list" | wc -l | tr -d ' ')"
  latest_tag="$(printf '%s\n' "$tag_list" | head -1)"
  latest_tag_sha="$(git rev-parse -q --verify "refs/tags/$latest_tag^{commit}" 2>/dev/null || true)"
  if [ -n "$latest_tag_sha" ] && [ "$latest_tag_sha" = "$head_sha" ]; then
    head_at_latest="true"
  fi
fi

# --- gh releases ---
releases_status="skipped"
releases_count_json="null"
missing_for_tags_json="[]"
if [ "$has_origin" = "true" ] && command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    if release_list="$(gh release list --limit 500 2>/dev/null)"; then
      releases_status="ok"
      if [ -z "$release_list" ]; then
        releases_count_json=0
      else
        releases_count_json="$(printf '%s\n' "$release_list" | wc -l | tr -d ' ')"
      fi
      # Compute missing-for-tags: tags that exist but have no matching release.
      if [ -n "$tag_list" ]; then
        missing=""
        while IFS= read -r t; do
          [ -z "$t" ] && continue
          if ! gh release view "$t" >/dev/null 2>&1; then
            missing="${missing}${t}"$'\n'
          fi
        done <<< "$tag_list"
        if [ -n "$missing" ]; then
          missing_for_tags_json="$(printf '%s' "$missing" | jq -R -s -c 'split("\n") | map(select(length>0))')"
        fi
      fi
    else
      releases_status="gh_unauth"
    fi
  else
    releases_status="gh_unauth"
  fi
elif [ "$has_origin" != "true" ]; then
  releases_status="no_remote"
fi

# --- manifests (scan every built-in preset's sync_targets) ---
manifests_json="[]"
seen_paths=""
if [ -d "$PRESET_DIR" ]; then
  for p in "$PRESET_DIR"/*.json; do
    base="$(basename "$p" .json)"
    case "$base" in _index|_schema|_adopt-contract) continue ;; esac
    while IFS=$'\t' read -r path ptype is_primary selector; do
      [ -z "$path" ] && continue
      # Resolve {app_root} against both "." and any matching app_root prefix.
      for candidate_root in "." app app/server app/client app/backend app/frontend backend frontend src; do
        expanded="$(APP_ROOT="$candidate_root" expand_app_root "$path")"
        [ -e "$expanded" ] || continue
        case ":$seen_paths:" in *":$expanded:"*) continue ;; esac
        seen_paths="${seen_paths}:$expanded"

        # Read version per type.
        mv=""
        case "$ptype" in
          json)
            if command -v jq >/dev/null 2>&1; then
              sel="${selector:-version}"
              mv="$(jq -r --arg s "$sel" '.[$s] // empty' "$expanded" 2>/dev/null || true)"
            fi
            ;;
          toml|plain)
            if [ "$(basename "$expanded")" = "VERSION" ]; then
              mv="$(tr -d '[:space:]' < "$expanded" 2>/dev/null || true)"
              mv="${mv#v}"
            elif [ "$(basename "$expanded")" = "Cargo.toml" ] || [ "$(basename "$expanded")" = "pyproject.toml" ]; then
              mv="$(grep -E '^version[[:space:]]*=' "$expanded" 2>/dev/null | head -1 | sed -E 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/' || true)"
            fi
            ;;
          yaml)
            case "$(basename "$expanded")" in
              project.yml)
                mv="$(grep -E '^[[:space:]]*MARKETING_VERSION:' "$expanded" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || true)"
                ;;
            esac
            ;;
          gradle)
            mv="$(grep -E 'versionName[[:space:]]*[=\"]' "$expanded" 2>/dev/null | head -1 | sed -E 's/.*versionName[[:space:]]*[=]?[[:space:]]*"([^"]+)".*/\1/' || true)"
            ;;
        esac
        [ -z "$mv" ] && mv_json="null" || mv_json="$(printf '%s' "$mv" | jq -R .)"

        manifests_json="$(jq \
          --arg path "$expanded" \
          --arg type "$ptype" \
          --argjson primary "${is_primary:-false}" \
          --arg preset "$base" \
          --argjson version "$mv_json" \
          '. + [{path: $path, type: $type, version: $version, primary: $primary, preset: $preset}]' \
          <<<"$manifests_json")"
        break
      done
    done < <(jq -r '.sync_targets[]? | [.path, .type, (.primary // false), (.selector // "")] | @tsv' "$p")
  done
fi

# --- VERSION file ---
version_file_exists="false"
version_file_value_json="null"
if [ -f VERSION ]; then
  version_file_exists="true"
  v="$(tr -d '[:space:]' < VERSION 2>/dev/null || true)"
  v="${v#v}"
  [ -n "$v" ] && version_file_value_json="$(printf '%s' "$v" | jq -R .)"
fi

# --- CHANGELOG ---
changelog_exists="false"
changelog_path_json="null"
changelog_format="none"
changelog_entry_count_json="null"
if [ -f CHANGELOG.md ]; then
  changelog_exists="true"
  changelog_path_json='"CHANGELOG.md"'
  first_line="$(head -1 CHANGELOG.md 2>/dev/null || true)"
  # Look for our seed signature (inserted by changelog.sh).
  if grep -qE '^_Changes since' CHANGELOG.md 2>/dev/null; then
    changelog_format="managed"
  elif grep -qE '^## \[(Unreleased|[0-9]+\.[0-9]+\.[0-9]+)\]' CHANGELOG.md 2>/dev/null; then
    changelog_format="keep-a-changelog"
  elif grep -qE '^## \[?v?[0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md 2>/dev/null; then
    changelog_format="conventional"
  else
    changelog_format="unknown"
  fi
  ec="$(grep -cE '^## \[?v?[0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md 2>/dev/null || echo 0)"
  changelog_entry_count_json="$ec"
fi

# --- .version-preset state ---
preset_state_json="absent"
preset_name_json="null"
preset_mode_json="null"
preset_detected_json="null"
preset_app_root_json="null"
preset_app_root_val="."
if [ -f .version-preset ]; then
  preset_state_json="present"
  state_out="$(preset_state 2>/dev/null || true)"
  pn="$(printf '%s\n' "$state_out" | awk -F= '/^NAME=/ {print $2}')"
  pm="$(printf '%s\n' "$state_out" | awk -F= '/^MODE=/ {print $2}')"
  pd="$(printf '%s\n' "$state_out" | awk -F= '/^DETECTED=/ {print $2}')"
  pa="$(printf '%s\n' "$state_out" | awk -F= '/^APP_ROOT=/ {print $2}')"
  [ -n "$pn" ] && preset_name_json="$(printf '%s' "$pn" | jq -R .)"
  [ -n "$pm" ] && preset_mode_json="$(printf '%s' "$pm" | jq -R .)"
  [ -n "$pd" ] && preset_detected_json="$(printf '%s' "$pd" | jq -R .)"
  if [ -n "$pa" ]; then
    preset_app_root_json="$(printf '%s' "$pa" | jq -R .)"
    preset_app_root_val="$pa"
  fi
fi

# --- detected tool ---
detected_tool=""
if [ -x "$SCRIPT_DIR/existing-ci-detect.sh" ]; then
  detected_tool="$("$SCRIPT_DIR/existing-ci-detect.sh" 2>/dev/null || true)"
fi

# --- resolved version with provenance ---
rv_line="$(resolve_version_with_provenance)"
rv_value="${rv_line%%$'\t'*}"
rv_source="${rv_line##*$'\t'}"

# --- drift: manifests whose version differs from resolved ---
drift_json="[]"
if [ -n "$rv_value" ]; then
  drift_json="$(jq --arg rv "$rv_value" '
    [ .[] | select(.version != null and .version != $rv)
    | {path: .path, manifest_version: .version, resolved_version: $rv} ]
  ' <<<"$manifests_json")"
fi

# --- partial?: any signal present ---
partial="false"
if [ "$tag_count" -gt 0 ] \
   || [ "$preset_state_json" = "present" ] \
   || ([ "$changelog_exists" = "true" ] && [ "$changelog_format" != "managed" ]) \
   || [ -n "$detected_tool" ]; then
  partial="true"
fi

# --- assemble JSON ---
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
out="$(jq -n \
  --arg schema_version "v1" \
  --arg now "$now" \
  --arg root "$repo_root_path" \
  --argjson has_origin "$has_origin" \
  --arg origin_url "$origin_url" \
  --arg head_sha "$head_sha" \
  --argjson tag_count "$tag_count" \
  --arg latest_tag "$latest_tag" \
  --arg latest_tag_sha "$latest_tag_sha" \
  --argjson head_at_latest "$head_at_latest" \
  --arg releases_status "$releases_status" \
  --argjson releases_count "$releases_count_json" \
  --argjson missing_for_tags "$missing_for_tags_json" \
  --argjson manifests "$manifests_json" \
  --argjson version_file_exists "$version_file_exists" \
  --argjson version_file_value "$version_file_value_json" \
  --argjson changelog_exists "$changelog_exists" \
  --argjson changelog_path "$changelog_path_json" \
  --arg changelog_format "$changelog_format" \
  --argjson changelog_entry_count "$changelog_entry_count_json" \
  --arg preset_state "$preset_state_json" \
  --argjson preset_name "$preset_name_json" \
  --argjson preset_mode "$preset_mode_json" \
  --argjson preset_detected "$preset_detected_json" \
  --argjson preset_app_root "$preset_app_root_json" \
  --arg detected_tool "$detected_tool" \
  --arg app_root "$preset_app_root_val" \
  --arg rv_value "$rv_value" \
  --arg rv_source "$rv_source" \
  --argjson drift "$drift_json" \
  --argjson partial "$partial" \
  '{
    schema_version: $schema_version,
    generated_at: $now,
    repo: {
      root: $root,
      has_origin: $has_origin,
      origin_url: (if ($origin_url|length)>0 then $origin_url else null end)
    },
    git: {
      head_sha: $head_sha,
      tags: {
        count: $tag_count,
        latest: (if ($latest_tag|length)>0 then $latest_tag else null end),
        latest_sha: (if ($latest_tag_sha|length)>0 then $latest_tag_sha else null end),
        head_at_latest: $head_at_latest
      },
      releases: {
        status: $releases_status,
        count: $releases_count,
        missing_for_tags: $missing_for_tags
      }
    },
    manifests: $manifests,
    version_file: {
      exists: $version_file_exists,
      value: $version_file_value
    },
    changelog: {
      exists: $changelog_exists,
      path: $changelog_path,
      format: $changelog_format,
      entry_count: $changelog_entry_count
    },
    preset: {
      state: $preset_state,
      name: $preset_name,
      mode: $preset_mode,
      detected: $preset_detected,
      app_root: $preset_app_root
    },
    detected_tool: $detected_tool,
    app_root: $app_root,
    resolved_version: { value: $rv_value, source: $rv_source },
    partial: $partial,
    drift: $drift
  }')"

printf '%s\n' "$out"

# --- pretty table on stderr ---
if [ "$pretty" = "true" ]; then
  {
    printf '\n'
    printf '  Adopt preflight for %s\n' "$repo_root_path"
    printf '  ----------------------------------------------------\n'
    printf '  %-22s %s\n' "Resolved version:" "$rv_value (source: $rv_source)"
    printf '  %-22s %s\n' "Git tags:" "${tag_count} total${latest_tag:+, latest $latest_tag}"
    if [ "$releases_status" = "ok" ]; then
      missing_n="$(jq 'length' <<<"$missing_for_tags_json")"
      printf '  %-22s %s\n' "GitHub releases:" "${releases_count_json} total, ${missing_n} tags missing releases"
    else
      printf '  %-22s %s\n' "GitHub releases:" "(unavailable: $releases_status)"
    fi
    printf '  %-22s %s\n' "VERSION file:" "$(if [ "$version_file_exists" = "true" ]; then printf 'yes (%s)' "${version_file_value_json//\"/}"; else printf 'absent'; fi)"
    printf '  %-22s %s\n' "CHANGELOG.md:" "$(if [ "$changelog_exists" = "true" ]; then printf '%s' "$changelog_format"; else printf 'absent'; fi)"
    printf '  %-22s %s\n' "Preset state:" "$preset_state_json${pn:+ ($pn:$pm)}"
    printf '  %-22s %s\n' "Detected tool:" "${detected_tool:-<none>}"
    printf '  %-22s %s\n' "App root:" "$preset_app_root_val"
    m_count="$(jq 'length' <<<"$manifests_json")"
    d_count="$(jq 'length' <<<"$drift_json")"
    printf '  %-22s %s\n' "Manifests found:" "$m_count (${d_count} drift)"
    if [ "$d_count" -gt 0 ]; then
      while IFS=$'\t' read -r dp mv rv; do
        printf '    drift: %s=%s (resolved=%s)\n' "$dp" "$mv" "$rv"
      done < <(jq -r '.[] | [.path, .manifest_version, .resolved_version] | @tsv' <<<"$drift_json")
    fi
    printf '  %-22s %s\n' "Partial state:" "$(if [ "$partial" = "true" ]; then printf 'YES'; else printf 'no'; fi)"
    printf '\n'
  } >&2
fi

exit 0
