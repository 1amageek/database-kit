import DatabaseTypes
import Testing
import Foundation

@Suite("Package Boundary Tests")
struct PackageBoundaryTests {
    @Test("Canonical targets exclude platform and Codable contracts")
    func canonicalTargetsExcludePlatformAndCodableContracts() throws {
        let root = Self.packageRoot()
        let canonicalRoots = [
            root.appendingPathComponent("Sources/DatabaseKit"),
            root.appendingPathComponent("Sources/DatabaseWire"),
        ]
        let forbiddenImports: Set<String> = [
            "Foundation",
            "FoundationEssentials",
            "DatabaseTypesFoundation",
        ]
        let forbiddenConformanceFragments = [
            ": Codable",
            ", Codable",
            ": Encodable",
            ", Encodable",
            ": Decodable",
            ", Decodable",
        ]

        var violations: [String] = []
        for canonicalRoot in canonicalRoots {
            for file in try Self.swiftFiles(under: canonicalRoot) {
                let text = try String(contentsOf: file, encoding: .utf8)
                let relativePath = Self.relativePath(file, from: root)
                for (lineIndex, lineSlice) in text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .enumerated() {
                    let line = String(lineSlice)
                    if let module = Self.importedModuleName(from: line),
                       forbiddenImports.contains(module) {
                        violations.append(
                            "\(relativePath):\(lineIndex + 1) imports \(module)"
                        )
                    }
                    for fragment in forbiddenConformanceFragments
                    where line.contains(fragment) {
                        violations.append(
                            "\(relativePath):\(lineIndex + 1) contains \(fragment)"
                        )
                    }
                }
            }
        }

        #expect(
            violations.isEmpty,
            "Canonical targets must remain Foundation- and Codable-independent: \(violations.joined(separator: ", "))"
        )
    }

    @Test("Sources keep storage and runtime backends out of database-kit")
    func sourcesDoNotImportBackendRuntimeModules() throws {
        let root = Self.packageRoot()
        let sourceFiles = try Self.swiftFiles(under: root.appendingPathComponent("Sources"))
        let forbiddenModules: Set<String> = [
            "StorageKit",
            "DatabaseEngine",
            "FDBStorage",
            "SQLiteStorage",
            "PostgreSQLStorage"
        ]

        var violations: [String] = []
        for file in sourceFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            let relativePath = Self.relativePath(file, from: root)

            for (lineIndex, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                guard let module = Self.importedModuleName(from: String(line)),
                      forbiddenModules.contains(module) else {
                    continue
                }
                violations.append("\(relativePath):\(lineIndex + 1) imports \(module)")
            }
        }

        #expect(
            violations.isEmpty,
            "database-kit must not import storage or runtime backend modules: \(violations.joined(separator: ", "))"
        )
    }

    @Test("Sources do not declare framework-owned execution models")
    func sourcesDoNotDeclareExecutionModels() throws {
        let root = Self.packageRoot()
        let sourceFiles = try Self.swiftFiles(
            under: root.appendingPathComponent("Sources")
        )
        let forbiddenDeclarations: Set<String> = [
            "AlternativePlan",
            "ChangeType",
            "CollectionStatistics",
            "DiffError",
            "DiffOptions",
            "FieldChange",
            "GraphIndexScanPlanner",
            "HyperLogLog",
            "HyperLogLogError",
            "IndexError",
            "IndexBuildState",
            "IndexStatistics",
            "ModelDiff",
            "PlanType",
            "PermutedIndexError",
            "QueryExecutionStats",
            "QueryPlan",
            "RelationshipSnapshot",
            "Snapshot",
            "VersionInfo",
        ]

        var violations: [String] = []
        for file in sourceFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            let relativePath = Self.relativePath(file, from: root)
            for (lineIndex, line) in text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                guard let declaration = Self.declaredTypeName(
                    from: String(line)
                ),
                forbiddenDeclarations.contains(declaration) else {
                    continue
                }
                violations.append(
                    "\(relativePath):\(lineIndex + 1) declares \(declaration)"
                )
            }
        }

        #expect(
            violations.isEmpty,
            "database-kit must not own planning, execution, or runtime statistics: \(violations.joined(separator: ", "))"
        )
    }

    @Test("Sources do not restore superseded value or codec contracts")
    func sourcesDoNotDeclareSupersededContracts() throws {
        let root = Self.packageRoot()
        let sourceFiles = try Self.swiftFiles(
            under: root.appendingPathComponent("Sources")
        )
        let forbiddenDeclarations: Set<String> = [
            "DatabaseObjectField",
            "DatabaseEmpty",
            "DatabaseExecutionBudget",
            "DatabaseGraphTerm",
            "DatabaseRevisionMutationResult",
            "DatabaseValidationReport",
            "FormerIndex",
            "IndexMetadataValue",
            "OWLLiteral",
            "ProtobufDecoder",
            "ProtobufEncoder",
            "QueryParameterValue",
            "ServiceEnvelope",
        ]

        var violations: [String] = []
        for file in sourceFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            let relativePath = Self.relativePath(file, from: root)
            for (lineIndex, line) in text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                guard let declaration = Self.declaredTypeName(
                    from: String(line)
                ),
                forbiddenDeclarations.contains(declaration) else {
                    continue
                }
                violations.append(
                    "\(relativePath):\(lineIndex + 1) declares \(declaration)"
                )
            }
        }

        #expect(
            violations.isEmpty,
            "database-kit has one FieldValue algebra and one canonical binary protocol: \(violations.joined(separator: ", "))"
        )
    }

    @Test("Only responsibility modules are public products")
    func onlyResponsibilityModulesArePublicProducts() throws {
        let root = Self.packageRoot()
        let packageText = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let sourceFiles = try Self.swiftFiles(
            under: root.appendingPathComponent("Sources")
        )
        let supersededModuleNames = [
            "Database" + "Value",
            "Database" + "ValueCodable",
            "Database" + "Model",
            "Database" + "Codable",
            "Core",
            "QueryIR",
            "QueryIRFoundation",
            "Relationship",
            "Vector",
            "FullText",
            "Geospatial",
            "Rank",
            "Permuted",
            "Graph",
            "DatabaseDigest",
        ]

        var violations: [String] = []
        for moduleName in supersededModuleNames {
            if packageText.contains("\"\(moduleName)\"") {
                violations.append("Package.swift declares \(moduleName)")
            }
            if FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Sources")
                    .appendingPathComponent(moduleName)
                    .path
            ) {
                violations.append("Sources/\(moduleName) exists")
            }
        }

        for file in sourceFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            let relativePath = Self.relativePath(file, from: root)
            for (lineIndex, line) in text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                guard let module = Self.importedModuleName(from: String(line)),
                      supersededModuleNames.contains(module) else {
                    continue
                }
                violations.append(
                    "\(relativePath):\(lineIndex + 1) imports \(module)"
                )
            }
        }

        #expect(
            violations.isEmpty,
            "Feature products must be folded into their responsibility module: \(violations.joined(separator: ", "))"
        )
    }

    @Test("DatabaseKitTests declares direct dependencies for imported local modules")
    func databaseKitTestsDeclaresDirectDependenciesForImportedLocalModules() throws {
        let root = Self.packageRoot()
        let localModules = try Self.localModuleNames(root: root)
        let testFiles = try Self.swiftFiles(
            under: root.appendingPathComponent("Tests/DatabaseKitTests")
        )
        let packageText = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let dependencyBlock = try Self.databaseKitTestsDependencyBlock(
            from: packageText
        )
        let declaredDependencies = Self.quotedStrings(in: dependencyBlock)

        var importedModules: Set<String> = []
        for file in testFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                if let module = Self.importedModuleName(from: String(line)),
                   localModules.contains(module) {
                    importedModules.insert(module)
                }
            }
        }

        let missing = importedModules.subtracting(declaredDependencies)

        #expect(
            missing.isEmpty,
            "DatabaseKitTests must declare direct dependencies for imported local modules: \(missing.sorted().joined(separator: ", "))"
        )
    }

    private static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true, file.pathExtension == "swift" {
                files.append(file)
            }
        }
        return files
    }

    private static func localModuleNames(root: URL) throws -> Set<String> {
        let sourceRoot = root.appendingPathComponent("Sources")
        let children = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var names: Set<String> = []
        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                names.insert(child.lastPathComponent)
            }
        }
        return names
    }

    private static func importedModuleName(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let importPrefix = "import "
        let testableImportPrefix = "@testable import "

        let remainder: Substring
        if trimmed.hasPrefix(importPrefix) {
            remainder = trimmed.dropFirst(importPrefix.count)
        } else if trimmed.hasPrefix(testableImportPrefix) {
            remainder = trimmed.dropFirst(testableImportPrefix.count)
        } else {
            return nil
        }

        return remainder.split(separator: " ").first.map(String.init)
    }

    private static func declaredTypeName(from line: String) -> String? {
        let tokens = line
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
        guard let declarationIndex = tokens.firstIndex(where: {
            $0 == "struct" || $0 == "enum" || $0 == "class"
                || $0 == "actor" || $0 == "protocol" || $0 == "typealias"
        }),
        declarationIndex + 1 < tokens.count else {
            return nil
        }
        return String(
            tokens[declarationIndex + 1]
                .prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
        )
    }

    private static func databaseKitTestsDependencyBlock(
        from packageText: String
    ) throws -> String {
        let targetStart = try #require(
            packageText.range(of: "name: \"DatabaseKitTests\"")?.lowerBound
        )
        let tail = packageText[targetStart...]
        let targetEnd = try #require(tail.range(of: "\n        ),")?.lowerBound)
        return String(tail[..<targetEnd])
    }

    private static func quotedStrings(in text: String) -> Set<String> {
        var values: Set<String> = []
        var searchStart = text.startIndex

        while let openingQuote = text[searchStart...].firstIndex(of: "\"") {
            let valueStart = text.index(after: openingQuote)
            guard let closingQuote = text[valueStart...].firstIndex(of: "\"") else {
                break
            }
            values.insert(String(text[valueStart..<closingQuote]))
            searchStart = text.index(after: closingQuote)
        }

        return values
    }

    private static func relativePath(_ file: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            return filePath
        }
        return String(filePath.dropFirst(prefix.count))
    }
}
