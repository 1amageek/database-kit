// swift-tools-version: 6.4
import PackageDescription
import CompilerPluginSupport

// The verification harness supplies the selected Embedded SDK archive only for
// its executable lane. Target scoping keeps host macro linkage unchanged.
let queryValueRuntimeLinkerSettings: [LinkerSetting]
if let archive = Context.environment["DATABASE_KIT_QUERY_VALUE_UNICODE_ARCHIVE"], !archive.isEmpty {
    queryValueRuntimeLinkerSettings = [
        .unsafeFlags(["-Xlinker", archive], .when(platforms: [.wasi])),
    ]
} else {
    queryValueRuntimeLinkerSettings = []
}

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
            from: "26.0730.0"
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
            exclude: [
                "DESIGN.md",
                "Model/DESIGN.md",
                "Query/DESIGN.md",
                "Query/SQL/DESIGN.md",
                "Query/SQL/DDL/DESIGN.md",
                "Schema/DESIGN.md",
                "Schema/SQLCatalog/DESIGN.md",
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
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "DatabaseWire",
            dependencies: [
                "DatabaseKit",
                .product(name: "DatabaseTypes", package: "database-types"),
            ],
            exclude: ["DESIGN.md"],
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
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "DatabaseSchemaJSON",
            dependencies: [
                "DatabaseKit",
                "DatabaseWire",
                .product(name: "DatabaseTypes", package: "database-types"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "DatabaseKitDeclarationContract",
            dependencies: [
                "DatabaseKit",
                .product(name: "DatabaseTypes", package: "database-types"),
            ],
            path: "Tests/DatabaseKitDeclarationContract"
        ),
        .executableTarget(
            name: "QueryValueRuntimeContract",
            dependencies: [
                "DatabaseKit",
                "DatabaseWire",
                .product(name: "DatabaseTypes", package: "database-types"),
            ],
            path: "Tests/QueryValueRuntimeContract",
            exclude: ["run.mjs"],
            swiftSettings: [
                .define("DATABASE_KIT_MULTI_BASE", .when(traits: ["MultiBase"])),
            ],
            linkerSettings: queryValueRuntimeLinkerSettings
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
