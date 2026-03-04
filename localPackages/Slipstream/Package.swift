// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Slipstream",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Slipstream",
            targets: ["SlipstreamC"]
        )
    ],
    targets: [
        .target(
            name: "SlipstreamC",
            dependencies: [
                .target(name: "slipstream-client")
            ],
            path: "Sources/C",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .binaryTarget(
            name: "slipstream-client",
            path: "Frameworks/slipstream-client.xcframework"
        ),
    ]
)
