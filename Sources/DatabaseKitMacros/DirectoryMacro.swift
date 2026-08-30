import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `#Directory` macro.
///
/// This freestanding declaration macro generates nothing. It validates the
/// Directory declaration where it is written, and the `@Persistable` macro
/// reads the same call from the AST and compiles it into
/// `directoryPathComponents` and `directoryLayer`. Both macros parse the
/// declaration with `parseDirectoryDeclaration(arguments:rootType:node:)`, so a
/// declaration accepted here is compiled with the meaning validated here.
///
/// **Path components**: each unlabeled variadic element is either
/// - a nonempty string literal without interpolation, contributing a static
///   component: `"app"`, `"tenants"`; or
/// - a key path naming one stored property of the generic type, contributing a
///   dynamic component: `\Order.accountID`.
///
/// **Layer**: `layer:` names the layer tag of the final resolved node and must
/// be a `DirectoryLayer` case:
/// - `.default` (the default): the node resolves a plain Directory;
/// - `.partition`: the node resolves a Partition, and the declaration must
///   contain at least one dynamic component.
///
/// Usage:
/// ```swift
/// @Persistable
/// struct User {
///     #Directory<User>("app", "users")
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
///     #Directory<Order>("tenants", \Order.accountID, "orders", layer: .partition)
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
///         "tenants",
///         \Message.accountID,
///         "channels",
///         \Message.channelID,
///         "messages",
///         layer: .partition
///     )
///     #PrimaryKey<Message>([\.messageID])
///
///     var messageID: Int64
///     var accountID: String  // First dynamic component
///     var channelID: String  // Second dynamic component
/// }
/// ```
///
/// **Generated code** (by the `@Persistable` macro):
/// ```swift
/// extension Order {
///     public static var directoryPathComponents: [DirectoryPathComponent] {
///         [.staticPath("tenants"), .dynamicField(fieldName: "accountID"), .staticPath("orders")]
///     }
///     public static var directoryLayer: DatabaseKit.DirectoryLayer { .partition }
/// }
/// ```
///
/// **Validation**:
/// - the generic type parameter `<T>` is required;
/// - path components must be unlabeled;
/// - a static component must be a nonempty string literal without
///   interpolation;
/// - a dynamic component must be a key path written with an explicit root
///   equal to `T` and naming exactly one property;
/// - `layer:` must be `.default` or `.partition` and may appear once;
/// - `layer: .partition` requires at least one dynamic component.
public struct DirectoryMacro: DeclarationMacro {

    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        guard let genericClause = node.genericArgumentClause,
              let genericArgument = genericClause.arguments.first else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "#Directory requires a type parameter (e.g., #Directory<User>)"
                    )
                )
            ])
        }

        _ = try parseDirectoryDeclaration(
            arguments: node.arguments,
            rootType: genericArgument.argument.trimmedDescription,
            node: Syntax(node)
        )

        // This macro does not generate any declarations. The @Persistable macro
        // reads its #Directory call directly from the AST.
        return []
    }
}
