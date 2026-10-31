#!/usr/bin/env bash
# Signs two builds with a throwaway certificate and checks macOS would see them as the same app:
# their fingerprints differ, but what permissions are tied to does not. CI only, since codesign
# needs the keychain in its search list and that shouldn't change on a working Mac.
set -euo pipefail
if [ -z "${GITHUB_ACTIONS:-}" ]; then echo "error: this test runs on CI" >&2; exit 1; fi
cd "$(dirname "$0")/.."

work="$(mktemp -d)"
keychain="$work/test.keychain-db"
cleanup() {
  security delete-keychain "$keychain" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

scripts/make-signing-cert.sh --no-upload "$work" >/dev/null
info="$(CERTIFICATE_BASE64="$(base64 -i "$work/mestre-signing.p12")" \
  CERTIFICATE_PASSWORD="$(cat "$work/mestre-signing-password.txt")" \
  scripts/import-signing-cert.sh "$keychain")"
identity="$(tail -n 1 <<<"$info")"

build() {
  MESTRE_SIGN_IDENTITY="$identity" MESTRE_HARDENED_RUNTIME=1 MESTRE_VERSION="$1" MESTRE_BUILD="$2" \
    scripts/bundle.sh release >&2 || return 1
  codesign --verify --deep --strict build/Mestre.app
  codesign -dr - build/Mestre.app 2>&1 | grep '^designated'
  codesign -dvvv build/Mestre.app 2>&1 | grep '^CDHash=' >> "$work/hashes"
}

fail() { echo "FAIL $1" >&2; exit 1; }
security find-identity -p codesigning "$keychain"
first="$(build 0.0.1 1)" || fail "couldn't sign the first build"
second="$(build 0.0.2 2)" || fail "couldn't sign the second build"
echo "$first"
grep -q 'certificate leaf' <<<"$first" || fail "the requirement doesn't name the certificate"
[ "$first" = "$second" ] || fail "the requirement changed between builds: $second"
[ "$(sort -u "$work/hashes" | wc -l)" -eq 2 ] || fail "both builds have the same fingerprint, so this proves nothing"
echo "ok   two different builds share one identity"

codesign -dvvv build/Mestre.app 2>&1 | grep -q 'flags=.*runtime' || fail "the hardened runtime is off"
for inner in Versions/B/Autoupdate Versions/B/Updater.app Versions/B/XPCServices/Installer.xpc Versions/B/XPCServices/Downloader.xpc; do
  codesign -dvvv "build/Mestre.app/Contents/Frameworks/Sparkle.framework/$inner" 2>&1 | grep -q 'flags=.*runtime' || fail "the hardened runtime is off for $inner"
done
codesign -d --entitlements - build/Mestre.app 2>&1 | grep -q 'automation.apple-events' || fail "the Apple events entitlement is missing"
echo "ok   the hardened runtime is on, with the Apple events entitlement"

# Library validation is the risk: under the hardened runtime, dyld refuses a framework it doesn't
# accept, and the app dies before it starts. Sparkle is linked, so surviving launch means it loaded.
mkdir -p "$work/config"
XDG_CONFIG_HOME="$work/config" build/Mestre.app/Contents/MacOS/Mestre >"$work/launch.log" 2>&1 &
pid=$!
sleep 8
if ! kill -0 "$pid" 2>/dev/null; then
  cat "$work/launch.log" >&2
  fail "the hardened app didn't survive launch"
fi
kill "$pid"
echo "ok   the hardened app launches with Sparkle loaded"
