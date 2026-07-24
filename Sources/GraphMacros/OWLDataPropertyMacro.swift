import Foundation
import DatabaseTypes
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

        guard let literal = firstArg.expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              let segment = literal.segments.first?.as(StringSegmentSyntax.self),
              !segment.content.text.contains("\\") else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg),
                    message: OWLDataPropertyMacroErrorMessage(
                        "@OWLDataProperty first argument must be a plain string literal"
                    )
                )
            ])
        }
        guard RDFIRISyntax.isValid(segment.content.text) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg),
                    message: OWLDataPropertyMacroErrorMessage(
                        "@OWLDataProperty IRI must be absolute"
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
