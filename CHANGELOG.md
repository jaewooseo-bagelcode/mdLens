# Changelog

Releases are now tagged `build-<hash>` (see README). Entries below the semver ones use that scheme.

## [build-e3a2834] - 2026-06-26

### Added
- Raw `.html` viewing — loaded directly in WKWebView, markdown pipeline bypassed
- Quick Look preview extension (`mdLensQL.appex`) — Finder spacebar / preview-pane renders `.md`
  and `.html` at full fidelity (highlight.js / KaTeX / Mermaid run inside the Quick Look host)
- Opt-in Slack 👀 ingestion — react 👀 on a Slack `.html`/`.md` to download and open it in mdLens
  (per-user Socket Mode listener; tokens stored in Keychain, never embedded)

### Changed
- Shared rendering extracted into a `MarkdownCore` module (used by the app and the QL extension)
- Per-user Slack manifest app name is now unique: `mdLens (<user>-<id>)`

## [1.0.1] - 2026-03-03

### Fixed

- Fix crash when opening markdown files containing blockquotes with tables (swift-markdown `.parseBlockDirectives` bug)
- Improve KaTeX detection to avoid false positives on currency like `$0.014`

## [1.0.0] - 2025-02-25

Initial release.

### Features

- Markdown rendering via swift-markdown AST → HTML → WKWebView
- Syntax highlighting with highlight.js (190+ languages)
- KaTeX math rendering (inline and display)
- Mermaid diagram support (flowcharts, sequence diagrams, etc.)
- GitHub-style admonitions (NOTE, TIP, IMPORTANT, WARNING, CAUTION)
- Footnotes with back-links
- Emoji shortcodes (~200 common shortcodes)
- Sidebar with file tree, heading outline, and article list
- Themes: Auto, Light, Dark, Sepia
- File watching with auto-reload (FSEvents, 200ms debounce)
- Quick Open with fuzzy search (Cmd+P)
- Drag & drop for files and folders
- Open Recent files menu
- Set as default app for .md files
- Word / character / line count with reading time
- Developer ID signed and Apple notarized
