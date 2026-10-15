// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Yimiao",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Yimiao", path: "Sources/Yimiao"),
        .testTarget(name: "YimiaoTests", dependencies: ["Yimiao"])
    ]
)
