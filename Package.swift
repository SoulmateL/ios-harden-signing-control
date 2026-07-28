// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ios-harden-signing-control",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SigningControlCore", targets: ["SigningControlCore"]),
        .executable(
            name: "ios-harden-actions-signer",
            targets: ["ios-harden-actions-signer"]
        )
    ],
    targets: [
        .target(name: "SigningControlCore"),
        .executableTarget(
            name: "ios-harden-actions-signer",
            dependencies: ["SigningControlCore"]
        ),
        .testTarget(
            name: "SigningControlCoreTests",
            dependencies: ["SigningControlCore"]
        )
    ]
)
