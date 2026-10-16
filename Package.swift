// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ouch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        // TODO: point at https://github.com/noxaur/mackeys-sdk once its per-key views (MacKeyCap, MacKeyboardDeckView) ship in a release.
        .package(path: "/Users/per/Code/noxaur/mackeys-sdk-perkey"),
    ],
    targets: [
        .executableTarget(
            name: "ouch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MacKeysCore", package: "mackeys-sdk-perkey"),
                .product(name: "MacKeysUI", package: "mackeys-sdk-perkey"),
            ],
            path: "Sources/ouch",
            // build.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
