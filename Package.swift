// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clippy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
        .package(url: "https://github.com/krisk/fuse-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Clippy",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Fuse", package: "fuse-swift"),
            ],
            path: "Sources",
            exclude: ["App/Clippy.entitlements", "App/Info.plist"]
        )
    ]
)
