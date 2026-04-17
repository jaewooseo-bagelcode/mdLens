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

Releases are tagged by git commit hash (no semver). The build script derives the hash from `HEAD`
and injects it into `Sources/MarkdownViewer/Services/BuildInfo.swift` at build time.

```bash
# Commit all changes first (script refuses on dirty tree)
./scripts/build-release.sh
# → produces /tmp/mdLens-build-<hash>-arm64.zip

gh release create build-<hash> --repo jaewooseo-bagelcode/mdLens \
    --title "build-<hash>" --notes "Build <hash>" /tmp/mdLens-build-<hash>-arm64.zip
```

### Auto-update
`Updater.swift` runs on app launch. If `gh` CLI is available on PATH
(`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`) and the latest release tag's hash differs
from `BuildInfo.commitHash`, it downloads + unzips the new `.app` into `/tmp`, then swaps it
into `/Applications/mdLens.app` the moment no windows are visible (frictionless). The swap
terminates the app; next launch is the new build. Dev builds (`commitHash == "dev"`) skip
the check entirely.

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
