import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// @Polymorphable macro implementation
///
/// Generates Polymorphable protocol conformance for a protocol definition.
/// Enables multiple Persistable types to share a directory and indexes.
///
/// **Generated code includes**:
/// - `static var polymorphableType: String`
/// - `static var directoryPathComponents: [any DirectoryPathElement]`
/// - `static var directoryLayer: DirectoryLayer`
/// - `static var indexDescriptors: [IndexDescriptor]`
///
/// **Usage**:
/// ```swift
/// @Polymorphable
/// protocol Document {
///     var id: String { get }
///     var title: String { get }
///
///     #Directory<Document>("app", "documents")
///     #Index<Document>(ScalarIndexKind(fields: [\.title]), name: "Document_title")
/// }
/// ```
public struct PolymorphableMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Extract protocol name
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage("@Polymorphable can only be applied to protocols")
                )
            ])
        }

        let protocolName = protocolDecl.name.text

        // Extract #Index macro calls and generate IndexDescriptors
        var indexDescriptors: [String] = []

        for member in protocolDecl.memberBlock.members {
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Index" {

                var keyPaths: [String] = []
                var indexKindExpr: String?
                var isUnique = false
                var indexName: String?

                for arg in macroDecl.arguments {
                    // First unlabeled argument: IndexKind expression
                    if arg.label == nil {
                        if let funcCall = arg.expression.as(FunctionCallExprSyntax.self) {
                            // Extract KeyPaths from function arguments
                            for funcArg in funcCall.arguments {
                                if let arrayExpr = funcArg.expression.as(ArrayExprSyntax.self) {
                                    for element in arrayExpr.elements {
                                        if let keyPathExpr = element.expression.as(KeyPathExprSyntax.self) {
                                            let keyPathString = extractKeyPathString(from: keyPathExpr)
                                            if !keyPathString.isEmpty {
                                                keyPaths.append(keyPathString)
                                            }
                                        }
                                    }
                                } else if let keyPathExpr = funcArg.expression.as(KeyPathExprSyntax.self) {
                                    let keyPathString = extractKeyPathString(from: keyPathExpr)
                                    if !keyPathString.isEmpty {
                                        keyPaths.append(keyPathString)
                                    }
                                }
                            }

                            indexKindExpr = arg.expression.description.trimmingCharacters(in: .whitespaces)
                        }
                    }
                    // "unique:" argument
                    else if let label = arg.label, label.text == "unique" {
                        if let boolExpr = arg.expression.as(BooleanLiteralExprSyntax.self) {
                            isUnique = boolExpr.literal.text == "true"
                        }
                    }
                    // "name:" argument
                    else if let label = arg.label, label.text == "name" {
                        if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                            indexName = segment.content.text
                        }
                    }
                }

                guard !keyPaths.isEmpty else { continue }

                // Generate index name if not provided
                let finalIndexName: String
                if let customName = indexName {
                    finalIndexName = customName
                } else {
                    let flattenedKeyPaths = keyPaths.map { $0.replacingOccurrences(of: ".", with: "_") }
                    finalIndexName = "\(protocolName)_\(flattenedKeyPaths.joined(separator: "_"))"
                }

                // Generate IndexDescriptor with fieldNames (not keyPaths, since protocol has no concrete type)
                let fieldNames = keyPaths.map { "\"\($0)\"" }.joined(separator: ", ")
                let kindInit = indexKindExpr ?? "ScalarIndexKind(fieldNames: [])"

                // Convert IndexKind to use fieldNames instead of KeyPaths
                let convertedKindInit = convertIndexKindToFieldNames(kindInit, keyPaths: keyPaths)
                let optionsInit = isUnique ? ".init(unique: true)" : ".init()"

                let descriptorInit = """
                    IndexDescriptor(
                        name: "\(finalIndexName)",
                        fieldNames: [\(fieldNames)],
                        kind: \(convertedKindInit),
                        commonOptions: \(optionsInit)
                    )
                """

                indexDescriptors.append(descriptorInit)
            }
        }

        // Extract #Directory macro call
        var directoryPathComponents: [String] = []
        var directoryLayerValue: String = ".default"

        for member in protocolDecl.memberBlock.members {
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Directory" {

                for arg in macroDecl.arguments {
                    // Check for "layer:" argument
                    if let label = arg.label, label.text == "layer" {
                        if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                            directoryLayerValue = ".\(memberAccess.declName.baseName.text)"
                        }
                        continue
                    }

                    let expr = arg.expression

                    // String literal → Path("value")
                    if let stringLiteral = expr.as(StringLiteralExprSyntax.self),
                       let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                        let pathValue = segment.content.text
                        directoryPathComponents.append("Path(\"\(pathValue)\")")
                        continue
                    }

                    // Field(\.property) is NOT allowed for polymorphic protocols
                    if let functionCall = expr.as(FunctionCallExprSyntax.self) {
                        let calledExpr = functionCall.calledExpression.description.trimmingCharacters(in: .whitespaces)
                        if calledExpr == "Field" {
                            throw DiagnosticsError(diagnostics: [
                                Diagnostic(
                                    node: Syntax(functionCall),
                                    message: MacroExpansionErrorMessage(
                                        "Field path components are not allowed in @Polymorphable protocols. " +
                                        "Use only static Path components (string literals)."
                                    )
                                )
                            ])
                        }
                    }
                }
                break
            }
        }

        // MemberMacro: Don't generate members in the protocol itself
        // All implementations are provided via ExtensionMacro below
        return []
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Get protocol name
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            return []
        }
        let protocolName = protocolDecl.name.text

        // Parse #Directory and #Index macros from protocol body
        var directoryPathComponents: [String] = []
        var directoryLayerValue: String = ".default"
        var indexDescriptors: [String] = []

        for member in protocolDecl.memberBlock.members {
            // Check for #Directory freestanding macro
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Directory" {
                (directoryPathComponents, directoryLayerValue) = parseDirectoryMacro(macroDecl)
            }

            // Check for #Index freestanding macro
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Index" {
                if let indexDesc = parseIndexMacro(macroDecl, protocolName: protocolName) {
                    indexDescriptors.append(indexDesc)
                }
            }
        }

        // Build extension body with implementations
        var extensionBody: [String] = []

        // polymorphableType
        extensionBody.append("""
            public static var polymorphableType: String { "\(protocolName)" }
        """)

        // polymorphicDirectoryPathComponents - shared directory for all conforming types
        if !directoryPathComponents.isEmpty {
            let componentsArray = directoryPathComponents.joined(separator: ", ")
            extensionBody.append("""
                public static var polymorphicDirectoryPathComponents: [any DirectoryPathElement] { [\(componentsArray)] }
            """)
        } else {
            // Default: use polymorphableType as path
            extensionBody.append("""
                public static var polymorphicDirectoryPathComponents: [any DirectoryPathElement] { [Path(polymorphableType)] }
            """)
        }

        // polymorphicDirectoryLayer
        // Use Core.DirectoryLayer to disambiguate from FoundationDB.DirectoryLayer
        extensionBody.append("""
            public static var polymorphicDirectoryLayer: Core.DirectoryLayer { \(directoryLayerValue) }
        """)

        // polymorphicIndexDescriptors
        if !indexDescriptors.isEmpty {
            let descriptorsArray = indexDescriptors.joined(separator: ",\n            ")
            extensionBody.append("""
                public static var polymorphicIndexDescriptors: [IndexDescriptor] {
                    [
                        \(descriptorsArray)
                    ]
                }
            """)
        }

        // Generate extension with implementations
        // Note: The protocol must explicitly inherit from Polymorphable
        // e.g., `protocol Document: Polymorphable { ... }`
        // This extension only provides default implementations
        let bodyString = extensionBody.joined(separator: "\n    ")
        let conformanceExt: DeclSyntax = """
            extension \(type.trimmed) {
                \(raw: bodyString)
            }
            """

        if let extensionDecl = conformanceExt.as(ExtensionDeclSyntax.self) {
            return [extensionDecl]
        }

        return []
    }
}

