#!/usr/bin/env bash
# Tests the release scripts against a throwaway git repository.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

git init --quiet
git config user.name test
git config user.email test@example.com
commit() { git commit --quiet --allow-empty -m "$1"; }
failures=0
expect() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$3'"; failures=$((failures + 1)); fi
}
next() { "$root/scripts/next-version.sh"; }

commit "feat: first"
expect "no tag starts at 0.1.0" "0.1.0" "$(next)"

git tag -a v0.2.0 -m v0.2.0
commit "docs: a page"
expect "docs alone suggest nothing" "" "$(next)"
commit "fix(panel): a bug"
expect "fix bumps patch" "0.2.1" "$(next)"
commit "feat(themes): a theme"
expect "feat bumps minor" "0.3.0" "$(next)"
commit "feat(config)!: rename a key"
expect "breaking bumps minor below 1.0" "0.3.0" "$(next)"

git tag -a v0.3.0-beta.1 -m beta
expect "betas do not count as the last release" "0.3.0" "$(next)"

git tag -a v1.0.0 -m v1.0.0
commit "fix: a bug"
expect "patch above 1.0" "1.0.1" "$(next)"
git commit --quiet --allow-empty -m "fix: rename a key" -m "BREAKING CHANGE: the key moved"
expect "breaking footer bumps major above 1.0" "2.0.0" "$(next)"
git tag -a v2.0.0 -m v2.0.0
commit "feat!: another"
expect "breaking mark bumps major above 1.0" "3.0.0" "$(next)"

git tag -a v3.0.0 -m v3.0.0
commit "feat(themes): add <micro>"
commit "fix: a bug"
commit "chore: tidy"
git tag -a v3.1.0 -m v3.1.0
notes="$("$root/scripts/release-notes.sh" v3.1.0)"
expected="$(printf '## Features\n\n- themes: add <micro>\n\n## Fixes\n\n- a bug')"
expect "notes group commits and skip chores" "$expected" "$notes"

"$root/scripts/release-notes.sh" v3.1.0 >notes.md
add() {
  python3 "$root/scripts/appcast.py" --file appcast.xml --version "$1" --build "$2" \
    --url "https://example.com/$1.zip" --length 10 --signature sig --min-os 14.0 --notes-file notes.md
}
add 1.0.0 10
add 1.1.0-beta.1 11
add 1.1.0 12
add 1.1.0 12
result="$(python3 - <<'EOF'
import xml.etree.ElementTree as ET
sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
items = ET.parse("appcast.xml").getroot().find("channel").findall("item")
print(" ".join(i.findtext(sparkle + "version") for i in items))
print(items[1].findtext(sparkle + "channel"), items[0].findtext(sparkle + "channel"))
print(items[0].find("enclosure").get(sparkle + "edSignature"))
print("&lt;micro&gt;" in items[0].findtext("description"))
EOF
)"
expect "appcast is newest first, with beta channel, signature, escaped notes" "$(printf '12 11 10\nbeta None\nsig\nTrue')" "$result"

exit "$failures"
