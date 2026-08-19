import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

func validateIndexDeclarationExpression(
    _ expression: ExprSyntax,
    node: Syntax
) throws {
    guard let call = expression.as(FunctionCallExprSyntax.self),
          call.calledExpression.as(MemberAccessExprSyntax.self) != nil
    else {
        throw indexDeclarationDiagnostic(
            node: node,
            message: "#Index requires one IndexDeclaration factory expression"
        )
    }
    guard let nameArgument = call.arguments.first(where: {
        $0.label?.text == "name"
    }),
    let name = indexPlainStringLiteral(nameArgument.expression),
    !name.isEmpty else {
        throw indexDeclarationDiagnostic(
            node: node,
            message: "Index name must be an explicit nonempty string literal"
        )
    }
}

func compileConcreteIndexDeclaration(
    _ expression: ExprSyntax,
    rootType: String,
    node: Syntax
) throws -> ExprSyntax {
    try validateIndexDeclarationExpression(expression, node: node)
    let collector = KeyPathCollector(viewMode: .sourceAccurate)
    collector.walk(expression)
    for keyPath in collector.keyPaths {
        guard keyPath.rootType == rootType else {
            throw indexDeclarationDiagnostic(
                node: node,
                message: "Index field '\(keyPath.fieldPath)' must use a key path rooted at '\(rootType)'"
            )
        }
    }
    for fieldPath in collector.fieldPaths {
        guard !fieldPath.contains(".") else {
            throw indexDeclarationDiagnostic(
                node: node,
                message: "Index field '\(fieldPath)' must identify one persisted property"
            )
        }
    }
    return IndexKeyPathRewriter(rootType: rootType).rewrite(expression)
}

func validatePolymorphicIndexDeclaration(
    _ expression: ExprSyntax,
    node: Syntax
) throws {
    try validateIndexDeclarationExpression(expression, node: node)
}

private final class IndexKeyPathRewriter: SyntaxRewriter {
    private let rootType: String

    init(rootType: String) {
        self.rootType = rootType
        super.init(viewMode: .sourceAccurate)
    }

    func rewrite(_ expression: ExprSyntax) -> ExprSyntax {
        visit(expression)
    }

    override func visit(_ node: KeyPathExprSyntax) -> ExprSyntax {
        let path = node.components.compactMap { component in
            component.component
                .as(KeyPathPropertyComponentSyntax.self)?
                .declName
                .baseName
                .text
        }
        .joined(separator: ".")
        return ExprSyntax(
            stringLiteral: "\(rootType).fields.\(path).identity"
        )
    }
}

private func indexPlainStringLiteral(_ expression: ExprSyntax) -> String? {
    guard let literal = expression.as(StringLiteralExprSyntax.self),
          literal.segments.count == 1,
          let segment = literal.segments.first?.as(StringSegmentSyntax.self)
    else {
        return nil
    }
    return segment.content.text
}

private func indexDeclarationDiagnostic(
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
