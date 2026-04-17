#!/bin/bash
set -euo pipefail

TEAM_ID="5FK7UUGMX3"
SIGNING_IDENTITY="Developer ID Application: Sugarscone ($TEAM_ID)"
BUNDLE_ID="com.sugarscone.mdlens"
APP_NAME="mdLens"
NOTARY_PROFILE="notarytool-profile"
REPO="jaewooseo-bagelcode/mdLens"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
BUILD_DIR="$PROJECT_DIR/.build/release"
BINARY="$BUILD_DIR/$APP_NAME"
BUILDINFO="$PROJECT_DIR/Sources/MarkdownViewer/Services/BuildInfo.swift"

cd "$PROJECT_DIR"

if ! git diff --quiet HEAD -- . ':!Sources/MarkdownViewer/Services/BuildInfo.swift'; then
    echo "error: uncommitted changes. Commit first so the hash reflects shipped code." >&2
    exit 1
fi

HASH="$(git rev-parse --short=7 HEAD)"
TAG="build-$HASH"
OUTPUT_ZIP="/tmp/${APP_NAME}-${TAG}-arm64.zip"

echo "=== Building $APP_NAME $TAG ==="

cat > "$BUILDINFO" <<EOF
enum BuildInfo {
    static let commitHash = "$HASH"
    static let repo = "$REPO"
}
EOF
trap 'git checkout -- "$BUILDINFO" 2>/dev/null || true' EXIT

echo "[1/6] Building release binary..."
swift build -c release

echo "[2/6] Updating app bundle..."
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
plutil -replace CFBundleShortVersionString -string "$HASH" "$APP_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$HASH" "$APP_BUNDLE/Contents/Info.plist"

echo "[3/6] Code signing..."
codesign --force --deep --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --timestamp \
    "$APP_BUNDLE"
codesign --verify --verbose=2 "$APP_BUNDLE"

echo "[4/6] Creating zip..."
rm -f "$OUTPUT_ZIP"
zip -r -q "$OUTPUT_ZIP" "$APP_NAME.app"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "[5/6] Notarizing..."
    xcrun notarytool submit "$OUTPUT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "[6/6] Stapling..."
    xcrun stapler staple "$APP_BUNDLE"
    rm -f "$OUTPUT_ZIP"
    zip -r -q "$OUTPUT_ZIP" "$APP_NAME.app"
else
    echo "[5/6] Skipping notarization (no keychain profile '$NOTARY_PROFILE')"
fi

echo ""
echo "=== Done ==="
echo "Tag:  $TAG"
echo "Zip:  $OUTPUT_ZIP"
echo ""
echo "Publish:"
echo "  gh release create $TAG --repo $REPO --title \"$TAG\" --notes \"Build $HASH\" \"$OUTPUT_ZIP\""
