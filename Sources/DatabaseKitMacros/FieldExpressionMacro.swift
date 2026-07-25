import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct FieldExpressionMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: FieldExpressionDiagnostic(
                        message: "#field requires a stored-property key path"
                    )
                )
            ])
        }

        let source = argument.description.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard source.hasPrefix("\\") else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(argument),
                    message: FieldExpressionDiagnostic(
                        message: "#field requires a key path with an explicit root type"
                    )
                )
            ])
        }

        let components = source
            .dropFirst()
            .split(separator: ".", omittingEmptySubsequences: true)
        guard components.count == 2 else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(argument),
                    message: FieldExpressionDiagnostic(
                        message: "#field supports one stored property and requires an explicit root type"
                    )
                )
            ])
        }

        let root = components[0]
        let property = components[1]
        return "\(raw: root).fields.\(raw: property)"
    }
}

private struct FieldExpressionDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID = MessageID(
        domain: "DatabaseKit.FieldExpressionMacro",
        id: "invalidFieldExpression"
    )
    let severity = DiagnosticSeverity.error
}
