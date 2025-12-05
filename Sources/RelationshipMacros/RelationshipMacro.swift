import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// @Relationship macro implementation
///
/// This is a peer macro that marks a FK field as a relationship.
/// The actual relationship processing is done in `PersistableMacro`
/// which detects `@Relationship` attributes and generates:
/// - RelationshipDescriptor entries in `descriptors`
/// - Appropriate index descriptors
///
/// The peer macro itself validates the FK field and doesn't generate code.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Order {
///     @Relationship(Customer.self, deleteRule: .nullify)
///     var customerID: String?  // To-one FK
/// }
///
/// @Persistable
/// struct Customer {
///     @Relationship(Order.self, deleteRule: .cascade)
///     var orderIDs: [String] = []  // To-many FK array
/// }
/// ```
public struct RelationshipMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Validate that @Relationship is applied to a variable declaration
        guard let varDecl = declaration.as(VariableDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "@Relationship can only be applied to variable declarations"
                    )
                )
            ])
        }

        // Validate it's a var (not let)
        guard varDecl.bindingSpecifier.text == "var" else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "@Relationship must be applied to 'var' declarations, not 'let'"
                    )
                )
            ])
        }

        // Get the property name and type
        guard let binding = varDecl.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "@Relationship requires a type annotation"
                    )
                )
            ])
        }

        let propertyName = pattern.identifier.text
        let typeString = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)

        // Validate FK field naming convention
        let isToMany = isToManyFKField(typeString)

        if isToMany {
            // To-Many: must end with "IDs" (e.g., orderIDs: [String])
            if !propertyName.hasSuffix("IDs") {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(
                        node: Syntax(pattern),
                        message: MacroExpansionErrorMessage(
                            "@Relationship to-many FK field must end with 'IDs'. " +
                            "Rename '\(propertyName)' to '\(propertyName)IDs' or similar."
                        )
                    )
                ])
            }
            // Validate type is [String]
            if typeString != "[String]" && typeString != "Array<String>" {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(
                        node: Syntax(typeAnnotation),
                        message: MacroExpansionErrorMessage(
                            "@Relationship to-many FK field must be [String]. " +
                            "Found: \(typeString)"
                        )
                    )
                ])
            }
        } else {
            // To-One: must end with "ID" (e.g., customerID: String?)
            if !propertyName.hasSuffix("ID") {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(
                        node: Syntax(pattern),
                        message: MacroExpansionErrorMessage(
                            "@Relationship to-one FK field must end with 'ID'. " +
                            "Rename '\(propertyName)' to '\(suggestFKName(for: propertyName))' or similar."
                        )
                    )
                ])
            }
            // Validate type is String? or String
            if typeString != "String?" && typeString != "String" &&
               typeString != "Optional<String>" {
                throw DiagnosticsError(diagnostics: [
                    Diagnostic(
                        node: Syntax(typeAnnotation),
                        message: MacroExpansionErrorMessage(
                            "@Relationship to-one FK field must be String or String?. " +
                            "Found: \(typeString)"
                        )
                    )
                ])
            }
        }

        // Validate that the first argument is a type (T.self)
        guard let arguments = node.arguments,
              let labeledList = arguments.as(LabeledExprListSyntax.self),
              let firstArg = labeledList.first else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(node),
                    message: MacroExpansionErrorMessage(
                        "@Relationship requires a type argument. " +
                        "Example: @Relationship(Customer.self)"
                    )
                )
            ])
        }

        // Check if first argument is a metatype expression (T.self)
        let firstArgExpr = firstArg.expression.description.trimmingCharacters(in: .whitespaces)
        if !firstArgExpr.hasSuffix(".self") {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(
                    node: Syntax(firstArg),
                    message: MacroExpansionErrorMessage(
                        "@Relationship first argument must be a type (e.g., Customer.self). " +
                        "Found: \(firstArgExpr)"
                    )
                )
            ])
        }

        // The peer macro doesn't generate any declarations.
        // All relationship handling is done in PersistableMacro.
        return []
    }
}

// MARK: - Helper Functions

/// Suggest a FK field name for a given property name
private func suggestFKName(for name: String) -> String {
    if name.first?.isUppercase == true {
        return name.lowercased() + "ID"
    }
    return name + "ID"
}

/// Check if a type string represents a to-many FK field ([String])
public func isToManyFKField(_ typeString: String) -> Bool {
    let trimmed = typeString.trimmingCharacters(in: .whitespaces)
    return trimmed == "[String]" || trimmed == "Array<String>"
}

/// Check if a type string represents a to-one FK field (String or String?)
public func isToOneFKField(_ typeString: String) -> Bool {
    let trimmed = typeString.trimmingCharacters(in: .whitespaces)
    return trimmed == "String" || trimmed == "String?" || trimmed == "Optional<String>"
}

/// Extract relationship information from an attribute
///
/// Returns (relatedTypeName, deleteRule) tuple
public func extractRelationshipInfo(from attribute: AttributeSyntax) -> (relatedTypeName: String, deleteRule: String) {
    var relatedTypeName = ""
    var deleteRule = ".nullify"  // Default

    guard let arguments = attribute.arguments,
          let labeledList = arguments.as(LabeledExprListSyntax.self) else {
        return (relatedTypeName, deleteRule)
    }

    for (index, argument) in labeledList.enumerated() {
        let label = argument.label?.text

        if index == 0 && label == nil {
            // First unlabeled argument is the type (e.g., Customer.self)
            let expr = argument.expression.description.trimmingCharacters(in: .whitespaces)
            // Remove ".self" suffix to get the type name
            if expr.hasSuffix(".self") {
                relatedTypeName = String(expr.dropLast(".self".count))
            } else {
                relatedTypeName = expr
            }
        } else if label == "deleteRule" {
            // Extract delete rule (e.g., .cascade, .nullify)
            deleteRule = argument.expression.description.trimmingCharacters(in: .whitespaces)
        }
    }

    return (relatedTypeName, deleteRule)
}

/// Derive relationship property name from FK field name
///
/// - `"customerID"` → `"customer"`
/// - `"orderIDs"` → `"orders"`
public func deriveRelationshipPropertyName(from fkFieldName: String, isToMany: Bool) -> String {
    if isToMany {
        let base = fkFieldName.replacingOccurrences(of: "IDs", with: "")
        return base + "s"
    } else {
        return fkFieldName.replacingOccurrences(of: "ID", with: "")
    }
}

/// Check if a variable declaration has a @Relationship attribute
public func hasRelationshipAttribute(_ varDecl: VariableDeclSyntax) -> Bool {
    for attribute in varDecl.attributes {
        if let attr = attribute.as(AttributeSyntax.self),
           let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == "Relationship" {
            return true
        }
    }
    return false
}

/// Get the @Relationship attribute from a variable declaration
public func getRelationshipAttribute(_ varDecl: VariableDeclSyntax) -> AttributeSyntax? {
    for attribute in varDecl.attributes {
        if let attr = attribute.as(AttributeSyntax.self),
           let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == "Relationship" {
            return attr
        }
    }
    return nil
}

/// Error message helper
struct MacroExpansionErrorMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String) {
        self.message = message
        self.diagnosticID = MessageID(domain: "RelationshipMacros", id: message)
        self.severity = .error
    }
}

/// Compiler plugin entry point
@main
struct RelationshipMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        RelationshipMacro.self,
    ]
}
