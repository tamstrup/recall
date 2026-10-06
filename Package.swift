// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Recall",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Recall", targets: ["Recall"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0")
    ],
    targets: [
        .executableTarget(name: "Recall", dependencies: [
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
            .product(name: "SpeakerKit", package: "argmax-oss-swift")
        ]),
        .testTarget(name: "RecallTests", dependencies: ["Recall"])
    ],
    swiftLanguageModes: [.v5]
)
