// swift-tools-version: 6.4
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "database-kit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "DatabaseValue", targets: ["DatabaseValue"]),
        .library(name: "DatabaseValueCodable", targets: ["DatabaseValueCodable"]),
        .library(name: "DatabaseDigest", targets: ["DatabaseDigest"]),
        .library(name: "Core", targets: ["Core"]),
        .library(name: "DatabaseWire", targets: ["DatabaseWire"]),
        .library(name: "Relationship", targets: ["Relationship"]),
        .library(name: "Vector", targets: ["Vector"]),
        .library(name: "FullText", targets: ["FullText"]),
        .library(name: "Geospatial", targets: ["Geospatial"]),
        .library(name: "Rank", targets: ["Rank"]),
        .library(name: "Permuted", targets: ["Permuted"]),
        .library(name: "Graph", targets: ["Graph"]),
        .library(name: "DatabaseKit", targets: ["DatabaseKit"]),
        .library(name: "QueryIR", targets: ["QueryIR"]),
        .library(name: "QueryIRFoundation", targets: ["QueryIRFoundation"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    ],
    targets: [
        .target(name: "DatabaseValue", dependencies: []),
        .target(name: "DatabaseValueCodable", dependencies: ["DatabaseValue"]),
        .target(name: "DatabaseDigest", dependencies: ["DatabaseValue"]),
        .target(
            name: "DatabaseWire",
            dependencies: ["DatabaseDigest", "DatabaseValue", "QueryIR"]
        ),
        .target(
            name: "Core",
            dependencies: ["CoreMacros", "DatabaseValue", "DatabaseValueCodable"]
        ),
        .target(name: "Relationship", dependencies: ["Core", "RelationshipMacros"]),
        .macro(
            name: "CoreMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .macro(
            name: "RelationshipMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "QueryIR", dependencies: ["DatabaseValue"]),
        .target(name: "QueryIRFoundation", dependencies: ["QueryIR", "DatabaseValue"]),
        .target(name: "Vector", dependencies: ["Core"]),
        .target(name: "FullText", dependencies: ["Core"]),
        .target(name: "Geospatial", dependencies: ["Core"]),
        .target(name: "Rank", dependencies: ["Core"]),
        .target(name: "Permuted", dependencies: ["Core"]),
        .macro(
            name: "GraphMacros",
            dependencies: [
                "DatabaseValue",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Graph",
            dependencies: ["Core", "DatabaseValue", "DatabaseValueCodable", "GraphMacros"]
        ),
        .target(
            name: "DatabaseKit",
            dependencies: ["Core", "Vector", "FullText", "Geospatial", "Rank", "Permuted", "Graph"]
        ),
        .testTarget(
            name: "DatabaseDigestTests",
            dependencies: ["DatabaseDigest", "DatabaseValue"]
        ),
        .testTarget(
            name: "DatabaseWireTests",
            dependencies: [
                "DatabaseValue",
                "DatabaseWire",
                "QueryIR",
            ]
        ),
        .testTarget(
            name: "DatabaseValueCodableTests",
            dependencies: ["DatabaseValue", "DatabaseValueCodable"]
        ),
        .testTarget(
            name: "DatabaseValueTests",
            dependencies: ["DatabaseValue"]
        ),
        .testTarget(
            name: "GraphValueTests",
            dependencies: ["DatabaseValue", "Graph"]
        ),
        .testTarget(
            name: "QueryIRFoundationTests",
            dependencies: [
                "DatabaseValue",
                "QueryIR",
                "QueryIRFoundation",
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                "CoreMacros",
                "DatabaseValue",
                "GraphMacros",
                "Vector",
                "FullText",
                "Geospatial",
                "Rank",
                "Permuted",
                "Graph",
                "Relationship",
                "QueryIR",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
