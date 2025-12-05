// RelationshipHelpers.swift
// CoreMacros - Helper functions for @Relationship processing in @Persistable macro
//
// These functions are used by PersistableMacro to detect and process
// @Relationship attributes. The actual @Relationship macro implementation
// is in the RelationshipMacros module.

import SwiftSyntax

// MARK: - Helper Functions

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
        // "orderIDs" → "orders"
        // Remove "IDs" suffix and add "s"
        let base = fkFieldName.replacingOccurrences(of: "IDs", with: "")
        return base + "s"
    } else {
        // "customerID" → "customer"
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
