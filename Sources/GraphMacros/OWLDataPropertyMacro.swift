import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Implementation of the `@OWLDataProperty` macro (validation-only peer macro).
///
/// Follows the same pattern as `@Relationship`: validates syntax only,
/// code generation is handled by `@OWLClass` / `@Persistable`.
public struct OWLDataPropertyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLDataPropertyMacroErrorMessage(
                        "@OWLDataProperty can only be applied to variable declarations"
                    )
                )
            ])
        }

        guard varDecl.bindingSpecifier.text == "var" else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLDataPropertyMacroErrorMessage(
                        "@OWLDataProperty must be applied to 'var' declarations, not 'let'"
                    )
                )
            ])
        }

        guard let arguments = node.arguments,
              let labeledList = arguments.as(LabeledExprListSyntax.self),
              let firstArg = labeledList.first else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLDataPropertyMacroErrorMessage(
                        "@OWLDataProperty requires an IRI string argument. " +
                        "Example: @OWLDataProperty(\"name\")"
                    )
                )
            ])
        }

        // Validate first argument is a string literal
        let firstArgExpr = firstArg.expression.description.trimmingCharacters(in: .whitespaces)
        guard firstArgExpr.hasPrefix("\"") && firstArgExpr.hasSuffix("\"") else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg),
                    message: OWLDataPropertyMacroErrorMessage(
                        "@OWLDataProperty first argument must be a string literal. " +
                        "Found: \(firstArgExpr)"
                    )
                )
            ])
        }

        return []
    }
}

/// Error message for @OWLDataProperty macro
struct OWLDataPropertyMacroErrorMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "GraphMacros", id: message)
        self.severity = .error
    }
}
