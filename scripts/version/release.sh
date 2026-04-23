#!/usr/bin/env bash
# The reusable GitHub portion of the version skill.
# Creates a git tag at HEAD, pushes it, and creates a matching GitHub release.
# This script is the ONLY place that talks to git-remote and `gh`. Every preset
# and every helper routes tag/release through here so the logic lives in one file.
#
# Usage:
#   release.sh seed     --version X.Y.Z [--prerelease] [--notes PATH|-] [--title STR]
#   release.sh cut      --version X.Y.Z [--prerelease] [--notes PATH|-] [--title STR]
#   release.sh backfill [--dry-run] [--exclude-pattern PAT]
#
# Modes:
#   seed      Create the initial tag+release for an existing version (no bump commit).
#   cut       Create a tag+release after a bump commit. Same mechanics, different intent
#             (callers using "cut" have already made a bump commit that HEAD points at).
#   backfill  Walk existing vX.Y.Z tags and create missing GitHub releases from
#             auto-generated notes. Idempotent. Does not promote specs (see Notes).
#
# Notes source priority:
#   --notes <path>   read file
#   --notes -        read stdin
#   (neither)        auto-generate from changelog.sh for the range since the previous tag

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

mode="${1:-}"; shift || true
case "$mode" in
  seed|cut|backfill) ;;
  *) die "usage: release.sh seed|cut|backfill [...]" ;;
esac

# --- backfill subcommand: create missing GitHub releases for existing tags ---
if [ "$mode" = "backfill" ]; then
  dry_run="false"
  exclude_pattern=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run="true"; shift ;;
      --exclude-pattern) exclude_pattern="$2"; shift 2 ;;
      *) die "unknown arg: $1" ;;
    esac
  done

  require_cmd git
  require_cmd gh
  is_repo_root || die "not inside a git repository" 30
  git remote get-url origin >/dev/null 2>&1 || die "no 'origin' remote configured" 30

  backfilled=0
  skipped=0
  total=0
  warnings=0

  # Walk stable vX.Y.Z tags in version order.
  while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    total=$((total + 1))
    if [ -n "$exclude_pattern" ]; then
      case "$tag" in
        $exclude_pattern) skipped=$((skipped + 1)); continue ;;
      esac
    fi

    # Skip if the tag does not point at a reachable commit from any branch.
    tag_sha="$(git rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null || true)"
    if [ -z "$tag_sha" ]; then
      warn "tag $tag does not resolve to a commit; skipping"
      warnings=$((warnings + 1))
      skipped=$((skipped + 1))
      continue
    fi

    if gh release view "$tag" >/dev/null 2>&1; then
      skipped=$((skipped + 1))
      dbg "release exists for $tag; skipping"
      continue
    fi

    # Decide prerelease from suffix.
    prerelease_flag=()
    case "$tag" in
      *-rc*|*-beta*|*-alpha*) prerelease_flag=( --prerelease ) ;;
    esac

    if [ "$dry_run" = "true" ]; then
      log "DRY-RUN: would create release for $tag"
      backfilled=$((backfilled + 1))
      continue
    fi

    # Warn if tag is local-only (not on origin) rather than pushing it.
    remote_sha="$(git ls-remote --tags origin "refs/tags/$tag" 2>/dev/null | awk '{print $1}' || true)"
    if [ -z "$remote_sha" ]; then
      warn "tag $tag exists locally but not on origin; suggest 'git push origin $tag' before creating release"
      warnings=$((warnings + 1))
      skipped=$((skipped + 1))
      continue
    fi

    log "creating GitHub release for $tag"
    if gh release create "$tag" --generate-notes --title "$tag" "${prerelease_flag[@]}" >/dev/null 2>&1; then
      backfilled=$((backfilled + 1))
    else
      warn "gh release create failed for $tag; continuing"
      warnings=$((warnings + 1))
      skipped=$((skipped + 1))
    fi
  done < <(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=version:refname 2>/dev/null || true)

  log "backfill summary: backfilled=$backfilled skipped=$skipped total=$total warnings=$warnings"
  printf 'backfilled=%d skipped=%d total=%d warnings=%d\n' "$backfilled" "$skipped" "$total" "$warnings"
  exit 0
fi

