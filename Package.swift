// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NemoVoiceTyping",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NemoVoiceTyping", targets: ["NemoVoiceTyping"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.16.0")
    ],
    targets: [
        .executableTarget(
            name: "NemoVoiceTyping",
            dependencies: [
                "HotKey",
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")
            ],
            path: "NemoVoiceTyping",
            resources: [
                // We can add asset resources here if needed
            ]
        )
    ]
)
