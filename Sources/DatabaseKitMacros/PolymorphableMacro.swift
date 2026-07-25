import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// @Polymorphable macro implementation
///
/// Generates a concrete polymorphic group declaration. The annotated protocol
/// binds that declaration in its `Polymorphable<Group>` inheritance clause.
///
/// **Generated code includes**:
/// - A concrete `{ProtocolName}PolymorphicGroup` metadata declaration
///
/// **Usage**:
/// ```swift
/// @Polymorphable
/// @PolymorphicDirectory("app", "documents")
/// @PolymorphicIndex(
///     .scalar,
///     fields: ["title"],
///     name: "Document_title"
/// )
/// protocol Document: Polymorphable<DocumentPolymorphicGroup> {
///     var id: String { get }
///     var title: String { get }
/// }
/// ```
public struct PolymorphableMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            return []
        }
        let protocolName = protocolDecl.name.text
        let declarationName = "\(protocolName)PolymorphicGroup"
        guard protocolDecl.polymorphicGroupType == declarationName else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "@Polymorphable protocol '\(protocolName)' must inherit from Polymorphable<\(declarationName)>"
                    )
                )
            ])
        }
        let access = protocolDecl.modifiers.first { modifier in
            switch modifier.name.tokenKind {
            case .keyword(.public), .keyword(.package):
                return true
            default:
                return false
            }
        }?.name.text
        let accessPrefix = access.map { "\($0) " } ?? ""
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

        var foundDirectory = false
        for element in protocolDecl.attributes {
            guard
                let attribute = element.as(AttributeSyntax.self),
                let arguments = attribute.arguments?.as(
                    LabeledExprListSyntax.self
                )
            else {
                continue
            }
            let attributeName = attribute.attributeName.trimmedDescription
                .split(separator: ".")
                .last
                .map(String.init)
            if attributeName == "PolymorphicDirectory" {
                guard !foundDirectory else {
                    throw DiagnosticsError(diagnostics: [
                        Diagnostic(
                            node: Syntax(attribute),
                            message: MacroExpansionErrorMessage(
                                "A polymorphic protocol can declare only one @PolymorphicDirectory"
                            )
                        )
                    ])
                }
                foundDirectory = true
                (directoryPathComponents, directoryLayerValue) =
                    try parseDirectoryArguments(
                        arguments,
                        node: Syntax(attribute)
                    )
            } else if attributeName == "PolymorphicIndex" {
                indexDefinitions.append(
                    try parseIndexArguments(
                        arguments,
                        node: Syntax(attribute),
                        protocolName: protocolName,
                        protocolFieldNames: protocolFieldNames
                    )
                )
            }
        }

        let componentsExpression: String
        if !directoryPathComponents.isEmpty {
            componentsExpression = "[\(directoryPathComponents.joined(separator: ", "))]"
        } else {
            componentsExpression = "[.staticPath(identifier)]"
        }

        let indexesExpression: String
        if indexDefinitions.isEmpty {
            indexesExpression = "[]"
        } else {
            let definitions = indexDefinitions
                .map(\.trimmedDescription)
                .joined(separator: ",\n")
            indexesExpression = "[\n\(definitions)\n]"
        }

        let declaration: DeclSyntax = """
            \(raw: accessPrefix)enum \(raw: declarationName): DatabaseKit.PolymorphicGroupDeclaration {
                \(raw: accessPrefix)static let identifier = "\(raw: protocolName)"

                \(raw: accessPrefix)static let directoryComponents: [DatabaseKit.DirectoryPathComponent] = \(raw: componentsExpression)

                \(raw: accessPrefix)static let directoryLayer: DatabaseKit.DirectoryLayer = \(raw: directoryLayerValue)

                \(raw: accessPrefix)static let indexes: [DatabaseKit.PolymorphicIndexDefinition] = \(raw: indexesExpression)
            }
            """
        return [declaration]
    }
}

