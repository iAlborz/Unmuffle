// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Unmuffle",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Unmuffle",
            path: "Sources/Unmuffle",
            linkerSettings: [
                .linkedFramework("AVKit"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
