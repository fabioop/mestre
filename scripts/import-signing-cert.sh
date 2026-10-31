#!/usr/bin/env bash
# Imports a signing certificate into a new throwaway keychain on a CI machine.
# Prints the keychain's path and the certificate's SHA-1, which codesign accepts as an identity.
# Usage: CERTIFICATE_BASE64=… CERTIFICATE_PASSWORD=… scripts/import-signing-cert.sh <keychain path>
set -euo pipefail
if [ -z "${GITHUB_ACTIONS:-}" ]; then echo "error: this changes the keychain search list, so it runs on CI only" >&2; exit 1; fi

keychain="$1"
password="$(uuidgen)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
printf '%s' "$CERTIFICATE_BASE64" | base64 --decode > "$work/certificate.p12"
security import "$work/certificate.p12" -k "$keychain" -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null

# codesign only finds identities in the search list, which is fine to change on a throwaway machine.
security list-keychains -d user -s "$keychain" login.keychain

echo "$keychain"
security find-certificate -a -Z "$keychain" | awk '/^SHA-1/ { print $NF; exit }'