// MARK: - Helper Functions

private extension ProtocolDeclSyntax {
    var polymorphicGroupType: String? {
        for inheritedType in inheritanceClause?.inheritedTypes ?? [] {
            let spelling = inheritedType.type.trimmedDescription
                .replacingOccurrences(of: " ", with: "")
            guard
                let markerRange = spelling.range(
                    of: "Polymorphable<",
                    options: .backwards
                ),
                spelling.last == ">"
            else {
                continue
            }
            return String(
                spelling[
                    markerRange.upperBound ..< spelling.index(before: spelling.endIndex)
                ]
            )
        }
        return nil
    }
}

/// Parse a polymorphic directory attribute.
private func parseDirectoryArguments(
    _ arguments: LabeledExprListSyntax,
    node: Syntax
) throws -> (components: [String], layer: String) {
    var directoryPathComponents: [String] = []
    var directoryLayerValue: String = ".default"

    for arg in arguments {
        // Check for "layer:" argument
        if let label = arg.label, label.text == "layer" {
            guard
                let memberAccess = arg.expression.as(
                    MemberAccessExprSyntax.self
                )
            else {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(
                        node: Syntax(arg.expression),
                        message: MacroExpansionErrorMessage(
                            "@PolymorphicDirectory layer must be a DirectoryLayer case"
                        )
                    )
                ])
            }
            directoryLayerValue = ".\(memberAccess.declName.baseName.text)"
            continue
        }

        guard
            let pathValue = staticStringLiteralValue(arg.expression),
            !pathValue.isEmpty
        else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(arg.expression),
                    message: MacroExpansionErrorMessage(
                        "@PolymorphicDirectory components must be nonempty string literals"
                    )
                )
            ])
        }
        directoryPathComponents.append(".staticPath(\"\(pathValue)\")")
    }

    guard !directoryPathComponents.isEmpty else {
        throw DiagnosticsError(diagnostics: [
            Diagnostic(
                node: node,
                message: MacroExpansionErrorMessage(
                    "@PolymorphicDirectory requires at least one path component"
                )
            )
        ])
    }
    return (directoryPathComponents, directoryLayerValue)
}

/// Compile a protocol index declaration into a logical definition.
private func parseIndexArguments(
    _ arguments: LabeledExprListSyntax,
    node: Syntax,
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

    for arg in arguments {
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
                node: node,
                message: MacroExpansionErrorMessage(
                    "@PolymorphicIndex requires an IndexDefinition case"
                )
            )
        ])
    }
    let keyPaths = try selectedIndexFieldPaths(
        definition: definition,
        roles: fieldsByRole,
        node: node
    )
    try validateIndexFieldOrders(
        definition: definition,
        roles: fieldsByRole,
        orders: fieldOrders,
        node: node
    )
    for keyPath in keyPaths + storedFieldKeyPaths {
        guard !keyPath.contains(".") else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: node,
                    message: MacroExpansionErrorMessage(
                        "Polymorphic index field '\(keyPath)' must identify one protocol property"
                    )
                )
            ])
        }
        guard protocolFieldNames.contains(keyPath) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: node,
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
        return "DatabaseKit.PolymorphicIndexField(name: \"\(fieldName)\", order: \(order))"
    }
    .joined(separator: ", ")
    let optionsInit = isUnique ? ".init(unique: true)" : ".init()"
    let storedFieldNames = storedFieldKeyPaths
        .map { "\"\($0)\"" }
        .joined(separator: ", ")
    let expression: ExprSyntax = """
        DatabaseKit.PolymorphicIndexDefinition(
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

private func staticStringLiteralValue(_ expression: ExprSyntax) -> String? {
    guard
        let literal = expression.as(StringLiteralExprSyntax.self),
        literal.segments.count == 1,
        let segment = literal.segments.first?.as(StringSegmentSyntax.self)
    else {
        return nil
    }
    return segment.content.text
}
