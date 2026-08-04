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
            name: "DatabaseKitFoundation",
            targets: ["DatabaseKitFoundation"]
        ),
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
                .product(
                    name: "SwiftSyntaxMacroExpansion",
                    package: "swift-syntax"
                ),
                .product(
                    name: "SwiftSyntaxMacrosTestSupport",
                    package: "swift-syntax"
                ),
            ]
        ),
        .testTarget(
            name: "DatabaseWireTests",
            dependencies: [
                "DatabaseKit",
                "DatabaseWire",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
        .testTarget(
            name: "DatabaseKitFoundationTests",
            dependencies: [
                "DatabaseKit",
                "DatabaseKitFoundation",
                .product(name: "DatabaseTypes", package: "database-types"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
