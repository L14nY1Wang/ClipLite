// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipLite",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipLite",
            path: "Sources/ClipLite"
        )
    ]
)
