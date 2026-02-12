import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// @OWLProperty マクロの実装（マーカーマクロ）。
///
/// `@Relationship` と同じパターンで、バリデーションのみ行い、
/// コード生成は `PersistableMacro` が担当する。
public struct OWLPropertyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLPropertyMacroErrorMessage(
                        "@OWLProperty can only be applied to variable declarations"
                    )
                )
            ])
        }

        guard varDecl.bindingSpecifier.text == "var" else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: OWLPropertyMacroErrorMessage(
                        "@OWLProperty must be applied to 'var' declarations, not 'let'"
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
                    message: OWLPropertyMacroErrorMessage(
                        "@OWLProperty requires an IRI string argument. " +
                        "Example: @OWLProperty(\"name\")"
                    )
                )
            ])
        }

        // 最初の引数が文字列リテラルであることを確認
        let firstArgExpr = firstArg.expression.description.trimmingCharacters(in: .whitespaces)
        guard firstArgExpr.hasPrefix("\"") && firstArgExpr.hasSuffix("\"") else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg),
                    message: OWLPropertyMacroErrorMessage(
                        "@OWLProperty first argument must be a string literal. " +
                        "Found: \(firstArgExpr)"
                    )
                )
            ])
        }

        return []
    }
}

/// @OWLProperty マクロのエラーメッセージ
struct OWLPropertyMacroErrorMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "GraphMacros", id: message)
        self.severity = .error
    }
}

/// コンパイラプラグインエントリポイント
@main
struct GraphMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        OWLPropertyMacro.self,
        OntologyMacro.self,
    ]
}
