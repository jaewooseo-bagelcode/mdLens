#!/bin/bash
set -euo pipefail

IDENTITY="Developer ID Application: Sugarscone (5FK7UUGMX3)"
TEAM_ID="5FK7UUGMX3"
EXEC="mdLens"

# Optional suffix (e.g. `build-app.sh dev`) builds an isolated bundle with a unique
# name + bundle id so it never collides with an installed release while testing.
SUFFIX="${1:-}"
if [ -n "$SUFFIX" ]; then
    APP="mdLens-$SUFFIX.app"
    BUNDLE_ID="com.sugarscone.mdlens.$SUFFIX"
    DISPLAY_NAME="mdLens ($SUFFIX)"
else
    APP="mdLens.app"
    BUNDLE_ID="com.sugarscone.mdlens"
    DISPLAY_NAME="mdLens"
fi

echo "==> Building mdLens (release)..."
swift build -c release

echo "==> Creating .app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp ".build/release/$EXEC" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Apply bundle identity (canonical, or suffixed for an isolated dev build).
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$APP/Contents/Info.plist"

# Create entitlements for hardened runtime
ENTITLEMENTS=$(mktemp /tmp/entitlements.XXXXXX.plist)
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
PLIST

# Embed the Quick Look preview extension, signed with ONLY the minimal sandbox
# entitlements (app-sandbox + user-selected read + network.client). Extra
# hardened-runtime entitlements here would break JavaScript in the QL WebContent
# process. Nested code is signed before the outer app seals it.
echo "==> Embedding Quick Look extension..."
APPEX="$APP/Contents/PlugIns/mdLensQL.appex"
APPEX_ID="$BUNDLE_ID.quicklook"
mkdir -p "$APPEX/Contents/MacOS"
cp ".build/release/mdLensQL" "$APPEX/Contents/MacOS/mdLensQL"
cp Sources/QuickLookExtension/Info.plist "$APPEX/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$APPEX_ID" "$APPEX/Contents/Info.plist"
codesign --force --options runtime \
    --sign "$IDENTITY" \
    --identifier "$APPEX_ID" \
    --entitlements Sources/QuickLookExtension/QuickLook.entitlements \
    --timestamp \
    "$APPEX"

echo "==> Signing with: $IDENTITY"
codesign --force --options runtime \
    --sign "$IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    "$APP"

rm -f "$ENTITLEMENTS"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1

echo ""
echo "Binary size: $(du -sh "$APP/Contents/MacOS/$EXEC" | cut -f1)"
echo "App bundle:  $(du -sh "$APP" | cut -f1)"
echo ""
echo "To run:     open $APP"
echo "To install: cp -R $APP /Applications/"
echo ""
echo "To notarize:"
echo "  ditto -c -k --keepParent $APP mdLens.zip"
echo "  xcrun notarytool submit mdLens.zip --keychain-profile \"MarkdownViewer\" --wait"
echo "  xcrun stapler staple $APP"