version=""
prerelease="false"
notes_src=""
title=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version) version="${2#v}"; shift 2 ;;
    --prerelease) prerelease="true"; shift ;;
    --notes) notes_src="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[ -n "$version" ] || die "--version is required"
parse_semver "$version"
require_cmd git
require_cmd gh

is_repo_root || die "not inside a git repository" 30

tag="v${version}"
[ -n "$title" ] || title="$tag"

# Verify we can see origin.
git remote get-url origin >/dev/null 2>&1 || die "no 'origin' remote configured" 30

# Fetch tags so we can detect collisions with remote-only tags.
git fetch --tags origin 2>/dev/null || warn "git fetch --tags origin failed; continuing"

# Idempotency guard: if the tag exists locally or remotely, verify it points at HEAD.
head_sha="$(git rev-parse HEAD)"
existing_local="$(git rev-parse -q --verify "refs/tags/$tag" 2>/dev/null || true)"
existing_remote="$(git ls-remote --tags origin "refs/tags/$tag" 2>/dev/null | awk '{print $1}' || true)"

if [ -n "$existing_local" ] && [ "$existing_local" != "$head_sha" ]; then
  die "tag $tag already exists locally at $existing_local (HEAD is $head_sha). Refusing to retarget." 20
fi
if [ -n "$existing_remote" ] && [ "$existing_remote" != "$head_sha" ]; then
  die "tag $tag already exists on origin at $existing_remote (HEAD is $head_sha). Refusing to retarget." 20
fi

# Resolve notes.
notes_file="$(mktemp)"
trap 'rm -f "$notes_file"' EXIT

if [ -z "$notes_src" ]; then
  log "auto-generating notes from conventional commits"
  "$SCRIPT_DIR/changelog.sh" --version "$version" --output "$notes_file"
elif [ "$notes_src" = "-" ]; then
  cat > "$notes_file"
else
  [ -f "$notes_src" ] || die "--notes file not found: $notes_src"
  cp "$notes_src" "$notes_file"
fi

# Make tag locally if not already there.
if [ -z "$existing_local" ]; then
  log "creating tag $tag at $head_sha"
  git tag -a "$tag" -F "$notes_file" "$head_sha"
fi

# Push tag.
if [ -z "$existing_remote" ]; then
  log "pushing tag $tag to origin"
  git push origin "$tag" || die "failed to push tag to origin" 20
else
  dbg "tag already present on origin; skipping push"
fi

# Create or update the GitHub release.
release_flags=( --title "$title" --notes-file "$notes_file" )
[ "$prerelease" = "true" ] && release_flags+=( --prerelease )

if gh release view "$tag" >/dev/null 2>&1; then
  log "updating existing GitHub release $tag"
  gh release edit "$tag" "${release_flags[@]}" || die "gh release edit failed" 21
else
  log "creating GitHub release $tag"
  gh release create "$tag" "${release_flags[@]}" || die "gh release create failed" 21
fi

release_url="$(gh release view "$tag" --json url -q .url 2>/dev/null || true)"

# Promote any specs shipped in this release: implemented|needs_review -> live.
# Best-effort; never blocks the release. Uses prev-tag..new-tag range so we
# only touch specs referenced in commits that landed in THIS release.
if [ -x "$SCRIPT_DIR/lib/promote-specs.sh" ] && [ -f specs/.index ]; then
  prev_tag="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname 2>/dev/null | grep -vFx "$tag" | head -1 || true)"
  if [ -n "$prev_tag" ]; then
    spec_range="${prev_tag}..${tag}"
  else
    spec_range="$tag"
  fi
  promote_stdout="$("$SCRIPT_DIR/lib/promote-specs.sh" --range "$spec_range" --status live --version "$version" || true)"
  changed_count="${promote_stdout#changed=}"
  if [ "${changed_count:-0}" -gt 0 ]; then
    git add specs/.index
    if git commit -m "chore(specs): mark ${changed_count} spec(s) live after ${tag}" >/dev/null 2>&1; then
      log "marked ${changed_count} spec(s) live in specs/.index"
      git push origin HEAD 2>/dev/null || warn "committed spec promotion locally but push failed"
    else
      warn "specs/.index promotion staged but commit failed"
    fi
  fi
fi

log "done"
printf 'tag=%s\ncommit=%s\nrelease=%s\n' "$tag" "$head_sha" "${release_url:-unknown}"
