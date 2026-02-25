#!/bin/bash
set -euo pipefail

IDENTITY="${CODESIGN_IDENTITY:--}"
BUNDLE_ID="com.sugarscone.mdlens"
APP="mdLens.app"
EXEC="mdLens"
QL_EXEC="mdLensQL"
QL_APPEX="mdLensQL.appex"
QL_ENTITLEMENTS="Sources/QuickLookExtension/QuickLook.entitlements"

echo "==> Building mdLens (release)..."
swift build -c release

echo "==> Creating .app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp ".build/release/$EXEC" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# --- Quick Look Extension ---
echo "==> Creating Quick Look extension..."
mkdir -p "$APP/Contents/PlugIns/$QL_APPEX/Contents/MacOS"
cp ".build/release/$QL_EXEC" "$APP/Contents/PlugIns/$QL_APPEX/Contents/MacOS/"
cp Sources/QuickLookExtension/Info.plist "$APP/Contents/PlugIns/$QL_APPEX/Contents/"

echo "==> Extension: $APP/Contents/PlugIns/$QL_APPEX"

echo "==> Signing with: $IDENTITY"
# Sign extension first (inside-out signing) with sandbox entitlements
codesign --force --sign "$IDENTITY" \
    --entitlements "$QL_ENTITLEMENTS" \
    "$APP/Contents/PlugIns/$QL_APPEX"

# Sign main app
codesign --force --sign "$IDENTITY" \
    "$APP"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1

echo ""
echo "Binary size: $(du -sh "$APP/Contents/MacOS/$EXEC" | cut -f1)"
echo "QL ext size: $(du -sh "$APP/Contents/PlugIns/$QL_APPEX/Contents/MacOS/$QL_EXEC" | cut -f1)"
echo "App bundle:  $(du -sh "$APP" | cut -f1)"
echo ""
echo "To run:     open $APP"
echo "To install: cp -R $APP /Applications/"
echo ""
echo "To notarize (requires Developer ID):"
echo "  CODESIGN_IDENTITY='Developer ID Application: ...' bash scripts/build-app.sh"
echo "  ditto -c -k --keepParent $APP mdLens.zip"
echo "  xcrun notarytool submit mdLens.zip --keychain-profile \"MarkdownViewer\" --wait"
echo "  xcrun stapler staple $APP"
