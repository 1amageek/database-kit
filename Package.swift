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
        .library(name: "DatabaseKit", targets: ["DatabaseKit"]),
        .library(name: "DatabaseWire", targets: ["DatabaseWire"]),
        .library(
            name: "DatabaseSchemaJSON",
            targets: ["DatabaseSchemaJSON"]
        ),
        .library(
            name: "DatabaseKitFoundation",
            targets: ["DatabaseKitFoundation"]
        ),
    ],
    traits: [
        .trait(name: "MultiBase"),
    ],
    dependencies: [
        .package(
            url: "https://github.com/1amageek/database-types.git",
            revision: "6ff1742926d6618e44eb9f6c0ef2a2719c88c645"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            from: "603.0.2"
        ),
    ],
    targets: [
        .target(
            name: "DatabaseKit",
            dependencies: [
                "DatabaseKitMacros",
                .product(name: "DatabaseTypes", package: "database-types"),
            ],
            swiftSettings: [
                .define(
                    "DATABASE_KIT_MULTI_BASE",
                    .when(traits: ["MultiBase"])
                ),
            ]
        ),
        .macro(
            name: "DatabaseKitMacros",
            dependencies: [
                .product(name: "DatabaseTypes", package: "database-types"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "DatabaseWire",
            dependencies: [
                "DatabaseKit",
                .product(name: "DatabaseTypes", package: "database-types"),
            ],
            swiftSettings: [
                .define(
                    "DATABASE_KIT_MULTI_BASE",
                    .when(traits: ["MultiBase"])
                ),
            ]
        ),
        .target(
            name: "DatabaseKitFoundation",
            dependencies: [
                "DatabaseKit",
                .product(
                    name: "DatabaseTypes",
                    package: "database-types"
                ),
                .product(
                    name: "DatabaseTypesFoundation",
                    package: "database-types"
                ),
            ]
        ),
        .target(
            name: "DatabaseSchemaJSON",
            dependencies: [
                "DatabaseKit",
                "DatabaseWire",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .target(
            name: "DatabaseKitDeclarationContract",
            dependencies: [
                "DatabaseKit",
                .product(name: "DatabaseTypes", package: "database-types"),
            ],
            path: "Tests/DatabaseKitDeclarationContract"
        ),
        .testTarget(
            name: "DatabaseKitTests",
            dependencies: [
                "DatabaseKit",
                "DatabaseKitMacros",
                .product(name: "DatabaseTypes", package: "database-types"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(
                    name: "SwiftSyntaxMacroExpansion",
                    package: "swift-syntax"
                ),
                .product(
                    name: "SwiftSyntaxMacrosTestSupport",
                    package: "swift-syntax"
                ),
            ],
            swiftSettings: [
                .define(
                    "DATABASE_KIT_MULTI_BASE",
                    .when(traits: ["MultiBase"])
                ),
            ]
        ),
        .testTarget(
            name: "DatabaseWireTests",
            dependencies: [
                "DatabaseKit",
                "DatabaseWire",
                .product(name: "DatabaseTypes", package: "database-types"),
            ],
            swiftSettings: [
                .define(
                    "DATABASE_KIT_MULTI_BASE",
                    .when(traits: ["MultiBase"])
                ),
            ]
        ),
        .testTarget(
            name: "DatabaseKitFoundationTests",
            dependencies: [
                "DatabaseKit",
                "DatabaseKitFoundation",
                .product(name: "DatabaseTypes", package: "database-types"),
            ],
            swiftSettings: [
                .define(
                    "DATABASE_KIT_MULTI_BASE",
                    .when(traits: ["MultiBase"])
                ),
            ]
        ),
        .testTarget(
            name: "DatabaseSchemaJSONTests",
            dependencies: [
                "DatabaseKit",
                "DatabaseSchemaJSON",
                "DatabaseWire",
                .product(name: "DatabaseTypes", package: "database-types"),
            ],
            swiftSettings: [
                .define(
                    "DATABASE_KIT_MULTI_BASE",
                    .when(traits: ["MultiBase"])
                ),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
