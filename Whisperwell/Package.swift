// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Whisperwell",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Whisperwell", targets: ["Whisperwell"]),
    ],
    dependencies: [
        // On-device Whisper speech-to-text (MIT). Only the app target uses it.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
    ],
    targets: [
        // Pure logic: audio encoding, API clients, prompt building. Unit tested.
        .target(name: "WhisperwellCore"),
        // macOS glue: menu bar, hotkey, microphone, Accessibility, paste, on-device speech.
        .executableTarget(
            name: "Whisperwell",
            dependencies: [
                "WhisperwellCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(name: "WhisperwellCoreTests", dependencies: ["WhisperwellCore"]),
    ]
)
