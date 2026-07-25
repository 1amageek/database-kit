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
/// - `static var directoryPathComponents: [DirectoryPathComponent]`
/// - `static var directoryLayer: DirectoryLayer`
/// - `static var polymorphicIndexes: [PolymorphicIndexDefinition]`
///
/// **Usage**:
/// ```swift
/// @Polymorphable
/// protocol Document: Polymorphable {
///     var id: String { get }
///     var title: String { get }
///
///     #Directory<Self>("app", "documents")
///     #PolymorphicIndex(
///         .scalar,
///         fields: ["title"],
///         name: "Document_title"
///     )
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
        let protocolFieldNames: Set<String> = Set(
            protocolDecl.memberBlock.members.compactMap { member -> String? in
                guard
                    let variable = member.decl.as(VariableDeclSyntax.self),
                    let binding = variable.bindings.first,
                    let identifier = binding.pattern.as(
                        IdentifierPatternSyntax.self
                    )
                else {
                    return nil
                }
                return identifier.identifier.text
            }
        )

        // Parse directory and polymorphic-index declarations.
        var directoryPathComponents: [String] = []
        var directoryLayerValue: String = ".default"
        var indexDefinitions: [ExprSyntax] = []

        for member in protocolDecl.memberBlock.members {
            // Check for #Directory freestanding macro
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Directory" {
                (directoryPathComponents, directoryLayerValue) = parseDirectoryMacro(macroDecl)
            }

            // Check for #PolymorphicIndex freestanding macro.
            if let macroDecl = member.decl.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "PolymorphicIndex" {
                indexDefinitions.append(
                    try parseIndexMacro(
                        macroDecl,
                        protocolName: protocolName,
                        protocolFieldNames: protocolFieldNames
                    )
                )
            }
        }

        // Build extension members as independent syntax nodes so SwiftSyntax owns
        // indentation and trivia for each declaration.
        var extensionMembers: [DeclSyntax] = []

        // polymorphableType
        extensionMembers.append("""
            public static var polymorphableType: String { "\(raw: protocolName)" }
        """)

        // polymorphicDirectoryPathComponents - shared directory for all conforming types
        if !directoryPathComponents.isEmpty {
            let componentsArray = directoryPathComponents.joined(separator: ", ")
            extensionMembers.append("""
                public static var polymorphicDirectoryPathComponents: [DirectoryPathComponent] { [\(raw: componentsArray)] }
            """)
        } else {
            // Default: use polymorphableType as path
            extensionMembers.append("""
                public static var polymorphicDirectoryPathComponents: [DirectoryPathComponent] { [.staticPath(polymorphableType)] }
            """)
        }

        // polymorphicDirectoryLayer
        // Qualify the semantic directory policy emitted into the client module.
        extensionMembers.append("""
            public static var polymorphicDirectoryLayer: DatabaseKit.DirectoryLayer { \(raw: directoryLayerValue) }
        """)

        // polymorphicIndexes
        if !indexDefinitions.isEmpty {
            let definitionsArray = ArrayExprSyntax {
                for (index, definition) in indexDefinitions.enumerated() {
                    ArrayElementSyntax(
                        leadingTrivia: .spaces(4),
                        expression: definition.trimmed,
                        trailingComma: index == indexDefinitions.index(before: indexDefinitions.endIndex)
                            ? nil
                            : .commaToken(trailingTrivia: .newline)
                    )
                }
            }
            .with(\.leftSquare, .leftSquareToken(trailingTrivia: .newline))
            .with(\.rightSquare, .rightSquareToken(leadingTrivia: .newline))
            extensionMembers.append("""
                public static var polymorphicIndexes: [PolymorphicIndexDefinition] {
                    \(definitionsArray)
                }
            """)
        }

        // Generate extension with implementations
        // Note: The protocol must explicitly inherit from Polymorphable
        // e.g., `protocol Document: Polymorphable { ... }`
        // This extension only provides default implementations
        let extensionDecl = try ExtensionDeclSyntax("extension \(type.trimmed)") {
            for member in extensionMembers {
                member
            }
        }
        return [extensionDecl]
    }
}

// MARK: - Helper Functions

private extension ProtocolDeclSyntax {
    var inheritsPolymorphable: Bool {
        inheritanceClause?.inheritedTypes.contains { inheritedType in
            let name = inheritedType.type.trimmedDescription
            return name == "Polymorphable" || name.hasSuffix(".Polymorphable")
        } ?? false
    }
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

        // Compile a string literal into a canonical static path component.
        if let stringLiteral = expr.as(StringLiteralExprSyntax.self),
           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
            let pathValue = segment.content.text
            directoryPathComponents.append(".staticPath(\"\(pathValue)\")")
        }
    }

    return (directoryPathComponents, directoryLayerValue)
}

