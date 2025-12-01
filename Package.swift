// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "DatabaseKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Vector", targets: ["Vector"]),
        .library(name: "FullText", targets: ["FullText"]),
        .library(name: "Spatial", targets: ["Spatial"]),
        .library(name: "Rank", targets: ["Rank"]),
        .library(name: "Permuted", targets: ["Permuted"]),
        .library(name: "Graph", targets: ["Graph"]),
        .library(name: "DatabaseKit", targets: ["DatabaseKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"602.0.0"),
    ],
    targets: [
        .target(name: "Core", dependencies: ["CoreMacros"]),
        .macro(
            name: "CoreMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "Vector", dependencies: ["Core"]),
        .target(name: "FullText", dependencies: ["Core"]),
        .target(name: "Spatial", dependencies: ["Core"]),
        .target(name: "Rank", dependencies: ["Core"]),
        .target(name: "Permuted", dependencies: ["Core"]),
        .target(name: "Graph", dependencies: ["Core"]),
        .target(
            name: "DatabaseKit",
            dependencies: ["Core", "Vector", "FullText", "Spatial", "Rank", "Permuted", "Graph"]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ],
    swiftLanguageModes: [.v6]
)
