// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IslandBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IslandBar", targets: ["IslandBarApp"]),
    ],
    targets: [
        // Shared models, settings, persistence, state machines and feature contracts. No UI.
        .target(name: "IslandCore"),

        // Themes, animation engine, shared SwiftUI components and the module UI contract.
        .target(name: "IslandDesign", dependencies: ["IslandCore"]),

        // Platform integrations shared by features: Core Audio queries, running-app resolution.
        .target(name: "IslandPlatform"),

        // Real-time audio mixing and equaliser, in C so the audio thread never touches the
        // Swift runtime.
        .target(name: "IslandAudioDSP", linkerSettings: [.linkedFramework("CoreAudio")]),

        // NSPanel lifecycle, display detection, notch geometry and positioning.
        .target(name: "IslandWindows", dependencies: ["IslandCore"]),

        // Feature modules. Each depends only on Core, Design and Platform, never on each other.
        .target(name: "FeatureMedia", dependencies: ["IslandCore", "IslandDesign"]),
        .target(name: "FeatureFileShelf", dependencies: ["IslandCore", "IslandDesign"]),
        .target(name: "FeatureFocus", dependencies: ["IslandCore", "IslandDesign"]),
        .target(name: "FeatureSystemMonitor", dependencies: ["IslandCore", "IslandDesign"]),
        .target(name: "FeatureDeveloper", dependencies: ["IslandCore", "IslandDesign"]),
        .target(name: "FeatureNotifications", dependencies: ["IslandCore", "IslandDesign"]),
        .target(name: "FeaturePrivacyIndicators", dependencies: ["IslandCore", "IslandDesign", "IslandPlatform"]),
        .target(name: "FeatureMirror", dependencies: ["IslandCore", "IslandDesign"]),
        .target(name: "FeatureBluetooth", dependencies: ["IslandCore", "IslandDesign", "IslandPlatform"]),
        .target(name: "FeatureCaffeinate", dependencies: ["IslandCore", "IslandDesign"]),
        .target(name: "FeatureAudioMixer", dependencies: ["IslandCore", "IslandDesign", "IslandPlatform", "IslandAudioDSP"]),

        // Application entry point, menu bar, settings UI. Composition root.
        .executableTarget(
            name: "IslandBarApp",
            dependencies: [
                "IslandCore", "IslandDesign", "IslandWindows",
                "FeatureMedia", "FeatureFileShelf", "FeatureFocus",
                "FeatureSystemMonitor", "FeatureDeveloper", "FeatureNotifications",
                "FeaturePrivacyIndicators", "FeatureMirror",
                "FeatureBluetooth", "FeatureCaffeinate", "FeatureAudioMixer",
            ]
        ),

        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandWindowsTests", dependencies: ["IslandWindows"]),
        .testTarget(
            name: "FeatureTests",
            dependencies: [
                "IslandCore", "FeatureMedia", "FeatureFileShelf", "FeatureFocus",
                "FeatureSystemMonitor", "FeatureDeveloper", "FeaturePrivacyIndicators",
                "IslandPlatform", "IslandAudioDSP", "FeatureBluetooth", "FeatureCaffeinate", "FeatureAudioMixer",
            ]
        ),
    ]
)
