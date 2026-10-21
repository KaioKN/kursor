// swift-tools-version: 6.0
import PackageDescription

// Swift 5 language mode: the event-tap core is confined to one dedicated thread
// and talks to C callbacks; strict Sendable checking adds noise without safety there.
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Kursor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Kursor", targets: ["Kursor"]),
    ],
    targets: [
        .target(
            name: "KursorSPI",
            path: "Sources/KursorSPI",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .target(
            name: "KursorCore",
            dependencies: ["KursorSPI"],
            path: "Sources/KursorCore",
            swiftSettings: swift5,
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .executableTarget(
            name: "Kursor",
            dependencies: ["KursorCore"],
            path: "Sources/Kursor",
            swiftSettings: swift5,
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .testTarget(
            name: "KursorCoreTests",
            dependencies: ["KursorCore"],
            path: "Tests/KursorCoreTests",
            resources: [.copy("Fixtures")],
            swiftSettings: swift5
        ),
    ]
)
