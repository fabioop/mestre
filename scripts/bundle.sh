#!/usr/bin/env bash
# Builds Mestre with SwiftPM and wraps the binary in a .app bundle.
# No Xcode needed: Command Line Tools provide swift-build and codesign.
#
# Release builds set these; a plain local build needs none of them:
#   MESTRE_VERSION            visible version, from the git tag (default 0.0.0-dev)
#   MESTRE_BUILD              build number Sparkle compares (default: commits on this branch)
#   MESTRE_SIGN_IDENTITY      Developer ID identity (default: ad-hoc)
#   MESTRE_SPARKLE_PUBLIC_KEY update key; without it the app leaves Sparkle off
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/Mestre.app"
VERSION="${MESTRE_VERSION:-0.0.0-dev}"
BUILD="${MESTRE_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"
IDENTITY="${MESTRE_SIGN_IDENTITY:--}"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp ".build/$CONFIG/Mestre" "$APP/Contents/MacOS/Mestre"
cp Resources/Info.plist "$APP/Contents/Info.plist"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$PLIST"
if [ -n "${MESTRE_SPARKLE_PUBLIC_KEY:-}" ]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $MESTRE_SPARKLE_PUBLIC_KEY" "$PLIST"
fi
ditto ".build/$CONFIG/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Mestre"
# SwiftPM puts module resources in a .bundle whose generated accessor only looks at the
# .app root or the build directory; the app reads them from Contents/Resources instead.
for bundle in ".build/$CONFIG"/*.bundle; do
  [ -d "$bundle" ] && find "$bundle" -maxdepth 1 -type f -exec cp {} "$APP/Contents/Resources/" \;
done
if [ -f Resources/Mestre.icns ]; then
  cp Resources/Mestre.icns "$APP/Contents/Resources/Mestre.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Mestre" "$APP/Contents/Info.plist" >/dev/null
fi

# Sign inside out: Sparkle's helpers, its framework, then the app.
if [ "$IDENTITY" = "-" ]; then
  sign() { codesign --force --sign - "$@"; }
else
  sign() { codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"; }
fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"

# Ad-hoc signature: keeps the bundle identity stable across rebuilds so
# Login Items (SMAppService) and permission grants stick. The hardened runtime a Developer ID
# signature needs blocks Apple events unless the entitlement allows them.
if [ "$IDENTITY" = "-" ]; then
  sign --identifier app.mestre.Mestre "$APP"
else
  sign --identifier app.mestre.Mestre --entitlements Resources/Mestre.entitlements "$APP"
fi

echo "Built $APP ($CONFIG, $VERSION build $BUILD)"
