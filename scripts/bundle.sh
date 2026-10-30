#!/usr/bin/env bash
# Builds Mestre with SwiftPM and wraps the binary in a .app bundle.
# No Xcode needed: Command Line Tools provide swift-build and codesign.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/Mestre.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Mestre" "$APP/Contents/MacOS/Mestre"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# SwiftPM puts module resources in a .bundle whose generated accessor only looks at the
# .app root or the build directory; the app reads them from Contents/Resources instead.
for bundle in ".build/$CONFIG"/*.bundle; do
  [ -d "$bundle" ] && find "$bundle" -maxdepth 1 -type f -exec cp {} "$APP/Contents/Resources/" \;
done
if [ -f Resources/Mestre.icns ]; then
  cp Resources/Mestre.icns "$APP/Contents/Resources/Mestre.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Mestre" "$APP/Contents/Info.plist" >/dev/null
fi

# Ad-hoc signature: keeps the bundle identity stable across rebuilds so
# Login Items (SMAppService) and permission grants stick.
codesign --force --sign - --identifier app.mestre.Mestre "$APP"

echo "Built $APP ($CONFIG)"
