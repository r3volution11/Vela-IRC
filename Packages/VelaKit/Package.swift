// swift-tools-version: 6.2
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PackageDescription

let mainActorByDefault: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "VelaKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "VelaUI", targets: ["VelaUI"]),
        .library(name: "VelaCore", targets: ["VelaCore"]),
        .library(name: "VelaIRC", targets: ["VelaIRC"]),
        .library(name: "VelaTheme", targets: ["VelaTheme"]),
        .library(name: "VelaMedia", targets: ["VelaMedia"]),
        .library(name: "VelaStore", targets: ["VelaStore"]),
        .library(name: "VelaIntelligence", targets: ["VelaIntelligence"]),
        .library(name: "VelaIntents", targets: ["VelaIntents"]),
        .executable(name: "vela-theme-tool", targets: ["VelaThemeTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        // Shared, dependency-free helpers (JSONC, file watching).
        .target(name: "VelaFoundation"),

        // IRC protocol, connection, IRCv3 negotiation. No UI, no persistence.
        .target(name: "VelaIRC"),

        // Persistence: SQLite scrollback, settings.json, network configs, Keychain.
        .target(
            name: "VelaStore",
            dependencies: [
                "VelaFoundation",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        // Theme engine: token registry, loading, VS Code import, live reload.
        .target(
            name: "VelaTheme",
            dependencies: [
                "VelaFoundation",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [.copy("BuiltInThemes")]
        ),

        // Inline media: link detection, classification, previews, images.
        .target(
            name: "VelaMedia",
            resources: [.copy("Resources/adult-domains.txt")]
        ),

        // App-level models that tie IRC, storage and media together.
        .target(
            name: "VelaCore",
            dependencies: ["VelaIRC", "VelaStore", "VelaMedia", "VelaFoundation"],
            swiftSettings: mainActorByDefault
        ),

        // Apple Intelligence on this Mac: Catch me up summaries (Foundation
        // Models), message translation (Translation, NaturalLanguage).
        .target(
            name: "VelaIntelligence",
            dependencies: ["VelaCore", "VelaIRC", "VelaStore", "VelaFoundation"],
            swiftSettings: mainActorByDefault
        ),

        // Siri, Shortcuts and Spotlight: App Intents and entities.
        .target(
            name: "VelaIntents",
            dependencies: ["VelaCore", "VelaIntelligence", "VelaStore"],
            swiftSettings: mainActorByDefault
        ),

        // SwiftUI views and scenes. Resources/AppIcons holds the Dock icons
        // (design/app-icon/build.sh writes them).
        .target(
            name: "VelaUI",
            dependencies: ["VelaCore", "VelaTheme", "VelaMedia", "VelaIRC", "VelaStore", "VelaIntelligence", "VelaIntents"],
            resources: [.copy("Resources/AppIcons")],
            swiftSettings: mainActorByDefault
        ),

        // Generates schemas/vela-theme.schema.json and the docs token table.
        .executableTarget(name: "VelaThemeTool", dependencies: ["VelaTheme"]),

        .testTarget(name: "VelaFoundationTests", dependencies: ["VelaFoundation"]),
        .testTarget(name: "VelaIRCTests", dependencies: ["VelaIRC"]),
        .testTarget(name: "VelaStoreTests", dependencies: ["VelaStore"]),
        .testTarget(
            name: "VelaThemeTests",
            dependencies: ["VelaTheme"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "VelaMediaTests",
            dependencies: ["VelaMedia"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "VelaCoreTests", dependencies: ["VelaCore", "VelaIRC"]),
        .testTarget(
            name: "VelaIntelligenceTests",
            dependencies: ["VelaIntelligence", "VelaCore"],
            swiftSettings: mainActorByDefault
        ),
        .testTarget(
            name: "VelaIntentsTests",
            dependencies: ["VelaIntents", "VelaCore", "VelaStore"],
            swiftSettings: mainActorByDefault
        ),
        .testTarget(
            name: "VelaUITests",
            dependencies: ["VelaUI", "VelaCore", "VelaStore", "VelaTheme", "VelaIRC"],
            swiftSettings: mainActorByDefault
        ),
    ]
)
