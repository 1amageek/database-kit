import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// @Polymorphable macro implementation
///
/// Generates polymorphic group metadata for a protocol definition.
/// Enables multiple Persistable types to share a directory and indexes.
/// The protocol must explicitly inherit from `Polymorphable`; Swift does not
/// allow an attached macro to add protocol inheritance through an extension.
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
/// protocol Document: Polymorphable {
///     var id: String { get }
///     var title: String { get }
///
///     #Directory<Self>("app", "documents")
///     #Index(ScalarIndexKind<Self>(fields: [\Self.title]), name: "Document_title")
/// }
/// ```
public struct PolymorphableMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // @Polymorphable can only be applied to protocols
        guard declaration.is(ProtocolDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage("@Polymorphable can only be applied to protocols")
                )
            ])
        }
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self),
              protocolDecl.inheritsPolymorphable else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "@Polymorphable protocols must explicitly inherit from Polymorphable"
                    )
                )
            ])
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
        guard protocolDecl.inheritsPolymorphable else {
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

private extension ProtocolDeclSyntax {
    var inheritsPolymorphable: Bool {
        inheritanceClause?.inheritedTypes.contains { inheritedType in
            let name = inheritedType.type.trimmedDescription
            return name == "Polymorphable" || name.hasSuffix(".Polymorphable")
        } ?? false
    }
}

private func collectKeyPathStrings(from expression: ExprSyntax) -> [String] {
    if let arrayExpr = expression.as(ArrayExprSyntax.self) {
        return arrayExpr.elements.compactMap { element in
            guard let keyPathExpr = element.expression.as(KeyPathExprSyntax.self) else {
                return nil
            }
            let keyPathString = extractKeyPathString(from: keyPathExpr)
            return keyPathString.isEmpty ? nil : keyPathString
        }
    }
    if let keyPathExpr = expression.as(KeyPathExprSyntax.self) {
        let keyPathString = extractKeyPathString(from: keyPathExpr)
        return keyPathString.isEmpty ? [] : [keyPathString]
    }
    return []
}

/// Rewrite protocol-level index expressions so generated descriptors are
/// materialized per concrete conforming type.
///
/// `#Index<Document>(ScalarIndexKind<Document>(fields: [\.title]))` becomes
/// `ScalarIndexKind<Self>(fields: [\Self.title])` inside `extension Document`.
private func rewriteIndexKindExpression(
    _ expression: String,
    protocolName: String
) -> String {
    expression
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "<\(protocolName)>", with: "<Self>")
        .replacingOccurrences(of: "<\(protocolName),", with: "<Self,")
        .replacingOccurrences(of: "\\\(protocolName).", with: "\\Self.")
        .replacingOccurrences(of: "\\.", with: "\\Self.")
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
    var storedFieldKeyPaths: [String] = []
    var indexKindExpr: String?
    var isUnique = false
    var indexName: String?

    for arg in macroDecl.arguments {
        // First unlabeled argument: IndexKind expression
        if arg.label == nil {
            if let funcCall = arg.expression.as(FunctionCallExprSyntax.self) {
                // Extract KeyPaths from function arguments
                for funcArg in funcCall.arguments {
                    keyPaths.append(contentsOf: collectKeyPathStrings(from: funcArg.expression))
                }

                indexKindExpr = arg.expression.description.trimmingCharacters(in: .whitespaces)
            }
        }
        // "storedFields:" argument
        else if let label = arg.label, label.text == "storedFields" {
            storedFieldKeyPaths.append(contentsOf: collectKeyPathStrings(from: arg.expression))
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

    let keyPathsLiterals = keyPaths.map { "\\Self.\($0)" }.joined(separator: ", ")
    let kindInit = rewriteIndexKindExpression(
        indexKindExpr ?? "ScalarIndexKind(fields: [])",
        protocolName: protocolName
    )
    let optionsInit = isUnique ? ".init(unique: true)" : ".init()"

    if storedFieldKeyPaths.isEmpty {
        return """
            IndexDescriptor(
                name: "\(finalIndexName)",
                keyPaths: [\(keyPathsLiterals)],
                kind: \(kindInit),
                commonOptions: \(optionsInit)
            )
        """
    }

    let storedKeyPathsLiterals = storedFieldKeyPaths.map { "\\Self.\($0)" }.joined(separator: ", ")
    let storedFieldNamesLiterals = storedFieldKeyPaths.map { "\"\($0)\"" }.joined(separator: ", ")
    return """
        IndexDescriptor(
            name: "\(finalIndexName)",
            keyPaths: [\(keyPathsLiterals)],
            kind: \(kindInit),
            commonOptions: \(optionsInit),
            storedKeyPaths: [\(storedKeyPathsLiterals)],
            storedFieldNames: [\(storedFieldNamesLiterals)]
        )
    """
}
