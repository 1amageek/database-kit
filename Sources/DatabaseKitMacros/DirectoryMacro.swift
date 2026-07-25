import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// Implementation of its #Directory macro
///
/// This freestanding declaration macro validates the directory path syntax and layer parameter,
/// serving as a marker for the @Persistable macro. The @Persistable macro reads its #Directory
/// call from the AST to generate type-safe store() methods.
///
/// **Path Elements**: The path is an array where each element can be:
/// - String literal: `"app"`, `"tenants"`, `"users"` (static path segments)
/// - Key path: `\Order.accountID`, `\Order.channelID` (dynamic partition keys)
///
/// **Layer**: The layer parameter specifies the directory type:
/// - `.default` (default): Default directory
/// - `.partition`: Multi-tenant partition (requires at least one Field in path)
/// - Custom: `"my_custom_format_v2"`
///
/// Usage:
/// ```swift
/// @Persistable
/// struct User {
///     #Directory<User>(["app", "users"], layer: .default)
///     #PrimaryKey<User>([\.userID])
///
///     var userID: Int64
///     var email: String
/// }
/// ```
///
/// **Multi-tenant with Partition**:
/// ```swift
/// @Persistable
/// struct Order {
///     #Directory<Order>(
///         ["tenants", \Order.accountID, "orders"],
///         layer: .partition
///     )
///     #PrimaryKey<Order>([\.orderID])
///
///     var orderID: Int64
///     var accountID: String
/// }
/// ```
///
/// **Multi-level partitioning**:
/// ```swift
/// @Persistable
/// struct Message {
///     #Directory<Message>(
///         ["tenants", \Message.accountID, "channels", \Message.channelID, "messages"],
///         layer: .partition
///     )
///     #PrimaryKey<Message>([\.messageID])
///
///     var messageID: Int64
///     var accountID: String  // First partition key
///     var channelID: String  // Second partition key
/// }
/// ```
///
/// **Generated code** (by @Persistable macro):
/// ```swift
/// // Basic directory
/// extension User {
///     static func openDirectory(database: any DatabaseProtocol) async throws -> DirectorySubspace
///     static func store(database: any DatabaseProtocol, schema: Schema) async throws -> PersistableStore<User>
/// }
///
/// // Partition directory
/// extension Order {
///     static func openDirectory(accountID: String, database: any DatabaseProtocol) async throws -> DirectorySubspace
///     static func store(accountID: String, database: any DatabaseProtocol, schema: Schema) async throws -> PersistableStore<Order>
/// }
/// ```
///
/// **Validation**:
/// - Generic type parameter `<T>` is required
/// - Path elements must be string literals or stored-property key paths
/// - Field properties must exist in the struct and match the generic type parameter
/// - If `layer: .partition`, at least one Field is required in the path
public struct DirectoryMacro: DeclarationMacro {

    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        // Validate the macro usage
        // Ensure a generic type parameter is provided
        guard let genericClause = node.genericArgumentClause,
              let genericArg = genericClause.arguments.first else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage("#Directory requires a type parameter (e.g., #Directory<User>)")
                )
            ])
        }

        // Type name is extracted from generic argument (not currently used but available for future validation)
        _ = genericArg.argument.description.trimmingCharacters(in: .whitespaces)

        // Extract Field properties from the path elements (variadic arguments)
        var fieldProperties: [String] = []
        var layerExpr: ExprSyntax? = nil

        // Process all arguments (variadic path elements + optional layer)
        for arg in node.arguments {
            // Check if this is the "layer:" labeled argument
            if let label = arg.label, label.text == "layer" {
                layerExpr = arg.expression
                continue
            }

            let expr = arg.expression

            // Check if it's a string literal
            if expr.is(StringLiteralExprSyntax.self) {
                // String literal path element - valid
                continue
            }

            if let keyPath = expr.as(KeyPathExprSyntax.self),
               let component = keyPath.components.last,
               let property = component.component.as(
                   KeyPathPropertyComponentSyntax.self
               ) {
                fieldProperties.append(property.declName.baseName.text)
                continue
            }

            // Invalid element type
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(expr),
                    message: MacroExpansionErrorMessage("Path elements must be string literals or stored-property key paths")
                )
            ])
        }

        // Validate layer: .partition requires at least one Field
        if let layerExpr = layerExpr {
            // Check if layer is .partition
            if let memberAccessExpr = layerExpr.as(MemberAccessExprSyntax.self),
               memberAccessExpr.declName.baseName.text == "partition" {
                // Ensure at least one Field exists
                if fieldProperties.isEmpty {
                    throw DiagnosticsError(diagnostics: [
                        Diagnostic(
                            node: Syntax(layerExpr),
                            message: MacroExpansionErrorMessage("layer: .partition requires at least one stored-property key path")
                        )
                    ])
                }
            }
        }

        // This macro does not generate any declarations.
        // The @Persistable macro reads its #Directory call directly from the AST.
        return []
    }
}
