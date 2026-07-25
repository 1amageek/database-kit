import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Validates attributes consumed by `@Polymorphable`.
///
/// The group macro reads these attributes from the protocol declaration and
/// emits one concrete metadata declaration. Marker expansion itself emits no
/// peer declaration.
public struct PolymorphicDeclarationMarkerMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ProtocolDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "@\(node.attributeName.trimmedDescription) can only be applied to protocols"
                    )
                )
            ])
        }
        return []
    }
}
