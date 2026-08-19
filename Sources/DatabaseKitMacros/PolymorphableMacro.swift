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
///     .ordered(
///         name: "Document_title",
///         keys: [.ascending("title")]
///     )
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
        let groupIdentifier = try parseGroupIdentifier(
            from: node,
            defaultValue: protocolName
        )
        let groupIdentifierLiteral = StringLiteralExprSyntax(
            content: groupIdentifier
        )
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
                        node: Syntax(attribute)
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
                \(raw: accessPrefix)static let identifier = \(groupIdentifierLiteral)

                \(raw: accessPrefix)static let directoryComponents: [DatabaseKit.DirectoryPathComponent] = \(raw: componentsExpression)

                \(raw: accessPrefix)static let directoryLayer: DatabaseKit.DirectoryLayer = \(raw: directoryLayerValue)

                \(raw: accessPrefix)static let indexes: [DatabaseKit.IndexDeclaration<String>] = \(raw: indexesExpression)
            }
            """
        return [declaration]
    }
}

// MARK: - Helper Functions

private func parseGroupIdentifier(
    from attribute: AttributeSyntax,
    defaultValue: String
) throws -> String {
    guard
        let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
        let argument = arguments.first
    else {
        return defaultValue
    }
    guard
        argument.label?.text == "identifier",
        let identifier = staticStringLiteralValue(argument.expression),
        !identifier.isEmpty
    else {
        throw DiagnosticsError(diagnostics: [
            Diagnostic(
                node: Syntax(argument),
                message: MacroExpansionErrorMessage(
                    "@Polymorphable identifier must be a nonempty string literal"
                )
            )
        ])
    }
    return identifier
}

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
    node: Syntax
) throws -> ExprSyntax {
    guard arguments.count == 1,
          let argument = arguments.first,
          argument.label == nil else {
        throw DiagnosticsError(diagnostics: [
            Diagnostic(
                node: node,
                message: MacroExpansionErrorMessage(
                    "@PolymorphicIndex accepts exactly one unlabeled IndexDeclaration"
                )
            )
        ])
    }
    try validatePolymorphicIndexDeclaration(
        argument.expression,
        node: node
    )
    return argument.expression
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
