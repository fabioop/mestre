#!/usr/bin/env bash
# Creates the self-signed certificate releases are signed with, and adds it to GitHub's secrets.
# macOS ties permissions like Accessibility to this certificate, so they survive updates.
# Usage: scripts/make-signing-cert.sh [--no-upload] [folder for the files, default ~]
set -euo pipefail

upload=true
if [ "${1:-}" = "--no-upload" ]; then upload=false; shift; fi
out="${1:-$HOME}"
p12="$out/mestre-signing.p12"
password_file="$out/mestre-signing-password.txt"
if [ -e "$p12" ]; then echo "error: $p12 already exists" >&2; exit 1; fi

umask 077
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# /usr/bin/openssl on purpose: `security import` reads its .p12 format, and OpenSSL 3's default it can't.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -sha256 \
  -subj "/CN=Mestre Self-Signed" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
/usr/bin/openssl rand -hex 24 > "$password_file"
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "Mestre Self-Signed" \
  -passout "file:$password_file" -out "$p12"

if [ "$upload" = true ]; then
  base64 -i "$p12" | gh secret set SIGNING_CERTIFICATE_BASE64 --repo fabioop/mestre
  gh secret set SIGNING_CERTIFICATE_PASSWORD --repo fabioop/mestre < "$password_file"
  echo "Added SIGNING_CERTIFICATE_BASE64 and SIGNING_CERTIFICATE_PASSWORD to GitHub."
fi

echo "Created $p12 and $password_file."
echo "Save both in your password manager, then delete them from this folder."
