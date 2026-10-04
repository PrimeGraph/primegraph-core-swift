// swift-tools-version:6.4
import PackageDescription

// Tools version 6.x builds the package in the Swift 6 language mode, as every
// generated package is built. The platforms are exactly the five the generated
// packages declare — watchOS is absent there because firebase-ios-sdk ships no
// watchOS Firestore slice — so this package never promises a platform none of
// its consumers can reach. The floors are the lowest the code allows; the
// generated packages raise their own floors as their SDK dependencies require.
let package = Package(
    name: "PrimeGraphCore",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .macCatalyst(.v15),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "PrimeGraphCore",
            targets: ["PrimeGraphCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PrimeGraphCore",
            path: "Sources/PrimeGraphCore"
        ),
        .testTarget(
            name: "PrimeGraphCoreTests",
            dependencies: ["PrimeGraphCore"],
            path: "Tests/PrimeGraphCoreTests"
        ),
    ]
)
