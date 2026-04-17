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

## Release & Auto-update
Tag format is `build-<7-char-hash>` (no semver). See `README.md` for the full install,
release, and auto-update flow — it's the authoritative doc. Do not duplicate details here.

Key invariants agents must preserve:
- `swift build` alone produces an ad-hoc signed binary with `BuildInfo.commitHash == "dev"` — auto-update stays disabled.
- `scripts/build-release.sh` is the only path that injects a real hash + Developer ID signs + notarizes.
- Never hand-edit `CFBundleShortVersionString`; the script sets it from `git HEAD`.

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
