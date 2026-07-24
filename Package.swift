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
        .package(
            url: "https://github.com/1amageek/database-types.git",
            branch: "main"
        ),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    ],
    targets: [
        .target(
            name: "DatabaseValue",
            dependencies: [
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "DatabaseValueCodable",
            dependencies: [
                "DatabaseValue",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "DatabaseDigest",
            dependencies: [
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "DatabaseWire",
            dependencies: [
                "DatabaseDigest",
                "DatabaseValue",
                "QueryIR",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "Core",
            dependencies: [
                "CoreMacros",
                "DatabaseValue",
                "DatabaseValueCodable",
                .product(name: "DatabaseTypes", package: "database-types"),
                .product(
                    name: "DatabaseTypesFoundation",
                    package: "database-types"
                ),
            ]
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
        .target(
            name: "QueryIR",
            dependencies: [
                "DatabaseValue",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "QueryIRFoundation",
            dependencies: [
                "QueryIR",
                "DatabaseValue",
                .product(
                    name: "DatabaseTypesFoundation",
                    package: "database-types"
                ),
            ]
        ),
        .target(
            name: "Vector",
            dependencies: [
                "Core",
                "DatabaseValue",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "FullText",
            dependencies: [
                "Core",
                "DatabaseValue",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "Geospatial",
            dependencies: [
                "Core",
                "DatabaseValue",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "Rank",
            dependencies: [
                "Core",
                "DatabaseValue",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "Permuted",
            dependencies: [
                "Core",
                "DatabaseValue",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .macro(
            name: "GraphMacros",
            dependencies: [
                .product(name: "DatabaseTypes", package: "database-types"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Graph",
            dependencies: [
                "Core",
                "DatabaseValue",
                "DatabaseValueCodable",
                "GraphMacros",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "DatabaseKit",
            dependencies: ["Core", "Vector", "FullText", "Geospatial", "Rank", "Permuted", "Graph"]
        ),
        .testTarget(
            name: "DatabaseDigestTests",
            dependencies: [
                "DatabaseDigest",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .testTarget(
            name: "DatabaseWireTests",
            dependencies: [
                "DatabaseValue",
                "DatabaseWire",
                "QueryIR",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .testTarget(
            name: "DatabaseValueCodableTests",
            dependencies: [
                "DatabaseValue",
                "DatabaseValueCodable",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .testTarget(
            name: "DatabaseValueTests",
            dependencies: [
                "DatabaseValue",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .testTarget(
            name: "GraphValueTests",
            dependencies: [
                "DatabaseValue",
                "Graph",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .testTarget(
            name: "QueryIRFoundationTests",
            dependencies: [
                "DatabaseValue",
                "QueryIR",
                "QueryIRFoundation",
                .product(name: "DatabaseTypes", package: "database-types"),
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
                .product(name: "DatabaseTypes", package: "database-types"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
