#!/usr/bin/env bash
# Builds Mestre with SwiftPM and wraps the binary in a .app bundle.
# No Xcode needed: Command Line Tools provide swift-build and codesign.
#
# Release builds set these; a plain local build needs none of them:
#   MESTRE_VERSION            visible version, from the git tag (default 0.0.0-dev)
#   MESTRE_BUILD              build number Sparkle compares (default: commits on this branch)
#   MESTRE_SIGN_IDENTITY      signing identity: Developer ID or self-signed (default: ad-hoc)
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
  # The appcast is signed too, so a feed from anywhere else (the config's feedURL, a pushed
  # appcast branch) can't offer builds or show notes; the archive is checked before it's unpacked.
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $MESTRE_SPARKLE_PUBLIC_KEY" \
    -c "Add :SURequireSignedFeed bool true" -c "Add :SUVerifyUpdateBeforeExtraction bool true" "$PLIST"
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
# An ad-hoc identity is only a fingerprint of the build, so macOS drops permissions like
# Accessibility on every rebuild. A certificate keeps them across builds. Every build gets the
# hardened runtime, which ignores DYLD_INSERT_LIBRARIES: without it any process could load code into
# Mestre and use its permissions. The runtime's library validation only loads frameworks signed by
# the same team, and a self-signed or ad-hoc certificate has none, so those builds turn it off to
# load Sparkle. DYLD_* variables stay ignored either way.
ENTITLEMENTS=Resources/Mestre.entitlements
SIGN=(codesign --force --sign "$IDENTITY" --options runtime)
case "$IDENTITY" in
  "Developer ID"*)
    SIGN+=(--timestamp)
    ;;
  *)
    ENTITLEMENTS="build/Mestre.entitlements"
    cp Resources/Mestre.entitlements "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS"
    ;;
esac
APP_FLAGS=(--entitlements "$ENTITLEMENTS")
sign() { "${SIGN[@]}" "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --identifier app.mestre.Mestre ${APP_FLAGS[@]+"${APP_FLAGS[@]}"} "$APP"

echo "Built $APP ($CONFIG, $VERSION build $BUILD)"
