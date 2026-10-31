#!/usr/bin/env bash
# Prints Markdown release notes for a tag from the Conventional Commits since the tag before it.
# Usage: scripts/release-notes.sh v1.2.3
set -euo pipefail

tag="$1"
previous="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$tag^" 2>/dev/null || true)"
range="${previous:+$previous..}$tag"
subjects="$(git log --no-merges --format='%s' "$range")"

section() {
  local lines
  lines="$(grep -E "$2" <<<"$subjects" | sed -E 's/^[a-z]+(\(([^)]*)\))?!?: /- \2: /; s/^- : /- /' || true)"
  if [ -n "$lines" ]; then printf '## %s\n\n%s\n\n' "$1" "$lines"; fi
}

section "Breaking changes" '^[a-z]+(\([^)]*\))?!:'
section "Features" '^feat(\([^)]*\))?:'
section "Fixes" '^(fix|perf)(\([^)]*\))?:'
