// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-acoustics-string",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Acoustics String", targets: ["Acoustics String"])
    ],
    dependencies: [
        .package(url: "https://github.com/swift-molecules/swift-acoustics.git", branch: "main"),
        .package(url: "https://github.com/swift-molecules/swift-acoustics-resonator.git", branch: "main"),
        .package(url: "https://github.com/swift-molecules/swift-contact.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-decay.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-density.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-friction.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-frequency.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-loss.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-numeric.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-rigidity.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-velocity.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-viscosity.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-wavenumber.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Acoustics String",
            dependencies: [
                .product(name: "Acoustics", package: "swift-acoustics"),
                .product(name: "Acoustics Resonator", package: "swift-acoustics-resonator"),
                .product(name: "Contact", package: "swift-contact"),
                .product(name: "Decay", package: "swift-decay"),
                .product(name: "Density", package: "swift-density"),
                .product(name: "Friction", package: "swift-friction"),
                .product(name: "Frequency", package: "swift-frequency"),
                .product(name: "Loss", package: "swift-loss"),
                .product(name: "Numeric", package: "swift-numeric"),
                .product(name: "Rigidity", package: "swift-rigidity"),
                .product(name: "Velocity", package: "swift-velocity"),
                .product(name: "Viscosity", package: "swift-viscosity"),
                .product(name: "Wavenumber", package: "swift-wavenumber"),
            ]
        ),
        .testTarget(
            name: "Acoustics String Tests",
            dependencies: [
                .product(name: "Wavenumber", package: "swift-wavenumber"),
                .target(name: "Acoustics String"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings =
        (target.swiftSettings ?? []) + [
            .strictMemorySafety(),
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault"),
            .enableUpcomingFeature("MemberImportVisibility"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .enableExperimentalFeature("Lifetimes"),
            .treatAllWarnings(as: .error),
        ]
}
