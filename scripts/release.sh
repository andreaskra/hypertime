#!/usr/bin/env bash
# Builds, signs and packages Hypertime for distribution (Phase 3, §7).
#
#   scripts/release.sh                 # Developer ID if one is installed, otherwise ad-hoc
#   scripts/release.sh --adhoc         # force ad-hoc signing (local use only)
#   scripts/release.sh --notarize      # also submit to Apple and staple the ticket
#   scripts/release.sh --profile NAME  # notarytool keychain profile (default: hypertime)
#
# Sparkle-style auto-updates are out of scope.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=0
ADHOC=0
PROFILE="hypertime"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --notarize) NOTARIZE=1 ;;
    --adhoc) ADHOC=1 ;;
    --profile) PROFILE="$2"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

APP="dist/Hypertime.app"
PLIST="Sources/Hypertime/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
ZIP="dist/Hypertime-$VERSION.zip"
DMG="dist/Hypertime-$VERSION.dmg"

# ---------------------------------------------------------------- identity
IDENTITY="-"
if [ "$ADHOC" -eq 0 ]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | grep 'Developer ID Application' \
    | head -1 \
    | sed -E 's/.*"(.*)".*/\1/' || true)"
fi

if [ -z "$IDENTITY" ] || [ "$IDENTITY" = "-" ]; then
  IDENTITY="-"
  SIGN_OPTIONS=""
  cat <<'EOF'
No Developer ID Application certificate found — signing ad-hoc.

An ad-hoc build runs on this Mac but Gatekeeper will refuse it elsewhere. To distribute:
  1. Join the Apple Developer Program and create a "Developer ID Application" certificate.
  2. Install it in the login keychain, then re-run this script.
EOF
else
  # Hardened runtime and a secure timestamp are both required for notarisation.
  SIGN_OPTIONS="--options runtime --timestamp"
  echo "Signing with: $IDENTITY"
fi

# ---------------------------------------------------------------- build
SIGN_IDENTITY="$IDENTITY" SIGN_OPTIONS="$SIGN_OPTIONS" scripts/build-app.sh

echo "Verifying signature…"
codesign --verify --strict --verbose=2 "$APP"
if [ "$IDENTITY" != "-" ]; then
  spctl -a -vv "$APP" || echo "Note: Gatekeeper will accept the app once it is notarised."
fi

# ---------------------------------------------------------------- package
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "Hypertime $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

if [ "$IDENTITY" != "-" ]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

echo "Packaged:"
echo "  $ZIP"
echo "  $DMG"

# ---------------------------------------------------------------- notarise
if [ "$NOTARIZE" -eq 0 ]; then
  if [ "$IDENTITY" != "-" ]; then
    cat <<EOF

To notarise (one-off credential setup, then re-run with --notarize):
  xcrun notarytool store-credentials "$PROFILE" \\
    --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>
  scripts/release.sh --notarize
EOF
  fi
  exit 0
fi

if [ "$IDENTITY" = "-" ]; then
  echo "Refusing to notarise an ad-hoc signed build." >&2
  exit 1
fi

echo "Submitting to Apple…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "Notarised and stapled: $DMG"
