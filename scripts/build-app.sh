#!/usr/bin/env bash
# Builds dist/Hypertime.app from the SwiftPM executable (Phase 0, §7).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="dist/Hypertime.app"
RESOURCES="Sources/Hypertime/Resources"
# Ad-hoc by default; scripts/release.sh passes a Developer ID plus hardened-runtime options.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_OPTIONS="${SIGN_OPTIONS:-}"

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

# App icon: rendered from the handoff's vector definition, then packed with iconutil.
ICON_WORK="$(mktemp -d)"
if "$APP/Contents/MacOS/Hypertime" --render-icon "$ICON_WORK" 2>/dev/null; then
  iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
else
  echo "Warning: could not render the app icon."
fi
rm -rf "$ICON_WORK"

# shellcheck disable=SC2086
codesign --force --sign "$SIGN_IDENTITY" $SIGN_OPTIONS \
  --entitlements "$RESOURCES/Hypertime.entitlements" "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
case "$(cd "$(dirname "$APP")" && pwd)" in
  /Applications*) ;;
  *) echo "Note: login items (R-16) only work reliably when the app runs from /Applications." ;;
esac
