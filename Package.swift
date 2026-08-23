// swift-tools-version:5.9
import PackageDescription

// PrimeGraphCore is pure Swift with no Firebase or transport dependency, so it
// can and does declare every Apple platform. The floors are the lowest the code
// allows; the generated packages that depend on it raise their own floors as
// their SDK dependencies require.
let package = Package(
    name: "PrimeGraphCore",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
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
