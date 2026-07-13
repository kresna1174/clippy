// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipboardManager",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
        .package(url: "https://github.com/krisk/fuse-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClipboardManager",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Fuse", package: "fuse-swift"),
            ],
            path: "Sources",
            exclude: ["App/ClipboardManager.entitlements"]
        )
    ]
)
