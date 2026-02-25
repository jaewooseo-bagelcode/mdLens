// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mdLens",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "mdLens",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/MarkdownViewer",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
