import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Test macro to verify if type references cause circular dependency
///
/// This is a minimal peer macro that accepts a type parameter.
/// We want to test if two structs can reference each other via this macro.
public struct ReferenceMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Just a marker macro - generates nothing
        // The type parameter is captured in the attribute for metadata
        return []
    }
}