// MARK: - Helper Functions

/// Extract field name from KeyPath expression
private func extractKeyPathString(from keyPathExpr: KeyPathExprSyntax) -> String {
    var pathComponents: [String] = []
    for component in keyPathExpr.components {
        if let property = component.component.as(KeyPathPropertyComponentSyntax.self) {
            pathComponents.append(property.declName.baseName.text)
        }
    }
    return pathComponents.joined(separator: ".")
}

/// Convert IndexKind expression to use fieldNames instead of KeyPaths
/// e.g., ScalarIndexKind<Document>(fields: [\.title]) → ScalarIndexKind(fieldNames: ["title"])
private func convertIndexKindToFieldNames(_ kindInit: String, keyPaths: [String]) -> String {
    // Extract the IndexKind name (before the generic or opening paren)
    let kindName: String
    if let genericStart = kindInit.firstIndex(of: "<") {
        kindName = String(kindInit[..<genericStart])
    } else if let parenStart = kindInit.firstIndex(of: "(") {
        kindName = String(kindInit[..<parenStart])
    } else {
        kindName = kindInit
    }

    // Generate fieldNames array
    let fieldNamesArray = keyPaths.map { "\"\($0)\"" }.joined(separator: ", ")

    return "\(kindName)(fieldNames: [\(fieldNamesArray)])"
}

