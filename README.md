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

The updater splits download and install across launches so the app never swaps its own
bundle while running (that races with teardown). On launch the app runs `Updater.swift`:

**Stage (background, this launch):**
1. Locates `gh` at `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, or `/usr/bin/gh`. If none
   are executable → skip silently.
2. `gh release view ... -q .tagName` → compare the `build-<hash>` suffix to
   `BuildInfo.commitHash`.
3. If different, downloads + unzips the new `.app` into
   `~/Library/Application Support/mdLens/updates/<tag>/`, verifies its code signature and
   Team ID match the running app, and records a pointer in `UserDefaults`. Nothing is
   swapped this session.

**Apply (next launch):**
4. If a verified staged build is pending, the app spawns a detached helper
   (`/tmp/mdlens-update-swap.sh`) that waits for the app's PID to exit, then atomically
   swaps `/Applications/mdLens.app` (old moved aside → new moved in → old removed; rollback
   on failure), clears the quarantine xattr, and relaunches.

So an update fetched during one session installs the next time the app exits and is
reopened — deterministically, via a process that outlives the app. No polling, no toast,
no prompt, no window-close race. A `BuildInfo.commitHash == "dev"` build (anything not
produced by `scripts/build-release.sh`) skips the updater entirely.

**Bootstrap note:** because the *installed* app's updater performs the swap, a fix to the
updater itself only takes effect one release later — the transition *to* the fixed build may
need a manual install (replace `/Applications/mdLens.app` with the release zip's `.app`).

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
Sources/
├── MarkdownCore/        shared lib: MarkdownRenderer, EmojiMap, AppThemeMode,
│                        String+Extensions — used by BOTH the app and the QL extension
├── MarkdownViewer/      app executable (target `mdLens`)
│   ├── App/             MarkdownViewerApp (DocumentGroup), AppSettings, AppCommands, FocusedValues
│   ├── Models/          MarkdownFileDocument (read-only FileDocument; .md + .html)
│   ├── Services/        DocumentStats, BuildInfo (generated), Updater
│   ├── Slack/           opt-in 👀 ingestion: SlackController, SocketModeClient, SlackAPI,
│   │                    Keychain, ManifestService, SlackConfig, SlackSetupView, SlackMenuView
│   └── Views/           DocumentView (root + raw-.html path), StatusBarView, SettingsView
└── QuickLookExtension/  the `mdLensQL.appex` (QLPreviewingController + WKWebView via MarkdownCore)
```

Three SwiftPM targets: `MarkdownCore` (lib), `mdLens` (app), `mdLensQL` (Quick Look `.appex`,
embedded + separately signed by the build scripts).

The app is a `DocumentGroup(viewing:)` — one window per file, independent per-window state,
no shared document singleton. `AppSettings` (@Observable, UserDefaults-backed) holds the only
cross-window state (theme, fontSize).

Rendering pipeline is in `MarkdownCore/MarkdownRenderer.swift`: front matter extraction → link/emoji
preprocess → swift-markdown AST → custom `HTMLVisitor` → HTML wrapped with CSS, KaTeX,
Mermaid, highlight.js (all CDN, loaded only when features are detected).

## License

MIT
