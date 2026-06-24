// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mdLens",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        // Shared rendering pipeline used by both the app and the Quick Look extension.
        .target(
            name: "MarkdownCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/MarkdownCore",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "mdLens",
            dependencies: ["MarkdownCore"],
            path: "Sources/MarkdownViewer",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        // Quick Look preview extension: renders .md/.html via MarkdownCore + WKWebView.
        .executableTarget(
            name: "mdLensQL",
            dependencies: ["MarkdownCore"],
            path: "Sources/QuickLookExtension",
            exclude: ["Info.plist", "QuickLook.entitlements"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
