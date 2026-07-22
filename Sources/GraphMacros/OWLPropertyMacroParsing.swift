// NOTE: CoreMacros/OWLPropertyMacroParsing.swift must be kept in sync with this file.

import SwiftSyntax

// MARK: - @OWLDataProperty helpers

private func plainStringLiteralValue(_ expression: ExprSyntax) -> String? {
    guard let literal = expression.as(StringLiteralExprSyntax.self),
          literal.segments.count == 1,
          let segment = literal.segments.first?.as(StringSegmentSyntax.self),
          !segment.content.text.contains("\\") else {
        return nil
    }
    return segment.content.text
}

/// Check whether a variable has an @OWLDataProperty attribute.
public func hasOWLDataPropertyAttribute(_ varDecl: VariableDeclSyntax) -> Bool {
    for attribute in varDecl.attributes {
        if let attr = attribute.as(AttributeSyntax.self),
           let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == "OWLDataProperty" {
            return true
        }
    }
    return false
}

/// Return the @OWLDataProperty attribute from a variable.
public func getOWLDataPropertyAttribute(_ varDecl: VariableDeclSyntax) -> AttributeSyntax? {
    for attribute in varDecl.attributes {
        if let attr = attribute.as(AttributeSyntax.self),
           let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == "OWLDataProperty" {
            return attr
        }
    }
    return nil
}

/// Extract metadata from an @OWLDataProperty attribute.
///
/// - Returns: (iri, label, targetTypeName, targetFieldName) tuple
///   - iri: OWL property IRI (string literal)
///   - label: Display label (optional)
///   - targetTypeName: Root type name from `to:` parameter (nil for DataProperty)
///   - targetFieldName: Field name from `to:` parameter (nil for DataProperty)
public func extractOWLDataPropertyInfo(from attribute: AttributeSyntax) -> (
    iri: String,
    label: String?,
    targetTypeName: String?,
    targetFieldName: String?
) {
    var iri = ""
    var label: String? = nil
    var targetTypeName: String? = nil
    var targetFieldName: String? = nil

    guard let arguments = attribute.arguments,
          let labeledList = arguments.as(LabeledExprListSyntax.self) else {
        return (iri, label, targetTypeName, targetFieldName)
    }

    for (index, argument) in labeledList.enumerated() {
        let argLabel = argument.label?.text

        if index == 0 && argLabel == nil {
            // First unlabeled argument = IRI string
            iri = plainStringLiteralValue(argument.expression) ?? ""
        } else if argLabel == "label" {
            label = plainStringLiteralValue(argument.expression)
        } else if argLabel == "to" {
            // Parse KeyPath expression: \Department.id → (Department, id)
            let expr = argument.expression.description
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parsed = parseKeyPathExpression(expr)
            targetTypeName = parsed.rootType
            targetFieldName = parsed.fieldName
        }
    }

    return (iri, label, targetTypeName, targetFieldName)
}

/// Extract Root type name and field name from a KeyPath expression string (`\Department.id`)
///
/// - Parameter expr: String representation of a KeyPath expression
/// - Returns: (rootType, fieldName) tuple
private func parseKeyPathExpression(_ expr: String) -> (rootType: String?, fieldName: String?) {
    var s = expr
    if s.hasPrefix("\\") {
        s = String(s.dropFirst())
    }
    guard let dotIndex = s.firstIndex(of: ".") else {
        return (nil, nil)
    }
    let rootType = String(s[s.startIndex..<dotIndex])
    let fieldName = String(s[s.index(after: dotIndex)...])
    return (rootType.isEmpty ? nil : rootType, fieldName.isEmpty ? nil : fieldName)
}

// MARK: - @OWLObjectProperty helpers

/// Check if a struct has @OWLObjectProperty attribute
public func getOWLObjectPropertyAttribute(_ decl: StructDeclSyntax) -> AttributeSyntax? {
    for attribute in decl.attributes {
        if let attr = attribute.as(AttributeSyntax.self),
           let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
           identifier.name.text == "OWLObjectProperty" {
            return attr
        }
    }
    return nil
}

/// Extract metadata from @OWLObjectProperty attribute
///
/// - Returns: (iri, fromField, toField) tuple
public func extractOWLObjectPropertyInfo(from attribute: AttributeSyntax) -> (
    iri: String,
    fromField: String,
    toField: String
) {
    var iri = ""
    var fromField = ""
    var toField = ""

    guard let arguments = attribute.arguments,
          let labeledList = arguments.as(LabeledExprListSyntax.self) else {
        return (iri, fromField, toField)
    }

    for (index, argument) in labeledList.enumerated() {
        let argLabel = argument.label?.text

        if index == 0 && argLabel == nil {
            iri = plainStringLiteralValue(argument.expression) ?? ""
        } else if argLabel == "from" {
            fromField = plainStringLiteralValue(argument.expression) ?? ""
        } else if argLabel == "to" {
            toField = plainStringLiteralValue(argument.expression) ?? ""
        }
    }

    return (iri, fromField, toField)
}
