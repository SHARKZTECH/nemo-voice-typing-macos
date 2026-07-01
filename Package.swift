// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NemoVoiceTyping",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NemoVoiceTyping", targets: ["NemoVoiceTyping"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3")
    ],
    targets: [
        .executableTarget(
            name: "NemoVoiceTyping",
            dependencies: [
                "HotKey"
            ],
            path: "NemoVoiceTyping",
            resources: [
                // We can add asset resources here if needed
            ]
        )
    ]
)
