# mdLens — Claude Code Instructions

## Project Overview
macOS native markdown viewer built with SwiftUI + WKWebView + swift-markdown.
SwiftPM project (no Xcode project file).

## Features (PLAN.md is the SSOT for in-flight work)
Viewers: rendered Markdown (swift-markdown → WKWebView) and raw `.html` (loaded directly,
pipeline bypassed). Two optional add-ons, both shipped:
- **Quick Look extension** (`Sources/QuickLookExtension` → `mdLensQL.appex`): Finder spacebar /
  preview-pane renders `.md`/`.html` via the shared `MarkdownCore`, full fidelity. JavaScript
  **runs** in the QL WebContent process — only with the minimal sandbox entitlements; adding
  JIT/library entitlements breaks it (see memory `quicklook-extension-wkwebview-js`).
- **Opt-in Slack 👀 ingestion** (`Sources/MarkdownViewer/Slack`): with Keychain tokens, a
  MenuBarExtra runs a Socket Mode listener; reacting 👀 on a Slack `.html`/`.md` downloads it
  into a new mdLens window. No tokens → pure viewer, zero background. Tokens in **Keychain**
  (never embedded); per-user BYO Slack app, manifest name `mdLens (<user>-<id>)`. Signing
  identity `Developer ID Application: Sugarscone (5FK7UUGMX3)` keeps Keychain ACL prompt-free.

⚠️ **Never use `pkill -f <pat>`** — it matches and kills the executing shell. Kill only recorded PIDs.
Work on `dev`; `main` is the protected release branch.

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

### Package targets (3)
- **`MarkdownCore`** (library) — shared rendering: `MarkdownRenderer`, `EmojiMap`, `AppThemeMode`,
  `String+Extensions`. Public surface: `MarkdownRenderer.renderHTML`, `AppThemeMode`, `markdownExtensions`.
  Depended on by both other targets.
- **`mdLens`** (`Sources/MarkdownViewer`) — the SwiftUI app executable.
- **`mdLensQL`** (`Sources/QuickLookExtension`) — the Quick Look preview `.appex`. `NSExtensionMain`
  entry; signed with ONLY app-sandbox + files.user-selected.read-only + network.client.

### App Structure
- **DocumentGroup(viewing: MarkdownFileDocument.self)** — read-only document app. Each open
  file gets its own window/scene with independent state; there is **no shared app-wide document
  singleton**. Opening N files (Finder multi-select, drag-to-Dock) yields N windows.
- `MarkdownFileDocument` (FileDocument) holds the loaded text; the on-disk URL comes from
  `FileDocumentConfiguration.fileURL` (needed for relative-image baseURL).
- `AppSettings` (@Observable, single shared instance, UserDefaults-backed) holds cross-window
  prefs (theme, fontSize). Injected via `.environment`.
- Per-window menu actions (Reload) flow through `.focusedSceneValue` → `@FocusedValue` so the
  command targets the frontmost document window.

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
- Image paths resolved to absolute `file://` URLs in HTMLVisitor; link hrefs likewise
  resolved in `visitLink` (relative→doc dir, absolute `/` & `~` direct, `#`/http/mailto kept)
- Link clicks routed by `WebViewRepresentable`'s `WKNavigationDelegate`: `.md` files open in
  a new window (open-with-this-app → DocumentGroup), other files/web URLs open externally,
  same-document `#anchors` scroll
- Temp HTML written per-window to `/tmp/mdlens/preview-<uuid>.html`, `allowingReadAccessTo: /` (UUID avoids multi-window clobber)
- Dangerous HTML tags (script, iframe, etc.) sanitized in visitHTMLBlock/visitInlineHTML

### Raw .html & Quick Look
- `MarkdownFileDocument.readableContentTypes` includes `.html`; `DocumentView` detects html and
  uses `WebViewRepresentable(directFileURL:)` to `loadFileURL` the file directly (no markdown pipeline).
- `mdLensQL.appex` (`PreviewViewController`): `.md` → `MarkdownRenderer` → temp file → `loadFileURL`;
  `.html` → `loadFileURL` directly. Embedded + signed by `build-app.sh`/`build-release.sh` (app signed
  WITHOUT `--deep` so the appex keeps its own entitlements).

### Slack (Sources/MarkdownViewer/Slack)
- `SlackController.shared` (started at launch via `startIfConfigured`) owns the opt-in lifecycle;
  `isActive` drives `MenuBarExtra(isInserted:)`. `SocketModeClient` (@MainActor) → reaction → `SlackAPI`
  download → open in a new window. `SlackSetupView` ("Connect Slack") writes tokens to `Keychain`
  (service = `Bundle.main.bundleIdentifier`). `ManifestService` builds the BYO-app manifest deep link.

### Shared utilities (Sources/MarkdownCore/String+Extensions.swift)
- `extractPlainText(from:)`, `SlugGenerator` (heading anchors), `markdownExtensions` (public),
  `String.htmlEscaped`, `String.slugified`.

## Conventions
- All regexes cached as `static let` (no runtime compilation per render)
- UserDefaults keys as `static let` constants (e.g. on `AppSettings`)
- No shared mutable app state across windows; document state lives per-scene via DocumentGroup
