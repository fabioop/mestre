#!/usr/bin/env bash
# Tags master and pushes the tag, which starts .github/workflows/release.yml.
# Usage: scripts/release.sh [version]. Without a version it suggests one and asks.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "error: $1" >&2; exit 1; }

[ "$(git branch --show-current)" = master ] || fail "releases come from master"
[ -z "$(git status --porcelain)" ] || fail "the working tree has uncommitted changes"
git fetch --quiet --tags origin master
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] || fail "master differs from origin/master"

version="${1:-}"
if [ -z "$version" ]; then
  suggested="$(scripts/next-version.sh)"
  if [ -n "$suggested" ]; then
    read -r -p "Version [$suggested]: " version
    version="${version:-$suggested}"
  else
    echo "No feature or fix since the last release."
    read -r -p "Version (empty to stop): " version
    [ -n "$version" ] || exit 0
  fi
fi

version="${version#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || fail "$version is not a version like 1.2.3 or 1.2.3-beta.1"
git rev-parse --quiet --verify "refs/tags/v$version" >/dev/null && fail "v$version already exists"

read -r -p "Tag and release v$version from $(git rev-parse --short HEAD)? [y/N] " answer
[ "$answer" = y ] || [ "$answer" = Y ] || exit 0

git tag -a "v$version" -m "v$version"
git push origin "v$version"
echo "Pushed v$version. Follow it with: gh run watch"
