import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// The canonical content of one `#Directory` declaration.
struct ParsedDirectoryDeclaration {
    /// `DirectoryPathComponent` case expressions in declaration order.
    let componentExpressions: [String]

    /// Dynamic field names in declaration order.
    let dynamicFieldNames: [String]

    /// The `DirectoryLayer` case expression, including its leading dot.
    let layerExpression: String
}

/// Parse the argument list of one `#Directory` declaration.
///
/// The freestanding `#Directory` macro validates the declaration and the
/// `@Persistable` macro compiles the same call from the AST. Both use this
/// parser, so a declaration one macro accepts cannot be silently reinterpreted
/// by the other. Every element that would otherwise change meaning is rejected
/// with a diagnostic instead of being dropped, defaulted, or reinterpreted.
func parseDirectoryDeclaration(
    arguments: LabeledExprListSyntax,
    rootType: String,
    node: Syntax
) throws -> ParsedDirectoryDeclaration {
    var componentExpressions: [String] = []
    var dynamicFieldNames: [String] = []
    var layerName: String?

    for argument in arguments {
        if let label = argument.label {
            guard label.text == "layer" else {
                throw directoryDeclarationDiagnostic(
                    node: Syntax(argument),
                    message: "#Directory path components must be unlabeled"
                )
            }
            guard layerName == nil else {
                throw directoryDeclarationDiagnostic(
                    node: Syntax(argument),
                    message: "#Directory accepts at most one layer argument"
                )
            }
            layerName = try directoryLayerCaseName(
                argument.expression,
                label: "#Directory"
            )
            continue
        }

        let expression = argument.expression

        if expression.is(StringLiteralExprSyntax.self) {
            guard let value = staticStringLiteralValue(expression), !value.isEmpty else {
                throw directoryDeclarationDiagnostic(
                    node: Syntax(expression),
                    message: """
                        #Directory path components must be nonempty string \
                        literals without interpolation
                        """
                )
            }
            componentExpressions.append(".staticPath(\"\(value)\")")
            continue
        }

        if let keyPath = expression.as(KeyPathExprSyntax.self) {
            let fieldName = try directoryDynamicFieldName(keyPath, rootType: rootType)
            dynamicFieldNames.append(fieldName)
            componentExpressions.append(
                ".dynamicField(fieldName: \"\(fieldName)\")"
            )
            continue
        }

        throw directoryDeclarationDiagnostic(
            node: Syntax(expression),
            message: """
                #Directory path components must be nonempty string literals or \
                stored-property key paths
                """
        )
    }

    if layerName == "partition", dynamicFieldNames.isEmpty {
        throw directoryDeclarationDiagnostic(
            node: node,
            message: """
                #Directory layer: .partition requires at least one \
                stored-property key path
                """
        )
    }

    return ParsedDirectoryDeclaration(
        componentExpressions: componentExpressions,
        dynamicFieldNames: dynamicFieldNames,
        layerExpression: ".\(layerName ?? "default")"
    )
}

/// Read a single-segment string literal written without interpolation.
func staticStringLiteralValue(_ expression: ExprSyntax) -> String? {
    guard
        let literal = expression.as(StringLiteralExprSyntax.self),
        literal.segments.count == 1,
        let segment = literal.segments.first?.as(StringSegmentSyntax.self)
    else {
        return nil
    }
    return segment.content.text
}

/// Read the `DirectoryLayer` case a `layer:` argument names.
///
/// `label` is the declaration spelling the diagnostic reports.
func directoryLayerCaseName(
    _ expression: ExprSyntax,
    label: String
) throws -> String {
    guard let memberAccess = expression.as(MemberAccessExprSyntax.self) else {
        throw directoryDeclarationDiagnostic(
            node: Syntax(expression),
            message: "\(label) layer must be a DirectoryLayer case"
        )
    }
    let name = memberAccess.declName.baseName.text
    guard admittedDirectoryLayerCases.contains(name) else {
        throw directoryDeclarationDiagnostic(
            node: Syntax(expression),
            message: """
                \(label) layer must be DirectoryLayer.default or \
                DirectoryLayer.partition
                """
        )
    }
    return name
}

/// `DirectoryLayer` is declared in this package with exactly these cases, so a
/// name outside this set can only fail inside generated code.
private let admittedDirectoryLayerCases: Set<String> = ["default", "partition"]

private func directoryDynamicFieldName(
    _ keyPath: KeyPathExprSyntax,
    rootType: String
) throws -> String {
    let properties = keyPath.components.compactMap { component -> String? in
        guard
            let property = component.component.as(KeyPathPropertyComponentSyntax.self),
            case .identifier(let name) = property.declName.baseName.tokenKind
        else {
            return nil
        }
        return name
    }
    guard properties.count == keyPath.components.count, !properties.isEmpty else {
        throw directoryDeclarationDiagnostic(
            node: Syntax(keyPath),
            message: directorySinglePropertyMessage(
                fieldPath: keyPath.trimmedDescription
            )
        )
    }
    let fieldPath = properties.joined(separator: ".")
    guard let writtenRoot = keyPath.root?.trimmedDescription,
          writtenRoot == rootType else {
        throw directoryDeclarationDiagnostic(
            node: Syntax(keyPath),
            message: """
                #Directory field '\(fieldPath)' must use a key path rooted at \
                '\(rootType)'
                """
        )
    }
    guard properties.count == 1, let fieldName = properties.first else {
        throw directoryDeclarationDiagnostic(
            node: Syntax(keyPath),
            message: directorySinglePropertyMessage(fieldPath: fieldPath)
        )
    }
    return fieldName
}

private func directorySinglePropertyMessage(fieldPath: String) -> String {
    "#Directory field '\(fieldPath)' must identify one persisted property"
}

private func directoryDeclarationDiagnostic(
    node: Syntax,
    message: String
) -> DiagnosticsError {
    DiagnosticsError(diagnostics: [
        Diagnostic(
            node: node,
            message: MacroExpansionErrorMessage(message)
        )
    ])
}
