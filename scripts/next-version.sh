#!/usr/bin/env bash
# Prints the version the commits since the last stable tag call for, or nothing when they
# hold no feature or fix. Below 1.0 a breaking change bumps the minor: 1.0.0 is a choice.
set -euo pipefail

last="$(git tag --list 'v[0-9]*' --sort=-v:refname | grep -v -- '-' | head -n 1 || true)"
if [ -z "$last" ]; then
  echo "0.1.0"
  exit 0
fi

log="$(git log --format='%s%n%b%n--' "$last..HEAD")"
if grep -qE '^[a-z]+(\([^)]*\))?!:|^BREAKING[ -]CHANGE:' <<<"$log"; then
  bump=major
elif grep -qE '^feat(\([^)]*\))?:' <<<"$log"; then
  bump=minor
elif grep -qE '^(fix|perf)(\([^)]*\))?:' <<<"$log"; then
  bump=patch
else
  exit 0
fi

IFS=. read -r major minor patch <<<"${last#v}"
if [ "$bump" = major ] && [ "$major" -eq 0 ]; then bump=minor; fi
case "$bump" in
  major) echo "$((major + 1)).0.0" ;;
  minor) echo "$major.$((minor + 1)).0" ;;
  patch) echo "$major.$minor.$((patch + 1))" ;;
esac
