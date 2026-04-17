# mdLens — Agent Guide

This README is written for coding agents (Claude Code, Codex, etc.) that need to install,
run, update, or modify mdLens on a user's Mac. Human-facing marketing copy lives elsewhere.

mdLens is a native macOS markdown viewer: SwiftUI + WKWebView + swift-markdown.
SwiftPM project, no Xcode project file. macOS 14+, Apple Silicon.

## Install (agent-driven)

Assumes `gh` CLI is authenticated and the user's machine is arm64.

```bash
TAG=$(gh release view --repo jaewooseo-bagelcode/mdLens --json tagName -q .tagName)
TMP=$(mktemp -d)
gh release download "$TAG" --repo jaewooseo-bagelcode/mdLens --pattern '*.zip' --dir "$TMP"
unzip -q -o "$TMP"/*.zip -d "$TMP"
rm -rf /Applications/mdLens.app
mv "$TMP/mdLens.app" /Applications/mdLens.app
xattr -dr com.apple.quarantine /Applications/mdLens.app 2>/dev/null || true
open /Applications/mdLens.app
```

Releases are Developer ID signed + notarized + stapled, so Gatekeeper allows launch without
the "unidentified developer" dialog. If install fails with a signature error, confirm the
zip is the notarized artifact (`spctl -a -vv /Applications/mdLens.app` should print `accepted`).

## Auto-update (how the app stays current)

Every release is tagged `build-<short-hash>` where `<short-hash>` is the 7-char git commit
hash the binary was built from. The app embeds its own hash in `BuildInfo.swift` at build
time.

On launch the app runs `Updater.swift`:

1. Locates `gh` at `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, or `/usr/bin/gh`. If none
   are executable → skip silently.
2. `gh release view --repo jaewooseo-bagelcode/mdLens --json tagName -q .tagName` →
   compare the `build-<hash>` suffix to `BuildInfo.commitHash`.
3. If different, downloads + unzips the new `.app` into `/tmp/mdlens-update-<tag>/`.
4. Watches for "no visible windows" (checks immediately, otherwise observes
   `NSWindow.willCloseNotification`). The moment the user closes the last window, a helper
   bash script at `/tmp/mdlens-update-swap.sh` waits for the parent PID to exit, replaces
   `/Applications/mdLens.app`, clears the quarantine xattr, and the app terminates itself.
5. Next Dock click launches the new build.

Updates only happen when the UI is frictionless (no open windows). There is no polling,
no toast, no prompt. A `BuildInfo.commitHash == "dev"` build (i.e. anything not produced by
`scripts/build-release.sh`) skips the updater entirely.

**For agents:** do not invoke the updater manually. If a user is on an old build, either
wait for them to restart, or reinstall using the snippet above.

## Build from source

```bash
swift build              # debug, ad-hoc signed (BuildInfo.commitHash == "dev", no auto-update)
swift run mdLens         # run directly from the command line
```

## Release (maintainer / agent with push access)

The working tree must be clean — the release script derives the commit hash from `HEAD`
and refuses to build otherwise.

```bash
git push                                   # publish the commit first
./scripts/build-release.sh                 # builds, injects BuildInfo, signs, notarizes, zips
HASH=$(git rev-parse --short=7 HEAD)
gh release create "build-$HASH" \
    --repo jaewooseo-bagelcode/mdLens \
    --title "build-$HASH" \
    --notes "Build $HASH" \
    "/tmp/mdLens-build-$HASH-arm64.zip"
```

Every existing client running an older build will pull this release on next launch.

### One-time setup
Notarization keychain profile (stored on the maintainer's Mac only):
```bash
xcrun notarytool store-credentials notarytool-profile \
    --apple-id <APPLE_ID> --team-id 5FK7UUGMX3 --password <APP_SPECIFIC_PASSWORD>
```
If the profile is absent, `build-release.sh` skips notarization — the resulting zip will
still be Developer ID signed but Gatekeeper will warn on first launch.

## Source map

```
Sources/MarkdownViewer/
├── App/           MarkdownViewerApp, AppState, AppCommands
├── Models/        MarkdownDocument, FileTreeNode, OutlineItem, DocumentStats
├── Services/      MarkdownRenderer, OutlineParser, EmojiMap, FileService,
│                  BuildInfo (generated), Updater
├── Views/         ContentView, DocumentView, sidebar/settings/quick-open
├── Theme/         AppTheme
└── Extensions/    String+Extensions (htmlEscaped, slugified, SlugGenerator)
```

Rendering pipeline is in `MarkdownRenderer.swift`: front matter extraction → link/emoji
preprocess → swift-markdown AST → custom `HTMLVisitor` → HTML wrapped with CSS, KaTeX,
Mermaid, highlight.js (all CDN, loaded only when features are detected).

## License

MIT
