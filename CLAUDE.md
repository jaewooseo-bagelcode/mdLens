# mdLens — Claude Code Instructions

## Project Overview
macOS native markdown viewer built with SwiftUI + WKWebView + swift-markdown.
SwiftPM project (no Xcode project file).

## Build & Run

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run locally (copy binary into app bundle)
cp .build/release/mdLens mdLens.app/Contents/MacOS/mdLens
open mdLens.app
```

## Release Build (Signed + Notarized)

```bash
# Build, sign, notarize, and create zip
./scripts/build-release.sh 1.2.0

# Upload to GitHub release
gh release create v1.2.0 --title "v1.2.0 — Title" --notes "..."
gh release upload v1.2.0 /tmp/mdLens-v1.2.0-arm64.zip
```

### Notarization Setup (one-time)
The build script skips notarization if the keychain profile is not configured.
```bash
xcrun notarytool store-credentials notarytool-profile \
    --apple-id <APPLE_ID> \
    --team-id 5FK7UUGMX3 \
    --password <APP_SPECIFIC_PASSWORD>
```

### Signing Identity
- **Developer ID**: `Developer ID Application: Sugarscone (5FK7UUGMX3)`
- **Bundle ID**: `com.sugarscone.mdlens`
- `swift build` produces ad-hoc signed binaries → Gatekeeper blocks these
- Must use `codesign --options runtime --sign "Developer ID..."` for distribution

## Architecture

### Rendering Pipeline (MarkdownRenderer.swift)
1. Front matter extraction → styled HTML card
2. Link destination preprocessing (encode spaces for CommonMark)
3. Emoji shortcode conversion (single-pass regex)
4. Footnote definition extraction
5. swift-markdown AST parsing → HTMLVisitor
6. Post-process: footnote refs, admonitions
7. Wrap in full HTML with CSS + scripts

### Key Design Decisions
- **loadFileURL** instead of loadHTMLString: WKWebView needs file:// access for local images
- Image paths resolved to absolute `file://` URLs in HTMLVisitor
- Temp HTML written to `/tmp/mdlens/preview.html`, `allowingReadAccessTo: /`
- Dangerous HTML tags (script, iframe, etc.) sanitized in visitHTMLBlock/visitInlineHTML

### Shared Utilities (String+Extensions.swift)
- `extractPlainText(from:)` — recursive AST plain text extraction
- `SlugGenerator` — heading ID generation (shared between OutlineParser + HTMLVisitor)
- `markdownExtensions` — `Set<String>` of recognized extensions
- `String.htmlEscaped` — HTML entity escaping
- `String.slugified` — heading text → URL-safe slug

## Conventions
- All regexes cached as `static let` (no runtime compilation per render)
- `AppState.applyDocument()` for shared load-parse-compute pipeline
- UserDefaults keys as `static let` constants on AppState
