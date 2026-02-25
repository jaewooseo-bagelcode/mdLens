# mdLens

Lightweight macOS-native markdown viewer. No Electron, no bloat.

**2.3 MB binary / ~15 MB memory / instant startup**

Built with SwiftUI + WKWebView and a single dependency ([swift-markdown](https://github.com/swiftlang/swift-markdown)).

## Features

- **Syntax Highlighting** — 190+ languages via highlight.js, theme-aware
- **Math / LaTeX** — Inline `$...$` and display `$$...$$` via KaTeX
- **Mermaid Diagrams** — Flowcharts, sequence diagrams, and more
- **GitHub Admonitions** — NOTE, TIP, IMPORTANT, WARNING, CAUTION
- **Footnotes** — Reference-style footnotes with back-links
- **Emoji Shortcodes** — ~200 common shortcodes (`:rocket:` → :rocket:)
- **Sidebar** — File tree, heading outline, article list
- **Themes** — Auto / Light / Dark / Sepia
- **File Watching** — Auto-reload on external changes (FSEvents)
- **Quick Open** — `Cmd+P` fuzzy file search
- **Drag & Drop** — Drop `.md` files or folders to open

## Install

Download `mdLens.app` from [Releases](https://github.com/jaewooseo-bagelcode/mdLens/releases) and move to `/Applications`.

Signed and notarized with Developer ID.

## Build from Source

Requires macOS 14+ and Swift toolchain (Xcode Command Line Tools is enough).

```bash
# Run directly
swift run mdLens

# Release build
swift build -c release

# Create .app bundle (requires Developer ID certificate)
bash scripts/build-app.sh
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+O` | Open file |
| `Cmd+Shift+O` | Open folder |
| `Cmd+P` | Quick Open |
| `Cmd+Shift+L` | Toggle sidebar |
| `Cmd+W` | Close window |

## Architecture

```
Sources/MarkdownViewer/
├── App/           # Entry point, state, menu commands
├── Models/        # Document, file tree, outline
├── Services/      # Renderer, file watcher, parser, emoji map
├── Views/         # Content, sidebar, document, settings
├── Theme/         # Light/Dark/Sepia theme definitions
└── Extensions/    # String utilities
```

Markdown → swift-markdown AST → HTML (custom visitor) → WKWebView.

Heavy JS libraries (KaTeX, Mermaid) are lazy-loaded from CDN only when the document needs them.

## License

MIT
