import Testing
import Foundation

@Suite("Package Boundary Tests")
struct PackageBoundaryTests {

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

    @Test("CoreTests declares direct dependencies for imported local modules")
    func coreTestsDeclaresDirectDependenciesForImportedLocalModules() throws {
        let root = Self.packageRoot()
        let localModules = try Self.localModuleNames(root: root)
        let testFiles = try Self.swiftFiles(under: root.appendingPathComponent("Tests/CoreTests"))
        let packageText = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let dependencyBlock = try Self.coreTestsDependencyBlock(from: packageText)
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
            "CoreTests must declare direct dependencies for imported local modules: \(missing.sorted().joined(separator: ", "))"
        )
    }

    private static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
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

    private static func coreTestsDependencyBlock(from packageText: String) throws -> String {
        let targetStart = try #require(packageText.range(of: "name: \"CoreTests\"")?.lowerBound)
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