/// Parse #Directory macro and extract path components and layer
private func parseDirectoryMacro(_ macroDecl: MacroExpansionDeclSyntax) -> (components: [String], layer: String) {
    var directoryPathComponents: [String] = []
    var directoryLayerValue: String = ".default"

    for arg in macroDecl.arguments {
        // Check for "layer:" argument
        if let label = arg.label, label.text == "layer" {
            if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                directoryLayerValue = ".\(memberAccess.declName.baseName.text)"
            }
            continue
        }

        let expr = arg.expression

        // String literal → Path("value")
        if let stringLiteral = expr.as(StringLiteralExprSyntax.self),
           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
            let pathValue = segment.content.text
            directoryPathComponents.append("Path(\"\(pathValue)\")")
        }
    }

    return (directoryPathComponents, directoryLayerValue)
}

/// Parse #Index macro and generate IndexDescriptor string
private func parseIndexMacro(_ macroDecl: MacroExpansionDeclSyntax, protocolName: String) -> String? {
    var keyPaths: [String] = []
    var indexKindExpr: String?
    var isUnique = false
    var indexName: String?

    for arg in macroDecl.arguments {
        // First unlabeled argument: IndexKind expression
        if arg.label == nil {
            if let funcCall = arg.expression.as(FunctionCallExprSyntax.self) {
                // Extract KeyPaths from function arguments
                for funcArg in funcCall.arguments {
                    if let arrayExpr = funcArg.expression.as(ArrayExprSyntax.self) {
                        for element in arrayExpr.elements {
                            if let keyPathExpr = element.expression.as(KeyPathExprSyntax.self) {
                                let keyPathString = extractKeyPathString(from: keyPathExpr)
                                if !keyPathString.isEmpty {
                                    keyPaths.append(keyPathString)
                                }
                            }
                        }
                    } else if let keyPathExpr = funcArg.expression.as(KeyPathExprSyntax.self) {
                        let keyPathString = extractKeyPathString(from: keyPathExpr)
                        if !keyPathString.isEmpty {
                            keyPaths.append(keyPathString)
                        }
                    }
                }

                indexKindExpr = arg.expression.description.trimmingCharacters(in: .whitespaces)
            }
        }
        // "unique:" argument
        else if let label = arg.label, label.text == "unique" {
            if let boolExpr = arg.expression.as(BooleanLiteralExprSyntax.self) {
                isUnique = boolExpr.literal.text == "true"
            }
        }
        // "name:" argument
        else if let label = arg.label, label.text == "name" {
            if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                indexName = segment.content.text
            }
        }
    }

    guard !keyPaths.isEmpty else { return nil }

    // Generate index name if not provided
    let finalIndexName: String
    if let customName = indexName {
        finalIndexName = customName
    } else {
        let flattenedKeyPaths = keyPaths.map { $0.replacingOccurrences(of: ".", with: "_") }
        finalIndexName = "\(protocolName)_\(flattenedKeyPaths.joined(separator: "_"))"
    }

    // Generate IndexDescriptor with fieldNames (not keyPaths, since protocol has no concrete type)
    let fieldNames = keyPaths.map { "\"\($0)\"" }.joined(separator: ", ")
    let kindInit = indexKindExpr ?? "ScalarIndexKind(fieldNames: [])"

    // Convert IndexKind to use fieldNames instead of KeyPaths
    let convertedKindInit = convertIndexKindToFieldNames(kindInit, keyPaths: keyPaths)
    let optionsInit = isUnique ? ".init(unique: true)" : ".init()"

    return """
        IndexDescriptor(
            name: "\(finalIndexName)",
            fieldNames: [\(fieldNames)],
            kind: \(convertedKindInit),
            commonOptions: \(optionsInit)
        )
    """
}