/// Compile a protocol index declaration into a logical definition.
private func parseIndexMacro(
    _ macroDecl: MacroExpansionDeclSyntax,
    protocolName: String,
    protocolFieldNames: Set<String>
) throws -> ExprSyntax {
    var fieldsByRole: [String: [String]] = [:]
    var storedFieldKeyPaths: [String] = []
    var fieldOrders: [String] = []
    var definition: ParsedIndexDefinition?
    var definitionExpression: String?
    var isUnique = false
    var indexName: String?

    for arg in macroDecl.arguments {
        if arg.label == nil {
            definition = parseIndexDefinition(arg.expression)
            definitionExpression = arg.expression.description
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let label = arg.label,
                  label.text == "storedFields"
                    || label.text == "storedFieldNames" {
            let stringFields = collectStringLiterals(from: arg.expression)
            storedFieldKeyPaths.append(
                contentsOf: stringFields.isEmpty
                    ? collectKeyPathStrings(from: arg.expression)
                    : stringFields
            )
        } else if let label = arg.label, label.text == "orders" {
            if let orders = arg.expression.as(ArrayExprSyntax.self) {
                fieldOrders = orders.elements.map {
                    $0.expression.description.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                }
            }
        } else if let label = arg.label, label.text == "unique" {
            if let boolExpr = arg.expression.as(BooleanLiteralExprSyntax.self) {
                isUnique = boolExpr.literal.text == "true"
            }
        } else if let label = arg.label, label.text == "name" {
            if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                indexName = segment.content.text
            }
        } else if let label = arg.label {
            let role: String
            switch label.text {
            case "fieldNames": role = "fields"
            case "groupByNames": role = "groupBy"
            case "valueName": role = "value"
            case "fieldName": role = "field"
            case "embeddingName": role = "embedding"
            case "locationName": role = "location"
            case "fromName": role = "from"
            case "edgeName": role = "edge"
            case "toName": role = "to"
            case "graphName": role = "graph"
            default: role = label.text
            }
            let stringFields = collectStringLiterals(from: arg.expression)
            fieldsByRole[role] = stringFields.isEmpty
                ? collectKeyPathStrings(from: arg.expression)
                : stringFields
        }
    }

    guard let definition, let definitionExpression else {
        throw DiagnosticsError(diagnostics: [
            Diagnostic(
                node: Syntax(macroDecl),
                message: MacroExpansionErrorMessage(
                    "#Index requires an IndexDefinition case"
                )
            )
        ])
    }
    let keyPaths = try selectedIndexFieldPaths(
        definition: definition,
        roles: fieldsByRole,
        node: Syntax(macroDecl)
    )
    try validateIndexFieldOrders(
        definition: definition,
        roles: fieldsByRole,
        orders: fieldOrders,
        node: Syntax(macroDecl)
    )
    for keyPath in keyPaths + storedFieldKeyPaths {
        guard !keyPath.contains(".") else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(macroDecl),
                    message: MacroExpansionErrorMessage(
                        "Polymorphic index field '\(keyPath)' must identify one protocol property"
                    )
                )
            ])
        }
        guard protocolFieldNames.contains(keyPath) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(macroDecl),
                    message: MacroExpansionErrorMessage(
                        "Polymorphic index field '\(keyPath)' is not declared by protocol '\(protocolName)'"
                    )
                )
            ])
        }
    }

    let finalIndexName: String
    if let customName = indexName {
        finalIndexName = customName
    } else {
        let flattenedKeyPaths = keyPaths.map { $0.replacingOccurrences(of: ".", with: "_") }
        finalIndexName = generateIndexName(
            typeName: protocolName,
            definition: definition,
            fieldNames: flattenedKeyPaths
        )
    }

    let compiledFields = keyPaths.enumerated().map { offset, fieldName in
        let order: String
        if !fieldOrders.isEmpty {
            order = fieldOrders[offset]
        } else if definition.name == "rank"
                    || (definition.name == "timeWindowLeaderboard"
                        && offset == keyPaths.index(before: keyPaths.endIndex)) {
            order = ".descending"
        } else {
            order = ".ascending"
        }
        return "PolymorphicIndexField(name: \"\(fieldName)\", order: \(order))"
    }
    .joined(separator: ", ")
    let optionsInit = isUnique ? ".init(unique: true)" : ".init()"
    let storedFieldNames = storedFieldKeyPaths
        .map { "\"\($0)\"" }
        .joined(separator: ", ")
    let expression: ExprSyntax = """
        PolymorphicIndexDefinition(
            name: "\(raw: finalIndexName)",
            definition: \(raw: definitionExpression),
            fields: [\(raw: compiledFields)],
            commonOptions: \(raw: optionsInit),
            storedFieldNames: [\(raw: storedFieldNames)]
        )
    """
    return expression
}

private func collectStringLiterals(
    from expression: ExprSyntax
) -> [String] {
    if let literal = expression.as(StringLiteralExprSyntax.self),
       let segment = literal.segments.first?.as(StringSegmentSyntax.self) {
        return [segment.content.text]
    }
    guard let array = expression.as(ArrayExprSyntax.self) else {
        return []
    }
    return array.elements.compactMap { element in
        guard
            let literal = element.expression.as(StringLiteralExprSyntax.self),
            let segment = literal.segments.first?.as(StringSegmentSyntax.self)
        else {
            return nil
        }
        return segment.content.text
    }
}
