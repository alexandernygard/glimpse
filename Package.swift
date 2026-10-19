// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Glimpse",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Glimpse",
            path: "Sources/Glimpse",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
