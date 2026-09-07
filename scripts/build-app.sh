#!/usr/bin/env bash
# Builds dist/Hypertime.app from the SwiftPM executable (Phase 0, §7).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="dist/Hypertime.app"
RESOURCES="Sources/Hypertime/Resources"

swift build -c "$CONFIG" --product Hypertime
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/Hypertime" "$APP/Contents/MacOS/Hypertime"
cp "$RESOURCES/Info.plist" "$APP/Contents/Info.plist"

# SwiftPM resource bundles (GRDB ships one) must travel with the executable.
for bundle in "$BIN_PATH"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Asset catalogue is optional until the Phase 2 design handoff lands.
if [ -d "$RESOURCES/Assets.xcassets" ]; then
  xcrun actool "$RESOURCES/Assets.xcassets" \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 15.0 \
    --app-icon AppIcon --output-partial-info-plist /tmp/hypertime-assets.plist >/dev/null
fi

codesign --force --sign - --entitlements "$RESOURCES/Hypertime.entitlements" "$APP" 2>/dev/null

echo "Built $APP"
case "$(cd "$(dirname "$APP")" && pwd)" in
  /Applications*) ;;
  *) echo "Note: login items (R-16) only work reliably when the app runs from /Applications." ;;
esac
