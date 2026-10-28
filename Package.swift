// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Unmuffle",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Updates for the GitHub version. The App Store version is built from the Xcode project without it.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "Unmuffle",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Unmuffle",
            linkerSettings: [
                .linkedFramework("AVKit"),
                .linkedFramework("AVFoundation"),
                // build.sh copies Sparkle.framework into Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        )
    ]
)
