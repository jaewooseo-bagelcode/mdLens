#!/bin/bash
set -euo pipefail

# --- Configuration ---
TEAM_ID="5FK7UUGMX3"
SIGNING_IDENTITY="Developer ID Application: Sugarscone ($TEAM_ID)"
BUNDLE_ID="com.sugarscone.mdlens"
APP_NAME="mdLens"
NOTARY_PROFILE="notarytool-profile"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
BUILD_DIR="$PROJECT_DIR/.build/release"
BINARY="$BUILD_DIR/$APP_NAME"

# Version from argument or Info.plist
VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist")}"
OUTPUT_ZIP="/tmp/${APP_NAME}-v${VERSION}-arm64.zip"

echo "=== Building $APP_NAME v$VERSION ==="

# --- Step 1: Build release binary ---
echo "[1/6] Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

# --- Step 2: Update app bundle ---
echo "[2/6] Updating app bundle..."
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Update version in Info.plist
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP_BUNDLE/Contents/Info.plist"

# --- Step 3: Code sign with Developer ID + hardened runtime ---
echo "[3/6] Code signing with Developer ID..."
codesign --force --deep --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --timestamp \
    "$APP_BUNDLE"

codesign --verify --verbose=2 "$APP_BUNDLE"
echo "  Signature OK"

# --- Step 4: Create zip ---
echo "[4/6] Creating zip..."
rm -f "$OUTPUT_ZIP"
cd "$PROJECT_DIR"
zip -r -q "$OUTPUT_ZIP" "$APP_NAME.app"

# --- Step 5: Notarize (skip if profile not configured) ---
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "[5/6] Submitting for notarization..."
    xcrun notarytool submit "$OUTPUT_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    # --- Step 6: Staple ---
    echo "[6/6] Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"

    # Recreate zip with stapled app
    rm -f "$OUTPUT_ZIP"
    cd "$PROJECT_DIR"
    zip -r -q "$OUTPUT_ZIP" "$APP_NAME.app"
else
    echo "[5/6] Skipping notarization (keychain profile '$NOTARY_PROFILE' not found)"
    echo "  To set up: xcrun notarytool store-credentials $NOTARY_PROFILE"
    echo "    --apple-id <APPLE_ID> --team-id $TEAM_ID --password <APP_SPECIFIC_PASSWORD>"
    echo "[6/6] Skipping staple"
fi

echo ""
echo "=== Done ==="
echo "App:  $APP_BUNDLE"
echo "Zip:  $OUTPUT_ZIP"
echo ""
echo "To upload to GitHub release:"
echo "  gh release upload v$VERSION $OUTPUT_ZIP --clobber"
