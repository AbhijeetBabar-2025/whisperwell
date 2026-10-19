// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlowLite",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FlowLite", targets: ["FlowLite"]),
    ],
    dependencies: [
        // On-device Whisper speech-to-text (MIT). Only the app target uses it.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
    ],
    targets: [
        // Pure logic: audio encoding, API clients, prompt building. Unit tested.
        .target(name: "FlowLiteCore"),
        // macOS glue: menu bar, hotkey, microphone, Accessibility, paste, on-device speech.
        .executableTarget(
            name: "FlowLite",
            dependencies: [
                "FlowLiteCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(name: "FlowLiteCoreTests", dependencies: ["FlowLiteCore"]),
    ]
)
